/**
 * HTTP Server service using Shelf and Shelf Router
 * Handles incoming HTTP requests for order management and KDS communication
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart' show ZipDecoder;
import 'package:crypto/crypto.dart' show md5;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;
import '../data/database/app_database.dart';
import '../domain/models/component_rules.dart';
import '../domain/models/line_payment.dart';
import '../domain/models/order_course.dart';
import '../domain/models/order_money.dart';
import '../domain/models/order_money_rows.dart';
import '../domain/models/socket_models.dart';
import '../domain/models/table_occupancy.dart' show orderBlocksTable;
import '../providers/database_providers.dart';
import '../providers/order_provider.dart'
    show OrderRepository, orderRepositoryProvider;
import '../providers/settings_provider.dart' show settingsProvider;
import '../providers/network_provider.dart' show lastKnownOnlineStatusProvider;
import '../providers/sync_manager_provider.dart' show syncManagerProvider;
import 'activity_log_service.dart' show activityLogServiceProvider;
import 'order_log_service.dart';
import 'discovery_service.dart' show DiscoveryService;
import 'lan_notification_hub.dart';
import 'waiter_call_service.dart' show waiterCallServiceProvider;
import 'kds_feed_scope.dart';
import 'kds_live_service.dart';
import '../presentation/widgets/settings_lock_dialog.dart'
    show settingsCodeAccepted;
import 'waiter_kitchen_events.dart';
import 'waiter_order_money.dart';
import 'waiter_live_updates.dart';
import 'waiter_notification_inbox.dart';
import 'waiter_request_replay.dart';
import 'line_cancellation.dart';
import 'printing_service.dart' show PrintOutput, KdsPrintMode;
import 'package:drift/drift.dart' as drift;
import '../utils/pos_log.dart';
import 'package:loggecrea/loggecrea.dart';
import 'product_cost_resolver.dart';
import 'z_day_resolver.dart';
import 'pos_notifications.dart';
import 'kitchen_timing.dart'
    show kdsCourseLines, kitchenDoneAt, kitchenSince, kitchenStageStamps;

/// Thrown inside a DB transaction to abort it (rolling back all writes) and
/// surface a specific HTTP error to the client. Lets a race-safe check *inside*
/// a transaction (e.g. table occupancy) reject cleanly without leaving a
/// half-written order behind. Caught by the endpoint and turned into a JSON
/// `{error, message}` response with [status].
class _WaiterConflict implements Exception {
  final int status;
  final String code;
  final String message;

  /// The order already sitting on the table, when there is one. Sent back so
  /// the tablet can offer to open it rather than leaving the waiter with an
  /// error and no way forward.
  final String? orderCode;

  /// Extra fields for the response body (which product, option or group).
  final Map<String, Object?> details;

  const _WaiterConflict(this.status, this.code, this.message,
      {this.orderCode, this.details = const {}});

  Response toResponse() => Response(
        status,
        body: jsonEncode({
          'error': code,
          'message': message,
          if (orderCode != null) 'orderCode': orderCode,
          ...details,
        }),
        headers: {'Content-Type': 'application/json'},
      );
}

/// One option row to store on a waiter line, priced by the till.
typedef _PricedOption = ({
  int componentId,
  int quantity,
  double price,
  String? name,
});

class ServerService {
  final Ref _ref;
  HttpServer? _server;
  int _port;
  String? _serverPassword;
  bool _isRunning = false;

  // Embedded KDS web bundle: extracted once from assets/kds_web.zip to a temp
  // dir, then served as static files. `_kdsExtraction` dedupes concurrent
  // first-hits (a browser fires many parallel requests on load).
  String? _kdsWebDir;
  Future<String?>? _kdsExtraction;

  /// Kitchen tickets waiting for the waiter to finish adding, keyed by order.
  /// See [_fireKdsForWaiterAddedProduct] and [AppSettings.waiterKdsBatchSeconds].
  final Map<int, Timer> _pendingWaiterKds = {};

  /// Failed `/kds-api/settings-code` guesses per address.
  final AttemptLimiter _settingsCodeAttempts = AttemptLimiter();

  /// Stored answers for retried / double-tapped waiter writes.
  final WaiterRequestReplay _waiterReplay = WaiterRequestReplay();

  ServerService(this._ref, {int port = 8080}) : _port = port;

  /// Start the HTTP server
  Future<void> start({int? port, String? password}) async {
    if (_isRunning) {
      Logger.instance.warning('Server already running on port $_port');
      return;
    }

    if (port != null) _port = port;
    _serverPassword = password;

    final router = _buildRouter();
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_authMiddleware())
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
      _isRunning = true;
      _ref.read(waiterLiveUpdateServiceProvider).start();
      _ref.read(kdsChangeSignalProvider).start();
      // The server binds to 0.0.0.0 (all interfaces); log the REACHABLE LAN URL
      // instead of 0.0.0.0 so the console shows what a KDS/waiter should connect
      // to.
      final lanIp = await DiscoveryService.getLocalIp();
      posLog('✅ Server started on http://$lanIp:${_server!.port} '
          '(bound to ${_server!.address.host}:${_server!.port})');
    } catch (e) {
      Logger.instance.error('Failed to start server: $e');
      rethrow;
    }
  }

  /// Stop the HTTP server
  Future<void> stop() async {
    // Anything still waiting for "one more item" goes to the kitchen NOW.
    // A ticket sitting in a timer when the POS closes is food nobody cooks.
    await _flushPendingWaiterKds();
    await _ref.read(waiterLiveUpdateServiceProvider).stop();
    await _ref.read(kdsChangeSignalProvider).stop();
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _isRunning = false;
      posLog('🛑 Server stopped');
    }
  }

  /// Build the router with all endpoints
  Router _buildRouter() {
    final router = Router();

    // Health check
    router.get('/health', _healthCheck);

    // Order endpoints
    router.get('/orders', _getOrders);
    // Kitchen screens: a push nudge instead of polling every 2 s.
    router.post('/orders/events/ticket', _kdsEventsTicket);
    router.get('/orders/events', _kdsEvents);
    // A kitchen screen set to "use the till's PIN" for its settings lock.
    router.post('/kds-api/settings-code', _kdsSettingsCode);
    router.post('/orders', _createOrder);
    router.put('/orders/<orderId>', _updateOrder);
    router.put('/orders/products/<id>', _updateOrderProduct);
    router.get('/stations', _getStations);

    // Embedded KDS web app — the pre-built Flutter web bundle, served straight
    // from the LAN server so any browser/TV on the network can open the board
    // at http://<pos-ip>:<port>/kds (no install). Its API calls hit /orders on
    // this same origin. Exempt from the password in _authMiddleware.
    router.get('/kds', (Request r) => _serveKdsWeb(''));
    router.get('/kds/', (Request r) => _serveKdsWeb(''));
    router.get('/kds/<path|.*>', (Request r, String path) => _serveKdsWeb(path));

    // Waiter-specific endpoints
    router.get('/waiters/profiles', _waiterProfiles);
    router.post('/waiters/login', _waiterLogin);
    router.get('/waiters/dashboard', _waiterDashboard);
    router.get('/waiters/products', _waiterProducts);
    router.get('/waiters/categories', _waiterCategories);
    router.get('/waiters/components', _waiterComponents);
    router.get('/waiters/component-groups', _waiterComponentGroups);
    router.get('/waiters/product-components', _waiterProductComponents);
    router.get('/waiters/product-component-groups', _waiterProductComponentGroups);
    router.get('/waiters/product-variants', _waiterProductVariants);
    router.get('/waiters/tables', _waiterTables);
    router.get('/waiters/orders', _waiterOrders);
    router.get('/waiters/orders/<code>', _waiterOrderDetail);
    // The three routes that add food are replay-safe: a retried round that
    // carries the same requestId is answered, not applied twice. See
    // [WaiterRequestReplay].
    router.post('/waiters/orders',
        (Request r) => _waiterReplay.run(r, 'create', _waiterCreateOrder));
    router.put(
        '/waiters/orders/<code>/add-product',
        (Request r, String code) => _waiterReplay.run(r, 'add-product:$code',
            (req) => _waiterAddProductToOrder(req, code)));
    router.put(
        '/waiters/orders/<code>/add-products',
        (Request r, String code) => _waiterReplay.run(
            r, 'add-products:$code', (req) => _waiterAddProductsToOrder(req, code)));
    router.post('/waiters/orders/<code>/print', _waiterPrintOrder);
    router.post('/waiters/orders/<code>/cancel', _waiterCancelOrder);
    router.post('/waiters/orders/<code>/transfer-table', _waiterTransferTable);
    router.delete('/waiters/orders/<code>/products/<opId>', _waiterRemoveProduct);
    router.post('/waiters/tables/<tableId>/clear', _waiterClearTable);

    // Push channel: the waiter app holds this open for the whole shift.
    router.get('/waiters/events', _waiterEvents);
    router.post('/waiters/calls/<callId>/ack', _waiterAckCall);
    // In-memory history of what was pushed — gone on a POS restart.
    router.get('/waiters/notifications', _waiterNotifications);
    router.post('/waiters/notifications/read', _waiterNotificationsRead);

    // Catch-all for 404
    router.all('/<ignored|.*>', _notFound);

    return router;
  }

  /// CORS Middleware
  Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }

        final response = await innerHandler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  /// Authentication Middleware
  Middleware _authMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        // Skip auth for the health check and the embedded KDS web bundle
        // (a browser can't attach the password header to static asset loads;
        // the KDS's own API calls still carry it).
        final p = request.url.path;
        if (p == 'health' || p == 'kds' || p.startsWith('kds/')) {
          return innerHandler(request);
        }
        // The KDS event stream: a browser's EventSource cannot send the
        // password header, so the handler checks the header OR a one-time
        // ticket fetched with it.
        if (p == 'orders/events' && request.method == 'GET') {
          return innerHandler(request);
        }

        // Tenant / business / terminal deactivated: the waiter app may not
        // keep selling through this till. The KDS keeps working so the
        // kitchen can finish what is already ordered.
        if ((p.startsWith('waiters/') ||
                (p == 'orders' && request.method == 'POST')) &&
            _ref.read(apiServiceProvider).isAccountBlocked) {
          return Response(423,
              body: jsonEncode({
                'error': 'ACCOUNT_DISABLED',
                'code': 'ACCOUNT_DISABLED',
                'message': 'This till is deactivated.',
              }),
              headers: {'Content-Type': 'application/json', ..._corsHeaders});
        }

        // Check password if configured
        if (_serverPassword != null && _serverPassword!.isNotEmpty) {
          final authHeader = request.headers['x-server-password'];
          if (authHeader != _serverPassword) {
            return Response.forbidden(
              jsonEncode({'error': 'Invalid or missing server password'}),
              headers: {'Content-Type': 'application/json'},
            );
          }
        }

        return innerHandler(request);
      };
    };
  }

  Map<String, String> get _corsHeaders => {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers':
            'Origin, Content-Type, Accept, X-Server-Password, Last-Event-ID, Idempotency-Key, X-KDS-Name, X-KDS-Stations, X-KDS-Version',
      };

  // ==================== ENDPOINT HANDLERS ====================

  /// Health check endpoint
  /// GET /health — liveness, plus the handful of terminal-wide switches a
  /// LAN client needs before (and during) a session.
  ///
  /// [coursesEnabled] rides here rather than on a catalogue or dashboard
  /// endpoint at the waiter app's request, and the reasoning is sound: this is
  /// the only route they call BEFORE login (their connect screen probes it)
  /// and they re-poll it every 15s for the reconnect banner, so a cashier
  /// toggling courses mid-shift reaches every waiter within 15s without a
  /// restart or a re-login. It is also exempt from the server password, so it
  /// is readable in exactly the state where a client can talk to us at all.
  /// The catalogue routes are cached for a whole session by design, so a
  /// toggle would not have propagated until the next login.
  ///
  /// Always present, never null: their parse treats an absent field as false,
  /// which is the right degradation for an older POS build but a confusing
  /// one to debug if we started omitting it on purpose.
  Map<String, bool> _waiterKitchenSwitches() {
    final s = _ref.read(settingsProvider);
    return {
      // Not a setting: this build sends `order-updated` / `tables-changed`,
      // so the app keeps its stream open whatever else is switched on.
      'waiterLiveUpdates': true,
      // Not a setting either: create / add-product / add-products honour a
      // `requestId` (see [WaiterRequestReplay]), so a client may retry a send
      // whose reply it never got without the round landing twice.
      'idempotentWrites': true,
      'waiterShowKitchenStatus': s.waiterShowKitchenStatus,
      'waiterNotifyReady': s.waiterNotifyReady,
      'waiterNotifyCanceled': s.waiterNotifyCanceled,
      'waiterNotifyRupture': s.waiterNotifyRupture,
    };
  }

  Future<Response> _healthCheck(Request request) async {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'timestamp': DateTime.now().toIso8601String(),
        'port': _port,
        'coursesEnabled': _ref.read(settingsProvider).coursesEnabled,
        // Lets a client show or hide its own call-related UI, and makes a
        // "nothing rings" report answerable from one curl.
        'waiterCallsEnabled': _ref.read(settingsProvider).waiterCallEnabled,
        // Kitchen feedback switches. The app gates its status chips on the
        // first; the notify ones are informational (the POS only sends those
        // events when they're on) but let the app explain a silent phone.
        ..._waiterKitchenSwitches(),
        // Opaque to the client: compare it with the last one seen and re-fetch
        // the catalogue when it differs. See [_catalogVersion].
        'catalogVersion': await _catalogVersion(),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// Drops the products a hidden category would have leaked.
  ///
  /// The waiter app's search filters by name across every product it holds and
  /// never consults the category list, so scoping only the category route would
  /// enforce the scope in the grid and bypass it in the search box beside it.
  /// Filtering here means the tablet receives a smaller menu and needs no
  /// notion of scope at all.
  ///
  /// The filter itself is the one the till's own grid uses — one function, not
  /// a second copy that can drift away from it.
  List<Product> _scopeProducts(List<Product> products) =>
      scopedProducts(products, _ref.read(categoryScopeProvider));

  /// A fingerprint of everything a waiter's menu depends on, for clients that
  /// cache the catalogue: when this changes, their copy is stale.
  ///
  /// DERIVED, never incremented. A counter is only correct while every writer
  /// remembers to bump it, and the first one that forgets leaves tablets
  /// confidently stale. A hash moves for any change — scope edit, price, a new
  /// product, a sync delta — including the ones nobody thought about here.
  ///
  /// It hashes rather than taking `max(updatedAt)` because 86'ing a product
  /// writes `isAvailable` alone and never touches the timestamp, so a
  /// timestamp-based version would sit still while tablets kept offering an
  /// item the kitchen just killed.
  ///
  /// Briefly memoised: `/health` is polled every 15 s by every connected
  /// tablet, and this reads both tables in full.
  Future<String> _catalogVersion() async {
    final cached = _catalogVersionCache;
    final at = _catalogVersionAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < const Duration(seconds: 3)) {
      return cached;
    }

    final database = _ref.read(databaseProvider);
    final categories = scopedCategories(
        await (database.select(database.categories)
              ..where((c) => c.isActive.equals(true)))
            .get(),
        _ref.read(categoryScopeProvider));
    final products = _scopeProducts(await (database.select(database.products)
          ..where((p) => p.isActive.equals(true))
          ..orderBy([(p) => drift.OrderingTerm(expression: p.id)]))
        .get());

    final buf = StringBuffer();
    for (final c in categories) {
      buf
        ..write(c.id)
        ..write('')
        ..write(c.name)
        ..write('')
        ..write(c.displayOrder)
        ..write('')
        ..write(c.color)
        ..write('');
    }
    buf.write('');
    for (final p in products) {
      buf
        ..write(p.id)
        ..write('')
        ..write(p.name)
        ..write('')
        ..write(p.price)
        ..write('')
        ..write(p.finalPrice)
        ..write('')
        ..write(p.categoryId)
        ..write('')
        ..write(p.stationId)
        ..write('')
        ..write(p.isAvailable)
        ..write('');
    }

    final version =
        md5.convert(utf8.encode(buf.toString())).toString().substring(0, 16);
    _catalogVersionCache = version;
    _catalogVersionAt = DateTime.now();
    return version;
  }

  String? _catalogVersionCache;
  DateTime? _catalogVersionAt;



  /// GET /orders/?since=date&from_date=date&to_date=date&updated_after_log_id=int
  ///                &station=string&status=csv&after_id=int
  ///
  /// Date params (any combination accepted; `from_date` is an alias for `since`):
  ///   - `since` / `from_date` — lower bound (inclusive).  Default: start of today.
  ///   - `to_date`             — upper bound (inclusive).  Default: no upper bound.
  ///
  /// Filter priority:
  ///   1. Date window (`since`/`from_date`/`to_date`) — the primary scope.
  ///   2. `updated_after_log_id` — incremental cursor; constrained by date window.
  ///   3. `station` — pre-filtered at DB level (no noisy post-fetch skips).
  ///
  /// Returns: orders (new), orders_updated (updated), orders_deleted (IDs),
  ///          last_log_id (opaque cursor for next poll).
  /// GET /orders/ — KDS polling endpoint.
  ///
  /// Date window is ALWAYS the primary scope (defaults to start-of-today).
  /// `updated_after_log_id` is a secondary cursor that narrows WITHIN that window;
  /// it never widens the scope beyond the date bounds.
  Future<Response> _getOrders(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final q = request.url.queryParameters;
      _noteKdsRequest(request);
      // Read before any query: a write while this request runs moves it on,
      // so the screen's next poll does the full work.
      final feedVersion = _ref.read(kdsChangeSignalProvider).version;

      // ── 1. Parse params ─────────────────────────────────────────────────
      final afterId = int.tryParse(q['after_id'] ?? '');
      final statusStr = q['status'];
      // `station` accepts a CSV of names so one KDS can cover several stations
      // (the "printer covers these stations" model). Lower-cased for matching.
      final stationParam = q['station'];
      final stationNames = stationParam != null
          ? stationParam
              .split(',')
              .map((s) => s.trim().toLowerCase())
              .where((s) => s.isNotEmpty)
              .toList()
          : <String>[];

      // Printer-style options (order types / sources, unassigned, linked).
      final feedFilter = KdsFeedFilter.fromQuery(q);

      // Status: ONHOLD never reaches KDS
      final List<String> status = statusStr != null
          ? statusStr.split(',').map((s) => s.trim().toUpperCase()).toList()
          : [];
      status.removeWhere((s) => s == 'ONHOLD');

      // Scope: default to the CURRENT SESSION (LAN KDS shows the open shift).
      // Any date param (since/from_date/to_date) OVERRIDES to a date window
      // (history / reprints). `since` is the log-cursor lower bound; in session
      // mode it's set to the session's start below, with `sessionScopeId` doing
      // the real scoping in applyFilters.
      final hasDateOverride = q['since'] != null ||
          q['from_date'] != null ||
          q['to_date'] != null;
      late DateTime since;
      if (q['since'] != null || q['from_date'] != null) {
        try {
          since = DateTime.parse(q['since'] ?? q['from_date']!);
        } catch (_) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Invalid date format for "since"/"from_date"'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      } else if (hasDateOverride) {
        // Only `to_date` given → lower bound is start of today.
        final now = DateTime.now();
        since = DateTime(now.year, now.month, now.day);
      }
      // else: session mode — `since` is assigned from the session below.

      // Upper-bound date (optional)
      DateTime? toDate;
      if (q['to_date'] != null) {
        try {
          toDate = DateTime.parse(q['to_date']!);
        } catch (_) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Invalid date format for "to_date"'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // Log cursor (optional — secondary, always scoped to date window)
      int? updatedAfterLogId;
      if (q['updated_after_log_id'] != null) {
        updatedAfterLogId = int.tryParse(q['updated_after_log_id']!);
        if (updatedAfterLogId == null) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Invalid integer for "updated_after_log_id"'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // ── 2. Resolve station → set of order IDs ───────────────────────────
      Future<Response> emptyResponse({String? version}) async {
        final lastLogId = await logService.getLastUpdateLogId();
        return Response.ok(
          jsonEncode({
            'orders': [], 'orders_updated': [], 'orders_deleted': [],
            'last_log_id': lastLogId, 'count': 0, 'updated_count': 0, 'deleted_count': 0,
            'version': version ?? feedVersion,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Nothing the board is built from was written since this screen's
      // last answer: skip the scope queries (the station join grows with the
      // shift). Only for an incremental poll (both cursors), and the version
      // rolls over every 30 s, so a write the change feed cannot see still
      // shows up as fast as the screen's safety poll.
      if (afterId != null &&
          updatedAfterLogId != null &&
          q['known_version'] == feedVersion) {
        return emptyResponse(version: feedVersion);
      }

      // Session scope (default). Resolved here so emptyResponse is in scope.
      // No open shift → nothing to cook; return empty rather than all history.
      int? sessionScopeId;
      if (!hasDateOverride) {
        final session = _ref.read(currentSessionProvider);
        if (session == null) return emptyResponse();
        sessionScopeId = session.id;
        since = session.startedAt; // loose lower bound; sessionId does real scoping
      }

      // Orders are born COMPLETED (see AppSettings.defaultOrderStatus); the
      // KITCHEN state lives on each PRODUCT, not on order.status. So the KDS is
      // selected by product state — never by order.status, which reads COMPLETED
      // for every kitchen order.
      //
      //   orderIdsForStation → every order with a product for this KDS's
      //     stations (the KEEP scope: updates + reconcile).
      //   activeOrderIds     → orders with a product in one of the requested
      //     states (e.g. PENDING/PREPARING) (the ADD scope: new tickets).
      //   stationFilters     → resolved lower-cased station names, passed to
      //     _buildSocketOrder so each order's line items are filtered to this
      //     KDS's stations (a line is kept if it belongs to ANY of them).
      Set<int>? orderIdsForStation;
      Set<int>? activeOrderIds;
      Set<String>? stationFilters;

      if (stationNames.isNotEmpty || status.isNotEmpty) {
        final joinQuery = database.select(database.orderProducts).join([
          drift.innerJoin(
            database.products,
            database.products.id.equalsExp(database.orderProducts.productId),
          ),
        ]);

        if (stationNames.isNotEmpty) {
          final stations = await (database.select(database.stations)
                ..where((tbl) => tbl.name.lower().isIn(stationNames)))
              .get();
          if (stations.isEmpty) return emptyResponse();

          final stationIds = stations.map((s) => s.id).toList();
          stationFilters = stations.map((s) => s.name.toLowerCase()).toSet();

          // A product belongs to a station via its primary stationId OR via the
          // product_stations join table (multi-station products).
          final extraStationProductIds = database.selectOnly(database.productStations)
            ..addColumns([database.productStations.productId])
            ..where(database.productStations.stationId.isIn(stationIds));

          var inScope = database.products.stationId.isIn(stationIds) |
              database.products.id.isInQuery(extraStationProductIds);

          // Stationless products: no primary station and no join-table row.
          if (feedFilter.unassigned) {
            final anyStationProductIds = database.selectOnly(database.productStations)
              ..addColumns([database.productStations.productId]);
            inScope = inScope |
                (database.products.stationId.isNull() &
                    database.products.id.isNotInQuery(anyStationProductIds));
          }

          // Lines carrying an option that IS a product routed here (the drink
          // inside a menu, for the bar). The parent line's state stands in for
          // the option's when picking new tickets.
          if (feedFilter.linked) {
            final linkedComponentIds = await linkedComponentIdsForStations(
                database, stationIds.toSet());
            if (linkedComponentIds.isNotEmpty) {
              final linkedLineIds = database.selectOnly(database.orderProductComponents)
                ..addColumns([database.orderProductComponents.orderProductId])
                ..where(database.orderProductComponents.componentId
                    .isIn(linkedComponentIds));
              inScope = inScope |
                  database.orderProducts.id.isInQuery(linkedLineIds);
            }
          }

          joinQuery.where(inScope);
        }

        final rows = await joinQuery.get();

        if (stationNames.isNotEmpty) {
          orderIdsForStation =
              rows.map((r) => r.readTable(database.orderProducts).orderId).toSet();
          if (orderIdsForStation.isEmpty) return emptyResponse();
        }

        if (status.isNotEmpty) {
          activeOrderIds = rows
              .where((r) => status.contains(r.readTable(database.orderProducts).state))
              .map((r) => r.readTable(database.orderProducts).orderId)
              .toSet();
        }
      }

      // ADD scope for new tickets: the product-state set when a status filter is
      // present (initial fetch), else the full station scope (incremental /
      // reconcile polls carry no status).
      final Set<int>? newOrderScope =
          status.isNotEmpty ? activeOrderIds : orderIdsForStation;

      // ── Helper: apply shared filters to a select statement ───────────────
      // The KEEP scope (date/session, station, exclude held ONHOLD). Kitchen
      // state is NOT matched here — it lives on products, and order.status reads
      // COMPLETED for every kitchen order. The product-state ADD scope is applied
      // to new orders only (see below), preserving the original "adding applies
      // the live filter, reconcile only removes" contract.
      void applyFilters(drift.SimpleSelectStatement<$OrdersTable, Order> sel) {
        sel..where((o) => o.createdAt.isBiggerOrEqualValue(since));
        if (toDate != null) sel..where((o) => o.createdAt.isSmallerOrEqualValue(toDate!));
        if (sessionScopeId != null) {
          sel..where((o) => o.sessionId.equals(sessionScopeId!));
        }
        // Held (cart) orders never reach the KDS.
        sel..where((o) => o.status.equals('ONHOLD').not());
        if (orderIdsForStation != null) {
          sel..where((o) => o.id.isIn(orderIdsForStation!.toList()));
        }
      }

      // ── 3. New orders (created within date window) ───────────────────────
      final newOrdersQuery = database.select(database.orders);
      applyFilters(newOrdersQuery);
      // ADD scope: only surface a new ticket when it has a product in one of the
      // requested kitchen states for this station (empty set ⇒ nothing new).
      if (newOrderScope != null) {
        newOrdersQuery..where((o) => o.id.isIn(newOrderScope.toList()));
      }
      if (afterId != null) {
        newOrdersQuery..where((o) => o.id.isBiggerThanValue(afterId));
      }
      final newOrders = (await newOrdersQuery.get())
          .where(feedFilter.allowsOrder)
          .toList();

      // ── 4. Updated orders — date PRIMARY, log cursor secondary ───────────
      // Log cursor always constrained by the date window (never widens scope).
      final updatedOrderIds = updatedAfterLogId != null
          ? await logService.getUpdatedOrdersSinceLogIdAndDate(updatedAfterLogId, since)
          : await logService.getUpdatedOrdersSinceDate(since);

      // Batch fetch — single query instead of N+1
      List<Order> updatedOrders = [];
      if (updatedOrderIds.isNotEmpty) {
        final updatedQuery = database.select(database.orders)
          ..where((o) => o.id.isIn(updatedOrderIds));
        applyFilters(updatedQuery);
        updatedOrders = (await updatedQuery.get())
            .where(feedFilter.allowsOrder)
            .toList();
      }

      // ── 5. Deleted order IDs — same date-primary pattern ─────────────────
      final deletedOrderIds = updatedAfterLogId != null
          ? await logService.getDeletedOrdersSinceLogIdAndDate(updatedAfterLogId, since)
          : await logService.getDeletedOrdersSinceDate(since);

      // ── 6. Build socket models + respond ────────────────────────────────
      final [socketNewRaw, socketUpdatedRaw, lastLogIdRaw] = await Future.wait([
        Future.wait(newOrders
            .map((o) => _buildSocketOrder(o, stationFilters, feedFilter))),
        Future.wait(updatedOrders
            .map((o) => _buildSocketOrder(o, stationFilters, feedFilter))),
        logService.getLastUpdateLogId(),
      ]);

      final socketNew = (socketNewRaw as List).whereType<SocketOrderModel>().toList();
      final socketUpdated = (socketUpdatedRaw as List).whereType<SocketOrderModel>().toList();
      final lastLogId = lastLogIdRaw as int;

      return Response.ok(
        jsonEncode({
          'orders': socketNew.map((o) => o.toJson()).toList(),
          'orders_updated': socketUpdated.map((o) => o.toJson()).toList(),
          'orders_deleted': deletedOrderIds,
          'last_log_id': lastLogId,
          'count': socketNew.length,
          'updated_count': socketUpdated.length,
          'deleted_count': deletedOrderIds.length,
          'version': feedVersion,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _getOrders: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Records which kitchen screen is asking (`X-KDS-Name`, `X-KDS-Stations`,
  /// `X-KDS-Version`), for the devices screen. Old screens send none.
  void _noteKdsRequest(Request request) {
    final name = request.headers['x-kds-name'];
    if (name == null || name.trim().isEmpty) return;
    _ref.read(kdsPresenceProvider).seen(
          name,
          stations: parseKdsStations(request.headers['x-kds-stations']),
          version: request.headers['x-kds-version'],
          address: _remoteAddress(request),
        );
  }

  static String? _remoteAddress(Request request) {
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : null;
  }

  /// POST /orders/events/ticket — a one-time ticket to open
  /// `GET /orders/events` with. Behind the normal password check.
  Future<Response> _kdsEventsTicket(Request request) async {
    _noteKdsRequest(request);
    final ticket = _ref.read(kdsStreamTicketsProvider).issue();
    return Response.ok(
      jsonEncode({
        'ticket': ticket,
        'expiresInSeconds':
            _ref.read(kdsStreamTicketsProvider).ttl.inSeconds,
      }),
      headers: {'Content-Type': 'application/json', 'Cache-Control': 'no-store'},
    );
  }

  /// GET /orders/events?ticket=…&name=…&stations=a,b&version=…
  ///
  /// Server-Sent Events for kitchen screens: `connected` (with the
  /// heartbeat period), then `orders-changed` whenever the board's tables
  /// change (throttled), plus `: hb` comments every 20 s. A nudge to fetch
  /// `/orders` with the screen's own cursors, never order data.
  ///
  /// Authenticated by the password header (native screens may send it) or a
  /// ticket from `POST /orders/events/ticket` (the browser screen). 403
  /// otherwise — and an old till answers 404, which tells the screen to keep
  /// polling.
  Future<Response> _kdsEvents(Request request) async {
    final q = request.url.queryParameters;
    final password = _serverPassword;
    if (password != null && password.isNotEmpty) {
      final byHeader = request.headers['x-server-password'] == password;
      if (!byHeader &&
          !_ref.read(kdsStreamTicketsProvider).redeem(q['ticket'])) {
        return Response.forbidden(
          jsonEncode({'error': 'Invalid or missing ticket'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
    }

    final name = (q['name'] ?? request.headers['x-kds-name'] ?? '').trim();
    final label = name.isEmpty ? 'unnamed' : name;
    final presence = _ref.read(kdsPresenceProvider);
    final stations = parseKdsStations(q['stations']);
    final version = q['version'];
    final address = _remoteAddress(request);

    final hub = _ref.read(lanNotificationHubProvider);
    final inner = hub.subscribe(
      kdsChannel(label),
      hello: {
        'name': label,
        'heartbeatSeconds': LanNotificationHub.heartbeatInterval.inSeconds,
      },
    );
    presence.streamOpened(label,
        stations: stations, version: version, address: address);
    // The hub learns of a gone client on its next write; the presence entry
    // must follow the same moment, once.
    var closed = false;
    void leave() {
      if (closed) return;
      closed = true;
      presence.streamClosed(label);
    }

    // Completes when the client goes (cancel) or the hub closes it (done).
    final controller = StreamController<List<int>>(onCancel: leave);
    controller.addStream(inner).whenComplete(() {
      leave();
      if (!controller.isClosed) controller.close();
    });

    return Response.ok(
      controller.stream,
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'X-Accel-Buffering': 'no',
      },
      context: {'shelf.io.buffer_output': false},
    );
  }

  /// POST /kds-api/settings-code `{ "code": "1234" }` →
  /// `{ "accepted": bool, "tillPinSet": bool }`.
  ///
  /// Lets a kitchen screen accept the till's own settings PIN (or the daily
  /// master code), so one PIN guards every screen and is changed in one
  /// place — without the PIN ever leaving the till. Rate limited per
  /// address: a 4-digit PIN is otherwise a few minutes of guessing.
  Future<Response> _kdsSettingsCode(Request request) async {
    final address = _remoteAddress(request) ?? '?';
    if (!_settingsCodeAttempts.allow(address)) {
      return Response(429,
          body: jsonEncode({'error': 'too_many_attempts'}),
          headers: {'Content-Type': 'application/json'});
    }
    String code = '';
    try {
      final body = jsonDecode(await request.readAsString());
      if (body is Map) code = '${body['code'] ?? ''}';
    } catch (_) {
      return Response.badRequest(
          body: jsonEncode({'error': 'invalid_json'}),
          headers: {'Content-Type': 'application/json'});
    }
    final settings = _ref.read(settingsProvider);
    final pin = settings.settingsLockEnabled ? settings.settingsPin : '';
    final accepted =
        settingsCodeAccepted(code, pin: pin, now: DateTime.now());
    if (accepted) {
      _settingsCodeAttempts.reset(address);
    } else {
      _settingsCodeAttempts.fail(address);
    }
    return Response.ok(
      jsonEncode({'accepted': accepted, 'tillPinSet': pin.isNotEmpty}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// POST /orders/ - Create new order
  Future<Response> _createOrder(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      posLog('📥 _createOrder: $json');

      // Read extra fields not in SocketOrderModel
      final waiterId = json['waiterId'] as int?;
      final createdBy = json['createdBy'] as int?;
      final takenBy = json['takenBy'] as int? ?? createdBy;

      final socketOrder = SocketOrderModel.fromJson(json);

      // For DINE_IN: validate waiter only when one is provided
      // (kiosk/KDS orders may arrive without a waiter — that's acceptable here)
      if (socketOrder.type == 'DINE_IN' && waiterId != null) {
        final waiter = await (database.select(database.waiters)
              ..where((w) => w.id.equals(waiterId)))
            .getSingleOrNull();
        if (waiter == null || !waiter.isActive) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Invalid or inactive waiter'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // The shift this order belongs to. Read from `cash_sessions`, not from
      // `currentSessionProvider`: that provider is only ever populated by the
      // login screen, and this endpoint serves KDS/kiosk devices that post
      // over the LAN whether or not a cashier has signed in on this terminal.
      // When it was null the z_day fell through to `DateTime.now()`, so a
      // kiosk order taken at 00:30 inside a 20:00 shift was stamped with the
      // NEXT day.
      //
      // `sessionId` was never set here at all, which also kept these orders
      // out of every session-scoped view and left the backend with nothing to
      // reconcile them to.
      final createSession = await ZDayResolver(database).activeSession();
      final createZDay =
          await ZDayResolver(database).forSession(createSession?.id) ??
              _ref.read(currentZDayProvider);

      // Header, table link, lines and options commit together: a crash
      // mid-write must not leave a half-written order on the floor.
      final orderId = await database.transaction<int>(() async {
        final newOrderId = await database.into(database.orders).insert(
          OrdersCompanion.insert(
            code: socketOrder.code,
            status: drift.Value(socketOrder.status),
            type: drift.Value(socketOrder.type),
            priority: drift.Value(socketOrder.priority),
            persons: drift.Value(socketOrder.persons),
            tableId: drift.Value(socketOrder.tableId),
            clientId: drift.Value(socketOrder.clientId),
            waiterId: drift.Value(waiterId),
            createdBy: drift.Value(createdBy),
            takenBy: drift.Value(takenBy),
            note: drift.Value(socketOrder.note),
            sessionId: drift.Value(createSession?.id),
            sessionOrderNo: drift.Value(await database.nextSessionOrderNo(
                createSession?.id,
                mode: _ref.read(settingsProvider).orderNumberResetMode)),
            zDay: drift.Value(createZDay),
            createdAt: drift.Value(socketOrder.date),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );

        // If DINE_IN with a table, link the order to the table
        if (socketOrder.tableId != null) {
          await (database.update(database.areaTables)
            ..where((t) => t.id.equals(socketOrder.tableId!)))
            .write(AreaTablesCompanion(orderId: drift.Value(newOrderId)));
        }

        // Insert products
        // One resolver for the basket: it memoises the catalogue lookups.
        final costResolver = ProductCostResolver(database);
        for (final product in socketOrder.products) {
          // Resolve authoritative price from DB for the variant (prevents price manipulation)
          double unitPrice = product.unitaryPrice;
          double unitTva = product.tvaAmount ?? 0.0;
          double unitDiscount = product.discountAmount ?? 0.0;

          if (product.variantId != null) {
            final variant = await (database.select(database.productVariants)
              ..where((v) => v.id.equals(product.variantId!)))
              .getSingleOrNull();
            if (variant != null) {
              unitPrice = variant.price;
              unitTva = variant.tvaAmount;
              // A variant has its own price and no catalogue discount.
              unitDiscount = 0.0;
            }
          } else {
            final dbProduct = await (database.select(database.products)
              ..where((p) => p.id.equals(product.productId)))
              .getSingleOrNull();
            if (dbProduct != null) {
              unitPrice = dbProduct.finalPrice;
              unitTva = dbProduct.tvaAmount;
              unitDiscount = dbProduct.discountAmount;
            }
          }

          final orderProductId = await database.into(database.orderProducts).insert(
            OrderProductsCompanion.insert(
              orderId: newOrderId,
              productId: product.productId,
              variantId: drift.Value(product.variantId),
              quantity: drift.Value(product.quantity),
              unitaryPrice: unitPrice,
              // Cost stamped for LAN-created orders too, so a waiter-app sale
              // reports the same margin as one rung up on the till.
              cost: drift.Value(await costResolver.resolve(
                  productId: product.productId,
                  variantId: product.variantId)),
              unitaryDiscount: drift.Value(unitDiscount),
              unitaryTva: drift.Value(unitTva),
              note: drift.Value(product.note),
              state: drift.Value(product.state),
              zDay: drift.Value(createZDay),
            ),
          );

          // Insert components
          for (final component in product.components) {
            await database.into(database.orderProductComponents).insert(
              OrderProductComponentsCompanion.insert(
                orderProductId: orderProductId,
                componentId: component.componentId,
                quantity: drift.Value(component.quantity),
                price: drift.Value(component.extraPrice ?? 0.0),
                isSpecial: drift.Value(component.isSpecial),
                name: drift.Value(component.componentName),
              ),
            );
          }
        }
        return newOrderId;
      });

      // Log order creation
      await logService.logOrderCreated(orderId, 'Order created via API: code=${socketOrder.code}');

      posLog('✅ _createOrder: inserted order #$orderId code=${socketOrder.code}');

      return Response(
        201,
        body: jsonEncode({'id': orderId, 'code': socketOrder.code}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _createOrder: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create order', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /orders/<code> - Update order
  /// PUT /orders/<code>?status=newstatus - Fast update order status
  Future<Response> _updateOrder(Request request, String orderId) async {
    final id = int.tryParse(orderId)!;

    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final queryParams = request.url.queryParameters;
      final statusParam = queryParams['status'];

      // Fast status update
      if (statusParam != null) {
        final newStatus = statusParam.toUpperCase();

        // Confirming user: accept `userId` (preferred), or legacy `createdBy`/`takenBy`
        final userIdStr = queryParams['userId'] ?? queryParams['createdBy'];
        final userId = userIdStr != null ? int.tryParse(userIdStr) : null;

        // Look up current order to detect confirmation (ONHOLD → non-ONHOLD)
        final existing = await (database.select(database.orders)
              ..where((tbl) => tbl.id.equals(id)))
            .getSingleOrNull();
        if (existing == null) {
          return Response.notFound(
            jsonEncode({'error': 'Order not found'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        final isConfirming = existing.status == 'ONHOLD' && newStatus != 'ONHOLD';

        // On confirmation, always assign createdBy + takenBy to the confirming user
        final companion = OrdersCompanion(
          status: drift.Value(newStatus),
          updatedAt: drift.Value(DateTime.now()),
          createdBy: isConfirming && userId != null
              ? drift.Value(userId)
              : const drift.Value.absent(),
          takenBy: isConfirming && userId != null
              ? drift.Value(userId)
              : const drift.Value.absent(),
          // Kitchen micro-states stay LOCAL (LAN-only KDS); only a TERMINAL
          // state marks the order for cloud sync.
          isSynced: _isTerminalState(newStatus)
              ? const drift.Value(false)
              : const drift.Value.absent(),
        );

        await (database.update(database.orders)
              ..where((tbl) => tbl.id.equals(id)))
            .write(companion);

        if (_isTerminalState(newStatus)) {
          _autoSyncWaiterOrder(id, 'kds-terminal');
        }

        if (isConfirming) {
          await logService.logOrderUpdated(
            id,
            'Order confirmed (status $newStatus)${userId != null ? ' by user #$userId' : ''}',
          );
        }

        return Response.ok(
          jsonEncode({'message': 'Order status updated', 'id': id}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Full update with body
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final socketOrder = SocketOrderModel.fromJson(json);

      final waiterId = json['waiterId'] as int?;
      final createdBy = json['createdBy'] as int?;
      final takenBy = json['takenBy'] as int?;

      // DINE_IN must have waiter
      if (socketOrder.type == 'DINE_IN' && waiterId == null) {
        // Check if order already has a waiter
        final existing = await (database.select(database.orders)
              ..where((o) => o.id.equals(id)))
            .getSingleOrNull();
        if (existing == null || existing.waiterId == null) {
          return Response.badRequest(
            body: jsonEncode(
                {'error': 'waiterId is required for DINE_IN orders'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // Update order
      final updated = await (database.update(database.orders)
            ..where((tbl) => tbl.id.equals(id)))
          .write(
        OrdersCompanion(
          status: drift.Value(socketOrder.status),
          type: drift.Value(socketOrder.type),
          priority: drift.Value(socketOrder.priority),
          persons: drift.Value(socketOrder.persons),
          tableId: drift.Value(socketOrder.tableId),
          clientId: drift.Value(socketOrder.clientId),
          waiterId: waiterId != null
              ? drift.Value(waiterId)
              : const drift.Value.absent(),
          createdBy: createdBy != null
              ? drift.Value(createdBy)
              : const drift.Value.absent(),
          takenBy: takenBy != null
              ? drift.Value(takenBy)
              : const drift.Value.absent(),
          note: drift.Value(socketOrder.note),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
      if (updated == 0) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      await logService.logOrderUpdated(id, 'Order fully updated via API');

      return Response.ok(
        jsonEncode({'message': 'Order updated', 'code': id}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _updateOrder: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update order', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /orders/products/<id>?status=newstatus - Update product status
  Future<Response> _updateOrderProduct(Request request, String id) async {
    try {
      final queryParams = request.url.queryParameters;
      final statusParam = queryParams['status'];

      if (statusParam == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing "status" query parameter'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final productId = int.tryParse(id);
      if (productId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid product ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final found = await applyKitchenLineState(
          productId, statusParam.toUpperCase(),
          source: 'API');
      if (!found) {
        return Response.notFound(
          jsonEncode({'error': 'Order product not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'message': 'Product status updated', 'id': productId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _updateOrderProduct: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update product', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Move one order line to [newState] exactly as a KDS bump does: stage
  /// stamps, the waiter's "ready" event, the order rollup, and the change-log
  /// entry the KDS polls on. Shared by `PUT /orders/products/<id>` and the
  /// POS kitchen board, so a change made at the till reaches every screen.
  /// Returns false when the line does not exist.
  Future<bool> applyKitchenLineState(int lineId, String newState,
      {String source = 'POS'}) async {
    final database = _ref.read(databaseProvider);
    final logService = OrderLogService(database);
    final now = DateTime.now();

    // Read the current row first: needed to stamp each KDS stage timestamp
    // only the FIRST time the item enters that stage (a remake bouncing back
    // to PREPARING must not overwrite the original prep start).
    final existing = await (database.select(database.orderProducts)
          ..where((tbl) => tbl.id.equals(lineId)))
        .getSingleOrNull();
    if (existing == null) return false;

    await (database.update(database.orderProducts)
          ..where((tbl) => tbl.id.equals(lineId)))
        .write(kitchenStageStamps(existing, newState, now).copyWith(
          state: drift.Value(newState),
          updatedAt: drift.Value(now),
        ));

    final orderId = existing.orderId;
    // First time the kitchen is done with this line → the waiter has food
    // to carry. Stage timestamps are write-once, so a remake bounced back
    // and re-bumped does not ring twice.
    if (isKitchenDoneState(newState) &&
        existing.readyAt == null &&
        existing.servedAt == null) {
      _ref
          .read(waiterKitchenEventServiceProvider)
          .lineReady(orderId: orderId, lineId: lineId);
    }
    final allProducts = await (database.select(database.orderProducts)
          ..where((tbl) => tbl.orderId.equals(orderId)))
        .get();
    final allSameStatus = allProducts.every((p) => p.state == newState);
    // Whole order finished in the kitchen → tell the delivery platform.
    // Fired on READY and on any terminal rollup, because a station that goes
    // straight from PREPARING to COMPLETED never passes through READY.
    if (allSameStatus &&
        (newState == 'READY' || _isTerminalState(newState))) {
      // ignore: unawaited_futures
      _signalOrderReadyIfDelivery(orderId);
    }
    if (allSameStatus) {
      final terminal = _isTerminalState(newState);
      // Orders are born COMPLETED (cloud-terminal); the kitchen flow lives on
      // the PRODUCTS. So a KDS micro-state rollup (PENDING/PREPARING/READY)
      // must NOT drag order.status back down — that would un-complete a
      // cloud-terminal order. Only a genuinely terminal rollup
      // (COMPLETED/CANCELED/DELIVERED) writes order.status, and only a
      // non-COMPLETED terminal (CANCELED/DELIVERED) is a real change worth
      // re-syncing.
      if (terminal) {
        await (database.update(database.orders)
              ..where((tbl) => tbl.id.equals(orderId)))
            .write(OrdersCompanion(
          status: drift.Value(newState),
          updatedAt: drift.Value(now),
          isSynced: const drift.Value(false),
        ));
        _autoSyncWaiterOrder(orderId, 'kds-terminal');
      } else {
        // Micro-state rollup: bump updatedAt only, so the change-log cursor
        // still surfaces the order to the KDS on the next poll.
        await (database.update(database.orders)
              ..where((tbl) => tbl.id.equals(orderId)))
            .write(OrdersCompanion(updatedAt: drift.Value(now)));
      }
    }
    await logService.logOrderUpdated(
        orderId, 'Product status updated via $source to $newState');
    return true;
  }

  /// Flag (or unflag) [orderId] as a rush for the kitchen: the KDS shows it
  /// first, flashing, with the alarm. Rides the order's existing `priority`
  /// (> 0 = rush) and the change log, so the KDS picks it up on its next poll.
  Future<void> setOrderRush(int orderId, bool rush) async {
    final database = _ref.read(databaseProvider);
    await (database.update(database.orders)
          ..where((tbl) => tbl.id.equals(orderId)))
        .write(OrdersCompanion(
      priority: drift.Value(rush ? 1 : 0),
      updatedAt: drift.Value(DateTime.now()),
    ));
    await OrderLogService(database).logOrderUpdated(
        orderId, rush ? 'Kitchen rush requested' : 'Kitchen rush cleared');
  }

  /// GET /stations/ - Get all stations (for KDS station selection)
  Future<Response> _getStations(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final stations = await database.select(database.stations).get();
      // `description` is NULLABLE in the DB. Never send null here: a KDS that
      // decodes it as a non-nullable String crashes its whole station list with
      // "null is not a subtype of type 'String'". Coalescing server-side also
      // fixes older KDS builds already deployed in the field.
      final stationList = stations
          .map((s) => {
                'id': s.id,
                'name': s.name,
                'description': s.description ?? '',
              })
          .toList();

      return Response.ok(
        jsonEncode({'stations': stationList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _getStations: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch stations', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// 404 handler
  Future<Response> _notFound(Request request) async {
    return Response.notFound(
      jsonEncode({'error': 'Endpoint not found'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // ==================== WAITER PUSH CHANNEL ====================

  /// GET /waiters/events?waiterId=12 — Server-Sent Events, held open for the
  /// whole shift.
  ///
  /// Deliberately LAN-only. The cloud SSE channel this mirrors ([SseService])
  /// is for things the *company* pushes; a cashier asking a waiter to come to
  /// table 7 is a room-sized event that must keep working when the internet
  /// does not. Same Wi-Fi, same Shelf server, no round trip.
  ///
  /// Unlike the other waiter routes this one does not 400 on a missing waiter:
  /// it is held open for hours, so an identity that has since been
  /// deactivated has to fail at *connect* time and stay failed, rather than
  /// leave the phone reconnecting in a loop against an endpoint that answers.
  ///
  /// 200: `text/event-stream`, framed `connected` / `waiter-call` /
  /// `waiter-call-cancelled` events plus `: hb` comments every 20s.
  Future<Response> _waiterEvents(Request request) async {
    final waiterId = int.tryParse(request.url.queryParameters['waiterId'] ?? '');
    if (waiterId == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'waiterId is required'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final db = _ref.read(databaseProvider);
    final waiter = await (db.select(db.waiters)
          ..where((w) => w.id.equals(waiterId)))
        .getSingleOrNull();
    if (waiter == null || !waiter.isActive) {
      return Response.forbidden(
        jsonEncode({'error': 'unknown_waiter'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final calls = _ref.read(waiterCallServiceProvider);
    final stream = _ref.read(lanNotificationHubProvider).subscribe(
          'waiter:$waiterId',
          hello: {
            'waiterId': waiterId,
            'callsEnabled': _ref.read(settingsProvider).waiterCallEnabled,
            ..._waiterKitchenSwitches(),
            'heartbeatSeconds': LanNotificationHub.heartbeatInterval.inSeconds,
          },
          // A call placed while this phone was locked, out of range, or on the
          // login screen is still owed to the waiter. Replaying it on connect
          // is what turns best-effort push into something a cashier can rely on.
          replay: [
            ...calls.replayEventsFor(waiterId),
            ..._ref
                .read(waiterKitchenEventServiceProvider)
                .replayEventsFor(waiterId),
          ],
        );

    return Response.ok(
      stream,
      headers: {
        'Content-Type': 'text/event-stream; charset=utf-8',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        // Tells any reverse proxy in front of the till not to buffer. Without
        // it a proxy can hold events until the response "finishes", which for
        // a stream is never.
        'X-Accel-Buffering': 'no',
      },
      // shelf_io buffers response bodies by default, which for SSE means the
      // client sees nothing until the buffer fills. This is the documented
      // opt-out and the single line that makes the whole channel work.
      context: {'shelf.io.buffer_output': false},
    );
  }

  /// POST /waiters/calls/<callId>/ack — the waiter dismissed the notification.
  ///
  /// Stops the ringing on that waiter's other devices and lets the POS tell
  /// the cashier somebody is on the way, so they do not call twice.
  ///
  /// 200 on success; 404 when the call already expired or was acknowledged —
  /// both are fine outcomes for the phone, which should stop ringing either way.
  Future<Response> _waiterAckCall(Request request, String callId) async {
    try {
      String? by;
      final raw = await request.readAsString();
      if (raw.trim().isNotEmpty) {
        final body = jsonDecode(raw);
        if (body is Map<String, dynamic>) by = body['by'] as String?;
      }

      final call = _ref.read(waiterCallServiceProvider).acknowledge(callId, by: by);
      if (call == null) {
        return Response.notFound(
          jsonEncode({'error': 'unknown_call', 'callId': callId}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      return Response.ok(
        jsonEncode({
          'acknowledged': true,
          'callId': call.id,
          'acknowledgedAt': call.acknowledgedAt?.toIso8601String(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      Logger.instance.error('_waiterAckCall failed: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'ack_failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/notifications?waiterId=&limit= — the waiter's notification
  /// history (kitchen events + calls), newest first, with read flags.
  ///
  /// Held in memory by [WaiterNotificationInbox]: survives app restarts and
  /// reconnects, not a POS restart. Same entries and ids as the live SSE
  /// frames, so the app can merge the two.
  Future<Response> _waiterNotifications(Request request) async {
    final q = request.url.queryParameters;
    final waiterId = int.tryParse(q['waiterId'] ?? '');
    if (waiterId == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'waiterId is required'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final limit = (int.tryParse(q['limit'] ?? '') ?? 100).clamp(1, 500);
    final inbox = _ref.read(waiterNotificationInboxProvider);
    return Response.ok(
      jsonEncode({
        'notifications': inbox.listFor(waiterId, limit: limit),
        'unreadCount': inbox.unreadCount(waiterId),
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// POST /waiters/notifications/read — body `{"waiterId": 12, "ids": [...]}`.
  /// Omit `ids` to mark everything read. Returns the new unread count.
  Future<Response> _waiterNotificationsRead(Request request) async {
    try {
      final raw = await request.readAsString();
      final body = raw.trim().isEmpty ? null : jsonDecode(raw);
      final waiterId =
          body is Map<String, dynamic> ? (body['waiterId'] as num?)?.toInt() : null;
      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      final ids = (body['ids'] as List?)?.map((e) => e.toString());
      final inbox = _ref.read(waiterNotificationInboxProvider);
      inbox.markRead(waiterId, ids);
      return Response.ok(
        jsonEncode({'unreadCount': inbox.unreadCount(waiterId)}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.badRequest(
        body: jsonEncode({'error': 'invalid_body', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // ==================== EMBEDDED KDS WEB APP ====================

  /// Serve a file from the extracted KDS web bundle. [rel] is the path under
  /// `/kds/` ('' → index.html). Unknown paths fall back to index.html so the
  /// single-page app's client-side routes resolve.
  Future<Response> _serveKdsWeb(String rel) async {
    final root = await _ensureKdsWebExtracted();
    if (root == null) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'KDS web bundle unavailable'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    var path = rel.replaceFirst(RegExp(r'^/+'), '');
    if (path.isEmpty) path = 'index.html';
    // Block path traversal.
    if (path.contains('..')) return Response.forbidden('Forbidden');

    // Neutralise the Flutter service worker. A cached SW would keep serving a
    // STALE JS bundle on refresh (the cause of "orders disappear / old app after
    // F5"). We instead return a self-unregistering SW that caches nothing and
    // wipes any existing caches, so every load fetches fresh from the POS.
    if (path == 'flutter_service_worker.js') {
      const noop = '''
self.addEventListener('install', (e) => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) { await caches.delete(k); }
    await self.clients.claim();
  })());
});
self.addEventListener('fetch', () => {}); // pass-through, no caching
''';
      return Response.ok(noop, headers: {
        'Content-Type': 'text/javascript',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
      });
    }

    var file = File('$root/$path');
    if (!await file.exists()) {
      file = File('$root/index.html');
      path = 'index.html';
    }
    try {
      // index.html: force the base href to /kds/ so the bundle's assets
      // (flutter_bootstrap.js, main.dart.js, canvaskit, …) resolve under /kds/
      // instead of the site root. This makes serving path-independent of how
      // the web bundle was built.
      if (path == 'index.html') {
        var html = await file.readAsString();
        html = html.replaceFirst(
            RegExp(r'<base\s+href="[^"]*"\s*/?>'), '<base href="/kds/">');
        return Response.ok(html, headers: {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-cache',
        });
      }
      final bytes = await file.readAsBytes();
      return Response.ok(bytes, headers: {
        'Content-Type': _kdsMimeType(path),
        'Cache-Control': 'no-cache',
      });
    } catch (e) {
      return Response.internalServerError(body: 'Failed to read $path');
    }
  }

  /// Extract `assets/kds_web.zip` to a temp dir once and return its path.
  Future<String?> _ensureKdsWebExtracted() {
    if (_kdsWebDir != null) return Future.value(_kdsWebDir);
    return _kdsExtraction ??= () async {
      try {
        final tmp = await getTemporaryDirectory();
        final dir = Directory('${tmp.path}/kds_web');
        // Fresh extraction once per app launch (deduped by _kdsExtraction), so
        // an updated bundle isn't shadowed by a previous run's stale files.
        if (await dir.exists()) await dir.delete(recursive: true);
        await dir.create(recursive: true);
        final data = await rootBundle.load('assets/kds_web.zip');
        final archive = ZipDecoder().decodeBytes(data.buffer.asUint8List());
        for (final entry in archive) {
          final outPath = '${dir.path}/${entry.name}';
          if (entry.isFile) {
            final f = File(outPath);
            await f.parent.create(recursive: true);
            await f.writeAsBytes(entry.content as List<int>);
          } else {
            await Directory(outPath).create(recursive: true);
          }
        }
        posLog('✅ Extracted KDS web bundle to ${dir.path}');
        _kdsWebDir = dir.path;
        return _kdsWebDir;
      } catch (e, st) {
        Logger.instance.error('Failed to extract KDS web bundle: $e\n$st');
        _kdsExtraction = null; // allow a retry on the next request
        return null;
      }
    }();
  }

  String _kdsMimeType(String p) {
    if (p.endsWith('.html')) return 'text/html; charset=utf-8';
    if (p.endsWith('.js') || p.endsWith('.mjs')) return 'text/javascript';
    if (p.endsWith('.json')) return 'application/json';
    if (p.endsWith('.wasm')) return 'application/wasm';
    if (p.endsWith('.css')) return 'text/css';
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.svg')) return 'image/svg+xml';
    if (p.endsWith('.ico')) return 'image/x-icon';
    if (p.endsWith('.mp3')) return 'audio/mpeg';
    if (p.endsWith('.otf')) return 'font/otf';
    if (p.endsWith('.ttf')) return 'font/ttf';
    if (p.endsWith('.woff')) return 'font/woff';
    if (p.endsWith('.woff2')) return 'font/woff2';
    return 'application/octet-stream';
  }

  // ==================== WAITER ENDPOINTS ====================

  /// POST /waiters/login
  ///
  /// Pin-only authentication. The waiter types a numeric PIN into the
  /// waiter app; that PIN is the unique identifier for the waiter record
  /// (uniqueness enforced by the partial unique index `idx_waiters_pin`
  /// added at schemaVersion 18, populated from the backend via
  /// `_persistWaiters`).
  ///
  /// Body: `{ "pin": "1234" }`
  ///
  /// Responses (see `docs/waiter_app_pin_login.md` for the full contract):
  ///   - 200: `{ "waiter": { id, firstName, lastName, imageUrl, areaIds } }`
  ///   - 400: `{ "error": "pin_required" }`
  ///   - 403: `{ "error": "invalid_pin" }`          // unknown OR inactive
  ///   - 500: `{ "error": "login_failed", "details": "..." }`
  ///
  /// Deliberately returns the SAME error code for "no such pin" and
  /// "pin matches an inactive waiter" so the response can't be used as an
  /// oracle to enumerate valid pins.
  /// GET /waiters/profiles
  ///
  /// Roster for the login profile-picker: the active waiters the app shows so
  /// the user taps their face/name and then enters their PIN (instead of a
  /// blind PIN entry). Deliberately carries NO pin — the PIN is still the
  /// credential, verified by [_waiterLogin]. Names/photos are not secret.
  ///
  /// 200: `{ "waiters": [ { id, firstName, lastName, imageUrl } ] }`
  Future<Response> _waiterProfiles(Request request) async {
    try {
      final db = _ref.read(databaseProvider);
      final waiters = await (db.select(db.waiters)
            ..where((w) => w.isActive.equals(true))
            ..orderBy([(w) => drift.OrderingTerm(expression: w.firstName)]))
          .get();
      return Response.ok(
        jsonEncode({
          'waiters': waiters
              .map((w) => {
                    'id': w.id,
                    'firstName': w.firstName,
                    'lastName': w.lastName,
                    'imageUrl': w.imageUrl,
                  })
              .toList(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      Logger.instance.error('_waiterProfiles failed: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode(
            {'error': 'Failed to fetch profiles', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  Future<Response> _waiterLogin(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final pin = (body['pin'] as String?)?.trim();
      // Optional: the profile the user picked on the login screen. When sent,
      // the PIN is validated against THIS waiter (so picking profile A but
      // typing B's PIN fails). When absent, we fall back to pin-only lookup
      // for backward compatibility with the original blind-PIN flow.
      final selectedWaiterId = body['waiterId'] as int?;

      if (pin == null || pin.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'pin_required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final db = _ref.read(databaseProvider);
      // With a selected profile: match by id AND pin. Without: look up by pin
      // alone (the partial unique index guarantees at most one match).
      final waiter = selectedWaiterId != null
          ? await (db.select(db.waiters)
                ..where((w) => w.id.equals(selectedWaiterId) & w.pin.equals(pin)))
              .getSingleOrNull()
          : await (db.select(db.waiters)
                ..where((w) => w.pin.equals(pin)))
              .getSingleOrNull();

      if (waiter == null || !waiter.isActive) {
        return Response.forbidden(
          jsonEncode({'error': 'invalid_pin'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final waiterAreas = await (db.select(db.waiterAreas)
            ..where((wa) => wa.waiterId.equals(waiter.id)))
          .get();

      // Activity log — audit trail of every successful waiter PIN login.
      // Fire-and-forget; the service swallows its own errors so a logging
      // hiccup never breaks login.
      final waiterFullName =
          '${waiter.firstName} ${waiter.lastName ?? ''}'.trim();
      // ignore: unawaited_futures
      _ref
          .read(activityLogServiceProvider)
          .logWaiterLogin(waiterName: waiterFullName);

      return Response.ok(
        jsonEncode({
          'waiter': {
            'id': waiter.id,
            'firstName': waiter.firstName,
            'lastName': waiter.lastName,
            'imageUrl': waiter.imageUrl,
            'areaIds': waiterAreas.map((wa) => wa.areaId).toList(),
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterLogin: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'login_failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

    /// GET /waiters/dashboard?waiterId=1
  /// Returns: total orders, active orders, expected cash, total cash
  /// Canonical per-line total — the SINGLE formula the waiter endpoints must
  /// use so their amounts match the POS. Mirrors [OrderItem.totalPrice] and
  /// `OrderRepository.getOrderTotals`:
  ///
  ///   (unitaryPrice + Σ(component.price × component.quantity) − manualDiscount)
  ///       × quantity
  ///
  /// Two mistakes the older inline math made — which made waiter totals differ
  /// from the POS — are fixed here: (1) each component is multiplied by the
  /// product `quantity` (it was added only once, so a qty-2 line with add-ons
  /// under-counted the add-ons); (2) `unitaryDiscount` is NOT subtracted — the
  /// per-unit pre-discount is already baked into `unitaryPrice`, so subtracting
  /// it again double-discounted the line. The caller skips cancelled lines and
  /// applies the order-level `discountPercentage`.
  double _waiterLineTotal(
          OrderProduct p, Iterable<OrderProductComponent> comps) =>
      p.amounts(componentsPerUnit: componentsPerUnitOf(comps)).net;

  /// Money already taken on the order's open split-by-amount parts.
  Future<double> _splitCredit(int orderId) async =>
      (await _ref.read(orderRepositoryProvider).moneySplitParts(orderId))
          .fold<double>(0.0, (sum, t) => sum + t.amount);

  /// Terminal (done) order/product states — the only ones that mark an order
  /// for cloud sync from the KDS path. Everything else (PENDING, PREPARING,
  /// READY, …) is a kitchen micro-state that stays LOCAL on the LAN-only KDS.
  static bool _isTerminalState(String s) =>
      s == 'COMPLETED' || s == 'CANCELED' || s == 'DELIVERED';

  /// The active cash-session id, or null when none is open. The read endpoints
  /// (`dashboard`, `orders`) scope to THIS session (the current shift) rather
  /// than a calendar day, so opening a new session gives the waiter app a clean
  /// slate and closing one hides its orders. (`tables` is deliberately NOT
  /// scoped — see [_waiterTables].)
  int? _currentWaiterSessionId() => _ref.read(currentSessionProvider)?.id;

  /// Returns an error [Response] when a waiter may NOT create an order right
  /// now — no session open, or the session is paused — or null when creation
  /// is allowed. The session's status is re-read LIVE from the DB because the
  /// in-memory `currentSessionProvider` copy can be stale (a pause-in-place
  /// updates the row but not the provider). Emits a machine `error` code plus a
  /// human `message` (see `docs/waiter_api_errors.md`).
  Future<Response?> _blockOrderCreationIfSessionUnavailable() async {
    Response err(String code, String message) => Response(
          409,
          body: jsonEncode({'error': code, 'message': message}),
          headers: {'Content-Type': 'application/json'},
        );

    final session = _ref.read(currentSessionProvider);
    if (session == null) {
      return err('no_open_session',
          'No cash session is open. Ask the cashier to open a session before taking orders.');
    }
    final database = _ref.read(databaseProvider);
    final live = await (database.select(database.cashSessions)
          ..where((s) => s.id.equals(session.id)))
        .getSingleOrNull();
    if (live == null || live.status == 'ended') {
      return err('no_open_session',
          'No cash session is open. Ask the cashier to open a session before taking orders.');
    }
    if (live.status == 'paused') {
      return err('session_paused',
          'The cash session is paused. Ask the cashier to resume it before taking orders.');
    }
    return null;
  }

  Future<Response> _waiterDashboard(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final queryParams = request.url.queryParameters;
      final waiterIdStr = queryParams['waiterId'];

      if (waiterIdStr == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final waiterId = int.tryParse(waiterIdStr);
      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid waiterId'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Scope to the CURRENT cash session (the shift), not a calendar day.
      // No session open ⇒ nothing to report (stable zero shape).
      final sessionId = _currentWaiterSessionId();
      if (sessionId == null) {
        return Response.ok(
          jsonEncode({
            'totalOrders': 0,
            'activeOrders': 0,
            'cancelledOrders': 0,
            'expectedCash': 0.0,
            'totalCash': 0.0,
            'cancelledAmount': 0.0,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final allWaiterOrders = await (database.select(database.orders)
        ..where((o) => o.waiterId.equals(waiterId) & o.sessionId.equals(sessionId)))
        .get();

      final waiterOrders = allWaiterOrders.where((o) => o.status != 'CANCELED').toList();
      final cancelledOrders = allWaiterOrders.where((o) => o.status == 'CANCELED').toList();

      final totalOrders = waiterOrders.length;
      final cancelledCount = cancelledOrders.length;
      // `activeOrders` is derived from PRODUCT state below, not order.status:
      // orders are born COMPLETED (cloud-terminal), so order.status can no
      // longer tell an in-progress order from a finished one.

      // Batch-load all order products, components, and tickets in 3 queries
      final allOrderIds = allWaiterOrders.map((o) => o.id).toList();
      final allOrderProducts = allOrderIds.isEmpty
          ? <OrderProduct>[]
          : await (database.select(database.orderProducts)
              ..where((op) => op.orderId.isIn(allOrderIds)))
              .get();

      final allOpIds = allOrderProducts.map((p) => p.id).toList();
      final allComponentsList = allOpIds.isEmpty
          ? <OrderProductComponent>[]
          : await (database.select(database.orderProductComponents)
              ..where((c) => c.orderProductId.isIn(allOpIds)))
              .get();

      final ticketIds = allOrderProducts
          .where((p) => p.ticketId != null)
          .map((p) => p.ticketId!)
          .toSet()
          .toList();
      final ticketsRaw = ticketIds.isEmpty
          ? <Ticket>[]
          : await (database.select(database.tickets)
              ..where((t) => t.id.isIn(ticketIds)))
              .get();

      // Build lookup maps
      final componentsByOpId = <int, List<OrderProductComponent>>{};
      for (final c in allComponentsList) {
        componentsByOpId.putIfAbsent(c.orderProductId, () => []).add(c);
      }
      final ticketsMap = {for (final t in ticketsRaw) t.id: t};
      final productsByOrderId = <int, List<OrderProduct>>{};
      for (final p in allOrderProducts) {
        productsByOrderId.putIfAbsent(p.orderId, () => []).add(p);
      }

      // "Active" = still has kitchen/payment work outstanding: at least one
      // product not in a done state. Mirrors the KDS's product-driven model.
      const doneProductStates = {'COMPLETED', 'CANCELED', 'DELIVERED', 'PAID'};
      final activeOrders = waiterOrders.where((o) {
        final prods = productsByOrderId[o.id] ?? const <OrderProduct>[];
        return prods.any((p) => !doneProductStates.contains(p.state));
      }).length;

      double expectedCash = 0.0;
      double totalCash = 0.0;
      double cancelledAmount = 0.0;

      for (final order in cancelledOrders) {
        for (final p in productsByOrderId[order.id] ?? const <OrderProduct>[]) {
          cancelledAmount +=
              _waiterLineTotal(p, componentsByOpId[p.id] ?? const []);
        }
      }

      for (final order in waiterOrders) {
        var orderExpected = 0.0, orderCash = 0.0;
        for (final p in productsByOrderId[order.id] ?? const <OrderProduct>[]) {
          if (!lineCountsInTotal(p.state, paid: p.ticketId != null)) continue;
          final item = _waiterLineTotal(p, componentsByOpId[p.id] ?? const []);
          orderExpected += item;
          if (p.ticketId != null) {
            final ticket = ticketsMap[p.ticketId];
            if (ticket != null && !ticket.isCancelled) orderCash += item;
          }
        }
        expectedCash +=
            applyOrderDiscount(orderExpected, order.discountPercentage);
        totalCash += applyOrderDiscount(orderCash, order.discountPercentage);
      }

      // Cashier setting — when off, zero out the financial fields so the
      // waiter app sees `0` rows instead of the real values. Keys stay in
      // the response (the waiter app gets a stable JSON shape) but the
      // numbers don't leak the cash situation back to the waiter.
      final showOwed =
          _ref.read(settingsProvider).waiterDashboardShowOwed;
      return Response.ok(
        jsonEncode({
          'totalOrders': totalOrders,
          'activeOrders': activeOrders,
          'cancelledOrders': cancelledCount,
          'expectedCash': showOwed ? expectedCash : 0.0,
          'totalCash': showOwed ? totalCash : 0.0,
          'cancelledAmount': showOwed ? cancelledAmount : 0.0,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterDashboard: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to get dashboard', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/products
  Future<Response> _waiterProducts(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final products = _scopeProducts(await (database.select(database.products)
        ..where((p) => p.isActive.equals(true)))
        .get());

      final productList = products.map((p) => {
        'id': p.id,
        'name': p.name,
        'barcode': p.barcode,
        'imageUrl': p.imageUrl,
        'description': p.description,
        'price': p.price,
        'finalPrice': p.finalPrice,
        'categoryId': p.categoryId,
        'stationId': p.stationId,
        'isVariant': p.isVariant,
        'color': p.color,
        'isPlannable': p.isPlannable,
        'planDurationMinutes': p.planDurationMinutes,
        // The local "86" flag, so a waiter app / kiosk can grey the item out
        // instead of taking an order the kitchen cannot fill. Sent rather than
        // filtered so the client can SHOW it as unavailable — silently omitting
        // it would look like the product had been deleted.
        'isAvailable': p.isAvailable,
      }).toList();

      return Response.ok(
        jsonEncode({'products': productList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterProducts: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch products', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/categories
  Future<Response> _waiterCategories(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final categories = scopedCategories(
          await (database.select(database.categories)
                ..where((c) => c.isActive.equals(true))
                ..orderBy([(c) => drift.OrderingTerm(expression: c.displayOrder)]))
              .get(),
          _ref.read(categoryScopeProvider));

      final categoryList = categories.map((c) => {
        'id': c.id,
        'name': c.name,
        'imageUrl': c.imageUrl,
        'description': c.description,
        'displayOrder': c.displayOrder,
        'color': c.color,
      }).toList();

      return Response.ok(
        jsonEncode({'categories': categoryList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterCategories: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch categories', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/components
  ///
  /// 86'd components (`isActive = false`) are excluded — same rule the POS
  /// itself applies (`database_providers.dart`): the row stays for order
  /// history, but nobody gets to add one to a new line. `isActive` is still
  /// sent on every surviving row (always `true`) so an older waiter build
  /// that skips server-side filtering has something to defend itself with.
  Future<Response> _waiterComponents(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final components = await (database.select(database.components)
            ..where((c) => c.isActive.equals(true))
            ..orderBy([
              (c) => drift.OrderingTerm(expression: c.displayOrder),
              (c) => drift.OrderingTerm(expression: c.name),
            ]))
          .get();

      final componentList = components.map((c) => {
        'id': c.id,
        'name': c.name,
        'price': c.price,
        'componentGroupId': c.componentGroupId,
        'displayOrder': c.displayOrder,
        'isActive': c.isActive,
      }).toList();

      return Response.ok(
        jsonEncode({'components': componentList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterComponents: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch components', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/component-groups
  ///
  /// `selectionType`/`minSelection`/`maxSelection`/`freeQuantity` are the
  /// GROUP-LEVEL defaults — see `GET /waiters/product-component-groups` for
  /// the per-product overrides that win over these field-by-field. An
  /// unbounded `maxSelection` is sent as a real JSON `null`; the local
  /// column is nullable, so there is no zero-vs-unbounded ambiguity to guard
  /// against here the way there is on `/waiters/product-components`.
  Future<Response> _waiterComponentGroups(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final groups = await (database.select(database.componentGroups)
        ..orderBy([(g) => drift.OrderingTerm(expression: g.displayOrder)]))
        .get();

      final groupList = groups.map((g) => {
        'id': g.id,
        'name': g.name,
        'description': g.description,
        'displayOrder': g.displayOrder,
        'selectionType': g.selectionType,
        'minSelection': g.minSelection,
        'maxSelection': g.maxSelection,
        'freeQuantity': g.freeQuantity,
        'color': g.color,
      }).toList();

      return Response.ok(
        jsonEncode({'componentGroups': groupList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterComponentGroups: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch component groups', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/product-components
  Future<Response> _waiterProductComponents(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final productComponents = await database.select(database.productComponents).get();

      final pcList = productComponents.map((pc) => {
        'productId': pc.productId,
        'componentId': pc.componentId,
        'defaultPrice': pc.defaultPrice,
        'defaultQuantity': pc.defaultQuantity, // ✅ Added: Default quantity from ProductComponents relation table
        'isRequired': pc.isRequired,
        'minQuantity': pc.minQuantity,
        'maxQuantity': pc.maxQuantity,
        'chargeOnRemoval': pc.chargeOnRemoval,
      }).toList();

      return Response.ok(
        jsonEncode({'productComponents': pcList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterProductComponents: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch product components', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/product-component-groups
  ///
  /// Per-product overrides of a component group's selection rules — mirrors
  /// `ProductComponentGroups` (see the table's own doc comment) and the local
  /// merge in `database_providers.dart` (`productComponentGroupRulesProvider`,
  /// group default `?? ` per-product override, field by field).
  ///
  /// A row exists ONLY for a genuinely overridden (product, group) pair; a
  /// product that follows its group's defaults has no row here at all — ask
  /// `GET /waiters/component-groups` for those.
  ///
  /// Within a row, each rule field is OMITTED from the JSON when that
  /// specific field carries no override — never sent as an explicit `null`,
  /// never coerced to `0`. On this table `minSelection: 0` would silently
  /// un-require a group and `maxSelection: 0` would read as unlimited
  /// (`effectiveMaxQuantity`), so a coerced zero would be indistinguishable
  /// from a real override in both directions. A `containsKey` test on the
  /// field name is the wire-level way to ask "is this field overridden here".
  /// `displayOrder` is the one exception: the column is non-nullable
  /// (default 0) and always present.
  Future<Response> _waiterProductComponentGroups(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final overrides =
          await database.select(database.productComponentGroups).get();

      final rowList = overrides.map((o) {
        final row = <String, dynamic>{
          'productId': o.productId,
          'componentGroupId': o.groupId,
          'displayOrder': o.displayOrder,
        };
        if (o.selectionType != null) row['selectionType'] = o.selectionType;
        if (o.minSelection != null) row['minSelection'] = o.minSelection;
        if (o.maxSelection != null) row['maxSelection'] = o.maxSelection;
        if (o.freeQuantity != null) row['freeQuantity'] = o.freeQuantity;
        // Conditional group: shown only once one of these is picked.
        final visibleWhen = decodeVisibleWhen(o.visibleWhenComponentIds);
        if (visibleWhen.isNotEmpty) {
          row['visibleWhenComponentIds'] = visibleWhen;
        }
        return row;
      }).toList();

      return Response.ok(
        jsonEncode({'productComponentGroups': rowList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterProductComponentGroups: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({
          'error': 'Failed to fetch product component group overrides',
          'details': e.toString(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/product-variants?productId=123
  /// Returns all variant groups and their variants with attributes for proper selection
  Future<Response> _waiterProductVariants(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final queryParams = request.url.queryParameters;
      final productIdStr = queryParams['productId'];

      if (productIdStr == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'productId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final productId = int.tryParse(productIdStr);
      if (productId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid productId'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Check if product exists
      final product = await (database.select(database.products)
        ..where((p) => p.id.equals(productId)))
        .getSingleOrNull();

      if (product == null) {
        return Response(
          404,
          body: jsonEncode({
            'error': 'Product not found',
            'message': 'Product with ID $productId does not exist'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get all variants for this product
      final variants = await (database.select(database.productVariants)
        ..where((v) => v.productId.equals(productId))
        ..where((v) => v.isActive.equals(true)))
        .get();

      if (variants.isEmpty) {
        return Response.ok(
          jsonEncode({
            'hasVariants': false,
            'variants': [],
            'attributeGroups': []
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get all variant attribute values for these variants
      final variantIds = variants.map((v) => v.id).toList();
      final attributeValues = await (database.select(database.variantAttributeValues)
        ..where((av) => av.variantId.isIn(variantIds)))
        .get();

      // Build variants list with their attributes
      final variantsList = variants.map((variant) {
        final variantAttrs = attributeValues
            .where((av) => av.variantId == variant.id)
            .toList();

        return {
          'id': variant.id,
          'productId': variant.productId,
          'name': variant.name,
          'barcode': variant.barcode,
          'sku': variant.sku,
          'description': variant.description,
          'imageUrl': variant.imageUrl,
          'color': variant.color,
          'price': variant.price,
          'additionalPrice': variant.price - product.price,
          'finalPrice': variant.price,
          'tvaAmount': variant.tvaAmount,
          'isActive': variant.isActive,
          'attributes': variantAttrs.map((attr) => {
            'attributeId': attr.attributeId,
            'attributeName': attr.attributeName,
            'valueId': attr.valueId,
            'value': attr.value,
          }).toList(),
        };
      }).toList();

      // Build attribute groups for UI selection
      final Map<String, Map<String, dynamic>> attributeGroupsMap = {};

      for (final attrValue in attributeValues) {
        final attrName = attrValue.attributeName ?? 'Options';
        final attrId = attrValue.attributeId;

        if (!attributeGroupsMap.containsKey(attrName)) {
          attributeGroupsMap[attrName] = {
            'id': attrId,
            'name': attrName,
            'values': <Map<String, dynamic>>[],
          };
        }

        // Add unique values only
        final values = attributeGroupsMap[attrName]!['values'] as List;
        final existingValue = values.any((v) => v['id'] == attrValue.valueId);

        if (!existingValue) {
          values.add({
            'id': attrValue.valueId,
            'value': attrValue.value,
            'attributeId': attrId,
          });
        }
      }

      // Convert to list and sort
      final attributeGroups = attributeGroupsMap.values.toList();

      return Response.ok(
        jsonEncode({
          'hasVariants': true,
          'baseProduct': {
            'id': product.id,
            'name': product.name,
            'price': product.price,
            'imageUrl': product.imageUrl,
          },
          'variants': variantsList,
          'attributeGroups': attributeGroups,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterProductVariants: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({
          'error': 'Failed to fetch product variants',
          'details': e.toString()
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/tables?waiterId=1
  /// Returns tables for the waiter's assigned areas
  Future<Response> _waiterTables(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final queryParams = request.url.queryParameters;
      final waiterIdStr = queryParams['waiterId'];

      if (waiterIdStr == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final waiterId = int.tryParse(waiterIdStr);
      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid waiterId'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get waiter areas
      final waiterAreas = await (database.select(database.waiterAreas)
        ..where((wa) => wa.waiterId.equals(waiterId)))
        .get();
      final areaIds = waiterAreas.map((wa) => wa.areaId).toList();

      // Get tables — all for global waiters (no area), filtered for area-restricted waiters
      final tablesQuery = database.select(database.areaTables);
      if (areaIds.isNotEmpty) {
        tablesQuery.where((t) => t.areaId.isIn(areaIds));
      }
      final tables = await tablesQuery.get();

      if (tables.isEmpty) {
        return Response.ok(
          jsonEncode({'tables': []}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Batch: load all areas for tables
      final uniqueAreaIds = tables
          .where((t) => t.areaId != null)
          .map((t) => t.areaId!)
          .toSet()
          .toList();
      final areasRaw = uniqueAreaIds.isEmpty
          ? <Area>[]
          : await (database.select(database.areas)
              ..where((a) => a.id.isIn(uniqueAreaIds)))
              .get();
      final areasMap = {for (final a in areasRaw) a.id: a};

      // Batch: load orders for occupied tables
      final tableOrderIds = tables
          .where((t) => t.orderId != null)
          .map((t) => t.orderId!)
          .toSet()
          .toList();
      // Tables are intentionally OUTSIDE session scoping: occupancy mirrors the
      // POS, which marks a table occupied purely by `areaTables.order_id`,
      // regardless of which session the order belongs to.
      List<Order> ordersRaw = [];
      if (tableOrderIds.isNotEmpty) {
        final ordersQuery = database.select(database.orders)
          ..where((o) => o.id.isIn(tableOrderIds));
        // Occupancy must mirror the POS, which marks a table occupied purely by
        // `areaTables.order_id`. So we keep COMPLETED orders here — a paid-but-
        // not-yet-cleared table stays occupied in the waiter app just like on
        // the POS (balance shows 0). Only CANCELED is dropped: a canceled order
        // never occupies a table. (Previously this also excluded COMPLETED,
        // which made paid tables wrongly show empty to area-restricted waiters
        // while the POS still showed them full.)
        if (areaIds.isNotEmpty) {
          ordersQuery.where((o) => o.status.equals('CANCELED').not());
        }
        ordersRaw = await ordersQuery.get();
      }
      final ordersMap = {for (final o in ordersRaw) o.id: o};

      // Batch: load all order products + components for those orders
      final activeOrderIds = ordersRaw.map((o) => o.id).toList();
      final allProducts = activeOrderIds.isEmpty
          ? <OrderProduct>[]
          : await (database.select(database.orderProducts)
              ..where((op) => op.orderId.isIn(activeOrderIds)))
              .get();

      final allOpIds = allProducts.map((p) => p.id).toList();
      final allComponents = allOpIds.isEmpty
          ? <OrderProductComponent>[]
          : await (database.select(database.orderProductComponents)
              ..where((c) => c.orderProductId.isIn(allOpIds)))
              .get();

      // Batch: the waiters holding those orders, for `orderWaiterName`.
      // Same batched shape as the areas above rather than a lookup per table —
      // a busy floor is 30+ tables and this endpoint is polled.
      final orderWaiterIds = ordersRaw
          .where((o) => o.waiterId != null)
          .map((o) => o.waiterId!)
          .toSet()
          .toList();
      final waitersRaw = orderWaiterIds.isEmpty
          ? <Waiter>[]
          : await (database.select(database.waiters)
                ..where((w) => w.id.isIn(orderWaiterIds)))
              .get();
      final waitersMap = {for (final w in waitersRaw) w.id: w};

      // Build lookup maps
      final productsByOrderId = <int, List<OrderProduct>>{};
      for (final p in allProducts) {
        productsByOrderId.putIfAbsent(p.orderId, () => []).add(p);
      }
      final componentsByOpId = <int, List<OrderProductComponent>>{};
      for (final c in allComponents) {
        componentsByOpId.putIfAbsent(c.orderProductId, () => []).add(c);
      }

      // Build table list
      final tableList = <Map<String, dynamic>>[];
      for (final table in tables) {
        final area = table.areaId != null ? areasMap[table.areaId] : null;
        final order = table.orderId != null ? ordersMap[table.orderId] : null;

        double totalAmount = 0.0;
        if (order != null) {
          for (final p in productsByOrderId[order.id] ?? const <OrderProduct>[]) {
            if (p.ticketId == null && lineIsOwed(p.state)) {
              totalAmount +=
                  _waiterLineTotal(p, componentsByOpId[p.id] ?? const []);
            }
          }
          totalAmount =
              applyOrderDiscount(totalAmount, order.discountPercentage);
        }

        // Who is serving this table, for the waiter app's "my tables" view.
        //
        // Named `orderWaiterId`, not `waiterId`: this endpoint's query param is
        // already `waiterId` and means the CALLER, so a bare name here would be
        // two different things spelled the same. It reads alongside `orderId` /
        // `orderCode`, which is what it belongs to.
        //
        // Null means "nobody's", in all three of its cases — a free table, an
        // order the cashier rang up at the till (`Orders.waiterId` is nullable),
        // and an older client that never sees the key. None of them is a
        // wildcard: a null must never make a table match every waiter.
        final orderWaiter =
            order?.waiterId != null ? waitersMap[order!.waiterId!] : null;

        tableList.add({
          'id': table.id,
          'name': table.name,
          'capacity': table.capacity,
          'areaId': table.areaId,
          'areaName': area?.name,
          'orderId': order?.id,
          'orderCode': order?.code,
          if (_ref.read(settingsProvider).showOrderNumberOnWaiter &&
              order?.sessionOrderNo != null)
            'orderNumber': order!.sessionOrderNo,
          'totalAmount': totalAmount,
          'orderWaiterId': order?.waiterId,
          'orderWaiterName': orderWaiter == null
              ? null
              : '${orderWaiter.firstName} ${orderWaiter.lastName ?? ''}'.trim(),
        });
      }

      return Response.ok(
        jsonEncode({'tables': tableList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterTables: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch tables', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/orders?waiterId=1&status=PENDING,ONHOLD&page=0&limit=20
  Future<Response> _waiterOrders(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final queryParams = request.url.queryParameters;
      final waiterIdStr = queryParams['waiterId'];
      final statusStr = queryParams['status'];
      final pageStr = queryParams['page'] ?? '0';
      final limitStr = queryParams['limit'] ?? '20';

      if (waiterIdStr == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final waiterId = int.tryParse(waiterIdStr);
      final page = int.tryParse(pageStr) ?? 0;
      final limit = int.tryParse(limitStr) ?? 20;

      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid waiterId'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Scope to the current session (the shift), not all-time. No session
      // open ⇒ no current orders.
      final sessionId = _currentWaiterSessionId();
      if (sessionId == null) {
        return Response.ok(
          jsonEncode({'orders': [], 'page': page, 'limit': limit, 'count': 0}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Build query
      var query = database.select(database.orders)
        ..where((o) => o.waiterId.equals(waiterId) & o.sessionId.equals(sessionId));

      // Filter by status if provided
      if (statusStr != null && statusStr.isNotEmpty) {
        final statuses = statusStr.split(',').map((s) => s.trim().toUpperCase()).toList();
        query = query..where((o) => o.status.isIn(statuses));
      }

      // Order by creation date descending
      query = query..orderBy([(o) => drift.OrderingTerm(expression: o.createdAt, mode: drift.OrderingMode.desc)]);

      // Pagination
      query = query..limit(limit, offset: page * limit);

      final orders = await query.get();

      if (orders.isEmpty) {
        return Response.ok(
          jsonEncode({'orders': [], 'page': page, 'limit': limit, 'count': 0}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Batch-load tables, products, and components in 3 queries
      final orderIds = orders.map((o) => o.id).toList();
      final tableIds = orders
          .where((o) => o.tableId != null)
          .map((o) => o.tableId!)
          .toSet()
          .toList();

      final tablesRaw = tableIds.isEmpty
          ? <AreaTable>[]
          : await (database.select(database.areaTables)
              ..where((t) => t.id.isIn(tableIds)))
              .get();
      final tablesMap = {for (final t in tablesRaw) t.id: t};

      final allProducts = await (database.select(database.orderProducts)
          ..where((op) => op.orderId.isIn(orderIds)))
          .get();

      final allOpIds = allProducts.map((p) => p.id).toList();
      final allComponents = allOpIds.isEmpty
          ? <OrderProductComponent>[]
          : await (database.select(database.orderProductComponents)
              ..where((c) => c.orderProductId.isIn(allOpIds)))
              .get();

      // Resolve display names for the line items (product + component names)
      // so the waiter app can render an itemised order / split-pay checklist.
      final productIds = allProducts.map((p) => p.productId).toSet().toList();
      final productNames = await _loadProductNames(database, productIds);
      final showKitchen =
          _ref.read(settingsProvider).waiterShowKitchenStatus;
      final componentIds =
          allComponents.map((c) => c.componentId).toSet().toList();
      final componentNames = await _loadComponentNames(database, componentIds);

      final productsByOrderId = <int, List<OrderProduct>>{};
      for (final p in allProducts) {
        productsByOrderId.putIfAbsent(p.orderId, () => []).add(p);
      }
      final componentsByOpId = <int, List<OrderProductComponent>>{};
      for (final c in allComponents) {
        componentsByOpId.putIfAbsent(c.orderProductId, () => []).add(c);
      }

      final orderList = <Map<String, dynamic>>[];
      final showOrderNo = _ref.read(settingsProvider).showOrderNumberOnWaiter;
      for (final order in orders) {
        final table = order.tableId != null ? tablesMap[order.tableId] : null;
        final products = productsByOrderId[order.id] ?? [];

        final money = WaiterOrderMoney.of(order, products, componentsByOpId,
            credit: await _splitCredit(order.id));
        final lineList = <Map<String, dynamic>>[];
        for (final p in products) {
          final lineComponents = componentsByOpId[p.id] ?? const [];
          final compList = <Map<String, dynamic>>[];
          for (final c in lineComponents) {
            compList.add({
              'id': c.id,
              'componentId': c.componentId,
              // The name AS SOLD, if it was captured at order time — a
              // deactivated (86'd) or since-deleted component can no longer
              // answer the live join below, and a deleted one answers with
              // nothing at all (`name: null` on the wire). Falls back to the
              // live join for rows written before this column existed.
              'name': c.name ?? componentNames[c.componentId],
              'quantity': c.quantity,
              'price': c.price,
            });
          }
          // Canonical line total (matches the POS) — components × quantity,
          // pre-discount already in unitaryPrice.
          final lineMoney = WaiterLineMoney.of(p, lineComponents);
          final item = lineMoney.net;
          final paid = p.ticketId != null;

          lineList.add({
            'id': p.id,
            'productId': p.productId,
            'name': productNames[p.productId] ?? 'Product #${p.productId}',
            'quantity': p.quantity,
            'unitaryPrice': p.unitaryPrice,
            'note': p.note,
            'courseNo': p.courseNo,
            'paid': paid,
            'lineTotal': item,
            'grossTotal': lineMoney.gross,
            'discountAmount': lineMoney.discount,
            'components': compList,
            ...waiterKitchenFields(p, enabled: showKitchen),
          });
        }

        orderList.add({
          'id': order.id,
          'code': order.code,
          if (showOrderNo && order.sessionOrderNo != null)
            'orderNumber': order.sessionOrderNo,
          'status': order.status,
          'type': order.type,
          'persons': order.persons,
          'tableId': order.tableId,
          'tableName': table?.name,
          ...money.toJson(),
          'productCount': products.length,
          'products': lineList,
          'createdAt': order.createdAt.toIso8601String(),
          'updatedAt': order.updatedAt.toIso8601String(),
        });
      }

      return Response.ok(
        jsonEncode({'orders': orderList, 'page': page, 'limit': limit, 'count': orderList.length}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterOrders: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch orders', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /waiters/orders - Create new order
  /// Body: { "waiterId": 1, "tableId": 5, "type": "DINE_IN", "persons": 2, "products": [...] }
  Future<Response> _waiterCreateOrder(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final waiterId = json['waiterId'] as int?;
      final tableId = json['tableId'] as int?;
      final type = json['type'] as String? ?? 'DINE_IN';
      final persons = json['persons'] as int? ?? 1;
      final products = json['products'] as List<dynamic>? ?? [];

      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Orders can only be raised while a cash session is OPEN and not paused
      // (the POS itself requires an open session to ring up). Rejects with
      // `no_open_session` or `session_paused` — see docs/waiter_api_errors.md.
      final sessionBlock = await _blockOrderCreationIfSessionUnavailable();
      if (sessionBlock != null) return sessionBlock;

      // Validate table for DINE_IN
      if (type == 'DINE_IN' && tableId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'tableId is required for DINE_IN orders'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify waiter exists + active
      final waiter = await (database.select(database.waiters)
            ..where((w) => w.id.equals(waiterId)))
          .getSingleOrNull();
      if (waiter == null || !waiter.isActive) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid or inactive waiter'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // For DINE_IN, ensure waiter is assigned to the table's area
      if (type == 'DINE_IN' && tableId != null) {
        final table = await (database.select(database.areaTables)
              ..where((t) => t.id.equals(tableId)))
            .getSingleOrNull();
        if (table == null) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Table not found'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
        if (table.areaId != null) {
          // A waiter with NO area assignments is "global" and may serve any
          // table — this mirrors GET /waiters/tables (_waiterTables), which
          // shows global waiters every table. Without this, a global waiter
          // can browse all tables but gets a 403 when creating an order on
          // any table that belongs to an area. Only area-restricted waiters
          // are checked against the specific table's area.
          final waiterAreas = await (database.select(database.waiterAreas)
                ..where((wa) => wa.waiterId.equals(waiterId)))
              .get();
          final isAreaRestricted = waiterAreas.isNotEmpty;
          final assignedToArea =
              waiterAreas.any((wa) => wa.areaId == table.areaId);
          if (isAreaRestricted && !assignedToArea) {
            return Response(
              403,
              body: jsonEncode({
                'error': 'Waiter not assigned to this table\'s area'
              }),
              headers: {'Content-Type': 'application/json'},
            );
          }
        }
      }
      // NOTE: the table-occupancy check ("already has another waiter's order")
      // is done INSIDE the transaction below, not here — otherwise two waiters
      // opening the same table at the same instant could both pass a pre-check
      // before either links the table (a TOCTOU race). See the transaction.

      // Generate a short uppercase alphanumeric order code (e.g. RGH7IE3H3LR),
      // verified unique against existing orders.
      final now = DateTime.now();
      final orderCode = await OrderRepository.uniqueOrderCode(database);

      // Create order. `source: 'WAITER'` lets the print-rule engine filter
      // this row out (or in) per cashier config — see [PrintRule.sources].
      // Initial status uses the SAME `AppSettings.defaultOrderStatus` as the
      // cashier "normal" flow (main_screen → OrderRepository.saveOrder), so a
      // waiter order defaults exactly like a POS-created one. The paid-on-
      // create branch below still bumps it to `paidOrderDefaultStatus`.
      //
      // `sessionId` carries the active cash session at create-time so the
      // order lands inside the current Z-report scope — without this the
      // cashier-side `WaiterProfileDialog` (which filters
      // `orders.sessionId == currentSession.id`) excludes every waiter
      // order. Null when no session is open is fine; the profile dialog
      // falls back to a today-window in that case.
      final settings = _ref.read(settingsProvider);
      final session = _ref.read(currentSessionProvider);
      final waiterOrderStatus = settings.defaultOrderStatus;
      // Product line state mirrors saveOrder: ONHOLD orders keep their lines
      // ONHOLD (so they never reach the KDS), everything else starts at the
      // configured default KDS state.
      final waiterItemState =
          waiterOrderStatus == 'ONHOLD' ? 'ONHOLD' : settings.defaultKdsState;
      // Attribute the order to whoever is logged into the POS right now, so a
      // waiter order behaves like a normal POS order created by that cashier:
      // `createdBy`/`takenBy` reference `users.id` and drive the "Cashier"
      // line on the ticket + the Orders Management attribution. The `waiterId`
      // column above still records which waiter raised it (for the waiter
      // app's own order list / dashboard). Null when no cashier is logged in.
      final posUser = _ref.read(currentUserProvider);
      // z_day from THIS order's session (the same `session` used for
      // sessionId below) so it cannot drift from the shift collecting it.
      // Through the resolver rather than `zDayForSession` directly, so a
      // session belonging to a Z takes the Z's opening day and every session
      // in one shift agrees.
      final waiterZDay =
          await ZDayResolver(database).forSessionOrCurrent(session?.id) ??
              _ref.read(currentZDayProvider);
      // Everything below is ONE transaction so it commits atomically: no
      // half-written order is ever visible to a concurrent reader, and — because
      // drift serializes transactions on the single connection — the occupancy
      // re-check and the table link commit together, so two waiters can't
      // double-book the same table. A conflict throws `_WaiterConflict`, which
      // rolls the whole thing back and is turned into a 409 below.
      late final int orderId;
      try {
        orderId = await database.transaction<int>(() async {
          // Race-safe table-occupancy check INSIDE the tx (see note above).
          if (type == 'DINE_IN' && tableId != null) {
            final t = await (database.select(database.areaTables)
                  ..where((x) => x.id.equals(tableId)))
                .getSingleOrNull();
            if (t != null && t.orderId != null) {
              final existing = await (database.select(database.orders)
                    ..where((o) => o.id.equals(t.orderId!)))
                  .getSingleOrNull();
              // Whether the sitting order is still LIVE.
              //
              // This used to read `existing.status != 'COMPLETED'`, but orders
              // are born COMPLETED in this app (the cloud-terminal model — the
              // kitchen flow lives on the products). That made the condition
              // always false, so the guard never fired: two waiters could open
              // orders on the same table and the second silently overwrote
              // `area_tables.orderId`, orphaning the first order's table link.
              //
              // Liveness is therefore judged the way the rest of the POS judges
              // it: an order is done when it is cancelled, or when every line has
              // been paid for.
              var stillLive = false;
              if (existing != null) {
                final lines = await (database.select(database.orderProducts)
                      ..where((op) => op.orderId.equals(existing.id)))
                    .get();
                stillLive = orderBlocksTable(
                  orderStatus: existing.status,
                  lineStates: lines.map((l) => settlementState(l.state, l.ticketId)),
                );
              }
              // A live order blocks the table, whoever raised it.
              //
              // This used to exempt the waiter who already held it
              // (`existing.waiterId != waiterId`), on the assumption that a
              // waiter would not open the same table twice. They do: the same
              // waiter signed in on two phones opens two, the second silently
              // overwrote `area_tables.orderId`, and the first order was
              // orphaned — off the floor plan, with food already sent.
              //
              // Told apart only so the tablet can respond usefully: its own
              // order is one it can open and add to, another's is not.
              if (existing != null && stillLive) {
                if (existing.waiterId == waiterId) {
                  throw _WaiterConflict(
                      409,
                      'table_already_has_your_order',
                      'You already have an open order on this table. Open it and add to it instead of starting a second one.',
                      orderCode: existing.code);
                }
                String owner = 'another waiter';
                if (existing.waiterId != null) {
                  final other = await (database.select(database.waiters)
                        ..where((w) => w.id.equals(existing.waiterId!)))
                      .getSingleOrNull();
                  if (other != null) {
                    owner = '${other.firstName} ${other.lastName ?? ''}'.trim();
                  }
                } else {
                  owner = 'the cashier';
                }
                throw _WaiterConflict(
                    409,
                    'table_taken_by_other_waiter',
                    'This table already has an open order by $owner. It must be handled by them or the cashier first.',
                    orderCode: existing.code);
              }
            }
          }

          final newOrderId = await database.into(database.orders).insert(
            OrdersCompanion.insert(
              code: orderCode,
              status: drift.Value(waiterOrderStatus),
              type: drift.Value(type),
              persons: drift.Value(persons),
              tableId: drift.Value(tableId),
              source: const drift.Value('WAITER'),
              waiterId: drift.Value(waiterId),
              createdBy: drift.Value(posUser?.id),
              takenBy: drift.Value(posUser?.id),
              sessionId: drift.Value(session?.id),
              sessionOrderNo: drift.Value(await database.nextSessionOrderNo(
                  session?.id,
                  mode: _ref.read(settingsProvider).orderNumberResetMode)),
              zDay: drift.Value(waiterZDay),
              createdAt: drift.Value(now),
              updatedAt: drift.Value(now),
            ),
          );

          // Insert products
          for (final productJson in products) {
            await _insertWaiterLine(
              database,
              newOrderId,
              (productJson as Map).cast<String, dynamic>(),
              state: waiterItemState,
              zDay: waiterZDay,
            );
          }

          // Link the table INSIDE the tx so the occupancy check above and this
          // write commit atomically — the guarantee against double-booking.
          if (tableId != null) {
            await (database.update(database.areaTables)
                  ..where((t) => t.id.equals(tableId)))
                .write(AreaTablesCompanion(orderId: drift.Value(newOrderId)));
          }

          return newOrderId;
        });
      } on _WaiterConflict catch (e) {
        return e.toResponse();
      }

      // Waiter orders are ALWAYS created open/unpaid. All payment happens on
      // the POS — the cashier settles waiter orders via the waiter
      // settlement / profile dialog. There is no waiter-side payment.

      // Order-level log (visible in order details) + cross-cutting
      // activity log (visible in the Logs screen). The order log carries
      // the waiter's name so the audit trail reads naturally; the activity
      // log fires through the new `logWaiterOrderCreated` convenience that
      // skips the users-table lookup (waiter ids live in `waiters`).
      final waiterFullName =
          '${waiter.firstName} ${waiter.lastName ?? ''}'.trim();
      await logService.logOrderCreated(
          orderId, 'Order created by waiter $waiterFullName');
      // ignore: unawaited_futures
      _ref.read(activityLogServiceProvider).logWaiterOrderCreated(
            waiterName: waiterFullName,
            orderCode: orderCode,
          );

      // Fire the configured auto-prints (order ticket + KDS) in the background
      // so the waiter app's POST doesn't block on a slow / dead printer. The
      // pipeline reads the just-saved row via OrderRepository, then gates each
      // output via shouldPrint(... source: 'WAITER') — so the cashier's print
      // rules (incl. the "sources" checkboxes in `printers_management_screen`)
      // decide whether this waiter order produces paper.
      // ignore: unawaited_futures
      _firePrintsForWaiterOrder(orderId, posUser?.firstName);

      // Immediate auto-sync when online. Mirrors the cashier-side path in
      // `main_screen.dart` so a default-paid waiter order doesn't sit
      // unsynced for up to a `SyncJobService` cycle (default 5 min). The
      // row already has `isSynced=false`, so the periodic sync is the
      // automatic fallback when offline / when this call fails.
      try {
        final isOnline = _ref.read(lastKnownOnlineStatusProvider);
        if (isOnline) {
          // ignore: unawaited_futures
          _ref
              .read(syncManagerProvider.notifier)
              .autoSyncOrder(orderId)
              .catchError((Object e) {
            Logger.instance.warning('Waiter order autoSync failed: $e');
            return false;
          });
        }
      } catch (e) {
        Logger.instance.warning('Waiter order autoSync kickoff failed: $e');
      }

      final int? orderNumber =
          _ref.read(settingsProvider).showOrderNumberOnWaiter
              ? (await (database.select(database.orders)
                        ..where((o) => o.id.equals(orderId)))
                      .getSingleOrNull())
                  ?.sessionOrderNo
              : null;

      return Response(
        201,
        body: jsonEncode({
          'id': orderId,
          'code': orderCode,
          if (orderNumber != null) 'orderNumber': orderNumber,
          'message': 'Order created successfully',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterCreateOrder: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create order', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Background auto-print for a freshly created waiter order. Reads the
  /// saved row back as a [CurrentOrder] (so the print formatters see the
  /// same shape they do on the cashier side), then fires order ticket and
  /// KDS prints — each gated by [PrintingService.shouldPrint] with
  /// `source: 'WAITER'`. The cashier's print-rule config (see
  /// `printers_management_screen.dart`) decides whether any of these
  /// actually produce paper.
  ///
  /// [cashierName] is the POS user logged in when the waiter order arrived —
  /// the order is attributed to them (`createdBy`), so the ticket shows the
  /// standard "Cashier" line exactly like a POS-created order. There is no
  /// special waiter-only ticket.
  ///
  /// All exceptions are swallowed: the order is already persisted, the
  /// waiter app already got its 201, and a printer outage must not crash
  /// the server isolate.
  Future<void> _firePrintsForWaiterOrder(
      int orderId, String? cashierName) async {
    try {
      // Master switch: when off, NO waiter action prints automatically —
      // order ticket and KDS are suppressed in one place. Explicit reprints
      // (`.../print`) still work.
      if (!_ref.read(settingsProvider).printWaiterPaper) return;

      final orderRepo = _ref.read(orderRepositoryProvider);
      final printingService = _ref.read(printingServiceProvider);
      final currentOrder = await orderRepo.getOrderById(orderId);
      if (currentOrder == null) {
        Logger.instance.warning('_firePrintsForWaiterOrder: order $orderId not found post-insert');
        return;
      }
      final hasTable = currentOrder.tableId != null;

      // Same store-identity header the cashier passes (see main_screen.dart
      // proceed-flow). Without these the ticket prints with no business
      // header and looks unlike the standard cashier ticket.
      final prefs = _ref.read(sharedPreferencesProvider);
      final storeName = prefs.getString('business_name');
      final storeAddress = prefs.getString('business_address');
      final storePhone = prefs.getString('business_phone');

      // Global shortcut: when the cashier turned off "print waiter order
      // ticket" in Settings → Order Defaults, skip the order-ticket auto-
      // print entirely (KDS still fires below). Saves paper without the
      // cashier needing to maintain per-rule Sources filters.
      final printOrderTicket =
          _ref.read(settingsProvider).printWaiterOrderTicket;
      if (printOrderTicket &&
          printingService.shouldPrint(
            PrintOutput.orderTicket,
            orderType: currentOrder.type,
            hasTable: hasTable,
            source: 'WAITER',
          )) {
        try {
          // Print exactly like a POS order created by the current cashier:
          // standard "Cashier" line + the same store header.
          await printingService.printOrderReceipt(
            order: currentOrder,
            cashierName: cashierName,
            storeName: storeName,
            storeAddress: storeAddress,
            storePhone: storePhone,
          );
        } catch (e) {
          Logger.instance.warning('Waiter orderTicket print failed: $e');
        }
      }

      if (printingService.config.kdsEnabled &&
          printingService.shouldPrint(
            PrintOutput.kds,
            orderType: currentOrder.type,
            hasTable: hasTable,
            source: 'WAITER',
          )) {
        try {
          await printingService.printKdsTicket(
            order: currentOrder,
            cashierName: cashierName,
          );
        } catch (e) {
          Logger.instance.warning('Waiter KDS print failed: $e');
        }
      }

    } catch (e, st) {
      Logger.instance.error('_firePrintsForWaiterOrder failed: $e\n$st');
    }
  }

  /// Background KDS print after a waiter appends a product to an existing
  /// order. Prints in `modificationsOnly` mode so ONLY the just-added,
  /// not-yet-printed items reach the kitchen — same behaviour as the
  /// cashier-side "add to open order" flow. Gated by the same `kds` print
  /// rule (`source: 'WAITER'`). [cashierName] is the current POS user, so the
  /// kitchen ticket carries the standard cashier line. Exceptions swallowed:
  /// the product is already saved and the waiter app already got its 200.
  /// [roundIsComplete] prints at once instead of waiting.
  ///
  /// The wait exists only because N single `add-product` calls carry no signal
  /// for where a round ends, so the POS has to guess with a timer. A batch
  /// (`add-products`) IS that signal — the client has said "this is the round"
  /// — so waiting on it would be a delay bought for nothing, which is exactly
  /// what the endpoint was added to remove.
  void _fireKdsForWaiterAddedProduct(int orderId, String? cashierName,
      {bool roundIsComplete = false}) {
    // Master switch (see [_firePrintsForWaiterOrder]): off = no waiter paper.
    if (!_ref.read(settingsProvider).printWaiterPaper) return;

    final wait =
        roundIsComplete ? 0 : _ref.read(settingsProvider).waiterKdsBatchSeconds;
    if (wait <= 0) {
      // Drop anything already waiting on this order. Its lines are unprinted,
      // so the print below carries them; leaving the timer alive would only
      // wake up later to find nothing left to say.
      _pendingWaiterKds.remove(orderId)?.cancel();
      // ignore: unawaited_futures
      _printWaiterKdsNow(orderId, cashierName);
      return;
    }

    // Group the run. The waiter app has no cart when adding to an open table:
    // its add-product screen fires one product and navigates back to the menu,
    // so three items arrive as three calls, tens of seconds apart, and each one
    // used to cut its own ticket. Nothing on the wire says "that was the last
    // one", so the ticket waits [wait] seconds for a neighbour and every new
    // add restarts the wait. The print itself is modifications-only, so
    // whatever accumulated lands on a single ticket.
    _pendingWaiterKds.remove(orderId)?.cancel();
    _pendingWaiterKds[orderId] = Timer(Duration(seconds: wait), () {
      _pendingWaiterKds.remove(orderId);
      // ignore: unawaited_futures
      _printWaiterKdsNow(orderId, cashierName);
    });
  }

  /// How many orders currently have a kitchen ticket waiting for more items.
  /// One pending entry after a run of adds is the whole point: it means those
  /// adds will land on a single ticket rather than one each.
  @visibleForTesting
  int get pendingWaiterKdsCount => _pendingWaiterKds.length;

  /// Fire every waiting kitchen ticket at once and forget the timers.
  Future<void> _flushPendingWaiterKds() async {
    if (_pendingWaiterKds.isEmpty) return;
    final due = _pendingWaiterKds.keys.toList();
    for (final timer in _pendingWaiterKds.values) {
      timer.cancel();
    }
    _pendingWaiterKds.clear();
    for (final orderId in due) {
      await _printWaiterKdsNow(orderId, null);
    }
  }

  Future<void> _printWaiterKdsNow(int orderId, String? cashierName) async {
    try {
      // Re-checked at fire time, not at queue time: the cashier may have turned
      // waiter paper off while this was waiting.
      if (!_ref.read(settingsProvider).printWaiterPaper) return;

      final printingService = _ref.read(printingServiceProvider);
      if (!printingService.config.kdsEnabled) return;
      final orderRepo = _ref.read(orderRepositoryProvider);
      final currentOrder = await orderRepo.getOrderById(orderId);
      if (currentOrder == null) {
        Logger.instance.warning('_printWaiterKdsNow: order $orderId not found');
        return;
      }
      if (!printingService.shouldPrint(
        PrintOutput.kds,
        orderType: currentOrder.type,
        hasTable: currentOrder.tableId != null,
        source: 'WAITER',
      )) {
        return;
      }
      await printingService.printKdsTicket(
        order: currentOrder,
        cashierName: cashierName,
        mode: KdsPrintMode.modificationsOnly,
      );
    } catch (e, st) {
      Logger.instance.error('_fireKdsForWaiterAddedProduct failed: $e\n$st');
    }
  }

  /// Insert one waiter-supplied line, with its options, into [orderId].
  ///
  /// Shared by order-create and batch-add so the two cannot drift: price, TVA
  /// and pre-discount are read from the CATALOGUE here, never taken from the
  /// client — a tablet is not allowed to name its own price. Returns the new
  /// `order_products.id`, or null when the product id is unknown, which the
  /// callers report rather than failing a whole round over.
  Future<int?> _insertWaiterLine(
    AppDatabase database,
    int orderId,
    Map<String, dynamic> productJson, {
    required String state,
    DateTime? zDay,
  }) async {
    final productId = productJson['productId'] as int;
    final variantId = productJson['variantId'] as int?;
    final quantity = (productJson['quantity'] as num?)?.toDouble() ?? 1.0;
    final productNote = productJson['note'] as String?;
    // Course (1 entrée, 2 plat, 3 dessert), optional and normally absent — the
    // waiter app only sends it when the shop works in courses. Omitted or null
    // means "no course", which is the state every line has until somebody
    // chooses one.
    //
    // Normalised rather than taken as given: a client promising to send only
    // 1-3 is a promise living in the client's code, not in this contract, and
    // the next build of it is not this build. Anything else becomes null here.
    final productCourse = normalizeCourseNo(productJson['courseNo']);
    final components = productJson['components'] as List<dynamic>? ?? [];

    final product = await (database.select(database.products)
          ..where((p) => p.id.equals(productId)))
        .getSingleOrNull();
    if (product == null) return null;

    // Authoritative price/TVA from the DB (variant overrides product).
    double unitPrice = product.finalPrice;
    double unitTva = product.tvaAmount;
    double unitDiscount = product.discountAmount;
    if (variantId != null) {
      final variant = await (database.select(database.productVariants)
            ..where((v) => v.id.equals(variantId)))
          .getSingleOrNull();
      if (variant != null) {
        unitPrice = variant.price;
        unitTva = variant.tvaAmount;
        unitDiscount = 0.0; // Variants typically have no pre-discount
      }
    }

    // Checked before anything is written: a refusal throws, and the caller's
    // transaction takes the rest of the round back with it.
    final options = await _priceWaiterOptions(database, productId, components);

    final orderProductId = await database.into(database.orderProducts).insert(
          OrderProductsCompanion.insert(
            orderId: orderId,
            productId: productId,
            variantId: drift.Value(variantId),
            quantity: drift.Value(quantity),
            unitaryPrice: unitPrice,
            cost: drift.Value(await ProductCostResolver(database)
                .resolve(productId: productId, variantId: variantId)),
            unitaryDiscount: drift.Value(unitDiscount),
            unitaryTva: drift.Value(unitTva),
            note: drift.Value(productNote),
            courseNo: drift.Value(productCourse),
            state: drift.Value(state),
            zDay: drift.Value(zDay),
          ),
        );

    for (final option in options) {
      await database.into(database.orderProductComponents).insert(
            OrderProductComponentsCompanion.insert(
              orderProductId: orderProductId,
              componentId: option.componentId,
              quantity: drift.Value(option.quantity),
              price: drift.Value(option.price),
              isSpecial: const drift.Value(false),
              name: drift.Value(option.name),
            ),
          );
    }

    return orderProductId;
  }

  /// The option rows for a waiter line, checked and priced as the till's
  /// product dialog would: only options this product offers, only in groups
  /// the selection makes visible, within each group's min/max, at the
  /// catalogue price with the group's free allowance applied. Any `price` the
  /// tablet sent is ignored. Throws [_WaiterConflict] (400) when the selection
  /// is not one the till would accept.
  ///
  /// Entries are summed per component first, so a tablet that already split
  /// a component into a free and a charged row gets the same result as one
  /// that sent it once. Zero-quantity entries are kept as zero rows.
  Future<List<_PricedOption>> _priceWaiterOptions(
      AppDatabase database, int productId, List<dynamic> components) async {
    if (components.isEmpty) return const [];

    final links = await (database.select(database.productComponents)
          ..where((pc) => pc.productId.equals(productId)))
        .get();
    final linkByComponent = {for (final l in links) l.componentId: l};
    final offered = links.isEmpty
        ? const <Component>[]
        : await (database.select(database.components)
              ..where((c) =>
                  c.id.isIn(linkByComponent.keys) & c.isActive.equals(true)))
            .get();
    final catalogue = {
      for (final c in offered)
        c.id: linkByComponent[c.id]!.defaultPrice ?? c.price,
    };
    final groupOf = {for (final c in offered) c.id: c.componentGroupId};
    final nameOf = {for (final c in offered) c.id: c.name};

    final picked = <int, int>{};
    final zeroRows = <int>[];
    for (final raw in components) {
      final json = (raw as Map).cast<String, dynamic>();
      final id = json['componentId'] as int;
      final qty = json['quantity'] as int? ?? 1;
      if (qty > 0) {
        picked[id] = (picked[id] ?? 0) + qty;
      } else if (catalogue.containsKey(id) && !zeroRows.contains(id)) {
        zeroRows.add(id);
      }
    }

    final rules = await loadComponentGroupRules(database, productId);
    final pricing = priceOptions(
      picked: picked,
      catalogue: catalogue,
      groupOf: groupOf,
      rules: rules,
      maxEach: {
        for (final c in offered)
          c.id: maxUnitsOf(
              rules[c.componentGroupId], linkByComponent[c.id]!.maxQuantity),
      },
    );
    final problem = pricing.problem;
    if (problem != null) {
      final group = pricing.group;
      final (code, message) = switch (problem) {
        OptionProblem.notOffered => (
            'option_not_offered',
            'Option ${pricing.componentId} is not available on product $productId.'
          ),
        OptionProblem.tooManyOfOne => (
            'option_too_many',
            'Too many of option ${pricing.componentId} on product $productId.'
          ),
        OptionProblem.hiddenGroup => (
            'option_group_hidden',
            'Option ${pricing.componentId} belongs to a group this selection does not show.'
          ),
        OptionProblem.tooFew => (
            'option_group_too_few',
            'Group "${group?.name}" needs at least ${group?.minSelection} option(s).'
          ),
        OptionProblem.tooMany => (
            'option_group_too_many',
            'Group "${group?.name}" allows at most ${group?.maxSelection} option(s).'
          ),
      };
      throw _WaiterConflict(400, code, message, details: {
        'productId': productId,
        if (pricing.componentId != null) 'componentId': pricing.componentId,
        if (group != null) 'componentGroupId': group.groupId,
        if (group != null) 'minSelection': group.minSelection,
        if (group?.maxSelection != null) 'maxSelection': group!.maxSelection,
      });
    }

    return [
      for (final line in pricing.lines)
        (
          componentId: line.componentId,
          quantity: line.quantity,
          price: line.unitPrice,
          name: nameOf[line.componentId],
        ),
      for (final id in zeroRows)
        if (!picked.containsKey(id))
          (componentId: id, quantity: 0, price: 0.0, name: nameOf[id]),
    ];
  }

  /// PUT /waiters/orders/`<code>`/add-products — add SEVERAL products at once.
  ///
  /// The batch twin of [_waiterAddProductToOrder], which is left exactly as it
  /// was: older waiter builds keep working, untouched.
  ///
  /// Body: `{ "waiterId": int, "products": [ ... ] }` — each entry
  /// `{ productId, variantId?, quantity?, note?, courseNo?, components?[] }`,
  /// the same shape as the `products` array of `POST /waiters/orders`.
  ///
  /// Why it exists: the kitchen should get ONE ticket per round of ordering.
  /// Sent as N single calls there is nothing on the wire saying where the round
  /// ends, so the POS has to guess with a timer
  /// ([AppSettings.waiterKdsBatchSeconds]). One call IS the round, so the
  /// ticket is exact and immediate — a shop whose waiters are all on a
  /// batching build can set that wait to 0.
  ///
  /// Every line commits in ONE transaction: a half-added round is not something
  /// a waiter can see, let alone correct. An unknown product id does not fail
  /// the call — it comes back in `skipped` so the tablet can say what it lost.
  ///
  /// `skipped` entries carry the INDEX into the request's `products` array as
  /// well as the product id, because the id alone cannot identify a line: a
  /// cart legitimately holds two entries of the same product that differ by
  /// variant, options or course, and they ring up differently. Told only the
  /// id, a client cannot know which of its two lines to keep for retry.
  ///
  /// Responses:
  ///   - 200 `{ message, added: int, skipped: [ { index, productId } ] }`
  ///   - 400 bad body / nothing usable, 403 wrong owner, 404 no such order
  Future<Response> _waiterAddProductsToOrder(
      Request request, String code) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final waiterId = json['waiterId'] as int?;
      final products = json['products'] as List<dynamic>? ?? const [];

      if (waiterId == null || products.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'waiterId and a non-empty products array are required'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final order = await (database.select(database.orders)
            ..where((o) => o.code.equals(code)))
          .getSingleOrNull();
      if (order == null) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (order.waiterId != waiterId) {
        return Response(
          403,
          body: jsonEncode({'error': 'Not authorized to modify this order'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final skipped = <Map<String, dynamic>>[];
      var added = 0;
      try {
        await database.transaction(() async {
          for (var index = 0; index < products.length; index++) {
            final map = (products[index] as Map).cast<String, dynamic>();
            final int? inserted;
            try {
              inserted = await _insertWaiterLine(
                database,
                order.id,
                map,
                // Matches the single-product route exactly.
                state: 'PENDING',
                // Inherited from the order, so a round lands in the same Z as
                // the order it was added to.
                zDay: order.zDay,
              );
            } on _WaiterConflict catch (e) {
              // Refused options fail the whole round, which the transaction
              // takes back; the index says which line to fix.
              throw _WaiterConflict(e.status, e.code, e.message,
                  details: {...e.details, 'index': index});
            }
          if (inserted == null) {
            skipped.add({
              'index': index,
              'productId': map['productId'] as int,
            });
          } else {
            added++;
          }
        }

        // `isSynced: false` is the load-bearing half — see the single-product
        // route for why leaving it true loses the lines on the next delta.
        await (database.update(database.orders)
              ..where((o) => o.id.equals(order.id)))
            .write(OrdersCompanion(
          updatedAt: drift.Value(DateTime.now()),
          isSynced: const drift.Value(false),
        ));
        });
      } on _WaiterConflict catch (e) {
        return e.toResponse();
      }

      if (added == 0) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'no_known_products',
            'message': 'None of the products sent exist in the catalogue',
            'skipped': skipped,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final waiterRow = await (database.select(database.waiters)
            ..where((w) => w.id.equals(waiterId)))
          .getSingleOrNull();
      final waiterFullName = waiterRow == null
          ? 'waiter #$waiterId'
          : '${waiterRow.firstName} ${waiterRow.lastName ?? ''}'.trim();
      await logService.logOrderUpdated(
          order.id, '$added product(s) added by waiter $waiterFullName');
      // ignore: unawaited_futures
      _ref.read(activityLogServiceProvider).logWaiterProductAdded(
            waiterName: waiterFullName,
            productName: '$added product(s)',
            orderCode: code,
          );

      // ONE ticket for the whole round, and immediately: this call is itself
      // the statement that the round is finished, so there is nothing to wait
      // for. A single-product add still gets the grouping window.
      final posUser = _ref.read(currentUserProvider);
      _fireKdsForWaiterAddedProduct(order.id, posUser?.firstName,
          roundIsComplete: true);

      _autoSyncWaiterOrder(order.id, 'add-products');

      return Response.ok(
        jsonEncode({
          'message': 'Products added to order successfully',
          'added': added,
          'skipped': skipped,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterAddProductsToOrder: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode(
            {'error': 'Failed to add products', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Batch-load product display names for the given product ids.
  Future<Map<int, String>> _loadProductNames(
      AppDatabase database, List<int> ids) async {
    if (ids.isEmpty) return {};
    final rows = await (database.select(database.products)
          ..where((p) => p.id.isIn(ids)))
        .get();
    return {for (final r in rows) r.id: r.name};
  }

  /// Batch-load component display names for the given component ids.
  Future<Map<int, String>> _loadComponentNames(
      AppDatabase database, List<int> ids) async {
    if (ids.isEmpty) return {};
    final rows = await (database.select(database.components)
          ..where((c) => c.id.isIn(ids)))
        .get();
    return {for (final r in rows) r.id: r.name};
  }

  /// GET /waiters/orders/<code>?waiterId=int — full detail for a single order,
  /// including its itemised line list (with `order_products.id` per line, so
  /// the waiter app can drive split-pay). Ownership is enforced: the order's
  /// `waiter_id` must match the `waiterId` query param, else 403.
  ///
  /// Returns the same per-order shape as `GET /waiters/orders` (with the
  /// `products` array + `balanceAmount`).
  Future<Response> _waiterOrderDetail(Request request, String code) async {
    try {
      final database = _ref.read(databaseProvider);
      final waiterIdStr = request.url.queryParameters['waiterId'];
      final waiterId = waiterIdStr == null ? null : int.tryParse(waiterIdStr);
      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final order = await (database.select(database.orders)
            ..where((o) => o.code.equals(code)))
          .getSingleOrNull();
      if (order == null) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (order.waiterId != waiterId) {
        return Response(
          403,
          body: jsonEncode({'error': 'Not authorized to view this order'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final table = order.tableId != null
          ? await (database.select(database.areaTables)
                ..where((t) => t.id.equals(order.tableId!)))
              .getSingleOrNull()
          : null;

      final products = await (database.select(database.orderProducts)
            ..where((op) => op.orderId.equals(order.id)))
          .get();
      final opIds = products.map((p) => p.id).toList();
      final components = opIds.isEmpty
          ? <OrderProductComponent>[]
          : await (database.select(database.orderProductComponents)
                ..where((c) => c.orderProductId.isIn(opIds)))
              .get();
      final componentsByOpId = <int, List<OrderProductComponent>>{};
      for (final c in components) {
        componentsByOpId.putIfAbsent(c.orderProductId, () => []).add(c);
      }

      final productNames = await _loadProductNames(
          database, products.map((p) => p.productId).toSet().toList());
      final showKitchen =
          _ref.read(settingsProvider).waiterShowKitchenStatus;
      final componentNames = await _loadComponentNames(
          database, components.map((c) => c.componentId).toSet().toList());

      final money = WaiterOrderMoney.of(order, products, componentsByOpId,
          credit: await _splitCredit(order.id));
      final lineList = <Map<String, dynamic>>[];
      for (final p in products) {
        final lineComponents = componentsByOpId[p.id] ?? const [];
        final compList = <Map<String, dynamic>>[];
        for (final c in lineComponents) {
          compList.add({
            'id': c.id,
            'componentId': c.componentId,
            // The name AS SOLD, if it was captured at order time — a
            // deactivated (86'd) or since-deleted component can no longer
            // answer the live join below, and a deleted one answers with
            // nothing at all (`name: null` on the wire). Falls back to the
            // live join for rows written before this column existed.
            'name': c.name ?? componentNames[c.componentId],
            'quantity': c.quantity,
            'price': c.price,
          });
        }
        // Canonical line total (matches the POS) — components × quantity,
        // pre-discount already in unitaryPrice.
        final lineMoney = WaiterLineMoney.of(p, lineComponents);
        final item = lineMoney.net;
        final paid = p.ticketId != null;

        lineList.add({
          'id': p.id,
          'productId': p.productId,
          'name': productNames[p.productId] ?? 'Product #${p.productId}',
          'quantity': p.quantity,
          'unitaryPrice': p.unitaryPrice,
          'note': p.note,
          'courseNo': p.courseNo,
          'paid': paid,
          'lineTotal': item,
          'grossTotal': lineMoney.gross,
          'discountAmount': lineMoney.discount,
          'components': compList,
          ...waiterKitchenFields(p, enabled: showKitchen),
        });
      }

      return Response.ok(
        jsonEncode({
          'id': order.id,
          'code': order.code,
          if (_ref.read(settingsProvider).showOrderNumberOnWaiter &&
              order.sessionOrderNo != null)
            'orderNumber': order.sessionOrderNo,
          'status': order.status,
          'type': order.type,
          'persons': order.persons,
          'tableId': order.tableId,
          'tableName': table?.name,
          ...money.toJson(),
          'productCount': products.length,
          'products': lineList,
          'createdAt': order.createdAt.toIso8601String(),
          'updatedAt': order.updatedAt.toIso8601String(),
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      Logger.instance.error('_waiterOrderDetail failed: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode(
            {'error': 'Failed to fetch order', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /waiters/orders/<code>/print — on-demand (re)print of an order's
  /// ticket from the waiter app.
  ///
  /// Body: `{ "waiterId": int, "kds"?: bool }`
  ///   - `waiterId` (required): must own the order, else 403.
  ///   - `kds` (optional, default false): also (re)print the kitchen ticket,
  ///     in FULL mode (every item) — a reprint must not depend on the
  ///     "modifications only" cursor, which could emit nothing.
  ///
  /// Unlike the auto-print at creation, this is an explicit operator action,
  /// so it BYPASSES the `shouldPrint` rule/source gate (mirrors the
  /// cashier-side reprints). The order ticket carries the "Waiter:" line via
  /// `order.waiterName`, so no cashier name is passed.
  ///
  /// Responses:
  ///   - 200 `{ printed: true, outputs: {...} }`  — at least one output printed
  ///   - 503 `{ printed: false, outputs: {...} }` — printer offline/disabled
  ///   - 400 / 403 / 404 for bad input / wrong owner / missing order
  Future<Response> _waiterPrintOrder(Request request, String code) async {
    try {
      final database = _ref.read(databaseProvider);
      final body = await request.readAsString();
      final json = body.isNotEmpty
          ? jsonDecode(body) as Map<String, dynamic>
          : <String, dynamic>{};
      final waiterId = json['waiterId'] as int?;
      final alsoKds = json['kds'] as bool? ?? false;

      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final order = await (database.select(database.orders)
            ..where((o) => o.code.equals(code)))
          .getSingleOrNull();
      if (order == null) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (order.waiterId != waiterId) {
        return Response(
          403,
          body: jsonEncode({'error': 'Not authorized to print this order'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final printingService = _ref.read(printingServiceProvider);
      if (!printingService.config.printingEnabled) {
        return Response(
          503,
          body: jsonEncode({'error': 'printing_disabled', 'printed': false}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final orderRepo = _ref.read(orderRepositoryProvider);
      final currentOrder = await orderRepo.getOrderByCode(code);
      if (currentOrder == null) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to load order'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Same store-identity header as the cashier ticket / the create-time
      // auto-print, so a reprint is byte-for-byte the standard ticket.
      final prefs = _ref.read(sharedPreferencesProvider);
      final storeName = prefs.getString('business_name');
      final storeAddress = prefs.getString('business_address');
      final storePhone = prefs.getString('business_phone');

      // Cashier line = the POS user the order was attributed to at creation
      // (`createdBy`), so a reprint matches the original ticket.
      String? cashierName;
      if (order.createdBy != null) {
        final u = await (database.select(database.users)
              ..where((x) => x.id.equals(order.createdBy!)))
            .getSingleOrNull();
        cashierName = u?.firstName;
      }

      final outputs = <String, bool>{};
      try {
        outputs['orderTicket'] = await printingService.printOrderReceipt(
          order: currentOrder,
          cashierName: cashierName,
          storeName: storeName,
          storeAddress: storeAddress,
          storePhone: storePhone,
        );
      } catch (e) {
        Logger.instance.warning('Waiter reprint orderTicket failed: $e');
        outputs['orderTicket'] = false;
      }

      if (alsoKds && printingService.config.kdsEnabled) {
        try {
          outputs['kds'] = await printingService.printKdsTicket(
            order: currentOrder,
            cashierName: cashierName,
            mode: KdsPrintMode.full,
          );
        } catch (e) {
          Logger.instance.warning('Waiter reprint KDS failed: $e');
          outputs['kds'] = false;
        }
      }

      final anyPrinted = outputs.values.any((v) => v);
      return Response(
        anyPrinted ? 200 : 503,
        body: jsonEncode({'printed': anyPrinted, 'outputs': outputs}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      Logger.instance.error('_waiterPrintOrder failed: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to print', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Whether [waiterId] may act on [table]. Global waiters (no area
  /// assignments) may use any table; area-restricted waiters only tables in
  /// their assigned areas. A table with no area is open to everyone. Mirrors
  /// the ownership model in [_waiterCreateOrder].
  Future<bool> _waiterMayServeTable(
      AppDatabase db, int waiterId, AreaTable table) async {
    if (table.areaId == null) return true;
    final areas = await (db.select(db.waiterAreas)
          ..where((wa) => wa.waiterId.equals(waiterId)))
        .get();
    if (areas.isEmpty) return true; // global waiter
    return areas.any((wa) => wa.areaId == table.areaId);
  }

  /// Fire-and-forget auto-sync of [orderId] when the POS is online. Shared by
  /// the waiter mutation endpoints so a change doesn't sit unsynced until the
  /// next periodic cycle. Safe to call unawaited.
  void _autoSyncWaiterOrder(int orderId, String label) {
    try {
      if (_ref.read(lastKnownOnlineStatusProvider)) {
        // ignore: unawaited_futures
        _ref
            .read(syncManagerProvider.notifier)
            .autoSyncOrder(orderId)
            .catchError((Object e) {
          Logger.instance.warning('Waiter $label autoSync failed: $e');
          return false;
        });
      }
    } catch (e) {
      Logger.instance.warning('Waiter $label autoSync kickoff failed: $e');
    }
  }

  /// Fire-and-forget "kitchen finished" signal for a delivery order, so the
  /// platform (Glovo / Kooul) gets its ready call.
  ///
  /// Deliberately narrow:
  ///   - only orders that came from, or go out on, a delivery platform;
  ///   - only once per order (`readySignalAt` guards it — the endpoint is
  ///     idempotent anyway, this just avoids a pointless round-trip);
  ///   - only while online, and only after the order exists server-side, since
  ///     the endpoint 404s on an unsynced order. There is no offline queue by
  ///     design: a ready signal delivered an hour late is worse than none.
  /// Intentionally not awaited by its caller — the KDS response must not wait
  /// on a delivery-platform round-trip.
  Future<void> _signalOrderReadyIfDelivery(int orderId) async {
    {
      try {
        if (!_ref.read(lastKnownOnlineStatusProvider)) return;
        final database = _ref.read(databaseProvider);
        final order = await (database.select(database.orders)
              ..where((o) => o.id.equals(orderId)))
            .getSingleOrNull();
        if (order == null) return;
        if (order.readySignalAt != null) return; // already signalled
        if (order.status == 'CANCELED') return;

        final isPlatform =
            order.externalOrderId != null || order.type == 'DELIVERY';
        if (!isPlatform) return;

        // The signal 404s until the order exists server-side. Push it first,
        // then signal — that's the documented order of operations.
        if (!order.isSynced) {
          final synced = await _ref
              .read(dataSyncServiceProvider)
              .syncSingleOrder(orderId);
          if (!synced) return;
        }

        final ok = await _ref.read(apiServiceProvider).signalOrderReady(order.code);
        if (!ok) return;
        await (database.update(database.orders)
              ..where((o) => o.id.equals(orderId)))
            .write(OrdersCompanion(readySignalAt: drift.Value(DateTime.now())));
      } catch (e) {
        Logger.instance.warning('ready-signal failed for order #$orderId: $e');
      }
    }
  }

  /// DELETE /waiters/orders/<code>/products/<opId>?waiterId=int
  ///
  /// Remove a single line from an order the waiter owns. A PAID line (already
  /// on a ticket) cannot be removed — refund is a cashier action.
  ///
  ///   - 200 `{ removed: true, removedId }`
  ///   - 400 bad input / line already paid
  ///   - 403 not owner
  ///   - 404 order or line not found
  Future<Response> _waiterRemoveProduct(
      Request request, String code, String opId) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final waiterId =
          int.tryParse(request.url.queryParameters['waiterId'] ?? '');
      final orderProductId = int.tryParse(opId);
      if (waiterId == null || orderProductId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId and a valid line id are required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final order = await (database.select(database.orders)
            ..where((o) => o.code.equals(code)))
          .getSingleOrNull();
      if (order == null) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (order.waiterId != waiterId) {
        return Response(403,
            body: jsonEncode({'error': 'Not authorized to modify this order'}),
            headers: {'Content-Type': 'application/json'});
      }

      final line = await (database.select(database.orderProducts)
            ..where((p) => p.id.equals(orderProductId) & p.orderId.equals(order.id)))
          .getSingleOrNull();
      if (line == null) {
        return Response.notFound(
          jsonEncode({'error': 'Line not found on this order'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (line.ticketId != null) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'cannot_remove_paid_line',
            'message':
                'This line is already paid and can\'t be removed. Ask the cashier to refund it.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Tombstone BEFORE the delete — once the row is gone there is nothing
      // left to describe, and the Z has to be able to total what was pulled.
      try {
        final product = await (database.select(database.products)
              ..where((t) => t.id.equals(line.productId)))
            .getSingleOrNull();
        final variant = line.variantId == null
            ? null
            : await (database.select(database.productVariants)
                  ..where((t) => t.id.equals(line.variantId!)))
                .getSingleOrNull();
        final waiterRow = await (database.select(database.waiters)
              ..where((w) => w.id.equals(waiterId)))
            .getSingleOrNull();
        final comps = await (database.select(database.orderProductComponents)
              ..where((c) => c.orderProductId.equals(line.id)))
            .get();
        // Billed unit price: options in, manual discount out — same as the
        // till's own tombstones.
        final unitBilled = line.unitaryPrice +
            comps.fold<double>(0, (s, c) => s + c.price * c.quantity) -
            line.manualDiscount;
        final tombstone = RemovedOrderItemsCompanion.insert(
          orderId: order.id,
          orderCode: drift.Value(order.code),
          sessionId: drift.Value(order.sessionId),
          zDay: drift.Value(order.zDay),
          productId: line.productId,
          variantId: drift.Value(line.variantId),
          productName: product?.name ?? 'item #${line.productId}',
          variantName: drift.Value(variant?.name),
          quantity: line.quantity,
          unitaryPrice: drift.Value(unitBilled),
          amount: drift.Value(line.quantity * unitBilled),
          wasSentToKitchen: drift.Value(line.kdsPrintedQuantity > 0),
          source: const drift.Value('WAITER'),
          removedBy: drift.Value(waiterId),
          removedByName: drift.Value(waiterRow == null
              ? null
              : '${waiterRow.firstName} ${waiterRow.lastName ?? ''}'.trim()),
        );
        await database.into(database.removedOrderItems).insert(tombstone);
        notifyRemovedItems(_ref.read, [tombstone]);
      } catch (e) {
        // Never fail the removal over its own audit row.
        Logger.instance
            .warning('Removed-item tombstone failed for line #$orderProductId: $e');
      }

      // Kept for the v2 push, which sends it as a cancelled line instead of
      // letting it vanish from the order.
      await keepCancelledLine(database, line);
      await (database.delete(database.orderProductComponents)
            ..where((c) => c.orderProductId.equals(orderProductId)))
          .go();
      await (database.delete(database.orderProducts)
            ..where((p) => p.id.equals(orderProductId)))
          .go();
      await (database.update(database.orders)
            ..where((o) => o.id.equals(order.id)))
          .write(OrdersCompanion(
        updatedAt: drift.Value(DateTime.now()),
        // Without this the autoSync below is a no-op (`syncSingleOrder`
        // returns early on a synced order) and the backend keeps the line —
        // which the next delta pull then re-inserts locally.
        isSynced: const drift.Value(false),
      ));

      await logService.logOrderUpdated(
          order.id, 'Line #$orderProductId removed by waiter #$waiterId');
      _autoSyncWaiterOrder(order.id, 'remove-line');

      return Response.ok(
        jsonEncode({'removed': true, 'removedId': orderProductId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      Logger.instance.error('_waiterRemoveProduct failed: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to remove line', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /waiters/orders/<code>/cancel
  /// Body: `{ "waiterId": int, "reason"?: string }`
  ///
  /// Cancel an order the waiter owns: sets the order + its lines to CANCELED
  /// and frees the table. Blocked when any line is already paid (a paid order
  /// must be voided/refunded by the cashier).
  ///
  ///   - 200 `{ canceled: true, status: "CANCELED" }`
  ///   - 400 bad input / order has payments
  ///   - 403 not owner
  ///   - 404 order not found
  Future<Response> _waiterCancelOrder(Request request, String code) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = body.isNotEmpty
          ? jsonDecode(body) as Map<String, dynamic>
          : <String, dynamic>{};
      final waiterId = json['waiterId'] as int?;
      final reason = (json['reason'] as String?)?.trim();
      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final order = await (database.select(database.orders)
            ..where((o) => o.code.equals(code)))
          .getSingleOrNull();
      if (order == null) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (order.waiterId != waiterId) {
        return Response(403,
            body: jsonEncode({'error': 'Not authorized to cancel this order'}),
            headers: {'Content-Type': 'application/json'});
      }

      // Block cancellation once any line is paid — that revenue is on a ticket
      // and must be voided by the cashier, not silently cancelled here.
      final lines = await (database.select(database.orderProducts)
            ..where((p) => p.orderId.equals(order.id)))
          .get();
      if (lines.any((p) => p.ticketId != null)) {
        return Response.badRequest(
          body: jsonEncode({
            'error': 'order_has_payments',
            'message':
                'This order has payments and can\'t be cancelled. Ask the cashier to void/refund it.',
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final now = DateTime.now();
      // Valued before the write, while the lines still count.
      final cancelledAmount = await _ref
          .read(orderRepositoryProvider)
          .getOrderTotals([order.id])
          .then((t) => t[order.id] ?? 0.0)
          .catchError((_) => 0.0);
      await (database.update(database.orders)
            ..where((o) => o.id.equals(order.id)))
          .write(OrdersCompanion(
        status: const drift.Value('CANCELED'),
        cancellationReason:
            reason != null && reason.isNotEmpty ? drift.Value(reason) : const drift.Value.absent(),
        updatedAt: drift.Value(now),
        isSynced: const drift.Value(false),
      ));
      await (database.update(database.orderProducts)
            ..where((p) => p.orderId.equals(order.id)))
          .write(OrderProductsCompanion(
        state: const drift.Value('CANCELED'),
        updatedAt: drift.Value(now),
      ));

      // Free the table the order occupied — keyed on real occupancy
      // (area_tables.orderId == order.id) rather than the order's possibly
      // stale/null tableId, so a waiter-cancelled order can't leave a table
      // stuck as occupied.
      try {
        await _ref.read(orderRepositoryProvider).freeTablesForOrder(order.id);
      } catch (e) {
        Logger.instance.warning('Waiter cancel table clear failed: $e');
      }

      await logService.logOrderUpdated(order.id,
          'Order canceled by waiter #$waiterId${reason != null && reason.isNotEmpty ? ' — $reason' : ''}');
      final waiterRow = await (database.select(database.waiters)
            ..where((w) => w.id.equals(waiterId)))
          .getSingleOrNull();
      notifyOrderCancelled(
        _ref.read,
        orderCode: order.code,
        amount: cancelledAmount,
        reason: reason,
        byName: waiterRow == null
            ? 'Waiter #$waiterId'
            : '${waiterRow.firstName} ${waiterRow.lastName ?? ''}'.trim(),
      );
      _autoSyncWaiterOrder(order.id, 'cancel');

      return Response.ok(
        jsonEncode({'canceled': true, 'status': 'CANCELED'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      Logger.instance.error('_waiterCancelOrder failed: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to cancel order', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /waiters/orders/<code>/transfer-table
  /// Body: `{ "waiterId": int, "tableId": int }`
  ///
  /// Move an order the waiter owns to a different (free) table. The waiter must
  /// be allowed to serve the target table (area rule). The old table is freed
  /// and the new table linked to the order.
  ///
  ///   - 200 `{ transferred: true, tableId }`
  ///   - 400 bad input / target occupied
  ///   - 403 not owner / not allowed on target table
  ///   - 404 order or target table not found
  Future<Response> _waiterTransferTable(Request request, String code) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = body.isNotEmpty
          ? jsonDecode(body) as Map<String, dynamic>
          : <String, dynamic>{};
      final waiterId = json['waiterId'] as int?;
      final newTableId = json['tableId'] as int?;
      if (waiterId == null || newTableId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId and tableId are required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final order = await (database.select(database.orders)
            ..where((o) => o.code.equals(code)))
          .getSingleOrNull();
      if (order == null) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (order.waiterId != waiterId) {
        return Response(403,
            body: jsonEncode({'error': 'Not authorized to move this order'}),
            headers: {'Content-Type': 'application/json'});
      }

      final newTable = await (database.select(database.areaTables)
            ..where((t) => t.id.equals(newTableId)))
          .getSingleOrNull();
      if (newTable == null) {
        return Response.notFound(
          jsonEncode({'error': 'Target table not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!await _waiterMayServeTable(database, waiterId, newTable)) {
        return Response(403,
            body: jsonEncode({'error': 'Not allowed to use the target table'}),
            headers: {'Content-Type': 'application/json'});
      }
      final now = DateTime.now();
      // All table-link writes happen in ONE transaction, with the occupancy
      // re-check inside it — so two concurrent transfers (or a transfer racing
      // a create) onto the same target table can't both succeed and stomp the
      // link. A conflict rolls back and becomes a 400 below.
      try {
        await database.transaction(() async {
          final t = await (database.select(database.areaTables)
                ..where((x) => x.id.equals(newTableId)))
              .getSingleOrNull();
          if (t != null && t.orderId != null && t.orderId != order.id) {
            throw const _WaiterConflict(400, 'target_table_occupied',
                'The target table is already occupied by another order.');
          }
          // Free the old table (if any) before linking the new one.
          if (order.tableId != null && order.tableId != newTableId) {
            await (database.update(database.areaTables)
                  ..where((x) => x.id.equals(order.tableId!)))
                .write(const AreaTablesCompanion(orderId: drift.Value(null)));
          }
          await (database.update(database.areaTables)
                ..where((x) => x.id.equals(newTableId)))
              .write(AreaTablesCompanion(orderId: drift.Value(order.id)));
          await (database.update(database.orders)
                ..where((o) => o.id.equals(order.id)))
              .write(OrdersCompanion(
            tableId: drift.Value(newTableId),
            updatedAt: drift.Value(now),
            isSynced: const drift.Value(false),
          ));
        });
      } on _WaiterConflict catch (e) {
        return e.toResponse();
      }

      await logService.logOrderUpdated(order.id,
          'Order moved to table #$newTableId by waiter #$waiterId');
      _autoSyncWaiterOrder(order.id, 'transfer-table');

      return Response.ok(
        jsonEncode({'transferred': true, 'tableId': newTableId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      Logger.instance.error('_waiterTransferTable failed: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to transfer table', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /waiters/tables/<tableId>/clear
  /// Body: `{ "waiterId": int }`
  ///
  /// Free a table (unlink its order) without touching the order itself — the
  /// explicit counterpart to `autoClearTableAfterPaying`. The waiter must be
  /// allowed to serve the table (area rule).
  ///
  ///   - 200 `{ cleared: true }`
  ///   - 400 bad input
  ///   - 403 not allowed on this table
  ///   - 404 table not found
  Future<Response> _waiterClearTable(Request request, String tableId) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = body.isNotEmpty
          ? jsonDecode(body) as Map<String, dynamic>
          : <String, dynamic>{};
      final waiterId = json['waiterId'] as int?;
      final tId = int.tryParse(tableId);
      if (waiterId == null || tId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId and a valid tableId are required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final table = await (database.select(database.areaTables)
            ..where((t) => t.id.equals(tId)))
          .getSingleOrNull();
      if (table == null) {
        return Response.notFound(
          jsonEncode({'error': 'Table not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }
      if (!await _waiterMayServeTable(database, waiterId, table)) {
        return Response(403,
            body: jsonEncode({'error': 'Not allowed to clear this table'}),
            headers: {'Content-Type': 'application/json'});
      }

      final clearedOrderId = table.orderId;
      await (database.update(database.areaTables)
            ..where((t) => t.id.equals(tId)))
          .write(const AreaTablesCompanion(orderId: drift.Value(null)));

      if (clearedOrderId != null) {
        await logService.logOrderUpdated(
            clearedOrderId, 'Table #$tId cleared by waiter #$waiterId');
      }

      return Response.ok(
        jsonEncode({'cleared': true}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, st) {
      Logger.instance.error('_waiterClearTable failed: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to clear table', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /waiters/orders/<code>/add-product - Add product to existing order
  /// Body: { "waiterId": 1, "productId": 5, "quantity": 2, "components": [...] }
  Future<Response> _waiterAddProductToOrder(Request request, String code) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final waiterId = json['waiterId'] as int?;
      // The line itself (variant, quantity, note, course, options) is read
      // by _insertWaiterLine, the same as on the create and batch routes.
      final productId = json['productId'] as int?;

      if (waiterId == null || productId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId and productId are required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get order
      final order = await (database.select(database.orders)
        ..where((o) => o.code.equals(code)))
        .getSingleOrNull();

      if (order == null) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify waiter owns this order
      if (order.waiterId != waiterId) {
        return Response(
          403,
          body: jsonEncode({'error': 'Not authorized to modify this order'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get product details
      final product = await (database.select(database.products)
        ..where((p) => p.id.equals(productId)))
        .getSingleOrNull();

      if (product == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Product not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // A line added to an existing order takes that order's z_day — the same
      // rule `_insertWaiterLine` follows on the create path, which this one
      // did not, so a course added later carried a null z_day while its
      // siblings carried the right day. Falls back to the order's session,
      // then to the shift open now, for an order that has neither.
      final addZDay = order.zDay ??
          await ZDayResolver(database).forSessionOrCurrent(order.sessionId);

      // The same line write as the create and batch routes: catalogue price,
      // options checked and priced by the till. One transaction with the
      // order's `isSynced: false` flip — the load-bearing half, since
      // `syncSingleOrder` returns early on an already-synced order, so
      // without it the new line never reaches the backend and the next
      // order delta, whose snapshot lacks it, deletes it again locally.
      try {
        await database.transaction(() async {
          await _insertWaiterLine(
            database,
            order.id,
            json,
            state: 'PENDING',
            zDay: addZDay,
          );
          await (database.update(database.orders)
                ..where((o) => o.id.equals(order.id)))
              .write(OrdersCompanion(
            updatedAt: drift.Value(DateTime.now()),
            isSynced: const drift.Value(false),
          ));
        });
      } on _WaiterConflict catch (e) {
        return e.toResponse();
      }

      // Order-level log + cross-cutting activity log. Same shape as
      // _waiterCreateOrder above: waiter name resolved once, then both
      // logs fire.
      final waiterRow = await (database.select(database.waiters)
            ..where((w) => w.id.equals(waiterId)))
          .getSingleOrNull();
      final waiterFullName = waiterRow == null
          ? 'waiter #$waiterId'
          : '${waiterRow.firstName} ${waiterRow.lastName ?? ''}'.trim();
      await logService.logOrderUpdated(
          order.id, 'Product added by waiter $waiterFullName');
      // ignore: unawaited_futures
      _ref.read(activityLogServiceProvider).logWaiterProductAdded(
            waiterName: waiterFullName,
            productName: product.name,
            orderCode: code,
          );

      // Fire the kitchen ticket for the newly-added item, in the background so
      // the waiter app's PUT doesn't block on the printer. modifications-only,
      // so only this new line prints — exactly like adding to an order on the
      // POS. Attributed to the current POS cashier.
      final posUser = _ref.read(currentUserProvider);
      _fireKdsForWaiterAddedProduct(order.id, posUser?.firstName);

      _autoSyncWaiterOrder(order.id, 'add-product');

      return Response.ok(
        jsonEncode({'message': 'Product added to order successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      Logger.instance.error('Error in _waiterAddProductToOrder: $e');
      posLog(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to add product', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // ==================== HELPER METHODS ====================

  /// Build SocketOrderModel from database order
  Future<SocketOrderModel?> _buildSocketOrder(
      Order order, Set<String>? stationFilters,
      [KdsFeedFilter feedFilter = const KdsFeedFilter()]) async {
    final database = _ref.read(databaseProvider);

    // Get order products first - if none, return null
    final orderProducts = await (database.select(database.orderProducts)
      ..where((tbl) => tbl.orderId.equals(order.id)))
        .get();

    if (orderProducts.isEmpty) {
      Logger.instance.warning('Order ${order.code} has no products, skipping...');
      return null;
    }

    // Batch load all needed data in parallel
    final [
    table,
    client,
    products,
    allComponents,
    allStations,
    allProductStations,
    waiter,
    ] = await Future.wait([
      // Get table
      order.tableId != null
          ? (database.select(database.areaTables)
        ..where((tbl) => tbl.id.equals(order.tableId!))).getSingleOrNull()
          : Future.value(null),

      // Get client
      order.clientId != null
          ? (database.select(database.customers)
        ..where((tbl) => tbl.id.equals(order.clientId!))).getSingleOrNull()
          : Future.value(null),

      // Get all products for this order in one query
      (database.select(database.products)
        ..where((tbl) => tbl.id.isIn(orderProducts.map((p) => p.productId).toList())))
          .get(),

      // Get all components for all order products
      (database.select(database.orderProductComponents)
        ..where((tbl) => tbl.orderProductId.isIn(orderProducts.map((p) => p.id).toList())))
          .get(),

      // Get all stations (for filtering)
      database.select(database.stations).get(),

      // Get extra product↔station links for this order's products
      (database.select(database.productStations)
        ..where((tbl) => tbl.productId.isIn(orderProducts.map((p) => p.productId).toList())))
          .get(),

      // The waiter who took it, for the pass.
      order.waiterId != null
          ? (database.select(database.waiters)
                ..where((tbl) => tbl.id.equals(order.waiterId!)))
              .getSingleOrNull()
          : Future.value(null),
    ]);

    // Create maps for quick lookup
    final productsMap = {for (var p in products as List<dynamic>) p.id: p};
    final stationsMap = {for (var s in allStations as List<dynamic>) s.id: s};
    // productId -> set of extra station ids
    final extraStationsByProduct = <int, Set<int>>{};
    for (final ps in allProductStations as List<dynamic>) {
      extraStationsByProduct.putIfAbsent(ps.productId, () => <int>{}).add(ps.stationId);
    }
    final componentsByOrderProduct = <int, List>{};

    // Group components by order product ID
    for (var comp in allComponents as List<dynamic>) {
      componentsByOrderProduct.putIfAbsent(comp.orderProductId, () => []).add(comp);
    }

    // Batch-load component details to avoid N+1 per component
    final allComponentIds = allComponents
        .map((c) => c.componentId as int)
        .toSet()
        .toList();
    final componentDetailsList = allComponentIds.isNotEmpty
        ? await (database.select(database.components)
            ..where((tbl) => tbl.id.isIn(allComponentIds)))
            .get()
        : <Component>[];
    final componentsMap = {for (final c in componentDetailsList) c.id: c};

    // Linked options, resolved only when this KDS asked for them and is
    // station-scoped (an unscoped board already shows every parent line).
    final linkedByComponent = feedFilter.linked && stationFilters != null
        ? await linkedProductByComponent(database, componentDetailsList)
        : const <int, int>{};
    final linkedStations = linkedByComponent.isEmpty
        ? const <int, Set<int>>{}
        : await stationIdsByProduct(database, linkedByComponent.values);
    // The linked product's own preparation time (the drink, not the menu).
    final linkedPrep = linkedByComponent.isEmpty
        ? const <int, int?>{}
        : {
            for (final lp in await (database.select(database.products)
                  ..where((t) => t.id.isIn(linkedByComponent.values.toSet())))
                .get())
              lp.id: lp.preparingDuration,
          };
    final coursesOn = _ref.read(settingsProvider).coursesEnabled;
    String? matchingStation(Iterable<int> ids) {
      for (final id in ids) {
        final n = stationsMap[id]?.name as String?;
        if (n != null && stationFilters!.contains(n.toLowerCase())) return n;
      }
      return null;
    }

    final tableName = table != null ? (table as dynamic).name : null;
    final clientName = client != null
        ? '${(client as dynamic).firstName} ${(client as dynamic).lastName}'.trim()
        : null;

    // Process products
    final socketProducts = <SocketOrderProductModel>[];

    for (final orderProduct in orderProducts) {
      final product = productsMap[orderProduct.productId];
      if (product == null) continue;

      // Build the product's full station set: primary stationId + extra (join) stations.
      final stationIds = <int>{
        if (product.stationId != null) product.stationId as int,
        ...?extraStationsByProduct[orderProduct.productId],
      };

      // Filter by station if specified: keep the item if ANY of its stations is
      // in this KDS's set of stations — or, when asked for, if it has no
      // station at all.
      if (stationFilters != null) {
        final matches = stationIds.any((id) {
          final n = stationsMap[id]?.name?.toLowerCase();
          return n != null && stationFilters.contains(n);
        }) || (feedFilter.unassigned && stationIds.isEmpty);
        if (!matches) {
          // Not this station's line, but an option on it may be: the drink in
          // a menu whose parent the kitchen owns. Shown as its own read-only
          // line, one per parent unit, following the parent's state.
          if (linkedByComponent.isNotEmpty) {
            final comps = componentsByOrderProduct[orderProduct.id] ?? const [];
            for (var k = 0; k < comps.length; k++) {
              final comp = comps[k];
              // A removed or zero-quantity option is nothing to make.
              if (comp.removalCharge == true || (comp.quantity as num) <= 0) {
                continue;
              }
              final lp = linkedByComponent[comp.componentId];
              if (lp == null) continue;
              final station = matchingStation(linkedStations[lp] ?? const {});
              if (station == null) continue;
              final units = orderProduct.quantity * (comp.quantity as num);
              if (units <= 0) continue;
              socketProducts.add(SocketOrderProductModel(
                id: linkedLineId(orderProduct.id, k),
                productId: lp,
                productName: componentsMap[comp.componentId]?.name ??
                    'Product #$lp',
                quantity: units.toDouble(),
                unitaryPrice: 0,
                state: orderProduct.state,
                paid: isLinePaid(orderProduct.state, orderProduct.ticketId),
                stationName: station,
                components: const [],
                note: '← ${product.name}',
                courseNo: coursesOn
                    ? normalizeCourseNo(orderProduct.courseNo)
                    : null,
                parentLineId: orderProduct.id,
                // The parent's clocks: the option is made with it.
                kitchenAt:
                    kitchenSince(orderProduct, fallback: order.createdAt),
                preparingAt: orderProduct.preparingAt,
                doneAt: kitchenDoneAt(orderProduct),
                prepMinutes: linkedPrep[lp],
              ));
            }
          }
          continue;
        }
      }

      // Station name to surface: the item's own matching station when filtering
      // (so a merged multi-station board can label each line), else the primary.
      String? stationName;
      if (stationFilters != null) {
        for (final id in stationIds) {
          final n = stationsMap[id]?.name;
          if (n != null && stationFilters.contains(n.toLowerCase())) {
            stationName = n;
            break;
          }
        }
      } else if (product.stationId != null) {
        stationName = stationsMap[product.stationId]?.name;
      }

      // Get components for this order product
      final productComponents = componentsByOrderProduct[orderProduct.id] ?? [];

      final socketComponents = <SocketOrderProductComponentModel>[];
      final removed = <String>[];
      for (final comp in productComponents) {
        final component = componentsMap[comp.componentId];

        // Same rules as the kitchen ticket: a removal-charge row is "NO x",
        // and a zero-quantity row is a signal for the server, not an option.
        if (comp.removalCharge == true) {
          final n = (comp.name as String?) ?? component?.name;
          if (n != null && n.isNotEmpty) removed.add(n);
          continue;
        }
        if ((comp.quantity as num) <= 0) continue;

        if (component != null) {
          socketComponents.add(SocketOrderProductComponentModel(
            componentId: comp.componentId,
            componentName: component.name,
            quantity: comp.quantity,
            isSpecial: comp.isSpecial,
            extraPrice: comp.price,
          ));
        }
      }

      socketProducts.add(SocketOrderProductModel(
        id: orderProduct.id,
        productId: orderProduct.productId,
        variantId: orderProduct.variantId,
        productName: product.name,
        imageUrl: product.imageUrl,
        quantity: orderProduct.quantity,
        unitaryPrice: orderProduct.unitaryPrice,
        state: orderProduct.state,
        paid: isLinePaid(orderProduct.state, orderProduct.ticketId),
        stationId: product.stationId,
        stationName: stationName,
        components: socketComponents,
        note: orderProduct.note,
        tvaAmount: orderProduct.unitaryTva,
        discountAmount: orderProduct.unitaryDiscount,
        // Courses off = no sections on the KDS, even for lines tagged while
        // they were on.
        courseNo: coursesOn ? normalizeCourseNo(orderProduct.courseNo) : null,
        kitchenAt: kitchenSince(orderProduct, fallback: order.createdAt),
        preparingAt: orderProduct.preparingAt,
        doneAt: kitchenDoneAt(orderProduct),
        prepMinutes: product.preparingDuration as int?,
        removedComponents: removed,
      ));
    }

    // If no products after filtering, return null
    if (socketProducts.isEmpty) {
      Logger.instance.warning('Order ${order.code} has no products after station filter, skipping...');
      return null;
    }

    return SocketOrderModel(
      id: order.id,
      code: order.code,
      status: order.status,
      type: order.type,
      priority: order.priority,
      persons: order.persons,
      date: order.createdAt,
      tableId: order.tableId,
      tableName: tableName,
      clientId: order.clientId,
      clientName: clientName,
      products: socketProducts,
      note: order.note,
      cancellationReason: order.cancellationReason,
      reference: order.reference,
      orderNumber: _ref.read(settingsProvider).showOrderNumberOnKds
          ? order.sessionOrderNo
          : null,
      courseLines: coursesOn
          ? kdsCourseLines(orderProducts, fallback: order.createdAt)
          : const [],
      source: order.source,
      waiterName: waiter == null
          ? null
          : '${(waiter as Waiter).firstName} ${waiter.lastName ?? ''}'.trim(),
      externalOrderCode: order.externalOrderCode,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    );
  }

  // ==================== GETTERS ====================

  bool get isRunning => _isRunning;
  int get port => _port;
  String? get serverPassword => _serverPassword;
}


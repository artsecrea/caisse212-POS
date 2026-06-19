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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/enums.dart' show TransactionType;
import '../data/database/app_database.dart';
import '../domain/models/socket_models.dart';
import '../providers/database_providers.dart';
import '../providers/order_provider.dart' show orderRepositoryProvider;
import '../providers/settings_provider.dart' show settingsProvider;
import '../providers/network_provider.dart' show lastKnownOnlineStatusProvider;
import '../providers/sync_manager_provider.dart' show syncManagerProvider;
import 'activity_log_service.dart' show activityLogServiceProvider;
import 'order_log_service.dart';
import 'printing_service.dart' show PrintOutput, KdsPrintMode;
import '../utils/order_code.dart';
import 'package:drift/drift.dart' as drift;

class ServerService {
  final Ref _ref;
  HttpServer? _server;
  int _port;
  String? _serverPassword;
  bool _isRunning = false;

  ServerService(this._ref, {int port = 8080}) : _port = port;

  /// Start the HTTP server
  Future<void> start({int? port, String? password}) async {
    if (_isRunning) {
      print('⚠️ Server already running on port $_port');
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
      print('✅ Server started on http://${_server!.address.host}:${_server!.port}');
    } catch (e) {
      print('❌ Failed to start server: $e');
      rethrow;
    }
  }

  /// Stop the HTTP server
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _isRunning = false;
      print('🛑 Server stopped');
    }
  }

  /// Build the router with all endpoints
  Router _buildRouter() {
    final router = Router();

    // Health check
    router.get('/health', _healthCheck);

    // Order endpoints
    router.get('/orders', _getOrders);
    router.post('/orders', _createOrder);
    router.put('/orders/<orderId>', _updateOrder);
    router.put('/orders/products/<id>', _updateOrderProduct);
    router.get('/stations', _getStations);

    // Waiter-specific endpoints
    router.post('/waiters/login', _waiterLogin);
    router.get('/waiters/dashboard', _waiterDashboard);
    router.get('/waiters/products', _waiterProducts);
    router.get('/waiters/categories', _waiterCategories);
    router.get('/waiters/components', _waiterComponents);
    router.get('/waiters/component-groups', _waiterComponentGroups);
    router.get('/waiters/product-components', _waiterProductComponents);
    router.get('/waiters/product-variants', _waiterProductVariants);
    router.get('/waiters/tables', _waiterTables);
    router.get('/waiters/orders', _waiterOrders);
    router.post('/waiters/orders', _waiterCreateOrder);
    router.put('/waiters/orders/<code>/add-product', _waiterAddProductToOrder);
    router.post('/waiters/orders/<code>/print', _waiterPrintOrder);

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
        // Skip auth for health check
        if (request.url.path == 'health') {
          return innerHandler(request);
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
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, X-Server-Password',
      };

  // ==================== ENDPOINT HANDLERS ====================

  /// Health check endpoint
  Future<Response> _healthCheck(Request request) async {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'timestamp': DateTime.now().toIso8601String(),
        'port': _port,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }



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

      // ── 1. Parse params ─────────────────────────────────────────────────
      final afterId = int.tryParse(q['after_id'] ?? '');
      final statusStr = q['status'];
      final stationName = q['station'];

      // Status: ONHOLD never reaches KDS
      final List<String> status = statusStr != null
          ? statusStr.split(',').map((s) => s.trim().toUpperCase()).toList()
          : [];
      status.removeWhere((s) => s == 'ONHOLD');

      // Lower-bound date — ALWAYS set; log cursor never replaces it
      DateTime since;
      if (q['since'] != null || q['from_date'] != null) {
        try {
          since = DateTime.parse(q['since'] ?? q['from_date']!);
        } catch (_) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Invalid date format for "since"/"from_date"'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      } else {
        final now = DateTime.now();
        since = DateTime(now.year, now.month, now.day);
      }

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
      Future<Response> emptyResponse() async {
        final lastLogId = await logService.getLastUpdateLogId();
        return Response.ok(
          jsonEncode({
            'orders': [], 'orders_updated': [], 'orders_deleted': [],
            'last_log_id': lastLogId, 'count': 0, 'updated_count': 0, 'deleted_count': 0,
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      Set<int>? orderIdsForStation;
      if (stationName != null) {
        final station = await (database.select(database.stations)
              ..where((tbl) => tbl.name.lower().equals(stationName.toLowerCase())))
            .getSingleOrNull();
        if (station == null) return emptyResponse();

        // A product belongs to this station via its primary stationId OR via the
        // product_stations join table (multi-station products).
        final extraStationProductIds = database.selectOnly(database.productStations)
          ..addColumns([database.productStations.productId])
          ..where(database.productStations.stationId.equals(station.id));

        final rows = await (database.select(database.orderProducts).join([
          drift.innerJoin(
            database.products,
            database.products.id.equalsExp(database.orderProducts.productId),
          ),
        ])..where(database.products.stationId.equals(station.id) |
            database.products.id.isInQuery(extraStationProductIds))).get();

        orderIdsForStation =
            rows.map((r) => r.readTable(database.orderProducts).orderId).toSet();
        if (orderIdsForStation.isEmpty) return emptyResponse();
      }

      // ── Helper: apply shared filters to a select statement ───────────────
      void applyFilters(drift.SimpleSelectStatement<$OrdersTable, Order> sel,
          {bool applyStatus = true}) {
        sel..where((o) => o.createdAt.isBiggerOrEqualValue(since));
        if (toDate != null) sel..where((o) => o.createdAt.isSmallerOrEqualValue(toDate!));
        if (applyStatus) {
          if (status.isNotEmpty) {
            sel..where((o) => o.status.isIn(status));
          } else {
            sel..where((o) => o.status.equals('ONHOLD').not());
          }
        }
        if (orderIdsForStation != null) {
          sel..where((o) => o.id.isIn(orderIdsForStation!.toList()));
        }
      }

      // ── 3. New orders (created within date window) ───────────────────────
      final newOrdersQuery = database.select(database.orders);
      applyFilters(newOrdersQuery);
      if (afterId != null) {
        newOrdersQuery..where((o) => o.id.isBiggerThanValue(afterId));
      }
      final newOrders = await newOrdersQuery.get();

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
        updatedOrders = await updatedQuery.get();
      }

      // ── 5. Deleted order IDs — same date-primary pattern ─────────────────
      final deletedOrderIds = updatedAfterLogId != null
          ? await logService.getDeletedOrdersSinceLogIdAndDate(updatedAfterLogId, since)
          : await logService.getDeletedOrdersSinceDate(since);

      // ── 6. Build socket models + respond ────────────────────────────────
      final [socketNewRaw, socketUpdatedRaw, lastLogIdRaw] = await Future.wait([
        Future.wait(newOrders.map((o) => _buildSocketOrder(o, stationName))),
        Future.wait(updatedOrders.map((o) => _buildSocketOrder(o, stationName))),
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
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _getOrders: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /orders/ - Create new order
  Future<Response> _createOrder(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      print('📥 _createOrder: $json');

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

      // Convert to database order
      final orderId = await database.into(database.orders).insert(
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
          createdAt: drift.Value(socketOrder.date),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      // If DINE_IN with a table, link the order to the table
      if (socketOrder.tableId != null) {
        await (database.update(database.areaTables)
          ..where((t) => t.id.equals(socketOrder.tableId!)))
          .write(AreaTablesCompanion(orderId: drift.Value(orderId)));
      }

      // Insert products
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
            orderId: orderId,
            productId: product.productId,
            variantId: drift.Value(product.variantId),
            quantity: drift.Value(product.quantity),
            unitaryPrice: unitPrice,
            unitaryDiscount: drift.Value(unitDiscount),
            unitaryTva: drift.Value(unitTva),
            note: drift.Value(product.note),
            state: drift.Value(product.state),
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
            ),
          );
        }
      }

      // Log order creation
      await logService.logOrderCreated(orderId, 'Order created via API: code=${socketOrder.code}');

      print('✅ _createOrder: inserted order #$orderId code=${socketOrder.code}');

      return Response(
        201,
        body: jsonEncode({'id': orderId, 'code': socketOrder.code}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _createOrder: $e');
      print(stackTrace);
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
        );

        await (database.update(database.orders)
              ..where((tbl) => tbl.id.equals(id)))
            .write(companion);

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
      print('❌ Error in _updateOrder: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update order', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /orders/products/<id>?status=newstatus - Update product status
  Future<Response> _updateOrderProduct(Request request, String id) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
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

      final updated = await (database.update(database.orderProducts)
            ..where((tbl) => tbl.id.equals(productId)))
          .write(
        OrderProductsCompanion(
          state: drift.Value(statusParam.toUpperCase()),
        ),
      );

      if (updated == 0) {
        return Response.notFound(
          jsonEncode({'error': 'Order product not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final orderProduct = await (database.select(database.orderProducts)
        ..where((tbl) => tbl.id.equals(productId)))
        .getSingleOrNull();
      if (orderProduct != null) {
        final orderId = orderProduct.orderId;
        final allProducts = await (database.select(database.orderProducts)
          ..where((tbl) => tbl.orderId.equals(orderId)))
          .get();
        final allSameStatus = allProducts.every((p) => p.state == statusParam.toUpperCase());
        if (allSameStatus) {
          await (database.update(database.orders)
            ..where((tbl) => tbl.id.equals(orderId)))
            .write(OrdersCompanion(
              status: drift.Value(statusParam.toUpperCase()),
              updatedAt: drift.Value(DateTime.now()),
            ));
        }
        await logService.logOrderUpdated(orderId, 'Product status updated via API to $statusParam');
      }

      return Response.ok(
        jsonEncode({'message': 'Product status updated', 'id': productId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _updateOrderProduct: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update product', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /stations/ - Get all stations (for KDS station selection)
  Future<Response> _getStations(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final stations = await database.select(database.stations).get();
      final stationList = stations
          .map((s) => {'id': s.id, 'name': s.name, "description": s.description})
          .toList();

      return Response.ok(
        jsonEncode({'stations': stationList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _getStations: $e');
      print(stackTrace);
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
  Future<Response> _waiterLogin(Request request) async {
    try {
      final body =
          jsonDecode(await request.readAsString()) as Map<String, dynamic>;
      final pin = (body['pin'] as String?)?.trim();

      if (pin == null || pin.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'pin_required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final db = _ref.read(databaseProvider);
      // Look up by pin alone. The partial unique index guarantees at most
      // one match; `getSingleOrNull` collapses the null case for us.
      final waiter = await (db.select(db.waiters)
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
      print('❌ Error in _waiterLogin: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'login_failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

    /// GET /waiters/dashboard?waiterId=1
  /// Returns: total orders, active orders, expected cash, total cash
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

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      final allWaiterOrders = await (database.select(database.orders)
        ..where((o) => o.waiterId.equals(waiterId) & o.createdAt.isBiggerOrEqualValue(startOfDay)))
        .get();

      final waiterOrders = allWaiterOrders.where((o) => o.status != 'CANCELED').toList();
      final cancelledOrders = allWaiterOrders.where((o) => o.status == 'CANCELED').toList();

      final totalOrders = waiterOrders.length;
      final activeOrders = waiterOrders.where((o) => o.status != 'COMPLETED').length;
      final cancelledCount = cancelledOrders.length;

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

      double expectedCash = 0.0;
      double totalCash = 0.0;
      double cancelledAmount = 0.0;

      for (final order in cancelledOrders) {
        for (final p in productsByOrderId[order.id] ?? []) {
          double item = p.unitaryPrice * p.quantity;
          for (final c in componentsByOpId[p.id] ?? []) item += c.price * c.quantity;
          item -= p.unitaryDiscount * p.quantity;
          item -= p.manualDiscount * p.quantity;
          cancelledAmount += item;
        }
      }

      for (final order in waiterOrders) {
        for (final p in productsByOrderId[order.id] ?? []) {
          double item = p.unitaryPrice * p.quantity;
          for (final c in componentsByOpId[p.id] ?? []) item += c.price * c.quantity;
          item -= p.unitaryDiscount * p.quantity;
          item -= p.manualDiscount * p.quantity;
          expectedCash += item;
          if (p.ticketId != null) {
            final ticket = ticketsMap[p.ticketId];
            if (ticket != null && !ticket.isCancelled) totalCash += item;
          }
        }
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
      print('❌ Error in _waiterDashboard: $e');
      print(stackTrace);
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
      final products = await (database.select(database.products)
        ..where((p) => p.isActive.equals(true)))
        .get();

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
      }).toList();

      return Response.ok(
        jsonEncode({'products': productList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterProducts: $e');
      print(stackTrace);
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
      final categories = await (database.select(database.categories)
        ..where((c) => c.isActive.equals(true))
        ..orderBy([(c) => drift.OrderingTerm(expression: c.displayOrder)]))
        .get();

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
      print('❌ Error in _waiterCategories: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch categories', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/components
  Future<Response> _waiterComponents(Request request) async {


    try {
      final database = _ref.read(databaseProvider);
      final components = await database.select(database.components).get();

      final componentList = components.map((c) => {
        'id': c.id,
        'name': c.name,
        'price': c.price,
        'componentGroupId': c.componentGroupId,
      }).toList();

      print(componentList);
      return Response.ok(
        jsonEncode({'components': componentList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterComponents: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch components', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/component-groups
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
      }).toList();

      return Response.ok(
        jsonEncode({'componentGroups': groupList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterComponentGroups: $e');
      print(stackTrace);
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
      }).toList();

      return Response.ok(
        jsonEncode({'productComponents': pcList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterProductComponents: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch product components', 'details': e.toString()}),
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
      print('❌ Error in _waiterProductVariants: $e');
      print(stackTrace);
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
      List<Order> ordersRaw = [];
      if (tableOrderIds.isNotEmpty) {
        final ordersQuery = database.select(database.orders)
          ..where((o) => o.id.isIn(tableOrderIds));
        // Area-restricted waiters only see active (non-completed/cancelled) orders
        if (areaIds.isNotEmpty) {
          ordersQuery.where((o) => o.status.isNotIn(['COMPLETED', 'CANCELED']));
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
          for (final p in productsByOrderId[order.id] ?? []) {
            if (p.ticketId == null) {
              double item = p.unitaryPrice * p.quantity;
              for (final c in componentsByOpId[p.id] ?? []) { item += c.price * c.quantity; }
              item -= p.unitaryDiscount * p.quantity;
              item -= p.manualDiscount * p.quantity;
              totalAmount += item;
            }
          }
        }

        tableList.add({
          'id': table.id,
          'name': table.name,
          'capacity': table.capacity,
          'areaId': table.areaId,
          'areaName': area?.name,
          'orderId': order?.id,
          'orderCode': order?.code,
          'totalAmount': totalAmount,
        });
      }

      return Response.ok(
        jsonEncode({'tables': tableList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterTables: $e');
      print(stackTrace);
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

      // Build query
      var query = database.select(database.orders)..where((o) => o.waiterId.equals(waiterId));

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

      final productsByOrderId = <int, List<OrderProduct>>{};
      for (final p in allProducts) {
        productsByOrderId.putIfAbsent(p.orderId, () => []).add(p);
      }
      final componentsByOpId = <int, List<OrderProductComponent>>{};
      for (final c in allComponents) {
        componentsByOpId.putIfAbsent(c.orderProductId, () => []).add(c);
      }

      final orderList = <Map<String, dynamic>>[];
      for (final order in orders) {
        final table = order.tableId != null ? tablesMap[order.tableId] : null;
        final products = productsByOrderId[order.id] ?? [];

        double totalAmount = 0.0;
        bool allPaid = true;
        for (final p in products) {
          double item = p.unitaryPrice * p.quantity;
          for (final c in componentsByOpId[p.id] ?? []) { item += c.price * c.quantity; }
          item -= p.unitaryDiscount * p.quantity;
          item -= p.manualDiscount * p.quantity;
          totalAmount += item;
          if (p.ticketId == null) allPaid = false;
        }

        orderList.add({
          'id': order.id,
          'code': order.code,
          'status': order.status,
          'type': order.type,
          'persons': order.persons,
          'tableId': order.tableId,
          'tableName': table?.name,
          'totalAmount': totalAmount,
          'allPaid': allPaid,
          'productCount': products.length,
          'createdAt': order.createdAt.toIso8601String(),
          'updatedAt': order.updatedAt.toIso8601String(),
        });
      }

      return Response.ok(
        jsonEncode({'orders': orderList, 'page': page, 'limit': limit, 'count': orderList.length}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterOrders: $e');
      print(stackTrace);
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

      print(json);

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

      // Generate a short uppercase alphanumeric order code (e.g. RGH7IE3H3LR),
      // verified unique against existing orders.
      final now = DateTime.now();
      final orderCode = await _generateUniqueOrderCode(database);

      // Create order. `source: 'WAITER'` lets the print-rule engine filter
      // this row out (or in) per cashier config — see [PrintRule.sources].
      // Initial status is cashier-configurable via
      // `AppSettings.waiterOrderDefaultStatus` (default PENDING) so shops
      // that pre-pay at the table can set this to COMPLETED, or send
      // straight to the kitchen with PREPARING.
      //
      // `sessionId` carries the active cash session at create-time so the
      // order lands inside the current Z-report scope — without this the
      // cashier-side `WaiterProfileDialog` (which filters
      // `orders.sessionId == currentSession.id`) excludes every waiter
      // order. Null when no session is open is fine; the profile dialog
      // falls back to a today-window in that case.
      final settings = _ref.read(settingsProvider);
      final session = _ref.read(currentSessionProvider);
      final waiterOrderStatus = settings.waiterOrderDefaultStatus;
      // Attribute the order to whoever is logged into the POS right now, so a
      // waiter order behaves like a normal POS order created by that cashier:
      // `createdBy`/`takenBy` reference `users.id` and drive the "Cashier"
      // line on the ticket + the Orders Management attribution. The `waiterId`
      // column above still records which waiter raised it (for the waiter
      // app's own order list / dashboard). Null when no cashier is logged in.
      final posUser = _ref.read(currentUserProvider);
      final orderId = await database.into(database.orders).insert(
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
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // Insert products
      for (final productJson in products) {
        final productId = productJson['productId'] as int;
        final variantId = productJson['variantId'] as int?;
        final quantity = productJson['quantity'] as int? ?? 1;
        final productNote = productJson['note'] as String?;
        final components = productJson['components'] as List<dynamic>? ?? [];

        // Get product details
        final product = await (database.select(database.products)
          ..where((p) => p.id.equals(productId)))
          .getSingleOrNull();

        if (product == null) continue;

        // Use variant price/TVA if a variantId is provided
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

        final orderProductId = await database.into(database.orderProducts).insert(
          OrderProductsCompanion.insert(
            orderId: orderId,
            productId: productId,
            variantId: drift.Value(variantId),
            quantity: drift.Value(quantity),
            unitaryPrice: unitPrice,
            unitaryDiscount: drift.Value(unitDiscount),
            unitaryTva: drift.Value(unitTva),
            note: drift.Value(productNote),
            state: const drift.Value('PENDING'),
          ),
        );

        // Insert components
        for (final compJson in components) {
          final componentId = compJson['componentId'] as int;
          final compQuantity = compJson['quantity'] as int? ?? 1;
          final price = (compJson['price'] as num?)?.toDouble() ?? 0.0;

          await database.into(database.orderProductComponents).insert(
            OrderProductComponentsCompanion.insert(
              orderProductId: orderProductId,
              componentId: componentId,
              quantity: drift.Value(compQuantity),
              price: drift.Value(price),
              isSpecial: const drift.Value(false),
            ),
          );
        }
      }


      // update the tabele order_id

      if (tableId != null) {
        await (database.update(database.areaTables)..where((t) => t.id.equals(tableId)))
          .write(AreaTablesCompanion(orderId: drift.Value(orderId)));
      }

      // Default-paid path: when `waiterOrderDefaultPaid` is on, create a
      // CASH ticket covering the full order, mark every product PAID +
      // linked to that ticket, and bump the order status to the
      // cashier-configured `paidOrderDefaultStatus` (mirrors the cashier
      // payment screen at payment_screen.dart:1503-1525). Skipped when
      // off — today's legacy behaviour kicks in (open order, settle via
      // the cashier-side WaiterSettlementDialog later).
      final wasPaidOnCreate = settings.waiterOrderDefaultPaid;
      if (wasPaidOnCreate) {
        final orderTotal = await _computeWaiterOrderTotal(database, orderId);
        final ticketId = await database.into(database.tickets).insert(
          TicketsCompanion.insert(
            num: '0001',
            orderId: orderId,
            paymentMethod: TransactionType.cash.value,
            amount: orderTotal,
            sessionId: drift.Value(session?.id),
            isPaid: const drift.Value(true),
            printCount: const drift.Value(0),
          ),
        );
        await (database.update(database.orderProducts)
              ..where((p) => p.orderId.equals(orderId)))
            .write(OrderProductsCompanion(
          ticketId: drift.Value(ticketId),
          state: const drift.Value('PAID'),
          updatedAt: drift.Value(now),
        ));
        final paidStatus = settings.paidOrderDefaultStatus;
        await (database.update(database.orders)
              ..where((o) => o.id.equals(orderId)))
            .write(OrdersCompanion(
          status: drift.Value(paidStatus),
          updatedAt: drift.Value(now),
        ));
      }

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

      // Fire the configured auto-prints (order ticket + KDS, plus the
      // customer receipt + store copy when the order arrived pre-paid)
      // in the background so the waiter app's POST doesn't block on a
      // slow / dead printer. The pipeline reads the just-saved row via
      // OrderRepository, then gates each output via shouldPrint(... source:
      // 'WAITER') — so the cashier's print rules (incl. the "sources"
      // checkboxes in `printers_management_screen`) decide whether
      // this waiter order produces paper.
      // ignore: unawaited_futures
      _firePrintsForWaiterOrder(orderId, posUser?.firstName,
          wasPaid: wasPaidOnCreate);

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
            print('⚠️ Waiter order autoSync failed: $e');
            return false;
          });
        }
      } catch (e) {
        print('⚠️ Waiter order autoSync kickoff failed: $e');
      }

      return Response(
        201,
        body: jsonEncode({
          'id': orderId,
          'code': orderCode,
          'message': 'Order created successfully',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterCreateOrder: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create order', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// Sum the just-inserted order's line totals. Mirrors the cashier-side
  /// math in `OrderRepository._buildOrderFullDetails` but skips the
  /// discount factors (the waiter endpoint doesn't accept discount
  /// inputs today): for each `order_products` row, take
  /// `(unitaryPrice + Σ components.price × components.quantity) × quantity`.
  ///
  /// Used by the default-paid path in [_waiterCreateOrder] to compute the
  /// ticket amount.
  /// Generate a unique order code (see [generateOrderCode]) by re-rolling on
  /// the astronomically rare chance the random code already exists. Falls back
  /// to a timestamp-suffixed code after a few tries to guarantee termination.
  Future<String> _generateUniqueOrderCode(AppDatabase database) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final code = generateOrderCode();
      final existing = await (database.select(database.orders)
            ..where((o) => o.code.equals(code)))
          .getSingleOrNull();
      if (existing == null) return code;
    }
    return 'O${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<double> _computeWaiterOrderTotal(
      AppDatabase database, int orderId) async {
    final products = await (database.select(database.orderProducts)
          ..where((p) => p.orderId.equals(orderId)))
        .get();
    var total = 0.0;
    for (final p in products) {
      final components = await (database.select(database.orderProductComponents)
            ..where((c) => c.orderProductId.equals(p.id)))
          .get();
      var componentTotal = 0.0;
      for (final c in components) {
        componentTotal += c.price * c.quantity;
      }
      total += (p.unitaryPrice + componentTotal) * p.quantity;
    }
    return total;
  }

  /// Background auto-print for a freshly created waiter order. Reads the
  /// saved row back as a [CurrentOrder] (so the print formatters see the
  /// same shape they do on the cashier side), then fires order ticket and
  /// KDS prints — each gated by [PrintingService.shouldPrint] with
  /// `source: 'WAITER'`. The cashier's print-rule config (see
  /// `printers_management_screen.dart`) decides whether any of these
  /// actually produce paper.
  ///
  /// When [wasPaid] is true, ALSO fires `printPaymentDocuments` (customer
  /// receipt + store copy) — the cashier post-payment flow. Same source
  /// gate applies; the cashier can opt out per-rule.
  ///
  /// [cashierName] is the POS user logged in when the waiter order arrived —
  /// the order is attributed to them (`createdBy`), so the ticket shows the
  /// standard "Cashier" line exactly like a POS-created order. There is no
  /// special waiter-only ticket.
  ///
  /// All exceptions are swallowed: the order is already persisted, the
  /// waiter app already got its 201, and a printer outage must not crash
  /// the server isolate.
  Future<void> _firePrintsForWaiterOrder(int orderId, String? cashierName,
      {bool wasPaid = false}) async {
    try {
      final orderRepo = _ref.read(orderRepositoryProvider);
      final printingService = _ref.read(printingServiceProvider);
      final currentOrder = await orderRepo.getOrderById(orderId);
      if (currentOrder == null) {
        print('⚠️ _firePrintsForWaiterOrder: order $orderId not found post-insert');
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
          print('⚠️ Waiter orderTicket print failed: $e');
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
          print('⚠️ Waiter KDS print failed: $e');
        }
      }

      // Default-paid path: fire the cashier post-payment prints (customer
      // receipt + store copy). printPaymentDocuments internally calls
      // shouldPrint for each output with source:'WAITER', so the cashier
      // can disable per-rule from printers_management without touching
      // server code. Look up the freshly created ticket by orderId; the
      // default-paid branch always inserts exactly one with num='0001'.
      if (wasPaid) {
        try {
          final database = _ref.read(databaseProvider);
          final ticket = await (database.select(database.tickets)
                ..where((t) => t.orderId.equals(orderId)))
              .getSingleOrNull();
          if (ticket != null) {
            final itemsForPrint = currentOrder.items.map((item) {
              return {
                'name': item.displayName,
                'quantity': item.quantity,
                'price': item.totalPrice,
                'components': item.components
                    .map((c) => {'name': c.name, 'quantity': c.quantity})
                    .toList(),
              };
            }).toList();

            await printingService.printPaymentDocuments(
              ticketId: ticket.id,
              ticketNumber: ticket.num,
              amount: ticket.amount,
              paymentMethod: ticket.paymentMethod,
              createdAt: ticket.date,
              items: itemsForPrint,
              orderType: currentOrder.type,
              hasTable: hasTable,
              source: 'WAITER',
              orderCode: currentOrder.orderCode,
              cashierName: cashierName,
              storeName: storeName,
              storeAddress: storeAddress,
              storePhone: storePhone,
              customerName: currentOrder.customerName,
              customerPhone: currentOrder.customerPhone,
              tableName: currentOrder.tableName,
              numberOfPersons: currentOrder.numberOfPersons,
            );
          }
        } catch (e) {
          print('⚠️ Waiter paymentDocuments print failed: $e');
        }
      }
    } catch (e, st) {
      print('❌ _firePrintsForWaiterOrder failed: $e\n$st');
    }
  }

  /// Background KDS print after a waiter appends a product to an existing
  /// order. Prints in `modificationsOnly` mode so ONLY the just-added,
  /// not-yet-printed items reach the kitchen — same behaviour as the
  /// cashier-side "add to open order" flow. Gated by the same `kds` print
  /// rule (`source: 'WAITER'`). [cashierName] is the current POS user, so the
  /// kitchen ticket carries the standard cashier line. Exceptions swallowed:
  /// the product is already saved and the waiter app already got its 200.
  Future<void> _fireKdsForWaiterAddedProduct(
      int orderId, String? cashierName) async {
    try {
      final printingService = _ref.read(printingServiceProvider);
      if (!printingService.config.kdsEnabled) return;
      final orderRepo = _ref.read(orderRepositoryProvider);
      final currentOrder = await orderRepo.getOrderById(orderId);
      if (currentOrder == null) {
        print('⚠️ _fireKdsForWaiterAddedProduct: order $orderId not found');
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
      print('❌ _fireKdsForWaiterAddedProduct failed: $e\n$st');
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
        print('⚠️ Waiter reprint orderTicket failed: $e');
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
          print('⚠️ Waiter reprint KDS failed: $e');
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
      print('❌ _waiterPrintOrder failed: $e\n$st');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to print', 'details': e.toString()}),
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
      final productId = json['productId'] as int?;
      final variantId = json['variantId'] as int?;
      final quantity = json['quantity'] as int? ?? 1;
      final productNote = json['note'] as String?;
      final components = json['components'] as List<dynamic>? ?? [];

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

      // Use variant price/TVA if a variantId is provided
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
          unitDiscount = 0.0;
        }
      }

      // Insert product
      final orderProductId = await database.into(database.orderProducts).insert(
        OrderProductsCompanion.insert(
          orderId: order.id,
          productId: productId,
          variantId: drift.Value(variantId),
          quantity: drift.Value(quantity),
          unitaryPrice: unitPrice,
          unitaryDiscount: drift.Value(unitDiscount),
          unitaryTva: drift.Value(unitTva),
          note: drift.Value(productNote),
          state: const drift.Value('PENDING'),
        ),
      );

      // Insert components
      for (final compJson in components) {
        final componentId = compJson['componentId'] as int;
        final compQuantity = compJson['quantity'] as int? ?? 1;
        final price = (compJson['price'] as num?)?.toDouble() ?? 0.0;

        await database.into(database.orderProductComponents).insert(
          OrderProductComponentsCompanion.insert(
            orderProductId: orderProductId,
            componentId: componentId,
            quantity: drift.Value(compQuantity),
            price: drift.Value(price),
            isSpecial: const drift.Value(false),
          ),
        );
      }

      // Update order timestamp
      await (database.update(database.orders)..where((o) => o.id.equals(order.id)))
        .write(OrdersCompanion(updatedAt: drift.Value(DateTime.now())));

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
      // ignore: unawaited_futures
      _fireKdsForWaiterAddedProduct(order.id, posUser?.firstName);

      return Response.ok(
        jsonEncode({'message': 'Product added to order successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterAddProductToOrder: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to add product', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  // ==================== HELPER METHODS ====================

  /// Build SocketOrderModel from database order
  Future<SocketOrderModel?> _buildSocketOrder(Order order, String? stationFilter) async {
    final database = _ref.read(databaseProvider);

    // Get order products first - if none, return null
    final orderProducts = await (database.select(database.orderProducts)
      ..where((tbl) => tbl.orderId.equals(order.id)))
        .get();

    if (orderProducts.isEmpty) {
      print('⚠️ Order ${order.code} has no products, skipping...');
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
    final allComponentIds = (allComponents as List)
        .map((c) => c.componentId as int)
        .toSet()
        .toList();
    final componentDetailsList = allComponentIds.isNotEmpty
        ? await (database.select(database.components)
            ..where((tbl) => tbl.id.isIn(allComponentIds)))
            .get()
        : <Component>[];
    final componentsMap = {for (final c in componentDetailsList) c.id: c};

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

      // Filter by station if specified: keep the item if ANY of its stations matches.
      if (stationFilter != null) {
        final matches = stationIds.any(
            (id) => stationsMap[id]?.name?.toLowerCase() == stationFilter.toLowerCase());
        if (!matches) continue;
      }

      // Station name to surface: the matching station when filtering, else the primary.
      String? stationName;
      if (stationFilter != null) {
        stationName = stationsMap.values
            .firstWhere(
              (s) => stationIds.contains(s.id) &&
                  s.name.toLowerCase() == stationFilter.toLowerCase(),
              orElse: () => null,
            )
            ?.name;
      } else if (product.stationId != null) {
        stationName = stationsMap[product.stationId]?.name;
      }

      // Get components for this order product
      final productComponents = componentsByOrderProduct[orderProduct.id] ?? [];

      final socketComponents = <SocketOrderProductComponentModel>[];
      for (final comp in productComponents) {
        final component = componentsMap[comp.componentId];

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
        stationId: product.stationId,
        stationName: stationName,
        components: socketComponents,
        note: orderProduct.note,
        tvaAmount: orderProduct.unitaryTva,
        discountAmount: orderProduct.unitaryDiscount,
      ));
    }

    // If no products after filtering, return null
    if (socketProducts.isEmpty) {
      print('⚠️ Order ${order.code} has no products after station filter, skipping...');
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
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    );
  }

  // ==================== GETTERS ====================

  bool get isRunning => _isRunning;
  int get port => _port;
  String? get serverPassword => _serverPassword;
}


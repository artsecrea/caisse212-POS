import 'package:drift/drift.dart';
import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart';
import '../domain/models/external_order_models.dart';
import '../domain/models/live_external_order.dart';
import '../domain/models/order_money_rows.dart' show componentsPerUnitOf;
import 'api_service.dart';
import 'customer_repository.dart';
import 'product_cost_resolver.dart';
import 'external_item_resolver.dart';
import 'z_day_resolver.dart';
import '../domain/services/external_order_service.dart';

/// Handles the external order queue.
///
/// Two key responsibilities:
///   1. Fetch PENDING items from the server for display.
///   2. On cashier action (confirm or cancel), call the matching server
///      endpoint then persist the order locally.
///
/// **The backend NEVER saves the order content.** The POS owns the
/// `orders` table; queue endpoints only flip queue state and forward it
/// to DealUp. The locally-inserted order row goes up to the server on
/// the next normal sync push (`PUT /pos/orders/{code}`).
class ExternalOrderQueueService implements ExternalOrderService {
  final ApiService _api;
  final AppDatabase _db;
  // Read on each confirm so a settings change applies without a rebuild.
  final String Function()? _orderNumberMode;

  ExternalOrderQueueService(this._api, this._db, [this._orderNumberMode]);

  late final _resolver = ExternalItemResolver(_db);

  /// Fill in local product ids the server could not.
  ///
  /// Runs on every item the POS receives, from any path — the queued payload is
  /// frozen when the platform sends it, but this terminal matches against a
  /// catalogue that has moved on since, so a line the server marked unmapped is
  /// very often resolvable here. Nothing is asked of the cashier.
  Future<ExternalQueueItem> resolve(ExternalQueueItem item) async {
    // Cheap exit for the overwhelmingly common case: the server resolved it all.
    if (!item.order.hasUnmappedItems) return item;
    final resolved =
        await _resolver.resolveOrder(item.order, source: item.source);
    return item.copyWith(order: resolved);
  }

  Future<List<ExternalQueueItem>> _resolveAll(
      List<ExternalQueueItem> items) async {
    final out = <ExternalQueueItem>[];
    for (final i in items) {
      out.add(await resolve(i));
    }
    return out;
  }

  /// Fetches all PENDING queue items from the server.
  Future<List<ExternalQueueItem>> fetchPending() async {
    final raw = await _api.fetchPendingQueueItems();
    return _resolveAll(raw
        .map((j) => ExternalQueueItem.fromJson(j))
        .where((item) => item.status == 'PENDING')
        .toList());
  }

  /// Paged browse with optional source/status filters.
  ///
  /// Falls back to the flat `/pending` list when the paged endpoint isn't
  /// available (an older backend), so a terminal pointed at an out-of-date
  /// server still shows its actionable orders instead of an error screen. The
  /// fallback is synthesised into a single page and only makes sense for the
  /// PENDING view, which is what `/pending` returns.
  @override
  Future<QueuePage> browse({
    int page = 0,
    int size = 20,
    String? source,
    String? status,
  }) async {
    try {
      final raw = await _api.fetchQueuePage(
          page: page, size: size, source: source, status: status);
      final parsed = QueuePage.fromJson(raw);
      // Resolve here too: the browse list is what the confirm screen renders,
      // so a line only fixed on the /pending path would still look unmappable.
      return parsed.copyWith(content: await _resolveAll(parsed.content));
    } catch (e) {
      final wantsPendingOnly = status == null || status == 'PENDING';
      if (!wantsPendingOnly) rethrow;
      Logger.instance.warning(
          'Queue browse unavailable, falling back to /pending: $e');
      var items = await fetchPending();
      if (source != null && source.isNotEmpty) {
        items = items.where((i) => matchesSource(i.source, source)).toList();
      }
      return QueuePage(
        content: items,
        page: 0,
        size: items.length,
        totalElements: items.length,
        totalPages: 1,
        first: true,
        last: true,
      );
    }
  }

  /// `OTHER` is defined by the contract as "any source outside WEB/GLOVO/KOOUL",
  /// so it can't be matched by equality — DealUp and WhatsApp both land there.
  static bool matchesSource(String itemSource, String filter) {
    final s = itemSource.toUpperCase();
    if (filter == 'OTHER') {
      return s != 'WEB' && s != 'GLOVO' && s != 'KOOUL';
    }
    return s == filter.toUpperCase();
  }

  /// Per-source tallies for the filter chips. Never throws — a missing badge
  /// must not take the screen down with it.
  /// Orders already accepted into the POS from an external platform, from
  /// the last 24 hours, newest first, as they change: read from the local
  /// database, not the queue endpoint, so the counter sees what the order
  /// holds now, edits included, and keeps working offline. "External" is
  /// `source` set to anything but POS.
  @override
  Stream<List<LiveExternalOrder>> watchLiveOrders() {
    final db = _db;

    // Yesterday, not today: a late-night order handed over after midnight is
    // still the order in front of you.
    final since = DateTime.now().subtract(const Duration(hours: 24));

    final query = db.select(db.orders)
      ..where((o) =>
          o.source.isNotNull() &
          o.source.equals('POS').not() &
          o.date.isBiggerOrEqualValue(since))
      ..orderBy([(o) => OrderingTerm.desc(o.date)]);

    return query.watch().asyncMap((orders) async {
      if (orders.isEmpty) return const <LiveExternalOrder>[];

      final orderIds = orders.map((o) => o.id).toList();
      final lines = await (db.select(db.orderProducts)
            ..where((p) => p.orderId.isIn(orderIds)))
          .get();

      final components = lines.isEmpty
          ? const <OrderProductComponent>[]
          : await (db.select(db.orderProductComponents)
                ..where((c) => c.orderProductId.isIn([for (final l in lines) l.id])))
              .get();
      final componentsByLine = <int, List<OrderProductComponent>>{};
      for (final c in components) {
        componentsByLine.putIfAbsent(c.orderProductId, () => []).add(c);
      }
      final perUnit = {
        for (final e in componentsByLine.entries)
          e.key: componentsPerUnitOf(e.value),
      };

      final productIds = lines.map((l) => l.productId).toSet().toList();
      final products = productIds.isEmpty
          ? const <Product>[]
          : await (db.select(db.products)..where((p) => p.id.isIn(productIds)))
              .get();
      final names = {for (final p in products) p.id: p.name};

      final clientIds =
          orders.map((o) => o.clientId).whereType<int>().toSet().toList();
      final customers = clientIds.isEmpty
          ? const <Customer>[]
          : await (db.select(db.customers)..where((c) => c.id.isIn(clientIds)))
              .get();
      final byClient = {for (final c in customers) c.id: c};

      final byOrder = <int, List<OrderProduct>>{};
      for (final l in lines) {
        byOrder.putIfAbsent(l.orderId, () => []).add(l);
      }

      return [
        for (final o in orders)
          LiveExternalOrder(
            order: o,
            lines: byOrder[o.id] ?? const [],
            productNames: names,
            componentsPerUnit: perUnit,
            customer: o.clientId == null ? null : byClient[o.clientId!],
          ),
      ];
    });
  }

  /// Tell the platform [order] is waiting on the counter: a signal, not a
  /// state change — only `deliveryStatus` advances, and a failure is
  /// reported, never queued (a late "ready" is worse than none). False
  /// when the order has not reached the backend yet or the network is down.
  @override
  Future<bool> signalReady(Order order) async {
    final api = _api;
    final db = _db;

    final signalled = await api.signalOrderReady(order.code);
    if (!signalled) return false;

    await (db.update(db.orders)..where((o) => o.id.equals(order.id)))
        .write(OrdersCompanion(
      deliveryStatus: const Value(DeliveryStatus.ready),
      updatedAt: Value(DateTime.now()),
    ));
    Logger.instance.info('Signalled ready for pickup: order ${order.code}');
    return true;
  }

  @override
  Future<QueueCounts> counts({String? status}) async {
    final raw = await _api.fetchQueueCounts(status: status);
    return QueueCounts.fromJson(raw);
  }

  /// Confirms [item] on the server (state PENDING→CONFIRMED, DealUp
  /// notified), then writes the order + products to local SQLite.
  ///
  /// Local row is inserted with `isSynced=false` and `status=PENDING`
  /// so the next sync push uploads it via the normal order endpoints.
  ///
  /// - [confirmedByUserId] is stored as `createdBy`.
  /// - [overrideClientId] short-circuits the phone-based customer upsert
  ///   when the cashier picked / modified the customer via the review
  ///   dialog. Otherwise the queue's name/phone goes through the upsert.
  ///
  /// Throws [QueueItemTakenException] when another POS terminal already
  /// confirmed or cancelled this item — the caller should drop it from
  /// the queue view and surface a "taken" toast.
  ///
  /// Returns the local order row id.
  @override
  Future<int> confirmAndSave(ExternalQueueItem item,
      {int? confirmedByUserId, int? overrideClientId}) async {
    // 1. Server-side confirm. Throws QueueItemTakenException on 409 so
    //    the caller can drop the item from the queue without surfacing a
    //    generic error toast.
    final raw = await _api.confirmQueueItem(item.id);
    final result = QueueStateResult.fromJson(raw);
    final orderCode = result.orderCode ?? item.orderCode;
    Logger.instance.info(
        'ExternalOrderQueueService: confirmed ${item.orderCode} → status=${result.status}');

    // 2. Save the order locally with isSynced=false so it pushes up via
    //    the normal sync path. Status PENDING is the standard "new
    //    order" state the rest of the app expects.
    final localOrderId = await _insertLocalOrder(
      item: item,
      orderCode: orderCode,
      status: 'PENDING',
      confirmedByUserId: confirmedByUserId,
      overrideClientId: overrideClientId,
    );

    Logger.instance.info(
        'ExternalOrderQueueService: order $orderCode written to local DB (id=$localOrderId)');
    return localOrderId;
  }

  /// Cancels [item] on the server (state → CANCELLED, DealUp notified),
  /// then writes the order locally with `status=CANCELED` and
  /// `isSynced=false` so the cancellation propagates to the backend on
  /// the next sync push.
  ///
  /// 409 from the server (already cancelled) is treated as success —
  /// the desired end state is reached; we still save the local row for
  /// the audit trail.
  ///
  /// Returns the local order row id.
  @override
  Future<int> cancelAndSave(ExternalQueueItem item,
      {int? confirmedByUserId}) async {
    final raw = await _api.cancelQueueItem(item.id);
    final result = QueueStateResult.fromJson(raw);
    final orderCode = result.orderCode ?? item.orderCode;
    Logger.instance.info(
        'ExternalOrderQueueService: cancelled ${item.orderCode} → status=${result.status}');

    // No customer upsert on cancel — the order's being rejected; we
    // don't onboard a customer for a rejected order. Falls back to the
    // server-supplied customerId so the local row still has a clientId
    // reference for analytics / display.
    final localOrderId = await _insertLocalOrder(
      item: item,
      orderCode: orderCode,
      status: 'CANCELED',
      confirmedByUserId: confirmedByUserId,
      overrideClientId: null,
      skipCustomerUpsert: true,
      cancellationReason: 'Rejected from external queue',
    );

    Logger.instance.info(
        'ExternalOrderQueueService: cancelled order $orderCode written to local DB (id=$localOrderId)');
    return localOrderId;
  }

  /// Shared local-insert path used by both confirm and cancel. Wraps
  /// customer-upsert (when applicable) + order row + products +
  /// components in a single transaction.
  Future<int> _insertLocalOrder({
    required ExternalQueueItem item,
    required String orderCode,
    required String status,
    required int? confirmedByUserId,
    required int? overrideClientId,
    bool skipCustomerUpsert = false,
    String? cancellationReason,
  }) async {
    // The shift taking the order in. A delivery-platform order is a sale on
    // whichever session is open when the cashier accepts it, so it is bound
    // to that session exactly like a walk-in — previously it was bound to
    // nothing, and an order with no session and no z_day left the backend to
    // fall back to `createdAt`, which here is the PLATFORM's timestamp: an
    // order placed at 23:50 and accepted at 00:10 was booked to the wrong day
    // in one direction, and yesterday's backlog to the wrong day in the other.
    //
    // Resolved before the transaction: it only reads, and the drift
    // connection is single-threaded.
    final zResolver = ZDayResolver(_db);
    final activeSession = await zResolver.activeSession();
    final externalZDay = await zResolver.forSession(activeSession?.id);

    late int localOrderId;
    await _db.transaction(() async {
      // 1. Resolve / upsert the local customer id.
      int? localClientId = overrideClientId;
      if (localClientId == null && !skipCustomerUpsert) {
        final phone = item.order.customerPhone?.trim() ?? '';
        if (phone.isNotEmpty) {
          final fullName = (item.order.customerName ?? '').trim();
          final parts = fullName.isEmpty
              ? const <String>[]
              : fullName.split(RegExp(r'\s+'));
          final firstName = parts.isNotEmpty ? parts.first : '';
          final lastName =
              parts.length > 1 ? parts.sublist(1).join(' ') : '';
          localClientId = await CustomerRepository(_db).upsertByPhone(
            phoneRaw: phone,
            firstName: firstName,
            lastName: lastName,
            // The customer carries `isSynced=false` because the queue
            // confirm endpoint no longer persists customers either —
            // the regular customer sync push handles it.
            isSynced: false,
          );
        }
      }

      // 2. Insert the order. POS now owns the id (autoincrement; we
      //    don't pass one). isSynced=false so the sync push uploads
      //    this fresh order via the regular order endpoints.
      localOrderId = await _db.into(_db.orders).insert(
            OrdersCompanion(
              code: Value(orderCode),
              status: Value(status),
              type: Value(item.order.type),
              source: Value(item.source),
              sourceId: Value(item.id),
              // The PLATFORM's own order id (e.g. "glovo-123"), echoed back on
              // every re-sync so the server can close the reconciliation loop.
              //
              // This previously stored `item.orderCode` — the POS's own code,
              // which is a different identifier entirely. The model carries the
              // real value now. Left null when the platform didn't supply one:
              // the contract says the server backfills from the queue by code,
              // and a wrong id is worse than an absent one.
              externalOrderId: Value(item.externalOrderId),
              // The courier-facing code, copied onto the ORDER so reprints
              // still work after the queue row is purged at 7 days.
              externalOrderCode: Value(item.order.externalOrderCode),
              // The platform's delivery charge, copied onto the local order so
              // it survives the queue's 7-day purge and rides up to the server
              // on the normal order push (`_orderContractFields`). Left null
              // when the platform sent none — an absent fee is not a free one.
              deliveryFee: Value(item.order.deliveryFee),
              // Orders created from a delivery queue also carry the order date
              // the platform reported, not the moment we ingested it.
              date: Value(item.createdAt),
              clientId: Value(localClientId ?? item.customerId),
              note: Value(item.order.note),
              address: Value(item.order.address),
              courierName: Value(item.order.courierName),
              courierPhone: Value(item.order.courierPhone),
              cancellationReason: Value(cancellationReason),
              isSynced: const Value(false),
              persons: const Value(1),
              priority: const Value(0),
              discountPercentage: const Value(0.0),
              createdBy: Value(confirmedByUserId),
              // Bound to the shift that accepted it — see [externalZDay].
              sessionId: Value(activeSession?.id),
              sessionOrderNo: Value(await _db.nextSessionOrderNo(
                  activeSession?.id,
                  mode: _orderNumberMode?.call() ?? 'session')),
              zDay: Value(externalZDay),
              createdAt: Value(item.createdAt),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // 3. Insert order products — resolve prices from local catalog.
      final costResolver = ProductCostResolver(_db);
      for (final qItem in item.order.items) {
        final product = await (_db.select(_db.products)
              ..where((p) => p.id.equals(qItem.productId)))
            .getSingleOrNull();
        final price = product?.finalPrice ?? 0.0;
        final tva = product?.tvaAmount ?? 0.0;

        final orderProductId =
            await _db.into(_db.orderProducts).insert(
                  OrderProductsCompanion.insert(
                    orderId: localOrderId,
                    productId: qItem.productId,
                    variantId: Value(qItem.variantId),
                    quantity: Value(qItem.quantity.toDouble()),
                    unitaryPrice: price,
                    // Online orders need a cost like any other sale, or every
                    // Glovo/WhatsApp line reports an unknown margin.
                    cost: await costResolver.resolveValue(
                        productId: qItem.productId,
                        variantId: qItem.variantId),
                    unitaryTva: Value(tva),
                    note: Value(qItem.note),
                    state: const Value('PENDING'),
                    zDay: Value(externalZDay),
                  ),
                );

        // 4. Components.
        for (final comp in qItem.components) {
          final component = await (_db.select(_db.components)
                ..where((c) => c.id.equals(comp.componentId)))
              .getSingleOrNull();
          final compPrice = component?.price ?? 0.0;

          await _db.into(_db.orderProductComponents).insert(
                OrderProductComponentsCompanion.insert(
                  componentId: comp.componentId,
                  orderProductId: orderProductId,
                  quantity: Value(comp.quantity),
                  price: Value(compPrice),
                  name: Value(component?.name),
                ),
              );
        }
      }
    });
    return localOrderId;
  }
}

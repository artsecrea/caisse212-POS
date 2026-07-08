import 'package:drift/drift.dart' show Value;
import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart';
import '../domain/models/external_order_models.dart';
import 'api_service.dart';
import 'customer_repository.dart';

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
class ExternalOrderQueueService {
  final ApiService _api;
  final AppDatabase _db;

  ExternalOrderQueueService(this._api, this._db);

  /// Fetches all PENDING queue items from the server.
  Future<List<ExternalQueueItem>> fetchPending() async {
    final raw = await _api.fetchPendingQueueItems();
    return raw
        .map((j) => ExternalQueueItem.fromJson(j))
        .where((item) => item.status == 'PENDING')
        .toList();
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
              clientId: Value(localClientId ?? item.customerId),
              note: Value(item.order.note),
              cancellationReason: Value(cancellationReason),
              isSynced: const Value(false),
              persons: const Value(1),
              priority: const Value(0),
              discountPercentage: const Value(0.0),
              createdBy: Value(confirmedByUserId),
              createdAt: Value(item.createdAt),
              updatedAt: Value(DateTime.now()),
            ),
          );

      // 3. Insert order products — resolve prices from local catalog.
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
                    unitaryTva: Value(tva),
                    note: Value(qItem.note),
                    state: const Value('PENDING'),
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
                ),
              );
        }
      }
    });
    return localOrderId;
  }
}

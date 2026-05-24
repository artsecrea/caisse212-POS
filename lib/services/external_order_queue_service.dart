import 'package:drift/drift.dart' show Value, InsertMode;
import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart';
import '../domain/models/external_order_models.dart';
import 'api_service.dart';

/// Handles the external order queue:
/// - Fetches pending items from the server
/// - Acknowledges a queue item and writes the resulting order to local SQLite
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

  /// Acknowledges [item] on the server, then writes the order + products to
  /// local SQLite with [isSynced = true] so the sync worker skips it.
  ///
  /// [confirmedByUserId] is stored as [createdBy] on the local order row.
  /// Returns the local order ID on success.
  /// Throws on any error — caller must NOT write locally if this throws.
  Future<int> acknowledgeAndSave(ExternalQueueItem item,
      {int? confirmedByUserId}) async {
    // 1. Acknowledge on server first
    final raw = await _api.acknowledgeQueueItem(item.id);
    final ack = AcknowledgeResult.fromJson(raw);
    Logger.instance.info(
        'ExternalOrderQueueService: acknowledged ${item.orderCode} → orderId=${ack.orderId}');

    // 2. Write to local DB in a transaction
    await _db.transaction(() async {
      // Insert order — use server-assigned id and code
      await _db.into(_db.orders).insert(
        OrdersCompanion(
          id: Value(ack.orderId),
          code: Value(ack.orderCode),
          status: const Value('PENDING'),
          type: Value(item.order.type),
          source: Value(item.source),
          sourceId: Value(item.id),
          clientId: Value(item.customerId),
          note: Value(item.order.note),
          isSynced: const Value(true), // already persisted server-side
          persons: const Value(1),
          priority: const Value(0),
          discountPercentage: const Value(0.0),
          createdBy: Value(confirmedByUserId),
          createdAt: Value(item.createdAt),
          updatedAt: Value(DateTime.now()),
        ),
        mode: InsertMode.insertOrIgnore, // idempotent on retry
      );

      // 3. Insert order products — resolve prices from local product catalog
      for (final qItem in item.order.items) {
        final product = await (_db.select(_db.products)
              ..where((p) => p.id.equals(qItem.productId)))
            .getSingleOrNull();
        final price = product?.finalPrice ?? 0.0;
        final tva = product?.tvaAmount ?? 0.0;

        final orderProductId =
            await _db.into(_db.orderProducts).insert(
          OrderProductsCompanion.insert(
            orderId: ack.orderId,
            productId: qItem.productId,
            variantId: Value(qItem.variantId),
            quantity: Value(qItem.quantity),
            unitaryPrice: price,
            unitaryTva: Value(tva),
            note: Value(qItem.note),
            state: const Value('PENDING'),
          ),
        );

        // 4. Insert components
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

    Logger.instance.info(
        'ExternalOrderQueueService: order ${ack.orderId} written to local DB');
    return ack.orderId;
  }
}

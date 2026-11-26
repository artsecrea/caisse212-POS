import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/models/order_models.dart';
import '../domain/services/floor_service.dart';
import '../providers/database_providers.dart';
import '../providers/order_provider.dart';
import 'order_log_service.dart';

/// [FloorService] on this till's own database: the standalone till. Every
/// action is the [OrderRepository] method the screens called before, so the
/// floor behaves exactly as it did.
class LocalFloorService implements FloorService {
  LocalFloorService(this._database, this._orders);

  final AppDatabase _database;
  final OrderRepository _orders;

  @override
  Stream<List<AreaTable>> watchTables() =>
      _database.select(_database.areaTables).watch();

  @override
  Future<CurrentOrder?> openTable(int tableId) =>
      _orders.getOrderByTable(tableId);

  @override
  Future<void> transfer(
    int orderId, {
    int? fromTableId,
    required int toTableId,
    FloorActor by = const ByCashier(),
  }) =>
      _orders.transferOrderToTable(orderId, fromTableId, toTableId,
          byWaiterId: switch (by) {
            ByWaiter(:final waiterId) => waiterId,
            ByCashier() => null,
          });

  /// A waiter's release is written on the order it freed, as the waiter API
  /// always has; the cashier's is not logged.
  @override
  Future<void> clearTable(int tableId,
      {FloorActor by = const ByCashier()}) async {
    if (by is! ByWaiter) return _orders.clearTableOrder(tableId);
    final held = await (_database.select(_database.areaTables)
          ..where((t) => t.id.equals(tableId)))
        .getSingleOrNull();
    await _orders.clearTableOrder(tableId);
    if (held?.orderId != null) {
      await OrderLogService(_database).logOrderUpdated(
          held!.orderId!, 'Table #$tableId cleared by waiter #${by.waiterId}');
    }
  }

  @override
  Future<int> reconcile({required bool freeOnPayment}) =>
      _orders.reconcileTableOccupancy(freeOnPayment: freeOnPayment);

  @override
  Future<void> freeTablesForSession(int sessionId) =>
      _orders.clearTablesForSession(sessionId);
}

/// The floor's actions for the screens. A hub-linked till overrides this one
/// provider; nothing else changes.
final floorServiceProvider = Provider<FloorService>((ref) => LocalFloorService(
      ref.watch(databaseProvider),
      ref.watch(orderRepositoryProvider),
    ));

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/models/order_models.dart';
import '../domain/services/floor_service.dart';
import '../providers/database_providers.dart';
import '../providers/order_provider.dart';

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
    required int fromTableId,
    required int toTableId,
  }) =>
      _orders.transferOrderToTable(orderId, fromTableId, toTableId);

  @override
  Future<void> clearTable(int tableId) => _orders.clearTableOrder(tableId);

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

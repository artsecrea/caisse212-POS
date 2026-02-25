import 'package:drift/drift.dart';
import '../data/database/app_database.dart';

/// Service to log order changes for syncing
class OrderLogService {
  final AppDatabase database;

  OrderLogService(this.database);

  /// Log order creation
  Future<void> logOrderCreated(int orderId, String description) async {
    await database.into(database.orderLogs).insert(
      OrderLogsCompanion.insert(
        orderId: orderId,
        action: 'CREATED',
        description: Value(description),
      ),
    );
  }

  /// Log order update
  Future<void> logOrderUpdated(int orderId, String description) async {
    await database.into(database.orderLogs).insert(
      OrderLogsCompanion.insert(
        orderId: orderId,
        action: 'UPDATED',
        description: Value(description),
      ),
    );
  }

  /// Log order deletion
  Future<void> logOrderDeleted(int orderId, String description) async {
    await database.into(database.orderLogs).insert(
      OrderLogsCompanion.insert(
        orderId: orderId,
        action: 'DELETED',
        description: Value(description),
      ),
    );
  }

  /// Get updated orders since a specific log ID
  Future<List<int>> getUpdatedOrdersSinceLogId(int logId) async {
    final logs = await (database.select(database.orderLogs)
          ..where((tbl) => tbl.id.isBiggerThanValue(logId))
          ..where((tbl) => tbl.action.equals('UPDATED')))
        .get();

    return logs.map((log) => log.orderId).toSet().toList();
  }

  /// Get deleted order IDs since a specific log ID
  Future<List<int>> getDeletedOrdersSinceLogId(int logId) async {
    final logs = await (database.select(database.orderLogs)
          ..where((tbl) => tbl.id.isBiggerThanValue(logId))
          ..where((tbl) => tbl.action.equals('DELETED')))
        .get();

    return logs.map((log) => log.orderId).toSet().toList();
  }

  /// Get updated orders for today
  Future<List<int>> getUpdatedOrdersToday() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final logs = await (database.select(database.orderLogs)
          ..where((tbl) => tbl.timestamp.isBiggerOrEqualValue(startOfDay))
          ..where((tbl) => tbl.action.equals('UPDATED')))
        .get();

    return logs.map((log) => log.orderId).toSet().toList();
  }

  /// Get deleted order IDs for today
  Future<List<int>> getDeletedOrdersToday() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);

    final logs = await (database.select(database.orderLogs)
          ..where((tbl) => tbl.timestamp.isBiggerOrEqualValue(startOfDay))
          ..where((tbl) => tbl.action.equals('DELETED')))
        .get();

    return logs.map((log) => log.orderId).toSet().toList();
  }

  /// Get the highest log ID for updated orders
  Future<int> getLastUpdateLogId() async {
    final result = await (database.selectOnly(database.orderLogs)
          ..addColumns([database.orderLogs.id.max()])
          ..where(database.orderLogs.action.equals('UPDATED')))
        .getSingleOrNull();

    return result?.read(database.orderLogs.id.max()) ?? 0;
  }
}


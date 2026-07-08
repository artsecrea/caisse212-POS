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
        timestamp: Value(DateTime.now()),
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
        timestamp: Value(DateTime.now()),
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
        timestamp: Value(DateTime.now()),
      ),
    );
  }

  /// Get updated orders since a specific log ID (no date bound)
  Future<List<int>> getUpdatedOrdersSinceLogId(int logId) async {
    final logs = await (database.select(database.orderLogs)
          ..where((tbl) => tbl.id.isBiggerThanValue(logId))
          ..where((tbl) => tbl.action.equals('UPDATED')))
        .get();
    return logs.map((log) => log.orderId).toSet().toList();
  }

  /// Get deleted order IDs since a specific log ID (no date bound)
  Future<List<int>> getDeletedOrdersSinceLogId(int logId) async {
    final logs = await (database.select(database.orderLogs)
          ..where((tbl) => tbl.id.isBiggerThanValue(logId))
          ..where((tbl) => tbl.action.equals('DELETED')))
        .get();
    return logs.map((log) => log.orderId).toSet().toList();
  }

  /// Get updated order IDs since a specific log ID AND within a date window.
  /// Date is the primary scope; log ID refines "only new entries since last poll".
  Future<List<int>> getUpdatedOrdersSinceLogIdAndDate(
      int logId, DateTime since) async {
    final logs = await (database.select(database.orderLogs)
          ..where((tbl) => tbl.id.isBiggerThanValue(logId))
          ..where((tbl) => tbl.timestamp.isBiggerOrEqualValue(since))
          ..where((tbl) => tbl.action.equals('UPDATED')))
        .get();
    return logs.map((log) => log.orderId).toSet().toList();
  }

  /// Get deleted order IDs since a specific log ID AND within a date window.
  Future<List<int>> getDeletedOrdersSinceLogIdAndDate(
      int logId, DateTime since) async {
    final logs = await (database.select(database.orderLogs)
          ..where((tbl) => tbl.id.isBiggerThanValue(logId))
          ..where((tbl) => tbl.timestamp.isBiggerOrEqualValue(since))
          ..where((tbl) => tbl.action.equals('DELETED')))
        .get();
    return logs.map((log) => log.orderId).toSet().toList();
  }

  /// Get updated orders whose log entry timestamp >= [since].
  /// Preferred over getUpdatedOrdersToday() when a custom date is provided.
  Future<List<int>> getUpdatedOrdersSinceDate(DateTime since) async {
    final logs = await (database.select(database.orderLogs)
          ..where((tbl) => tbl.timestamp.isBiggerOrEqualValue(since))
          ..where((tbl) => tbl.action.equals('UPDATED')))
        .get();
    return logs.map((log) => log.orderId).toSet().toList();
  }

  /// Get deleted order IDs whose log entry timestamp >= [since].
  Future<List<int>> getDeletedOrdersSinceDate(DateTime since) async {
    final logs = await (database.select(database.orderLogs)
          ..where((tbl) => tbl.timestamp.isBiggerOrEqualValue(since))
          ..where((tbl) => tbl.action.equals('DELETED')))
        .get();
    return logs.map((log) => log.orderId).toSet().toList();
  }

  /// Get updated orders for today (convenience – used when no date param given)
  Future<List<int>> getUpdatedOrdersToday() async {
    final now = DateTime.now();
    return getUpdatedOrdersSinceDate(DateTime(now.year, now.month, now.day));
  }

  /// Get deleted order IDs for today (convenience – used when no date param given)
  Future<List<int>> getDeletedOrdersToday() async {
    final now = DateTime.now();
    return getDeletedOrdersSinceDate(DateTime(now.year, now.month, now.day));
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


import 'package:drift/drift.dart';

/// Table to track operations (delete/update) that need to be synced when online
class PendingSyncOperations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Type of operation: 'DELETE' or 'UPDATE'
  TextColumn get operationType => text().withLength(min: 1, max: 10)();

  /// Entity type: 'ORDER', 'TICKET', 'ORDER_PRODUCT', etc.
  TextColumn get entityType => text().withLength(min: 1, max: 50)();

  /// ID of the entity to delete/update (local database ID)
  IntColumn get entityId => integer()();

  /// Server ID if available (for entities already synced) - DEPRECATED, use orderCode/ticketNum
  IntColumn get serverId => integer().nullable()();
  
  /// Order code for identifying orders on server (unique identifier)
  TextColumn get orderCode => text().nullable()();
  
  /// Ticket num for identifying tickets on server (used with orderCode)
  TextColumn get ticketNum => text().nullable()();

  /// JSON data for UPDATE operations (contains the fields to update)
  TextColumn get updateData => text().nullable()();

  /// Timestamp when the operation was queued
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();

  /// Number of retry attempts
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Last error message if sync failed
  TextColumn get lastError => text().nullable()();
}


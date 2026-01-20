import 'dart:convert';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import 'package:loggecrea/loggecrea.dart';

/// Service to manage pending sync operations (deletes/updates) for offline support
class PendingOperationsService {
  final AppDatabase _database;
  final _logger = Logger.instance;

  PendingOperationsService(this._database);

  /// Queue a delete operation
  Future<void> queueDelete({
    required String entityType,
    required int entityId,
    int? serverId,
  }) async {
    try {
      await _database.into(_database.pendingSyncOperations).insert(
        PendingSyncOperationsCompanion.insert(
          operationType: 'DELETE',
          entityType: entityType,
          entityId: entityId,
          serverId: Value(serverId),
        ),
      );
      _logger.info('Queued DELETE operation for $entityType #$entityId');
    } catch (e) {
      _logger.error('Failed to queue delete operation: $e');
      rethrow;
    }
  }

  /// Queue an update operation
  Future<void> queueUpdate({
    required String entityType,
    required int entityId,
    int? serverId,
    required Map<String, dynamic> updateData,
  }) async {
    try {
      await _database.into(_database.pendingSyncOperations).insert(
        PendingSyncOperationsCompanion.insert(
          operationType: 'UPDATE',
          entityType: entityType,
          entityId: entityId,
          serverId: Value(serverId),
          updateData: Value(jsonEncode(updateData)),
        ),
      );
      _logger.info('Queued UPDATE operation for $entityType #$entityId');
    } catch (e) {
      _logger.error('Failed to queue update operation: $e');
      rethrow;
    }
  }

  /// Get all pending operations
  Future<List<PendingSyncOperation>> getPendingOperations() async {
    return await (_database.select(_database.pendingSyncOperations)
      ..orderBy([
        (tbl) => OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.asc),
      ]))
        .get();
  }

  /// Get pending operations by entity type
  Future<List<PendingSyncOperation>> getPendingOperationsByType(String entityType) async {
    return await (_database.select(_database.pendingSyncOperations)
      ..where((tbl) => tbl.entityType.equals(entityType))
      ..orderBy([
        (tbl) => OrderingTerm(expression: tbl.createdAt, mode: OrderingMode.asc),
      ]))
        .get();
  }

  /// Mark operation as completed and remove from queue
  Future<void> markCompleted(int operationId) async {
    try {
      await (_database.delete(_database.pendingSyncOperations)
        ..where((tbl) => tbl.id.equals(operationId)))
          .go();
      _logger.info('Marked operation #$operationId as completed');
    } catch (e) {
      _logger.error('Failed to mark operation as completed: $e');
      rethrow;
    }
  }

  /// Update retry count and error message
  Future<void> recordFailure(int operationId, String error) async {
    try {
      final operation = await (_database.select(_database.pendingSyncOperations)
        ..where((tbl) => tbl.id.equals(operationId)))
          .getSingleOrNull();

      if (operation != null) {
        await (_database.update(_database.pendingSyncOperations)
          ..where((tbl) => tbl.id.equals(operationId)))
            .write(PendingSyncOperationsCompanion(
          retryCount: Value(operation.retryCount + 1),
          lastError: Value(error),
        ));
        _logger.warning('Recorded failure for operation #$operationId: $error');
      }
    } catch (e) {
      _logger.error('Failed to record operation failure: $e');
    }
  }

  /// Clear all pending operations (use with caution!)
  Future<void> clearAll() async {
    try {
      await _database.delete(_database.pendingSyncOperations).go();
      _logger.info('Cleared all pending operations');
    } catch (e) {
      _logger.error('Failed to clear pending operations: $e');
      rethrow;
    }
  }

  /// Clear operations older than specified days
  Future<void> clearOldOperations({int daysOld = 30}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
      await (_database.delete(_database.pendingSyncOperations)
        ..where((tbl) => tbl.createdAt.isSmallerThanValue(cutoffDate)))
          .go();
      _logger.info('Cleared operations older than $daysOld days');
    } catch (e) {
      _logger.error('Failed to clear old operations: $e');
    }
  }

  /// Get count of pending operations
  Future<int> getPendingCount() async {
    final result = await _database.customSelect(
      'SELECT COUNT(*) as count FROM pending_sync_operations',
      readsFrom: {_database.pendingSyncOperations},
    ).getSingle();
    return result.read<int>('count');
  }
}


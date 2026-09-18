import 'dart:convert';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import 'package:loggecrea/loggecrea.dart';

/// Service to manage pending sync operations (deletes/updates) for offline support
class PendingOperationsService {
  final AppDatabase _database;
  final _logger = Logger.instance;

  PendingOperationsService(this._database);

  /// A pending op that keeps failing is a poison message — after this many
  /// attempts it is skipped (dead-lettered in place) so it can't retry forever
  /// or block the queue on every sync cycle. The row is kept for diagnostics.
  static const int maxRetries = 5;

  /// Insert a pending op, deduplicating against an existing op with the same
  /// (entityType, entityId, operationType):
  ///   - DELETE: idempotent — a second identical delete is skipped.
  ///   - UPDATE: the queued payload is overwritten with the newest state and
  ///     the retry counter reset (older duplicate rows are removed).
  /// This prevents double-taps / repeated failures from piling up duplicate
  /// operations (e.g. two deletes for the same order, the second of which would
  /// fail forever with "not found").
  Future<void> _upsertOperation({
    required String operationType,
    required String entityType,
    required int entityId,
    int? serverId,
    String? updateDataJson,
  }) async {
    final existing = await (_database.select(_database.pendingSyncOperations)
          ..where((t) =>
              t.entityType.equals(entityType) &
              t.entityId.equals(entityId) &
              t.operationType.equals(operationType)))
        .get();

    if (existing.isNotEmpty) {
      if (operationType == 'DELETE') {
        _logger.info(
            'Skipped duplicate DELETE for $entityType #$entityId (already queued)');
        return;
      }
      // UPDATE: refresh the newest row's payload, drop any older duplicates.
      final keep = existing.first;
      await (_database.update(_database.pendingSyncOperations)
            ..where((t) => t.id.equals(keep.id)))
          .write(PendingSyncOperationsCompanion(
        updateData: Value(updateDataJson),
        serverId: Value(serverId),
        retryCount: const Value(0),
        lastError: const Value(null),
        createdAt: Value(DateTime.now()),
      ));
      for (final dup in existing.skip(1)) {
        await (_database.delete(_database.pendingSyncOperations)
              ..where((t) => t.id.equals(dup.id)))
            .go();
      }
      return;
    }

    await _database.into(_database.pendingSyncOperations).insert(
          PendingSyncOperationsCompanion.insert(
            operationType: operationType,
            entityType: entityType,
            entityId: entityId,
            serverId: Value(serverId),
            updateData: updateDataJson != null
                ? Value(updateDataJson)
                : const Value.absent(),
            createdAt: Value(DateTime.now()),
          ),
        );
  }

  /// Queue a delete operation for an order
  Future<void> queueOrderDelete({
    required int entityId,
    required String orderCode,
  }) async {
    try {
      await _upsertOperation(
        operationType: 'DELETE',
        entityType: 'ORDER',
        entityId: entityId,
        updateDataJson: jsonEncode({'_orderCode': orderCode}),
      );
      _logger.info('Queued DELETE operation for ORDER code=$orderCode');
    } catch (e) {
      _logger.error('Failed to queue order delete operation: $e');
      rethrow;
    }
  }

  /// Queue a delete operation for a ticket
  Future<void> queueTicketDelete({
    required int entityId,
    required String orderCode,
    required String ticketNum,
  }) async {
    try {
      await _upsertOperation(
        operationType: 'DELETE',
        entityType: 'TICKET',
        entityId: entityId,
        updateDataJson: jsonEncode({'_orderCode': orderCode, '_ticketNum': ticketNum}),
      );
      _logger.info('Queued DELETE operation for TICKET orderCode=$orderCode, ticketNum=$ticketNum');
    } catch (e) {
      _logger.error('Failed to queue ticket delete operation: $e');
      rethrow;
    }
  }

  /// Queue a delete operation for a session
  Future<void> queueSessionDelete({
    required int entityId,
    required String sessionCode,
  }) async {
    try {
      await _upsertOperation(
        operationType: 'DELETE',
        entityType: 'SESSION',
        entityId: entityId,
        updateDataJson: jsonEncode({'_sessionCode': sessionCode}),
      );
      _logger.info('Queued DELETE operation for SESSION code=$sessionCode');
    } catch (e) {
      _logger.error('Failed to queue session delete operation: $e');
      rethrow;
    }
  }

  /// Queue an update operation for a session
  Future<void> queueSessionUpdate({
    required int entityId,
    required String sessionCode,
    required Map<String, dynamic> updateData,
  }) async {
    try {
      final dataWithMeta = Map<String, dynamic>.from(updateData);
      dataWithMeta['_sessionCode'] = sessionCode;

      await _upsertOperation(
        operationType: 'UPDATE',
        entityType: 'SESSION',
        entityId: entityId,
        updateDataJson: jsonEncode(dataWithMeta),
      );
      _logger.info('Queued UPDATE operation for SESSION code=$sessionCode');
    } catch (e) {
      _logger.error('Failed to queue session update operation: $e');
      rethrow;
    }
  }

  /// Queue a generic delete operation (legacy support)
  Future<void> queueDelete({
    required String entityType,
    required int entityId,
    int? serverId,
    String? orderCode,
    String? ticketNum,
  }) async {
    try {
      // Store orderCode/ticketNum in updateData JSON temporarily
      Map<String, dynamic>? metaData;
      if (orderCode != null || ticketNum != null) {
        metaData = {};
        if (orderCode != null) metaData['_orderCode'] = orderCode;
        if (ticketNum != null) metaData['_ticketNum'] = ticketNum;
      }

      await _upsertOperation(
        operationType: 'DELETE',
        entityType: entityType,
        entityId: entityId,
        serverId: serverId,
        updateDataJson: metaData != null ? jsonEncode(metaData) : null,
      );
      _logger.info('Queued DELETE operation for $entityType #$entityId');
    } catch (e) {
      _logger.error('Failed to queue delete operation: $e');
      rethrow;
    }
  }

  /// Queue an update operation for an order
  Future<void> queueOrderUpdate({
    required int entityId,
    required String orderCode,
    required Map<String, dynamic> updateData,
  }) async {
    try {
      // Include orderCode in updateData (temporarily until database is regenerated)
      final dataWithMeta = Map<String, dynamic>.from(updateData);
      dataWithMeta['_orderCode'] = orderCode;

      await _upsertOperation(
        operationType: 'UPDATE',
        entityType: 'ORDER',
        entityId: entityId,
        updateDataJson: jsonEncode(dataWithMeta),
      );
      _logger.info('Queued UPDATE operation for ORDER code=$orderCode');
    } catch (e) {
      _logger.error('Failed to queue order update operation: $e');
      rethrow;
    }
  }

  /// Queue an update operation for a ticket
  Future<void> queueTicketUpdate({
    required int entityId,
    required String orderCode,
    required String ticketNum,
    required Map<String, dynamic> updateData,
  }) async {
    try {
      // Include orderCode and ticketNum in updateData (temporarily until database is regenerated)
      final dataWithMeta = Map<String, dynamic>.from(updateData);
      dataWithMeta['_orderCode'] = orderCode;
      dataWithMeta['_ticketNum'] = ticketNum;

      await _upsertOperation(
        operationType: 'UPDATE',
        entityType: 'TICKET',
        entityId: entityId,
        updateDataJson: jsonEncode(dataWithMeta),
      );
      _logger.info('Queued UPDATE operation for TICKET orderCode=$orderCode, ticketNum=$ticketNum');
    } catch (e) {
      _logger.error('Failed to queue ticket update operation: $e');
      rethrow;
    }
  }

  /// Queue a generic update operation (legacy support)
  Future<void> queueUpdate({
    required String entityType,
    required int entityId,
    int? serverId,
    String? orderCode,
    String? ticketNum,
    required Map<String, dynamic> updateData,
  }) async {
    try {
      // Include orderCode/ticketNum in updateData JSON temporarily
      final dataWithMeta = Map<String, dynamic>.from(updateData);
      if (orderCode != null) dataWithMeta['_orderCode'] = orderCode;
      if (ticketNum != null) dataWithMeta['_ticketNum'] = ticketNum;

      await _upsertOperation(
        operationType: 'UPDATE',
        entityType: entityType,
        entityId: entityId,
        serverId: serverId,
        updateDataJson: jsonEncode(dataWithMeta),
      );
      _logger.info('Queued UPDATE operation for $entityType #$entityId');
    } catch (e) {
      _logger.error('Failed to queue update operation: $e');
      rethrow;
    }
  }

  /// Get all pending operations still worth retrying (FIFO). Ops that have
  /// exceeded [maxRetries] are excluded — they stay in the table for
  /// diagnostics but no longer retry or block the queue every cycle.
  Future<List<PendingSyncOperation>> getPendingOperations() async {
    return await (_database.select(_database.pendingSyncOperations)
      ..where((tbl) => tbl.retryCount.isSmallerThanValue(maxRetries))
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
        final newCount = operation.retryCount + 1;
        await (_database.update(_database.pendingSyncOperations)
          ..where((tbl) => tbl.id.equals(operationId)))
            .write(PendingSyncOperationsCompanion(
          retryCount: Value(newCount),
          lastError: Value(error),
        ));
        if (newCount >= maxRetries) {
          _logger.error(
              'Operation #$operationId dead-lettered after $newCount attempts '
              '(${operation.entityType} ${operation.operationType} #${operation.entityId}): $error');
        } else {
          _logger.warning('Recorded failure for operation #$operationId (attempt $newCount): $error');
        }
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


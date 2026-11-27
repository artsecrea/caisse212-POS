import '../../data/database/app_database.dart' show PendingSyncOperation;

/// The writes waiting to be sent, as the sync screens inspect and settle
/// them. An interface because, linked to a hub, the till queues for the hub
/// only while no hub answers: standalone, it queues for the cloud
/// (`PendingOperationsService`).
abstract interface class PendingOperations {
  /// Get pending operations by entity type
  Future<List<PendingSyncOperation>> getPendingOperationsByType(String entityType);

  /// Every queued op, newest first, dead-lettered ones included — the queue
  /// as the operator inspects it, unlike the retry order of
  /// [getPendingOperations].
  Future<List<PendingSyncOperation>> getAllOperationsNewestFirst();

  /// Mark operation as completed and remove from queue
  Future<void> markCompleted(int operationId);
}

import 'dart:async';
import 'package:loggecrea/loggecrea.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data_sync_service.dart';

/// Service that runs periodic sync jobs
class SyncJobService {
  final DataSyncService _syncService;
  final SharedPreferences _prefs;
  final bool Function() _isOnlineCallback;
  final _logger = Logger.instance;

  Timer? _syncTimer;
  bool _isRunning = false;

  // Settings keys
  static const String _autoSyncDurationKey = 'auto_sync_duration_minutes';
  static const String _dataRetentionDaysKey = 'data_retention_days';
  static const String _autoClearSyncedDataKey = 'auto_clear_synced_data';
  static const String _lastDataClearDateKey = 'last_data_clear_date';
  static const String _bulkSyncSizeKey = 'bulk_sync_size';

  SyncJobService(this._syncService, this._prefs, this._isOnlineCallback);

  /// Start the periodic sync job
  void start() {
    if (_isRunning) {
      _logger.warning('Sync job already running');
      return;
    }

    _isRunning = true;
    final durationMinutes = _prefs.getInt(_autoSyncDurationKey) ?? 5;

    _logger.info('Starting sync job with interval: $durationMinutes minutes');

    // Run initial sync
    _runSyncJob();

    // Schedule periodic sync
    _syncTimer = Timer.periodic(
      Duration(minutes: durationMinutes),
      (_) => _runSyncJob(),
    );
  }

  /// Stop the periodic sync job
  void stop() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _isRunning = false;
    _logger.info('Sync job stopped');
  }

  /// Update the sync interval (will restart the job)
  void updateInterval(int minutes) {
    if (_isRunning) {
      stop();
      _prefs.setInt(_autoSyncDurationKey, minutes);
      start();
    }
  }

  /// Run the sync job
  Future<void> _runSyncJob() async {
    if (!_isOnlineCallback()) {
      _logger.info('Sync job skipped: offline');
      return;
    }

    _logger.info('Running sync job...');

    try {
      // 1. Clear old synced data if enabled and needed
      await _clearOldDataIfNeeded();

      // 2. Sync pending operations (deletes, updates)
      await _syncService.syncPendingOperations();

      // 3. Sync unsynced orders
      final bulkSize = _prefs.getInt(_bulkSyncSizeKey) ?? 50;
      final ordersSynced = await _syncService.syncOrdersBulk(batchSize: bulkSize);
      if (ordersSynced > 0) {
        _logger.info('Synced $ordersSynced orders');
      }

      // 4. Sync tickets for synced orders
      final ticketsSynced = await _syncService.syncTicketsBulk(batchSize: bulkSize);
      if (ticketsSynced > 0) {
        _logger.info('Synced $ticketsSynced tickets');
      }

      // 5. Sync ended sessions
      final sessionsSynced = await _syncService.syncSessionsBulk(batchSize: bulkSize);
      if (sessionsSynced > 0) {
        _logger.info('Synced $sessionsSynced sessions');
      }

      // 6. Sync new customers
      final customersSynced = await _syncService.syncCustomersBulk(batchSize: bulkSize);
      if (customersSynced > 0) {
        _logger.info('Synced $customersSynced customers');
      }

      _logger.info('Sync job completed');
    } catch (e) {
      _logger.error('Sync job failed: $e');
    }
  }

  /// Clear old synced data if auto-clear is enabled and it's a new day
  Future<void> _clearOldDataIfNeeded() async {
    final autoClear = _prefs.getBool(_autoClearSyncedDataKey) ?? true;
    if (!autoClear) return;

    final lastClearDateStr = _prefs.getString(_lastDataClearDateKey);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime? lastClearDate;
    if (lastClearDateStr != null) {
      lastClearDate = DateTime.tryParse(lastClearDateStr);
    }

    // Check if we need to clear data today
    bool shouldClear = false;
    if (lastClearDate == null) {
      shouldClear = true;
    } else {
      final lastClearDay = DateTime(lastClearDate.year, lastClearDate.month, lastClearDate.day);
      shouldClear = today.isAfter(lastClearDay);
    }

    if (shouldClear) {
      final retentionDays = _prefs.getInt(_dataRetentionDaysKey) ?? 7;
      _logger.info('Clearing synced data older than $retentionDays days');

      try {
        await _syncService.clearOldSyncedData(retentionDays);
        await _prefs.setString(_lastDataClearDateKey, now.toIso8601String());
        _logger.info('Old synced data cleared successfully');
      } catch (e) {
        _logger.error('Failed to clear old synced data: $e');
      }
    }
  }

  /// Get the current sync status
  Future<Map<String, int>> getSyncStatus() async {
    return await _syncService.getSyncStatus();
  }

  /// Manually trigger a sync
  Future<void> syncNow() async {
    _logger.info('Manual sync triggered');
    await _runSyncJob();
  }

  /// Check if the job is running
  bool get isRunning => _isRunning;
}


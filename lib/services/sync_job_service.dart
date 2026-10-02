import 'dart:async';
import 'package:loggecrea/loggecrea.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data_sync_service.dart';
import 'activity_log_service.dart';
import 'identity_fix_service.dart';

/// Service that runs periodic sync jobs
class SyncJobService {
  final DataSyncService _syncService;
  final SharedPreferences _prefs;
  final bool Function() _isOnlineCallback;
  final ActivityLogService? _activityLog;
  final IdentityFixService? _identityFix;
  final _logger = Logger.instance;

  Timer? _syncTimer;
  bool _isRunning = false;

  // Settings keys
  static const String _autoSyncDurationKey = 'auto_sync_duration_minutes';
  static const String _bulkSyncSizeKey = 'bulk_sync_size';

  SyncJobService(this._syncService, this._prefs, this._isOnlineCallback,
      [this._activityLog, this._identityFix]);

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
    // Activity-log retention runs regardless of connectivity (local DB + file work).
    await _archiveOldLogsIfNeeded();

    if (!_isOnlineCallback()) {
      _logger.info('Sync job skipped: offline');
      return;
    }

    _logger.info('Running sync job...');

    try {
      // 0. Repair tenant/business identity BEFORE anything is pushed, so the
      //    request headers (X-Tenant-ID) and any server-side scoping use the
      //    corrected ids for the rest of this cycle. Guarded + non-blocking:
      //    it self-skips once applied and never throws.
      final identityFix = _identityFix;
      if (identityFix != null) {
        await identityFix.ensureIdentityBackfilled();
      }

      // 2. Sync pending operations (deletes, updates)
      await _syncService.syncPendingOperations();

      final bulkSize = _prefs.getInt(_bulkSyncSizeKey) ?? 50;

      // 3. Sync ended sessions FIRST (tickets may reference sessions). A Z
      //    reaches the server on its sessions — there is no Z push.
      final sessionsSynced = await _syncService.syncSessionsBulk(batchSize: bulkSize);
      if (sessionsSynced > 0) {
        _logger.info('Synced $sessionsSynced sessions');
      }
      final movementsSynced =
          await _syncService.syncCashMovementsBulk(batchSize: bulkSize);
      if (movementsSynced > 0) {
        _logger.info('Synced $movementsSynced cash movements');
      }
      final notified = await _syncService.syncPendingNotifications();
      if (notified > 0) {
        _logger.info('Delivered $notified queued notifications');
      }

      // 4. Sync unsynced orders
      final ordersSynced = await _syncService.syncOrdersBulk(batchSize: bulkSize);
      if (ordersSynced > 0) {
        _logger.info('Synced $ordersSynced orders');
      }

      // 5. Sync tickets for synced orders (after both sessions and orders are synced)
      final ticketsSynced = await _syncService.syncTicketsBulk(batchSize: bulkSize);
      if (ticketsSynced > 0) {
        _logger.info('Synced $ticketsSynced tickets');
      }


      // 6. Sync new customers
      final customersSynced = await _syncService.syncCustomersBulk(batchSize: bulkSize);
      if (customersSynced > 0) {
        _logger.info('Synced $customersSynced customers');
      }

      // 7. NOTE: the periodic job deliberately does NOT pull server-side order
      // deltas. Re-downloading and rebuilding orders this POS already owns is
      // wasted work (and used to clobber client-only state). Local orders are
      // still PUSHED above; the down-pull now happens ONLY on an explicit
      // request — the top-bar Sync button, the Sync Inspector, or a backend
      // `sync_orders` command. Restore `pullAllDeltas` here to re-enable
      // automatic reconciliation for multi-till / server-side edits.

      _logger.info('Sync job completed (push-only; order pull is manual)');
    } catch (e) {
      _logger.error('Sync job failed: $e');
    }
  }

  /// Roll the activity log: once per day, append entries older than the
  /// retention window to a Desktop text file and delete them from the table.
  Future<void> _archiveOldLogsIfNeeded() async {
    await _activityLog?.purgeIfDue();
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

  /// Whether any locally-queued data (orders/tickets/sessions/customers/Z
  /// shifts) is still waiting to reach the server. Returns false when offline —
  /// there's nothing we could push anyway. Used by the exit flow so a clean
  /// (fully-synced) exit doesn't block on a sync at all.
  Future<bool> hasPendingForExit() async {
    if (!_isOnlineCallback()) return false;
    try {
      final status = await _syncService.getSyncStatus();
      final queued = status.values.fold<int>(0, (a, b) => a + b);
      return queued > 0 || (await _syncService.countUnsyncedZs()) > 0;
    } catch (e) {
      _logger.error('hasPendingForExit check failed: $e');
      return false;
    }
  }

  /// Push-only flush for app exit. Unlike [syncNow] it uploads locally-queued
  /// rows and stops — it deliberately skips `pullAllDeltas` and the daily
  /// housekeeping (retention/clear/identity-fix). Exit only needs to guarantee
  /// local data reaches the server; the full cycle is slow and pointless while
  /// the app is closing (and was the cause of the "frozen on exit" hang even
  /// when everything was already synced).
  Future<void> flushForExit() async {
    if (!_isOnlineCallback()) return;
    _logger.info('Exit flush: pushing pending data');
    try {
      await _syncService.syncPendingOperations();

      final bulkSize = _prefs.getInt(_bulkSyncSizeKey) ?? 50;
      // Sessions before orders before tickets (referential order).
      await _syncService.syncSessionsBulk(batchSize: bulkSize);
      await _syncService.syncCashMovementsBulk(batchSize: bulkSize);
      await _syncService.syncPendingNotifications();
      await _syncService.syncOrdersBulk(batchSize: bulkSize);
      await _syncService.syncTicketsBulk(batchSize: bulkSize);
      await _syncService.syncCustomersBulk(batchSize: bulkSize);
      _logger.info('Exit flush completed');
    } catch (e) {
      _logger.error('Exit flush failed: $e');
    }
  }

  /// Check if the job is running
  bool get isRunning => _isRunning;
}


import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../providers/database_providers.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/data_sync_service.dart';

/// Provider to manage auto-sync and bulk sync functionality
class SyncManagerNotifier extends StateNotifier<SyncState> {
  final Ref ref;
  Timer? _bulkSyncTimer;
  StreamSubscription? _connectivitySubscription;
  bool _hasCheckedDailyClear = false;

  SyncManagerNotifier(this.ref) : super(const SyncState()) {
    _initBulkSyncTimer();
    _initConnectivityListener();
    _checkDailyClear();
  }

  /// Check if daily data clear should be performed
  Future<void> _checkDailyClear() async {
    if (_hasCheckedDailyClear) return;
    _hasCheckedDailyClear = true;

    try {
      final settingsNotifier = ref.read(settingsProvider.notifier);

      if (settingsNotifier.shouldClearDataToday()) {
        print('Daily data clear check: clearing synced data...');
        await _clearOldSyncedData();
        await settingsNotifier.setLastDataClearDate();
        print('Daily data clear completed');
      }
    } catch (e) {
      print('Error during daily data clear check: $e');
    }
  }

  /// Clear old synced data based on retention settings
  Future<void> _clearOldSyncedData() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);
      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);
      final settings = ref.read(settingsProvider);

      await syncService.clearOldSyncedData(settings.dataRetentionDays);
      print('Cleared synced data older than ${settings.dataRetentionDays} days');
    } catch (e) {
      print('Error clearing old synced data: $e');
    }
  }

  /// Initialize periodic bulk sync timer using settings duration
  void _initBulkSyncTimer() {
    final settings = ref.read(settingsProvider);
    final duration = Duration(minutes: settings.autoSyncDurationMinutes);

    _bulkSyncTimer?.cancel(); // Cancel existing timer if any
    _bulkSyncTimer = Timer.periodic(duration, (_) async {
      await _runPeriodicSyncJob();
    });
  }

  /// Run the periodic sync job - syncs all pending data
  Future<void> _runPeriodicSyncJob() async {
    if (state.isSyncing) return; // Skip if already syncing

    print('Running periodic sync job...');

    // Check actual server connectivity
    final isOnline = await _checkServerConnectivity();

    if (!isOnline) {
      print('Periodic sync skipped - server not reachable');
      return;
    }

    try {
      // Perform bulk sync
      await performBulkSync();

      // Also check for pending operations (deletes/updates)
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);

      if (!apiService.isDemoMode()) {
        final database = ref.read(databaseProvider);
        final syncService = DataSyncService(database, apiService);
        await syncService.syncPendingOperations();
      }

      print('Periodic sync job completed');
    } catch (e) {
      print('Periodic sync job error: $e');
    }
  }

  /// Reinitialize timer with new duration (call after settings change)
  void updateSyncDuration() {
    _initBulkSyncTimer();
  }

  /// Check if server is actually reachable (not just network available)
  Future<bool> _checkServerConnectivity() async {
    try {
      // First check if device has network
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        return false;
      }

      // Check if demo mode
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);

      if (apiService.isDemoMode()) {
        return false; // Demo mode doesn't sync
      }

      // Assume online if we have network (let actual sync fail if server is down)
      // This avoids extra health check requests
      return true;
    } catch (e) {
      print('Connectivity check failed: $e');
      return false;
    }
  }

  /// Initialize connectivity listener to auto-sync when connection is restored
  void _initConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) async {
      final hasNetwork = result != ConnectivityResult.none;

      if (hasNetwork && !state.isSyncing) {
        print('Connection restored - triggering auto-sync');
        // Let the actual sync fail if server is down, no need for health check
        await performFullSync();
      }
    });
  }

  /// Auto-sync a single order when it's completed (if online)
  Future<bool> autoSyncOrder(int orderId) async {
    final settings = ref.read(settingsProvider);

    // Check if auto-sync is enabled
    if (!settings.autoSyncOnline) {
      return false;
    }

    // Check actual server connectivity
    final isOnline = await _checkServerConnectivity();

    if (!isOnline) {
      return false; // Not online, will be synced in bulk later
    }

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);

      // Skip if in demo mode
      if (apiService.isDemoMode()) {
        return false;
      }

      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);

      // Sync the single order
      final success = await syncService.syncSingleOrder(orderId);

      if (success) {
        state = state.copyWith(
          lastSyncTime: DateTime.now(),
          syncedOrdersCount: state.syncedOrdersCount + 1,
        );
      }

      return success;
    } catch (e) {
      print('Auto-sync order failed: $e');
      return false;
    }
  }

  /// Perform bulk sync of unsynced orders
  Future<int> performBulkSync() async {
    final settings = ref.read(settingsProvider);

    // Check actual server connectivity
    final isOnline = await _checkServerConnectivity();

    if (!isOnline) {
      return 0; // Not online, skip
    }

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);

      // Skip if in demo mode
      if (apiService.isDemoMode()) {
        return 0;
      }

      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);

      // Sync orders in bulk with configured batch size
      final syncedCount = await syncService.syncOrdersBulk(
        batchSize: settings.bulkSyncSize,
      );

      if (syncedCount > 0) {
        state = state.copyWith(
          lastBulkSyncTime: DateTime.now(),
          syncedOrdersCount: state.syncedOrdersCount + syncedCount,
        );
      }

      return syncedCount;
    } catch (e) {
      print('Bulk sync failed: $e');
      return 0;
    }
  }

  /// Perform full sync of all unsynced data (orders, tickets, customers, sessions)
  Future<SyncResult> performFullSync() async {
    if (state.isSyncing) {
      return SyncResult(success: false, message: 'Sync already in progress');
    }

    // Check actual server connectivity
    final isOnline = await _checkServerConnectivity();

    if (!isOnline) {
      return SyncResult(success: false, message: 'Server not reachable');
    }

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);

      // Skip if in demo mode
      if (apiService.isDemoMode()) {
        return SyncResult(success: false, message: 'Demo mode - sync disabled');
      }

      state = state.copyWith(isSyncing: true);

      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);

      int syncedOrders = 0;
      int syncedTickets = 0;
      int syncedCustomers = 0;
      int syncedSessions = 0;

      // 1. Sync customers first (may be referenced by orders)
      try {
        syncedCustomers = await syncService.syncCustomersBulk();
      } catch (e) {
        print('Error syncing customers: $e');
      }

      // 2. Sync orders
      try {
        syncedOrders = await syncService.syncOrdersBulk(batchSize: 100);
      } catch (e) {
        print('Error syncing orders: $e');
      }

      // 3. Sync tickets for synced orders
      try {
        syncedTickets = await syncService.syncTicketsBulk();
      } catch (e) {
        print('Error syncing tickets: $e');
      }

      // 4. Sync ended sessions
      try {
        syncedSessions = await syncService.syncSessionsBulk();
      } catch (e) {
        print('Error syncing sessions: $e');
      }

      // 5. Process any pending delete/update operations
      try {
        await syncService.syncPendingOperations();
      } catch (e) {
        print('Error syncing pending operations: $e');
      }

      state = state.copyWith(
        isSyncing: false,
        lastFullSyncTime: DateTime.now(),
        syncedOrdersCount: state.syncedOrdersCount + syncedOrders,
        syncedTicketsCount: state.syncedTicketsCount + syncedTickets,
        syncedCustomersCount: state.syncedCustomersCount + syncedCustomers,
        syncedSessionsCount: state.syncedSessionsCount + syncedSessions,
      );

      return SyncResult(
        success: true,
        message: 'Synced: $syncedOrders orders, $syncedTickets tickets, $syncedCustomers customers, $syncedSessions sessions',
        syncedOrders: syncedOrders,
        syncedTickets: syncedTickets,
        syncedCustomers: syncedCustomers,
        syncedSessions: syncedSessions,
      );
    } catch (e) {
      state = state.copyWith(isSyncing: false);
      print('Full sync failed: $e');
      return SyncResult(success: false, message: 'Sync failed: $e');
    }
  }

  /// Manual sync all data (downloads + uploads)
  Future<void> syncAllData() async {
    final settings = ref.read(settingsProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final apiService = ApiService(prefs);
    final database = ref.read(databaseProvider);
    final syncService = DataSyncService(database, apiService);

    // Upload local data first
    await syncService.uploadLocalData();

    // Download fresh data with retention
    await syncService.syncAllData(dataRetentionDays: settings.dataRetentionDays);

    state = state.copyWith(lastFullSyncTime: DateTime.now());
  }

  /// Get current sync status
  Future<Map<String, int>> getSyncStatus() async {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final apiService = ApiService(prefs);
      final database = ref.read(databaseProvider);
      final syncService = DataSyncService(database, apiService);
      return await syncService.getSyncStatus();
    } catch (e) {
      return {'orders': 0, 'tickets': 0, 'customers': 0, 'sessions': 0};
    }
  }

  @override
  void dispose() {
    _bulkSyncTimer?.cancel();
    _connectivitySubscription?.cancel();
    super.dispose();
  }
}

/// Sync result model
class SyncResult {
  final bool success;
  final String message;
  final int syncedOrders;
  final int syncedTickets;
  final int syncedCustomers;
  final int syncedSessions;

  SyncResult({
    required this.success,
    required this.message,
    this.syncedOrders = 0,
    this.syncedTickets = 0,
    this.syncedCustomers = 0,
    this.syncedSessions = 0,
  });

  int get totalSynced => syncedOrders + syncedTickets + syncedCustomers + syncedSessions;
}

/// Sync state model
class SyncState {
  final DateTime? lastSyncTime;
  final DateTime? lastBulkSyncTime;
  final DateTime? lastFullSyncTime;
  final int syncedOrdersCount;
  final int syncedTicketsCount;
  final int syncedCustomersCount;
  final int syncedSessionsCount;
  final bool isSyncing;

  const SyncState({
    this.lastSyncTime,
    this.lastBulkSyncTime,
    this.lastFullSyncTime,
    this.syncedOrdersCount = 0,
    this.syncedTicketsCount = 0,
    this.syncedCustomersCount = 0,
    this.syncedSessionsCount = 0,
    this.isSyncing = false,
  });

  SyncState copyWith({
    DateTime? lastSyncTime,
    DateTime? lastBulkSyncTime,
    DateTime? lastFullSyncTime,
    int? syncedOrdersCount,
    int? syncedTicketsCount,
    int? syncedCustomersCount,
    int? syncedSessionsCount,
    bool? isSyncing,
  }) {
    return SyncState(
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastBulkSyncTime: lastBulkSyncTime ?? this.lastBulkSyncTime,
      lastFullSyncTime: lastFullSyncTime ?? this.lastFullSyncTime,
      syncedOrdersCount: syncedOrdersCount ?? this.syncedOrdersCount,
      syncedTicketsCount: syncedTicketsCount ?? this.syncedTicketsCount,
      syncedCustomersCount: syncedCustomersCount ?? this.syncedCustomersCount,
      syncedSessionsCount: syncedSessionsCount ?? this.syncedSessionsCount,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }
}

/// Sync manager provider
final syncManagerProvider = StateNotifierProvider<SyncManagerNotifier, SyncState>((ref) {
  return SyncManagerNotifier(ref);
});


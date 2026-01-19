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

  SyncManagerNotifier(this.ref) : super(const SyncState()) {
    _initBulkSyncTimer();
  }

  /// Initialize periodic bulk sync timer (runs every 5 minutes)
  void _initBulkSyncTimer() {
    _bulkSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      await performBulkSync();
    });
  }

  /// Auto-sync a single order when it's completed (if online)
  Future<bool> autoSyncOrder(int orderId) async {
    final settings = ref.read(settingsProvider);

    // Check if auto-sync is enabled
    if (!settings.autoSyncOnline) {
      return false;
    }

    // Check network connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOnline = connectivityResult == ConnectivityResult.none ? false : true;


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
      print('Auto-sync failed: $e');
      return false;
    }
  }

  /// Perform bulk sync of unsynced orders
  Future<int> performBulkSync() async {
    final settings = ref.read(settingsProvider);

    // Check network connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOnline = connectivityResult == ConnectivityResult.none ? false : true;

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

  /// Manual sync all data
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

  @override
  void dispose() {
    _bulkSyncTimer?.cancel();
    super.dispose();
  }
}

/// Sync state model
class SyncState {
  final DateTime? lastSyncTime;
  final DateTime? lastBulkSyncTime;
  final DateTime? lastFullSyncTime;
  final int syncedOrdersCount;

  const SyncState({
    this.lastSyncTime,
    this.lastBulkSyncTime,
    this.lastFullSyncTime,
    this.syncedOrdersCount = 0,
  });

  SyncState copyWith({
    DateTime? lastSyncTime,
    DateTime? lastBulkSyncTime,
    DateTime? lastFullSyncTime,
    int? syncedOrdersCount,
  }) {
    return SyncState(
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
      lastBulkSyncTime: lastBulkSyncTime ?? this.lastBulkSyncTime,
      lastFullSyncTime: lastFullSyncTime ?? this.lastFullSyncTime,
      syncedOrdersCount: syncedOrdersCount ?? this.syncedOrdersCount,
    );
  }
}

/// Sync manager provider
final syncManagerProvider = StateNotifierProvider<SyncManagerNotifier, SyncState>((ref) {
  return SyncManagerNotifier(ref);
});


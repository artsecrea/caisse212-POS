import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_providers.dart';
import '../services/sync_job_service.dart';

/// Provider for network connectivity status
final connectivityProvider = StreamProvider<ConnectivityResult>((ref) async* {
  await for (final results in Connectivity().onConnectivityChanged) {
    yield results.firstOrNull ?? ConnectivityResult.none;
  }
});

/// Provider that checks if the device is online (has network)
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();

  await for (final results in connectivity.onConnectivityChanged) {
    // Just check network connectivity, not server health
    // Let actual sync operations fail if server is down
    yield results.isNotEmpty && !results.contains(ConnectivityResult.none);
  }
});

/// Notifier for managing online status
class OnlineStatusNotifier extends StateNotifier<bool> {
  OnlineStatusNotifier(this.ref) : super(false) {
    _init();
  }

  final Ref ref;

  void _init() {
    // Set initial state based on current connectivity
    Connectivity().checkConnectivity().then((results) {
      state = results.isNotEmpty && !results.contains(ConnectivityResult.none);
    });

    ref.listen(isOnlineProvider, (previous, next) {
      next.whenData((isOnline) {
        print('is online $isOnline');
        state = isOnline;

        // Trigger sync when network comes back online
        if (isOnline && previous?.value == false) {
          final syncService = ref.read(dataSyncServiceProvider);
          syncService.syncPendingOperations().catchError((e) {
            print('Auto-sync failed: $e');
          });
        }
      });
    });
  }
}

/// Provider for checking online status synchronously (last known state)
final lastKnownOnlineStatusProvider = StateNotifierProvider<OnlineStatusNotifier, bool>((ref) {
  return OnlineStatusNotifier(ref);
});

/// Sync Job Service Provider with proper network status access
final syncJobServiceWithNetworkProvider = Provider<SyncJobService>((ref) {
  final syncService = ref.watch(dataSyncServiceProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  final isOnline = ref.watch(lastKnownOnlineStatusProvider);
  return SyncJobService(syncService, prefs, () => isOnline);
});

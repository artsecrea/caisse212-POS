import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'database_providers.dart';

/// Provider for network connectivity status
final connectivityProvider = StreamProvider<ConnectivityResult>((ref) async* {
  await for (final result in Connectivity().onConnectivityChanged) {
    yield result;
  }
});

/// Provider that checks if the device is online (has network AND can reach server)
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  final apiService = ref.read(apiServiceProvider);

  await for (final result in connectivity.onConnectivityChanged) {
    if (result == ConnectivityResult.none) {
      yield false;
    } else {
      // Has network, but check if server is reachable
      try {
        final canReachServer = await apiService.checkConnection();
        yield canReachServer;
      } catch (e) {
        yield false;
      }
    }
  }
});

/// Notifier for managing online status
class OnlineStatusNotifier extends StateNotifier<bool> {
  OnlineStatusNotifier(this.ref) : super(false) {
    _init();
  }

  final Ref ref;

  void _init() {
    ref.listen(isOnlineProvider, (previous, next) {
      next.whenData((isOnline) {
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


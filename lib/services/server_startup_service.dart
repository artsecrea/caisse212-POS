import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/server_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/pos_log.dart';
import 'package:loggecrea/loggecrea.dart';

/// Service to initialize and manage server startup
class ServerStartupService {
  final Ref _ref;

  ServerStartupService(this._ref);

  /// Initialize server on app startup
  Future<void> initializeServer() async {
    final settings = _ref.read(settingsProvider);

    if (settings.autoStartServer) {
      posLog('🚀 Auto-starting HTTP server...');
      try {
        await startServerWithRef(_ref);
        posLog('✅ HTTP server started successfully');
      } catch (e) {
        Logger.instance.error('Failed to auto-start server: $e');
      }
    } else {
      posLog('ℹ️ Auto-start server is disabled');
    }
  }

  /// Restart server with new settings
  Future<void> restartServer() async {
    posLog('🔄 Restarting HTTP server...');
    try {
      await stopServerWithRef(_ref);
      await Future.delayed(const Duration(milliseconds: 500));
      await startServerWithRef(_ref);
      posLog('✅ HTTP server restarted successfully');
    } catch (e) {
      Logger.instance.error('Failed to restart server: $e');
      rethrow;
    }
  }
}

/// Provider for server startup service
final serverStartupServiceProvider = Provider<ServerStartupService>((ref) {
  return ServerStartupService(ref);
});


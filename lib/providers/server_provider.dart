import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/server_service.dart';
import 'settings_provider.dart';
import '../utils/pos_log.dart';
import 'package:loggecrea/loggecrea.dart';

/// Provider for the HTTP server service
final serverServiceProvider = Provider<ServerService>((ref) {
  return ServerService(ref);
});

/// Provider to track server running state
final serverRunningProvider = StateProvider<bool>((ref) => false);

/// Provider for server port
final serverPortProvider = StateProvider<int>((ref) => 8080);

/// Provider for server password (from settings)
final serverPasswordProvider = Provider<String?>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.serverPassword;
});

/// Start server with settings (for WidgetRef)
Future<void> startServerWithSettings(WidgetRef ref) async {
  final serverService = ref.read(serverServiceProvider);
  final settings = ref.read(settingsProvider);

  try {
    await serverService.start(
      port: settings.serverPort ?? 8080,
      password: settings.serverPassword,
    );
    ref.read(serverRunningProvider.notifier).state = true;
  } catch (e) {
    Logger.instance.error('Failed to start server: $e');
    rethrow;
  }
}

/// Start server with settings (for Ref - used in providers)
Future<void> startServerWithRef(Ref ref) async {
  final serverService = ref.read(serverServiceProvider);
  final settings = ref.read(settingsProvider);

  try {
    await serverService.start(
      port: settings.serverPort ?? 8080,
      password: settings.serverPassword,
    );
    ref.read(serverRunningProvider.notifier).state = true;
  } catch (e) {
    Logger.instance.error('Failed to start server: $e');
    rethrow;
  }
}

/// Stop server (for WidgetRef)
Future<void> stopServer(WidgetRef ref) async {
  final serverService = ref.read(serverServiceProvider);
  await serverService.stop();
  ref.read(serverRunningProvider.notifier).state = false;
}

/// Stop server (for Ref - used in providers)
Future<void> stopServerWithRef(Ref ref) async {
  final serverService = ref.read(serverServiceProvider);
  await serverService.stop();
  ref.read(serverRunningProvider.notifier).state = false;
}


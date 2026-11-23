import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/network_provider.dart';
import 'package:caisse212/providers/settings_provider.dart';
import 'package:caisse212/providers/sse_provider.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/sse_service.dart';

/// Counts the connections the lifecycle would open, without a network.
class _CountingSse extends SseService {
  _CountingSse(super.api);
  int subscriptions = 0;
  int stops = 0;
  bool running = false;

  @override
  void start() {
    if (running) return;
    running = true;
    subscriptions++;
  }

  @override
  void stop() {
    if (running) stops++;
    running = false;
  }
}

/// Prod showed tills reopening /subscribe every few seconds. A cashier
/// signing in or out rebuilds the lifecycle provider, and each rebuild used
/// to stop the stream and open a new one.
void main() {
  late ProviderContainer container;
  late _CountingSse sse;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'server_access_token': 'a.b.c',
      'api_base_url': 'https://bms.test/api',
      'business_id': 1,
    });
    final prefs = await SharedPreferences.getInstance();
    sse = _CountingSse(ApiService(prefs));
    container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      sseServiceProvider.overrideWithValue(sse),
      isOnlineProvider.overrideWith((ref) => Stream.value(true)),
    ]);
    container.listen(sseLifecycleProvider, (_, __) {});
  });

  tearDown(() => container.dispose());

  test('cashier sign-in and sign-out keep the one subscription', () async {
    expect(sse.subscriptions, 1);
    // What a currentUserProvider change does to it: a full rebuild.
    for (var i = 0; i < 5; i++) {
      container.invalidate(sseLifecycleProvider);
      container.read(sseLifecycleProvider);
    }
    expect(sse.subscriptions, 1);
    expect(sse.stops, 0);
  });

  test('turning SSE off still stops it, and on again reconnects once',
      () async {
    await container.read(settingsProvider.notifier).setSseEnabled(false);
    container.read(sseLifecycleProvider);
    expect(sse.running, isFalse);
    await container.read(settingsProvider.notifier).setSseEnabled(true);
    container.read(sseLifecycleProvider);
    expect(sse.running, isTrue);
    expect(sse.subscriptions, 2);
  });
}

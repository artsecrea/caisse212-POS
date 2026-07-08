import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../domain/models/external_order_models.dart';
import '../services/sse_service.dart';
import '../services/pos_command_handler.dart';
import 'database_providers.dart';
import 'external_order_provider.dart';

// ── Service providers ──────────────────────────────────────────────────────

final sseServiceProvider = Provider<SseService>((ref) {
  final api = ref.watch(apiServiceProvider);
  final service = SseService(api);
  ref.onDispose(service.dispose);
  return service;
});

final posCommandHandlerProvider = Provider<PosCommandHandler>((ref) {
  return PosCommandHandler(ref);
});

// ── UI-facing state providers ──────────────────────────────────────────────

/// Non-null when a `DISPLAY_ALERT` command arrives. UI should watch and clear.
final sseAlertProvider = StateProvider<String?>((ref) => null);

/// Non-null when a `new-order` SSE event arrives. UI should watch and clear.
/// Value is the raw queue item payload from the server.
final sseNewOrderProvider =
    StateProvider<Map<String, dynamic>?>((ref) => null);

/// Increments whenever the server sends a `close_session`, `close_all_sessions`,
/// `force_logout`, or `logout` command. UI listens and navigates to /login.
final sseSessionClosedProvider = StateProvider<int>((ref) => 0);

// ── Lifecycle provider ─────────────────────────────────────────────────────

/// Watch this provider from a top-level widget (e.g. MainScreen) to activate
/// the SSE connection while the user is logged in.
///
/// It auto-starts on first watch, stops on dispose, and routes every event
/// to the appropriate handler or state provider.
final sseLifecycleProvider = Provider<void>((ref) {
  final user = ref.watch(currentUserProvider);
  final sseService = ref.watch(sseServiceProvider);
  final commandHandler = ref.watch(posCommandHandlerProvider);

  if (user == null) {
    sseService.stop();
    return;
  }

  sseService.start();

  // Route events
  StreamSubscription<SseEvent>? sub;
  sub = sseService.events.listen((event) async {
    switch (event.type) {
      case SseEventType.connected:
        Logger.instance.info('SSE: connected to server — refreshing external queue');
        ref.read(externalOrderProvider.notifier).load();
        break;

      case SseEventType.newOrder:
        Logger.instance.info('SSE: new-order received');
        ref.read(sseNewOrderProvider.notifier).state = event.data;
        // Push into the external order queue so the UI updates in real-time
        try {
          final item = ExternalQueueItem.fromJson(event.data);
          ref.read(externalOrderProvider.notifier).onNewOrderEvent(item);
        } catch (e) {
          Logger.instance.error('SSE: failed to parse new-order event: $e');
        }
        break;

      case SseEventType.orderStateChanged:
        Logger.instance.info(
            'SSE: order-state-changed ${event.data['orderCode']} → ${event.data['newState']}');
        // Delta pull is intentionally NOT done here — use the manual update
        // button in the top bar to pull order changes on demand.
        break;

      case SseEventType.posCommand:
        final handledType = await commandHandler.handle(event.data);
        switch (handledType) {
          case 'display_alert':
            final msg = event.data['message'] as String?;
            if (msg != null && msg.isNotEmpty) {
              ref.read(sseAlertProvider.notifier).state = msg;
            }

          case 'close_session':
          case 'close_current_session':
          case 'close_all_sessions':
          case 'force_logout':
          case 'logout':
            // Signal the UI (main_screen) to navigate to /login.
            ref
                .read(sseSessionClosedProvider.notifier)
                .update((v) => v + 1);
        }
        break;

      case SseEventType.heartbeat:
      case SseEventType.unknown:
        break;
    }
  });

  ref.onDispose(() {
    sub?.cancel();
    sseService.stop();
  });
});

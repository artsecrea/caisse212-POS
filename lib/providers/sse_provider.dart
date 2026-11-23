import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../domain/models/external_order_models.dart';
import '../services/sse_service.dart';
import '../services/pos_command_handler.dart';
import '../services/remote_access_reporter.dart';
import '../services/remote_command_service.dart';
import 'database_providers.dart';
import 'external_order_provider.dart';
import 'network_provider.dart';
import 'reservation_providers.dart';
import 'settings_provider.dart';

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

/// Set when a queued order is cancelled on the platform side. The UI shows it
/// and clears it. `wasConfirmed` is the difference between "a ticket vanished"
/// and "stop cooking that" — the second needs a dialog, not a toast.
final sseOrderCancelledProvider =
    StateProvider<({String? orderCode, String? reason, bool wasConfirmed})?>(
        (ref) => null);

/// Increments whenever the server sends a `close_session`, `close_all_sessions`,
/// `force_logout`, or `logout` command. UI listens and navigates to /login.
final sseSessionClosedProvider = StateProvider<int>((ref) => 0);

// ── Lifecycle provider ─────────────────────────────────────────────────────

/// Watched from main.dart for as long as the app runs, so the SSE connection
/// is up whenever the terminal is signed in — on the login screen too, so the
/// back office can still reach a till nobody is using.
///
/// It auto-starts on first watch, stops on dispose, and routes every event
/// to the appropriate handler or state provider.
final sseLifecycleProvider = Provider<void>((ref) {
  // Watched only to re-evaluate on sign-in / sign-out: that is when the
  // terminal's tokens appear or are wiped. The stream itself needs no cashier.
  ref.watch(currentUserProvider);
  final sseService = ref.watch(sseServiceProvider);
  final commandHandler = ref.watch(posCommandHandlerProvider);
  final remote = ref.watch(remoteCommandServiceProvider);
  final hasTerminal = ref.read(apiServiceProvider).getAccessToken() != null;

  // Admin-controlled master switch (on unless someone turned it off). When
  // disabled — or the terminal itself is signed out — keep the SSE connection
  // torn down entirely.
  final sseEnabled = ref.watch(
      settingsProvider.select((s) => s.sseEnabled));

  // A disabled account would only collect 423s; reactivation goes through
  // the login screen anyway.
  final blocked = ref.watch(accountBlockProvider) != null;

  if (!hasTerminal || !sseEnabled || blocked) {
    sseService.stop();
    return;
  }

  // A no-op while the stream is already up: a cashier signing in or out
  // rebuilds this provider, and that must not cost a new subscription.
  sseService.start();

  // Back online: reconnect now rather than at the end of the backoff, which
  // can be a minute after a long outage.
  ref.listen<AsyncValue<bool>>(isOnlineProvider, (prev, next) {
    if (next.valueOrNull == true && prev?.valueOrNull != true) {
      sseService.reconnectNow();
    }
  });

  // A burst of reservation events (a basket edit fires several) costs one
  // agenda pull, not one each.
  Timer? reservationDebounce;

  // Route events
  StreamSubscription<SseEvent>? sub;
  sub = sseService.events.listen((event) async {
    switch (event.type) {
      case SseEventType.connected:
        Logger.instance.info(
            'SSE: connected — refreshing the external queue and session orders');
        ref.read(externalOrderProvider.notifier).load();
        // Remote support: once per run, and again if the ID moved.
        unawaited(ref.read(remoteAccessReporterProvider).report());
        // The stream has no replay: anything sent while this till was off it
        // (an admin cancel, a discount) is gone. Catch up from the source.
        unawaited(ref
            .read(dataSyncServiceProvider)
            .refreshOpenSessions()
            .then((_) {}, onError: (Object e) {
          Logger.instance.warning('SSE: catch-up refresh failed: $e');
        }));
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

      case SseEventType.orderCancelled:
        // The platform pulled the order. Take it off the board immediately —
        // a cancelled ticket left visible is one a cashier will work.
        final code = (event.data['orderCode'] ??
                event.data['order_code'] ??
                event.data['code'])
            ?.toString();
        final id = (event.data['id'] ?? event.data['queueItemId']) as int?;
        Logger.instance
            .warning('SSE: order-cancelled code=$code id=$id');
        final wasConfirmed = ref
            .read(externalOrderProvider.notifier)
            .onOrderCancelledEvent(queueItemId: id, orderCode: code);
        ref.read(sseOrderCancelledProvider.notifier).state = (
          orderCode: code,
          reason: (event.data['reason'] ?? event.data['cancellationReason'])
              ?.toString(),
          wasConfirmed: wasConfirmed,
        );
        break;

      case SseEventType.orderReady:
      case SseEventType.orderDeliveryStatusChanged:
        // Status moved on the platform's side. Nothing to decide locally —
        // refresh so the ticket shows the new state.
        Logger.instance.info('SSE: ${event.type.name} — refreshing the queue');
        ref.read(externalOrderProvider.notifier).load();
        break;

      case SseEventType.orderStateChanged:
        Logger.instance.info(
            'SSE: order-state-changed ${event.data['orderCode']} → ${event.data['newState']}');
        // Delta pull is intentionally NOT done here — use the manual update
        // button in the top bar to pull order changes on demand.
        break;

      case SseEventType.orderUpdated:
        final code = (event.data['orderCode'] ?? event.data['code'])?.toString();
        if (code == null) break;
        Logger.instance.info('SSE: order-updated $code — refreshing it');
        try {
          await ref.read(dataSyncServiceProvider).refreshOrder(code);
        } catch (e) {
          Logger.instance.warning('SSE: refresh of $code failed: $e');
        }
        break;

      case SseEventType.posCommand:
        // A requestId means the back office is waiting for exactly one reply.
        final requestId = RemoteCommandService.requestIdOf(event.data);
        if (requestId != null && remote.handles(event.data)) {
          unawaited(remote.answer(event.data, requestId));
          break;
        }
        final started = DateTime.now();
        String? handledType;
        Object? commandError;
        try {
          handledType = await commandHandler.handle(event.data);
        } catch (e) {
          if (requestId == null) rethrow;
          commandError = e;
        }
        if (requestId != null) {
          unawaited(remote.replyForCommand(
            event.data,
            requestId,
            handledType: handledType,
            error: commandError,
            took: DateTime.now().difference(started),
          ));
        }
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

      case SseEventType.reservationUpdated:
        Logger.instance.info('SSE: reservation-updated '
            '${event.data['code']} ${event.data['reason']}');
        reservationDebounce?.cancel();
        reservationDebounce = Timer(const Duration(milliseconds: 800), () {
          // Re-read the window the agenda is showing; with no agenda open
          // the next one to open pulls anyway.
          final visible = ref.read(agendaVisibleDateProvider);
          if (visible != null) unawaited(pullAgendaWeek(ref, visible));
        });
        break;

      case SseEventType.heartbeat:
      case SseEventType.unknown:
        break;
    }
  });

  // No stop() here: this runs on every rebuild, and stopping would drop a
  // healthy stream each time (the next build only starts a fresh one). The
  // stop paths are the branch above and the service's own dispose.
  ref.onDispose(() {
    reservationDebounce?.cancel();
    sub?.cancel();
  });
});

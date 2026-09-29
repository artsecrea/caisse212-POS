import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

/// One Server-Sent Event, already named and ready to frame.
class LanEvent {
  final String name;
  final Map<String, dynamic> data;

  const LanEvent(this.name, this.data);

  /// SSE wire format. The trailing blank line is what terminates the block —
  /// without it the client buffers the event forever.
  List<int> frame() =>
      utf8.encode('event: $name\ndata: ${jsonEncode(data)}\n\n');
}

class _Subscriber {
  final int id;
  final String channel;
  final StreamController<List<int>> sink;

  _Subscriber(this.id, this.channel, this.sink);
}

/// Fan-out for push events the POS sends to its LAN clients over SSE.
///
/// The POS already *consumes* SSE from the cloud ([SseService]); this is the
/// mirror image — the POS as the producer, for devices on the same Wi-Fi.
/// Nothing here touches the internet on purpose: calling a waiter is a request
/// to walk across the room, and it has to work on a service where the ADSL is
/// down. It rides the Shelf server that already serves `/waiters/*`.
///
/// Channels are `"<kind>:<id>"` — `waiter:12` today, `kds:3` and `kiosk:1`
/// when those apps grow the same listener. Publishing to `"<kind>:*"` reaches
/// every subscriber of that kind, which is how a broadcast message to the
/// floor works.
///
/// A dropped client is only discovered on the next write, so [_heartbeat]
/// doubles as the reaper: a comment frame every 20s both keeps proxies from
/// closing an idle stream and fails loudly enough to evict a phone that walked
/// out of range.
class LanNotificationHub {
  static const Duration heartbeatInterval = Duration(seconds: 20);

  final Map<int, _Subscriber> _subs = {};
  int _nextId = 1;
  Timer? _heartbeatTimer;
  bool _disposed = false;

  /// Open a stream for [channel]. The returned stream is what the Shelf
  /// handler hands back as the response body; cancelling it (client hangs up)
  /// unregisters the subscriber.
  ///
  /// [hello] is written immediately as a `connected` event so the client can
  /// tell "the stream is open" from "the stream connected and said nothing" —
  /// the exact ambiguity that cost days of debugging on the cloud SSE.
  Stream<List<int>> subscribe(
    String channel, {
    Map<String, dynamic>? hello,
    List<LanEvent> replay = const [],
  }) {
    final id = _nextId++;
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onCancel: () {
        _subs.remove(id);
        Logger.instance.info(
            'LanNotificationHub: client #$id left $channel '
            '(${_subs.length} still connected)');
        if (_subs.isEmpty) _stopHeartbeat();
      },
    );

    _subs[id] = _Subscriber(id, channel, controller);
    Logger.instance.info(
        'LanNotificationHub: client #$id joined $channel '
        '(${_subs.length} connected)');

    controller.add(LanEvent('connected', {
      'channel': channel,
      'serverTime': DateTime.now().toIso8601String(),
      ...?hello,
    }).frame());

    // Anything that was already waiting for this client before it connected.
    // A call placed while the waiter's phone was locked or reconnecting has to
    // survive the gap, or the cashier rings into the void.
    for (final event in replay) {
      controller.add(event.frame());
    }

    _startHeartbeat();
    return controller.stream;
  }

  /// Write [event] to every subscriber matching [channel]. Returns how many
  /// sinks it reached — 0 means nobody is listening, which the caller should
  /// surface to the cashier rather than swallow.
  int publish(String channel, LanEvent event) {
    if (_disposed) return 0;
    final frame = event.frame();
    var delivered = 0;
    for (final sub in _subs.values.toList()) {
      if (!_matches(sub.channel, channel)) continue;
      if (sub.sink.isClosed) continue;
      sub.sink.add(frame);
      delivered++;
    }
    Logger.instance.info(
        'LanNotificationHub: published ${event.name} → $channel '
        '($delivered client(s))');
    return delivered;
  }

  /// How many devices are listening on [channel]. Used to tell the cashier
  /// "this waiter is not connected" before they type a message nobody gets.
  int subscriberCount(String channel) =>
      _subs.values.where((s) => _matches(s.channel, channel)).length;

  /// A subscriber on `waiter:12` matches both `waiter:12` and `waiter:*`.
  @visibleForTesting
  static bool matches(String subscriberChannel, String publishChannel) =>
      _matches(subscriberChannel, publishChannel);

  static bool _matches(String subscriberChannel, String publishChannel) {
    if (subscriberChannel == publishChannel) return true;
    if (!publishChannel.endsWith(':*')) return false;
    final prefix = publishChannel.substring(0, publishChannel.length - 1);
    return subscriberChannel.startsWith(prefix);
  }

  void _startHeartbeat() {
    if (_heartbeatTimer != null || _disposed) return;
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      // A comment frame (`:` line) is ignored by every SSE parser but still
      // forces a socket write, which is the only way to notice a client that
      // vanished without closing.
      final beat = utf8.encode(': hb\n\n');
      for (final sub in _subs.values.toList()) {
        if (sub.sink.isClosed) {
          _subs.remove(sub.id);
          continue;
        }
        sub.sink.add(beat);
      }
      if (_subs.isEmpty) _stopHeartbeat();
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void dispose() {
    _disposed = true;
    _stopHeartbeat();
    for (final sub in _subs.values.toList()) {
      if (!sub.sink.isClosed) sub.sink.close();
    }
    _subs.clear();
  }
}

/// Single hub for the whole terminal — the Shelf handlers register clients on
/// it and the POS UI publishes through it.
final lanNotificationHubProvider = Provider<LanNotificationHub>((ref) {
  final hub = LanNotificationHub();
  ref.onDispose(hub.dispose);
  return hub;
});

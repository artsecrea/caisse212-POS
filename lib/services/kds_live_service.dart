import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../providers/database_providers.dart';
import 'lan_notification_hub.dart';

/// The LAN channel every kitchen screen listens on: `kds:<name>`.
String kdsChannel(String name) => 'kds:${name.trim().toLowerCase()}';

/// Tells kitchen screens that something they show may have changed, so they
/// fetch now instead of on their next poll.
///
/// A nudge, never the data: each screen has its own stations and filters,
/// and it already knows how to fetch exactly its share with its cursors. A
/// lost nudge costs nothing — the screen's slow safety poll catches up.
///
/// It watches the tables the board is built from rather than hooking every
/// writer (the till, the waiter app, the KDS itself, the cloud pull…).
/// Throttled, not debounced: the first write schedules one nudge [delay]
/// later and every write until then rides along, so a burst (a 10-line
/// order) is one nudge and a steady stream of writes can never starve it.
class KdsChangeSignal {
  final Stream<Set<TableUpdate>> Function() _updates;
  final int Function(String channel, LanEvent event) _publish;
  final int Function(String channel) _listeners;
  final Duration delay;

  final DateTime Function() _now;

  /// Changes with every process, so a screen's version from before a restart
  /// never matches.
  final String _boot;

  StreamSubscription<Set<TableUpdate>>? _sub;
  Timer? _timer;
  int _seq = 0;
  int _writes = 0;

  /// How long a version stays valid at most (see [version]).
  static const Duration versionWindow = Duration(seconds: 30);

  KdsChangeSignal({
    required Stream<Set<TableUpdate>> Function() updates,
    required int Function(String channel, LanEvent event) publish,
    required int Function(String channel) listeners,
    this.delay = const Duration(milliseconds: 250),
    DateTime Function()? now,
    String? boot,
  })  : _updates = updates,
        _publish = publish,
        _listeners = listeners,
        _now = now ?? DateTime.now,
        _boot = boot ??
            Random().nextInt(1 << 32).toRadixString(36);

  /// Identifies the state of everything the board is built from: equal
  /// versions mean nothing was written in between. Also rolls over every
  /// [versionWindow], so a write that bypasses drift's change feed (raw
  /// SQL) is never hidden for longer than that.
  String get version =>
      '$_boot.$_writes.${_now().millisecondsSinceEpoch ~/ versionWindow.inMilliseconds}';

  bool get isRunning => _sub != null;

  void start() {
    if (_sub != null) return;
    _sub = _updates().listen((_) {
      _writes++;
      _schedule();
    });
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    // Stopped = blind to writes: no version handed out now may be trusted.
    _writes++;
  }

  void _schedule() {
    if (_timer != null) return;
    _timer = Timer(delay, () {
      _timer = null;
      // Nobody listening (every screen polls, or none is on): skip the frame.
      if (_listeners('kds:*') == 0) return;
      _seq++;
      _publish('kds:*', LanEvent('orders-changed', {'seq': _seq}));
    });
  }
}

/// Short-lived tickets that let a screen open the event stream.
///
/// A browser's EventSource cannot send the server-password header, and the
/// password must not travel in a URL (it would land in the request log). So
/// the screen asks for a ticket with an ordinary authenticated request and
/// opens the stream with that: single use, valid [ttl].
class KdsStreamTickets {
  final Duration ttl;
  final int maxOutstanding;
  final DateTime Function() _now;
  final Random _random;
  final Map<String, DateTime> _issued = {};

  KdsStreamTickets({
    this.ttl = const Duration(seconds: 60),
    this.maxOutstanding = 64,
    DateTime Function()? now,
    Random? random,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  String issue() {
    _purge();
    // Never grows without bound, whatever a misbehaving client does.
    while (_issued.length >= maxOutstanding) {
      _issued.remove(_issued.keys.first);
    }
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    final ticket =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _issued[ticket] = _now().add(ttl);
    return ticket;
  }

  /// True once per issued, unexpired ticket.
  bool redeem(String? ticket) {
    if (ticket == null || ticket.isEmpty) return false;
    final expires = _issued.remove(ticket);
    return expires != null && _now().isBefore(expires);
  }

  void _purge() {
    final now = _now();
    _issued.removeWhere((_, expires) => !now.isBefore(expires));
  }
}

/// One kitchen screen as the till last saw it.
class KdsPresence {
  final String name;
  final List<String> stations;
  final String? version;
  final String? address;
  final DateTime lastSeen;

  /// Holding the event stream open right now.
  final bool live;

  const KdsPresence({
    required this.name,
    this.stations = const [],
    this.version,
    this.address,
    required this.lastSeen,
    this.live = false,
  });

  /// Seen recently enough to count as on: live, or polled within [window].
  bool onlineAt(DateTime now,
          {Duration window = KdsPresenceRegistry.onlineWindow}) =>
      live || now.difference(lastSeen) <= window;

  KdsPresence copyWith({
    List<String>? stations,
    String? version,
    String? address,
    DateTime? lastSeen,
    bool? live,
  }) =>
      KdsPresence(
        name: name,
        stations: stations ?? this.stations,
        version: version ?? this.version,
        address: address ?? this.address,
        lastSeen: lastSeen ?? this.lastSeen,
        live: live ?? this.live,
      );
}

/// Which kitchen screens are talking to this till, from the identity they
/// send on every request and from the event streams they hold. In memory
/// only: it describes the room right now, and a restart starts it afresh.
class KdsPresenceRegistry {
  /// A polling screen asks every few seconds; quiet for longer than this and
  /// it is off (or the tablet slept). Generous, so one slow poll does not
  /// flicker the devices screen.
  static const Duration onlineWindow = Duration(seconds: 45);

  final DateTime Function() _now;
  final Map<String, KdsPresence> _byKey = {};
  final Map<String, int> _streams = {};
  final _changes = StreamController<void>.broadcast();

  KdsPresenceRegistry({DateTime Function()? now}) : _now = now ?? DateTime.now;

  Stream<void> get changes => _changes.stream;

  static String _key(String name) => name.trim().toLowerCase();

  /// A request from screen [name]. Null or blank names (an old KDS build
  /// that sends no identity) are not tracked.
  void seen(String? name,
      {List<String>? stations, String? version, String? address}) {
    if (name == null || name.trim().isEmpty) return;
    final key = _key(name);
    final before = _byKey[key];
    final now = _now();
    _byKey[key] = (before ??
            KdsPresence(name: name.trim(), lastSeen: now))
        .copyWith(
      stations: stations,
      version: version,
      address: address,
      lastSeen: now,
      live: (_streams[key] ?? 0) > 0,
    );
    // Only a screen appearing is news; a poll refreshing lastSeen is not.
    if (before == null) _changes.add(null);
  }

  void streamOpened(String name,
      {List<String>? stations, String? version, String? address}) {
    final key = _key(name);
    _streams[key] = (_streams[key] ?? 0) + 1;
    seen(name, stations: stations, version: version, address: address);
    _changes.add(null);
  }

  void streamClosed(String name) {
    final key = _key(name);
    final left = (_streams[key] ?? 1) - 1;
    if (left <= 0) {
      _streams.remove(key);
    } else {
      _streams[key] = left;
    }
    final p = _byKey[key];
    if (p != null) {
      _byKey[key] = p.copyWith(live: left > 0, lastSeen: _now());
    }
    _changes.add(null);
  }

  /// Every screen seen since the till started, most recent first.
  List<KdsPresence> snapshot() =>
      _byKey.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

  KdsPresence? byName(String name) => _byKey[_key(name)];

  bool isOnline(String name) =>
      _byKey[_key(name)]?.onlineAt(_now()) ?? false;

  void dispose() => _changes.close();
}

/// Failed guesses per client address: after [maxFailures] within [window]
/// the address waits out the rest of the window. A success clears it.
class AttemptLimiter {
  final int maxFailures;
  final Duration window;
  final DateTime Function() _now;
  final Map<String, List<DateTime>> _failures = {};

  AttemptLimiter({
    this.maxFailures = 5,
    this.window = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  List<DateTime> _recent(String key) {
    final cutoff = _now().subtract(window);
    final list = (_failures[key] ?? [])..removeWhere((t) => t.isBefore(cutoff));
    if (list.isEmpty) {
      _failures.remove(key);
    } else {
      _failures[key] = list;
    }
    return list;
  }

  bool allow(String key) => _recent(key).length < maxFailures;

  void fail(String key) => (_failures[key] ??= []).add(_now());

  void reset(String key) => _failures.remove(key);
}

/// Parses the stations a screen reports (`X-KDS-Stations`, comma separated).
List<String> parseKdsStations(String? raw) => raw == null
    ? const []
    : raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

final kdsPresenceProvider = Provider<KdsPresenceRegistry>((ref) {
  final registry = KdsPresenceRegistry();
  ref.onDispose(registry.dispose);
  return registry;
});

/// Re-reads the registry when a screen appears / connects / leaves, and every
/// few seconds so one that went quiet flips to offline on its own.
final kdsPresenceSnapshotProvider =
    StreamProvider.autoDispose<List<KdsPresence>>((ref) async* {
  final registry = ref.watch(kdsPresenceProvider);
  yield registry.snapshot();
  final ticks = StreamController<void>();
  final timer = Timer.periodic(const Duration(seconds: 5), (_) {
    if (!ticks.isClosed) ticks.add(null);
  });
  final sub = registry.changes.listen((_) {
    if (!ticks.isClosed) ticks.add(null);
  });
  ref.onDispose(() {
    timer.cancel();
    sub.cancel();
    ticks.close();
  });
  await for (final _ in ticks.stream) {
    yield registry.snapshot();
  }
});

final kdsStreamTicketsProvider =
    Provider<KdsStreamTickets>((ref) => KdsStreamTickets());

final kdsChangeSignalProvider = Provider<KdsChangeSignal>((ref) {
  final db = ref.watch(databaseProvider);
  final hub = ref.watch(lanNotificationHubProvider);
  final signal = KdsChangeSignal(
    // Everything a board answer depends on, the session included: opening
    // or closing a shift changes which orders a screen gets.
    updates: () => db.tableUpdates(TableUpdateQuery.onAllTables([
      db.orders,
      db.orderProducts,
      db.orderProductComponents,
      db.orderLogs,
      db.cancelledOrderLines,
      db.cashSessions,
      db.products,
      db.stations,
      db.productStations,
      db.components,
    ])),
    publish: hub.publish,
    listeners: hub.subscriberCount,
  );
  ref.onDispose(() {
    // ignore: discarded_futures
    signal.stop();
    Logger.instance.info('KdsChangeSignal disposed');
  });
  return signal;
});

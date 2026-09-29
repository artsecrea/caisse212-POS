import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/settings_provider.dart';
import 'package:caisse212/services/lan_notification_hub.dart';
import 'package:caisse212/services/waiter_call_service.dart';

/// Calling a waiter's phone from the till.
///
/// The interesting failures are all about delivery, not about the dialog: a
/// call that reaches nobody and still says "sent", a call that rings a waiter
/// who was not the one asked for, and a call placed while the phone was
/// offline that then never arrives. Each has a test here.

/// Reads one SSE frame's worth of events out of the raw byte stream.
List<({String name, Map<String, dynamic> data})> parseFrames(String raw) {
  final out = <({String name, Map<String, dynamic> data})>[];
  for (final block in raw.split('\n\n')) {
    String? name;
    String? data;
    for (final line in block.split('\n')) {
      if (line.startsWith('event:')) name = line.substring(6).trim();
      if (line.startsWith('data:')) data = line.substring(5).trim();
    }
    if (name != null && data != null) {
      out.add((name: name, data: jsonDecode(data) as Map<String, dynamic>));
    }
  }
  return out;
}

void main() {
  group('LanNotificationHub', () {
    late LanNotificationHub hub;

    setUp(() => hub = LanNotificationHub());
    tearDown(() => hub.dispose());

    test('a subscriber only receives its own channel', () async {
      final alice = <String>[];
      final bob = <String>[];
      hub.subscribe('waiter:1').listen((b) => alice.add(utf8.decode(b)));
      hub.subscribe('waiter:2').listen((b) => bob.add(utf8.decode(b)));
      await Future<void>.delayed(Duration.zero);

      hub.publish('waiter:1', const LanEvent('waiter-call', {'callId': 'x'}));
      await Future<void>.delayed(Duration.zero);

      expect(parseFrames(alice.join()).map((e) => e.name),
          containsAllInOrder(['connected', 'waiter-call']));
      // Bob got his own `connected` and nothing else. A call landing on the
      // wrong phone is worse than one landing nowhere.
      expect(parseFrames(bob.join()).map((e) => e.name), ['connected']);
    });

    test('a wildcard publish reaches every waiter', () async {
      final seen = <String>[];
      hub.subscribe('waiter:1').listen((b) => seen.add(utf8.decode(b)));
      hub.subscribe('waiter:2').listen((b) => seen.add(utf8.decode(b)));
      await Future<void>.delayed(Duration.zero);

      final delivered =
          hub.publish('waiter:*', const LanEvent('notice', {'m': 'closing'}));
      expect(delivered, 2);
    });

    test('kds subscribers are not swept up by a waiter broadcast', () {
      expect(LanNotificationHub.matches('kds:3', 'waiter:*'), isFalse);
      expect(LanNotificationHub.matches('waiter:12', 'waiter:*'), isTrue);
      expect(LanNotificationHub.matches('waiter:12', 'waiter:12'), isTrue);
      expect(LanNotificationHub.matches('waiter:12', 'waiter:1'), isFalse);
    });

    test('replay events are written before anything new', () async {
      final seen = <String>[];
      hub.subscribe(
        'waiter:1',
        replay: const [
          LanEvent('waiter-call', {'callId': 'older'}),
        ],
      ).listen((b) => seen.add(utf8.decode(b)));
      await Future<void>.delayed(Duration.zero);

      final frames = parseFrames(seen.join());
      expect(frames.map((e) => e.name), ['connected', 'waiter-call']);
      expect(frames.last.data['callId'], 'older');
    });

    test('a client that hangs up stops counting as connected', () async {
      final sub = hub.subscribe('waiter:1').listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(hub.subscriberCount('waiter:1'), 1);

      await sub.cancel();
      expect(hub.subscriberCount('waiter:1'), 0);
      expect(hub.publish('waiter:1', const LanEvent('waiter-call', {})), 0);
    });
  });

  group('WaiterCallService', () {
    late AppDatabase db;
    late ProviderContainer container;
    late WaiterCallService calls;

    Future<void> boot({bool enabled = true}) async {
      SharedPreferences.setMockInitialValues({
        'waiter_call_enabled': enabled,
      });
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      calls = container.read(waiterCallServiceProvider);
    }

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await boot();
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('the setting holds at the service, not just in the widget', () async {
      container.dispose();
      await boot(enabled: false);
      expect(container.read(settingsProvider).waiterCallEnabled, isFalse);

      expect(
        () => calls.call(waiterId: 1, waiterName: 'Ali', fromUser: 'Sam'),
        throwsA(isA<StateError>()),
      );
    });

    test('a call reaches a connected phone with its message and table',
        () async {
      final seen = <String>[];
      container
          .read(lanNotificationHubProvider)
          .subscribe('waiter:7')
          .listen((b) => seen.add(utf8.decode(b)));
      await Future<void>.delayed(Duration.zero);

      final result = await calls.call(
        waiterId: 7,
        waiterName: 'Ali',
        message: 'Customer waiting',
        tableId: 3,
        tableName: 'T3',
        fromUser: 'Sam',
      );
      await Future<void>.delayed(Duration.zero);

      expect(result.devices, 1);
      final call = parseFrames(seen.join())
          .firstWhere((e) => e.name == 'waiter-call')
          .data;
      expect(call['waiterId'], 7);
      expect(call['message'], 'Customer waiting');
      expect(call['tableName'], 'T3');
      expect(call['from'], 'Sam');
      // Default setting: the phone is told to keep ringing.
      expect(call['ringUntilDismissed'], isTrue);
    });

    test('an empty message is sent as null, not as an empty bubble', () async {
      final result = await calls.call(
          waiterId: 7, waiterName: 'Ali', message: '   ', fromUser: 'Sam');
      expect(result.call.message, isNull);
    });

    test('calling an offline waiter reports 0 devices but still queues it',
        () async {
      final result =
          await calls.call(waiterId: 7, waiterName: 'Ali', fromUser: 'Sam');

      // The cashier must be told nothing rang — otherwise they wait instead of
      // walking over.
      expect(result.devices, 0);
      expect(calls.pendingFor(7).map((c) => c.id), [result.call.id]);
      expect(calls.pendingFor(8), isEmpty);
    });

    test('a queued call is replayed when the waiter finally connects',
        () async {
      await calls.call(
          waiterId: 7, waiterName: 'Ali', message: 'Table 3', fromUser: 'Sam');

      final seen = <String>[];
      container
          .read(lanNotificationHubProvider)
          .subscribe('waiter:7', replay: calls.replayEventsFor(7))
          .listen((b) => seen.add(utf8.decode(b)));
      await Future<void>.delayed(Duration.zero);

      final frames = parseFrames(seen.join());
      expect(frames.map((e) => e.name), ['connected', 'waiter-call']);
      expect(frames.last.data['message'], 'Table 3');
    });

    test('acknowledging silences the waiter other devices and tells the POS',
        () async {
      final seen = <String>[];
      container
          .read(lanNotificationHubProvider)
          .subscribe('waiter:7')
          .listen((b) => seen.add(utf8.decode(b)));
      await Future<void>.delayed(Duration.zero);

      final acked = expectLater(
        calls.acknowledgements,
        emits(predicate<WaiterCall>((c) => c.waiterName == 'Ali')),
      );

      final result =
          await calls.call(waiterId: 7, waiterName: 'Ali', fromUser: 'Sam');
      calls.acknowledge(result.call.id, by: 'Ali');
      await Future<void>.delayed(Duration.zero);
      await acked;

      final cancel = parseFrames(seen.join())
          .firstWhere((e) => e.name == 'waiter-call-cancelled')
          .data;
      expect(cancel['callId'], result.call.id);
      expect(cancel['reason'], 'acknowledged');
      // It is no longer owed to anyone, so a reconnect must not replay it.
      expect(calls.pendingFor(7), isEmpty);
    });

    test('acknowledging an unknown call is a no-op, not a crash', () {
      expect(calls.acknowledge('never-existed'), isNull);
    });
  });
}

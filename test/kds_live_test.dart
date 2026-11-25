import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpOverrides;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/server_provider.dart';
import 'package:caisse212/services/kds_live_service.dart';
import 'package:caisse212/services/lan_notification_hub.dart';
import 'package:caisse212/services/server_service.dart';

/// Kitchen screens told about changes instead of polling every 2 s: the
/// change signal, the stream tickets, who is connected, the "nothing new"
/// short answer — and that a screen which knows none of it gets exactly
/// what it got before.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  group('stream tickets', () {
    test('one use each, and only while fresh', () {
      var now = DateTime(2026, 11, 25, 12);
      final tickets = KdsStreamTickets(now: () => now);
      final a = tickets.issue();
      expect(tickets.redeem(a), isTrue);
      expect(tickets.redeem(a), isFalse, reason: 'single use');

      final b = tickets.issue();
      now = now.add(const Duration(seconds: 61));
      expect(tickets.redeem(b), isFalse, reason: 'expired');
      expect(tickets.redeem(null), isFalse);
      expect(tickets.redeem(''), isFalse);
      expect(tickets.redeem('made-up'), isFalse);
    });

    test('never piles up', () {
      final tickets = KdsStreamTickets(maxOutstanding: 3);
      final first = tickets.issue();
      for (var i = 0; i < 5; i++) {
        tickets.issue();
      }
      expect(tickets.redeem(first), isFalse, reason: 'oldest evicted');
    });
  });

  group('who is connected', () {
    test('a polling screen is online while it keeps asking', () {
      var now = DateTime(2026, 11, 25, 12);
      final r = KdsPresenceRegistry(now: () => now);
      r.seen('Cuisine', stations: ['Grill'], version: '1.2');
      expect(r.isOnline('cuisine'), isTrue, reason: 'case-insensitive');
      expect(r.byName('CUISINE')!.stations, ['Grill']);
      now = now.add(const Duration(seconds: 46));
      expect(r.isOnline('Cuisine'), isFalse);
    });

    test('a screen holding the stream is live until it leaves', () {
      var now = DateTime(2026, 11, 25, 12);
      final r = KdsPresenceRegistry(now: () => now);
      r.streamOpened('Bar');
      now = now.add(const Duration(hours: 1));
      expect(r.isOnline('Bar'), isTrue);
      expect(r.byName('Bar')!.live, isTrue);
      r.streamClosed('Bar');
      expect(r.byName('Bar')!.live, isFalse);
      expect(r.isOnline('Bar'), isTrue, reason: 'just seen');
      now = now.add(const Duration(minutes: 1));
      expect(r.isOnline('Bar'), isFalse);
    });

    test('two streams from one name: live until both are gone', () {
      final r = KdsPresenceRegistry();
      r.streamOpened('Bar');
      r.streamOpened('bar');
      r.streamClosed('Bar');
      expect(r.byName('Bar')!.live, isTrue);
      r.streamClosed('Bar');
      expect(r.byName('Bar')!.live, isFalse);
    });

    test('an old screen that sends no name is not tracked', () {
      final r = KdsPresenceRegistry();
      r.seen(null);
      r.seen('  ');
      expect(r.snapshot(), isEmpty);
    });

    test('stations header parsing', () {
      expect(parseKdsStations(' Grill, ,Bar '), ['Grill', 'Bar']);
      expect(parseKdsStations(null), isEmpty);
    });
  });

  group('change signal', () {
    late StreamController<Set<TableUpdate>> writes;
    late List<LanEvent> sent;
    late int listeners;
    late DateTime now;
    late KdsChangeSignal signal;

    setUp(() {
      writes = StreamController<Set<TableUpdate>>.broadcast();
      sent = [];
      listeners = 1;
      now = DateTime(2026, 11, 25, 12, 0, 1);
      signal = KdsChangeSignal(
        updates: () => writes.stream,
        publish: (channel, e) {
          expect(channel, 'kds:*');
          sent.add(e);
          return listeners;
        },
        listeners: (_) => listeners,
        delay: const Duration(milliseconds: 30),
        now: () => now,
        boot: 'b',
      )..start();
    });
    tearDown(() async {
      await signal.stop();
      await writes.close();
    });

    test('a burst of writes is one nudge', () async {
      for (var i = 0; i < 10; i++) {
        writes.add({});
      }
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(sent.map((e) => e.name), ['orders-changed']);
    });

    test('a steady stream of writes still nudges (throttle, not debounce)',
        () async {
      final ticker = Timer.periodic(
          const Duration(milliseconds: 10), (_) => writes.add({}));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      ticker.cancel();
      expect(sent.length, greaterThanOrEqualTo(2));
    });

    test('nobody listening: nothing sent', () async {
      listeners = 0;
      writes.add({});
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(sent, isEmpty);
    });

    test('the version moves on every write and every 30 s', () async {
      final v0 = signal.version;
      expect(signal.version, v0, reason: 'stable while nothing happens');
      writes.add({});
      await Future<void>.delayed(Duration.zero);
      final v1 = signal.version;
      expect(v1, isNot(v0));
      now = now.add(const Duration(seconds: 30));
      expect(signal.version, isNot(v1));
    });

    test('stopping invalidates every version handed out', () async {
      final v = signal.version;
      await signal.stop();
      expect(signal.version, isNot(v));
    });
  });

  // ── Over real HTTP ──────────────────────────────────────────────────────

  late AppDatabase db;
  late ProviderContainer container;
  late ServerService server;
  const port = 18131;
  final base = Uri.parse('http://127.0.0.1:$port');
  late int orderA;
  late int tajineLine;

  Future<void> boot({String? password}) async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
        id: const Value(1), code: '1', cashierId: 1, moneyAtStart: 0.0));
    container.read(currentSessionProvider.notifier).state =
        await (db.select(db.cashSessions)..where((s) => s.id.equals(1)))
            .getSingle();
    await db.into(db.stations).insert(
        StationsCompanion.insert(id: const Value(1), name: 'Cuisine'));
    await db
        .into(db.stations)
        .insert(StationsCompanion.insert(id: const Value(2), name: 'Bar'));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(10),
        name: 'Tajine',
        price: 10,
        finalPrice: 10,
        stationId: const Value(1),
        preparingDuration: const Value(25)));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(20),
        name: 'Coca',
        price: 10,
        finalPrice: 10,
        stationId: const Value(2)));
    await db.into(db.components).insert(ComponentsCompanion.insert(
        id: const Value(5),
        name: 'Coca menu',
        linkedProductId: const Value(20)));
    await db
        .into(db.components)
        .insert(ComponentsCompanion.insert(id: const Value(6), name: 'Oignon'));
    await db
        .into(db.components)
        .insert(ComponentsCompanion.insert(id: const Value(7), name: 'Sauce'));
    await db
        .into(db.components)
        .insert(ComponentsCompanion.insert(id: const Value(8), name: 'Olives'));
    await db.into(db.waiters).insert(WaitersCompanion.insert(
        id: const Value(3), firstName: 'Sara', lastName: const Value('B')));

    orderA = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'A',
          type: const Value('DINE_IN'),
          source: const Value('WAITER'),
          waiterId: const Value(3),
          sessionId: const Value(1),
          status: const Value('COMPLETED'),
        ));
    tajineLine = await db.into(db.orderProducts).insert(
        OrderProductsCompanion.insert(
            orderId: orderA, productId: 10, unitaryPrice: 10));
    for (final c in [
      // A real option.
      OrderProductComponentsCompanion.insert(
          componentId: 8, orderProductId: tajineLine),
      // "No onion", still charged: not something to make.
      OrderProductComponentsCompanion.insert(
          componentId: 6,
          orderProductId: tajineLine,
          name: const Value('Oignon'),
          removalCharge: const Value(true)),
      // A zero-quantity signal row for the server.
      OrderProductComponentsCompanion.insert(
          componentId: 7, orderProductId: tajineLine, quantity: const Value(0)),
      // The menu drink, taken off: the bar must not make it.
      OrderProductComponentsCompanion.insert(
          componentId: 5,
          orderProductId: tajineLine,
          removalCharge: const Value(true)),
    ]) {
      await db.into(db.orderProductComponents).insert(c);
    }

    server = container.read(serverServiceProvider);
    await server.start(port: port, password: password);
  }

  Future<void> shutdown() async {
    await server.stop();
    container.dispose();
    await db.close();
  }

  Future<Map<String, dynamic>> getOrders(Map<String, String> q,
      {Map<String, String> headers = const {}}) async {
    final res = await http.get(base.replace(path: '/orders', queryParameters: q),
        headers: headers);
    expect(res.statusCode, 200, reason: res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Opens the event stream and yields each `event:` name as it arrives.
  Future<(http.Client, Stream<String>)> openEvents(
      Map<String, String> q) async {
    final client = http.Client();
    final res = await client.send(http.Request(
        'GET', base.replace(path: '/orders/events', queryParameters: q)));
    expect(res.statusCode, 200);
    final events = res.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((l) => l.startsWith('event: '))
        .map((l) => l.substring(7))
        .asBroadcastStream();
    return (client, events);
  }

  group('feed, no password', () {
    setUp(boot);
    tearDown(shutdown);

    test('an old screen gets the same feed, plus a version it ignores',
        () async {
      final body = await getOrders({'station': 'Cuisine'});
      expect((body['orders'] as List).single['code'], 'A');
      expect(body['version'], isA<String>());
      expect(body.keys, containsAll(<String>[
        'orders', 'orders_updated', 'orders_deleted', 'last_log_id',
        'count', 'updated_count', 'deleted_count',
      ]));
    });

    test('nothing written since: the short answer, same shape', () async {
      final first = await getOrders({'station': 'Cuisine'});
      final cursors = {
        'station': 'Cuisine',
        'after_id': '$orderA',
        'updated_after_log_id': '${first['last_log_id']}',
      };
      final full = await getOrders(cursors);
      final short = await getOrders(
          {...cursors, 'known_version': first['version'] as String});
      expect(short, full, reason: 'a screen cannot tell them apart');
    });

    test('a write in between: the full answer, with the change', () async {
      final first = await getOrders({'station': 'Cuisine'});
      await server.applyKitchenLineState(tajineLine, 'PREPARING');
      final next = await getOrders({
        'station': 'Cuisine',
        'after_id': '$orderA',
        'updated_after_log_id': '${first['last_log_id']}',
        'known_version': first['version'] as String,
      });
      expect(next['version'], isNot(first['version']));
      final updated = next['orders_updated'] as List;
      expect(updated, isNotEmpty);
      expect((updated.single['products'] as List).single['state'],
          'PREPARING');
    });

    test('the first poll (no cursors) is never cut short', () async {
      final first = await getOrders({'station': 'Cuisine'});
      final again = await getOrders(
          {'station': 'Cuisine', 'known_version': first['version'] as String});
      expect((again['orders'] as List), isNotEmpty);
    });

    test('a removed option says "no", a signal row says nothing', () async {
      final line = ((await getOrders({'station': 'Cuisine'}))['orders']
              as List)
          .single['products']
          .single as Map<String, dynamic>;
      expect((line['components'] as List).map((c) => c['componentName']),
          ['Olives']);
      expect(line['removedComponents'],
          unorderedEquals(['Oignon', 'Coca menu']));
      expect(line['prepMinutes'], 25);
    });

    test('a drink taken off the menu does not reach the bar', () async {
      final body = await getOrders({'station': 'Bar', 'linked': '1'});
      expect(body['orders'], isEmpty);
    });

    test('who rang it up rides on the order', () async {
      final order = ((await getOrders({}))['orders'] as List).single
          as Map<String, dynamic>;
      expect(order['source'], 'WAITER');
      expect(order['waiterName'], 'Sara B');
    });

    test('a screen that names itself shows up as polling', () async {
      await getOrders({'station': 'Cuisine'},
          headers: {'X-KDS-Name': 'Grill 1', 'X-KDS-Stations': 'Cuisine'});
      final p = container.read(kdsPresenceProvider).byName('grill 1')!;
      expect(p.stations, ['Cuisine']);
      expect(p.live, isFalse);
      expect(container.read(kdsPresenceProvider).isOnline('Grill 1'), isTrue);
    });

    test('the stream says hello, then nudges on a kitchen write', () async {
      final (client, events) =
          await openEvents({'name': 'Grill 1', 'stations': 'Cuisine'});
      try {
        expect(await events.first.timeout(const Duration(seconds: 2)),
            'connected');
        expect(container.read(kdsPresenceProvider).byName('Grill 1')!.live,
            isTrue);
        final nudge = events.first.timeout(const Duration(seconds: 2));
        await server.applyKitchenLineState(tajineLine, 'PREPARING');
        expect(await nudge, 'orders-changed');
      } finally {
        client.close();
      }
      // The hub only notices a gone client when a write to it fails, which
      // can take a write or two after the socket closed (the heartbeat does
      // this every 20 s on a quiet till).
      var live = true;
      for (var i = 0; i < 20 && live; i++) {
        await db.into(db.orderLogs).insert(OrderLogsCompanion.insert(
            orderId: orderA, action: 'UPDATED'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
        live = container.read(kdsPresenceProvider).byName('Grill 1')!.live;
      }
      expect(live, isFalse);
    });
  });

  group('feed, password set', () {
    setUp(() => boot(password: 'secret'));
    tearDown(shutdown);

    test('the stream refuses a stranger', () async {
      final res = await http.get(base.replace(path: '/orders/events'));
      expect(res.statusCode, 403);
    });

    test('a ticket needs the password, and opens the stream once', () async {
      final refused =
          await http.post(base.replace(path: '/orders/events/ticket'));
      expect(refused.statusCode, 403);

      final res = await http.post(base.replace(path: '/orders/events/ticket'),
          headers: {'X-Server-Password': 'secret'});
      expect(res.statusCode, 200);
      final ticket =
          (jsonDecode(res.body) as Map<String, dynamic>)['ticket'] as String;

      final (client, events) =
          await openEvents({'ticket': ticket, 'name': 'Web'});
      try {
        expect(await events.first.timeout(const Duration(seconds: 2)),
            'connected');
      } finally {
        client.close();
      }

      final reuse = await http.get(base.replace(
          path: '/orders/events', queryParameters: {'ticket': ticket}));
      expect(reuse.statusCode, 403, reason: 'single use');
    });

    test('the password header opens it directly (native screens)', () async {
      final client = http.Client();
      try {
        final res = await client.send(http.Request(
            'GET', base.replace(path: '/orders/events'))
          ..headers['X-Server-Password'] = 'secret');
        expect(res.statusCode, 200);
      } finally {
        client.close();
      }
    });

    test('the password is still required on the feed itself', () async {
      final res = await http.get(base.replace(path: '/orders'));
      expect(res.statusCode, 403);
    });
  });
}

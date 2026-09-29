import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/socket_models.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/lan_notification_hub.dart';
import 'package:caisse212/services/waiter_kitchen_events.dart';

/// Kitchen feedback on the waiter phones: what the waiter is told, and — just
/// as important — when they are told nothing.

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
  group('kitchenStateOf', () {
    test('a paid line keeps the kitchen state its timestamps prove', () {
      expect(
          kitchenStateOf(state: 'PAID', readyAt: DateTime(2026)), 'READY');
      expect(kitchenStateOf(state: 'PAID', preparingAt: DateTime(2026)),
          'PREPARING');
      expect(kitchenStateOf(state: 'PAID'), 'PENDING');
    });

    test('COMPLETED without a READY stage still reads as ready', () {
      expect(kitchenStateOf(state: 'COMPLETED'), 'READY');
      expect(kitchenStateOf(state: 'DELIVERED'), 'READY');
    });

    test('canceled wins over any timestamp', () {
      expect(
          kitchenStateOf(state: 'CANCELED', readyAt: DateTime(2026)),
          'CANCELED');
    });
  });

  group('SocketOrderProductModel.courseNo', () {
    SocketOrderProductModel line(int? course) => SocketOrderProductModel(
          id: 1,
          productId: 1,
          productName: 'Tajine',
          quantity: 1,
          unitaryPrice: 50,
          state: 'PENDING',
          components: const [],
          courseNo: course,
        );

    test('rides the KDS payload when set, absent when not', () {
      expect(line(2).toJson()['courseNo'], 2);
      expect(line(null).toJson().containsKey('courseNo'), isFalse);
    });

    test('an out-of-range course parses as no course', () {
      final json = line(null).toJson()..['courseNo'] = 7;
      expect(SocketOrderProductModel.fromJson(json).courseNo, isNull);
    });
  });

  group('WaiterKitchenEventService', () {
    late AppDatabase db;
    late ProviderContainer container;
    late WaiterKitchenEventService events;
    late List<String> waiter1;
    late List<String> waiter2;
    late int orderId;

    Future<void> boot(Map<String, Object> prefsValues) async {
      SharedPreferences.setMockInitialValues(prefsValues);
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      events = container.read(waiterKitchenEventServiceProvider);
      final hub = container.read(lanNotificationHubProvider);
      waiter1 = [];
      waiter2 = [];
      hub.subscribe('waiter:1').listen((b) => waiter1.add(utf8.decode(b)));
      hub.subscribe('waiter:2').listen((b) => waiter2.add(utf8.decode(b)));
      await Future<void>.delayed(Duration.zero);
    }

    Future<int> line(int productId, {String state = 'PENDING', int? course}) =>
        db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
              orderId: orderId,
              productId: productId,
              unitaryPrice: 10,
              state: Value(state),
              courseNo: Value(course),
            ));

    List<({String name, Map<String, dynamic> data})> kitchen(List<String> raw) =>
        parseFrames(raw.join()).where((e) => e.name != 'connected').toList();

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value(1), name: 'Salade', price: 10, finalPrice: 10));
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value(2), name: 'Tajine', price: 10, finalPrice: 10));
      final tableId = await db
          .into(db.areaTables)
          .insert(AreaTablesCompanion.insert(name: 'T5'));
      orderId = await db.into(db.orders).insert(OrdersCompanion.insert(
            code: 'A-1',
            tableId: Value(tableId),
            waiterId: const Value(1),
          ));
    });
    tearDown(() async {
      container.dispose();
      await db.close();
    });

    test('a bumped ticket reaches its waiter as ONE event', () async {
      await boot({'waiter_notify_ready': true});
      final a = await line(1, state: 'READY', course: 1);
      final b = await line(2, state: 'READY', course: 2);
      events.lineReady(orderId: orderId, lineId: a);
      events.lineReady(orderId: orderId, lineId: b);
      await events.flushReady(orderId);
      await Future<void>.delayed(Duration.zero);

      final got = kitchen(waiter1);
      expect(got.map((e) => e.name), ['kitchen-ready']);
      expect(got.single.data['tableName'], 'T5');
      expect(got.single.data['orderCode'], 'A-1');
      expect((got.single.data['lines'] as List).map((l) => l['name']),
          containsAll(['Salade', 'Tajine']));
      expect(got.single.data['eventId'], isA<String>());
      // Another waiter's phone stays quiet.
      expect(kitchen(waiter2), isEmpty);
    });

    test('switch off → nothing is sent', () async {
      await boot({});
      final a = await line(1, state: 'READY');
      events.lineReady(orderId: orderId, lineId: a);
      await events.flushReady(orderId);
      await events.linesCanceled(
          orderId: orderId, wholeOrder: true, reason: 'client parti');
      events.productAvailabilityChanged(
          productId: 1, name: 'Salade', isAvailable: false);
      await Future<void>.delayed(Duration.zero);
      expect(kitchen(waiter1), isEmpty);
    });

    test('a cancel notice names the lines and the reason', () async {
      await boot({'waiter_notify_canceled': true});
      await events.linesCanceled(orderId: orderId, lines: const [
        CanceledLine(name: 'Salade', quantity: 1, courseNo: 1),
      ]);
      await Future<void>.delayed(Duration.zero);

      final got = kitchen(waiter1).single;
      expect(got.name, 'kitchen-canceled');
      expect(got.data['wholeOrder'], isFalse);
      expect((got.data['lines'] as List).single['courseNo'], 1);
    });

    test('rupture is broadcast to every waiter', () async {
      await boot({'waiter_notify_rupture': true});
      events.productAvailabilityChanged(
          productId: 2, name: 'Tajine', isAvailable: false);
      await Future<void>.delayed(Duration.zero);

      expect(kitchen(waiter1).single.name, 'product-availability');
      expect(kitchen(waiter2).single.data['isAvailable'], isFalse);
    });

    test('a waiter who reconnects is owed the events they missed', () async {
      await boot({'waiter_notify_ready': true, 'waiter_notify_rupture': true});
      final a = await line(2, state: 'READY');
      events.lineReady(orderId: orderId, lineId: a);
      await events.flushReady(orderId);
      events.productAvailabilityChanged(
          productId: 1, name: 'Salade', isAvailable: false);

      expect(events.replayEventsFor(1).map((e) => e.name),
          ['kitchen-ready', 'product-availability']);
      // Waiter 2 missed the broadcast but not someone else's ready food.
      expect(events.replayEventsFor(2).map((e) => e.name),
          ['product-availability']);
    });

    test('an order with no waiter tells nobody', () async {
      await boot({'waiter_notify_ready': true});
      orderId = await db
          .into(db.orders)
          .insert(OrdersCompanion.insert(code: 'COUNTER-1'));
      final a = await line(1, state: 'READY');
      events.lineReady(orderId: orderId, lineId: a);
      await events.flushReady(orderId);
      await Future<void>.delayed(Duration.zero);
      expect(kitchen(waiter1), isEmpty);
    });
  });
}

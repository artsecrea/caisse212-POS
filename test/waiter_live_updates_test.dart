import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/lan_notification_hub.dart';
import 'package:caisse212/services/waiter_kitchen_events.dart';
import 'package:caisse212/services/waiter_live_updates.dart';
import 'package:caisse212/services/waiter_notification_inbox.dart';
import 'package:caisse212/services/waiter_order_money.dart';

List<({String name, Map<String, dynamic> data})> frames(List<String> raw) {
  final out = <({String name, Map<String, dynamic> data})>[];
  for (final block in raw.join().split('\n\n')) {
    String? name;
    String? data;
    for (final line in block.split('\n')) {
      if (line.startsWith('event:')) name = line.substring(6).trim();
      if (line.startsWith('data:')) data = line.substring(5).trim();
    }
    if (name != null && data != null && name != 'connected') {
      out.add((name: name, data: jsonDecode(data) as Map<String, dynamic>));
    }
  }
  return out;
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late List<String> waiter1;
  late List<String> waiter2;
  late int orderId;
  late int lineA;
  late int lineB;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({'waiter_notify_ready': true});
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

    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'Tajine', price: 50, finalPrice: 50));
    final tableId = await db
        .into(db.areaTables)
        .insert(AreaTablesCompanion.insert(name: '5'));
    orderId = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'A-1',
          tableId: Value(tableId),
          waiterId: const Value(1),
          sessionId: const Value(1),
          status: const Value('COMPLETED'),
        ));
    await (db.update(db.areaTables)..where((t) => t.id.equals(tableId)))
        .write(AreaTablesCompanion(orderId: Value(orderId)));
    // 2 × 45 after a 5 promo, and 1 × 50 with a 10 manual discount.
    lineA = await db.into(db.orderProducts).insert(
        OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            unitaryPrice: 45,
            unitaryDiscount: const Value(5),
            quantity: const Value(2)));
    lineB = await db.into(db.orderProducts).insert(
        OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            unitaryPrice: 50,
            manualDiscount: const Value(10)));

    final hub = container.read(lanNotificationHubProvider);
    waiter1 = [];
    waiter2 = [];
    hub.subscribe('waiter:1').listen((b) => waiter1.add(utf8.decode(b)));
    hub.subscribe('waiter:2').listen((b) => waiter2.add(utf8.decode(b)));
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<WaiterOrderMoney> money() async {
    final o = await (db.select(db.orders)..where((x) => x.id.equals(orderId)))
        .getSingle();
    final ls = await (db.select(db.orderProducts)
          ..where((l) => l.orderId.equals(orderId)))
        .get();
    return WaiterOrderMoney.of(o, ls, const {});
  }

  group('WaiterOrderMoney', () {
    test('gross, discount and total agree with the till', () async {
      final m = (await money()).toJson();
      expect(m['subtotalAmount'], 150.0); // 2×50 + 50
      expect(m['discountAmount'], 20.0); // 2×5 promo + 10 manual
      expect(m['totalAmount'], 130.0);
      expect(m['balanceAmount'], 130.0);
      expect(m['paidAmount'], 0.0);
      expect(m['discountLabel'], isNull);
    });

    test('an order-level percentage comes off total and balance', () async {
      await (db.update(db.orders)..where((o) => o.id.equals(orderId))).write(
          const OrdersCompanion(
              discountPercentage: Value(10), discountReason: Value('Fidèle')));
      final m = (await money()).toJson();
      expect(m['totalAmount'], 117.0);
      expect(m['discountAmount'], 33.0);
      expect(m['discountLabel'], '-10%');
      expect(m['discountReason'], 'Fidèle');
    });
  });

  group('WaiterLiveUpdateService', () {
    late WaiterLiveUpdateService live;
    setUp(() async {
      live = container.read(waiterLiveUpdateServiceProvider);
      await live.scan(); // baseline — must publish nothing
      await Future<void>.delayed(Duration.zero);
      expect(frames(waiter1), isEmpty);
    });

    test('a partial payment at the till nudges the waiter and the floor',
        () async {
      final ticket = await db.into(db.tickets).insert(TicketsCompanion.insert(num: '0001',
          orderId: orderId, amount: 40, paymentMethod: 'CASH'));
      await (db.update(db.orderProducts)..where((l) => l.id.equals(lineB)))
          .write(OrderProductsCompanion(ticketId: Value(ticket)));
      await live.scan();
      await Future<void>.delayed(Duration.zero);

      final got = frames(waiter1);
      final updated = got.firstWhere((e) => e.name == 'order-updated');
      expect(updated.data['reason'], 'partial-payment');
      expect(updated.data['balanceAmount'], 90.0);
      expect(updated.data['tableName'], '5');
      expect(got.map((e) => e.name), contains('tables-changed'));
      // The other waiter hears about the table, not about the order.
      expect(frames(waiter2).map((e) => e.name), ['tables-changed']);
    });

    test('paying every line reads as paid', () async {
      final ticket = await db.into(db.tickets).insert(TicketsCompanion.insert(num: '0001',
          orderId: orderId, amount: 130, paymentMethod: 'CASH'));
      await (db.update(db.orderProducts)
            ..where((l) => l.orderId.equals(orderId)))
          .write(OrderProductsCompanion(ticketId: Value(ticket)));
      await live.scan();
      await Future<void>.delayed(Duration.zero);
      final u = frames(waiter1).firstWhere((e) => e.name == 'order-updated');
      expect(u.data['reason'], 'paid');
      expect(u.data['allPaid'], isTrue);
    });

    test('a discount and a new line each get their reason', () async {
      await (db.update(db.orders)..where((o) => o.id.equals(orderId)))
          .write(const OrdersCompanion(discountPercentage: Value(10)));
      await live.scan();
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
          orderId: orderId, productId: 1, unitaryPrice: 50));
      await live.scan();
      await Future<void>.delayed(Duration.zero);
      expect(
          frames(waiter1)
              .where((e) => e.name == 'order-updated')
              .map((e) => e.data['reason']),
          ['discount', 'lines']);
    });

    test('a scan with nothing changed says nothing', () async {
      await live.scan();
      await Future<void>.delayed(Duration.zero);
      expect(frames(waiter1), isEmpty);
    });

    test('order-updated is never kept in the inbox', () async {
      await (db.update(db.orders)..where((o) => o.id.equals(orderId)))
          .write(const OrdersCompanion(status: Value('CANCELED')));
      await live.scan();
      expect(container.read(waiterNotificationInboxProvider).listFor(1),
          isEmpty);
    });
  });

  test('a kitchen alert the waiter dismissed is not replayed', () async {
    await (db.update(db.orderProducts)..where((l) => l.id.equals(lineA)))
        .write(const OrderProductsCompanion(state: Value('READY')));
    final kitchen = container.read(waiterKitchenEventServiceProvider);
    kitchen.lineReady(orderId: orderId, lineId: lineA);
    await kitchen.flushReady(orderId);
    final replay = kitchen.replayEventsFor(1);
    expect(replay, hasLength(1));

    container
        .read(waiterNotificationInboxProvider)
        .markRead(1, [replay.single.data['eventId'] as String]);
    expect(kitchen.replayEventsFor(1), isEmpty);
  });
}

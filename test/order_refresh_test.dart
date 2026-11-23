import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';

/// The session refresh: the server's copy of each order replaces the local one
/// (admin cancel, discount, note) — except where that would lose the till's
/// own work. `docs/ORDER_REFRESH_CONTRACT.md`.
void main() {
  late AppDatabase db;
  late DataSyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sync = DataSyncService(db, ApiService(prefs), prefs);
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'Burger', price: 10, finalPrice: 10));
    await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
        id: const Value(7), code: 'S-7', cashierId: 1, moneyAtStart: 0));
  });
  tearDown(() => db.close());

  Future<Order> order(String code) =>
      (db.select(db.orders)..where((o) => o.code.equals(code))).getSingle();

  Future<int> seed({bool synced = true}) => db.into(db.orders).insert(
      OrdersCompanion.insert(
          code: 'ORD1', sessionId: const Value(7), isSynced: Value(synced)));

  Map<String, dynamic> snapshot({
    String status = 'COMPLETED',
    double discount = 0,
    Object? sessionId = 991,
    List<Map<String, dynamic>> payments = const [],
  }) =>
      {
        'code': 'ORD1',
        'status': status,
        'discountPercentage': discount,
        'note': 'admin note',
        'sessionId': sessionId, // the server's own key, not ours
        'products': [
          {'id': 501, 'productId': 1, 'quantity': 2, 'price': 10.0},
        ],
        'payments': payments,
      };

  test('an admin cancel and discount land on the local order', () async {
    await seed();

    expect(
        await sync.applyServerOrder(snapshot(status: 'CANCELED', discount: 10)),
        isTrue);

    final o = await order('ORD1');
    expect(o.status, 'CANCELED');
    expect(o.discountPercentage, 10);
    expect(o.note, 'admin note');
  });

  test('the server\'s sessionId never replaces the till\'s', () async {
    await seed();
    await sync.applyServerOrder(snapshot());
    expect((await order('ORD1')).sessionId, 7);
  });

  test('an order new to the till joins the session being refreshed',
      () async {
    await sync.applyServerOrder(snapshot(), localSessionId: 7);
    expect((await order('ORD1')).sessionId, 7);
  });

  test('an order with an unpushed edit is left alone', () async {
    await seed(synced: false);

    expect(await sync.applyServerOrder(snapshot(status: 'CANCELED')), isFalse);
    final o = await order('ORD1');
    expect(o.status, isNot('CANCELED'));
    expect(o.isSynced, isFalse, reason: 'the edit must still be pushed');
  });

  test('a queued operation on the order also protects it', () async {
    final id = await seed();
    await db.into(db.pendingSyncOperations).insert(
        PendingSyncOperationsCompanion.insert(
            operationType: 'UPDATE',
            entityType: 'ORDER',
            entityId: id,
            orderCode: const Value('ORD1')));

    expect(await sync.applyServerOrder(snapshot(status: 'CANCELED')), isFalse);
  });

  test('an order tombstone never deletes the order', () async {
    await seed();
    expect(
        await sync.applyServerOrder(
            {...snapshot(), 'deletedAt': '2026-10-02T10:00:00Z'}),
        isFalse);
    expect(await order('ORD1'), isNotNull);
  });

  test('payments in the snapshot are applied, tombstones removed', () async {
    final id = await seed();
    await db.into(db.tickets).insert(TicketsCompanion.insert(
        num: '0002', orderId: id, paymentMethod: 'CASH', amount: 5));

    await sync.applyServerOrder(snapshot(payments: [
      {'num': '0001', 'paymentMethod': 'CARD', 'amount': 20.0, 'isPaid': true},
      {'num': '0002', 'deletedAt': '2026-10-02T10:00:00Z'},
    ]));

    final tickets = await (db.select(db.tickets)
          ..where((t) => t.orderId.equals(id)))
        .get();
    expect(tickets.map((t) => t.num), ['0001']);
    expect(tickets.single.sessionId, 7);
  });

  group('the backend\'s WebOrderResponse names', () {
    // As the V188 audit describes it: state, covers, options[].componentName,
    // payments[].ticketNumber/method, no order note, no isPaid.
    Map<String, dynamic> webOrder() => {
          'code': 'ORD1',
          'state': 'CANCELED',
          'cancellationReason': 'customer left',
          'covers': 3,
          'products': [
            {
              'id': 501,
              'productId': 1,
              'quantity': 1,
              'price': 10.0,
              'options': [
                {'componentId': 9, 'componentName': 'Cheese', 'quantity': 1, 'price': 2.0},
                {'componentId': 8, 'componentName': 'Bacon', 'quantity': 1,
                  'price': 3.0, 'deletedAt': '2026-10-02T10:00:00Z'},
              ],
            },
          ],
          'payments': [
            {'ticketNumber': '0001', 'method': 'CASH', 'amount': 12.0, 'isCancelled': false},
          ],
        };

    test('are read: status, covers, options, payments', () async {
      final id = await seed();
      await sync.applyServerOrder(webOrder());

      final o = await order('ORD1');
      expect(o.status, 'CANCELED');
      expect(o.cancellationReason, 'customer left');
      expect(o.persons, 3);

      final line = await (db.select(db.orderProducts)
            ..where((l) => l.orderId.equals(id)))
          .getSingle();
      final options = await (db.select(db.orderProductComponents)
            ..where((c) => c.orderProductId.equals(line.id)))
          .get();
      expect(options.map((c) => c.name), ['Cheese'],
          reason: 'the voided option is not re-added');

      final ticket = await (db.select(db.tickets)
            ..where((t) => t.orderId.equals(id)))
          .getSingle();
      expect(ticket.num, '0001');
      expect(ticket.paymentMethod, 'CASH');
      expect(ticket.isPaid, isTrue);
    });

    test('fields the server does not store survive a refresh', () async {
      await db.into(db.orders).insert(OrdersCompanion.insert(
            code: 'ORD1',
            sessionId: const Value(7),
            isSynced: const Value(true),
            note: const Value('no onions, table by the window'),
            coupon: const Value('WELCOME10'),
          ));

      await sync.applyServerOrder(webOrder());

      final o = await order('ORD1');
      expect(o.note, 'no onions, table by the window');
      expect(o.coupon, 'WELCOME10');
    });
  });

  test('every service instance tells the order panel', () async {
    await seed();
    // The panel listens through one instance; the Sync button uses another.
    final panelSide = DataSyncService(db, ApiService(
        await SharedPreferences.getInstance()));
    final heard = <int>[];
    final sub = panelSide.syncedOrderUpdatedStream.listen(heard.add);

    await sync.applyServerOrder(snapshot());
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    expect(heard, [(await order('ORD1')).id]);
  });
}

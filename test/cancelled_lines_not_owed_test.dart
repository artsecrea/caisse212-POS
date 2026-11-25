import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/services/waiter_order_money.dart';

/// A cancelled line stays on the order — the kitchen and the cloud still see
/// it — but nobody pays for it. Lines arrive CANCELED when the web cancels
/// one ("delete means cancel") or when a whole order is cancelled. Every
/// total used to count them anyway, so quick pay charged for food the web
/// had already struck off.

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  group('cart', () {
    final order = CurrentOrder(
      discountPercentage: 10,
      items: [
        OrderItem(productId: 1, productName: 'A', finalPrice: 20, quantity: 2),
        OrderItem(
            productId: 2,
            productName: 'B',
            finalPrice: 50,
            state: 'CANCELED'),
      ],
    );

    test('totals leave the cancelled line out', () {
      expect(order.totalBeforeDiscount, 40);
      expect(order.total, closeTo(36, 1e-9));
    });

    test('there is nothing to pay on a cancelled line', () {
      expect(order.unpaidItems.map((i) => i.productId), [1]);
    });

    test('a line paid and then cancelled still counts: it was paid', () {
      final paidThenCancelled = CurrentOrder(items: [
        OrderItem(productId: 1, productName: 'A', finalPrice: 20),
        OrderItem(
            productId: 2,
            productName: 'B',
            finalPrice: 15,
            ticketId: 9,
            state: 'CANCELED'),
      ]);
      expect(paidThenCancelled.total, 35);
      expect(paidThenCancelled.unpaidItems.map((i) => i.productId), [1]);
    });
  });

  group('stored orders', () {
    late AppDatabase db;
    late ProviderContainer container;
    late OrderRepository repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ]);
      repo = OrderRepository(db, container.read(_refProvider));
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value(1), name: 'P', price: 10, finalPrice: 10));
    });
    tearDown(() {
      container.dispose();
      return db.close();
    });

    Future<int> order({double pct = 0}) =>
        db.into(db.orders).insert(OrdersCompanion.insert(
              code: 'O${DateTime.now().microsecondsSinceEpoch}',
              status: const Value('COMPLETED'),
              discountPercentage: Value(pct),
            ));

    Future<int> line(int orderId, double price,
            {String state = 'PENDING', int? ticketId}) =>
        db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
              orderId: orderId,
              productId: 1,
              unitaryPrice: price,
              state: Value(state),
              ticketId: Value(ticketId),
            ));

    test('getOrderTotals and the unpaid SQL agree on it', () async {
      final o = await order(pct: 10);
      await line(o, 30);
      await line(o, 70, state: 'CANCELED');
      expect((await repo.getOrderTotals([o]))[o], closeTo(27, 1e-9));

      // Paid for everything still owed: no longer unpaid, although the
      // cancelled line was never paid.
      await db.into(db.tickets).insert(TicketsCompanion.insert(
          num: '0001',
          orderId: o,
          paymentMethod: 'CASH',
          amount: 27,
          isPaid: const Value(true)));
      expect(await repo.getUnpaidOrdersForResume(), isEmpty);
    });

    test('an order whose every line is cancelled owes nothing', () async {
      final o = await order();
      await line(o, 30, state: 'CANCELED');
      expect((await repo.getOrderTotals([o]))[o], 0);
      expect(await repo.getUnpaidOrdersForResume(), isEmpty);
    });

    test('a line cancelled after it was paid stays on the bill', () async {
      // A paid on T1; B still owed. The back office then cancels A.
      final o = await order();
      final t1 = await db.into(db.tickets).insert(TicketsCompanion.insert(
          num: '0001',
          orderId: o,
          paymentMethod: 'CASH',
          amount: 10,
          isPaid: const Value(true)));
      await line(o, 10, state: 'CANCELED', ticketId: t1);
      await line(o, 10);

      // The 10 taken is still part of the bill, so B is still owed.
      expect((await repo.getOrderTotals([o]))[o], 20);
      expect((await repo.getUnpaidOrdersForResume()).map((x) => x.id), [o]);
    });

    test('the waiter API: nothing owed is not the same as paid', () async {
      final o = await order();
      await line(o, 30, state: 'CANCELED');
      final row = await (db.select(db.orders)..where((t) => t.id.equals(o)))
          .getSingle();
      final money =
          WaiterOrderMoney.of(row, await db.select(db.orderProducts).get(), const {});
      expect(money.total, 0);
      expect(money.allPaid, isFalse,
          reason: 'cancelled before anyone paid: never settled');
    });

    test('the waiter balance takes the amount already split off', () async {
      final o = await order();
      await line(o, 40);
      final row = await (db.select(db.orders)..where((t) => t.id.equals(o)))
          .getSingle();
      final money = WaiterOrderMoney.of(
          row, await db.select(db.orderProducts).get(), const {},
          credit: 15);
      expect(money.total, 40);
      expect(money.balance, 25);
      expect(money.allPaid, isFalse, reason: 'no line is settled yet');
    });

    test('an order cancelled with either spelling is not unpaid', () async {
      final o = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'DOUBLE-L', status: const Value('CANCELLED')));
      await line(o, 30);
      expect(await repo.getUnpaidOrdersForResume(), isEmpty);
    });

    test('the waiter API leaves it out of total and balance', () async {
      final o = await order(pct: 50);
      await line(o, 40);
      await line(o, 60, state: 'CANCELED');
      final row = await (db.select(db.orders)..where((t) => t.id.equals(o)))
          .getSingle();
      final lines = await db.select(db.orderProducts).get();
      final money = WaiterOrderMoney.of(row, lines, const {});
      expect(money.total, 20);
      expect(money.balance, 20);
      expect(money.allPaid, isFalse);
    });
  });
}

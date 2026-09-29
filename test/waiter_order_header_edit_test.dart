import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/providers/order_provider.dart';

/// What a cashier may do to a WAITER's order.
///
/// The old rule was all-or-nothing: a waiter order was read-only, and the
/// guard sat on the SAVE rather than on the edit. So a cashier could apply a
/// remise, watch it appear on screen, hit Print — and the discount never
/// reached the database and the ticket printed at full price.
///
/// The line is drawn where the ownership actually is: the remise, the note,
/// the covers and the tip belong to whoever settles the bill; the food
/// belongs to the waiter who rang it up. `headerOnly` enforces that in the
/// repository, so it holds even if a cart's items were somehow altered before
/// the save.

void main() {
  late AppDatabase db;
  late OrderRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OrderRepository(db);
  });
  tearDown(() => db.close());

  Future<int> seedWaiterOrder() async {
    for (final id in [1, 2]) {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: 'P$id',
            price: 100,
            finalPrice: 100,
          ));
    }
    final orderId = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'ORD1',
          source: const Value('WAITER'),
          waiterId: const Value(3),
        ));
    for (final id in [1, 2]) {
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: id,
            quantity: const Value(1),
            unitaryPrice: 100,
            kdsPrintedQuantity: const Value(1),
          ));
    }
    return orderId;
  }

  Future<Order> orderRow(int id) =>
      (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();

  Future<List<OrderProduct>> lines(int id) => (db.select(db.orderProducts)
        ..where((p) => p.orderId.equals(id))
        ..orderBy([(p) => OrderingTerm(expression: p.id)]))
      .get();

  group('the cashier keeps the header', () {
    test('a remise applied on a waiter order persists', () async {
      final orderId = await seedWaiterOrder();
      final cart = (await repo.getOrderById(orderId))!;

      await repo.updateOrder(
        cart.copyWith(discountPercentage: 20, discountReason: 'geste'),
        queueSyncOperation: false,
        headerOnly: true,
      );

      final row = await orderRow(orderId);
      expect(row.discountPercentage, 20.0,
          reason: 'this is the whole point — it used to silently not stick');
      expect(row.discountReason, 'geste');
    });

    test('the RELOADED order carries the remise — this is what prints', () async {
      // main_screen prints `getOrderById(orderId)`, never the in-memory cart
      // ("Always print the reloaded row"). So a remise that does not survive
      // the round-trip is a remise the ticket never shows, which is exactly
      // how it came to appear on the payment ticket and nowhere else.
      final orderId = await seedWaiterOrder();
      final cart = (await repo.getOrderById(orderId))!;

      await repo.updateOrder(cart.copyWith(discountPercentage: 20),
          queueSyncOperation: false, headerOnly: true);

      final reloaded = (await repo.getOrderById(orderId))!;
      expect(reloaded.discountPercentage, 20.0);
      expect(reloaded.totalDiscount, greaterThan(0),
          reason: 'the discount row is emitted under totalDiscount > 0');
      expect(reloaded.total, lessThan(reloaded.totalBeforeDiscount),
          reason: 'and the TOTAL row prints order.total');
    });

    test('a note persists too', () async {
      final orderId = await seedWaiterOrder();
      final cart = (await repo.getOrderById(orderId))!;

      await repo.updateOrder(cart.copyWith(note: 'sans oignons'),
          queueSyncOperation: false, headerOnly: true);

      expect((await orderRow(orderId)).note, 'sans oignons');
    });

    test('covers and tip persist', () async {
      final orderId = await seedWaiterOrder();
      final cart = (await repo.getOrderById(orderId))!;

      await repo.updateOrder(cart.copyWith(numberOfPersons: 6, tip: 25),
          queueSyncOperation: false, headerOnly: true);

      final row = await orderRow(orderId);
      expect(row.persons, 6);
      expect(row.tip, 25.0);
    });

    test('the order is flagged unsynced, so the remise reaches the backend',
        () async {
      final orderId = await seedWaiterOrder();
      await (db.update(db.orders)..where((o) => o.id.equals(orderId)))
          .write(const OrdersCompanion(isSynced: Value(true)));
      final cart = (await repo.getOrderById(orderId))!;

      await repo.updateOrder(cart.copyWith(discountPercentage: 10),
          queueSyncOperation: false, headerOnly: true);

      expect((await orderRow(orderId)).isSynced, isFalse);
    });
  });

  group('the waiter keeps the food', () {
    test('the lines are untouched — same rows, same ids', () async {
      final orderId = await seedWaiterOrder();
      final before = await lines(orderId);
      final cart = (await repo.getOrderById(orderId))!;

      await repo.updateOrder(cart.copyWith(discountPercentage: 20),
          queueSyncOperation: false, headerOnly: true);

      final after = await lines(orderId);
      expect(after.map((r) => r.id).toList(), before.map((r) => r.id).toList(),
          reason: 'a header save must not re-key the lines; the full path '
              'deletes and re-inserts them');
      expect(after.map((r) => r.productId).toList(), [1, 2]);
    });

    test('an item removed from the cart is NOT removed from the order',
        () async {
      final orderId = await seedWaiterOrder();
      final cart = (await repo.getOrderById(orderId))!;

      // Even if something put a shortened item list in front of the save, the
      // repository will not act on it.
      await repo.updateOrder(
        cart.copyWith(items: [cart.items.first], discountPercentage: 5),
        queueSyncOperation: false,
        headerOnly: true,
      );

      expect(await lines(orderId), hasLength(2),
          reason: 'the guarantee cannot depend on the panel disabling buttons');
      expect((await orderRow(orderId)).discountPercentage, 5.0,
          reason: 'and the header change still went through');
    });

    test('a quantity changed in the cart is NOT written', () async {
      final orderId = await seedWaiterOrder();
      final cart = (await repo.getOrderById(orderId))!;

      await repo.updateOrder(
        cart.copyWith(
            items: [for (final i in cart.items) i.copyWith(quantity: 9)]),
        queueSyncOperation: false,
        headerOnly: true,
      );

      expect((await lines(orderId)).map((r) => r.quantity), everyElement(1.0));
    });

    test('the kitchen print cursor is left alone', () async {
      final orderId = await seedWaiterOrder();
      final cart = (await repo.getOrderById(orderId))!;

      await repo.updateOrder(cart.copyWith(discountPercentage: 50),
          queueSyncOperation: false, headerOnly: true);

      expect((await lines(orderId)).map((r) => r.kdsPrintedQuantity),
          everyElement(1.0),
          reason: 'nothing here re-sends food to the kitchen');
    });
  });

  group('the cashier’s own order is unaffected', () {
    test('a full save still rewrites lines as before', () async {
      final orderId = await seedWaiterOrder();
      final cart = (await repo.getOrderById(orderId))!;

      await repo.updateOrder(
        cart.copyWith(items: [cart.items.first]),
        queueSyncOperation: false,
      );

      expect(await lines(orderId), hasLength(1),
          reason: 'headerOnly defaults to false — the normal path is unchanged');
    });
  });
}

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/services/printing_service.dart';

/// Two faults on the waiter path, both from reading the order once and acting
/// on that snapshot later.
///
///   * The waiter app writes straight into `order_products` over the LAN. The
///     cashier's panel is never told, and `updateOrder` wipes every unpaid row
///     and re-inserts what the panel holds — so the waiter's items vanished on
///     the cashier's next save, after the kitchen had cooked them.
///   * Print jobs are serialized, their callers are not. Each `add-product`
///     loaded the whole order before queuing, so a burst of adds all saw the
///     first line as never-sent and the kitchen made it once per add.

void main() {
  late AppDatabase db;
  late OrderRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OrderRepository(db);
  });
  tearDown(() => db.close());

  Future<int> seedOrder({int count = 1}) async {
    for (var i = 1; i <= count + 1; i++) {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(i),
            name: 'P$i',
            price: 10,
            finalPrice: 10,
          ));
    }
    final orderId =
        await db.into(db.orders).insert(OrdersCompanion.insert(code: 'ORD1'));
    for (var i = 1; i <= count; i++) {
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: i,
            quantity: const Value(1),
            unitaryPrice: 10,
          ));
    }
    return orderId;
  }

  /// What `_waiterAddProductToOrder` does: a bare insert, no cart involved.
  Future<int> waiterAddsLine(int orderId, {int productId = 2}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: productId,
            quantity: const Value(1),
            unitaryPrice: 10,
          ));

  Future<List<OrderProduct>> unpaidRows(int orderId) =>
      (db.select(db.orderProducts)
            ..where((t) => t.orderId.equals(orderId) & t.ticketId.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();

  group('a save from the cashier panel', () {
    test('keeps a line the waiter added while the panel sat open', () async {
      final orderId = await seedOrder();

      // Cashier opens the table.
      final cart = (await repo.getOrderById(orderId))!;
      // Waiter sends a drink to the same table a moment later.
      await waiterAddsLine(orderId);

      // Cashier saves — the panel still holds only the line it loaded.
      await repo.updateOrder(cart, queueSyncOperation: false);

      final rows = await unpaidRows(orderId);
      expect(
        rows.map((r) => r.productId).toList(),
        containsAll(<int>[1, 2]),
        reason: 'the waiter line was never in the cart, so the cart cannot '
            'have been asking for its removal',
      );
      expect(rows, hasLength(2));
    });

    test('still deletes a line the cashier really did remove', () async {
      final orderId = await seedOrder(count: 2);
      final cart = (await repo.getOrderById(orderId))!;

      final kept = cart.items.where((i) => i.productId != 2).toList();
      await repo.updateOrder(cart.copyWith(items: kept),
          queueSyncOperation: false);

      final rows = await unpaidRows(orderId);
      expect(rows.map((r) => r.productId).toList(), [1],
          reason: 'a line the cart loaded and dropped is a genuine removal');
    });

    test('a cart with no watermark behaves exactly as before', () async {
      final orderId = await seedOrder();
      final cart = (await repo.getOrderById(orderId))!;
      await waiterAddsLine(orderId);

      // A cart assembled by hand was never loaded from the database and so
      // cannot tell old rows from new: it keeps the old all-or-nothing
      // behaviour rather than guess.
      await repo.updateOrder(
        CurrentOrder(
          orderId: cart.orderId,
          orderCode: cart.orderCode,
          items: cart.items,
        ),
        queueSyncOperation: false,
      );

      expect(await unpaidRows(orderId), hasLength(1));
    });

    test('hands the backend line id back instead of inventing a new line',
        () async {
      final orderId = await seedOrder();
      final rowId = (await unpaidRows(orderId)).single.id;
      await (db.update(db.orderProducts)..where((t) => t.id.equals(rowId)))
          .write(const OrderProductsCompanion(serverId: Value(4242)));

      final cart = (await repo.getOrderById(orderId))!;
      await repo.updateOrder(cart, queueSyncOperation: false);

      expect((await unpaidRows(orderId)).single.serverId, 4242);
    });

    test('does not claw back the print cursor of a preserved line', () async {
      final orderId = await seedOrder();
      final cart = (await repo.getOrderById(orderId))!;

      // Same product as the cart's own line, so the cancellation bookkeeping
      // (which works per product, not per row) has to deal with both.
      final waiterRowId = await waiterAddsLine(orderId, productId: 1);
      await (db.update(db.orderProducts)
            ..where((t) => t.id.equals(waiterRowId)))
          .write(const OrderProductsCompanion(kdsPrintedQuantity: Value(1)));

      await repo.updateOrder(cart, queueSyncOperation: false);

      final preserved = await (db.select(db.orderProducts)
            ..where((t) => t.id.equals(waiterRowId)))
          .getSingleOrNull();
      expect(preserved != null, isTrue, reason: 'the line itself must survive');
      expect(preserved!.kdsPrintedQuantity, 1.0,
          reason: 'the kitchen was told about it and still is');
    });
  });

  group('the kitchen delta', () {
    Future<List<OrderItem>> linesFor(CurrentOrder order) => PrintingService()
        .kdsLinesForTesting(db, order, KdsPrintMode.modificationsOnly);

    test('a burst of adds sends each item once, not once per add', () async {
      final orderId = await seedOrder();

      // Add #1 loads the order and queues its ticket.
      final snapshotA = (await repo.getOrderById(orderId))!;
      // Add #2 loads before #1 has printed, so its snapshot still says the
      // first line was never sent. That window is what produced a second and
      // third copy of the same item.
      await waiterAddsLine(orderId);
      final snapshotB = (await repo.getOrderById(orderId))!;

      final firstTicket = await linesFor(snapshotA);
      expect(firstTicket.map((i) => i.productId), [1]);
      // The job marks what it printed, as the real one does on success.
      await (db.update(db.orderProducts)..where((t) => t.productId.equals(1)))
          .write(const OrderProductsCompanion(kdsPrintedQuantity: Value(1)));

      final secondTicket = await linesFor(snapshotB);
      expect(
        secondTicket.map((i) => i.productId).toList(),
        [2],
        reason: 'the second job reads committed state, so it carries only the '
            'line the first one did not',
      );
    });

    /// The exact pattern reported from the floor: the kitchen got the first
    /// item, then the first AND second, then the first, second AND third.
    /// Each add-product handler loaded the whole order before queuing its
    /// ticket, so every snapshot still said the earlier lines were unsent.
    test('the 1 / 1+2 / 1+2+3 pattern: each item reaches the kitchen once',
        () async {
      final orderId = await seedOrder();
      for (final id in [3, 4]) {
        await db.into(db.products).insert(ProductsCompanion.insert(
              id: Value(id), name: 'P$id', price: 10, finalPrice: 10));
      }

      // Three waiter calls in a burst. Each handler reads the order at its own
      // moment — none of them waits for the previous ticket to print.
      final snapshots = <CurrentOrder>[(await repo.getOrderById(orderId))!];
      for (final productId in [2, 3]) {
        await waiterAddsLine(orderId, productId: productId);
        snapshots.add((await repo.getOrderById(orderId))!);
      }

      // Now the print queue drains them, in order, marking on success.
      final tickets = <List<int>>[];
      for (final snapshot in snapshots) {
        final lines = await linesFor(snapshot);
        tickets.add([for (final line in lines) line.productId]);
        for (final line in lines) {
          await (db.update(db.orderProducts)
                ..where((t) => t.id.equals(line.id!)))
              .write(OrderProductsCompanion(
                  kdsPrintedQuantity: Value(line.quantity)));
        }
      }

      expect(tickets, [
        [1],
        [2],
        [3],
      ], reason: 'was [[1], [1,2], [1,2,3]] — the same food cooked 3, 2 and '
          '1 times over');

      // And every unit is accounted for exactly once across the three tickets.
      final printedCounts = <int, int>{};
      for (final ticket in tickets) {
        for (final productId in ticket) {
          printedCounts[productId] = (printedCounts[productId] ?? 0) + 1;
        }
      }
      expect(printedCounts, {1: 1, 2: 1, 3: 1});
    });

    test('a failed ticket is retried, not silently swallowed', () async {
      final orderId = await seedOrder();
      final snapshot = (await repo.getOrderById(orderId))!;

      // Printer down: nothing is marked, so the line is still owed to the
      // kitchen and the next send must carry it.
      expect((await linesFor(snapshot)).map((i) => i.productId), [1]);
      expect((await linesFor(snapshot)).map((i) => i.productId), [1],
          reason: 'no mark was written, so the delta is unchanged');
    });

    test('a quantity bump still prints only the added units', () async {
      final orderId = await seedOrder();
      await (db.update(db.orderProducts)..where((t) => t.productId.equals(1)))
          .write(const OrderProductsCompanion(
              quantity: Value(3), kdsPrintedQuantity: Value(1)));

      final order = (await repo.getOrderById(orderId))!;
      final lines = await linesFor(order);
      expect(lines, hasLength(1));
      expect(lines.single.kdsPrintQuantity, 2.0);
    });

    test('a line settled since the caller read it is no longer a modification',
        () async {
      final orderId = await seedOrder();
      final order = (await repo.getOrderById(orderId))!;

      final ticketId = await db.into(db.tickets).insert(
            TicketsCompanion.insert(
                orderId: orderId,
                num: 'T1',
                paymentMethod: 'CASH',
                amount: 10),
          );
      await (db.update(db.orderProducts)..where((t) => t.productId.equals(1)))
          .write(OrderProductsCompanion(ticketId: Value(ticketId)));

      expect(await linesFor(order), isEmpty);
    });

    test('a line with no row left falls back to the snapshot', () async {
      final orderId = await seedOrder();
      final order = (await repo.getOrderById(orderId))!;
      // updateOrder re-keys unpaid rows, so a missing id is a stale id at
      // least as often as a deletion — printing nothing would be worse.
      await (db.delete(db.orderProducts)
            ..where((t) => t.orderId.equals(orderId)))
          .go();

      expect(await linesFor(order), hasLength(1));
    });
  });
}

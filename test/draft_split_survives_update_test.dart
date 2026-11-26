import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/core/enums.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/domain/models/split_bill.dart';
import 'package:caisse212/presentation/paymen_screen/payment_screen.dart';
import 'package:caisse212/providers/order_provider.dart';

/// The draft ticket division is keyed by `order_products.id`, and every
/// `updateOrder` DELETES the unpaid rows and re-inserts them under fresh ids.
/// Nothing carried the division across that, so re-opening a divided order —
/// which always updates first — collapsed it back into one ticket. The
/// cashier saw two tickets saved and one ticket on return.

void main() {
  late AppDatabase db;
  late OrderRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OrderRepository(db);
  });
  tearDown(() => db.close());

  /// An order with [count] single-unit lines, each a different product.
  Future<int> seedOrder({int count = 2}) async {
    for (var i = 1; i <= count; i++) {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(i),
            name: 'P$i',
            price: 10,
            finalPrice: 10,
          ));
    }
    final orderId = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'ORD1',
        ));
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

  Future<List<int>> unpaidRowIds(int orderId) async {
    final rows = await (db.select(db.orderProducts)
          ..where((t) => t.orderId.equals(orderId) & t.ticketId.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.id)]))
        .get();
    return [for (final r in rows) r.id];
  }

  /// Put every row on its own ticket, exactly as `_persistDraftSplit` does.
  Future<void> saveOneTicketPerRow(int orderId, List<int> rowIds) async {
    for (var i = 0; i < rowIds.length; i++) {
      await db.into(db.ticketDraftSplits).insert(
            TicketDraftSplitsCompanion.insert(
              orderId: orderId,
              orderProductId: rowIds[i],
              draftIndex: i,
              quantity: 1,
            ),
          );
    }
  }

  Future<List<DraftSplitRow>> draftRows(int orderId) async {
    final rows = await (db.select(db.ticketDraftSplits)
          ..where((t) => t.orderId.equals(orderId)))
        .get();
    return [
      for (final r in rows)
        (
          orderProductId: r.orderProductId,
          draftIndex: r.draftIndex,
          quantity: r.quantity,
        ),
    ];
  }

  List<TicketData> rebuild(CurrentOrder order, List<DraftSplitRow> rows) =>
      reconstructUnpaidTickets(
        order.items.where((i) => i.ticketId == null).toList(),
        rows,
        defaultMethod: TransactionType.cash,
        discountPercentage: 0,
      );

  test('two saved tickets are still two after an update', () async {
    final orderId = await seedOrder();
    final before = await unpaidRowIds(orderId);
    await saveOneTicketPerRow(orderId, before);

    // Exactly what opening the payment screen does first.
    final order = (await repo.getOrderById(orderId))!;
    await repo.updateOrder(order, queueSyncOperation: false);

    // Lines are updated in place since the duplication fix, so the ids the
    // claims point at are the same rows they always were.
    final after = await unpaidRowIds(orderId);
    expect(after, before, reason: 'a save no longer re-mints line ids');

    final rows = await draftRows(orderId);
    expect(rows.map((r) => r.orderProductId).toSet(), after.toSet(),
        reason: 'every claim still points at a live line');

    final reloaded = (await repo.getOrderById(orderId))!;
    final tickets = rebuild(reloaded, rows);
    expect(tickets, hasLength(2));
    expect(tickets[0].items.single.item.productId, 1);
    expect(tickets[1].items.single.item.productId, 2);
  });

  test('the division survives repeated updates, not just the first', () async {
    // Open, close, open, close — each round re-keys every row again.
    final orderId = await seedOrder();
    await saveOneTicketPerRow(orderId, await unpaidRowIds(orderId));

    for (var round = 0; round < 3; round++) {
      final order = (await repo.getOrderById(orderId))!;
      await repo.updateOrder(order, queueSyncOperation: false);
    }

    final reloaded = (await repo.getOrderById(orderId))!;
    expect(rebuild(reloaded, await draftRows(orderId)), hasLength(2));
  });

  test('a line deleted in the panel takes its claim with it', () async {
    final orderId = await seedOrder(count: 3);
    await saveOneTicketPerRow(orderId, await unpaidRowIds(orderId));

    final order = (await repo.getOrderById(orderId))!;
    final kept = order.items.where((i) => i.productId != 2).toList();
    await repo.updateOrder(order.copyWith(items: kept),
        queueSyncOperation: false);

    final rows = await draftRows(orderId);
    expect(rows, hasLength(2), reason: 'the dropped line claims nothing now');

    final reloaded = (await repo.getOrderById(orderId))!;
    final tickets = rebuild(reloaded, rows);
    expect(tickets, hasLength(2));
    expect(
      [for (final t in tickets) t.items.single.item.productId],
      [1, 3],
      reason: 'the surviving lines keep their own tickets, in order',
    );
  });

  test('a line added in the panel joins the first ticket, breaking nothing',
      () async {
    final orderId = await seedOrder();
    await saveOneTicketPerRow(orderId, await unpaidRowIds(orderId));

    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value(9),
          name: 'New',
          price: 5,
          finalPrice: 5,
        ));
    final order = (await repo.getOrderById(orderId))!;
    await repo.updateOrder(
      order.copyWith(items: [
        ...order.items,
        // No id — the cashier just added it, so it has no claim.
        OrderItem(productId: 9, productName: 'New', finalPrice: 5),
      ]),
      queueSyncOperation: false,
    );

    final reloaded = (await repo.getOrderById(orderId))!;
    final tickets = rebuild(reloaded, await draftRows(orderId));
    expect(tickets, hasLength(2));
    expect(tickets[0].items, hasLength(2),
        reason: 'the new line lands in the leftover bucket on ticket 1');
    expect(tickets[1].items, hasLength(1));
  });

  test('an order nobody divided still comes back as one ticket', () async {
    final orderId = await seedOrder();
    final order = (await repo.getOrderById(orderId))!;
    await repo.updateOrder(order, queueSyncOperation: false);

    expect(await draftRows(orderId), isEmpty);
    final reloaded = (await repo.getOrderById(orderId))!;
    expect(rebuild(reloaded, const []), hasLength(1));
  });

  test('a quantity reduced below its claim drops the excess, keeps the ticket',
      () async {
    final orderId = await seedOrder(count: 1);
    final rowId = (await unpaidRowIds(orderId)).single;
    await (db.update(db.orderProducts)..where((t) => t.id.equals(rowId)))
        .write(const OrderProductsCompanion(quantity: Value(4)));
    // Divided 2 + 2.
    for (var i = 0; i < 2; i++) {
      await db.into(db.ticketDraftSplits).insert(
            TicketDraftSplitsCompanion.insert(
              orderId: orderId,
              orderProductId: rowId,
              draftIndex: i,
              quantity: 2,
            ),
          );
    }

    final order = (await repo.getOrderById(orderId))!;
    await repo.updateOrder(
      order.copyWith(items: [order.items.single.copyWith(quantity: 3)]),
      queueSyncOperation: false,
    );

    final reloaded = (await repo.getOrderById(orderId))!;
    final tickets = rebuild(reloaded, await draftRows(orderId));
    // 2 is honoured, the second claim of 2 exceeds the 1 left and is dropped,
    // and that 1 falls through to the leftover bucket on ticket 1.
    expect(tickets, hasLength(1));
    expect(tickets.single.total, 30.0);
  });
}

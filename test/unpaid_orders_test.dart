import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/unpaid_orders_service.dart';

/// A shift change leaves live tables behind, stamped with the outgoing
/// cashier and a session that is about to be closed. Once that session is
/// closed `updateOrder` refuses to touch the order at all, so the table can be
/// neither added to nor paid. The claim that happens when the next cashier
/// pays or edits one is what unsticks it — these pin what that moves, and
/// what it deliberately leaves alone.

void main() {
  late AppDatabase db;
  late UnpaidOrdersService svc;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    svc = UnpaidOrdersService(db);
  });
  tearDown(() => db.close());

  Future<int> user(int id, String name) =>
      db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: name,
            password: 'x',
            firstName: name,
            lastName: '',
            type: 'cashier',
          ));

  Future<int> session(int id, {String status = 'active'}) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            id: Value(id),
            code: 'S$id',
            cashierId: 1,
            moneyAtStart: 0,
            status: Value(status),
          ));

  Future<int> table(int id, String name) =>
      db.into(db.areaTables).insert(AreaTablesCompanion.insert(
            id: Value(id),
            name: name,
          ));

  /// One table order worth [price], optionally part-paid.
  Future<int> tableOrder({
    required String code,
    int? tableId,
    int? takenBy,
    int? sessionId,
    double price = 100,
    double quantity = 1,
    double discountPercentage = 0,
    double paid = 0,
    String status = 'COMPLETED',
  }) async {
    final id = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: code,
          tableId: Value(tableId),
          takenBy: Value(takenBy),
          sessionId: Value(sessionId),
          status: Value(status),
          discountPercentage: Value(discountPercentage),
        ));
    await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
          orderId: id,
          productId: 1,
          quantity: Value(quantity),
          unitaryPrice: price,
        ));
    if (paid > 0) {
      await db.into(db.tickets).insert(TicketsCompanion.insert(
            num: 'T$code',
            orderId: id,
            paymentMethod: 'CASH',
            amount: paid,
            isPaid: const Value(true),
          ));
    }
    return id;
  }

  group('what is offered for handover', () {
    test('an unpaid table held by a cashier', () async {
      await user(1, 'Amina');
      await table(5, 'T5');
      await tableOrder(code: 'A1', tableId: 5, takenBy: 1);

      final open = await svc.unpaidOrders(tablesOnly: true);
      expect(open, hasLength(1));
      expect(open.single.label, 'T5');
      expect(open.single.holderName, 'Amina');
      expect(open.single.due, 100);
    });

    test('a part-paid table, showing only what is still owed', () async {
      await table(5, 'T5');
      await tableOrder(code: 'A1', tableId: 5, price: 100, paid: 40);

      final t = (await svc.unpaidOrders(tablesOnly: true)).single;
      expect(t.total, 100);
      expect(t.paid, 40);
      expect(t.due, 60, reason: 'the balance is what the next cashier takes on');
    });

    test('a settled table is not offered', () async {
      await table(5, 'T5');
      await tableOrder(code: 'A1', tableId: 5, price: 100, paid: 100);
      expect(await svc.unpaidOrders(tablesOnly: true), isEmpty);
    });

    test('a penny of rounding does not resurrect a settled table', () async {
      await table(5, 'T5');
      await tableOrder(code: 'A1', tableId: 5, price: 100, paid: 99.999);
      expect(await svc.unpaidOrders(tablesOnly: true), isEmpty);
    });

    test('a cancelled order is not a table anyone inherits', () async {
      await table(5, 'T5');
      await tableOrder(code: 'A1', tableId: 5, status: 'CANCELED');
      expect(await svc.unpaidOrders(tablesOnly: true), isEmpty);
    });

    test('an order with no table is left out — this is a table handover',
        () async {
      await tableOrder(code: 'TAKEAWAY');
      expect(await svc.unpaidOrders(tablesOnly: true), isEmpty);
    });

    test('an empty order occupying a table is a floor problem, not a handover',
        () async {
      await table(5, 'T5');
      await db.into(db.orders).insert(
            OrdersCompanion.insert(code: 'EMPTY', tableId: const Value(5)),
          );
      expect(await svc.unpaidOrders(tablesOnly: true), isEmpty);
    });

    test('the order discount is applied before anything is owed', () async {
      await table(5, 'T5');
      await tableOrder(
          code: 'A1', tableId: 5, price: 100, discountPercentage: 25);
      expect((await svc.unpaidOrders(tablesOnly: true)).single.due, 75);
    });

    test('a table stuck in a closed session is flagged as such', () async {
      await session(9, status: 'ended');
      await table(5, 'T5');
      await tableOrder(code: 'A1', tableId: 5, sessionId: 9);

      final t = (await svc.unpaidOrders(tablesOnly: true)).single;
      expect(t.sessionEnded, isTrue,
          reason: 'this is the one the cashier most needs pulled over');
      expect(t.sessionCode, 'S9');
    });

    test('a live session is not flagged', () async {
      await session(9);
      await table(5, 'T5');
      await tableOrder(code: 'A1', tableId: 5, sessionId: 9);
      expect((await svc.unpaidOrders(tablesOnly: true)).single.sessionEnded, isFalse);
    });
  });

  group('the claim itself', () {
    test('moves the holder and the session together', () async {
      await user(1, 'Amina');
      await user(2, 'Bilal');
      await session(9, status: 'ended');
      await session(10);
      await table(5, 'T5');
      final orderId =
          await tableOrder(code: 'A1', tableId: 5, takenBy: 1, sessionId: 9);

      final moved = await svc.claim(
          orderIds: [orderId], toUserId: 2, toSessionId: 10);
      expect(moved, 1);

      final row = await (db.select(db.orders)..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(row.takenBy, 2);
      expect(row.sessionId, 10,
          reason: 'the money must land where it will be counted');
      expect(row.isSynced, isFalse, reason: 'the new owner has to reach the backend');
    });

    test('a null destination session leaves the stamp alone', () async {
      // The incoming cashier is not on shift yet: ownership still moves, the
      // session follows when the order is next paid.
      await session(9);
      await table(5, 'T5');
      final orderId =
          await tableOrder(code: 'A1', tableId: 5, takenBy: 1, sessionId: 9);

      await svc.claim(orderIds: [orderId], toUserId: 2);
      final row = await (db.select(db.orders)..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(row.takenBy, 2);
      expect(row.sessionId, 9, reason: 'absent, not cleared');
    });

    test('leaves the order contents completely untouched', () async {
      await table(5, 'T5');
      final orderId = await tableOrder(
          code: 'A1', tableId: 5, takenBy: 1, price: 100, quantity: 3);
      final before = await (db.select(db.orderProducts)
            ..where((p) => p.orderId.equals(orderId)))
          .get();

      await svc.claim(orderIds: [orderId], toUserId: 2, toSessionId: null);

      final after = await (db.select(db.orderProducts)
            ..where((p) => p.orderId.equals(orderId)))
          .get();
      expect(after.map((r) => r.id), before.map((r) => r.id),
          reason: 'a handover must not re-key the lines — the draft ticket '
              'division is keyed on these ids');
      expect(after.single.quantity, 3);
    });

    test('moves several tables in one go, and reports how many', () async {
      await table(5, 'T5');
      await table(6, 'T6');
      final a = await tableOrder(code: 'A1', tableId: 5, takenBy: 1);
      final b = await tableOrder(code: 'A2', tableId: 6, takenBy: 1);

      expect(await svc.claim(orderIds: [a, b], toUserId: 2), 2);
      final rows = await db.select(db.orders).get();
      expect(rows.every((o) => o.takenBy == 2), isTrue);
    });

    test('an empty selection is a no-op, not an error', () async {
      expect(await svc.claim(orderIds: const [], toUserId: 2), 0);
    });

    test('after the handover the table is held by the new cashier', () async {
      await user(1, 'Amina');
      await user(2, 'Bilal');
      await table(5, 'T5');
      final orderId = await tableOrder(code: 'A1', tableId: 5, takenBy: 1);

      await svc.claim(orderIds: [orderId], toUserId: 2);
      expect((await svc.unpaidOrders(tablesOnly: true)).single.holderName, 'Bilal');
    });
  });

  group('the wider set, and the summary the reports read', () {
    test('a parked takeaway is unpaid money too, just not a table', () async {
      await table(5, 'T5');
      await tableOrder(code: 'SIT', tableId: 5, price: 100);
      await tableOrder(code: 'TAKE', price: 40);

      expect(await svc.unpaidOrders(tablesOnly: true), hasLength(1));
      final all = await svc.unpaidOrders();
      expect(all, hasLength(2));
      expect(all.where((e) => e.isTable), hasLength(1));
      expect(all.where((e) => !e.isTable).single.label, 'TAKE',
          reason: 'a non-table order falls back to its code for a label');
    });

    test('the summary splits tables from the rest, and totals both', () async {
      await table(5, 'T5');
      await tableOrder(code: 'SIT', tableId: 5, price: 100, paid: 30);
      await tableOrder(code: 'TAKE', price: 40);

      final s = await svc.summary();
      expect(s.tableCount, 1);
      expect(s.others, hasLength(1));
      expect(s.totalValue, 140);
      expect(s.totalPaid, 30);
      expect(s.totalDue, 110);
      expect(s.tablesDue, 70);
      expect(s.othersDue, 40);
    });

    test('indexed by table id for the floor view', () async {
      await table(5, 'T5');
      await table(6, 'T6');
      final a = await tableOrder(code: 'A', tableId: 5, price: 100);
      final b = await tableOrder(code: 'B', tableId: 6, price: 20, paid: 5);
      // The index is keyed off what the table is HOLDING, so the tables have
      // to be holding it — see the seated-order group below.
      await (db.update(db.areaTables)..where((t) => t.id.equals(5)))
          .write(AreaTablesCompanion(orderId: Value(a)));
      await (db.update(db.areaTables)..where((t) => t.id.equals(6)))
          .write(AreaTablesCompanion(orderId: Value(b)));

      final byTable = (await svc.summary(tablesOnly: true)).byTableId;
      expect(byTable.keys.toSet(), {5, 6});
      expect(byTable[6]!.due, 15);
    });

    test('a settled floor summarises to zero, not to nothing', () async {
      await table(5, 'T5');
      await tableOrder(code: 'A', tableId: 5, price: 100, paid: 100);

      final s = await svc.summary();
      expect(s.entries, isEmpty);
      expect(s.totalDue, 0);
      expect(s.count, 0);
    });
  });

  group('what the claim must never touch', () {
    test('the waiter keeps the table — servedBy is not ownership', () async {
      await table(5, 'T5');
      final orderId = await tableOrder(code: 'A1', tableId: 5, takenBy: 1);
      await (db.update(db.orders)..where((o) => o.id.equals(orderId)))
          .write(const OrdersCompanion(waiterId: Value(3)));

      await svc.claim(orderIds: [orderId], toUserId: 2);

      final row = await (db.select(db.orders)..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(row.takenBy, 2);
      expect(row.waiterId, 3,
          reason: 'the waiter keeps their attribution, settlement and tips');
    });

    test('a waiter-raised order stays waiter-raised after the claim', () async {
      await table(5, 'T5');
      final orderId = await tableOrder(code: 'A1', tableId: 5, takenBy: 1);
      await (db.update(db.orders)..where((o) => o.id.equals(orderId)))
          .write(const OrdersCompanion(source: Value('WAITER')));

      await svc.claim(orderIds: [orderId], toUserId: 2);

      final row = await (db.select(db.orders)..where((o) => o.id.equals(orderId)))
          .getSingle();
      expect(row.source, 'WAITER',
          reason: 'the cashier edit lock keys off source and must keep biting');
    });
  });

  group('a table shows the order sitting on it', () {
    /// `area_tables.order_id` is the pointer to what is actually on the
    /// table. An unpaid order that names the table but is no longer the one
    /// on it — cleared, re-seated, or simply abandoned — keeps its `tableId`
    /// forever, and summing those made a table owe far more than the people
    /// sitting at it.
    Future<void> seat(int tableId, int orderId) async {
      await (db.update(db.areaTables)..where((t) => t.id.equals(tableId)))
          .write(AreaTablesCompanion(orderId: Value(orderId)));
    }

    test('only the seated order, not every unpaid order naming the table',
        () async {
      await table(5, 'T5');
      await tableOrder(code: 'OLD', tableId: 5, price: 500);
      final current = await tableOrder(code: 'NOW', tableId: 5, price: 60);
      await seat(5, current);

      final byTable = (await svc.summary(tablesOnly: true)).byTableId;
      expect(byTable[5]!.order.code, 'NOW');
      expect(byTable[5]!.due, 60,
          reason: 'not 560 — the stray order is not on this table');
    });

    test('the stray order is still reported, just not on the table', () async {
      await table(5, 'T5');
      await tableOrder(code: 'OLD', tableId: 5, price: 500);
      final current = await tableOrder(code: 'NOW', tableId: 5, price: 60);
      await seat(5, current);

      final s = await svc.summary(tablesOnly: true);
      expect(s.entries, hasLength(2),
          reason: 'the Z sheet exists to find exactly this money');
      expect(s.seatedTables, hasLength(1));
      expect(s.seatedTables.single.order.code, 'NOW');
    });

    test('a table holding nothing has no figure at all', () async {
      await table(5, 'T5');
      await tableOrder(code: 'STRAY', tableId: 5, price: 500);

      final s = await svc.summary(tablesOnly: true);
      expect(s.byTableId, isEmpty,
          reason: 'nobody is sitting there, so the card shows no amount');
      expect(s.seatedTables, isEmpty);
      expect(s.entries, hasLength(1), reason: 'but the money is not lost');
    });

    test('the floor total is the sum of what the cards show', () async {
      await table(5, 'T5');
      await table(6, 'T6');
      await tableOrder(code: 'STRAY', tableId: 5, price: 500);
      final a = await tableOrder(code: 'A', tableId: 5, price: 100, paid: 40);
      final b = await tableOrder(code: 'B', tableId: 6, price: 25);
      await seat(5, a);
      await seat(6, b);

      final seated = (await svc.summary(tablesOnly: true)).seatedTables;
      expect(seated.fold(0.0, (s, e) => s + e.due), 85);
      expect(seated.fold(0.0, (s, e) => s + e.paid), 40);
    });
  });
}

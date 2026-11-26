import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/order_provider.dart';

/// The row-level reads the UI used to run on the database itself, now on
/// [OrderRepository]. Each pins the query it replaces, odd parts included.
void main() {
  late AppDatabase db;
  late OrderRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OrderRepository(db);
  });
  tearDown(() => db.close());

  Future<int> order(
    String code, {
    String status = 'COMPLETED',
    DateTime? createdAt,
    int? createdBy,
    int? takenBy,
  }) =>
      db.into(db.orders).insert(OrdersCompanion.insert(
            code: code,
            status: Value(status),
            createdAt:
                createdAt == null ? const Value.absent() : Value(createdAt),
            createdBy: Value(createdBy),
            takenBy: Value(takenBy),
          ));

  Future<int> line(int orderId, {String? lineUid}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            unitaryPrice: 10,
            lineUid: lineUid == null ? const Value.absent() : Value(lineUid),
          ));

  Future<int> component(int lineId, int componentId) =>
      db.into(db.orderProductComponents).insert(
          OrderProductComponentsCompanion.insert(
              orderProductId: lineId, componentId: componentId));

  group('getOrderRow', () {
    test('returns the bare row', () async {
      final id = await order('A');
      final row = await repo.getOrderRow(id);
      expect(row?.id, id);
      expect(row?.code, 'A');
    });

    test('null for an unknown id', () async {
      expect(await repo.getOrderRow(42), isNull);
    });
  });

  group('findOrderRowByCode', () {
    test('finds the order carrying the code', () async {
      await order('A');
      final b = await order('B');
      expect((await repo.findOrderRowByCode('B'))?.id, b);
    });

    test('null when no order carries it', () async {
      await order('A');
      expect(await repo.findOrderRowByCode('Z'), isNull);
    });
  });

  test('lineUidsForOrder maps every row of the order, and only it', () async {
    final a = await order('A');
    final b = await order('B');
    final l1 = await line(a, lineUid: 'UID0001');
    final l2 = await line(a, lineUid: 'UID0002');
    await line(b, lineUid: 'UID0003');

    expect(await repo.lineUidsForOrder(a), {l1: 'UID0001', l2: 'UID0002'});
    expect(await repo.lineUidsForOrder(999), isEmpty);
  });

  group('recentOrdersForNoteLink', () {
    test('newest first', () async {
      final older = await order('OLD', createdAt: DateTime(2026, 1, 1));
      final newer = await order('NEW', createdAt: DateTime(2026, 1, 2));
      expect([for (final o in await repo.recentOrdersForNoteLink()) o.id],
          [newer, older]);
    });

    test("keeps CANCELED orders: the filter spells it 'CANCELLED'", () async {
      final canceled = await order('C1', status: 'CANCELED');
      final doubleL = await order('C2', status: 'CANCELLED');
      final ids = [for (final o in await repo.recentOrdersForNoteLink()) o.id];
      expect(ids, contains(canceled));
      expect(ids, isNot(contains(doubleL)));
    });

    test('capped at the 100 newest', () async {
      final base = DateTime(2026, 1, 1);
      for (var i = 0; i < 101; i++) {
        await order('O$i', createdAt: base.add(Duration(minutes: i)));
      }
      final rows = await repo.recentOrdersForNoteLink();
      expect(rows, hasLength(100));
      expect(rows.first.code, 'O100');
      expect(rows.map((o) => o.code), isNot(contains('O0')));
    });
  });

  group('ordersCreatedBetween', () {
    final from = DateTime(2026, 3, 4);
    final to = DateTime(2026, 3, 5);

    test('from is inclusive, to exclusive', () async {
      final atStart = await order('START', createdAt: from);
      await order('BEFORE', createdAt: from.subtract(const Duration(minutes: 1)));
      await order('AT_END', createdAt: to);
      final inside =
          await order('IN', createdAt: DateTime(2026, 3, 4, 23, 59));

      final ids = {
        for (final o in await repo.ordersCreatedBetween(from, to)) o.id
      };
      expect(ids, {atStart, inside});
    });

    test('a user owns the orders they created or took', () async {
      final at = DateTime(2026, 3, 4, 12);
      final created = await order('C', createdAt: at, createdBy: 7);
      final taken = await order('T', createdAt: at, createdBy: 3, takenBy: 7);
      final takenOnly = await order('TO', createdAt: at, takenBy: 7);
      await order('OTHER', createdAt: at, createdBy: 3, takenBy: 4);
      await order('NOBODY', createdAt: at);

      final mine = {
        for (final o in await repo.ordersCreatedBetween(from, to, userId: 7))
          o.id
      };
      expect(mine, {created, taken, takenOnly});
      expect(await repo.ordersCreatedBetween(from, to), hasLength(5));
    });
  });

  test('linesOfOrder returns the order lines by id ascending', () async {
    final a = await order('A');
    final b = await order('B');
    final l1 = await line(a);
    await line(b);
    final l3 = await line(a);
    expect([for (final l in await repo.linesOfOrder(a)) l.id], [l1, l3]);
  });

  group('linesForOrders', () {
    test('lines of every listed order', () async {
      final a = await order('A');
      final b = await order('B');
      final c = await order('C');
      final la = await line(a);
      final lb = await line(b);
      await line(c);
      expect({for (final l in await repo.linesForOrders([a, b])) l.id},
          {la, lb});
    });

    test('no orders, no lines', () async {
      await line(await order('A'));
      expect(await repo.linesForOrders([]), isEmpty);
    });
  });

  group('componentsOfLines', () {
    test('components of every listed line', () async {
      final a = await order('A');
      final l1 = await line(a);
      final l2 = await line(a);
      final l3 = await line(a);
      final c1 = await component(l1, 1);
      final c2 = await component(l1, 2);
      final c3 = await component(l2, 1);
      await component(l3, 1);
      expect({for (final c in await repo.componentsOfLines([l1, l2])) c.id},
          {c1, c2, c3});
    });

    test('no lines, no components', () async {
      await component(await line(await order('A')), 1);
      expect(await repo.componentsOfLines(const <int>[]), isEmpty);
    });
  });
}

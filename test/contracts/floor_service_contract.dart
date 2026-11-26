import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/services/floor_service.dart';

/// What a [FloorService] must do, whoever implements it. The local service
/// runs these against the till's database; a hub-backed one runs the same
/// cases with a harness that seeds the hub, so both answer alike.
abstract class FloorHarness {
  FloorService get floor;

  Future<int> addTable(String name);

  /// An order holding [tableId], with one line in [lineState] — paid when
  /// [paid] — inside [sessionId] when given.
  Future<int> openOrderAt(
    int tableId, {
    String lineState = 'PENDING',
    bool paid = false,
    String status = 'COMPLETED',
    int? sessionId,
  });

  Future<int> addSession();

  /// The order [tableId] points at, or null.
  Future<int?> holderOf(int tableId);

  /// The table the order itself names.
  Future<int?> tableOfOrder(int orderId);

  Future<void> dispose();
}

void floorServiceContract(String name, Future<FloorHarness> Function() make) {
  group('$name honours the FloorService contract', () {
    late FloorHarness h;

    setUp(() async => h = await make());
    tearDown(() => h.dispose());

    test('openTable: the order a table holds, null when free', () async {
      final busy = await h.addTable('T1');
      final free = await h.addTable('T2');
      final order = await h.openOrderAt(busy);

      expect((await h.floor.openTable(busy))?.orderId, order);
      expect(await h.floor.openTable(free), isNull);
    });

    test('transfer moves the order and frees the old table', () async {
      final from = await h.addTable('T1');
      final to = await h.addTable('T2');
      final order = await h.openOrderAt(from);

      await h.floor.transfer(order, fromTableId: from, toTableId: to);

      expect(await h.holderOf(from), isNull);
      expect(await h.holderOf(to), order);
      expect(await h.tableOfOrder(order), to);
    });

    test('transfer onto a held table is refused and moves nothing', () async {
      final from = await h.addTable('T1');
      final to = await h.addTable('T2');
      final mine = await h.openOrderAt(from);
      final theirs = await h.openOrderAt(to);

      await expectLater(
          h.floor.transfer(mine, fromTableId: from, toTableId: to),
          throwsA(isA<TableOccupiedException>()));

      expect(await h.holderOf(from), mine);
      expect(await h.holderOf(to), theirs);
      expect(await h.tableOfOrder(mine), from);
    });

    test('transfer seats an order that was on no table', () async {
      final scratch = await h.addTable('T0');
      final to = await h.addTable('T2');
      final order = await h.openOrderAt(scratch);
      await h.floor.clearTable(scratch);

      await h.floor.transfer(order, toTableId: to);

      expect(await h.holderOf(to), order);
      expect(await h.tableOfOrder(order), to);
    });

    test('a waiter can move and free tables too', () async {
      final from = await h.addTable('T1');
      final to = await h.addTable('T2');
      final order = await h.openOrderAt(from);

      await h.floor.transfer(order,
          fromTableId: from, toTableId: to, by: const ByWaiter(7));
      expect(await h.holderOf(to), order);

      await h.floor.clearTable(to, by: const ByWaiter(7));
      expect(await h.holderOf(to), isNull);
    });

    test('clearTable lets go whatever the table holds', () async {
      final table = await h.addTable('T1');
      await h.openOrderAt(table);

      await h.floor.clearTable(table);

      expect(await h.holderOf(table), isNull);
    });

    test('reconcile frees cancelled orders always, paid ones only on request',
        () async {
      final cancelled = await h.addTable('T1');
      final paid = await h.addTable('T2');
      final eating = await h.addTable('T3');
      await h.openOrderAt(cancelled, status: 'CANCELED');
      await h.openOrderAt(paid, paid: true);
      final live = await h.openOrderAt(eating);

      expect(await h.floor.reconcile(freeOnPayment: false), 1);
      expect(await h.holderOf(cancelled), isNull);
      expect(await h.holderOf(paid), isNotNull,
          reason: 'a paid table stays held for the customers still sitting');

      expect(await h.floor.reconcile(freeOnPayment: true), 1);
      expect(await h.holderOf(paid), isNull);
      expect(await h.holderOf(eating), live);
    });

    test('freeTablesForSession frees only that session\'s tables', () async {
      final mine = await h.addSession();
      final other = await h.addSession();
      final t1 = await h.addTable('T1');
      final t2 = await h.addTable('T2');
      await h.openOrderAt(t1, sessionId: mine);
      final kept = await h.openOrderAt(t2, sessionId: other);

      await h.floor.freeTablesForSession(mine);

      expect(await h.holderOf(t1), isNull);
      expect(await h.holderOf(t2), kept);
    });

    test('watchTables reports a table as it changes hands', () async {
      final table = await h.addTable('T1');
      final seen = h.floor
          .watchTables()
          .map((tables) =>
              tables.firstWhere((t) => t.id == table).orderId)
          .distinct();
      final order = await h.openOrderAt(table);

      await expectLater(seen, emits(order));
    });
  });
}

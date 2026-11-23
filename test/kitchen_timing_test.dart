import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/socket_models.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/services/kitchen_board_service.dart';
import 'package:caisse212/services/kitchen_timing.dart';

/// KDS timers start when a line reaches the kitchen and the kitchen's work on
/// a line survives `updateOrder`, which deletes and re-inserts every unpaid
/// row. Before this, adding a drink to a table sent every dish on it back to
/// PENDING on the KDS and lost when cooking started.
void main() {
  late AppDatabase db;
  late OrderRepository repo;
  final t0 = DateTime(2026, 10, 9, 12, 0);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OrderRepository(db);
  });
  tearDown(() => db.close());

  OrderProduct row({
    String state = 'PENDING',
    double quantity = 1,
    DateTime? kitchenAt,
    DateTime? preparingAt,
    DateTime? kdsPrintedAt,
  }) =>
      OrderProduct(
        id: 1,
        orderId: 1,
        productId: 1,
        quantity: quantity,
        unitaryPrice: 10,
        unitaryTva: 0,
        unitaryDiscount: 0,
        manualDiscount: 0,
        cost: 0,
        state: state,
        kdsPrintedQuantity: 0,
        orderTicketPrintedQuantity: 0,
        canceledQuantity: 0,
        kitchenAt: kitchenAt,
        preparingAt: preparingAt,
        kdsPrintedAt: kdsPrintedAt,
        updatedAt: t0,
      );

  group('carriedKitchenProgress', () {
    final now = t0.add(const Duration(minutes: 30));

    test('a new line starts pending, its clock now', () {
      final p = carriedKitchenProgress(before: null, quantity: 1, now: now);
      expect(p.state, 'PENDING');
      expect(p.kitchenAt, now);
    });

    test('a line still cooking keeps its state and clocks', () {
      final p = carriedKitchenProgress(
        before: row(state: 'PREPARING', kitchenAt: t0, preparingAt: t0),
        quantity: 2,
        now: now,
      );
      expect(p.state, 'PREPARING');
      expect(p.kitchenAt, t0);
      expect(p.preparingAt, t0);
    });

    test('a finished line that grew is food nobody made: pending from now',
        () {
      final p = carriedKitchenProgress(
        before: row(state: 'COMPLETED', kitchenAt: t0),
        quantity: 2,
        now: now,
      );
      expect(p.state, 'PENDING');
      expect(p.kitchenAt, now);
      expect(p.preparingAt, isNull);
    });

    test('a finished line left alone stays finished', () {
      final p = carriedKitchenProgress(
        before: row(state: 'COMPLETED', kitchenAt: t0),
        quantity: 1,
        now: now,
      );
      expect(p.state, 'COMPLETED');
    });

    test('a line coming off hold starts its clock now', () {
      final p = carriedKitchenProgress(
        before: row(state: 'ONHOLD', kitchenAt: t0),
        quantity: 1,
        now: now,
      );
      expect(p.state, 'PENDING');
      expect(p.kitchenAt, now);
    });

    test('a pre-v61 row falls back to the kitchen print time, then the order',
        () {
      expect(
        carriedKitchenProgress(
          before: row(kdsPrintedAt: t0),
          quantity: 1,
          now: now,
        ).kitchenAt,
        t0,
      );
      final created = t0.subtract(const Duration(minutes: 5));
      expect(
        carriedKitchenProgress(
          before: row(),
          quantity: 1,
          now: now,
          orderCreatedAt: created,
        ).kitchenAt,
        created,
      );
    });
  });

  group('kitchenStageStamps', () {
    final now = t0.add(const Duration(minutes: 20));

    test('forward moves stamp each stage once', () {
      final start = kitchenStageStamps(row(), 'PREPARING', now);
      expect(start.preparingAt, Value<DateTime?>(now));
      final again =
          kitchenStageStamps(row(state: 'PREPARING', preparingAt: t0), 'PREPARING', now);
      expect(again.preparingAt.present, isFalse);
      expect(kitchenStageStamps(row(state: 'PREPARING'), 'COMPLETED', now).servedAt,
          Value<DateTime?>(now));
    });

    test('reopening restarts the clocks, so the line is not instantly late',
        () {
      final c = kitchenStageStamps(
          row(state: 'COMPLETED', kitchenAt: t0, preparingAt: t0), 'PENDING', now);
      expect(c.kitchenAt, Value<DateTime?>(now));
      expect(c.preparingAt, const Value<DateTime?>(null));
      expect(c.servedAt, const Value<DateTime?>(null));
    });

    test('PENDING to PENDING changes nothing', () {
      final c = kitchenStageStamps(row(kitchenAt: t0), 'PENDING', now);
      expect(c.kitchenAt.present, isFalse);
    });
  });

  test('updateOrder keeps the kitchen work on unchanged lines', () async {
    for (final id in [1, 2]) {
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: Value(id), name: 'P$id', price: 10, finalPrice: 10));
    }
    final orderId =
        await db.into(db.orders).insert(OrdersCompanion.insert(code: 'K1'));
    await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
          orderId: orderId,
          productId: 1,
          unitaryPrice: 10,
          state: const Value('PREPARING'),
          kitchenAt: Value(t0),
          preparingAt: Value(t0.add(const Duration(minutes: 2))),
        ));
    await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
          orderId: orderId,
          productId: 2,
          unitaryPrice: 10,
          state: const Value('COMPLETED'),
          kitchenAt: Value(t0),
        ));

    final order = (await repo.getOrderById(orderId))!;
    // The cashier adds a second P2 — already served once.
    final items = [
      for (final i in order.items)
        i.productId == 2 ? i.copyWith(quantity: 2) : i,
    ];
    await repo.updateOrder(order.copyWith(items: items),
        queueSyncOperation: false);

    final rows = await (db.select(db.orderProducts)
          ..where((t) => t.orderId.equals(orderId)))
        .get();
    final p1 = rows.singleWhere((r) => r.productId == 1);
    final p2 = rows.singleWhere((r) => r.productId == 2);
    expect(p1.state, 'PREPARING');
    expect(p1.kitchenAt, t0);
    expect(p1.preparingAt, t0.add(const Duration(minutes: 2)));
    expect(p2.state, 'PENDING');
    expect(p2.kitchenAt!.isAfter(t0), isTrue);
  });

  test('the KDS payload carries both clocks, as local ISO', () {
    final json = SocketOrderProductModel(
      id: 1,
      productId: 1,
      productName: 'P',
      quantity: 1,
      unitaryPrice: 10,
      state: 'PREPARING',
      components: const [],
      kitchenAt: t0,
      preparingAt: t0.add(const Duration(minutes: 3)),
    ).toJson();
    expect(json['kitchenAt'], '2026-10-09T12:00:00.000');
    expect(json['preparingAt'], '2026-10-09T12:03:00.000');

    final bare = SocketOrderProductModel(
      id: 1,
      productId: 1,
      productName: 'P',
      quantity: 1,
      unitaryPrice: 10,
      state: 'PENDING',
      components: const [],
    ).toJson();
    expect(bare.containsKey('kitchenAt'), isFalse);
  });

  group('kitchen board', () {
    KitchenBoardLine line(String state, DateTime at, {DateTime? done}) =>
        KitchenBoardLine(
          id: 0,
          name: 'x',
          quantity: 1,
          state: state,
          kitchenAt: at,
          doneAt: done,
        );
    KitchenBoardOrder order(int id, List<KitchenBoardLine> lines) =>
        KitchenBoardOrder(id: id, code: 'O$id', type: 'DINE_IN', lines: lines);

    test('levels: amber from 3/4 of the target, red past it', () {
      expect(kitchenLevel(const Duration(minutes: 14), 20), KitchenLevel.ok);
      expect(kitchenLevel(const Duration(minutes: 15), 20), KitchenLevel.warn);
      expect(kitchenLevel(const Duration(minutes: 20), 20), KitchenLevel.late);
      expect(kitchenLevel(const Duration(hours: 3), 0), KitchenLevel.ok);
    });

    test('open orders oldest first, then recent ready ones; stale ready gone',
        () {
      final now = t0.add(const Duration(minutes: 30));
      final view = kitchenBoardView([
        order(1, [line('PENDING', t0.add(const Duration(minutes: 20)))]),
        order(2, [line('PREPARING', t0.add(const Duration(minutes: 5)))]),
        order(3, [
          line('COMPLETED', t0, done: t0.add(const Duration(minutes: 25)))
        ]),
        order(4, [line('COMPLETED', t0, done: t0)]),
      ], now);
      expect(view.map((o) => o.id), [2, 1, 3]);
      expect(view[0].stage, KitchenStage.preparing);
      expect(view[2].stage, KitchenStage.done);
      // A ready order's clock stops when the kitchen finished it.
      expect(view[2].age(now), const Duration(minutes: 25));
    });

    test('the clock counts from the oldest line still owed', () {
      final o = order(1, [
        line('COMPLETED', t0, done: t0.add(const Duration(minutes: 8))),
        line('PENDING', t0.add(const Duration(minutes: 10))),
      ]);
      expect(o.since, t0.add(const Duration(minutes: 10)));
      expect(o.stage, KitchenStage.pending);
    });

    test('the live query groups lines per order and skips held orders',
        () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value(1), name: 'Burger', price: 10, finalPrice: 10));
      final live = await db.into(db.orders).insert(OrdersCompanion.insert(
            code: 'L1',
            sessionId: const Value(7),
            status: const Value('PENDING'),
          ));
      final held = await db.into(db.orders).insert(OrdersCompanion.insert(
            code: 'H1',
            sessionId: const Value(7),
            status: const Value('ONHOLD'),
          ));
      for (final o in [live, live, held]) {
        await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
              orderId: o,
              productId: 1,
              unitaryPrice: 10,
              kitchenAt: Value(t0),
            ));
      }

      final orders = await KitchenBoardService(db).watch(7).first;
      expect(orders, hasLength(1));
      expect(orders.single.code, 'L1');
      expect(orders.single.lines, hasLength(2));
      expect(orders.single.lines.first.name, 'Burger');
      expect(orders.single.since, t0);
    });
  });
}

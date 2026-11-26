import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/ticket_provider.dart';

/// The ticket reads and draft-split writes the payment, tickets, dashboard
/// and waiter screens used to run on the database themselves, now on
/// [TicketRepository]. Each pins the query or helper it replaces.
void main() {
  late AppDatabase db;
  late TicketRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TicketRepository(db);
  });
  tearDown(() => db.close());

  Future<int> order(String code, {double? deliveryFee}) =>
      db.into(db.orders).insert(OrdersCompanion.insert(
            code: code,
            deliveryFee: Value(deliveryFee),
          ));

  Future<int> ticket(
    int orderId, {
    bool paid = true,
    bool cancelled = false,
    DateTime? date,
  }) =>
      db.into(db.tickets).insert(TicketsCompanion.insert(
            num: 'T',
            orderId: orderId,
            paymentMethod: 'CASH',
            amount: 10,
            isPaid: Value(paid),
            isCancelled: Value(cancelled),
            date: date == null ? const Value.absent() : Value(date),
          ));

  Future<int> line(
    int orderId, {
    int? ticketId,
    int productId = 1,
    double price = 10,
    double qty = 1,
    double tva = 0,
  }) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: productId,
            unitaryPrice: price,
            quantity: Value(qty),
            unitaryTva: Value(tva),
            ticketId: Value(ticketId),
          ));

  TicketDraftSplitsCompanion slice(int orderId, int lineId, int idx, double q) =>
      TicketDraftSplitsCompanion.insert(
          orderId: orderId, orderProductId: lineId, draftIndex: idx, quantity: q);

  Future<List<TicketDraftSplit>> allSlices() =>
      db.select(db.ticketDraftSplits).get();

  group('draft split', () {
    test('draftSplitRows returns only that order\'s slices', () async {
      await db.into(db.ticketDraftSplits).insert(slice(1, 10, 0, 2));
      await db.into(db.ticketDraftSplits).insert(slice(1, 11, 1, 1.5));
      await db.into(db.ticketDraftSplits).insert(slice(2, 20, 0, 1));

      final rows = await repo.draftSplitRows(1);
      expect(
          {for (final r in rows) (r.orderProductId, r.draftIndex, r.quantity)},
          {(10, 0, 2.0), (11, 1, 1.5)});
      expect(await repo.draftSplitRows(3), isEmpty);
    });

    test('replaceDraftSplit swaps the whole set, other orders untouched',
        () async {
      await db.into(db.ticketDraftSplits).insert(slice(1, 10, 0, 2));
      await db.into(db.ticketDraftSplits).insert(slice(2, 20, 0, 1));

      await repo.replaceDraftSplit(1, [slice(1, 12, 0, 1), slice(1, 13, 1, 3)]);

      expect(
          {for (final r in await allSlices()) (r.orderId, r.orderProductId)},
          {(1, 12), (1, 13), (2, 20)});
    });

    test('replaceDraftSplit with nothing clears the order', () async {
      await db.into(db.ticketDraftSplits).insert(slice(1, 10, 0, 2));
      await repo.replaceDraftSplit(1, const []);
      expect(await allSlices(), isEmpty);
    });

    test('replaceDraftSplit is one transaction: a failed insert keeps the '
        'old set', () async {
      await db.into(db.ticketDraftSplits).insert(slice(1, 10, 0, 2));
      // No orderId: the insert violates NOT NULL.
      const broken = TicketDraftSplitsCompanion(
          orderProductId: Value(12), draftIndex: Value(0), quantity: Value(1));

      await expectLater(
          repo.replaceDraftSplit(1, [slice(1, 11, 0, 1), broken]),
          throwsA(anything));

      expect([for (final r in await allSlices()) r.orderProductId], [10]);
    });

    test('clearDraftSplit drops only that order', () async {
      await db.into(db.ticketDraftSplits).insert(slice(1, 10, 0, 2));
      await db.into(db.ticketDraftSplits).insert(slice(2, 20, 0, 1));
      await repo.clearDraftSplit(1);
      expect([for (final r in await allSlices()) r.orderId], [2]);
    });
  });

  group('ticketsForOrders', () {
    test('every ticket of the listed orders, in any state', () async {
      final a = await order('A');
      final b = await order('B');
      final c = await order('C');
      final paid = await ticket(a);
      final unpaid = await ticket(a, paid: false);
      final cancelled = await ticket(b, cancelled: true);
      await ticket(c);

      expect({for (final t in await repo.ticketsForOrders([a, b])) t.id},
          {paid, unpaid, cancelled});
    });

    test('no orders, no tickets', () async {
      await ticket(await order('A'));
      expect(await repo.ticketsForOrders([]), isEmpty);
    });
  });

  group('paidTicketsForOrders', () {
    test('paid only (cancelled ones too), newest first', () async {
      final a = await order('A');
      final b = await order('B');
      final old = await ticket(a, date: DateTime(2026, 1, 1));
      final cancelledPaid =
          await ticket(b, cancelled: true, date: DateTime(2026, 1, 3));
      final recent = await ticket(a, date: DateTime(2026, 1, 2));
      await ticket(a, paid: false, date: DateTime(2026, 1, 4));
      await ticket(await order('C'), date: DateTime(2026, 1, 5));

      expect([for (final t in await repo.paidTicketsForOrders([a, b])) t.id],
          [cancelledPaid, recent, old]);
    });

    test('capped at the 50 newest', () async {
      final a = await order('A');
      final base = DateTime(2026, 1, 1);
      for (var i = 0; i < 51; i++) {
        await ticket(a, date: base.add(Duration(minutes: i)));
      }
      final rows = await repo.paidTicketsForOrders([a]);
      expect(rows, hasLength(50));
      expect(rows.last.date, base.add(const Duration(minutes: 1)));
    });

    test('no orders, no tickets', () async {
      await ticket(await order('A'));
      expect(await repo.paidTicketsForOrders([]), isEmpty);
    });
  });

  test('linesOfTicket returns the lines the ticket paid for', () async {
    final a = await order('A');
    final t1 = await ticket(a);
    final t2 = await ticket(a);
    final l1 = await line(a, ticketId: t1);
    await line(a, ticketId: t2);
    await line(a);
    expect([for (final l in await repo.linesOfTicket(t1)) l.id], [l1]);
  });

  group('deliveryFeeForTicket', () {
    test('the fee goes to the lowest-id ticket of the order, whatever its '
        'state', () async {
      final a = await order('A', deliveryFee: 15);
      final first = await ticket(a, paid: false, cancelled: true);
      final second = await ticket(a);
      expect(await repo.deliveryFeeForTicket(a, first), 15);
      expect(await repo.deliveryFeeForTicket(a, second), isNull);
    });

    test('no fee, a zero fee, or no such order: null', () async {
      final none = await order('A');
      final zero = await order('B', deliveryFee: 0);
      final t1 = await ticket(none);
      final t2 = await ticket(zero);
      expect(await repo.deliveryFeeForTicket(none, t1), isNull);
      expect(await repo.deliveryFeeForTicket(zero, t2), isNull);
      expect(await repo.deliveryFeeForTicket(999, t1), isNull);
    });

    test('an order with no ticket yet: null', () async {
      final a = await order('A', deliveryFee: 15);
      expect(await repo.deliveryFeeForTicket(a, 1), isNull);
    });
  });

  test('tvaTotalOf sums unitaryTva x quantity over the ticket\'s lines',
      () async {
    final a = await order('A');
    final t = await ticket(a);
    await line(a, ticketId: t, tva: 2, qty: 3);
    await line(a, ticketId: t, tva: 0.5, qty: 2);
    await line(a, tva: 100);
    expect(await repo.tvaTotalOf(t), 7);
    expect(await repo.tvaTotalOf(999), 0);
  });

  test('printItemsOf builds the reprint lines, skipping vanished components',
      () async {
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'Tajine', price: 50, finalPrice: 50));
    await db.into(db.components).insert(
        ComponentsCompanion.insert(id: const Value(5), name: 'Olives'));
    final a = await order('A');
    final t = await ticket(a);
    final tajine = await line(a, ticketId: t, productId: 1, price: 50, qty: 2);
    await line(a, ticketId: t, productId: 99, price: 4, qty: 1);
    await db.into(db.orderProductComponents).insert(
        OrderProductComponentsCompanion.insert(
            orderProductId: tajine,
            componentId: 5,
            quantity: const Value(2),
            price: const Value(3),
            isSpecial: const Value(true)));
    await db.into(db.orderProductComponents).insert(
        OrderProductComponentsCompanion.insert(
            orderProductId: tajine, componentId: 404));

    expect(await repo.printItemsOf(t), [
      {
        'name': 'Tajine',
        'quantity': 2.0,
        'price': 100.0,
        'components': [
          {'name': 'Olives', 'quantity': 2, 'price': 3.0, 'isSpecial': true},
        ],
      },
      {
        'name': 'Unknown Product',
        'quantity': 1.0,
        'price': 4.0,
        'components': [],
      },
    ]);
  });
}

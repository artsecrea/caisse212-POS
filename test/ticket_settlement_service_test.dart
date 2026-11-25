import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/ticket_settlement_service.dart';

/// The one write path behind every way a till takes money: a paid ticket and
/// the lines it settles, together or not at all.
void main() {
  late AppDatabase db;
  late TicketSettlementService service;
  late int orderId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = TicketSettlementService(db);
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'P', price: 10, finalPrice: 10));
    orderId = await db.into(db.orders).insert(OrdersCompanion.insert(code: 'O1'));
  });
  tearDown(() => db.close());

  Future<int> line({double qty = 1, int? ticketId, String state = 'PENDING'}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            quantity: Value(qty),
            unitaryPrice: 10,
            ticketId: Value(ticketId),
            state: Value(state),
          ));

  Future<OrderProduct> row(int id) =>
      (db.select(db.orderProducts)..where((t) => t.id.equals(id))).getSingle();

  test('numbers continue past local and server tickets', () async {
    expect(await service.nextTicketNum(orderId), '0001');
    await service.createPaidTicket(
        orderId: orderId, paymentMethod: 'CASH', amount: 5);
    expect(await service.nextTicketNum(orderId), '0002');
    expect(await service.nextTicketNum(orderId, serverNums: ['0007']), '0008');
  });

  test('a paid ticket carries what the caller gave it', () async {
    final day = DateTime(2026, 11, 25);
    final r = await service.createPaidTicket(
      orderId: orderId,
      num: '0042',
      paymentMethod: 'CARD',
      amount: 12.5,
      sessionId: 3,
      zDay: day,
      splitDetails: '{"x":1}',
    );
    final t = await (db.select(db.tickets)..where((t) => t.id.equals(r.ticketId)))
        .getSingle();
    expect(r.num, '0042');
    expect(t.num, '0042');
    expect(t.paymentMethod, 'CARD');
    expect(t.amount, 12.5);
    expect(t.sessionId, 3);
    expect(t.zDay, day);
    expect(t.isPaid, isTrue);
    expect(t.printCount, 0);
    expect(t.splitDetails, '{"x":1}');
  });

  test('UnpaidLinesOf skips lines another ticket already carries', () async {
    final earlier = await service.createPaidTicket(
        orderId: orderId, paymentMethod: 'CASH', amount: 10);
    final paid = await line(ticketId: earlier.ticketId);
    final open = await line();
    final r = await service.createPaidTicket(
        orderId: orderId,
        paymentMethod: 'CASH',
        amount: 10,
        lines: UnpaidLinesOf(orderId));
    expect((await row(paid)).ticketId, earlier.ticketId);
    expect((await row(open)).ticketId, r.ticketId);
  });

  test('WholeRows attaches exactly the rows named', () async {
    final a = await line();
    final b = await line();
    final r = await service.createPaidTicket(
        orderId: orderId,
        paymentMethod: 'CASH',
        amount: 10,
        lines: WholeRows([a]));
    expect((await row(a)).ticketId, r.ticketId);
    expect((await row(b)).ticketId, isNull);
  });

  test('NoLines leaves every line open', () async {
    final a = await line();
    await service.createPaidTicket(
        orderId: orderId, paymentMethod: 'CASH', amount: 4);
    expect((await row(a)).ticketId, isNull);
  });

  test('a part claim cuts the paid quantity onto a new row', () async {
    final a = await line(qty: 3);
    final whole = await line(qty: 1);
    final r = await service.createPaidTicket(
      orderId: orderId,
      paymentMethod: 'CASH',
      amount: 30,
      lines: ClaimedQuantities({a: 2, whole: 1}),
      splitFromSettled: (settled) => 'rows:${settled[a]},${settled[whole]}',
    );
    final remainder = await row(a);
    expect(remainder.quantity, 1);
    expect(remainder.ticketId, isNull);
    final sliceId = r.settledRows[a]!;
    expect(sliceId, isNot(a));
    final slice = await row(sliceId);
    expect(slice.quantity, 2);
    expect(slice.ticketId, r.ticketId);
    expect(r.settledRows[whole], whole);
    expect((await row(whole)).ticketId, r.ticketId);

    final t = await (db.select(db.tickets)..where((t) => t.id.equals(r.ticketId)))
        .getSingle();
    expect(t.splitDetails, 'rows:$sliceId,$whole');
  });

  test('a failure rolls the ticket back with the lines', () async {
    final a = await line();
    await expectLater(
      service.createPaidTicket(
        orderId: orderId,
        paymentMethod: 'CASH',
        amount: 10,
        lines: WholeRows([a]),
        splitFromSettled: (_) => throw StateError('boom'),
      ),
      throwsStateError,
    );
    expect(await db.select(db.tickets).get(), isEmpty);
    expect((await row(a)).ticketId, isNull);
  });
}

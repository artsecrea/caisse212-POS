import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/cash_report_sections.dart';
import 'package:caisse212/services/session_service.dart';

/// Delivery fees are real money in the drawer.
///
/// `ticket.amount` is products-only by design — it is what every sales figure
/// is built from, and folding a fee into it would corrupt them. The
/// consequence nobody had accounted for is that the fee was in the drawer and
/// in no report at all, so a shift with deliveries counted OVER by exactly the
/// fees and the variance looked like a miscount.
///
/// A fee belongs to the ORDER and rides the FIRST settlement, so it is
/// reconstructed here from the earliest live ticket on the order — the same
/// rule a reprint uses.

void main() {
  late AppDatabase db;
  late CashReportBuilder builder;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    builder = CashReportBuilder(db);
  });
  tearDown(() => db.close());

  Future<int> session({double start = 100, double? end}) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: 'S1',
            cashierId: 1,
            moneyAtStart: start,
            moneyAtEnd: Value(end),
          ));

  Future<int> order(int sessionId,
          {double fee = 0, String code = 'ORD1', String type = 'DELIVERY'}) =>
      db.into(db.orders).insert(OrdersCompanion.insert(
            code: code,
            sessionId: Value(sessionId),
            type: Value(type),
            deliveryFee: Value(fee),
          ));

  Future<void> product() => db.into(db.products).insert(
      ProductsCompanion.insert(
          id: const Value(1), name: 'P', price: 100, finalPrice: 100));

  Future<void> line(int orderId, {double price = 100}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            quantity: const Value(1),
            unitaryPrice: price,
            state: const Value('PAID'),
          ));

  /// sessionId matters: the report scopes tickets to the session, so a ticket
  /// without one is invisible to it.
  Future<int> ticket(int orderId, int sessionId,
          {double amount = 100,
          String method = 'CASH',
          String num_ = '0001'}) =>
      db.into(db.tickets).insert(TicketsCompanion.insert(
            num: num_,
            orderId: orderId,
            paymentMethod: method,
            amount: amount,
            sessionId: Value(sessionId),
            isPaid: const Value(true),
          ));

  test('a cash delivery fee lands in expected cash', () async {
    final s = await session(start: 0);
    await product();
    final o = await order(s, fee: 20);
    await line(o);
    await ticket(o, s, amount: 100);

    final report = await builder.build(sessionIds: [s]);

    expect(report.cash.cashSales, 120.0,
        reason: '100 of products and 20 of delivery went into the drawer');
    expect(report.cash.cashDeliveryFees, 20.0);
    expect(report.cash.expectedCash, 120.0,
        reason: 'this is the figure the manager counts against — it used to '
            'say 100 and the drawer was always 20 over');
  });

  test('no fee changes nothing', () async {
    final s = await session(start: 0);
    await product();
    final o = await order(s, type: 'DINE_IN');
    await line(o);
    await ticket(o, s, amount: 100);

    final report = await builder.build(sessionIds: [s]);
    expect(report.cash.cashSales, 100.0);
    expect(report.cash.cashDeliveryFees, 0.0);
  });

  test('a fee paid by card is NOT in the drawer', () async {
    final s = await session(start: 0);
    await product();
    final o = await order(s, fee: 20);
    await line(o);
    await ticket(o, s, amount: 100, method: 'CARD');

    final report = await builder.build(sessionIds: [s]);
    expect(report.cash.cashSales, 0.0);
    expect(report.cash.cashDeliveryFees, 0.0,
        reason: 'the fee followed the card, so no cash to account for');
  });

  test('a divided bill is charged the fee once, on the first ticket',
      () async {
    final s = await session(start: 0);
    await product();
    final o = await order(s, fee: 20);
    await line(o);
    await line(o);
    await ticket(o, s, amount: 100, num_: '0001');
    await ticket(o, s, amount: 100, num_: '0002');

    final report = await builder.build(sessionIds: [s]);
    expect(report.cash.cashDeliveryFees, 20.0,
        reason: 'not 40 — an order carries one delivery charge however many '
            'ways it is split');
    expect(report.cash.cashSales, 220.0);
  });

  test('the fee follows the method of the ticket that settled first',
      () async {
    final s = await session(start: 0);
    await product();
    final o = await order(s, fee: 20);
    await line(o);
    await line(o);
    // Earliest id is the cash one, so the fee arrived as cash.
    await ticket(o, s, amount: 100, method: 'CASH', num_: '0001');
    await ticket(o, s, amount: 100, method: 'CARD', num_: '0002');

    final report = await builder.build(sessionIds: [s]);
    expect(report.cash.cashDeliveryFees, 20.0);
    expect(report.cash.cashSales, 120.0, reason: '100 cash products + 20 fee');
  });

  test('sales by type adds up to what was taken, fee included', () async {
    final s = await session(start: 0);
    await product();
    final o = await order(s, fee: 20);
    await line(o);
    await ticket(o, s, amount: 100);

    final report = await builder.build(sessionIds: [s]);
    expect(report.salesByType['DELIVERY'], 120.0,
        reason: 'the split must agree with the drawer, not with the tickets');
  });

  group('the close-session count', () {
    test('expects the delivery fee in the drawer', () async {
      final s = await session(start: 0);
      await product();
      final o = await order(s, fee: 20);
      await line(o);
      await ticket(o, s, amount: 100);

      final summary = await SessionService(db).getSessionSummary(s);

      expect(summary.totalCash, 120.0,
          reason: 'the cashier counts 120 out of the drawer');
      expect(summary.expectedCashAtEnd, 120.0,
          reason: 'this is the variance line in CloseSessionDialog — it used '
              'to say 100 and every delivery shift looked 20 over');
    });

    test('a card delivery leaves the drawer alone', () async {
      final s = await session(start: 0);
      await product();
      final o = await order(s, fee: 20);
      await line(o);
      await ticket(o, s, amount: 100, method: 'CARD');

      final summary = await SessionService(db).getSessionSummary(s);
      expect(summary.totalCash, 0.0);
      expect(summary.totalCard, 120.0, reason: 'the fee went with the card');
    });

    test('no deliveries, no change', () async {
      final s = await session(start: 0);
      await product();
      final o = await order(s, type: 'DINE_IN');
      await line(o);
      await ticket(o, s, amount: 100);

      final summary = await SessionService(db).getSessionSummary(s);
      expect(summary.expectedCashAtEnd, 100.0);
    });
  });

  test('two delivery orders both count', () async {
    final s = await session(start: 0);
    await product();
    final a = await order(s, fee: 15, code: 'A');
    await line(a);
    await ticket(a, s, amount: 100, num_: '0001');
    final b = await order(s, fee: 25, code: 'B');
    await line(b);
    await ticket(b, s, amount: 100, num_: '0002');

    final report = await builder.build(sessionIds: [s]);
    expect(report.cash.cashDeliveryFees, 40.0);
    expect(report.cash.expectedCash, 240.0);
  });
}

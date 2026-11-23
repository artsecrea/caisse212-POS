import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/cash_report_sections.dart';

/// The banded X / Z body.
///
/// This is the money maths a shop reconciles its drawer against, so the rules
/// that are easy to get subtly wrong are pinned here: what counts as gross
/// versus net, that a struck line is reported once rather than twice, that VAT
/// is backed OUT of a TTC figure rather than added to it, and that an open
/// shift reports "not counted" instead of a zero count.
void main() {
  late AppDatabase db;
  late CashReportBuilder builder;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    builder = CashReportBuilder(db);
  });
  tearDown(() => db.close());

  Future<int> session({double start = 100, double? end}) async {
    return db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
          code: 'S1',
          cashierId: 1,
          moneyAtStart: start,
          moneyAtEnd: Value(end),
        ));
  }

  Future<void> category(int id, String name) =>
      db.into(db.categories).insert(CategoriesCompanion.insert(id: Value(id), name: name));

  Future<void> station(int id, String name) =>
      db.into(db.stations).insert(StationsCompanion.insert(id: Value(id), name: name));

  Future<void> product(int id, String name,
          {int? categoryId, int? stationId, double price = 10}) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: name,
            price: price,
            finalPrice: price,
            categoryId: Value(categoryId),
            stationId: Value(stationId),
          ));

  Future<int> order(int sessionId,
      {String type = 'DINE_IN',
      int persons = 2,
      double discountPct = 0,
      int? tableId,
      String code = 'ORD1',
      String status = 'COMPLETED'}) {
    return db.into(db.orders).insert(OrdersCompanion.insert(
          code: code,
          status: Value(status),
          sessionId: Value(sessionId),
          type: Value(type),
          persons: Value(persons),
          discountPercentage: Value(discountPct),
          tableId: Value(tableId),
        ));
  }

  Future<int> line(int orderId, int productId,
      {double qty = 1,
      double price = 100,
      double vat = 0,
      double unitDiscount = 0,
      double manualDiscount = 0,
      String state = 'PAID'}) {
    return db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
          orderId: orderId,
          productId: productId,
          quantity: Value(qty),
          unitaryPrice: price,
          unitaryTva: Value(vat),
          unitaryDiscount: Value(unitDiscount),
          manualDiscount: Value(manualDiscount),
          state: Value(state),
        ));
  }

  Future<int> ticket(int orderId, int sessionId,
          {double amount = 100,
          String method = 'CASH',
          bool paid = true,
          bool cancelled = false,
          String num_ = '0001'}) =>
      db.into(db.tickets).insert(TicketsCompanion.insert(
            num: num_,
            orderId: orderId,
            paymentMethod: method,
            amount: amount,
            sessionId: Value(sessionId),
            isPaid: Value(paid),
            isCancelled: Value(cancelled),
          ));

  group('§1 general summary', () {
    test('gross is before discounts, net is after everything', () async {
      final s = await session();
      await product(1, 'Pizza');
      final o = await order(s);
      // Catalogue 100 with 10 off: the line stores finalPrice 90 and the 10.
      // 2 units -> gross 200, discount 20, net 180.
      await line(o, 1, qty: 2, price: 90, unitDiscount: 10);

      final r = await builder.build(sessionIds: [s]);
      expect(r.general.grossSales, 200);
      expect(r.general.discounts, 20);
      expect(r.general.netTotal, 180);
    });

    test('an order-level percentage applies after the per-line discount',
        () async {
      final s = await session();
      await product(1, 'Pizza');
      final o = await order(s, discountPct: 10);
      // 100 - 20 = 80 (stored as finalPrice), then 10% of 80 = 8 -> total
      // discount 28, net 72.
      await line(o, 1, price: 80, unitDiscount: 20);

      final r = await builder.build(sessionIds: [s]);
      expect(r.general.discounts, closeTo(28, 0.001));
      expect(r.general.netTotal, closeTo(72, 0.001));
    });

    test('the catalogue discount is not taken off twice', () async {
      // Regression: finalPrice already has it off, so subtracting it again
      // made net read 20 short of what the customer paid.
      final s = await session();
      await product(1, 'Pizza');
      final o = await order(s);
      await line(o, 1, price: 80, unitDiscount: 20);

      final r = await builder.build(sessionIds: [s]);
      expect(r.general.grossSales, 100);
      expect(r.general.discounts, 20);
      expect(r.general.netTotal, 80);
      expect(r.topArticles.single.amount, 80);
    });

    test('manual discount and paid options are counted', () async {
      final s = await session();
      await product(1, 'Burger');
      final o = await order(s);
      // 50 + 10 of options, 5 off by hand, 2 units -> gross 120, disc 10.
      final id = await line(o, 1, qty: 2, price: 50, manualDiscount: 5);
      await db.into(db.orderProductComponents).insert(
          OrderProductComponentsCompanion.insert(
              componentId: 1, orderProductId: id, price: const Value(10)));

      final r = await builder.build(sessionIds: [s]);
      expect(r.general.grossSales, 120);
      expect(r.general.discounts, 10);
      expect(r.general.netTotal, 110);
      expect(r.vatTotalTtc, closeTo(110, 0.001));
    });

    test('a struck line is reported once, and never as gross', () async {
      // The double-count trap: a cancelled line must land on its own §1 row
      // without also inflating gross, the VAT bands or the best sellers.
      final s = await session();
      await product(1, 'Pizza');
      final o = await order(s);
      await line(o, 1, price: 100);
      await line(o, 1, price: 40, state: 'CANCELED');

      final r = await builder.build(sessionIds: [s]);
      expect(r.general.grossSales, 100, reason: 'struck line is not gross');
      expect(r.general.cancelledLines, 40);
      expect(r.indicators.cancelledLineCount, 1);
      expect(r.topArticles.single.amount, 100,
          reason: 'struck line is not a sale');
      expect(r.general.netTotal, 100,
          reason: 'never in gross, so never taken off net');
    });

    test('a line pulled off the order counts as a cancelled line', () async {
      // A whole-line cancel deletes the row and leaves a tombstone, so the
      // report reads the tombstone, not order_products.
      final s = await session();
      await product(1, 'Pizza');
      final o = await order(s);
      await line(o, 1, price: 100);
      await db.into(db.removedOrderItems).insert(
          RemovedOrderItemsCompanion.insert(
            orderId: o,
            sessionId: Value(s),
            productId: 1,
            productName: 'Pizza',
            quantity: 2,
            unitaryPrice: const Value(30),
            amount: const Value(60),
          ));

      final r = await builder.build(sessionIds: [s]);
      expect(r.general.cancelledLines, 60);
      expect(r.indicators.cancelledLineCount, 1);
      expect(r.removedItems.lineCount, 1);
      expect(r.general.grossSales, 100);
      expect(r.general.netTotal, 100);
    });

    test('both spellings of cancelled are understood', () async {
      final s = await session();
      await product(1, 'Pizza');
      final o = await order(s);
      await line(o, 1, price: 40, state: 'CANCELLED');

      final r = await builder.build(sessionIds: [s]);
      expect(r.general.cancelledLines, 40);
    });

    test('a paid then cancelled order is shown once, never as a sale',
        () async {
      final s = await session();
      await product(1, 'Pizza');
      final o = await order(s, status: 'CANCELED');
      await line(o, 1, price: 100, vat: 10);
      await ticket(o, s, amount: 100, cancelled: true);

      final r = await builder.build(sessionIds: [s]);
      expect(r.general.cancelledTickets, 100);
      expect(r.indicators.cancelledTicketCount, 1);
      expect(r.indicators.ticketCount, 0, reason: 'a void is not a sale');
      expect(r.general.grossSales, 0);
      expect(r.general.netTotal, 0);
      expect(r.vatBands, isEmpty);
      expect(r.topArticles, isEmpty);
    });

    test('an unpaid cancelled order is left out of everything', () async {
      final s = await session();
      await product(1, 'Pizza', categoryId: null);
      final live = await order(s, code: 'A', persons: 2);
      await line(live, 1, price: 50, vat: 10);
      final dead = await order(s, code: 'B', persons: 4, status: 'CANCELED');
      await line(dead, 1, price: 80, vat: 10);

      final r = await builder.build(sessionIds: [s]);
      expect(r.general.grossSales, 50);
      expect(r.general.netTotal, 50);
      expect(r.vatBands.single.ttc, closeTo(50, 0.001));
      expect(r.topArticles.single.amount, 50);
      expect(r.families.single.amount, 50);
      expect(r.indicators.covers, 2);
    });
  });

  group('§4 VAT', () {
    test('tax is backed out of the TTC line, not added to it', () async {
      final s = await session();
      await product(1, 'Pizza');
      final o = await order(s);
      // 120 TTC at 20% -> base 100, VAT 20.
      await line(o, 1, price: 120, vat: 20);

      final r = await builder.build(sessionIds: [s]);
      final band = r.vatBands.single;
      expect(band.rate, 20);
      expect(band.baseHt, closeTo(100, 0.001));
      expect(band.vat, closeTo(20, 0.001));
      expect(band.ttc, closeTo(120, 0.001));
    });

    test('rates get their own band, highest first', () async {
      final s = await session();
      await product(1, 'Pizza');
      await product(2, 'Water');
      final o = await order(s);
      await line(o, 1, price: 120, vat: 20);
      await line(o, 2, price: 110, vat: 10);

      final r = await builder.build(sessionIds: [s]);
      expect(r.vatBands.map((b) => b.rate), [20, 10]);
      expect(r.vatTotalTtc, closeTo(230, 0.001));
    });

    test('the rate is recovered from the stored tax amount', () async {
      // unitaryTva is an amount: 60 TTC holding 10 of tax is a 20% line.
      final s = await session();
      await product(1, 'Pizza');
      final o = await order(s);
      await line(o, 1, qty: 3, price: 60, vat: 10);

      final r = await builder.build(sessionIds: [s]);
      final band = r.vatBands.single;
      expect(band.rate, 20);
      expect(band.baseHt, closeTo(150, 0.001));
      expect(band.vat, closeTo(30, 0.001));
    });

    test('a zero-rated line is all base and no tax', () async {
      final s = await session();
      await product(1, 'Bread');
      final o = await order(s);
      await line(o, 1, price: 50, vat: 0);

      final r = await builder.build(sessionIds: [s]);
      expect(r.vatBands.single.baseHt, 50);
      expect(r.vatBands.single.vat, 0);
    });
  });

  group('§5 cash movements', () {
    test('expected cash is float plus cash takings plus in minus out',
        () async {
      final s = await session(start: 500);
      await product(1, 'Pizza');
      final o = await order(s);
      await line(o, 1, price: 100);
      await ticket(o, s, amount: 100, method: 'CASH');
      await ticket(o, s, amount: 60, method: 'CARD', num_: '0002');
      await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          amount: 700, reason: 'float', direction: const Value('IN'),
          sessionId: Value(s)));
      await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          amount: 150, reason: 'supplier', direction: const Value('OUT'),
          sessionId: Value(s)));

      final r = await builder.build(sessionIds: [s]);
      // Card takings must NOT reach the drawer figure.
      expect(r.cash.cashSales, 100);
      expect(r.cash.expectedCash, 500 + 100 + 700 - 150);
    });

    test('an open shift reports no count and no variance', () async {
      // The X case. A zero count would read as a drawer short by its whole
      // contents, which is the one number nobody should print by accident.
      final s = await session(start: 500);
      await product(1, 'Pizza');
      final o = await order(s);
      await line(o, 1, price: 100);

      final r = await builder.build(sessionIds: [s]);
      expect(r.cash.countedCash, isNull);
      expect(r.cash.variance, isNull);
    });

    test('a closed shift reports the variance against what was counted',
        () async {
      final s = await session(start: 500, end: 590);
      await product(1, 'Pizza');
      final o = await order(s);
      await line(o, 1, price: 100);
      await ticket(o, s, amount: 100, method: 'CASH');

      final r = await builder.build(sessionIds: [s]);
      expect(r.cash.expectedCash, 600);
      expect(r.cash.countedCash, 590);
      expect(r.cash.variance, closeTo(-10, 0.001));
    });
  });

  group('§2 §6 §7 §8', () {
    test('sales split by order type, from live tickets only', () async {
      final s = await session();
      await product(1, 'Pizza');
      final a = await order(s, type: 'DINE_IN', code: 'A');
      final b = await order(s, type: 'DELIVERY', code: 'B');
      await line(a, 1, price: 100);
      await line(b, 1, price: 70);
      await ticket(a, s, amount: 100, num_: '0001');
      await ticket(b, s, amount: 70, num_: '0002');
      await ticket(b, s, amount: 999, cancelled: true, num_: '0003');

      final r = await builder.build(sessionIds: [s]);
      expect(r.salesByType['DINE_IN'], 100);
      expect(r.salesByType['DELIVERY'], 70);
      expect(r.indicators.netSales, 170, reason: 'the void is excluded');
      expect(r.indicators.averageTicket, closeTo(85, 0.001));
    });

    test('covers count heads, not orders', () async {
      final s = await session();
      await product(1, 'Pizza');
      await order(s, persons: 4, code: 'A').then((o) => line(o, 1));
      await order(s, persons: 2, code: 'B').then((o) => line(o, 1));

      final r = await builder.build(sessionIds: [s]);
      expect(r.indicators.covers, 6);
    });

    test('families and top articles roll up by category and product',
        () async {
      final s = await session();
      await category(1, 'Boissons');
      await category(2, 'Plats');
      await product(1, 'The', categoryId: 1);
      await product(2, 'Cafe', categoryId: 1);
      await product(3, 'Tajine', categoryId: 2);
      final o = await order(s);
      await line(o, 1, qty: 2, price: 15);
      await line(o, 2, qty: 1, price: 10);
      await line(o, 3, qty: 1, price: 80);

      final r = await builder.build(sessionIds: [s]);
      expect(r.families.map((f) => f.name), ['Plats', 'Boissons'],
          reason: 'biggest first');
      expect(r.families.first.amount, 80);
      expect(r.families.last.quantity, 3);
      expect(r.topArticles.first.name, 'Tajine');
    });

    test('a product with no category lands under Divers', () async {
      final s = await session();
      await product(1, 'Mystery');
      final o = await order(s);
      await line(o, 1, price: 10);

      final r = await builder.build(sessionIds: [s]);
      expect(r.families.single.name, 'Divers');
    });

    test('station counts are orders, not lines', () async {
      // Two lines from one order to the same station is one order for it.
      final s = await session();
      await station(1, 'Cuisine');
      await station(2, 'Bar');
      await product(1, 'Tajine', stationId: 1);
      await product(2, 'Couscous', stationId: 1);
      await product(3, 'The', stationId: 2);
      final o = await order(s);
      await line(o, 1);
      await line(o, 2);
      await line(o, 3);

      final r = await builder.build(sessionIds: [s]);
      expect(r.indicators.ordersByStation['Cuisine'], 1);
      expect(r.indicators.ordersByStation['Bar'], 1);
    });
  });

  group('edges', () {
    test('no sessions gives the empty shape rather than throwing', () async {
      final r = await builder.build(sessionIds: []);
      expect(r.general.netTotal, 0);
      expect(r.vatBands, isEmpty);
      expect(r.families, isEmpty);
    });

    test('a session with no orders still reports its drawer', () async {
      final s = await session(start: 300);
      await db.into(db.cashMovements).insert(CashMovementsCompanion.insert(
          amount: 50, reason: 'x', direction: const Value('OUT'),
          sessionId: Value(s)));

      final r = await builder.build(sessionIds: [s]);
      expect(r.general.netTotal, 0);
      expect(r.cash.openingFloat, 300);
      expect(r.cash.cashOut, 50);
      expect(r.cash.expectedCash, 250);
    });

    test('another session\'s orders never leak in', () async {
      final mine = await session();
      final theirs = await db.into(db.cashSessions).insert(
          CashSessionsCompanion.insert(
              code: 'S2', cashierId: 2, moneyAtStart: 0));
      await product(1, 'Pizza');
      await order(mine, code: 'A').then((o) => line(o, 1, price: 100));
      await order(theirs, code: 'B').then((o) => line(o, 1, price: 999));

      final r = await builder.build(sessionIds: [mine]);
      expect(r.general.grossSales, 100);
    });
  });
}

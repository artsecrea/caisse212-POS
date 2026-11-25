import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/ticket_provider.dart';

/// A reprint from the tickets screen must show the same reductions as the
/// receipt the payment screen printed. It used to take the order percentage
/// off `unitaryPrice + unitaryTva` — VAT counted twice, since the price is
/// already TTC — and left the options out.
void main() {
  late AppDatabase db;
  late TicketRepository repo;
  late int ticketId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TicketRepository(db);
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'P', price: 30, finalPrice: 25));
    final orderId =
        await db.into(db.orders).insert(OrdersCompanion.insert(code: 'O1'));
    ticketId = await db.into(db.tickets).insert(TicketsCompanion.insert(
        num: '0001', orderId: orderId, paymentMethod: 'CASH', amount: 0));
    // 2 × 25 TTC (5 catalogue discount and 1 manual off each), VAT 4.17 inside,
    // with a 3.00 option per unit.
    final line = await db.into(db.orderProducts).insert(
        OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            quantity: const Value(2),
            unitaryPrice: 25,
            unitaryDiscount: const Value(5),
            manualDiscount: const Value(1),
            unitaryTva: const Value(4.17),
            ticketId: Value(ticketId)));
    await db.into(db.orderProductComponents).insert(
        OrderProductComponentsCompanion.insert(
            componentId: 1, orderProductId: line, price: const Value(3)));
  });
  tearDown(() => db.close());

  test('line discounts alone when the order has no percentage', () async {
    expect(await repo.discountTotalOf(ticketId, 0), 12);
  });

  test('the percentage comes off what the lines cost, options included',
      () async {
    // Net = (25 + 3 - 1) × 2 = 54; 10% of it = 5.40; plus 12 of line discounts.
    expect(await repo.discountTotalOf(ticketId, 10), closeTo(17.4, 1e-9));
  });

  test('an empty ticket has nothing taken off', () async {
    expect(await repo.discountTotalOf(999, 10), 0);
  });
}

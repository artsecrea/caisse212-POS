import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/ticket_read_models.dart';
import 'package:caisse212/providers/ticket_provider.dart';

void main() {
  late AppDatabase db;
  late TicketRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TicketRepository(db);
  });
  tearDown(() => db.close());

  Future<int> order(String code, {double? fee}) =>
      db.into(db.orders).insert(OrdersCompanion.insert(
            code: code,
            deliveryFee: Value(fee),
          ));

  Future<int> ticket(int orderId, String num, double amount) =>
      db.into(db.tickets).insert(TicketsCompanion.insert(
            num: num,
            orderId: orderId,
            paymentMethod: 'CASH',
            amount: amount,
            isPaid: const Value(true),
          ));

  Future<Map<int, TicketWithDetails>> page() async {
    final (rows, _) = await repo.getTicketsPage(offset: 0, limit: 50);
    return {for (final r in rows) r.ticket.id: r};
  }

  test('the fee sits on the first ticket of the order only', () async {
    final o = await order('D1', fee: 15);
    final first = await ticket(o, '0001', 60);
    final second = await ticket(o, '0002', 40);
    final rows = await page();

    expect(rows[first]!.deliveryFee, 15);
    expect(rows[second]!.deliveryFee, 0);
    expect(rows[first]!.displayAmount(includeDeliveryFee: true), 75);
    expect(rows[first]!.displayAmount(includeDeliveryFee: false), 60);
    expect(rows[second]!.displayAmount(includeDeliveryFee: true), 40);
  });

  test('an order without a fee shows the plain amount either way', () async {
    final o = await order('T1');
    final t = await ticket(o, '0001', 50);
    final row = (await page())[t]!;
    expect(row.displayAmount(includeDeliveryFee: true), 50);
    expect(row.displayAmount(includeDeliveryFee: false), 50);
  });
}

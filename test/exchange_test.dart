import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/core/enums.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/exchange.dart';

/// Exchange arithmetic: the credit pays for the new goods first, and only the
/// difference — in whichever direction — is real money.
void main() {
  test('new goods cost more: credit fully used, customer pays the rest', () {
    final s = settleExchange(120, 150);
    expect(s.creditUsed, 120);
    expect(s.customerPays, 30);
    expect(s.paidBack, 0);
  });

  test('new goods cost less: credit partly used, the rest goes back', () {
    final s = settleExchange(200, 80);
    expect(s.creditUsed, 80);
    expect(s.customerPays, 0);
    expect(s.paidBack, 120);
  });

  test('even exchange moves no money', () {
    final s = settleExchange(99.9, 99.9);
    expect((s.creditUsed, s.customerPays, s.paidBack), (99.9, 0.0, 0.0));
  });

  test('cents are rounded, never negative', () {
    final s = settleExchange(10.005, 3.333);
    expect(s.creditUsed, 3.33);
    expect(s.paidBack, 6.68);
    expect(settleExchange(-5, 10).customerPays, 10);
  });

  test('credit is the sum of the returned lines', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.orders).insert(
        OrdersCompanion.insert(code: 'O1', status: const Value('COMPLETED')));
    final order =
        await (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();
    final d = ExchangeDraft(
      order: order,
      lines: const [
        ExchangeReturnLine(
            orderProductId: 1, name: 'A', quantity: 1, amount: 10.10, restock: true),
        ExchangeReturnLine(
            orderProductId: 2, name: 'B', quantity: 0.5, amount: 4.95, restock: false),
      ],
    );
    expect(d.credit, 15.05);
  });

  test('EXCHANGE is never offered as a way to pay', () {
    expect(TransactionType.pickable, isNot(contains(TransactionType.exchange)));
    expect(TransactionType.fromString('EXCHANGE'), TransactionType.exchange);
  });
}

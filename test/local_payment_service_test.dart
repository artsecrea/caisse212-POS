import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/services/payment_service.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/local_payment_service.dart';

import 'contracts/payment_service_contract.dart';

/// The till's own database behind [PaymentService], driven by the shared
/// contract a hub-backed service will have to pass too.
class _LocalPaymentHarness implements PaymentHarness {
  _LocalPaymentHarness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;
  var _seq = 0;

  static Future<_LocalPaymentHarness> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'P', price: 10, finalPrice: 10));
    return _LocalPaymentHarness(db, container);
  }

  @override
  PaymentService get payments => container.read(paymentServiceProvider);

  @override
  Future<({int orderId, List<int> lineIds})> orderWithLines(int lines) async {
    final orderId = await db
        .into(db.orders)
        .insert(OrdersCompanion.insert(code: 'O${++_seq}'));
    return (
      orderId: orderId,
      lineIds: [
        for (var i = 0; i < lines; i++)
          await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
              orderId: orderId, productId: 1, unitaryPrice: 10)),
      ],
    );
  }

  @override
  Future<int> paidTicket(int orderId, List<int> lineIds,
      {bool sessionEnded = false}) async {
    final session = await db.into(db.cashSessions).insert(
        CashSessionsCompanion.insert(
            code: 'S${++_seq}',
            cashierId: 1,
            moneyAtStart: 0,
            status: Value(sessionEnded ? 'ended' : 'active')));
    final ticketId = await db.into(db.tickets).insert(TicketsCompanion.insert(
        num: '0001',
        orderId: orderId,
        paymentMethod: 'CASH',
        amount: 10,
        sessionId: Value(session),
        isPaid: const Value(true),
        isSynced: const Value(true)));
    await (db.update(db.orderProducts)..where((l) => l.id.isIn(lineIds)))
        .write(OrderProductsCompanion(ticketId: Value(ticketId)));
    return ticketId;
  }

  @override
  Future<({String method, double amount, int printCount, bool isSynced})?>
      ticket(int ticketId) async {
    final t = await (db.select(db.tickets)..where((x) => x.id.equals(ticketId)))
        .getSingleOrNull();
    return t == null
        ? null
        : (
            method: t.paymentMethod,
            amount: t.amount,
            printCount: t.printCount,
            isSynced: t.isSynced,
          );
  }

  @override
  Future<int?> ticketOfLine(int lineId) async =>
      (await (db.select(db.orderProducts)..where((l) => l.id.equals(lineId)))
              .getSingle())
          .ticketId;

  @override
  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  paymentServiceContract('LocalPaymentService', _LocalPaymentHarness.create);
}

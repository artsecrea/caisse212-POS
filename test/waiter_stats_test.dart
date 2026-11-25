import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';

/// The waiter picker shows each waiter's open orders and what they still owe.
/// It skipped COMPLETED orders — which every order is from birth — so it
/// showed nothing, and it ignored every discount.
void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'P', price: 10, finalPrice: 10));
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  var seq = 0;
  Future<int> order({String status = 'COMPLETED', double pct = 0}) =>
      db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'W${++seq}',
          status: Value(status),
          waiterId: const Value(7),
          discountPercentage: Value(pct)));

  Future<int> line(int o, double price,
          {double manual = 0, int? ticketId, String state = 'PENDING'}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
          orderId: o,
          productId: 1,
          unitaryPrice: price,
          manualDiscount: Value(manual),
          ticketId: Value(ticketId),
          state: Value(state)));

  test('open orders and what they owe, after discounts', () async {
    final open = await order(pct: 10);
    await line(open, 40, manual: 4); // 36 net
    await line(open, 50, state: 'CANCELED');

    final paid = await order();
    final t = await db.into(db.tickets).insert(TicketsCompanion.insert(
        num: '0001', orderId: paid, paymentMethod: 'CASH', amount: 20));
    await line(paid, 20, ticketId: t);

    final cancelled = await order(status: 'CANCELED');
    await line(cancelled, 99);

    final stats = await container.read(waiterStatsProvider(7).future);
    expect(stats['totalOrders'], 1);
    expect(stats['unpaidTotal'] as double, closeTo(32.4, 1e-9));
  });
}

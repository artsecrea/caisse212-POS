import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/external_orders_live_provider.dart';

/// The counter view of a platform order showed a total without the options
/// and without the order percentage, so it disagreed with the till.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'P', price: 10, finalPrice: 10));
  });
  tearDown(() => db.close());

  test('options, cancelled lines and the order percentage count', () async {
    final o = await db.into(db.orders).insert(OrdersCompanion.insert(
        code: 'G1',
        source: const Value('GLOVO'),
        discountPercentage: const Value(10)));
    final a = await db.into(db.orderProducts).insert(
        OrderProductsCompanion.insert(
            orderId: o,
            productId: 1,
            quantity: const Value(2),
            unitaryPrice: 20,
            manualDiscount: const Value(1)));
    await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
        orderId: o,
        productId: 1,
        unitaryPrice: 99,
        state: const Value('CANCELED')));

    final order = await (db.select(db.orders)..where((t) => t.id.equals(o)))
        .getSingle();
    final lines = await db.select(db.orderProducts).get();
    final live = LiveExternalOrder(
      order: order,
      lines: lines,
      productNames: const {},
      componentsPerUnit: {a: 4},
    );
    // (20 + 4 - 1) × 2 = 46, less 10% = 41.40; the cancelled line is not owed.
    expect(live.total, closeTo(41.4, 1e-9));
  });
}

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';

/// The cloud gets an order percentage as extra per-unit manual discount on
/// each line, shared by what each line costs. The share used to be weighted
/// on a price with the catalogue discount taken off a second time, so the
/// cloud took off less than the till whenever a line was on promotion.
void main() {
  late AppDatabase db;
  late DataSyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sync = DataSyncService(db, ApiService(prefs), prefs);
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'P', price: 60, finalPrice: 50));
    await db.into(db.orders).insert(OrdersCompanion.insert(code: 'O1'));
  });
  tearDown(() => db.close());

  Future<int> line(double price,
          {double discount = 0, String state = 'PENDING'}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: 1,
            productId: 1,
            unitaryPrice: price,
            unitaryDiscount: Value(discount),
            state: Value(state),
          ));

  /// What the cloud will take off: each line's manual discount × quantity.
  double sentDiscount(List<Map<String, dynamic>> out) => out.fold<double>(
      0,
      (s, l) =>
          s + (l['manualDiscount'] as double) * (l['quantity'] as num).toDouble());

  test('a promotion does not shrink the order discount', () async {
    await line(50, discount: 10); // 50 already has the 10 off
    await line(50);
    final out = await sync.buildProductsListForSync(
        await db.select(db.orderProducts).get(), 10);
    // The till took 10% of 100 off.
    expect(sentDiscount(out), closeTo(10, 1e-9));
    expect(out[0]['manualDiscount'], closeTo(5, 1e-9));
    expect(out[1]['manualDiscount'], closeTo(5, 1e-9));
  });

  test('a cancelled line takes no share', () async {
    await line(50);
    await line(50, state: 'CANCELED');
    final out = await sync.buildProductsListForSync(
        await db.select(db.orderProducts).get(), 10);
    expect(out[0]['manualDiscount'], closeTo(5, 1e-9));
    expect(out[1]['manualDiscount'], 0);
  });
}

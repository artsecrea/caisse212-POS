import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/product_cost_resolver.dart';

/// Pins the per-line `cost` the POS now sends with every order product.
///
/// The value feeds server-side margin reporting, so a wrong or silently-zero
/// cost is the kind of bug that shows up as a plausible-looking number in a
/// report rather than as a crash. These run the real payload builder against a
/// real in-memory SQLite — no reimplementation of the logic under test.
void main() {
  late AppDatabase db;
  late DataSyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // ApiService is never called: buildProductsListForSync only reads the DB.
    sync = DataSyncService(db, ApiService(prefs), prefs);
  });
  tearDown(() => db.close());

  Future<void> product(int id, {double? cost}) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: 'P$id',
            price: 100,
            finalPrice: 100,
            cost: Value(cost),
          ));

  Future<void> variant(int id, int productId, {double? cost}) =>
      db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: Value(id),
            productId: productId,
            name: 'V$id',
            price: 120,
            cost: Value(cost),
          ));

  /// [cost] is the snapshot the line was rung up with. Left null to model a
  /// row written before `order_products.cost` existed.
  Future<int> line(int productId,
          {int? variantId, double qty = 1, double? cost}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: 1,
            productId: productId,
            variantId: Value(variantId),
            quantity: Value(qty),
            unitaryPrice: 100,
            cost: Value(cost),
            state: const Value('PENDING'),
          ));

  Future<List<Map<String, dynamic>>> build() async {
    final rows = await db.select(db.orderProducts).get();
    return sync.buildProductsListForSync(rows, 0);
  }

  test('a product cost is sent per unit', () async {
    await product(5, cost: 8.5);
    await line(5, qty: 3);
    final out = await build();
    expect(out.single['cost'], 8.5,
        reason: 'cost is per unit — must NOT be multiplied by quantity');
  });

  test('a variant cost beats the parent product cost', () async {
    // A large pizza costs more to make than the base product it belongs to.
    await product(5, cost: 8.5);
    await variant(31, 5, cost: 11.0);
    await line(5, variantId: 31);
    final out = await build();
    expect(out.single['cost'], 11.0);
  });

  test('falls back to the product when the variant has no cost', () async {
    await product(5, cost: 8.5);
    await variant(31, 5); // null cost
    await line(5, variantId: 31);
    final out = await build();
    expect(out.single['cost'], 8.5);
  });

  test('an unknown cost is OMITTED, never sent as 0', () async {
    // 0.0 would read as "free to make" = 100% margin on every report.
    await product(5); // no cost on file
    await line(5);
    final out = await build();
    expect(out.single.containsKey('cost'), isFalse);
  });

  test('a product missing from the catalogue omits cost instead of throwing',
      () async {
    // Possible on a line whose product was deleted server-side then reconciled
    // away locally; the order must still sync.
    await line(999);
    final out = await build();
    expect(out.single.containsKey('cost'), isFalse);
    expect(out.single['productId'], 999);
  });

  test('cost survives the order-level discount rewrite', () async {
    // The builder rewrites manualDiscount to spread an order discount; cost
    // must not be touched by that pass.
    await product(5, cost: 8.5);
    await line(5, qty: 2);
    final rows = await db.select(db.orderProducts).get();
    final out = await sync.buildProductsListForSync(rows, 50);
    expect(out.single['cost'], 8.5);
    expect(out.single['manualDiscount'], greaterThan(0));
  });

  test('each line resolves its own cost in a mixed basket', () async {
    await product(5, cost: 8.5);
    await product(6, cost: 2.25);
    await product(7); // unknown
    await line(5);
    await line(6);
    await line(7);
    final out = await build();
    final byProduct = {for (final m in out) m['productId'] as int: m};
    expect(byProduct[5]!['cost'], 8.5);
    expect(byProduct[6]!['cost'], 2.25);
    expect(byProduct[7]!.containsKey('cost'), isFalse);
  });

  group('the snapshot on the line wins over the catalogue', () {
    test('a cost change after the sale does NOT rewrite the order', () async {
      // The whole point of snapshotting. The line was sold when the product
      // cost 8.50; the supplier price later rose to 20. Syncing that order
      // must still report the margin it was sold at.
      await product(5, cost: 20.0);
      await line(5, cost: 8.5);
      final out = await build();
      expect(out.single['cost'], 8.5);
    });

    test('a variant snapshot is respected over both catalogue costs', () async {
      await product(5, cost: 20.0);
      await variant(31, 5, cost: 30.0);
      await line(5, variantId: 31, cost: 11.0);
      final out = await build();
      expect(out.single['cost'], 11.0);
    });

    test('a legacy line with no snapshot falls back to the catalogue',
        () async {
      // Rows already in the sync queue when the column was added carry null.
      // Without the fallback they would sync with no cost at all.
      await product(5, cost: 8.5);
      await line(5); // no snapshot
      final out = await build();
      expect(out.single['cost'], 8.5);
    });

    test('a legacy line with no snapshot and no catalogue cost omits it',
        () async {
      await product(5);
      await line(5);
      final out = await build();
      expect(out.single.containsKey('cost'), isFalse);
    });

    test('a zero snapshot is sent as 0, not treated as unknown', () async {
      // A genuinely free item (promo giveaway) is a real cost of 0. That must
      // survive rather than being confused with "no cost on file".
      await product(5, cost: 8.5);
      await line(5, cost: 0);
      final out = await build();
      expect(out.single['cost'], 0);
    });
  });

  group('ProductCostResolver', () {
    test('variant cost wins, product is the fallback, unknown is null',
        () async {
      await product(5, cost: 8.5);
      await variant(31, 5, cost: 11.0);
      await variant(32, 5); // no cost of its own
      await product(6);     // no cost at all
      final r = ProductCostResolver(db);

      expect(await r.resolve(productId: 5, variantId: 31), 11.0);
      expect(await r.resolve(productId: 5, variantId: 32), 8.5);
      expect(await r.resolve(productId: 5), 8.5);
      // `isNull` is ambiguous here — drift exports one too — so compare
      // against null directly.
      expect(await r.resolve(productId: 6), null);
      expect(await r.resolve(productId: 999), null,
          reason: 'a product that is not in the catalogue must not throw');
    });

    test('the memo does not leak between product/variant keys', () async {
      await product(5, cost: 8.5);
      await variant(31, 5, cost: 11.0);
      final r = ProductCostResolver(db);
      // Resolve the variant first, so a naive cache keyed on productId alone
      // would then answer 11.0 for the base product.
      expect(await r.resolve(productId: 5, variantId: 31), 11.0);
      expect(await r.resolve(productId: 5), 8.5);
    });
  });
}

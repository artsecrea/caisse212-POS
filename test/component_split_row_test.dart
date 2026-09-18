import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/component_rules.dart';
import 'package:caisse212/providers/order_provider.dart';

/// The two-row split, pinned end to end against a real SQLite.
///
/// A component whose free allowance covers only part of its quantity is stored
/// as TWO rows for the same `componentId` — the covered units at 0.00 and the
/// rest at catalogue price — rather than one row at a blended price, because
/// option prices are two-decimal and a blended average would round into a
/// total that disagrees with the printed ticket.
///
/// That only works if nothing between here and the bill collapses the pair.
/// This file exists because the waiter app now emits the split over the LAN
/// API and asserts the same contract on its own side: if one end ever starts
/// merging by `componentId`, the other end bills wrong while its own tests
/// stay green. Two things get pinned here — the schema accepts the pair, and
/// the read-back sums both halves.
void main() {
  late AppDatabase db;
  late OrderRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // No Ref: getOrderTotals only reads the DB. The audit hook is null-guarded.
    repo = OrderRepository(db);
  });
  tearDown(() => db.close());

  /// One order carrying one line at [unitaryPrice], and returns its
  /// order_product id so component rows can hang off it.
  Future<int> lineOn(String code, {double unitaryPrice = 40.0}) async {
    final orderId = await db.into(db.orders).insert(
          OrdersCompanion.insert(code: code),
        );
    return db.into(db.orderProducts).insert(
          OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            unitaryPrice: unitaryPrice,
          ),
        );
  }

  Future<void> component(int orderProductId,
          {required int componentId,
          required int quantity,
          required double price}) =>
      db.into(db.orderProductComponents).insert(
            OrderProductComponentsCompanion.insert(
              orderProductId: orderProductId,
              componentId: componentId,
              quantity: Value(quantity),
              price: Value(price),
            ),
          );

  group('the schema accepts a split pair', () {
    test('two rows for one componentId on one line both persist', () async {
      final opId = await lineOn('SPLIT1');
      // 3 units chosen, allowance covered 2.
      await component(opId, componentId: 7, quantity: 2, price: 0.0);
      await component(opId, componentId: 7, quantity: 1, price: 12.0);

      final rows = await (db.select(db.orderProductComponents)
            ..where((c) => c.orderProductId.equals(opId)))
          .get();

      // A unique index on (orderProductId, componentId) would make the second
      // insert throw or replace the first. Neither may happen.
      expect(rows.length, 2);
      expect(rows.map((r) => r.componentId).toSet(), {7});
      expect(rows.map((r) => r.price).toList()..sort(), [0.0, 12.0]);
      // Distinct primary keys — the waiter API hands each row's id back, and
      // the split halves have to stay individually addressable.
      expect(rows.map((r) => r.id).toSet().length, 2);
    });
  });

  group('read-back sums both halves', () {
    test('a covered half contributes nothing and the charged half bills',
        () async {
      final opId = await lineOn('SPLIT2', unitaryPrice: 40.0);
      await component(opId, componentId: 7, quantity: 2, price: 0.0);
      await component(opId, componentId: 7, quantity: 1, price: 12.0);

      final totals = await repo.getOrderTotals([1]);

      // 40 + (0×2) + (12×1) = 52. A loader that keyed by componentId would
      // drop one row and give either 40 or 52 depending on which it kept —
      // and 40 is the dangerous one, since it looks like a plain line.
      expect(totals[1], closeTo(52.0, 0.001));
    });

    test('the split totals the same as the single row it replaces', () async {
      // The whole point: splitting is a storage detail, not a price change.
      final splitOp = await lineOn('SPLIT3', unitaryPrice: 40.0);
      await component(splitOp, componentId: 7, quantity: 2, price: 0.0);
      await component(splitOp, componentId: 7, quantity: 1, price: 12.0);

      final plainOp = await lineOn('PLAIN3', unitaryPrice: 40.0);
      await component(plainOp, componentId: 7, quantity: 1, price: 12.0);

      final totals = await repo.getOrderTotals([1, 2]);
      expect(totals[1], closeTo(totals[2]!, 0.001));
    });

    test('options are charged per parent unit, both halves included', () async {
      final opId = await lineOn('SPLIT4', unitaryPrice: 40.0);
      await (db.update(db.orderProducts)..where((p) => p.id.equals(opId)))
          .write(const OrderProductsCompanion(quantity: Value(2.0)));
      await component(opId, componentId: 7, quantity: 2, price: 0.0);
      await component(opId, componentId: 7, quantity: 1, price: 12.0);

      final totals = await repo.getOrderTotals([1]);

      // (40 + 12) × 2, not 40×2 + 12 — an option rides every parent unit.
      expect(totals[1], closeTo(104.0, 0.001));
    });
  });

  group('the allocation that produces those rows', () {
    test('emits exactly the pair the storage layer above accepts', () {
      // Closes the loop: what allocateFreeAllowance hands out is the shape
      // the DB and the read-back were just shown to handle.
      final lines = allocateFreeAllowance(
        const [ComponentPick(componentId: 7, quantity: 3, unitPrice: 12.0)],
        2,
      );

      expect(lines.length, 2);
      expect(lines.map((l) => l.componentId).toSet(), {7});
      expect(lines.firstWhere((l) => l.isFree).quantity, 2);
      expect(lines.firstWhere((l) => !l.isFree).quantity, 1);
      expect(optionTotalPerParentUnit(lines), closeTo(12.0, 0.001));
    });
  });
}

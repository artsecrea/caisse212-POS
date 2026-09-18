import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/refund_service.dart';

/// The refund slip is the customer's proof and carries the code support asks
/// for, so what it contains matters as much as that it prints. These cover the
/// assembly step — the part that can silently produce a blank or wrong slip.
void main() {
  late AppDatabase db;
  late RefundService refunds;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    refunds = RefundService(db);
  });
  tearDown(() => db.close());

  Future<Order> order() async {
    final id = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'ORD-2026-0042',
          status: const Value('COMPLETED'),
        ));
    return (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();
  }

  Future<int> product(int id, String name) async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: Value(id),
          name: name,
          price: 90,
          finalPrice: 90,
        ));
    return id;
  }

  Future<int> line(int orderId, int productId,
          {double qty = 2, double price = 90, int? serialId}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: productId,
            quantity: Value(qty),
            unitaryPrice: price,
            serialId: Value(serialId),
            state: const Value('PENDING'),
          ));

  test('carries the code, the order code and the total', () async {
    // The code is the whole point of the slip: it is what support asks for.
    final o = await order();
    await product(5, 'Tajine');
    final l = await line(o.id, 5);
    final r = await refunds.createRefund(
        order: o,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);

    final slip = await refunds.slipFor(r);
    expect(slip.code, r.code);
    expect(slip.code, startsWith('RF-'));
    expect(slip.orderCode, 'ORD-2026-0042');
    expect(slip.method, 'CASH');
    expect(slip.total, r.totalAmount);
    expect(slip.lines.single.name, 'Tajine');
    expect(slip.lines.single.quantity, 1);
  });

  test('resolves the product name, not a bare id', () async {
    final o = await order();
    await product(7, 'Coca');
    final l = await line(o.id, 7, price: 15);
    final r = await refunds.createRefund(
        order: o,
        method: 'CARD',
        lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);

    final slip = await refunds.slipFor(r);
    expect(slip.lines.single.name, 'Coca');
  });

  test('prints the serial of a serialised unit', () async {
    // A serialised slip is the customer's proof for THAT unit, not the model.
    final o = await order();
    await product(5, 'iPhone');
    await db.into(db.serials).insert(SerialsCompanion.insert(
          id: const Value(88),
          serialNumber: 'SN-2024-0001',
          productId: 5,
        ));
    final l = await line(o.id, 5, qty: 1, serialId: 88);
    final r = await refunds.createRefund(
        order: o,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);

    final slip = await refunds.slipFor(r);
    expect(slip.lines.single.serialNumber, 'SN-2024-0001');
  });

  test('a non-serial line carries no serial', () async {
    final o = await order();
    await product(5, 'Tajine');
    final l = await line(o.id, 5);
    final r = await refunds.createRefund(
        order: o,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);
    final slip = await refunds.slipFor(r);
    expect(slip.lines.single.serialNumber, null);
  });

  test('carries the waste flag so the slip can say so', () async {
    final o = await order();
    await product(5, 'Tajine');
    final l = await line(o.id, 5);
    final r = await refunds.createRefund(
      order: o,
      method: 'CASH',
      lines: [
        RefundLineDraft(orderProductId: l, quantity: 1, restock: false)
      ],
    );
    final slip = await refunds.slipFor(r);
    expect(slip.lines.single.restock, isFalse);
  });

  test('resolves the cashier who pressed the button', () async {
    await db.into(db.users).insert(UsersCompanion.insert(
          id: const Value(7),
          username: 'sara',
          password: 'x',
          firstName: 'Sara',
          lastName: 'Amrani',
          type: 'cashier',
          permissions: const Value(''),
        ));
    final o = await order();
    await product(5, 'Tajine');
    final l = await line(o.id, 5);
    final r = await refunds.createRefund(
        order: o,
        method: 'CASH',
        refundedBy: 7,
        lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);

    final slip = await refunds.slipFor(r);
    expect(slip.cashierName, 'Sara Amrani');
  });

  test('a deleted product still prints a line rather than a blank', () async {
    // Catalogue rows get reconciled away. A slip with an empty product line is
    // worse than one naming a row number.
    final o = await order();
    await product(5, 'Ghost');
    final l = await line(o.id, 5);
    final r = await refunds.createRefund(
        order: o,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);
    await (db.delete(db.products)..where((p) => p.id.equals(5))).go();

    final slip = await refunds.slipFor(r);
    expect(slip.lines.single.name, isNotEmpty);
  });

  test('a reprint later produces the same slip', () async {
    // Built from stored rows only, so the customer's proof does not drift as
    // the catalogue changes around it.
    final o = await order();
    await product(5, 'Tajine');
    final l = await line(o.id, 5);
    final r = await refunds.createRefund(
        order: o,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);

    final first = await refunds.slipFor(r);
    final second = await refunds.slipFor(r);
    expect(second.code, first.code);
    expect(second.total, first.total);
    expect(second.refundedAt, first.refundedAt);
    expect(second.lines.length, first.lines.length);
  });

  test('each line prints its own amount, not 0.00', () async {
    // The draft leaves `amount` null so the SERVER derives it, but the slip is
    // printed locally from the stored row — a null there prints "1 x 0.00"
    // under a correct total, which reads as a bug to the customer holding it.
    final o = await order();
    await product(5, 'Tajine');
    final l = await line(o.id, 5, price: 90);
    final r = await refunds.createRefund(
        order: o,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);

    final slip = await refunds.slipFor(r);
    expect(slip.lines.single.amount, closeTo(90, 0.001));
    // And the lines must add up to the printed total.
    final sum = slip.lines.fold<double>(0, (a, b) => a + b.amount);
    expect(sum, closeTo(slip.total, 0.001));
  });

  test('a multi-line refund keeps every line', () async {
    final o = await order();
    await product(5, 'Tajine');
    await product(6, 'Coca');
    final a = await line(o.id, 5);
    final b = await line(o.id, 6, price: 15);
    final r = await refunds.createRefund(order: o, method: 'CASH', lines: [
      RefundLineDraft(orderProductId: a, quantity: 1),
      RefundLineDraft(orderProductId: b, quantity: 2),
    ]);

    final slip = await refunds.slipFor(r);
    expect(slip.lines.length, 2);
    expect(slip.lines.map((l) => l.name), containsAll(['Tajine', 'Coca']));
    expect(slip.total, closeTo(90 + 30, 0.001));
  });

  group('amount override', () {
    test('a typed amount is stored, flagged, and printed', () async {
      // The override is the one field that can hide money, so it must be
      // visible in every artefact: the row, the flag, and the paper.
      final o = await order();
      await product(5, 'Tajine');
      final l = await line(o.id, 5, price: 90);
      final r = await refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [
            RefundLineDraft(orderProductId: l, quantity: 1, amount: 50)
          ]);

      final stored = await refunds.linesForRefund(r.id);
      expect(stored.single.amount, 50);
      expect(stored.single.amountOverridden, isTrue);

      final slip = await refunds.slipFor(r);
      expect(slip.lines.single.amount, 50);
      expect(slip.total, 50);
    });

    test('a derived amount is stored but NOT flagged as overridden', () async {
      // The flag is what keeps `amount` off the wire, so that the server does
      // its own derivation. Getting this backwards would risk a 400 on any
      // discounted order.
      final o = await order();
      await product(5, 'Tajine');
      final l = await line(o.id, 5, price: 90);
      final r = await refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);

      final stored = await refunds.linesForRefund(r.id);
      expect(stored.single.amountOverridden, isFalse);
      expect(stored.single.amount, closeTo(90, 0.001),
          reason: 'still stored locally, for the slip');
    });
  });
}

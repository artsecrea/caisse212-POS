import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_money.dart';

/// The order total used to be written out in each file that needed it. These
/// tests pin the shared formula to every one of those copies, verbatim, so
/// moving a caller onto it cannot change what the till charges. The copies
/// group the same terms differently, so they agree to the last few bits of a
/// double, not bit for bit — 1e-9 is far below a cent.
void main() {
  final rnd = Random(212);
  double money(double max) => (rnd.nextDouble() * max * 100).roundToDouble() / 100;

  List<LineAmounts> randomLines() => List.generate(1 + rnd.nextInt(6), (_) {
        final price = money(150);
        return LineAmounts(
          unitPrice: price,
          quantity: (1 + rnd.nextInt(5)).toDouble() / (rnd.nextBool() ? 1 : 4),
          componentsPerUnit: rnd.nextBool() ? money(20) : 0,
          manualDiscount: rnd.nextInt(4) == 0 ? money(price / 2) : 0,
          unitDiscount: rnd.nextInt(3) == 0 ? money(10) : 0,
          unitTva: money(price / 5),
        );
      });

  double pct() => [0.0, 5.0, 10.0, 12.5, 15.0, 33.3, 100.0][rnd.nextInt(7)];

  const eps = 1e-9;

  test('line net matches every former copy', () {
    for (var i = 0; i < 2000; i++) {
      for (final l in randomLines()) {
        final up = l.unitPrice, c = l.componentsPerUnit;
        final md = l.manualDiscount, ud = l.unitDiscount, tva = l.unitTva;
        final q = l.quantity;
        // OrderItem.totalPrice, getOrderTotals, server _waiterLineTotal,
        // WaiterLineMoney.
        expect(l.net, closeTo(((up + c) - md) * q, eps));
        // dashboard opLineTotal, unpaid_orders_service, daily summary.
        expect(l.net, closeTo(((up - md) + c) * q, eps));
        // _buildOrderFullDetailsBatch / daily summary breakdown.
        final productDiscount = (ud + md) * q;
        final itemSubtotal = (up - tva + ud + c) * q;
        expect(l.net, closeTo(itemSubtotal + tva * q - productDiscount, eps));
        // LineMoney (gross - discount, no order share).
        expect(l.gross - l.lineDiscount,
            closeTo((up + ud + c) * q - (ud + md) * q, eps));
        expect(l.unitSubtotalHt, closeTo(((up - tva) + ud) + c, eps));
      }
    }
  });

  test('order total matches every former copy', () {
    for (var i = 0; i < 2000; i++) {
      final lines = randomLines();
      final p = pct();
      final before = lines.fold<double>(0, (s, l) => s + l.net);
      final total = applyOrderDiscount(before, p);
      // CurrentOrder.total
      expect(total, closeTo(before - before * (p / 100), eps));
      // getOrderTotals
      expect(total, closeTo(before - (before * p / 100), eps));
      // dashboard, main_screen quick pay, daily summary orders list
      expect(total, closeTo(before * (1 - p / 100), eps));
      // _buildOrderFullDetailsBatch / TicketData breakdown
      final subtotal = lines.fold<double>(0, (s, l) => s + l.unitSubtotalHt * l.quantity);
      final tva = lines.fold<double>(0, (s, l) => s + l.tva);
      final itemDiscount = lines.fold<double>(0, (s, l) => s + l.lineDiscount);
      final manual = (subtotal + tva - itemDiscount) * (p / 100);
      expect(total, closeTo(subtotal + tva - (itemDiscount + manual), 1e-8));
      expect(orderDiscountAmount(before, p), closeTo(manual, 1e-8));
    }
  });

  test('a worked example a person can check', () {
    // 2 × 25.00 with a 3.00 option and 1.00 off each, then 10% off the order.
    const line = LineAmounts(
      unitPrice: 25,
      quantity: 2,
      componentsPerUnit: 3,
      manualDiscount: 1,
      unitDiscount: 5,
      unitTva: 25 / 6,
    );
    expect(line.net, 54);
    expect(line.gross, 66);
    expect(line.lineDiscount, 12);
    expect(applyOrderDiscount(line.net, 10), closeTo(48.6, 1e-12));
    expect(orderDiscountAmount(line.net, 10), closeTo(5.4, 1e-12));
  });
}

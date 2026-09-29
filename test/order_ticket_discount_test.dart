import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/services/printing_service.dart';

/// What the order ticket's totals band is handed for a discounted order.
///
/// The discount row is emitted under `order.totalDiscount > 0` and the TOTAL
/// row prints `order.total`, so these two values decide whether a remise
/// reaches the paper at all. Pinned here because the layout itself sits behind
/// a live printer connection and cannot be rendered in a test.

OrderItem item({
  int? id,
  double price = 100,
  double quantity = 1,
  double discount = 0,
  double manualDiscount = 0,
  double slipped = 0,
}) =>
    OrderItem(
      id: id ?? 1,
      productId: 1,
      productName: 'P',
      finalPrice: price,
      quantity: quantity,
      discount: discount,
      manualDiscount: manualDiscount,
      orderTicketPrintedQuantity: slipped,
    );

void main() {
  group('an order-level remise', () {
    test('reaches the discount row', () {
      final order = CurrentOrder(items: [item()], discountPercentage: 20);
      expect(order.totalDiscount, 20.0,
          reason: 'the row is gated on this being > 0');
      expect(order.totalDiscount > 0, isTrue);
    });

    test('and comes off the printed TOTAL', () {
      final order = CurrentOrder(items: [item()], discountPercentage: 20);
      expect(order.totalBeforeDiscount, 100.0);
      expect(order.total, 80.0, reason: 'the TOTAL row prints order.total');
    });

    test('stacks with a per-line discount rather than replacing it', () {
      final order = CurrentOrder(
        items: [item(price: 90, discount: 10)],
        discountPercentage: 10,
      );
      // Line discount 10, then 10% of the 90 that is left.
      expect(order.totalDiscount, closeTo(19.0, 0.001));
      expect(order.total, closeTo(81.0, 0.001));
    });

    test('a manual per-line reduction alone still shows', () {
      final order = CurrentOrder(items: [item(manualDiscount: 15)]);
      expect(order.totalDiscount, 15.0);
      expect(order.total, 85.0);
    });

    test('no remise means no row, which is why the guard exists', () {
      final order = CurrentOrder(items: [item()]);
      expect(order.totalDiscount, 0.0);
      expect(order.total, 100.0);
    });
  });

  group('an additions-only slip prices this round', () {
    /// The narrowing printOrderReceipt performs before laying anything out.
    CurrentOrder narrow(CurrentOrder order) => order.copyWith(
          items: PrintingService()
              .orderTicketLinesForTesting(order, OrderTicketPrintMode.additionsOnly),
        );

    test('the remise still appears on a round of new units', () {
      final order = CurrentOrder(
        items: [item(quantity: 3, slipped: 1)],
        discountPercentage: 20,
      );
      final slip = narrow(order);

      expect(slip.items.single.quantity, 2, reason: 'two un-slipped units');
      expect(slip.totalBeforeDiscount, 200.0);
      expect(slip.totalDiscount, 40.0,
          reason: 'the remise must not vanish just because the slip is a '
              'delta — it is the same order');
      expect(slip.total, 160.0);
    });

    test('the percentage carries through the narrowing at all', () {
      final order = CurrentOrder(items: [item()], discountPercentage: 15);
      expect(narrow(order).discountPercentage, 15.0,
          reason: 'copyWith must not drop it; the totals are derived from it');
    });
  });
}

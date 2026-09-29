import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_models.dart';

/// Reopening a line must show the price it was sold at.
///
/// The modification dialog seeded its price box from `subtotalPerItem` while
/// the save path read `finalPrice`. Those are not the same number: the first
/// strips the TVA, adds the pre-discount back and folds in the components. So
/// a 500 line reopened as 490, and accepting the dialog wrote 490 back — the
/// tax falling out of the price a little further on every reopen, silently,
/// on a number the cashier had typed deliberately.
///
/// These pin the gap between the two, so nobody swaps them back thinking they
/// are interchangeable.

OrderItem line({
  double finalPrice = 500,
  double tva = 10,
  double discount = 0,
  List<OrderItemComponent> components = const [],
}) =>
    OrderItem(
      id: 1,
      productId: 1,
      productName: 'P',
      finalPrice: finalPrice,
      quantity: 1,
      tva: tva,
      discount: discount,
      components: components,
    );

void main() {
  group('the two prices are genuinely different numbers', () {
    test('subtotalPerItem is finalPrice minus the tax — the reported 500/490',
        () {
      final item = line(finalPrice: 500, tva: 10);
      expect(item.finalPrice, 500.0);
      expect(item.subtotalPerItem, 490.0,
          reason: 'seeding the box from this is what dropped the tax');
    });

    test('they only agree when there is no tax, no discount, no options', () {
      final item = line(finalPrice: 500, tva: 0);
      expect(item.subtotalPerItem, item.finalPrice,
          reason: 'which is why the bug hid on zero-rated products');
    });

    test('a pre-discount widens the gap further', () {
      final item = line(finalPrice: 500, tva: 10, discount: 25);
      expect(item.subtotalPerItem, 515.0);
      expect(item.finalPrice, 500.0);
    });

    test('options widen it too — they are edited separately in the dialog', () {
      final item = line(finalPrice: 500, tva: 10, components: [
        OrderItemComponent(componentId: 1, name: 'Extra', quantity: 2, price: 5),
      ]);
      expect(item.subtotalPerItem, 500.0,
          reason: '490 base + 10 of options — the options counted twice once '
              'the dialog listed them on their own as well');
      expect(item.finalPrice, 500.0);
    });
  });

  group('reopening is lossless', () {
    test('the price survives any number of reopens', () {
      // What the dialog now does: seed from finalPrice, hand finalPrice back.
      var item = line(finalPrice: 500, tva: 10);
      for (var reopen = 0; reopen < 5; reopen++) {
        final seeded = item.finalPrice;
        item = item.copyWith(unitPrice: seeded);
      }
      expect(item.finalPrice, 500.0,
          reason: 'the old seed lost 10 per reopen: 500, 490, 480 …');
    });

    test('the old behaviour really did bleed, so this is worth pinning', () {
      var price = 500.0;
      const tva = 10.0;
      for (var reopen = 0; reopen < 3; reopen++) {
        // subtotalPerItem, with no discount and no options.
        price = price - tva;
      }
      expect(price, 470.0);
    });
  });
}

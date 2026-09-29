import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_models.dart';

/// Whether tapping another table should stop and ask.
///
/// It used to ask whenever the panel had any lines at all, which meant a
/// cashier walking from one saved table to another was nagged about
/// "discarding" an order that was never at risk — it stays on its own table
/// either way. The question is not "is there anything here" but "would moving
/// lose anything".

OrderItem line({int? id, double quantity = 1, double? savedQuantity}) =>
    OrderItem(
      id: id,
      productId: 1,
      productName: 'P',
      finalPrice: 10,
      quantity: quantity,
      savedQuantity: savedQuantity,
    );

void main() {
  group('a cart that was never saved', () {
    test('is unsaved the moment anything is on it', () {
      expect(CurrentOrder(items: [line()]).hasUnsavedChanges, isTrue);
    });

    test('an empty one has nothing to lose', () {
      expect(CurrentOrder().hasUnsavedChanges, isFalse);
    });
  });

  group('a saved order', () {
    test('is NOT unsaved just because it has lines — the old false alarm', () {
      final order = CurrentOrder(
        orderId: 7,
        items: [line(id: 1, quantity: 2, savedQuantity: 2)],
      );
      expect(order.hasUnsavedChanges, isFalse,
          reason: 'walking to another table leaves it exactly where it is');
    });

    test('a line added but not yet persisted counts', () {
      final order = CurrentOrder(orderId: 7, items: [
        line(id: 1, quantity: 1, savedQuantity: 1),
        line(), // no id — rung up this session, never written
      ]);
      expect(order.hasUnsavedChanges, isTrue);
    });

    test('a quantity moved since load counts', () {
      final order = CurrentOrder(
        orderId: 7,
        items: [line(id: 1, quantity: 3, savedQuantity: 1)],
      );
      expect(order.hasUnsavedChanges, isTrue);
    });

    test('a quantity reduced since load counts too', () {
      final order = CurrentOrder(
        orderId: 7,
        items: [line(id: 1, quantity: 1, savedQuantity: 3)],
      );
      expect(order.hasUnsavedChanges, isTrue);
    });

    test('floating-point noise is not a change', () {
      final order = CurrentOrder(
        orderId: 7,
        items: [line(id: 1, quantity: 0.30000000000000004, savedQuantity: 0.3)],
      );
      expect(order.hasUnsavedChanges, isFalse,
          reason: 'a weighed line must not nag on every table tap');
    });

    test('an emptied saved order has nothing pending', () {
      expect(CurrentOrder(orderId: 7).hasUnsavedChanges, isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/presentation/widgets/manual_discount_dialog.dart';
import 'package:caisse212/services/printing_service.dart';

/// Entering a reduction as money, and the kitchen ticket's day stamp.
///
/// The order stores a PERCENTAGE — `discountAmount` is derived from
/// `totalBeforeDiscount * (pct / 100)` — so an amount the cashier types has to
/// be converted before it can be saved, and the conversion has to survive a
/// round trip or the figure they typed is not the figure the customer gets.

void main() {
  group('amount → percentage', () {
    test('the ordinary case', () {
      expect(percentageForAmount(50, 500), 10.0);
      expect(percentageForAmount(125, 500), 25.0);
    });

    test('the whole order is 100%, not more', () {
      expect(percentageForAmount(500, 500), 100.0);
    });

    test('more than the order is clamped, never negative-total', () {
      expect(percentageForAmount(600, 500), 100.0,
          reason: 'the dialog refuses this outright, but the maths must not '
              'hand back something that writes a negative total');
    });

    test('nothing typed is no discount', () {
      expect(percentageForAmount(0, 500), 0.0);
      expect(percentageForAmount(-10, 500), 0.0);
    });

    test('an empty cart has no percentage that means anything', () {
      expect(percentageForAmount(50, 0), 0.0,
          reason: 'and crucially does not divide by zero');
      expect(percentageForAmount(50, -5), 0.0);
    });

    test('an awkward division still lands on the right money', () {
      // 33.33 off 99.99 is not a round percentage.
      final pct = percentageForAmount(33.33, 99.99);
      expect(amountForPercentage(pct, 99.99), closeTo(33.33, 0.001));
    });
  });

  group('percentage → amount', () {
    test('the inverse holds', () {
      expect(amountForPercentage(10, 500), 50.0);
      expect(amountForPercentage(100, 500), 500.0);
    });

    test('zero and empty are zero', () {
      expect(amountForPercentage(0, 500), 0.0);
      expect(amountForPercentage(10, 0), 0.0);
    });

    test('a round trip keeps the money the cashier typed', () {
      for (final amount in [1.0, 7.5, 49.99, 250.0, 499.99]) {
        final pct = percentageForAmount(amount, 500);
        expect(amountForPercentage(pct, 500), closeTo(amount, 0.001),
            reason: 'typing $amount must still take $amount off');
      }
    });
  });

  group('the kitchen ticket stamp', () {
    String stamp(DateTime dt) => PrintingService().kdsStampForTesting(dt);

    test('is day and time, no year and no seconds', () {
      expect(stamp(DateTime(2026, 9, 19, 14, 32, 57)), '19/09 14:32');
    });

    test('pads every part, so the column never shifts', () {
      expect(stamp(DateTime(2026, 1, 5, 9, 7)), '05/01 09:07');
    });

    test('midnight reads as 00:00, not 24:00 or blank', () {
      expect(stamp(DateTime(2026, 12, 31, 0, 0)), '31/12 00:00');
    });

    test('the afternoon is 24-hour — a kitchen does not read am/pm', () {
      expect(stamp(DateTime(2026, 7, 4, 23, 59)), '04/07 23:59');
    });
  });
}

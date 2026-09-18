import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/services/session_service.dart';

/// When a session does not balance — the drawer is short or over, or orders
/// are still unpaid on the floor — closing it can be made a supervised
/// moment. Off by default, because that is what every till already does: the
/// cashier closes and the difference is reported on the X.

void main() {
  bool needs({
    bool enabled = true,
    double? counted = 100,
    double expected = 100,
    bool unpaid = false,
  }) =>
      closeNeedsSignOff(
        featureEnabled: enabled,
        countedCash: counted,
        expectedCash: expected,
        hasUnpaidOrders: unpaid,
      );

  group('off by default, and off means off', () {
    test('a short drawer closes freely when the feature is off', () {
      expect(needs(enabled: false, counted: 40), isFalse);
    });

    test('so do unpaid orders', () {
      expect(needs(enabled: false, unpaid: true), isFalse);
    });

    test('so does a drawer nobody counted', () {
      expect(needs(enabled: false, counted: null), isFalse);
    });
  });

  group('what counts as unbalanced', () {
    test('a short drawer', () {
      expect(needs(counted: 40), isTrue);
    });

    test('an over drawer — a surplus is a discrepancy too', () {
      expect(needs(counted: 160), isTrue);
    });

    test('orders still unpaid, even with the drawer exact', () {
      expect(needs(unpaid: true), isTrue);
    });

    test('a blank count is not a clean close', () {
      // The dialog pre-fills the expected figure, so a null here means the
      // cashier deliberately cleared it — nobody counted the drawer, so
      // nobody can say it balances.
      expect(needs(counted: null), isTrue);
    });
  });

  group('what does not', () {
    test('an exact count with nothing owed', () {
      expect(needs(), isFalse);
    });

    test('a rounding penny is not an ecart', () {
      // Summing floats over a shift drifts; summoning a manager for a
      // thousandth of a dinar would make the feature unusable.
      expect(needs(counted: 100.004), isFalse);
      expect(needs(counted: 99.996), isFalse);
    });

    test('but a centime over the tolerance is', () {
      expect(needs(counted: 100.02), isTrue);
    });

    test('zero expected and zero counted balances', () {
      expect(needs(counted: 0, expected: 0), isFalse);
    });
  });
}

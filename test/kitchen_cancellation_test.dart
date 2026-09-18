import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_models.dart';

/// What the kitchen was told to make and no longer has to.
///
/// The arithmetic decides whether a printer fires, so it is worth pinning on
/// its own: printing too little means somebody plates a dish nobody will pay
/// for, and printing too much trains the pass to ignore the paper — which
/// costs the feature its whole value.

void main() {
  group('a line reduced', () {
    test('three sent, one left — two are cancelled', () {
      expect(cancelledQuantity(sent: 3, remaining: 1), 2);
    });

    test('three sent, none left — all three are cancelled', () {
      expect(cancelledQuantity(sent: 3, remaining: 0), 3);
    });
  });

  group('nothing to tell the kitchen', () {
    test('never sent — the kitchen never knew, so it needs no ticket', () {
      // The case that keeps this feature credible: ringing an item up and
      // pulling it before Continue must print nothing at all.
      expect(cancelledQuantity(sent: 0, remaining: 0), 0);
      expect(cancelledQuantity(sent: 0, remaining: 5), 0);
    });

    test('nothing was removed', () {
      expect(cancelledQuantity(sent: 2, remaining: 2), 0);
    });

    test('the line grew — an addition is not a cancellation', () {
      // Two sent, five on the order now: the extra three are the SEND path's
      // business, and must not come out as a negative void.
      expect(cancelledQuantity(sent: 2, remaining: 5), 0);
    });
  });

  group('weighed goods', () {
    test('a fractional reduction is cancelled', () {
      expect(cancelledQuantity(sent: 1.5, remaining: 0.5), closeTo(1.0, 1e-9));
    });

    test('a float wobble is not a cancellation', () {
      // 0.3+0.3+0.3 != 0.9 in binary. Without the epsilon every weighed line
      // would void a phantom fraction on every save.
      expect(cancelledQuantity(sent: 0.3 + 0.3 + 0.3, remaining: 0.9), 0);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/component_rules.dart';
import 'package:caisse212/domain/models/order_models.dart';

/// Charge-on-removal.
///
/// Some defaults are priced into the product, so taking one off is a
/// preference rather than a discount: "no cheese" costs what cheese costs.
/// The server does the charging; the POS has to say the default was removed
/// and quote the same number the server will bill. Both halves are easy to get
/// silently wrong — a removal that bills nothing, or a cart that quotes less
/// than the receipt.

RemovalCandidate candidate({
  int defaultQuantity = 1,
  int selectedQuantity = 0,
  double unitPrice = 2.0,
  bool chargeOnRemoval = true,
}) =>
    RemovalCandidate(
      componentId: 30,
      defaultQuantity: defaultQuantity,
      selectedQuantity: selectedQuantity,
      unitPrice: unitPrice,
      chargeOnRemoval: chargeOnRemoval,
    );

void main() {
  group('when a removal is charged', () {
    test('taking off a flagged default costs its price', () {
      final c = candidate();
      expect(c.deficit, 1);
      expect(c.charge, 2.0);
      expect(c.isCharged, isTrue);
    });

    test('an unflagged default is still a discount', () {
      // The overwhelming majority of links. Nothing about them changes.
      final c = candidate(chargeOnRemoval: false);
      expect(c.deficit, 0);
      expect(c.charge, 0.0);
      expect(c.needsExplicitRow, isFalse);
    });

    test('keeping the default costs nothing', () {
      expect(candidate(selectedQuantity: 1).charge, 0.0);
    });

    test('asking for extra is not a removal', () {
      // Two cheese on a one-cheese burger: the extra is priced by the normal
      // option path, and the deficit must not go negative and credit anyone.
      final c = candidate(selectedQuantity: 2);
      expect(c.deficit, 0);
      expect(c.charge, 0.0);
    });

    test('a partial removal charges only what was taken', () {
      // Comes with two, customer keeps one.
      final c = candidate(defaultQuantity: 2, selectedQuantity: 1);
      expect(c.deficit, 1);
      expect(c.charge, 2.0);
    });

    test('a component with no default cannot be removed', () {
      // Nothing was included, so nothing was taken away.
      final c = candidate(defaultQuantity: 0);
      expect(c.deficit, 0);
      expect(c.needsExplicitRow, isFalse);
    });
  });

  group('saying it out loud', () {
    test('a flagged default always needs its row sent', () {
      // A ticket that omits the row bills nothing — that is what protects
      // imported orders and older builds, and what makes silence unusable
      // here.
      expect(candidate().needsExplicitRow, isTrue);
      expect(candidate(selectedQuantity: 1).needsExplicitRow, isTrue,
          reason: 'still explicit even when nothing was removed');
    });
  });

  group('the money', () {
    test('several removals add up', () {
      expect(
          removalChargePerParentUnit([
            candidate(unitPrice: 2.0),
            candidate(unitPrice: 1.5),
          ]),
          3.5);
    });

    test('nothing removed, nothing owed', () {
      expect(
          removalChargePerParentUnit(
              [candidate(selectedQuantity: 1), candidate(chargeOnRemoval: false)]),
          0.0);
    });

    test('it is charged per parent unit, like every other option', () {
      // Two burgers with the cheese off pay for the cheese twice. The local
      // money row carries the deficit as its quantity, so the line maths that
      // already exists gets this right without a special case.
      final line = OrderItem(
        productId: 1,
        productName: 'Burger',
        finalPrice: 50.0,
        quantity: 2,
        components: [
          OrderItemComponent(
              componentId: 30, name: 'Cheese', quantity: 0, price: 0.0),
          OrderItemComponent(
              componentId: 30,
              name: 'Cheese',
              quantity: 1,
              price: 2.0,
              removalCharge: true),
        ],
      );
      expect(line.componentTotal, 2.0);
      expect(line.totalPrice, 104.0, reason: '(50 + 2) * 2');
    });

    test('the zero-quantity signal row adds nothing to the price', () {
      final line = OrderItem(
        productId: 1,
        productName: 'Burger',
        finalPrice: 50.0,
        components: [
          OrderItemComponent(
              componentId: 30, name: 'Cheese', quantity: 0, price: 0.0),
        ],
      );
      expect(line.componentTotal, 0.0);
      expect(line.totalPrice, 50.0);
    });
  });

  group('the rows a removal puts on the line', () {
    test('a full removal sends the signal and carries the money', () {
      final rows = removalRowsFor(candidate());
      expect(rows.length, 2);
      final signal = rows.firstWhere((r) => !r.removalCharge);
      final money = rows.firstWhere((r) => r.removalCharge);
      expect(signal.quantity, 0, reason: 'the explicit zero the server reads');
      expect(money.quantity, 1);
      expect(money.price, 2.0);
    });

    test('a partial removal adds NO signal row of its own', () {
      // The trap: the component is already on the line at the kept quantity,
      // and that row is a SERVED option. A second, zero-priced row for the
      // same component would have the kept unit bill nothing while the server
      // adds only the deficit — undercharging by exactly one unit.
      final rows = removalRowsFor(candidate(defaultQuantity: 2, selectedQuantity: 1));
      expect(rows.length, 1);
      expect(rows.single.removalCharge, isTrue);
      expect(rows.single.quantity, 1);
      expect(rows.single.price, 2.0);
    });

    test('a zero price never travels with a kept quantity', () {
      // The invariant, over every shape a removal can take.
      for (var defaultQty = 1; defaultQty <= 3; defaultQty++) {
        for (var kept = 0; kept <= defaultQty; kept++) {
          final rows = removalRowsFor(
              candidate(defaultQuantity: defaultQty, selectedQuantity: kept));
          for (final r in rows) {
            if (r.price == 0.0) {
              expect(r.quantity, 0,
                  reason: 'default $defaultQty, kept $kept');
            }
          }
        }
      }
    });

    test('nothing removed produces no rows at all', () {
      expect(removalRowsFor(candidate(selectedQuantity: 1)), isEmpty);
      expect(removalRowsFor(candidate(chargeOnRemoval: false)), isEmpty);
    });

    test('exactly one row is ever sent, and it is never the money row', () {
      // The sync payload drops flagged rows; what is left must still say the
      // default was removed.
      final sent = removalRowsFor(candidate()).where((r) => !r.removalCharge);
      expect(sent.length, 1);
      expect(sent.single.quantity, 0);
    });
  });

  group('the free allowance leaves removals alone', () {
    test('a removal is not a pick and cannot be made free', () {
      // The allowance covers things the customer chose. A charge for
      // something they did NOT take is not eligible, and the allocator never
      // sees it: signal rows are zero-quantity and money rows never become
      // picks in the first place.
      final lines = allocateFreeAllowance([
        const ComponentPick(componentId: 30, quantity: 0, unitPrice: 0.0),
        const ComponentPick(componentId: 31, quantity: 1, unitPrice: 5.0),
      ], 1);
      expect(lines.map((l) => l.componentId), [31]);
      expect(optionTotalPerParentUnit(lines), 0.0,
          reason: 'the allowance covered the one real pick');
    });
  });
}

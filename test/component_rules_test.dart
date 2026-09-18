import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/component_rules.dart';
import 'package:caisse212/domain/models/order_models.dart';

/// Component group rules and option pricing.
///
/// The backend has carried these rules since V138 while the POS rendered every
/// group as an unbounded row of steppers. These tests pin the three things
/// that decide what a customer may pick and what they pay for it: the bounds,
/// the free allowance, and whether an option is billed once per line or once
/// per parent unit.

ComponentPick pick(int id, int qty, double price) =>
    ComponentPick(componentId: id, quantity: qty, unitPrice: price);

void main() {
  group('selection type', () {
    test('the three known types parse', () {
      expect(parseSelectionType('SINGLE'), ComponentSelectionType.single);
      expect(parseSelectionType('MULTIPLE'), ComponentSelectionType.multiple);
      expect(parseSelectionType('QUANTITY'), ComponentSelectionType.quantity);
    });

    test('anything unrecognised falls back to the permissive one', () {
      // A group the POS does not understand must not become unusable — the
      // old behaviour was steppers with no bounds, so that is the fallback.
      for (final raw in [null, '', 'WHATEVER', 'single ']) {
        expect(parseSelectionType(raw), ComponentSelectionType.quantity,
            reason: 'raw: $raw');
      }
    });

    test('round-trips back to what the API sends', () {
      for (final t in ComponentSelectionType.values) {
        expect(parseSelectionType(selectionTypeToApi(t)), t);
      }
    });
  });

  group('the zero-means-unlimited quirk', () {
    test('0 is no ceiling, not a ban', () {
      // The server coerces a null max to 0 on the way out. Read literally it
      // froze the stepper at zero and made the option impossible to add.
      expect(effectiveMaxQuantity(0), isNull);
      expect(effectiveMaxQuantity(null), isNull);
      expect(effectiveMaxQuantity(-1), isNull);
    });

    test('a real ceiling survives', () {
      expect(effectiveMaxQuantity(3), 3);
      expect(effectiveMaxQuantity(1), 1);
    });
  });

  group('validating a group', () {
    const required1of1 = ComponentGroupRule(
      groupId: 7,
      name: 'Sauces',
      selectionType: ComponentSelectionType.single,
      minSelection: 1,
      maxSelection: 1,
    );

    test('a required group with nothing picked is short', () {
      final problem = validateGroup(required1of1, const []);
      expect(problem, isNotNull);
      expect(problem!.problem, GroupProblem.tooFew);
      expect(problem.selected, 0);
    });

    test('one pick satisfies it', () {
      expect(validateGroup(required1of1, [pick(30, 1, 2.0)]), isNull);
    });

    test('two picks break the ceiling', () {
      final problem =
          validateGroup(required1of1, [pick(30, 1, 2.0), pick(31, 1, 1.0)]);
      expect(problem!.problem, GroupProblem.tooMany);
      expect(problem.selected, 2);
    });

    test('a null ceiling never complains about too many', () {
      const unlimited = ComponentGroupRule(groupId: 8, name: 'Extras');
      expect(
          validateGroup(unlimited, [pick(1, 99, 1.0), pick(2, 99, 1.0)]),
          isNull);
    });

    test('quantities count as units, not as one pick each', () {
      const upToThree =
          ComponentGroupRule(groupId: 9, name: 'Toppings', maxSelection: 3);
      expect(validateGroup(upToThree, [pick(1, 3, 1.0)]), isNull);
      expect(validateGroup(upToThree, [pick(1, 4, 1.0)])!.problem,
          GroupProblem.tooMany);
    });

    test('an optional group is fine left empty', () {
      const optional = ComponentGroupRule(groupId: 10, name: 'Sides');
      expect(optional.isRequired, isFalse);
      expect(validateGroup(optional, const []), isNull);
    });
  });

  group('the free allowance', () {
    // Split rows, not a blended price. The server stores option prices as
    // NUMERIC(12,2) and rounds on insert, so an averaged 0.666… would be
    // written as 0.67 and read back as 2.01 against a ticket saying 2.00.
    // Two exact rows — the covered units at 0.00, the rest at catalogue —
    // agree to the cent on both sides.

    test('with no allowance every pick is one row at catalogue price', () {
      final lines =
          allocateFreeAllowance([pick(1, 2, 3.0), pick(2, 1, 1.0)], 0);
      expect(lines.length, 2);
      expect(lines[0].componentId, 1);
      expect(lines[0].quantity, 2);
      expect(lines[0].unitPrice, 3.0);
      expect(lines[1].unitPrice, 1.0);
    });

    test('the most expensive pick is the one that comes free', () {
      // Not the first chosen, and not the cheapest: the customer keeps the
      // best of what they picked.
      final lines =
          allocateFreeAllowance([pick(1, 1, 1.0), pick(2, 1, 5.0)], 1);
      expect(chargedTotalFor(lines, 2), 0.0, reason: 'the 5.00 one is free');
      expect(chargedTotalFor(lines, 1), 1.0);
    });

    test('a partly covered pick splits into a free row and a charged row', () {
      // Three units at 1.00 with one free: 1 @ 0.00 + 2 @ 1.00 = 2.00 owed,
      // and every price on the wire is already exact to the cent.
      final lines = allocateFreeAllowance([pick(1, 3, 1.0)], 1);
      expect(lines.length, 2);
      expect(lines[0].quantity, 1);
      expect(lines[0].unitPrice, 0.0);
      expect(lines[1].quantity, 2);
      expect(lines[1].unitPrice, 1.0);
      expect(optionTotalPerParentUnit(lines), 2.0);
    });

    test('every price sent is a real catalogue price or exactly zero', () {
      // The property that makes the split necessary: nothing blended, so
      // nothing for a 2-decimal column to round into a different number.
      final lines = allocateFreeAllowance(
          [pick(1, 3, 1.0), pick(2, 2, 2.5), pick(3, 1, 0.75)], 4);
      for (final l in lines) {
        expect(l.unitPrice == 0.0 || {1.0, 2.5, 0.75}.contains(l.unitPrice),
            isTrue,
            reason: 'blended price on the wire: $l');
      }
    });

    test('the allowance spills onto the next most expensive', () {
      // Two free out of {A 3.00 x1, B 1.00 x2}: A entirely, then one B.
      final lines =
          allocateFreeAllowance([pick(1, 1, 3.0), pick(2, 2, 1.0)], 2);
      expect(chargedTotalFor(lines, 1), 0.0);
      expect(freeUnitsFor(lines, 2), 1);
      expect(chargedTotalFor(lines, 2), 1.0);
    });

    test('a fully covered pick is one row at zero, not two', () {
      final lines = allocateFreeAllowance([pick(1, 2, 1.0)], 2);
      expect(lines.length, 1);
      expect(lines.single.quantity, 2);
      expect(lines.single.isFree, isTrue);
    });

    test('an allowance bigger than the selection makes it all free', () {
      final lines =
          allocateFreeAllowance([pick(1, 1, 2.0), pick(2, 1, 1.0)], 9);
      expect(optionTotalPerParentUnit(lines), 0.0);
    });

    test('unselected components produce no rows at all', () {
      final lines =
          allocateFreeAllowance([pick(1, 0, 2.0), pick(2, 1, 1.0)], 0);
      expect(lines.map((l) => l.componentId), [2]);
    });

    test('the same selection always allocates identically', () {
      // Cart lines merge by comparing their component lists, so an unstable
      // row order would stop two identical lines from ever combining.
      List<String> shape() => allocateFreeAllowance(
              [pick(1, 3, 1.0), pick(2, 2, 1.0), pick(3, 1, 5.0)], 3)
          .map((l) => '${l.componentId}:${l.quantity}@${l.unitPrice}')
          .toList();
      expect(shape(), shape());
      expect(shape().first.startsWith('1:'), isTrue,
          reason: 'rows follow the order the picks came in');
    });

    test('quantity totals survive the split', () {
      // Whatever the allowance does, the kitchen still gets three bacon.
      final lines = allocateFreeAllowance([pick(7, 3, 2.0)], 2);
      expect(lines.fold<int>(0, (sum, l) => sum + l.quantity), 3);
    });

    // Discount options (a negative catalogue price) used to be mistaken for
    // units the allowance had covered, which both mislabelled them in the
    // picker and let the allowance cancel the discount out.

    test('a discount option is not a free one', () {
      final lines = allocateFreeAllowance([pick(1, 2, -5.0)], 0);
      expect(lines.single.isFree, isFalse);
      expect(freeUnitsFor(lines, 1), 0);
      expect(chargedTotalFor(lines, 1), -10.0);
    });

    test('the allowance is never spent on a discount option', () {
      // Two free over {A 2.00 x1, B -5.00 x1}. Covering B would rewrite
      // -5.00 to 0.00 and make the allowance RAISE the bill to 0.00.
      final lines =
          allocateFreeAllowance([pick(1, 1, 2.0), pick(2, 1, -5.0)], 2);
      expect(optionTotalPerParentUnit(lines), -5.0);
      expect(chargedTotalFor(lines, 1), 0.0, reason: 'the 2.00 one is free');
      expect(chargedTotalFor(lines, 2), -5.0, reason: 'the discount survives');
    });

    test('the allowance is not wasted on a zero-priced option', () {
      // One free over {A 0.00 x1, B 3.00 x1}: the allowance buys B, not the
      // option that was already costing nothing.
      final lines =
          allocateFreeAllowance([pick(1, 1, 0.0), pick(2, 1, 3.0)], 1);
      expect(optionTotalPerParentUnit(lines), 0.0);
      expect(chargedTotalFor(lines, 2), 0.0);
    });
  });

  group('options are billed per parent unit', () {
    // The formula the backend uses for order totals, expectedCash and Z:
    //   line = productLine + (sum of option money) * lineQuantity
    // If the POS charged options once per line instead, every multi-quantity
    // line with a paid option would disagree with the backend's cash figure.

    test('the option total is for one parent unit', () {
      final lines =
          allocateFreeAllowance([pick(30, 1, 2.0), pick(31, 2, 0.5)], 0);
      expect(optionTotalPerParentUnit(lines), 3.0);
    });

    test('two burgers with one extra cheese each charge the cheese twice', () {
      final line = OrderItem(
        productId: 1,
        productName: 'Burger',
        finalPrice: 50.0,
        quantity: 2,
        components: [
          OrderItemComponent(
              componentId: 30, name: 'Extra Cheese', quantity: 1, price: 2.0),
        ],
      );
      expect(line.totalPrice, 104.0, reason: '(50 + 2) * 2');
    });

    test('a free option adds nothing to the line', () {
      final line = OrderItem(
        productId: 1,
        productName: 'Burger',
        finalPrice: 50.0,
        quantity: 3,
        components: [
          OrderItemComponent(
              componentId: 30, name: 'Ketchup', quantity: 1, price: 0.0),
        ],
      );
      expect(line.totalPrice, 150.0);
    });

    test('a split option lands on the line as two exact rows', () {
      // One of two bacon free: the line carries both halves, and the option
      // money for one parent unit is 0.00 + 1.00. Four burgers: 44.00.
      final lines = allocateFreeAllowance([pick(2, 2, 1.0)], 1);
      final line = OrderItem(
        productId: 1,
        productName: 'Burger',
        finalPrice: 10.0,
        quantity: 4,
        components: [
          for (final l in lines)
            OrderItemComponent(
                componentId: l.componentId,
                name: 'Bacon',
                quantity: l.quantity,
                price: l.unitPrice),
        ],
      );
      expect(line.components.length, 2, reason: 'free row plus charged row');
      expect(line.componentTotal, 1.0);
      expect(line.totalPrice, closeTo(44.0, 1e-9));
    });

    test('a repeated componentId still totals as the sum of its rows', () {
      // Duplicate component ids on one line are the whole point of the split,
      // so nothing downstream may collapse them by id.
      final line = OrderItem(
        productId: 1,
        productName: 'Burger',
        finalPrice: 0.0,
        quantity: 1,
        components: [
          OrderItemComponent(
              componentId: 9, name: 'Bacon', quantity: 1, price: 0.0),
          OrderItemComponent(
              componentId: 9, name: 'Bacon', quantity: 2, price: 1.5),
        ],
      );
      expect(line.componentTotal, 3.0);
    });
  });

  group('what a group opens with', () {
    // The bug this pins: tapping a product put TWO options from the same
    // radio group on the ticket, because seeding walked components one by one
    // with no idea which group they belonged to.

    const single = ComponentGroupRule(
      groupId: 1,
      name: 'Size',
      selectionType: ComponentSelectionType.single,
      minSelection: 1,
      maxSelection: 1,
    );

    test('a radio group seeds exactly one, even with two defaults', () {
      final seeded = seedGroup(single, const [
        ComponentSeed(componentId: 10, defaultQuantity: 1),
        ComponentSeed(componentId: 11, defaultQuantity: 1),
      ]);
      expect(seeded.length, 1);
      expect(seeded.keys.single, 10, reason: 'first in display order wins');
    });

    test('a radio group seeds one unit, whatever the default says', () {
      final seeded = seedGroup(single, const [
        ComponentSeed(componentId: 10, defaultQuantity: 3),
      ]);
      expect(seeded[10], 1);
    });

    test('two required components in a radio group still seed one', () {
      // Contradictory catalogue data — both flagged required inside a group
      // that permits one. Something has to give, and it cannot be the rule.
      final seeded = seedGroup(single, const [
        ComponentSeed(componentId: 10, isRequired: true),
        ComponentSeed(componentId: 11, isRequired: true),
      ]);
      expect(seeded.length, 1);
    });

    test('a checkbox group seeds one unit each', () {
      const multiple = ComponentGroupRule(
          groupId: 2,
          name: 'Extras',
          selectionType: ComponentSelectionType.multiple);
      final seeded = seedGroup(multiple, const [
        ComponentSeed(componentId: 10, defaultQuantity: 2),
        ComponentSeed(componentId: 11, defaultQuantity: 1),
      ]);
      expect(seeded, {10: 1, 11: 1});
    });

    test('a stepper group keeps the catalogue quantities', () {
      const quantity = ComponentGroupRule(groupId: 3, name: 'Toppings');
      final seeded = seedGroup(quantity, const [
        ComponentSeed(componentId: 10, defaultQuantity: 2),
        ComponentSeed(componentId: 11, defaultQuantity: 1, minQuantity: 3),
      ]);
      expect(seeded[10], 2);
      expect(seeded[11], 3, reason: 'never below the minimum');
    });

    test('a required component with nothing stated still starts at one', () {
      const quantity = ComponentGroupRule(groupId: 3, name: 'Toppings');
      final seeded = seedGroup(quantity, const [
        ComponentSeed(componentId: 10, isRequired: true),
      ]);
      expect(seeded[10], 1);
    });

    test('optional components with no default are simply absent', () {
      const quantity = ComponentGroupRule(groupId: 3, name: 'Toppings');
      final seeded = seedGroup(quantity, const [
        ComponentSeed(componentId: 10),
        ComponentSeed(componentId: 11),
      ]);
      expect(seeded, isEmpty);
    });

    test('a required radio group opens on its first option', () {
      // Nothing in the catalogue defaults, so without this the dialog opens
      // showing nothing chosen and refusing to confirm.
      final seeded = seedGroup(single, const [
        ComponentSeed(componentId: 10),
        ComponentSeed(componentId: 11),
      ]);
      expect(seeded, {10: 1});
    });

    test('an optional radio group opens on nothing', () {
      // Auto-picking here would put a charge on the ticket nobody asked for.
      const optionalSingle = ComponentGroupRule(
        groupId: 1,
        name: 'Sauce',
        selectionType: ComponentSelectionType.single,
        maxSelection: 1,
      );
      expect(
          seedGroup(optionalSingle, const [
            ComponentSeed(componentId: 10),
            ComponentSeed(componentId: 11),
          ]),
          isEmpty);
    });

    test('a stated default still beats the fallback to the first', () {
      final seeded = seedGroup(single, const [
        ComponentSeed(componentId: 10),
        ComponentSeed(componentId: 11, defaultQuantity: 1),
      ]);
      expect(seeded, {11: 1});
    });

    test('what a radio group opens with satisfies its own rule', () {
      // A dialog that opens already failing validation is a dialog the
      // cashier cannot confirm without understanding why.
      final seeded = seedGroup(single, const [
        ComponentSeed(componentId: 10, defaultQuantity: 1),
        ComponentSeed(componentId: 11, defaultQuantity: 1),
      ]);
      final picks = [
        for (final e in seeded.entries)
          ComponentPick(componentId: e.key, quantity: e.value, unitPrice: 1.0),
      ];
      expect(validateGroup(single, picks), isNull);
    });
  });

  group('what the rule says about itself', () {
    test('a minimum above zero is what makes a group required', () {
      expect(const ComponentGroupRule(groupId: 1, name: 'g').isRequired, isFalse);
      expect(
          const ComponentGroupRule(groupId: 1, name: 'g', minSelection: 1)
              .isRequired,
          isTrue);
    });

    test('single and multiple cap each component at one', () {
      const single = ComponentGroupRule(
          groupId: 1,
          name: 'g',
          selectionType: ComponentSelectionType.single,
          maxSelection: 5);
      const multiple = ComponentGroupRule(
          groupId: 1,
          name: 'g',
          selectionType: ComponentSelectionType.multiple,
          maxSelection: 5);
      expect(single.perComponentCap, 1);
      expect(multiple.perComponentCap, 1);
    });

    test('a quantity group defers to the group ceiling', () {
      const q =
          ComponentGroupRule(groupId: 1, name: 'g', maxSelection: 5);
      expect(q.perComponentCap, 5);
    });
  });
}

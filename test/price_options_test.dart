import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/component_rules.dart';

/// [priceOptions] is the till's product dialog, minus the dialog: what the
/// waiter API runs on a selection made on a tablet.
void main() {
  // "Formule" (2) shows the drinks group (3) only once "Menu" (20) is picked.
  const rules = <int?, ComponentGroupRule>{
    null: ComponentGroupRule(groupId: null, name: '', displayOrder: 9999),
    2: ComponentGroupRule(
        groupId: 2, name: 'Formule', minSelection: 1, maxSelection: 1),
    3: ComponentGroupRule(
        groupId: 3,
        name: 'Boisson',
        minSelection: 1,
        maxSelection: 1,
        freeQuantity: 1,
        visibleWhenComponentIds: [20]),
  };
  const catalogue = {20: 15.0, 21: 0.0, 30: 3.0, 31: 4.0};
  const groupOf = <int, int?>{20: 2, 21: 2, 30: 3, 31: 3};

  OptionPricing price(Map<int, int> picked) => priceOptions(
      picked: picked, catalogue: catalogue, groupOf: groupOf, rules: rules);

  test('a menu with its drink: the drink is in the menu price', () {
    final r = price({20: 1, 31: 1});
    expect(r.isOk, isTrue);
    expect({for (final l in r.lines) l.componentId: l.unitPrice},
        {20: 15.0, 31: 0.0});
  });

  test('a drink without the menu sits in a hidden group', () {
    final r = price({30: 1});
    expect(r.problem, OptionProblem.hiddenGroup);
    expect(r.componentId, 30);
  });

  test('nothing picked in a required visible group is too few', () {
    final r = price({});
    expect(r.problem, OptionProblem.tooFew);
    expect(r.group?.groupId, 2);
  });

  test('a menu without its drink is too few', () {
    final r = price({20: 1});
    expect(r.problem, OptionProblem.tooFew);
    expect(r.group?.groupId, 3);
  });

  test('one option past its own limit is refused', () {
    final r = priceOptions(
      picked: {20: 1, 31: 3},
      catalogue: catalogue,
      groupOf: groupOf,
      rules: rules,
      maxEach: {31: 2},
    );
    expect(r.problem, OptionProblem.tooManyOfOne);
    expect(r.componentId, 31);
  });

  test('the stepper limit: link max in a QUANTITY group, one otherwise', () {
    const stepper = ComponentGroupRule(groupId: 1, name: 'g');
    const radio = ComponentGroupRule(
        groupId: 1, name: 'g', selectionType: ComponentSelectionType.single);
    expect(maxUnitsOf(stepper, 3), 3);
    expect(maxUnitsOf(stepper, 0), isNull, reason: '0 = no cap');
    expect(maxUnitsOf(null, 4), 4, reason: 'ungrouped is a stepper');
    expect(maxUnitsOf(radio, 3), 1);
  });

  test('zero quantities are not picks', () {
    final r = price({21: 1, 30: 0});
    expect(r.isOk, isTrue);
    expect(r.lines.map((l) => l.componentId), [21]);
  });
}

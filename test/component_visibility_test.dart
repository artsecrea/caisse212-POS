import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/component_rules.dart';

// Tacos 40, the bms example:
//   Formule (1): Seul 10 | Menu 11
//   Boisson (2): Coca 20 | Eau 21        visibleWhen [Menu]
//   Accompagnement (3): Frites 30        visibleWhen [Menu]
//   Sauces (4): Algérienne 40            always
//   Taille (5): Grande 50                visibleWhen [Coca]  (a chain)
const groupOf = <int, int?>{
  10: 1, 11: 1,
  20: 2, 21: 2,
  30: 3,
  40: 4,
  50: 5,
  99: null, // ungrouped
};

final rules = <int?, ComponentGroupRule>{
  null: const ComponentGroupRule(groupId: null, name: ''),
  1: const ComponentGroupRule(groupId: 1, name: 'Formule'),
  2: const ComponentGroupRule(
      groupId: 2, name: 'Boisson', visibleWhenComponentIds: [11]),
  3: const ComponentGroupRule(
      groupId: 3, name: 'Accompagnement', visibleWhenComponentIds: [11]),
  4: const ComponentGroupRule(groupId: 4, name: 'Sauces'),
  5: const ComponentGroupRule(
      groupId: 5, name: 'Taille', visibleWhenComponentIds: [20]),
};

Set<int?> visibleFor(Set<int> selected,
        {Map<int, int?> groups = groupOf,
        Map<int?, ComponentGroupRule>? r}) =>
    visibleGroupIds(
        rules: r ?? rules,
        groupOfComponent: groups,
        selectedComponentIds: selected);

void main() {
  test('Seul shows only the unconditional groups', () {
    expect(visibleFor({10}), {null, 1, 4});
  });

  test('Menu opens Boisson and Accompagnement', () {
    expect(visibleFor({11}), {null, 1, 2, 3, 4});
  });

  test('a chain resolves through its trigger', () {
    expect(visibleFor({11, 20}), {null, 1, 2, 3, 4, 5});
  });

  test('a trigger in a hidden group counts for nothing', () {
    // Coca still selected after Menu -> Seul: Boisson is hidden, so Taille
    // must not open off it.
    expect(visibleFor({10, 20}), {null, 1, 4});
  });

  test('triggers are ORed', () {
    final r = {
      ...rules,
      2: const ComponentGroupRule(
          groupId: 2, name: 'Boisson', visibleWhenComponentIds: [11, 40]),
    };
    expect(visibleFor({10, 40}, r: r), containsAll([2]));
  });

  test('an ungrouped trigger always counts', () {
    final r = {
      ...rules,
      3: const ComponentGroupRule(
          groupId: 3, name: 'Accompagnement', visibleWhenComponentIds: [99]),
    };
    expect(visibleFor({99}, r: r), contains(3));
  });

  test('a trigger the product does not offer never fires', () {
    // 11 (Menu) off the product, e.g. 86'd and filtered out of the list.
    final groups = Map<int, int?>.from(groupOf)..remove(11);
    expect(visibleFor({11}, groups: groups), isNot(contains(2)));
  });

  test('a cycle with no outside trigger stays hidden', () {
    final r = {
      ...rules,
      2: const ComponentGroupRule(
          groupId: 2, name: 'Boisson', visibleWhenComponentIds: [30]),
      3: const ComponentGroupRule(
          groupId: 3, name: 'Accompagnement', visibleWhenComponentIds: [20]),
    };
    expect(visibleFor({20, 30}, r: r), {null, 1, 4, 5}..remove(5));
  });

  group('storage', () {
    test('round-trips', () {
      expect(decodeVisibleWhen(encodeVisibleWhen([11, 12])), [11, 12]);
    });
    test('absent, empty or junk is unconditional', () {
      expect(encodeVisibleWhen(null), isNull);
      expect(encodeVisibleWhen(const []), isNull);
      expect(encodeVisibleWhen('11'), isNull);
      expect(decodeVisibleWhen(null), isEmpty);
      expect(decodeVisibleWhen('not json'), isEmpty);
    });
  });
}

/// Component group selection rules and option pricing.
///
/// Kept as plain functions on plain data, with no Drift row and no widget in
/// sight, because this is where the money is decided: what a customer may
/// pick, and what they are charged for it. All of it is exercised directly in
/// `test/component_rules_test.dart`.
library;

import 'dart:convert';

/// How a group is picked from.
enum ComponentSelectionType {
  /// Radio. At most one component, always quantity 1.
  single,

  /// Checkboxes. Several components, each exactly quantity 1 — no stepper.
  multiple,

  /// Steppers, bounded per component. The permissive default, and what every
  /// group behaved as before the rules existed.
  quantity,
}

ComponentSelectionType parseSelectionType(String? raw) {
  switch (raw?.toUpperCase()) {
    case 'SINGLE':
      return ComponentSelectionType.single;
    case 'MULTIPLE':
      return ComponentSelectionType.multiple;
    case 'QUANTITY':
    default:
      return ComponentSelectionType.quantity;
  }
}

String selectionTypeToApi(ComponentSelectionType type) => switch (type) {
      ComponentSelectionType.single => 'SINGLE',
      ComponentSelectionType.multiple => 'MULTIPLE',
      ComponentSelectionType.quantity => 'QUANTITY',
    };

/// A per-component quantity bound of 0 means *unbounded*, not "you may not
/// have any".
///
/// The server stores these as nullable and coerces null to 0 on the way out,
/// so a component with no ceiling arrives as `maxQuantity: 0`. Taken at face
/// value that froze the stepper at zero and made the option impossible to add.
int? effectiveMaxQuantity(int? raw) => (raw == null || raw <= 0) ? null : raw;

/// The rules in force for one group on one product.
class ComponentGroupRule {
  /// Null for the bucket of components that belong to no group at all.
  final int? groupId;
  final String name;
  final String? color;
  final ComponentSelectionType selectionType;

  /// Minimum selected units across the whole group.
  final int minSelection;

  /// Maximum selected units, or null for unlimited.
  final int? maxSelection;

  /// Units included in the product price — the most expensive ones.
  final int freeQuantity;
  final int displayOrder;

  /// Component ids, from other groups, any one of which makes this group
  /// appear. Empty means always shown. See [visibleGroupIds].
  final List<int> visibleWhenComponentIds;

  const ComponentGroupRule({
    required this.groupId,
    required this.name,
    this.color,
    this.selectionType = ComponentSelectionType.quantity,
    this.minSelection = 0,
    this.maxSelection,
    this.freeQuantity = 0,
    this.displayOrder = 0,
    this.visibleWhenComponentIds = const [],
  });

  bool get isConditional => visibleWhenComponentIds.isNotEmpty;

  /// A group is required when it demands at least one unit. There is no
  /// separate flag — this *is* the flag.
  bool get isRequired => minSelection > 0;

  /// The ceiling on one component's quantity implied by the group itself.
  /// SINGLE and MULTIPLE are one-each by definition; QUANTITY defers to the
  /// per-component bounds.
  int? get perComponentCap => selectionType == ComponentSelectionType.quantity
      ? maxSelection
      : 1;

  ComponentGroupRule copyWith({
    String? name,
    String? color,
    ComponentSelectionType? selectionType,
    int? minSelection,
    int? maxSelection,
    int? freeQuantity,
    int? displayOrder,
    List<int>? visibleWhenComponentIds,
  }) {
    return ComponentGroupRule(
      groupId: groupId,
      name: name ?? this.name,
      color: color ?? this.color,
      selectionType: selectionType ?? this.selectionType,
      minSelection: minSelection ?? this.minSelection,
      maxSelection: maxSelection ?? this.maxSelection,
      freeQuantity: freeQuantity ?? this.freeQuantity,
      displayOrder: displayOrder ?? this.displayOrder,
      visibleWhenComponentIds:
          visibleWhenComponentIds ?? this.visibleWhenComponentIds,
    );
  }
}

/// The wire value of `visibleWhenComponentIds` as stored locally: a JSON
/// array, or null when there is nothing to store. Anything that is not a list
/// of numbers is treated as absent, i.e. the group is unconditional.
String? encodeVisibleWhen(Object? raw) {
  if (raw is! List) return null;
  final ids = [for (final v in raw) if (v is num) v.toInt()];
  return ids.isEmpty ? null : jsonEncode(ids);
}

List<int> decodeVisibleWhen(String? stored) {
  if (stored == null || stored.isEmpty) return const [];
  try {
    final raw = jsonDecode(stored);
    if (raw is! List) return const [];
    return [for (final v in raw) if (v is num) v.toInt()];
  } catch (_) {
    return const [];
  }
}

/// Which groups are on screen for the current selection.
///
/// A conditional group appears once any of its triggers is selected, but a
/// trigger only counts while its own group is visible: "Menu" ticked in a
/// group that is itself hidden opens nothing. Hence the fixpoint rather than
/// one pass, so chains (Menu -> Boisson -> Taille) resolve in any order.
///
/// [groupOfComponent] holds every component this product offers, mapped to
/// its group (null = ungrouped, which always counts as visible). A trigger the
/// product does not offer can never fire. A group with no rule is
/// unconditional. The ungrouped bucket (null) is always visible.
///
/// While a group is hidden it does not exist for the line: its minimum does
/// not apply, its defaults are not seeded, and no row of it, not even a zero,
/// is sent. Enforcing that is the caller's job; this only answers "which".
Set<int?> visibleGroupIds({
  required Map<int?, ComponentGroupRule> rules,
  required Map<int, int?> groupOfComponent,
  required Set<int> selectedComponentIds,
}) {
  final offered = groupOfComponent.values.toSet()..add(null);
  final visible = <int?>{
    for (final g in offered)
      if (!(rules[g]?.isConditional ?? false)) g,
  };

  var changed = true;
  while (changed) {
    changed = false;
    for (final g in offered) {
      if (visible.contains(g)) continue;
      final fires = rules[g]!.visibleWhenComponentIds.any((t) =>
          selectedComponentIds.contains(t) &&
          groupOfComponent.containsKey(t) &&
          visible.contains(groupOfComponent[t]));
      if (fires) {
        visible.add(g);
        changed = true;
      }
    }
  }
  return visible;
}

/// One chosen component within a group.
class ComponentPick {
  final int componentId;
  final int quantity;

  /// Catalogue price of a single unit, before any free allowance.
  final double unitPrice;

  const ComponentPick({
    required this.componentId,
    required this.quantity,
    required this.unitPrice,
  });
}

/// Why a group's selection is not acceptable.
enum GroupProblem {
  /// Fewer units selected than [ComponentGroupRule.minSelection].
  tooFew,

  /// More units selected than [ComponentGroupRule.maxSelection].
  tooMany,
}

class GroupValidation {
  final ComponentGroupRule rule;
  final GroupProblem problem;
  final int selected;

  const GroupValidation({
    required this.rule,
    required this.problem,
    required this.selected,
  });
}

/// Total units picked in a group.
int selectedUnits(Iterable<ComponentPick> picks) =>
    picks.fold(0, (sum, p) => sum + (p.quantity > 0 ? p.quantity : 0));

/// Check one group's selection against its rule. Null means it is fine.
///
/// SINGLE and MULTIPLE need no special case here: a SINGLE group arrives with
/// max 1 from the server, and both cap each component at one unit in the UI,
/// so the unit count is the only thing left to check.
GroupValidation? validateGroup(
    ComponentGroupRule rule, Iterable<ComponentPick> picks) {
  final units = selectedUnits(picks);
  if (units < rule.minSelection) {
    return GroupValidation(
        rule: rule, problem: GroupProblem.tooFew, selected: units);
  }
  final max = rule.maxSelection;
  if (max != null && units > max) {
    return GroupValidation(
        rule: rule, problem: GroupProblem.tooMany, selected: units);
  }
  return null;
}

/// What the catalogue says about one component on one product, as far as the
/// opening selection is concerned.
class ComponentSeed {
  final int componentId;
  final bool isRequired;
  final int minQuantity;
  final int defaultQuantity;

  const ComponentSeed({
    required this.componentId,
    this.isRequired = false,
    this.minQuantity = 0,
    this.defaultQuantity = 0,
  });
}

/// The quantities a group starts at when the dialog opens.
///
/// Only components that should begin selected appear in the result; everything
/// else is simply absent, which is how the dialog reads "not chosen".
///
/// The rule that matters here is the radio group. Two components in the same
/// SINGLE group both carrying a default used to seed both, so the ticket
/// opened with two mutually exclusive options already on it — the cashier had
/// to notice and undo one, and if they did not, both were sold. A radio group
/// takes at most one, and the first in display order wins.
Map<int, int> seedGroup(ComponentGroupRule rule, Iterable<ComponentSeed> seeds) {
  final out = <int, int>{};
  var singleTaken = false;

  for (final seed in seeds) {
    if (!seed.isRequired && seed.defaultQuantity <= 0) continue;

    // Never start below the minimum, and never start a required component at
    // nothing: required with no default and no minimum means one, which is
    // what the server does when it auto-adds an omitted required option.
    var quantity = seed.defaultQuantity < seed.minQuantity
        ? seed.minQuantity
        : seed.defaultQuantity;
    if (seed.isRequired && quantity <= 0) quantity = 1;
    if (quantity <= 0) continue;

    if (rule.selectionType != ComponentSelectionType.quantity) {
      quantity = 1; // one each, never a stepper's worth
    }
    if (rule.selectionType == ComponentSelectionType.single) {
      if (singleTaken) continue;
      singleTaken = true;
    }
    out[seed.componentId] = quantity;
  }

  // A required radio group that nothing defaulted into opens on its first
  // option rather than on nothing. Opening empty means opening in a state the
  // cashier cannot confirm, with a rule they have to read to understand.
  //
  // Only when required: auto-selecting into an *optional* radio group would
  // put a charge on the ticket that nobody asked for.
  if (rule.selectionType == ComponentSelectionType.single &&
      rule.isRequired &&
      out.isEmpty &&
      seeds.isNotEmpty) {
    out[seeds.first.componentId] = 1;
  }
  return out;
}

/// A default the customer may have taken off a product.
///
/// Some defaults are priced into the product and removing one is a preference,
/// not a discount: "no cheese" costs what cheese costs. The back office marks
/// those links, and the server does the charging — the POS only has to say
/// out loud that the default was removed, and show the customer the same
/// number the server will bill.
class RemovalCandidate {
  final int componentId;

  /// What the product comes with.
  final int defaultQuantity;

  /// What the cashier left on it.
  final int selectedQuantity;

  /// Charged per removed unit — the link override, or the catalogue price.
  final double unitPrice;

  /// Whether this link is one of the ones that charges on removal.
  final bool chargeOnRemoval;

  const RemovalCandidate({
    required this.componentId,
    required this.defaultQuantity,
    required this.selectedQuantity,
    required this.unitPrice,
    this.chargeOnRemoval = false,
  });

  /// Units short of the default, and so units billed. Zero unless this link
  /// charges on removal and something was actually taken off.
  int get deficit {
    if (!chargeOnRemoval || defaultQuantity < 1) return 0;
    final short = defaultQuantity - selectedQuantity;
    return short > 0 ? short : 0;
  }

  bool get isCharged => deficit > 0;

  /// What the removal costs for ONE parent unit.
  double get charge => deficit * unitPrice;

  /// Whether the order must carry this component's row explicitly.
  ///
  /// A ticket that simply leaves the row out bills nothing — that is what
  /// protects imported orders and older builds. So silence is not an option
  /// here: the removal has to be stated, as a quantity below the default.
  bool get needsExplicitRow => chargeOnRemoval && defaultQuantity >= 1;
}

/// One row a charged removal puts on the line.
class RemovalRow {
  final int componentId;
  final int quantity;
  final double price;

  /// True for the local money row, which is never sent to the server.
  final bool removalCharge;

  const RemovalRow({
    required this.componentId,
    required this.quantity,
    required this.price,
    required this.removalCharge,
  });
}

/// The extra rows a charged removal contributes, beyond the component's own.
///
/// A FULL removal needs a signal row — the component at quantity zero — because
/// nothing else in the line carries it once the quantity hits zero, and a
/// ticket that omits the row bills nothing at all.
///
/// A PARTIAL removal needs no signal: the component is already on the line at
/// the reduced quantity, and that row is a SERVED option which must keep its
/// real price. Emitting a zero-priced row for it would have the kept unit bill
/// nothing while the server adds only the deficit — undercharging by a unit.
/// Hence the invariant this function exists to hold: price 0.0 only ever
/// travels with quantity 0.
List<RemovalRow> removalRowsFor(RemovalCandidate candidate) {
  if (!candidate.isCharged) return const [];
  return [
    if (candidate.selectedQuantity <= 0)
      RemovalRow(
        componentId: candidate.componentId,
        quantity: 0,
        price: 0.0,
        removalCharge: false,
      ),
    RemovalRow(
      componentId: candidate.componentId,
      quantity: candidate.deficit,
      price: candidate.unitPrice,
      removalCharge: true,
    ),
  ];
}

/// What removals add to the price of ONE parent unit.
///
/// Per parent unit like every other option: two burgers with the cheese taken
/// off are charged for the cheese twice.
double removalChargePerParentUnit(Iterable<RemovalCandidate> candidates) =>
    candidates.fold(0.0, (sum, c) => sum + c.charge);

/// One option row as it will be billed and sent.
///
/// A component whose free allowance covers only part of its quantity produces
/// two of these — the covered units at 0.00 and the rest at the catalogue
/// price — rather than one row at a blended price. Both halves are then exact
/// to the cent, which the blended average is not: the server stores option
/// prices as NUMERIC(12,2) and rounds on insert, so 3 units at 0.666… would be
/// written as 0.67 and read back as 2.01 against a ticket that said 2.00.
class ChargedComponentLine {
  final int componentId;
  final int quantity;

  /// Exactly what one unit costs: the catalogue price, or zero when the
  /// group's allowance covers it.
  final double unitPrice;

  const ChargedComponentLine({
    required this.componentId,
    required this.quantity,
    required this.unitPrice,
  });

  /// Covered by the allowance: priced at exactly zero.
  ///
  /// Deliberately not `<= 0`. A discount option (a negative catalogue
  /// price) is not a covered unit, and counting it as one made the picker
  /// label a -5.00 option as free and hide the amount entirely.
  bool get isFree => unitPrice == 0;
  double get total => unitPrice * quantity;

  @override
  String toString() =>
      'ChargedComponentLine($componentId x$quantity @$unitPrice)';
}

/// Spend a group's free allowance over its selection, and return the rows to
/// bill and send.
///
/// The allowance covers the [freeQuantity] *most expensive* units in the
/// group, so the customer keeps the best of what they chose and pays for the
/// cheap remainder. The POS is the pricing authority on its own orders — the
/// server bills whatever rows it is handed.
///
/// Rows come back in the order the picks were given, free half first. That is
/// a convenience for reading the output, NOT a contract: every consumer
/// normalises. The POS compares cart lines through `_componentSignature`
/// (payment_screen.dart), which sorts before joining, and the waiter app's
/// line-identity key sorts by component id. So nothing downstream may depend
/// on this order — what each row must carry is its own exact unit price, since
/// that is what distinguishes a covered unit from a charged one.
List<ChargedComponentLine> allocateFreeAllowance(
    Iterable<ComponentPick> picks, int freeQuantity) {
  final active = picks.where((p) => p.quantity > 0).toList();
  if (active.isEmpty) return const [];

  final freeUnits = <int, int>{};
  if (freeQuantity > 0) {
    // Most expensive first: those are the units the allowance pays for.
    //
    // Only units that actually cost something are eligible. Spending the
    // allowance on a zero-priced option wastes it, and spending it on a
    // discount option (negative price) rewrote -5.00 to 0.00, so a free
    // allowance ended up raising the bill.
    final byPrice = active.where((p) => p.unitPrice > 0).toList()
      ..sort((a, b) => b.unitPrice.compareTo(a.unitPrice));
    var remaining = freeQuantity;
    for (final p in byPrice) {
      if (remaining <= 0) break;
      final covered = remaining >= p.quantity ? p.quantity : remaining;
      remaining -= covered;
      freeUnits[p.componentId] = covered;
    }
  }

  final lines = <ChargedComponentLine>[];
  for (final p in active) {
    final free = freeUnits[p.componentId] ?? 0;
    if (free > 0) {
      lines.add(ChargedComponentLine(
          componentId: p.componentId, quantity: free, unitPrice: 0.0));
    }
    final charged = p.quantity - free;
    if (charged > 0) {
      lines.add(ChargedComponentLine(
          componentId: p.componentId,
          quantity: charged,
          unitPrice: p.unitPrice));
    }
  }
  return lines;
}

/// How many units of one component the allowance covered.
int freeUnitsFor(Iterable<ChargedComponentLine> lines, int componentId) => lines
    .where((l) => l.componentId == componentId && l.isFree)
    .fold(0, (sum, l) => sum + l.quantity);

/// What one component costs across all its rows, for one parent unit.
double chargedTotalFor(Iterable<ChargedComponentLine> lines, int componentId) =>
    lines
        .where((l) => l.componentId == componentId)
        .fold(0.0, (sum, l) => sum + l.total);

/// What one line's options add to the price of a *single* parent unit.
///
/// The parent quantity is deliberately not part of this: an option price is
/// per parent unit, and the caller multiplies. Two burgers with one extra
/// cheese each is `(burger + cheese) * 2`, not `burger * 2 + cheese`.
double optionTotalPerParentUnit(Iterable<ChargedComponentLine> lines) =>
    lines.fold(0.0, (sum, l) => sum + l.total);


/// Why a set of options sent for a line was refused.
enum OptionProblem {
  /// Not offered on this product, or 86'd.
  notOffered,

  /// More units of one option than its own limit allows.
  tooManyOfOne,

  /// Picked in a group the rest of the selection keeps hidden.
  hiddenGroup,

  /// Fewer units than the group's minimum.
  tooFew,

  /// More units than the group's maximum.
  tooMany,
}

/// The outcome of [priceOptions]: the rows to store, or why there are none.
class OptionPricing {
  const OptionPricing._(this.lines, this.problem, this.componentId, this.group);

  const OptionPricing.ok(List<ChargedComponentLine> lines)
      : this._(lines, null, null, null);

  const OptionPricing.refused(OptionProblem problem,
      {int? componentId, ComponentGroupRule? group})
      : this._(const [], problem, componentId, group);

  /// One row per priced slice, as [allocateFreeAllowance] cuts them.
  final List<ChargedComponentLine> lines;
  final OptionProblem? problem;

  /// The component at fault, for [OptionProblem.notOffered],
  /// [OptionProblem.tooManyOfOne] and [OptionProblem.hiddenGroup].
  final int? componentId;

  /// The group at fault, for [OptionProblem.tooFew] and [OptionProblem.tooMany].
  final ComponentGroupRule? group;

  bool get isOk => problem == null;
}

/// How many units of one option a line may carry, as the product dialog's
/// stepper allows: the product link's `maxQuantity` in a stepper group (0 or
/// null = no cap), one in a SINGLE or MULTIPLE group.
int? maxUnitsOf(ComponentGroupRule? rule, int? linkMaxQuantity) =>
    (rule?.selectionType ?? ComponentSelectionType.quantity) ==
            ComponentSelectionType.quantity
        ? effectiveMaxQuantity(linkMaxQuantity)
        : 1;

/// Check and price a line's options the way the till's product dialog does,
/// for a selection made somewhere else (the waiter app). Whatever price the
/// sender attached is not an input: the catalogue decides.
///
/// [picked] is units per parent unit, summed by component. [catalogue] holds
/// the components on offer for this product with their resolved price (the
/// product link's override, else the component's own), and [groupOf] their
/// group. Rules are checked only for groups that have something on offer and
/// that the selection makes visible — exactly the groups the dialog shows.
///
/// [maxEach] caps units per option, as the dialog's stepper does (absent or
/// null = no cap); see [maxUnitsOf].
OptionPricing priceOptions({
  required Map<int, int> picked,
  required Map<int, double> catalogue,
  required Map<int, int?> groupOf,
  required Map<int?, ComponentGroupRule> rules,
  Map<int, int?> maxEach = const {},
}) {
  final chosen = {
    for (final e in picked.entries)
      if (e.value > 0) e.key: e.value,
  };
  for (final id in chosen.keys) {
    if (!catalogue.containsKey(id)) {
      return OptionPricing.refused(OptionProblem.notOffered, componentId: id);
    }
  }
  for (final e in chosen.entries) {
    final max = maxEach[e.key];
    if (max != null && e.value > max) {
      return OptionPricing.refused(OptionProblem.tooManyOfOne,
          componentId: e.key);
    }
  }

  final visible = visibleGroupIds(
    rules: rules,
    groupOfComponent: groupOf,
    selectedComponentIds: chosen.keys.toSet(),
  );
  for (final id in chosen.keys) {
    if (!visible.contains(groupOf[id])) {
      return OptionPricing.refused(OptionProblem.hiddenGroup, componentId: id);
    }
  }

  final picksByGroup = <int?, List<ComponentPick>>{
    for (final g in groupOf.values.toSet()) g: [],
  };
  for (final e in chosen.entries) {
    picksByGroup[groupOf[e.key]]!.add(ComponentPick(
        componentId: e.key, quantity: e.value, unitPrice: catalogue[e.key]!));
  }

  final lines = <ChargedComponentLine>[];
  for (final entry in picksByGroup.entries) {
    if (!visible.contains(entry.key)) continue;
    final rule = rules[entry.key];
    if (rule != null) {
      final problem = validateGroup(rule, entry.value);
      if (problem != null) {
        return OptionPricing.refused(
            problem.problem == GroupProblem.tooFew
                ? OptionProblem.tooFew
                : OptionProblem.tooMany,
            group: rule);
      }
    }
    lines.addAll(allocateFreeAllowance(entry.value, rule?.freeQuantity ?? 0));
  }
  return OptionPricing.ok(lines);
}

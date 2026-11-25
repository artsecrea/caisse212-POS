import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/component_rules.dart';
import '../../domain/models/order_models.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/button_styles.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';
import '../../providers/order_provider.dart';
import 'permission_guard.dart';
import 'serial_picker_panel.dart';
import './adaptive_text_field.dart';

String _fmtQtyLocal(double q) {
  if (q == q.truncateToDouble()) return q.toInt().toString();
  return q.toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

class ProductModificationDialog extends ConsumerStatefulWidget {
  final dynamic product;
  final bool isEditMode;

  const ProductModificationDialog({
    Key? key,
    required this.product,
    this.isEditMode = false,
  }) : super(key: key);

  @override
  ConsumerState<ProductModificationDialog> createState() => _ProductModificationDialogState();
}

class _ProductModificationDialogState extends ConsumerState<ProductModificationDialog> {
  final Map<int, int> _componentQuantities = {};
  final Map<int, bool> _componentSpecial = {};

  /// Index of the option group on screen in
  /// [ComponentGroupDisplayMode.step]. Never clamped in place: the group list
  /// arrives from a stream and can shrink under an open dialog, so every read
  /// clamps instead.
  int _groupStep = 0;

  late TextEditingController _manualDiscountController;
  late TextEditingController _noteController;
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  late FocusNode _discountFocusNode;

  /// The unit chosen for a serial-tracked product. Required before save, and
  /// forces quantity to 1 — one line per physical unit.
  Serial? _selectedSerial;

  /// Serial-tracking flag from the catalogue row, loaded with the plannable
  /// flags below. Null until that load lands; the getter falls back to the
  /// object we were handed so the very first frame is still correct.
  bool? _serialTrackedDb;

  bool _isPercentageDiscount = false;
  double _productDiscount = 0.0;
  double _quantity = 1.0;
  /// Manual unit-price override (permission-gated). Null = use the default
  /// product/variant price. Never negative.
  double? _customPrice;
  /// The product's unit of measure (e.g. kg, L). Falls back to "pcs" when the
  /// product has no unit set. Loaded from the products table on open.
  String? _unitName;
  String? _discountError;

  // Variant selection state
  Map<int, int> _selectedAttributeValues = {};
  Map<String, dynamic>? _selectedVariant;
  double? _variantPrice;
  String? _variantImageUrl;
  String? _variantName;

  /// Time-managed service: sold as a whole count of sessions. Booking a slot
  /// lives in reservations now, never on the order line.
  bool _isPlannable = false;

  /// Units carved off this line under a note of their own ("2 without
  /// onion"). Each becomes a separate order line on save; the main line keeps
  /// whatever quantity is left.
  final List<({String note, int quantity})> _noteSplits = [];
  bool _noteWritten = false;

  // ─── Helpers ────────────────────────────────────────────────────────────────

  int get _splitQuantity =>
      _noteSplits.fold(0, (sum, s) => sum + s.quantity);

  double get _mainQuantity => _quantity - _splitQuantity;

  /// A serial line is one physical unit and a weighed line's quantity is a
  /// weight, so neither can be shared out between notes.
  bool get _canSplitByNote {
    if (_isSerialTracked) return false;
    final product = widget.product;
    return !(product is OrderItem && product.isWeighedItem);
  }

  /// Whether this product (or the chosen variant) needs a serial. Read
  /// synchronously off the already-loaded rows so the panel can switch on the
  /// first frame — a tracked product must never render a components panel that
  /// lets the cashier add it without a unit.
  bool get _isSerialTracked {
    final variant = _selectedVariant?['variant'];
    if (variant != null && variant.isSerialTracked == true) return true;
    if (_serialTrackedDb != null) return _serialTrackedDb!;
    // Fall back to the object we were handed; an OrderItem has no flag, so an
    // edit of an existing serial line is detected by the serial it carries.
    if (widget.product is OrderItem) {
      return (widget.product as OrderItem).serialId != null;
    }
    try {
      return widget.product.isSerialTracked == true;
    } catch (_) {
      return false;
    }
  }

  /// Units already committed to OTHER lines of the current order, so the picker
  /// cannot hand the same physical unit to two lines.
  Set<int> _serialsInBasket() {
    final editingId =
        widget.product is OrderItem ? (widget.product as OrderItem).id : null;
    final ids = <int>{};
    for (final item in ref.read(orderProvider).items) {
      if (item.serialId == null) continue;
      if (editingId != null && item.id == editingId) continue;
      ids.add(item.serialId!);
    }
    return ids;
  }

  int get _productId => widget.product is OrderItem
      ? (widget.product as OrderItem).productId
      : widget.product.id;

  bool get _isVariantProduct =>
      widget.product is! OrderItem && (widget.product.isVariant ?? false);

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _manualDiscountController = TextEditingController();
    // Rebuild when the note goes from empty to written (or back), so the
    // "another note" button follows it — whichever keyboard typed it.
    _noteController = TextEditingController()
      ..addListener(() {
        final written = _noteController.text.trim().isNotEmpty;
        if (written != _noteWritten && mounted) {
          setState(() => _noteWritten = written);
        }
      });
    _quantityController = TextEditingController(text: '1');
    _priceController = TextEditingController();
    _discountFocusNode = FocusNode();

    if (widget.product is OrderItem) {
      final item = widget.product as OrderItem;
      _productDiscount = item.discount;
      _quantity = item.quantity;
      _quantityController.text = _fmtQtyLocal(_quantity);

      for (var comp in item.components) {
        _componentQuantities[comp.componentId] = comp.quantity;
        _componentSpecial[comp.componentId] = comp.isSpecial;
      }

      // Re-opening a serial line must show its own unit as the current pick,
      // not an empty picker that then demands a re-scan.
      if (item.serialId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          final s = await ref.read(serialServiceProvider).byId(item.serialId!);
          if (mounted && s != null) setState(() => _selectedSerial = s);
        });
      }

      if (item.manualDiscount > 0) {
        _manualDiscountController.text = item.manualDiscount.toStringAsFixed(2);
      }
      if (item.note != null) {
        // Set first so the listener sees no change and skips setState here.
        _noteWritten = item.note!.trim().isNotEmpty;
        _noteController.text = item.note!;
      }
      if (item.variantId != null) {
        _variantName = item.variantName;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadExistingVariant(item.variantId!);
        });
      }
    } else {
      _productDiscount = widget.product.discountAmount ?? 0.0;
      // Seeding happens in build() via ref.listen so it fires as soon as the
      // provider resolves, even on the very first frame.
    }

    // Load plannable flag for this product
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final db = ref.read(databaseProvider);
      final product = await (db.select(db.products)
            ..where((t) => t.id.equals(_productId)))
          .getSingleOrNull();
      if (product != null && mounted) {
        setState(() {
          _isPlannable = product.isPlannable;
          _serialTrackedDb = product.isSerialTracked;
          _unitName = product.unitName;
        });
      }
    });
  }

  /// Whether this product arrives with no price of its own, so the cashier
  /// has to supply one.
  ///
  /// Reads the CATALOGUE price, not the effective one: a variant or an
  /// override may well have filled it in by the time the dialog builds, and
  /// the question being asked is "did the catalogue leave this blank".
  bool get _needsPriceEntry {
    final product = widget.product;
    final base = product is OrderItem ? product.finalPrice : product.finalPrice;
    return base <= 0;
  }

  @override
  void dispose() {
    _manualDiscountController.dispose();
    _noteController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _discountFocusNode.dispose();
    super.dispose();
  }

  // ─── Variant logic ──────────────────────────────────────────────────────────

  Future<void> _loadExistingVariant(int variantId) async {
    final variantsData = await ref.read(productVariantsProvider(_productId).future);

    for (final vData in variantsData) {
      final variant = vData['variant'];
      if (variant.id != variantId) continue;

      final attributeValues = vData['attributeValues'] as List;
      for (final av in attributeValues) {
        _selectedAttributeValues[av.attributeId] = av.valueId;
      }

      setState(() {
        _selectedVariant = vData;
        _variantPrice = variant.price;
        _variantImageUrl = variant.imageUrl;
        _variantName = variant.name;
      });
      return;
    }
  }

  void _updateSelectedVariant(AsyncValue<List<Map<String, dynamic>>> variantsAsync) {
    variantsAsync.whenData((variantsData) {
      // Auto-clear selections that became incompatible.
      // For each selected attribute, check if its value is still reachable
      // given the other selections.
      bool cleared = true;
      while (cleared) {
        cleared = false;
        for (final attrId in _selectedAttributeValues.keys.toList()) {
          final compatible = _getCompatibleValueIds(attrId, variantsData);
          if (!compatible.contains(_selectedAttributeValues[attrId])) {
            _selectedAttributeValues.remove(attrId);
            cleared = true; // removal may affect other attributes, re-check
          }
        }
      }

      // Now try to find a variant that matches ALL remaining selections
      for (final vData in variantsData) {
        final attributeValues = vData['attributeValues'] as List;
        if (attributeValues.length != _selectedAttributeValues.length) continue;

        final allMatch = _selectedAttributeValues.entries.every((entry) =>
            attributeValues.any(
                  (av) => av.attributeId == entry.key && av.valueId == entry.value,
            ));

        if (allMatch) {
          final variant = vData['variant'];
          setState(() {
            _selectedVariant = vData;
            _variantPrice = variant.price;
            _variantImageUrl = variant.imageUrl;
            _variantName = variant.name;
          });
          return;
        }
      }

      setState(() {
        _selectedVariant = null;
        _variantPrice = null;
        _variantImageUrl = null;
        _variantName = null;
      });
    });
  }

  // ─── Component logic ─────────────────────────────────────────────────────────

  /// Seeds _componentQuantities from [componentsData] for any component not yet
  /// tracked. The initial quantity is max(defaultQuantity, minQuantity) so that
  /// required components always start at their minimum, never below it.
  void _seedComponents(List<dynamic> componentsData,
      Map<int?, ComponentGroupRule> rules, Set<int?> visible) {
    final byGroup = <int?, List<dynamic>>{};
    for (final cd in componentsData) {
      final groupId = cd['component']?.componentGroupId as int?;
      byGroup.putIfAbsent(groupId, () => []).add(cd);
    }

    byGroup.forEach((groupId, members) {
      // A hidden group's defaults are not preselected: they would be billed
      // (or, with charge-on-removal, read as removed) on a line that never
      // offered the group.
      if (!visible.contains(groupId)) return;
      final rule =
          rules[groupId] ?? ComponentGroupRule(groupId: groupId, name: '');
      final seeded = seedGroup(rule, [
        for (final cd in members)
          ComponentSeed(
            componentId: cd['component'].id as int,
            isRequired: cd['isRequired'] as bool,
            minQuantity: cd['minQuantity'] as int,
            defaultQuantity: cd['defaultQuantity'] as int? ?? 0,
          ),
      ]);
      seeded.forEach((componentId, quantity) {
        // Never overwrite what the cashier already touched.
        if (_componentQuantities.containsKey(componentId)) return;
        _componentQuantities[componentId] = quantity;
      });
    });
  }

  Map<int, int?> _groupOfComponent(List<dynamic> componentsData) => {
        for (final cd in componentsData)
          if (cd['component']?.id is int)
            cd['component'].id as int: cd['component']?.componentGroupId as int?,
      };

  /// Groups on screen for the current selection — see [visibleGroupIds].
  Set<int?> _visibleGroups(
          List<dynamic> componentsData, Map<int?, ComponentGroupRule> rules) =>
      visibleGroupIds(
        rules: rules,
        groupOfComponent: _groupOfComponent(componentsData),
        selectedComponentIds: {
          for (final e in _componentQuantities.entries)
            if (e.value > 0) e.key,
        },
      );

  /// Components sitting in a group the current selection hides. Empty until
  /// the rules load, when nothing is conditional yet.
  Set<int> _hiddenComponentIds(List<dynamic> componentsData) {
    final rules =
        ref.read(productComponentGroupRulesProvider(_productId)).valueOrNull;
    if (rules == null) return const {};
    final visible = _visibleGroups(componentsData, rules);
    return {
      for (final e in _groupOfComponent(componentsData).entries)
        if (!visible.contains(e.value)) e.key,
    };
  }

  /// Bring the selection in line with which groups are showing: seed the
  /// defaults of every visible group, and forget everything picked in a
  /// hidden one (Menu -> Seul drops the drink).
  ///
  /// Repeated until stable, because seeding can select a trigger that opens
  /// another group, and dropping a group can close the ones it opened.
  void _syncComponentSelection(
      List<dynamic> componentsData, Map<int?, ComponentGroupRule> rules) {
    final groupOf = _groupOfComponent(componentsData);
    for (var pass = 0; pass <= rules.length; pass++) {
      final before = Map<int, int>.from(_componentQuantities);
      final visible = _visibleGroups(componentsData, rules);
      bool hidden(int id, Object? _) =>
          groupOf.containsKey(id) && !visible.contains(groupOf[id]);
      _componentQuantities.removeWhere(hidden);
      _componentSpecial.removeWhere(hidden);
      _seedComponents(componentsData, rules, visible);

      final stable = before.length == _componentQuantities.length &&
          before.entries
              .every((e) => _componentQuantities[e.key] == e.value);
      if (stable) return;
    }
  }

  /// Adjust a component's quantity by [delta] (+1 or -1), respecting min/max.
  /// For non-required components whose minQuantity is 0, reaching 0 removes
  /// the entry from the map entirely (component is de-selected).
  void _adjustComponent({
    required int componentId,
    required int delta,
    required bool isRequired,
    required int minQuantity,
    required int? maxQuantity,
  }) {
    // Always read the current tracked value; it must already be in the map
    // because _seedComponents / _buildComponentCard guarantee it is seeded
    // before the user can tap.
    final current = _componentQuantities[componentId] ?? minQuantity;
    final next = current + delta;

    if (maxQuantity != null && next > maxQuantity) return;
    if (next < minQuantity) return;

    setState(() {
      if (next == 0 && !isRequired && minQuantity == 0) {
        // _componentQuantities.remove(componentId);
        // _componentSpecial.remove(componentId);
        _componentQuantities[componentId] = next;
      } else {
        _componentQuantities[componentId] = next;
      }
    });
  }

  /// Pick exactly one component out of a SINGLE group, clearing its siblings.
  ///
  /// Tapping the selected one again clears it, which is the only way to back
  /// out of an optional radio group once something has been chosen.
  void _selectExclusive(
      int componentId, List<dynamic> groupComponents, bool required) {
    setState(() {
      final wasSelected = (_componentQuantities[componentId] ?? 0) > 0;
      for (final cd in groupComponents) {
        final id = cd['component']?.id as int?;
        if (id != null) _componentQuantities[id] = 0;
      }
      if (!wasSelected || required) _componentQuantities[componentId] = 1;
    });
  }

  /// Flip one component of a MULTIPLE group on or off. Quantity is always one.
  void _toggleComponent(int componentId) {
    setState(() {
      final on = (_componentQuantities[componentId] ?? 0) > 0;
      _componentQuantities[componentId] = on ? 0 : 1;
    });
  }

  /// The current selection of one group, as pricing input.
  List<ComponentPick> _picksFor(List<dynamic> groupComponents) {
    final picks = <ComponentPick>[];
    for (final cd in groupComponents) {
      final id = cd['component']?.id as int?;
      if (id == null) continue;
      final qty = _componentQuantities[id] ?? 0;
      if (qty <= 0) continue;
      picks.add(ComponentPick(
        componentId: id,
        quantity: qty,
        unitPrice: (cd['defaultPrice'] as double?) ?? 0.0,
      ));
    }
    return picks;
  }

  /// Every option row this line will be billed and sent as, across all
  /// groups, with each group's free allowance already spent.
  ///
  /// The cart, the displayed total and the order line all read from this one
  /// list, so what the customer is shown is what gets sent and what gets
  /// charged. A partly-covered component appears twice: the free units at
  /// 0.00 and the rest at catalogue price.
  List<ChargedComponentLine> _allocatedLines(
      List<dynamic> componentsData, Map<int?, ComponentGroupRule> rules) {
    final byGroup = <int?, List<dynamic>>{};
    for (final cd in componentsData) {
      final groupId = cd['component']?.componentGroupId as int?;
      byGroup.putIfAbsent(groupId, () => []).add(cd);
    }
    final lines = <ChargedComponentLine>[];
    byGroup.forEach((groupId, members) {
      lines.addAll(allocateFreeAllowance(
          _picksFor(members), rules[groupId]?.freeQuantity ?? 0));
    });
    return lines;
  }

  /// Defaults the customer has taken off that are still charged for.
  ///
  /// Only ever non-empty for links the back office flagged. Everything else
  /// behaves as it always has: take the cheese off, pay less.
  List<RemovalCandidate> _removalCandidates(List<dynamic> componentsData) {
    final out = <RemovalCandidate>[];
    // A default in a hidden group was never on offer, so its absence is not a
    // removal: no zero row, no charge.
    final hidden = _hiddenComponentIds(componentsData);
    for (final cd in componentsData) {
      final id = cd['component']?.id as int?;
      if (id == null || hidden.contains(id)) continue;
      final candidate = RemovalCandidate(
        componentId: id,
        defaultQuantity: cd['defaultQuantity'] as int? ?? 0,
        selectedQuantity: _componentQuantities[id] ?? 0,
        unitPrice: (cd['defaultPrice'] as double?) ?? 0.0,
        chargeOnRemoval: cd['chargeOnRemoval'] as bool? ?? false,
      );
      // A flagged link with nothing to charge bills nothing, server-side, so
      // quoting a removal fee here would be a number that never arrives.
      if (candidate.needsExplicitRow && candidate.unitPrice > 0) {
        out.add(candidate);
      }
    }
    return out;
  }

  /// The first group whose selection breaks its own rule, or null.
  GroupValidation? _firstGroupProblem(
      List<dynamic> componentsData, Map<int?, ComponentGroupRule> rules) {
    final byGroup = <int?, List<dynamic>>{};
    for (final cd in componentsData) {
      final groupId = cd['component']?.componentGroupId as int?;
      byGroup.putIfAbsent(groupId, () => []).add(cd);
    }
    final visible = _visibleGroups(componentsData, rules);
    for (final entry in byGroup.entries) {
      final rule = rules[entry.key];
      if (rule == null || !visible.contains(entry.key)) continue;
      final problem = validateGroup(rule, _picksFor(entry.value));
      if (problem != null) return problem;
    }
    return null;
  }

  double _calculateComponentTotal(List<dynamic> componentsData) {
    double total = 0.0;
    for (final entry in _componentQuantities.entries) {
      try {
        final componentData = componentsData.firstWhere(
              (cd) => cd['component']?.id == entry.key,
        );
        final catalogue = (componentData['defaultPrice'] as double?) ?? 0.0;
        // Free-allowance pricing when the rules have loaded, catalogue price
        // otherwise — the cart must never quote more than it charges.
        final rules = ref
            .read(productComponentGroupRulesProvider(_productId))
            .valueOrNull;
        total += rules == null
            ? catalogue * entry.value
            : chargedTotalFor(
                _allocatedLines(componentsData, rules), entry.key);
      } catch (_) {
        continue;
      }
    }
    // Defaults taken off that are still charged for. Added separately from
    // the loop above because the money is owed precisely for the units that
    // are NOT selected, which that loop never visits.
    total += removalChargePerParentUnit(_removalCandidates(componentsData));
    return total;
  }

  // ─── Discount logic ──────────────────────────────────────────────────────────

  double _calculateManualDiscount(double basePrice) {
    final value = double.tryParse(_manualDiscountController.text) ?? 0.0;
    return _isPercentageDiscount ? basePrice * (value / 100) : value;
  }

  void _validateAndUpdateDiscount(String value, double basePrice) {
    setState(() {
      if (value.isEmpty) {
        _discountError = null;
        return;
      }

      final discountValue = double.tryParse(value);
      if (discountValue == null) {
        _discountError = 'Invalid number';
        return;
      }
      if (discountValue < 0) {
        _discountError = 'Cannot be negative';
        return;
      }

      if (_isPercentageDiscount) {
        if (discountValue > 100) {
          _discountError = 'Max 100%';
          _manualDiscountController.text = '100';
          _manualDiscountController.selection =
              TextSelection.collapsed(offset: _manualDiscountController.text.length);
        } else {
          _discountError = null;
        }
      } else {
        final maxDiscount = basePrice - _productDiscount;
        if (discountValue > maxDiscount) {
          _discountError = 'Max ${maxDiscount.toStringAsFixed(2)}';
          _manualDiscountController.text = maxDiscount.toStringAsFixed(2);
          _manualDiscountController.selection =
              TextSelection.collapsed(offset: _manualDiscountController.text.length);
        } else {
          _discountError = null;
        }
      }
    });
  }

  // ─── Save ────────────────────────────────────────────────────────────────────

  void _handleSave(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    if (_isVariantProduct && _selectedVariant == null) {
      SnackBarHelper.showErrorSnackBar(context, ref, l10n.translate('please_select_variant'));
      return;
    }

    // Hard gate. The backend 400s the entire order if a serial-tracked line
    // arrives without a unit, so the sale is stopped here rather than failing
    // later at sync time when the customer has already walked out.
    if (_isSerialTracked && _selectedSerial == null) {
      SnackBarHelper.showErrorSnackBar(
          context, ref, l10n.translate('serial_required'));
      return;
    }

    final rawQuantity =
        double.tryParse(_quantityController.text.replaceAll(',', '.')) ?? 1.0;
    // Time-managed products are a whole count of sessions — the backend rejects
    // a fractional quantity, so round to an integer here.
    // A serial names one physical unit, so the quantity is not the cashier's to
    // choose — selling three means three lines with three serials.
    final quantity = _isSerialTracked
        ? 1.0
        : (_isPlannable
            ? rawQuantity.roundToDouble().clamp(1.0, double.infinity)
            : rawQuantity);
    if (quantity < 1) {
      SnackBarHelper.showErrorSnackBar(context, ref, 'Quantity must be at least 1');
      return;
    }

    // The quantity can be lowered after notes took their share; the main line
    // must still keep at least one unit.
    final splits = _canSplitByNote ? _noteSplits : const <({String note, int quantity})>[];
    final mainQuantity = quantity - splits.fold(0, (sum, s) => sum + s.quantity);
    if (mainQuantity < 1) {
      SnackBarHelper.showErrorSnackBar(
          context, ref, l10n.translate('note_splits_exceed_quantity'));
      return;
    }

    final componentsAsync = ref.read(productComponentsProvider(_productId));
    if (!componentsAsync.hasValue) {
      SnackBarHelper.showWarningSnackBar(
          context, ref, 'Components not loaded yet, please try again');
      return;
    }

    final componentsData = componentsAsync.value!;

    // Validate required components. A hidden group's requirements do not
    // apply — the drink is required only once Menu is picked.
    final hiddenComponents = _hiddenComponentIds(componentsData);
    for (var componentData in componentsData) {
      final component = componentData['component'];
      if (hiddenComponents.contains(component.id)) continue;
      final isRequired = componentData['isRequired'] as bool;
      final minQuantity = componentData['minQuantity'] as int;

      if (isRequired) {
        final currentQty = _componentQuantities[component.id] ?? 0;
        if (currentQty < minQuantity) {
          SnackBarHelper.showErrorSnackBar(
            context,
            ref,
            '${component.name ?? 'Component'} is required (minimum: $minQuantity)',
          );
          return;
        }
      }
    }

    // Validate the group rules — how many of each group, not just whether the
    // individual component was marked required. Caught here as well as in the
    // UI because a rule can change under a dialog that is already open.
    final groupRules =
        ref.read(productComponentGroupRulesProvider(_productId)).valueOrNull;
    if (groupRules != null) {
      final problem = _firstGroupProblem(componentsData, groupRules);
      if (problem != null) {
        final l10n = AppLocalizations.of(context)!;
        final name = problem.rule.name.isEmpty
            ? l10n.translate('components')
            : problem.rule.name;
        SnackBarHelper.showErrorSnackBar(
          context,
          ref,
          problem.problem == GroupProblem.tooFew
              ? '$name: ${l10n.translate('at_least')} ${problem.rule.minSelection} (${problem.selected})'
              : '$name: ${l10n.translate('up_to')} ${problem.rule.maxSelection} (${problem.selected})',
        );
        return;
      }
    }

    // Every option row this line will be billed as, after each group's free
    // allowance. The POS is the pricing authority on its own orders, and a
    // partly-covered option ships as two rows — the free units at 0.00, the
    // rest at catalogue price — because the server stores option prices to two
    // decimals and would round a blended average into a different total than
    // the one printed on the customer's ticket.
    final allocation = groupRules == null
        ? const <ChargedComponentLine>[]
        : _allocatedLines(componentsData, groupRules);

    final selectedComponents = <OrderItemComponent>[];
    for (final line in allocation) {
      if (hiddenComponents.contains(line.componentId)) continue;
      Map<String, dynamic>? row;
      try {
        row = componentsData
            .firstWhere((c) => c['component']?.id == line.componentId);
      } catch (_) {
        continue;
      }
      final comp = row['component'];
      if (comp == null) continue;
      selectedComponents.add(OrderItemComponent(
        componentId: comp.id,
        name: comp.name ?? 'Unknown',
        quantity: line.quantity,
        price: line.unitPrice,
        isSpecial: _componentSpecial[comp.id] ?? false,
      ));
    }

    // Removals: say so explicitly, and carry the money.
    //
    // Two rows, deliberately. The first is the SIGNAL — the component at the
    // quantity actually wanted, zero included — and it is what the server
    // reads to work the charge out; a ticket that simply omits the row bills
    // nothing. The second is a local money row the server never sees: it is
    // dropped from the sync payload, and exists so the cart, the ticket and
    // the customer all quote the figure the server is about to charge.
    for (final candidate in _removalCandidates(componentsData)) {
      Map<String, dynamic>? catalogueRow;
      try {
        catalogueRow = componentsData
            .firstWhere((c) => c['component']?.id == candidate.componentId);
      } catch (_) {
        continue;
      }
      final comp = catalogueRow['component'];
      if (comp == null) continue;
      final name = comp.name ?? 'Unknown';

      for (final row in removalRowsFor(candidate)) {
        selectedComponents.add(OrderItemComponent(
          componentId: row.componentId,
          name: name,
          quantity: row.quantity,
          price: row.price,
          removalCharge: row.removalCharge,
        ));
      }
    }

    // Rules not loaded yet: fall back to catalogue pricing, one row per
    // component, exactly as the dialog behaved before the rules existed.
    for (final entry in groupRules != null
        ? const <MapEntry<int, int>>[]
        : _componentQuantities.entries) {
      if (entry.value <= 0) continue;

      Map<String, dynamic>? componentData;
      try {
        componentData = componentsData.firstWhere(
              (cd) => cd['component']?.id == entry.key,
        );
      } catch (_) {
        continue;
      }

      final component = componentData['component'];
      if (component == null) continue;

      final defaultPrice = (componentData['defaultPrice'] as double?) ?? 0.0;

      selectedComponents.add(OrderItemComponent(
        componentId: component.id,
        name: component.name ?? 'Unknown',
        quantity: entry.value,
        price: defaultPrice,
        isSpecial: _componentSpecial[component.id] ?? false,
      ));
    }

    final baseProductPrice = widget.product is OrderItem
        ? (widget.product as OrderItem).finalPrice
        : widget.product.price;
    final effectiveProductPrice = _customPrice ?? _variantPrice ?? baseProductPrice;
    final selectedComponentTotal = selectedComponents.fold(
        0.0, (sum, c) => sum + c.price * c.quantity);
    final manualDiscount =
        _calculateManualDiscount(effectiveProductPrice + selectedComponentTotal);

    int? variantId;
    String? variantName;
    double? variantPrice;
    double? variantTva;
    String? variantImageUrl;

    if (_selectedVariant != null) {
      final variant = _selectedVariant!['variant'];
      variantId = variant.id;
      variantName = variant.name;
      variantPrice = variant.price;
      variantTva = variant.tvaAmount;
      variantImageUrl = variant.imageUrl;
    }

    Navigator.of(context).pop({
      'components': selectedComponents,
      'serialId': _selectedSerial?.id,
      'serialNumber': _selectedSerial?.serialNumber,
      'discount': _productDiscount,
      'manualDiscount': manualDiscount,
      'note': _noteController.text.isEmpty ? null : _noteController.text,
      'quantity': mainQuantity,
      // Extra lines, identical to this one except for note and quantity.
      'noteSplits': [
        for (final s in splits)
          {'note': s.note, 'quantity': s.quantity.toDouble()},
      ],
      // Manual unit-price override (null unless a permitted user changed it).
      'priceOverride': _customPrice,
      'variantId': variantId,
      'variantName': variantName,
      'variantPrice': variantPrice,
      'variantTva': variantTva,
      'variantImageUrl': variantImageUrl,
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final productName = widget.product is OrderItem
        ? (widget.product as OrderItem).productName
        : widget.product.name;
    final baseProductPrice = widget.product is OrderItem
        // finalPrice, matching what the save path reads a few hundred lines
        // up. NOT subtotalPerItem: that strips the TVA, adds the pre-discount
        // back and folds in the components. Seeding the price box from it meant
        // reopening a 500 line showed 490, and accepting the dialog wrote 490
        // back — the tax falling out of the price a little more on every
        // reopen.
        ? (widget.product as OrderItem).finalPrice
        : widget.product.finalPrice;
    final baseProductImageUrl = widget.product is OrderItem
        ? (widget.product as OrderItem).imageUrl
        : widget.product.imageUrl;

    final basePrice = _variantPrice ?? baseProductPrice;
    // Seed the price field with the current price the first time it renders.
    if (_priceController.text.isEmpty) {
      _priceController.text = basePrice.toStringAsFixed(2);
    }
    // Manual override (permission-gated) wins for display + totals.
    final productPrice = _customPrice ?? basePrice;
    final productImageUrl = _variantImageUrl ?? baseProductImageUrl;

    final variantsAsync =
    _isVariantProduct ? ref.watch(productVariantsProvider(_productId)) : null;
    final attributesAsync =
    _isVariantProduct ? ref.watch(productAttributesProvider(_productId)) : null;

    final componentsAsync = ref.watch(productComponentsProvider(_productId));
    final componentGroupsAsync = ref.watch(componentGroupsProvider);

    final componentRulesAsync =
        ref.watch(productComponentGroupRulesProvider(_productId));

    // Seed only once BOTH the components and the rules governing them are
    // available.
    //
    // Seeding on the components alone raced the rules: the component list
    // comes from a stream that resolves first, so a radio group fell back to
    // the permissive default and every member carrying a default was selected
    // — and because seeding never overwrites what is already tracked, the
    // dialog stayed wrong for as long as it was open. Both providers are
    // watched, so this runs again on the rebuild when the rules land.
    //
    // Re-run on every build, not just the first: picking or dropping a
    // trigger (Menu) shows or hides groups, and their selection follows.
    if (componentsAsync.hasValue && componentRulesAsync.hasValue) {
      _syncComponentSelection(
          componentsAsync.value!, componentRulesAsync.value!);
    }
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.94,
        constraints: BoxConstraints(
          maxWidth: 1320,
          maxHeight: MediaQuery.of(context).size.height * 0.95,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header: product name, image, price, close ──
            _buildHeader(
              context,
              productName: productName,
              productPrice: productPrice,
              productImageUrl: productImageUrl,
              componentsAsync: componentsAsync,
              currencyFormatter: currencyFormatter,
              l10n: l10n,
            ),

            // ── Two-column body ──
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT: Variants, Quantity, Price, Discount, Note.
                  //
                  // Variants live here, inside the scrolling column, rather
                  // than above both columns: up there a product with several
                  // attributes took most of the height and squeezed the
                  // components list down to a line.
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_isVariantProduct && attributesAsync != null)
                            _buildVariantSection(
                                context, attributesAsync, variantsAsync, l10n),
                          _buildLeftPanel(productPrice, l10n, currencyFormatter),
                        ],
                      ),
                    ),
                  ),
                  // Divider
                  Container(
                    width: 1,
                    color: Theme.of(context).dividerColor,
                  ),
                  // RIGHT: Components — or the serial picker. A serial-tracked
                  // product carries no components, so the panel is reused
                  // rather than squeezing a second list onto the dialog.
                  Expanded(
                    flex: 5,
                    child: _isSerialTracked
                        ? SerialPickerPanel(
                            productId: _productId,
                            selectedSerialId: _selectedSerial?.id,
                            excludeSerialIds: _serialsInBasket(),
                            onSelected: (serial) => setState(() {
                              _selectedSerial = serial;
                              // One line per unit — the backend rejects a
                              // serial line with any other quantity.
                              _quantity = 1.0;
                              _quantityController.text = '1';
                            }),
                          )
                        : _buildComponentsPanel(
                            componentsAsync, componentGroupsAsync, l10n),
                  ),
                ],
              ),
            ),

            // ── Footer buttons ──
            Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: AppButtonStyles.textButtonStyle(isLarge: true),
                      child: Text(l10n.translate('cancel')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => _handleSave(context),
                      style: AppButtonStyles.elevatedButtonStyle(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        isLarge: true,
                      ),
                      child: Text(widget.isEditMode
                          ? l10n.translate('update')
                          : l10n.translate('add_to_order')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Left panel: Quantity, Discount, Note, Preview ───────────────────────────

  Widget _buildLeftPanel(double basePrice, AppLocalizations l10n, CurrencyFormatter currencyFormatter) {
    final componentsAsync = ref.watch(productComponentsProvider(_productId));
    final currency = ref.watch(settingsProvider).currency;

    return componentsAsync.when(
      data: (componentsData) {
        final componentTotal = _calculateComponentTotal(componentsData);
        final priceWithComponents = basePrice + componentTotal;
        final maxDiscountValue =
            _isPercentageDiscount ? 100.0 : (priceWithComponents - _productDiscount);

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Quantity ──
              _buildQuantityRow(context, componentsAsync, basePrice, currencyFormatter, l10n),
              const SizedBox(height: 12),

              // ── Unit price override (permission-gated; admins bypass) ──
              PermissionGuard(
                permission: Permissions.ordersItemPrice,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('unit_price'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AdaptiveKeyboardTextField(
                      controller: _priceController,
                      // Retyped, not edited — see [selectAllOnFocus].
                      selectAllOnFocus: true,
                      // A product the catalogue prices at zero is one whose
                      // price is decided at the counter, so the cashier is
                      // here to type it: put the caret in the box rather than
                      // making them find it.
                      autofocus: _needsPriceEntry,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        // Digits + one decimal only → negatives are impossible.
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      decoration: InputDecoration(
                        prefixText: '$currency ',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        setState(() => _customPrice =
                            (parsed == null || parsed < 0) ? null : parsed);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Product discount (read-only) ──
              if (_productDiscount > 0) ...[
                _buildProductDiscountCard(l10n, currencyFormatter),
                const SizedBox(height: 12),
              ],

              // ── Manual discount ──
              PermissionGuard(
                permission: Permissions.manualDiscount,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('discount'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: AdaptiveKeyboardTextField(
                            controller: _manualDiscountController,
                            focusNode: _discountFocusNode,
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'^\d*\.?\d{0,2}')),
                            ],
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              prefixIcon: Icon(_isPercentageDiscount
                                  ? Icons.percent
                                  : Icons.attach_money),
                              hintText: '0.00',
                              suffixText: _isPercentageDiscount ? '%' : currency,
                              errorText: _discountError,
                              helperText: _isPercentageDiscount
                                  ? '${l10n.translate("max")}: 100%'
                                  : '${l10n.translate("max")}: ${currencyFormatter.format(maxDiscountValue > 0 ? maxDiscountValue : 0)}',
                              isDense: true,
                            ),
                            onChanged: (value) =>
                                _validateAndUpdateDiscount(value, priceWithComponents),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<bool>(
                          segments: [
                            ButtonSegment(
                              value: false,
                              label: Text(currency),
                              icon: const Icon(Icons.attach_money, size: 16),
                            ),
                            const ButtonSegment(
                              value: true,
                              label: Text('%'),
                              icon: Icon(Icons.percent, size: 16),
                            ),
                          ],
                          selected: {_isPercentageDiscount},
                          onSelectionChanged: (newSelection) {
                            setState(() {
                              _isPercentageDiscount = newSelection.first;
                              _validateAndUpdateDiscount(
                                  _manualDiscountController.text, priceWithComponents);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),

              // ── Note ──
              _buildNoteSection(l10n),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) =>
          Center(child: Text(l10n.translate('error_loading_components'))),
    );
  }

  Widget _buildProductDiscountCard(AppLocalizations l10n, CurrencyFormatter currencyFormatter) {
    final totalProductDiscount = _productDiscount * _quantity;
    final discountColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.green[400]!
        : Colors.green[700]!;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(Icons.local_offer, size: 20, color: discountColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.translate('built_in_discount'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            Text(
              '-${currencyFormatter.format(totalProductDiscount)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: discountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Right panel: Components ─────────────────────────────────────────────────

  Widget _buildComponentsPanel(
      AsyncValue<List<dynamic>> componentsAsync,
      AsyncValue<List<dynamic>> componentGroupsAsync,
      AppLocalizations l10n,
  ) {
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          child: Row(
            children: [
              Icon(Icons.restaurant_menu, size: 18, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              Text(
                l10n.translate('components'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
        ),
        // Components list
        Expanded(
          child: _buildComponentsList(componentsAsync, componentGroupsAsync, currencyFormatter, l10n),
        ),
      ],
    );
  }

  Widget _buildComponentsList(
      AsyncValue<List<dynamic>> componentsAsync,
      AsyncValue<List<dynamic>> componentGroupsAsync,
      CurrencyFormatter currencyFormatter,
      AppLocalizations l10n,
  ) {
    return componentsAsync.when(
      data: (componentsData) {
        if (componentsData.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.restaurant_menu, size: 48,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
                const SizedBox(height: 8),
                Text(l10n.translate('no_components'),
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          );
        }

        return componentGroupsAsync.when(
          data: (groups) {
            final rules =
                ref.watch(productComponentGroupRulesProvider(_productId))
                        .valueOrNull ??
                    const <int?, ComponentGroupRule>{};
            final Map<int?, List<Map<String, dynamic>>> grouped = {};
            for (var cd in componentsData) {
              final groupId = cd['component']?.componentGroupId as int?;
              grouped.putIfAbsent(groupId, () => []).add(cd);
            }

            // Groups in the order the catalogue puts them in; the ungrouped
            // bucket carries displayOrder 9999 so it always trails. Groups
            // the current selection hides are not shown at all.
            final visible = _visibleGroups(componentsData, rules);
            final orderedIds = grouped.keys.where(visible.contains).toList()
              ..sort((a, b) {
                final ra = rules[a]?.displayOrder ?? 9999;
                final rb = rules[b]?.displayOrder ?? 9999;
                if (ra != rb) return ra.compareTo(rb);
                return (a ?? 1 << 30).compareTo(b ?? 1 << 30);
              });
            final allocation = _allocatedLines(componentsData, rules);

            // Stepping is only a layout of its own once there is more than
            // one group to step between - a single group would gain a step
            // counter and a pair of dead buttons and nothing else.
            final mode =
                ref.watch(settingsProvider).componentGroupDisplayMode;
            if (mode == ComponentGroupDisplayMode.step &&
                orderedIds.length > 1) {
              return _buildComponentSteps(
                groups: groups,
                orderedIds: orderedIds,
                grouped: grouped,
                rules: rules,
                allocation: allocation,
                currencyFormatter: currencyFormatter,
                l10n: l10n,
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: orderedIds.length,
              itemBuilder: (context, index) => _buildGroupSection(
                groups: groups,
                groupId: orderedIds[index],
                groupComponents: grouped[orderedIds[index]]!,
                rule: rules[orderedIds[index]],
                allocation: allocation,
                currencyFormatter: currencyFormatter,
                l10n: l10n,
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text('Error: $error')),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => const Center(child: Text('Error.')),
    );
  }

  // ─── Header ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(
      BuildContext context, {
        required String productName,
        required double productPrice,
        required String? productImageUrl,
        required AsyncValue<List<dynamic>> componentsAsync,
        required CurrencyFormatter currencyFormatter,
        required AppLocalizations l10n,
      }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Row(
        children: [
          if (productImageUrl != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                productImageUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _variantName ?? productName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_variantName != null)
                  Text(
                    productName,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                const SizedBox(height: 2),
                componentsAsync.maybeWhen(
                  data: (componentsData) {
                    final componentTotal = _calculateComponentTotal(componentsData);
                    // The header is the only price summary left, so it
                    // carries the manual discount the old preview card showed.
                    final manualDiscount =
                        _calculateManualDiscount(productPrice + componentTotal);
                    final total =
                        (productPrice + componentTotal - manualDiscount) * _quantity;
                    return Text(
                      '${currencyFormatter.format(productPrice)}${componentTotal > 0 ? '  +${currencyFormatter.format(componentTotal)}' : ''}${manualDiscount > 0 ? '  −${currencyFormatter.format(manualDiscount)}' : ''}  ×${_fmtQtyLocal(_quantity)}  =  ${currencyFormatter.format(total)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    );
                  },
                  orElse: () => Text(
                    currencyFormatter.format(productPrice),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: l10n.translate('close'),
          ),
        ],
      ),
    );
  }

  // ─── Quantity row ────────────────────────────────────────────────────────────

  Widget _buildQuantityRow(
      BuildContext context,
      AsyncValue<List<dynamic>> componentsAsync,
      double productPrice,
      CurrencyFormatter currencyFormatter,
      AppLocalizations l10n,
      ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final disabledColor = onSurface.withValues(alpha: 0.3);

    return Row(
      children: [
        Text(
          '${l10n.translate("quantity")}:',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
        ),
        const SizedBox(width: 8),
        ...[
          // Bumped tap targets to 48×48 (Material touch-target spec) — the
          // previous EdgeInsets.zero + empty constraints shrank these to the
          // icon's intrinsic 30px, which is fiddly on a touchscreen.
          IconButton(
            onPressed: _quantity > 1
                ? () => setState(() {
                      _quantity -= 1;
                      _quantityController.text = _fmtQtyLocal(_quantity);
                    })
                : null,
            icon: Icon(
              Icons.remove_circle,
              color: _quantity > 1
                  ? Theme.of(context).colorScheme.error
                  : disabledColor,
              size: 34,
            ),
            iconSize: 34,
            visualDensity: VisualDensity.comfortable,
          ),
          SizedBox(
            width: 80,
            child: AdaptiveKeyboardTextField(
              controller: _quantityController,
              selectAllOnFocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: onSurface,
              ),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
              ),
              onChanged: (value) {
                final parsed = double.tryParse(value.replaceAll(',', '.'));
                if (parsed != null && parsed > 0) {
                  // Time-managed services are a whole count — keep qty integer.
                  setState(() => _quantity =
                      _isPlannable ? parsed.roundToDouble() : parsed);
                }
              },
            ),
          ),
          IconButton(
            onPressed: () => setState(() {
              _quantity += 1;
              _quantityController.text = _fmtQtyLocal(_quantity);
            }),
            icon: Icon(Icons.add_circle,
                color: Theme.of(context).primaryColor, size: 34),
            iconSize: 34,
            visualDensity: VisualDensity.comfortable,
          ),
        ],
        // Unit of measure beside the quantity (defaults to "pcs").
        const SizedBox(width: 8),
        Text(
          _unitLabel(),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  /// The product's unit label for display, defaulting to "pcs" when unset.
  String _unitLabel() {
    final u = _unitName?.trim();
    return (u == null || u.isEmpty) ? 'pcs' : u;
  }

  // ─── Variant section ─────────────────────────────────────────────────────────

  /// For a given [attributeId], return the set of valueIds that are compatible
  /// with the currently selected values of all *other* attributes.
  ///
  /// A valueId is compatible if at least one active variant exists that has:
  ///  - that (attributeId, valueId) pair, AND
  ///  - every other currently-selected (otherAttributeId, otherValueId) pair.
  ///
  /// If no other attributes have been selected yet, all values are compatible.
  Set<int> _getCompatibleValueIds(
      int attributeId,
      List<Map<String, dynamic>> variantsData,
      ) {
    // Selections for attributes OTHER than the one we're checking
    final otherSelections = Map<int, int>.from(_selectedAttributeValues)
      ..remove(attributeId);

    // If nothing else is selected, everything is compatible
    if (otherSelections.isEmpty) {
      final allValueIds = <int>{};
      for (final vData in variantsData) {
        final avList = vData['attributeValues'] as List;
        for (final av in avList) {
          if (av.attributeId == attributeId) {
            allValueIds.add(av.valueId as int);
          }
        }
      }
      return allValueIds;
    }

    final compatible = <int>{};

    for (final vData in variantsData) {
      final avList = vData['attributeValues'] as List;

      // Check if this variant matches ALL other selected attributes
      final matchesOthers = otherSelections.entries.every((sel) =>
          avList.any((av) => av.attributeId == sel.key && av.valueId == sel.value));

      if (!matchesOthers) continue;

      // It does — so every value this variant has for [attributeId] is compatible
      for (final av in avList) {
        if (av.attributeId == attributeId) {
          compatible.add(av.valueId as int);
        }
      }
    }

    return compatible;
  }

  Widget _buildVariantSection(
      BuildContext context,
      AsyncValue<List<Map<String, dynamic>>> attributesAsync,
      AsyncValue<List<Map<String, dynamic>>>? variantsAsync,
      AppLocalizations l10n,
      ) {
    return attributesAsync.when(
      data: (attributes) {
        if (attributes.isEmpty) return const SizedBox.shrink();

        // Pre-compute compatible values for each attribute using variant data
        final variantsData = variantsAsync?.valueOrNull ?? [];

        final theme = Theme.of(context);

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title row uses Wrap so the "required" badge drops to a new
                  // line on narrow widths instead of overflowing the dialog.
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.style,
                              size: 20, color: theme.colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            l10n.translate('select_variant'),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      if (_selectedVariant == null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            l10n.translate('required'),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...attributes.map<Widget>((attr) {
                    final attributeId = attr['attributeId'] as int;
                    final attributeName = attr['attributeName'] as String;
                    final values = attr['values'] as List<Map<String, dynamic>>;
                    final selectedValue =
                        _selectedAttributeValues[attributeId];

                    final compatibleIds = variantsData.isNotEmpty
                        ? _getCompatibleValueIds(attributeId, variantsData)
                        : values.map((v) => v['valueId'] as int).toSet();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            attributeName,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Wrap (vs horizontal scroll) lets all values stay
                          // visible without needing a swipe gesture, which
                          // is the touch-screen win.
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: values.map((v) {
                              final valueId = v['valueId'] as int;
                              final valueName = v['value'] as String;
                              final isSelected = selectedValue == valueId;
                              final isCompatible =
                                  compatibleIds.contains(valueId);

                              return _VariantValueChip(
                                label: valueName,
                                selected: isSelected,
                                compatible: isCompatible,
                                onTap: isCompatible
                                    ? () {
                                        setState(() =>
                                            _selectedAttributeValues[
                                                attributeId] = valueId);
                                        _updateSelectedVariant(variantsAsync!);
                                      }
                                    : null,
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
        );
      },
      loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // ─── Component group header ──────────────────────────────────────────────────

  /// The group's name, its colour, and what it is asking of the cashier.
  ///
  /// The rule is stated in words rather than left to be discovered by a
  /// rejected confirm: "pick 1", "up to 3", "2 free". The live count next to
  /// it turns red only once the selection actually breaks the rule.
  /// One group: its header and its option cards. Shared by both layouts, so
  /// a card behaves identically whichever one is switched on.
  Widget _buildGroupSection({
    required List<dynamic> groups,
    required int? groupId,
    required List<dynamic> groupComponents,
    required ComponentGroupRule? rule,
    required List<ChargedComponentLine> allocation,
    required CurrencyFormatter currencyFormatter,
    required AppLocalizations l10n,
  }) {
    final group = groupId != null
        ? groups.cast<dynamic>().firstWhere(
              (g) => g.id == groupId,
              orElse: () => null,
            )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group != null)
          _buildGroupHeader(group.name as String, rule, groupComponents, l10n),
        ...groupComponents.map((cd) => _buildComponentCard(
              cd,
              currencyFormatter,
              l10n,
              rule: rule,
              groupComponents: groupComponents,
              allocation: allocation,
            )),
      ],
    );
  }

  /// [ComponentGroupDisplayMode.step]: one group on screen at a time.
  ///
  /// The numbered pills are navigation and progress at once - a group that
  /// still breaks its own rule stays red wherever the cashier is, so what is
  /// outstanding is visible without walking back through every step. They do
  /// not gate movement: [_handleSave] is the gate, and blocking Next would
  /// only make a group that is optional-but-wrong impossible to leave.
  Widget _buildComponentSteps({
    required List<dynamic> groups,
    required List<int?> orderedIds,
    required Map<int?, List<Map<String, dynamic>>> grouped,
    required Map<int?, ComponentGroupRule> rules,
    required List<ChargedComponentLine> allocation,
    required CurrencyFormatter currencyFormatter,
    required AppLocalizations l10n,
  }) {
    final theme = Theme.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final step = _groupStep.clamp(0, orderedIds.length - 1);
    final groupId = orderedIds[step];

    final problems = <int?, GroupValidation?>{
      for (final id in orderedIds)
        id: rules[id] == null
            ? null
            : validateGroup(rules[id]!, _picksFor(grouped[id]!)),
    };
    final outstanding = problems.values.where((p) => p != null).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // -- Step pills: tap to jump straight to a group --
        SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: orderedIds.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final isCurrent = i == step;
              final bad = problems[orderedIds[i]] != null;
              final color =
                  bad ? theme.colorScheme.error : theme.primaryColor;
              return InkWell(
                onTap: () => setState(() => _groupStep = i),
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? color.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isCurrent || bad ? color : theme.dividerColor,
                      width: isCurrent ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontWeight:
                          isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCurrent || bad
                          ? color
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // -- Where we are, and what is still outstanding elsewhere --
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                l10n
                    .translate('step_of')
                    .replaceAll('{0}', '${step + 1}')
                    .replaceAll('{1}', '${orderedIds.length}'),
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (outstanding > 0)
                Flexible(
                  child: Text(
                    l10n
                        .translate('incomplete_groups_remaining')
                        .replaceAll('{0}', '$outstanding'),
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.error,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),

        // -- The one group on screen --
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            children: [
              _buildGroupSection(
                groups: groups,
                groupId: groupId,
                groupComponents: grouped[groupId]!,
                rule: rules[groupId],
                allocation: allocation,
                currencyFormatter: currencyFormatter,
                l10n: l10n,
              ),
            ],
          ),
        ),

        // -- Back / Next --
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: step == 0
                      ? null
                      : () => setState(() => _groupStep = step - 1),
                  icon:
                      Icon(rtl ? Icons.chevron_right : Icons.chevron_left),
                  label: Text(l10n.translate('back')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: step >= orderedIds.length - 1
                      ? null
                      : () => setState(() => _groupStep = step + 1),
                  icon:
                      Icon(rtl ? Icons.chevron_left : Icons.chevron_right),
                  label: Text(l10n.translate('next')),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGroupHeader(
    String name,
    ComponentGroupRule? rule,
    List<dynamic> groupComponents,
    AppLocalizations l10n,
  ) {
    final theme = Theme.of(context);
    final picks = _picksFor(groupComponents);
    final units = selectedUnits(picks);
    final problem = rule == null ? null : validateGroup(rule, picks);

    final hints = <String>[];
    if (rule != null) {
      if (rule.minSelection > 0) {
        hints.add(rule.minSelection == rule.maxSelection
            ? '${l10n.translate('choose')} ${rule.minSelection}'
            : '${l10n.translate('at_least')} ${rule.minSelection}');
      }
      if (rule.maxSelection != null && rule.maxSelection != rule.minSelection) {
        hints.add('${l10n.translate('up_to')} ${rule.maxSelection}');
      }
      if (rule.freeQuantity > 0) {
        hints.add('${rule.freeQuantity} ${l10n.translate('free_included')}');
      }
    }

    Color? swatch;
    final raw = rule?.color;
    if (raw != null && raw.startsWith('#') && raw.length >= 7) {
      final parsed = int.tryParse(raw.substring(1, 7), radix: 16);
      if (parsed != null) swatch = Color(0xFF000000 | parsed);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          if (swatch != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: swatch, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (rule?.isRequired ?? false) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                l10n.translate('required').toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ],
          const Spacer(),
          if (hints.isNotEmpty)
            Text(
              hints.join(' · '),
              style: TextStyle(
                fontSize: 12,
                color: problem != null
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface.withValues(alpha: 0.55),
                fontWeight:
                    problem != null ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          if (hints.isNotEmpty && units > 0) ...[
            const SizedBox(width: 6),
            Text(
              '($units)',
              style: TextStyle(
                fontSize: 12,
                color: problem != null
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Component card ──────────────────────────────────────────────────────────

  Widget _buildComponentCard(
      Map<String, dynamic> componentData,
      CurrencyFormatter currencyFormatter,
      AppLocalizations l10n, {
      ComponentGroupRule? rule,
      List<dynamic> groupComponents = const [],
      List<ChargedComponentLine> allocation = const [],
      }) {
    final component = componentData['component'];
    final isRequired = componentData['isRequired'] as bool;
    final minQuantity = componentData['minQuantity'] as int;
    final defaultPrice = componentData['defaultPrice'] as double? ?? 0.0;

    // How this group is picked from. Absent rules mean the old permissive
    // behaviour: steppers, no group ceiling.
    final selectionType = rule?.selectionType ?? ComponentSelectionType.quantity;
    final isStepper = selectionType == ComponentSelectionType.quantity;

    // 0 from the server means unbounded. SINGLE and MULTIPLE are one-each
    // whatever the per-component bound says.
    final maxQuantity = isStepper
        ? effectiveMaxQuantity(componentData['maxQuantity'] as int?)
        : 1;

    // Seeding runs earlier in this same build pass, so the map already holds
    // every component that should start selected. Absent means not chosen —
    // and it must, because seeding deliberately leaves out the members of a
    // radio group it did not pick. Re-deriving a quantity here from
    // isRequired/defaultQuantity ignored the group rules and drew every
    // defaulted option as selected.
    final quantity = _componentQuantities[component.id] ?? 0;
    final selected = quantity > 0;

    // A group that has hit its ceiling stops accepting more, rather than
    // letting the cashier build a selection that will be refused on confirm.
    final groupMax = rule?.maxSelection;
    final groupFull = groupMax != null &&
        selectedUnits(_picksFor(groupComponents)) >= groupMax;

    final canDecrement = quantity > minQuantity;
    final canIncrement = (maxQuantity == null || quantity < maxQuantity) &&
        (!groupFull || quantity > 0);

    void decrement() => _adjustComponent(
      componentId: component.id,
      delta: -1,
      isRequired: isRequired,
      minQuantity: minQuantity,
      maxQuantity: maxQuantity,
    );

    void increment() => _adjustComponent(
      componentId: component.id,
      delta: 1,
      isRequired: isRequired,
      minQuantity: minQuantity,
      maxQuantity: maxQuantity,
    );

    // Whole-card tap for the two pick-one-each types. Selecting inside a full
    // MULTIPLE group is blocked; deselecting never is.
    void toggle() {
      if (selectionType == ComponentSelectionType.single) {
        _selectExclusive(
            component.id, groupComponents, rule?.isRequired ?? false);
      } else {
        if (!selected && groupFull) return;
        _toggleComponent(component.id);
      }
    }

    // What this component actually costs for one parent unit once the group's
    // free allowance is spent, and how many of its units that covered.
    final componentId = component.id as int;
    final freeUnits = freeUnitsFor(allocation, componentId);
    final chargedTotal = chargedTotalFor(allocation, componentId);
    final discounted = selected && freeUnits > 0;

    return GestureDetector(
      onTap: isStepper ? null : toggle,
      child: Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isRequired ? 3 : 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Decrement, or the tick / radio dot that replaces it.
            if (isStepper)
              _componentButton(
                icon: Icons.remove,
                active: canDecrement,
                activeColor: Theme.of(context).colorScheme.error,
                onTap: canDecrement ? decrement : null,
              )
            else
              Icon(
                selectionType == ComponentSelectionType.single
                    ? (selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked)
                    : (selected
                        ? Icons.check_box
                        : Icons.check_box_outline_blank),
                size: 30,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: groupFull ? 0.2 : 0.45),
              ),
            const SizedBox(width: 10),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          component.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isRequired) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.translate('required').toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // A discount option carries a negative catalogue price.
                      // Guarding on `> 0` printed nothing at all for one, so the
                      // cashier had no way to see what it took off.
                      if (defaultPrice != 0)
                        Text(
                          '${defaultPrice > 0 ? '+' : '-'}'
                          '${currencyFormatter.format(defaultPrice.abs())}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            decoration:
                                discounted ? TextDecoration.lineThrough : null,
                            color: discounted
                                ? Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.45)
                                : defaultPrice < 0
                                    // Same colour a discount gets in the price
                                    // preview below, so it reads as money off.
                                    ? Theme.of(context).colorScheme.error
                                    : (Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.green[400]
                                        : Colors.green[700]),
                          ),
                        ),
                      if (discounted) ...[
                        const SizedBox(width: 6),
                        Text(
                          chargedTotal <= 0
                              ? l10n.translate('free_included').toUpperCase()
                              : '+${currencyFormatter.format(chargedTotal)}'
                                  ' ($freeUnits ${l10n.translate('free_included')})',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                      if (defaultPrice != 0) const SizedBox(width: 8),
                      if (isStepper)
                        Text(
                          '$minQuantity–${maxQuantity ?? '∞'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            if (isStepper) ...[
              // Quantity badge
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2),
                ),
                child: Center(
                  child: Text(
                    quantity.toString(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Increment button
              _componentButton(
                icon: Icons.add,
                active: canIncrement,
                activeColor: Theme.of(context).brightness == Brightness.dark
                    ? Colors.green[400]!
                    : Colors.green[700]!,
                onTap: canIncrement ? increment : null,
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }

  Widget _componentButton({
    required IconData icon,
    required bool active,
    required Color activeColor,
    VoidCallback? onTap,
  }) {
    final disabledColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.25);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.12)
              : disabledColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: active ? activeColor : disabledColor, size: 22),
      ),
    );
  }

  // ─── Note + note splits ──────────────────────────────────────────────────────

  Widget _buildNoteSection(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final hasSplits = _canSplitByNote && _noteSplits.isNotEmpty;
    final overSplit = hasSplits && _mainQuantity < 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.translate('note'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        AdaptiveKeyboardTextField(
          controller: _noteController,
          decoration: InputDecoration(
            labelText: l10n.translate('add_note'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.note),
            // With splits on screen, say how many units this note still holds.
            suffixText: hasSplits ? '×${_fmtQtyLocal(_mainQuantity)}' : null,
            suffixStyle: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: overSplit ? scheme.error : scheme.primary,
            ),
            errorText:
                overSplit ? l10n.translate('note_splits_exceed_quantity') : null,
            isDense: true,
          ),
          maxLines: 2,
        ),
        if (hasSplits)
          for (var i = 0; i < _noteSplits.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _buildNoteSplitTile(i, l10n),
            ),
        if (_noteWritten && _canSplitByNote) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _editNoteSplit(l10n),
            icon: const Icon(Icons.add_comment_outlined),
            label: Text(l10n.translate('add_another_note')),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNoteSplitTile(int index, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final split = _noteSplits[index];

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _editNoteSplit(l10n, index),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '×${split.quantity}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  split.note,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: scheme.onSurface),
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _noteSplits.removeAt(index)),
                icon: Icon(Icons.delete_outline, color: scheme.error),
                tooltip: l10n.translate('delete'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Add a note split, or edit the one at [index].
  Future<void> _editNoteSplit(AppLocalizations l10n, [int? index]) async {
    final existing = index == null ? null : _noteSplits[index];
    // The main line always keeps one unit; a split can take the rest, plus
    // whatever it already holds when it is being edited.
    final available = (_mainQuantity - 1 + (existing?.quantity ?? 0)).floor();
    if (available < 1) {
      SnackBarHelper.showWarningSnackBar(
          context, ref, l10n.translate('note_split_needs_quantity'));
      return;
    }

    final result = await showDialog<({String note, int quantity})>(
      context: context,
      builder: (_) => _NoteSplitDialog(
        initialNote: existing?.note ?? '',
        initialQuantity: (existing?.quantity ?? 1).clamp(1, available),
        maxQuantity: available,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _noteSplits.add(result);
      } else {
        _noteSplits[index] = result;
      }
    });
  }
}

/// Asks for one more note and how many units of the line it applies to.
class _NoteSplitDialog extends StatefulWidget {
  final String initialNote;
  final int initialQuantity;
  final int maxQuantity;

  const _NoteSplitDialog({
    required this.initialNote,
    required this.initialQuantity,
    required this.maxQuantity,
  });

  @override
  State<_NoteSplitDialog> createState() => _NoteSplitDialogState();
}

class _NoteSplitDialogState extends State<_NoteSplitDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialNote);
  late int _quantity = widget.initialQuantity;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final note = _controller.text.trim();
    if (note.isEmpty) return;
    Navigator.of(context).pop((note: note, quantity: _quantity));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(l10n.translate('another_note')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdaptiveKeyboardTextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.translate('note'),
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.note),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '${l10n.translate('quantity')}:',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed:
                      _quantity > 1 ? () => setState(() => _quantity--) : null,
                  icon: const Icon(Icons.remove_circle),
                  color: scheme.error,
                  iconSize: 34,
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '$_quantity',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _quantity < widget.maxQuantity
                      ? () => setState(() => _quantity++)
                      : null,
                  icon: const Icon(Icons.add_circle),
                  color: scheme.primary,
                  iconSize: 34,
                ),
                Text(
                  '/ ${widget.maxQuantity}',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.translate('cancel')),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => ElevatedButton(
            onPressed: value.text.trim().isEmpty ? null : _save,
            child: Text(l10n.translate('save')),
          ),
        ),
      ],
    );
  }
}

/// Large, finger-friendly choice button for a variant attribute value.
/// Replaces the old Material `ChoiceChip` (which was too small for touch and
/// forced a horizontal scroll); these wrap naturally in a [Wrap].
class _VariantValueChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool compatible;
  final VoidCallback? onTap;

  const _VariantValueChip({
    required this.label,
    required this.selected,
    required this.compatible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color borderColor;
    final Color bgColor;
    final Color fgColor;
    if (!compatible) {
      borderColor = theme.colorScheme.outline.withValues(alpha: 0.25);
      bgColor = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
      fgColor = theme.colorScheme.onSurface.withValues(alpha: 0.35);
    } else if (selected) {
      borderColor = theme.colorScheme.primary;
      bgColor = theme.colorScheme.primaryContainer;
      fgColor = theme.colorScheme.onPrimaryContainer;
    } else {
      borderColor = theme.colorScheme.outline.withValues(alpha: 0.5);
      bgColor = theme.colorScheme.surface;
      fgColor = theme.colorScheme.onSurface;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 48, minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: selected ? 2 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                Icon(Icons.check_circle, size: 18, color: fgColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: fgColor,
                  decoration:
                      compatible ? null : TextDecoration.lineThrough,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
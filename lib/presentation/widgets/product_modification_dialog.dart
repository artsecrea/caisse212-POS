import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// intl exports a TextDirection of its own, which collides with the one
// material.dart brings in from dart:ui. Only the formatters are wanted
// here, so the clashing name is dropped at the import.
import 'package:intl/intl.dart' hide TextDirection;
import '../../data/database/app_database.dart';
import '../../providers/booking_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/network_provider.dart';
import '../../providers/resource_providers.dart';
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

/// A slot chosen from the availability sheet.
class _SlotPick {
  final DateTime start;
  final DateTime end;
  final int? waiterId;
  final String? waiterName;
  final int? resourceId;
  const _SlotPick({
    required this.start,
    required this.end,
    this.waiterId,
    this.waiterName,
    this.resourceId,
  });
}

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
  double? _variantTva;
  String? _variantImageUrl;
  String? _variantName;

  // ─── Planning state ──────────────────────────────────────────────────────────
  bool _isPlannable = false;
  int? _planDurationMinutes;
  DateTime? _planStartAt;
  DateTime? _planEndAt;
  int? _planWaiterId;
  String? _planWaiterName;
  int? _planResourceId;
  bool _loadingAvailability = false;

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /// When a plannable product has a start date selected, quantity is locked to 1.
  bool get _isQuantityLocked => _isPlannable && _planStartAt != null;

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
    _noteController = TextEditingController();
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
        _noteController.text = item.note!;
      }
      if (item.variantId != null) {
        _variantName = item.variantName;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadExistingVariant(item.variantId!);
        });
      }
      // Restore planning fields
      _planStartAt = item.planStartAt;
      _planEndAt = item.planEndAt;
      _planWaiterId = item.planWaiterId;
      _planResourceId = item.planResourceId;
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
          _planDurationMinutes = product.planDurationMinutes;
          _unitName = product.unitName;
          if (_planStartAt != null && _planEndAt == null && _planDurationMinutes != null) {
            _planEndAt = _planStartAt!.add(Duration(minutes: _planDurationMinutes!));
          }
          // Lock quantity to 1 if already in plannable+start-set state (edit mode)
          if (_isPlannable && _planStartAt != null) {
            _quantity = 1.0;
            _quantityController.text = '1';
          }
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
        _variantTva = variant.tvaAmount;
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
            _variantTva = variant.tvaAmount;
            _variantImageUrl = variant.imageUrl;
            _variantName = variant.name;
          });
          return;
        }
      }

      setState(() {
        _selectedVariant = null;
        _variantPrice = null;
        _variantTva = null;
        _variantImageUrl = null;
        _variantName = null;
      });
    });
  }

  // ─── Component logic ─────────────────────────────────────────────────────────

  /// Seeds _componentQuantities from [componentsData] for any component not yet
  /// tracked. The initial quantity is max(defaultQuantity, minQuantity) so that
  /// required components always start at their minimum, never below it.
  void _seedComponents(
      List<dynamic> componentsData, Map<int?, ComponentGroupRule> rules) {
    final byGroup = <int?, List<dynamic>>{};
    for (final cd in componentsData) {
      final groupId = cd['component']?.componentGroupId as int?;
      byGroup.putIfAbsent(groupId, () => []).add(cd);
    }

    byGroup.forEach((groupId, members) {
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
    for (final cd in componentsData) {
      final id = cd['component']?.id as int?;
      if (id == null) continue;
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
    for (final entry in byGroup.entries) {
      final rule = rules[entry.key];
      if (rule == null) continue;
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

    final rawQuantity = _isQuantityLocked
        ? 1.0
        : (double.tryParse(_quantityController.text.replaceAll(',', '.')) ?? 1.0);
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

    final componentsAsync = ref.read(productComponentsProvider(_productId));
    if (!componentsAsync.hasValue) {
      SnackBarHelper.showWarningSnackBar(
          context, ref, 'Components not loaded yet, please try again');
      return;
    }

    final componentsData = componentsAsync.value!;

    // Validate required components
    for (var componentData in componentsData) {
      final component = componentData['component'];
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
      'quantity': quantity,
      // Manual unit-price override (null unless a permitted user changed it).
      'priceOverride': _customPrice,
      'variantId': variantId,
      'variantName': variantName,
      'variantPrice': variantPrice,
      'variantTva': variantTva,
      'variantImageUrl': variantImageUrl,
      'planStartAt': _planStartAt,
      'planEndAt': _planEndAt,
      'planWaiterId': _planWaiterId,
      'planResourceId': _planResourceId,
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
    if (componentsAsync.hasValue && componentRulesAsync.hasValue) {
      _seedComponents(componentsAsync.value!, componentRulesAsync.value!);
    }
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        constraints: BoxConstraints(
          maxWidth: 1100,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
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

            // ── Variant selector (if applicable) ──
            if (_isVariantProduct && attributesAsync != null)
              _buildVariantSection(
                  context, attributesAsync, variantsAsync, l10n),

            // ── Two-column body ──
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // LEFT: Discount, Note, Preview
                  Expanded(
                    flex: 4,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _buildLeftPanel(productPrice, l10n, currencyFormatter),
                          // Planning section (only for plannable products)
                          if (_isPlannable) _buildPlanningSection(context, l10n),
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
              padding: const EdgeInsets.all(16),
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

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Quantity ──
              _buildQuantityRow(context, componentsAsync, basePrice, currencyFormatter, l10n),
              const SizedBox(height: 16),

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
              Text(
                l10n.translate('note'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              AdaptiveKeyboardTextField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: l10n.translate('add_note'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.note),
                  isDense: true,
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              // ── Preview ──
              _buildPreviewCard(
                basePrice: basePrice,
                componentTotal: componentTotal,
                priceWithComponents: priceWithComponents,
                currencyFormatter: currencyFormatter,
                l10n: l10n,
              ),
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
            // bucket carries displayOrder 9999 so it always trails.
            final orderedIds = grouped.keys.toList()
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

  /// Touch-friendly combined date + time picker.
  ///
  /// Replaces the two-step Material date-dial + time-dial dialogs with a single
  /// scrolling wheel ([CupertinoDatePicker]) in a bottom sheet — far quicker to
  /// operate on a POS touch screen. Returns the chosen [DateTime], or null if
  /// dismissed. [minimum] clamps the earliest selectable instant (used so an
  /// end time can't precede its start).
  Future<DateTime?> _pickWheelDateTime({
    required BuildContext context,
    required AppLocalizations l10n,
    required DateTime initial,
    DateTime? minimum,
    String? title,
  }) async {
    final theme = Theme.of(context);
    const interval = 5; // minute granularity for the wheel

    // CupertinoDatePicker asserts the initial (and minimum) sit on the minute
    // interval boundary, so snap both to it.
    DateTime snap(DateTime d) =>
        DateTime(d.year, d.month, d.day, d.hour, (d.minute ~/ interval) * interval);

    final minDate = minimum == null ? null : snap(minimum);
    var temp = snap(initial);
    if (minDate != null && temp.isBefore(minDate)) temp = minDate;

    return showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(l10n.translate('cancel')),
                      ),
                      Expanded(
                        child: Text(
                          title ?? '',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, temp),
                        child: Text(
                          l10n.translate('done'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: theme.brightness,
                      textTheme: CupertinoTextThemeData(
                        dateTimePickerTextStyle: theme.textTheme.titleLarge,
                      ),
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.dateAndTime,
                      initialDateTime: temp,
                      minimumDate: minDate,
                      minuteInterval: interval,
                      use24hFormat: MediaQuery.of(ctx).alwaysUse24HourFormat,
                      onDateTimeChanged: (d) => temp = d,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Planning Section ────────────────────────────────────────────────────────

  Widget _buildPlanningSection(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final dateTimeFmt = DateFormat('dd/MM HH:mm');

    Future<void> pickStart() async {
      final picked = await _pickWheelDateTime(
        context: context,
        l10n: l10n,
        initial: _planStartAt ?? DateTime.now(),
        title: l10n.translate('select_start_time'),
      );
      if (picked == null || !context.mounted) return;
      setState(() {
        _planStartAt = picked;
        if (_planDurationMinutes != null) {
          _planEndAt = picked.add(Duration(minutes: _planDurationMinutes!));
        } else if (_planEndAt != null && _planEndAt!.isBefore(picked)) {
          _planEndAt = picked.add(const Duration(hours: 1));
        }
        // Enforce quantity = 1 as soon as a time is selected for plannable product
        if (_isPlannable) {
          _quantity = 1.0;
          _quantityController.text = '1';
        }
      });
    }

    Future<void> pickEnd() async {
      final start = _planStartAt ?? DateTime.now();
      final picked = await _pickWheelDateTime(
        context: context,
        l10n: l10n,
        initial: _planEndAt ?? start.add(const Duration(hours: 1)),
        minimum: start, // end can never precede start
        title: l10n.translate('select_end_time'),
      );
      if (picked == null || !context.mounted) return;
      setState(() => _planEndAt = picked);
    }

    final canSchedule = ref.watch(lastKnownOnlineStatusProvider);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                l10n.translate('planning'),
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
              ),
              const Spacer(),
              if (_planStartAt != null)
                IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: 'Clear planning',
                  onPressed: () => setState(() {
                    _planStartAt = null;
                    _planEndAt = null;
                    _planWaiterId = null;
                    _planWaiterName = null;
                    // Quantity lock lifts when planning is cleared
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_planDurationMinutes == null)
            _durationRequiredBanner(theme, l10n),
          if (_planDurationMinutes != null) ...[
            _availabilityButton(context, l10n),
            const SizedBox(height: 8),
          ],
          // Manual start/end. Disabled offline for the same reason the
          // availability button is: these write the plan fields.
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(_planStartAt != null
                    ? dateTimeFmt.format(_planStartAt!)
                    : l10n.translate('select_start_time')),
                onPressed: canSchedule ? pickStart : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.stop, size: 16),
                label: Text(_planEndAt != null
                    ? dateTimeFmt.format(_planEndAt!)
                    : l10n.translate('select_end_time')),
                onPressed:
                    canSchedule && _planStartAt != null ? pickEnd : null,
              ),
            ),
          ]),
          if (_planStartAt != null && _planEndAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Duration: ${_planEndAt!.difference(_planStartAt!).inMinutes} min'
              '${_planWaiterName != null ? ' · ${l10n.translate('with')} $_planWaiterName' : ''}',
              style: theme.textTheme.bodySmall,
            ),
          ],
          // Resource selector (only shown when the service has an eligible pool)
          const SizedBox(height: 8),
          _buildResourceSelectorForPlan(context, l10n),
          // Waiter selector
          const SizedBox(height: 8),
          _buildWaiterSelectorForPlan(context, l10n),
        ],
      ),
    );
  }

  /// Amber banner: a time-managed service can't be booked until it has a
  /// duration (the availability endpoint 400s otherwise).
  Widget _durationRequiredBanner(ThemeData theme, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        const Icon(Icons.info_outline, size: 16, color: Colors.orange),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            l10n.translate('booking_needs_duration'),
            style: theme.textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }

  /// "Find available slots" — online-only entry point to real availability.
  ///
  /// Offline this is not a degraded mode with a manual fallback, it is closed.
  /// A time picked here becomes `planStartAt` on the line, which the next order
  /// sync would push as a booking — a slot claimed without ever asking the
  /// diary that owns it. Selling the service as a walk-in still works; it just
  /// carries no plan fields.
  Widget _availabilityButton(BuildContext context, AppLocalizations l10n) {
    final online = ref.watch(lastKnownOnlineStatusProvider);
    if (!online) {
      return Row(children: [
        Icon(Icons.cloud_off, size: 15, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(l10n.translate('reconnect_to_book'),
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]);
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonalIcon(
        icon: _loadingAvailability
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.event_available, size: 18),
        label: Text(l10n.translate('find_available_slots')),
        onPressed:
            _loadingAvailability ? null : () => _showAvailabilitySheet(context, l10n),
      ),
    );
  }

  /// Resource dropdown, shown only when this product has an eligible resource
  /// pool. `null` = unassigned. Kept in sync with the availability sheet.
  Widget _buildResourceSelectorForPlan(
      BuildContext context, AppLocalizations l10n) {
    final asyncRes = ref.watch(eligibleResourcesProvider(_productId));
    final resources = asyncRes.valueOrNull ?? const <Resource>[];
    if (resources.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<int?>(
      value: _planResourceId,
      decoration: InputDecoration(
        labelText: l10n.translate('assign_resource'),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        DropdownMenuItem<int?>(
            value: null, child: Text(l10n.translate('unspecified'))),
        ...resources.map((r) => DropdownMenuItem<int?>(
            value: r.id, child: Text(r.name))),
      ],
      onChanged: (v) => setState(() => _planResourceId = v),
    );
  }

  /// Bottom sheet that queries real availability and lets the user pick a slot.
  /// Picking a slot sets start (clamped to `start + duration`), end, waiter,
  /// and — when the service requires one — the resource.
  Future<void> _showAvailabilitySheet(
      BuildContext context, AppLocalizations l10n) async {
    if (_planDurationMinutes == null) return;
    DateTime selectedDate = DateTime(
      (_planStartAt ?? DateTime.now()).year,
      (_planStartAt ?? DateTime.now()).month,
      (_planStartAt ?? DateTime.now()).day,
    );
    int? sheetResourceId = _planResourceId;

    final picked = await showModalBottomSheet<_SlotPick>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (sheetCtx, setSheet) {
          final key = (
            productId: _productId,
            date: selectedDate,
            waiterId: null as int?,
            resourceId: sheetResourceId,
          );
          final async = ref.watch(availabilityProvider(key));
          final fmt = DateFormat('HH:mm');
          final dateFmt = DateFormat('EEE dd/MM');
          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(l10n.translate('available_slots'),
                        style: Theme.of(sheetCtx).textTheme.titleMedium),
                    const Spacer(),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(dateFmt.format(selectedDate)),
                      onPressed: () async {
                        final d = await showDatePicker(
                          context: sheetCtx,
                          initialDate: selectedDate,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 1)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (d != null) {
                          setSheet(() =>
                              selectedDate = DateTime(d.year, d.month, d.day));
                        }
                      },
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Flexible(
                    child: async.when(
                      loading: () => const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator())),
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          e.toString().replaceFirst('Exception: ', ''),
                          style: TextStyle(
                              color: Theme.of(sheetCtx).colorScheme.error),
                        ),
                      ),
                      data: (avail) {
                        // Resource chooser when required and not yet resolved.
                        final needsResource = avail.requiresResource &&
                            sheetResourceId == null &&
                            avail.eligibleResourceIds.isNotEmpty;
                        if (needsResource) {
                          final resList =
                              ref.watch(resourcesByIdProvider);
                          return ListView(
                            shrinkWrap: true,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                    l10n.translate('pick_a_resource_first'),
                                    style: Theme.of(sheetCtx)
                                        .textTheme
                                        .bodySmall),
                              ),
                              ...avail.eligibleResourceIds.map((rid) {
                                final r = resList[rid];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.meeting_room),
                                  title: Text(r?.name ?? 'Resource #$rid'),
                                  onTap: () =>
                                      setSheet(() => sheetResourceId = rid),
                                );
                              }),
                            ],
                          );
                        }
                        if (!avail.hasAnyAvailability) {
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(l10n.translate('no_slots_available')),
                          );
                        }
                        final dur =
                            Duration(minutes: _planDurationMinutes!);
                        return ListView(
                          shrinkWrap: true,
                          children: [
                            for (final c in avail.candidates)
                              if (c.hasAvailability) ...[
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 6),
                                  child: Text(c.waiterName,
                                      style: Theme.of(sheetCtx)
                                          .textTheme
                                          .labelLarge),
                                ),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final iv in c.freeIntervals)
                                      // Offer the interval's start; clamp end to
                                      // start + duration (interval may be longer).
                                      ActionChip(
                                        label: Text(
                                            '${fmt.format(iv.start)} - ${fmt.format(iv.start.add(dur))}'),
                                        onPressed: () => Navigator.of(sheetCtx)
                                            .pop(_SlotPick(
                                          start: iv.start,
                                          end: iv.start.add(dur),
                                          waiterId: c.waiterId,
                                          waiterName: c.waiterName,
                                          resourceId: sheetResourceId ??
                                              avail.resolvedResourceId,
                                        )),
                                      ),
                                  ],
                                ),
                                const Divider(height: 12),
                              ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      _planStartAt = picked.start;
      _planEndAt = picked.end;
      _planWaiterId = picked.waiterId;
      _planWaiterName = picked.waiterName;
      if (picked.resourceId != null) {
        _planResourceId = picked.resourceId;
      }
      _quantity = 1.0;
      _quantityController.text = '1';
    });
  }

  Widget _buildWaiterSelectorForPlan(BuildContext context, AppLocalizations l10n) {
    // `planWaiterId` is a *provider* employee id — a staff profile of its own,
    // and never a waiter: the backend allows one profile per employee and
    // rejects a non-provider outright, so offering waiters here would only
    // produce a 400 at the point of booking.
    final serviceProviders =
        ref.watch(serviceProvidersProvider).valueOrNull ?? const [];
    if (serviceProviders.isEmpty) return const SizedBox.shrink();

    return DropdownButtonFormField<int?>(
      value: _planWaiterId,
      decoration: InputDecoration(
        labelText: l10n.translate('provider'),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      items: [
        DropdownMenuItem<int?>(
            value: null, child: Text(l10n.translate('unspecified'))),
        ...serviceProviders.map((sp) => DropdownMenuItem<int?>(
            value: sp.id, child: Text(providerDisplayName(sp)))),
      ],
      // Left enabled offline on purpose: naming who is cutting the hair claims
      // no slot — there is no time window to conflict over — so a walk-in can
      // still record its provider with the connection down.
      onChanged: (v) => setState(() {
        _planWaiterId = v;
        _planWaiterName = v == null
            ? null
            : providerDisplayName(
                serviceProviders.firstWhere((sp) => sp.id == v));
      }),
    );
  }

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
                    final total = (productPrice + componentTotal) * _quantity;
                    return Text(
                      '${currencyFormatter.format(productPrice)}${componentTotal > 0 ? '  +${currencyFormatter.format(componentTotal)}' : ''}  ×${_fmtQtyLocal(_quantity)}  =  ${currencyFormatter.format(total)}',
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
    final locked = _isQuantityLocked;
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
        if (locked) ...[
          // Locked display: show quantity badge + lock icon, no controls
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(
                  color: Theme.of(context).colorScheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.3),
            ),
            child: Text(
              '1',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Quantity locked to 1 for bookable products',
            child: Icon(Icons.lock, size: 18, color: disabledColor),
          ),
        ] else ...[
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
        // Cap how much vertical space the variant block can claim so a product
        // with many attributes/values can't push the body (components, etc.)
        // off-screen. Past the cap the section scrolls internally.
        final dialogMaxH = MediaQuery.of(context).size.height * 0.9;
        final variantMaxH = (dialogMaxH * 0.45).clamp(180.0, 360.0);

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: variantMaxH),
            child: SingleChildScrollView(
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
            ),
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

  // ─── Preview card ────────────────────────────────────────────────────────────

  Widget _buildPreviewCard({
    required double basePrice,
    required double componentTotal,
    required double priceWithComponents,
    required CurrencyFormatter currencyFormatter,
    required AppLocalizations l10n,
  }) {
    final totalBase = basePrice * _quantity;
    final totalComponents = componentTotal * _quantity;
    final totalProductDiscount = _productDiscount * _quantity;
    final manualDiscount = _calculateManualDiscount(priceWithComponents);
    final finalPrice =
        (priceWithComponents - _productDiscount - manualDiscount) * _quantity;

    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l10n.translate('preview'),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (_quantity > 1) ...[
                  const Spacer(),
                  Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'x${_fmtQtyLocal(_quantity)}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const Divider(),
            _buildPreviewRow(l10n.translate('base_price'), totalBase, currencyFormatter),
            if (totalComponents > 0)
              _buildPreviewRow(
                  l10n.translate('components'), totalComponents, currencyFormatter),
            if (totalProductDiscount > 0)
              _buildPreviewRow(l10n.translate('product_discount'), totalProductDiscount,
                  currencyFormatter,
                  isDiscount: true),
            if (_manualDiscountController.text.isNotEmpty && manualDiscount > 0)
              _buildPreviewRow(l10n.translate('added_discount'),
                  manualDiscount * _quantity, currencyFormatter,
                  isDiscount: true),
            const Divider(),
            _buildPreviewRow(
                l10n.translate('final_price'), finalPrice, currencyFormatter,
                isFinal: true),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRow(
      String label,
      double value,
      CurrencyFormatter currencyFormatter, {
        bool isDiscount = false,
        bool isFinal = false,
      }) {
    final discountColor = Theme.of(context).colorScheme.error;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isFinal ? 16 : 14,
              fontWeight: isFinal ? FontWeight.bold : FontWeight.normal,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          Text(
            '${isDiscount ? '-' : ''}${currencyFormatter.format(value)}',
            style: TextStyle(
              fontSize: isFinal ? 18 : 14,
              fontWeight: isFinal ? FontWeight.bold : FontWeight.w600,
              color: isDiscount
                  ? discountColor
                  : isFinal
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
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
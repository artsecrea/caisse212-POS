import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart' show OnscreenKeyboardTextField;
import 'package:intl/intl.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/order_models.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/button_styles.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';
import 'permission_guard.dart';

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

  late TextEditingController _manualDiscountController;
  late TextEditingController _noteController;
  late TextEditingController _quantityController;
  late FocusNode _discountFocusNode;

  bool _isPercentageDiscount = false;
  double _productDiscount = 0.0;
  double _quantity = 1.0;
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

  // ─── Helpers ────────────────────────────────────────────────────────────────

  /// When a plannable product has a start date selected, quantity is locked to 1.
  bool get _isQuantityLocked => _isPlannable && _planStartAt != null;

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
          _planDurationMinutes = product.planDurationMinutes;
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

  @override
  void dispose() {
    _manualDiscountController.dispose();
    _noteController.dispose();
    _quantityController.dispose();
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
  void _seedComponents(List<dynamic> componentsData) {
    bool hasChanges = false;
    for (final componentData in componentsData) {
      final component = componentData['component'];
      final isRequired = componentData['isRequired'] as bool;
      final minQuantity = componentData['minQuantity'] as int;
      final defaultQuantity = componentData['defaultQuantity'] as int? ?? 0;

      if (_componentQuantities.containsKey(component.id)) continue;

      // Only auto-seed required components or those with a non-zero default.
      if (isRequired || defaultQuantity > 0) {
        // Never start below minQuantity.
        _componentQuantities[component.id] =
        defaultQuantity < minQuantity ? minQuantity : defaultQuantity;
        hasChanges = true;
      }
    }
    if (hasChanges && mounted) setState(() {});
  }

  /// Adjust a component's quantity by [delta] (+1 or -1), respecting min/max.
  /// For non-required components whose minQuantity is 0, reaching 0 removes
  /// the entry from the map entirely (component is de-selected).
  void _adjustComponent({
    required int componentId,
    required int delta,
    required bool isRequired,
    required int minQuantity,
    required int maxQuantity,
  }) {
    // Always read the current tracked value; it must already be in the map
    // because _seedComponents / _buildComponentCard guarantee it is seeded
    // before the user can tap.
    final current = _componentQuantities[componentId] ?? minQuantity;
    final next = current + delta;

    if (next > maxQuantity || next < minQuantity) return;

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

  double _calculateComponentTotal(List<dynamic> componentsData) {
    double total = 0.0;
    for (final entry in _componentQuantities.entries) {
      try {
        final componentData = componentsData.firstWhere(
              (cd) => cd['component']?.id == entry.key,
        );
        final defaultPrice = (componentData['defaultPrice'] as double?) ?? 0.0;
        total += defaultPrice * entry.value;
      } catch (_) {
        continue;
      }
    }
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

    final quantity = _isQuantityLocked ? 1.0 : (double.tryParse(_quantityController.text.replaceAll(',', '.')) ?? 1.0);
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

    // Build selected components list
    final selectedComponents = <OrderItemComponent>[];
    for (final entry in _componentQuantities.entries) {
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
    final effectiveProductPrice = _variantPrice ?? baseProductPrice;
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
      'discount': _productDiscount,
      'manualDiscount': manualDiscount,
      'note': _noteController.text.isEmpty ? null : _noteController.text,
      'quantity': quantity,
      'variantId': variantId,
      'variantName': variantName,
      'variantPrice': variantPrice,
      'variantTva': variantTva,
      'variantImageUrl': variantImageUrl,
      'planStartAt': _planStartAt,
      'planEndAt': _planEndAt,
      'planWaiterId': _planWaiterId,
    });
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final productName = widget.product is OrderItem
        ? (widget.product as OrderItem).productName
        : widget.product.name;
    final baseProductPrice = widget.product is OrderItem
        ? (widget.product as OrderItem).subtotalPerItem
        : widget.product.finalPrice;
    final baseProductImageUrl = widget.product is OrderItem
        ? (widget.product as OrderItem).imageUrl
        : widget.product.imageUrl;

    final productPrice = _variantPrice ?? baseProductPrice;
    final productImageUrl = _variantImageUrl ?? baseProductImageUrl;

    final variantsAsync =
    _isVariantProduct ? ref.watch(productVariantsProvider(_productId)) : null;
    final attributesAsync =
    _isVariantProduct ? ref.watch(productAttributesProvider(_productId)) : null;

    final componentsAsync = ref.watch(productComponentsProvider(_productId));
    final componentGroupsAsync = ref.watch(componentGroupsProvider);

    // Seed component quantities as soon as the provider resolves.
    // ref.listen fires synchronously on the current value and on every change,
    // so components are ready on the very first render rather than after a tap.
    ref.listen<AsyncValue<List<dynamic>>>(
      productComponentsProvider(_productId),
          (_, next) => next.whenData(_seedComponents),
    );
    // Also seed immediately if the value is already available (e.g. cached).
    componentsAsync.whenData(_seedComponents);
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
                  // RIGHT: Components
                  Expanded(
                    flex: 5,
                    child: _buildComponentsPanel(componentsAsync, componentGroupsAsync, l10n),
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
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
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
                          child: OnscreenKeyboardTextField(
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
              TextField(
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
            final Map<int?, List<Map<String, dynamic>>> grouped = {};
            for (var cd in componentsData) {
              final groupId = cd['component']?.componentGroupId as int?;
              grouped.putIfAbsent(groupId, () => []).add(cd);
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: grouped.length,
              itemBuilder: (context, index) {
                final groupId = grouped.keys.elementAt(index);
                final groupComponents = grouped[groupId]!;
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
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                        child: Text(
                          group.name as String,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ...groupComponents.map((cd) =>
                        _buildComponentCard(cd, currencyFormatter, l10n)),
                  ],
                );
              },
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
          // Start time button
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: Text(_planStartAt != null
                    ? dateTimeFmt.format(_planStartAt!)
                    : l10n.translate('select_start_time')),
                onPressed: pickStart,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.stop, size: 16),
                label: Text(_planEndAt != null
                    ? dateTimeFmt.format(_planEndAt!)
                    : l10n.translate('select_end_time')),
                onPressed: _planStartAt != null ? pickEnd : null,
              ),
            ),
          ]),
          if (_planStartAt != null && _planEndAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Duration: ${_planEndAt!.difference(_planStartAt!).inMinutes} min',
              style: theme.textTheme.bodySmall,
            ),
          ],
          // Waiter selector
          const SizedBox(height: 8),
          _buildWaiterSelectorForPlan(context, l10n),
        ],
      ),
    );
  }

  Widget _buildWaiterSelectorForPlan(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Waiter>>(
      future: ref.read(databaseProvider).select(ref.read(databaseProvider).waiters).get(),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
        final waiters = snap.data!;
        return DropdownButtonFormField<int?>(
          value: _planWaiterId,
          decoration: InputDecoration(
            labelText: l10n.translate('assign_waiter'),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: [
            DropdownMenuItem<int?>(value: null, child: Text(l10n.translate('unspecified'))),
            ...waiters.map((w) => DropdownMenuItem<int?>(
                value: w.id,
                child: Text('${w.firstName} ${w.lastName ?? ''}'.trim()))),
          ],
          onChanged: (v) => setState(() {
            _planWaiterId = v;
            _planWaiterName = v == null
                ? null
                : waiters.firstWhere((w) => w.id == v).firstName;
          }),
        );
      },
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
            child: OnscreenKeyboardTextField(
              controller: _quantityController,
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
                  setState(() => _quantity = parsed);
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
      ],
    );
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

  // ─── Component card ──────────────────────────────────────────────────────────

  Widget _buildComponentCard(
      Map<String, dynamic> componentData,
      CurrencyFormatter currencyFormatter,
      AppLocalizations l10n,
      ) {
    final component = componentData['component'];
    final isRequired = componentData['isRequired'] as bool;
    final minQuantity = componentData['minQuantity'] as int;
    final maxQuantity = componentData['maxQuantity'] as int;
    final defaultQuantity = componentData['defaultQuantity'] as int? ?? 0;
    final defaultPrice = componentData['defaultPrice'] as double? ?? 0.0;

    // The map is always seeded before this card renders (via ref.listen in
    // build). Fall back to minQuantity as a safe display default.
    final quantity = _componentQuantities[component.id] ??
        (isRequired || defaultQuantity > 0
            ? (defaultQuantity < minQuantity ? minQuantity : defaultQuantity)
            : 0);

    final canDecrement = quantity > minQuantity;
    final canIncrement = quantity < maxQuantity;

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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isRequired ? 3 : 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Decrement button
            _componentButton(
              icon: Icons.remove,
              active: canDecrement,
              activeColor: Theme.of(context).colorScheme.error,
              onTap: canDecrement ? decrement : null,
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
                      if (defaultPrice > 0)
                        Text(
                          '+${currencyFormatter.format(defaultPrice)}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.green[400]
                                : Colors.green[700],
                          ),
                        ),
                      if (defaultPrice > 0) const SizedBox(width: 8),
                      Text(
                        '$minQuantity–$maxQuantity',
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
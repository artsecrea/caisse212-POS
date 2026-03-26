import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart' show OnscreenKeyboardTextField;
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/order_models.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/button_styles.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';
import 'permission_guard.dart';

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

class _ProductModificationDialogState extends ConsumerState<ProductModificationDialog>
    with SingleTickerProviderStateMixin {
  final Map<int, int> _componentQuantities = {};
  final Map<int, bool> _componentSpecial = {};

  late TextEditingController _manualDiscountController;
  late TextEditingController _noteController;
  late TextEditingController _quantityController;
  late FocusNode _discountFocusNode;
  late TabController _tabController;

  bool _isPercentageDiscount = false;
  double _productDiscount = 0.0;
  int _quantity = 1;
  String? _discountError;

  // Variant selection state
  Map<int, int> _selectedAttributeValues = {};
  Map<String, dynamic>? _selectedVariant;
  double? _variantPrice;
  double? _variantTva;
  String? _variantImageUrl;
  String? _variantName;

  // ─── Helpers ────────────────────────────────────────────────────────────────

  int get _productId => widget.product is OrderItem
      ? (widget.product as OrderItem).productId
      : widget.product.id;

  bool get _isVariantProduct =>
      widget.product is! OrderItem && (widget.product.isVariant ?? false);

  // ─── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _manualDiscountController = TextEditingController();
    _noteController = TextEditingController();
    _quantityController = TextEditingController(text: '1');
    _discountFocusNode = FocusNode();

    if (widget.product is OrderItem) {
      final item = widget.product as OrderItem;
      _productDiscount = item.discount;
      _quantity = item.quantity;
      _quantityController.text = item.quantity.toString();

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
    } else {
      _productDiscount = widget.product.discountAmount ?? 0.0;
      // Seeding happens in build() via ref.listen so it fires as soon as the
      // provider resolves, even on the very first frame.
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
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

    final quantity = int.tryParse(_quantityController.text) ?? 1;
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

    final productPrice = widget.product is OrderItem
        ? (widget.product as OrderItem).finalPrice
        : widget.product.price;
    final manualDiscount = _calculateManualDiscount(productPrice);

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
      child: Container(
        width: 750,
        constraints: const BoxConstraints(maxHeight: 850),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(
              context,
              productName: productName,
              productPrice: productPrice,
              productImageUrl: productImageUrl,
              componentsAsync: componentsAsync,
              currencyFormatter: currencyFormatter,
              l10n: l10n,
            ),

            if (_isVariantProduct && attributesAsync != null)
              _buildVariantSection(
                  context, attributesAsync, variantsAsync, l10n),

            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor:
              Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              indicatorColor: Theme.of(context).primaryColor,
              tabs: [
                Tab(icon: const Icon(Icons.restaurant_menu), text: l10n.translate('components')),
                Tab(
                  icon: const Icon(Icons.attach_money),
                  text: '${l10n.translate("price")} & ${l10n.translate("discounts")}',
                ),
              ],
            ),

            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildComponentsTab(componentsAsync, componentGroupsAsync),
                  _buildPriceDiscountTab(productPrice),
                ],
              ),
            ),

            Padding(
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: productImageUrl != null
                    ? Image.network(
                  productImageUrl,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _placeholderImage(context),
                )
                    : _placeholderImage(context),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: componentsAsync.maybeWhen(
                  data: (componentsData) {
                    final componentTotal = _calculateComponentTotal(componentsData);
                    final priceWithComponents = productPrice + componentTotal;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _variantName ?? productName,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        if (_variantName != null)
                          Text(
                            productName,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          currencyFormatter.format(productPrice),
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (componentTotal > 0) ...[
                          const SizedBox(height: 2),
                          Text(
                            '+${currencyFormatter.format(componentTotal)} ${l10n.translate("components")}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          currencyFormatter.format(priceWithComponents),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    );
                  },
                  orElse: () => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(productName,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(currencyFormatter.format(productPrice),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildQuantityRow(context, componentsAsync, productPrice, currencyFormatter, l10n),
        ],
      ),
    );
  }

  Widget _placeholderImage(BuildContext context) => Container(
    width: 80,
    height: 80,
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: const Icon(Icons.fastfood, size: 40),
  );

  // ─── Quantity row (single definition, no duplication) ────────────────────────

  Widget _buildQuantityRow(
      BuildContext context,
      AsyncValue<List<dynamic>> componentsAsync,
      double productPrice,
      CurrencyFormatter currencyFormatter,
      AppLocalizations l10n,
      ) {
    final componentTotal = componentsAsync.maybeWhen(
      data: (data) => _calculateComponentTotal(data),
      orElse: () => 0.0,
    );
    final totalPrice = (productPrice + componentTotal) * _quantity;

    return Row(
      children: [
        Text(
          '${l10n.translate("quantity")}:',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: _quantity > 1
              ? () => setState(() {
            _quantity--;
            _quantityController.text = _quantity.toString();
          })
              : null,
          icon: Icon(
            Icons.remove_circle,
            color: _quantity > 1 ? Colors.red : Colors.grey,
            size: 32,
          ),
        ),
        SizedBox(
          width: 100,
          child: OnscreenKeyboardTextField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            onChanged: (value) {
              final parsed = int.tryParse(value);
              if (parsed != null && parsed > 0) {
                setState(() => _quantity = parsed);
              }
            },
          ),
        ),
        IconButton(
          onPressed: () => setState(() {
            _quantity++;
            _quantityController.text = _quantity.toString();
          }),
          icon: Icon(Icons.add_circle, color: Theme.of(context).primaryColor, size: 32),
        ),
        const Spacer(),
        Text(
          '${l10n.translate("total")}: ${currencyFormatter.format(totalPrice)}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  // ─── Variant section ─────────────────────────────────────────────────────────

  Widget _buildVariantSection(
      BuildContext context,
      AsyncValue<List<Map<String, dynamic>>> attributesAsync,
      AsyncValue<List<Map<String, dynamic>>>? variantsAsync,
      AppLocalizations l10n,
      ) {
    return attributesAsync.when(
      data: (attributes) {
        if (attributes.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.style, size: 18, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 8),
                  Text(
                    l10n.translate('select_variant'),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                  if (_selectedVariant == null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        l10n.translate('required'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 12,
                children: attributes.map<Widget>((attr) {
                  final attributeId = attr['attributeId'] as int;
                  final attributeName = attr['attributeName'] as String;
                  final values = attr['values'] as List<Map<String, dynamic>>;

                  return SizedBox(
                    width: 200,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attributeName,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 4),
                        DropdownButtonFormField<int>(
                          value: _selectedAttributeValues[attributeId],
                          decoration: InputDecoration(
                            contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                          hint: Text(l10n.translate('select')),
                          items: values
                              .map((v) => DropdownMenuItem<int>(
                            value: v['valueId'] as int,
                            child: Text(v['value'] as String),
                          ))
                              .toList(),
                          onChanged: (valueId) {
                            if (valueId != null) {
                              setState(
                                      () => _selectedAttributeValues[attributeId] = valueId);
                              _updateSelectedVariant(variantsAsync!);
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
      loading: () =>
      const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // ─── Components tab ──────────────────────────────────────────────────────────

  Widget _buildComponentsTab(
      AsyncValue<List<dynamic>> componentsAsync,
      AsyncValue<List<dynamic>> componentGroupsAsync,
      ) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: componentsAsync.when(
        data: (componentsData) {
          if (componentsData.isEmpty) {
            return Center(child: Text(l10n.translate('no_components')));
          }

          return componentGroupsAsync.when(
            data: (groups) {
              // Group components by their componentGroupId
              final Map<int?, List<Map<String, dynamic>>> grouped = {};
              for (var cd in componentsData) {
                final groupId = cd['component']?.componentGroupId as int?;
                grouped.putIfAbsent(groupId, () => []).add(cd);
              }

              return ListView.builder(
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
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Text(
                            group.name as String,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
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
      ),
    );
  }

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
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Decrement button
            _componentButton(
              icon: Icons.remove,
              active: canDecrement,
              activeColor: Colors.red,
              onTap: canDecrement ? decrement : null,
            ),
            const SizedBox(width: 12),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          component.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      if (isRequired) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            l10n.translate('required').toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (defaultPrice > 0)
                        Text(
                          '+${currencyFormatter.format(defaultPrice)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[700],
                          ),
                        ),
                      const SizedBox(width: 12),
                      Text(
                        'Min: $minQuantity || Max: $maxQuantity',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Quantity badge
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border:
                Border.all(color: Theme.of(context).primaryColor, width: 2),
              ),
              child: Center(
                child: Text(
                  quantity.toString(),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Increment button
            _componentButton(
              icon: Icons.add,
              active: canIncrement,
              activeColor: Colors.green,
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
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active
                ? activeColor.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: active ? activeColor : Colors.grey, size: 24),
        ),
      );

  // ─── Price & Discount tab ────────────────────────────────────────────────────

  Widget _buildPriceDiscountTab(double basePrice) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final currency = ref.watch(settingsProvider).currency;
    final componentsAsync = ref.watch(productComponentsProvider(_productId));

    return componentsAsync.when(
      data: (componentsData) {
        final componentTotal = _calculateComponentTotal(componentsData);
        final priceWithComponents = basePrice + componentTotal;
        final totalPriceWithComponents = priceWithComponents * _quantity;
        final totalProductDiscount = _productDiscount * _quantity;
        final maxDiscountValue =
        _isPercentageDiscount ? 100.0 : (priceWithComponents - _productDiscount);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Base price card
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    children: [
                      _priceRow(l10n.translate('base_price') + ' (x1):', basePrice,
                          currencyFormatter),
                      if (componentTotal > 0) ...[
                        const Divider(height: 12),
                        _priceRow(
                          l10n.translate('components') + ' (x1):',
                          componentTotal,
                          currencyFormatter,
                          prefix: '+',
                          valueColor: Theme.of(context).brightness == Brightness.dark
                              ? Colors.green[400]!
                              : Colors.green[700]!,
                        ),
                        const Divider(height: 12),
                        _priceRow(l10n.translate('subtotal') + ' (x1):',
                            priceWithComponents, currencyFormatter,
                            boldValue: true),
                      ],
                      if (_quantity > 1) ...[
                        const Divider(height: 12),
                        _priceRow(
                          '${l10n.translate("total")} (x$_quantity):',
                          totalPriceWithComponents,
                          currencyFormatter,
                          boldLabel: true,
                          boldValue: true,
                          valueSize: 18,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 2),

              // Product discount (read-only)
              if (_productDiscount > 0) ...[
                Text(
                  l10n.translate('product_discount'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.green[900]!.withValues(alpha: 0.3)
                      : Colors.green[50],
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Row(
                      children: [
                        Icon(Icons.local_offer,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.green[400]
                                : Colors.green[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.translate('built_in_discount'),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.green[300]
                                      : Colors.green[900],
                                ),
                              ),
                              if (_quantity > 1)
                                Text(
                                  '${currencyFormatter.format(_productDiscount)} x $_quantity',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.green[400]
                                        : Colors.green[700],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '-${currencyFormatter.format(totalProductDiscount)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.green[400]
                                : Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 2),
              ],

              // Manual discount — permission-gated
              PermissionGuard(
                permission: Permissions.manualDiscount,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate('discount'),
                      style: TextStyle(
                        fontSize: 18,
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
                            ),
                            onChanged: (value) =>
                                _validateAndUpdateDiscount(value, priceWithComponents),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SegmentedButton<bool>(
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
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              // Note
              Text(
                l10n.translate('note'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              TextField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: l10n.translate('add_note'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.note),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 2),

              // Preview card
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
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.orange[900]!.withValues(alpha: 0.3)
          : Colors.orange[50],
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
                      'x$_quantity',
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
    final discountColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.orange[400]!
        : Colors.orange[700]!;

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

  /// Simple helper for the price info card rows.
  Widget _priceRow(
      String label,
      double value,
      CurrencyFormatter fmt, {
        String prefix = '',
        Color? valueColor,
        bool boldLabel = false,
        bool boldValue = false,
        double valueSize = 16,
      }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: boldLabel ? FontWeight.w600 : FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Text(
          '$prefix${fmt.format(value)}',
          style: TextStyle(
            fontSize: valueSize,
            fontWeight: boldValue ? FontWeight.bold : FontWeight.normal,
            color: valueColor ?? Theme.of(context).colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
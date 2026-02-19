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

class _ProductModificationDialogState extends ConsumerState<ProductModificationDialog> with SingleTickerProviderStateMixin {
  final Map<int, int> _componentQuantities = {};
  final Map<int, bool> _componentSpecial = {};

  // Price modification fields
  late TextEditingController _manualDiscountController;
  late TextEditingController _noteController;
  late TextEditingController _quantityController;
  late FocusNode _discountFocusNode;
  bool _isPercentageDiscount = false;
  late TabController _tabController;
  double _productDiscount = 0.0; // Product's built-in discount
  int _quantity = 1;
  String? _discountError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _manualDiscountController = TextEditingController();
    _noteController = TextEditingController();
    _quantityController = TextEditingController(text: '1');
    _discountFocusNode = FocusNode();

    // Get product discount from product data
    if (widget.product is OrderItem) {
      final item = widget.product as OrderItem;
      _productDiscount = item.discount;
      _quantity = item.quantity;
      _quantityController.text = item.quantity.toString();

      // Populate components
      for (var comp in item.components) {
        _componentQuantities[comp.componentId] = comp.quantity;
        _componentSpecial[comp.componentId] = comp.isSpecial;
      }

      // Populate manual discount
      if (item.manualDiscount > 0) {
        _manualDiscountController.text = item.manualDiscount.toStringAsFixed(2);
      }

      // Populate note
      if (item.note != null) {
        _noteController.text = item.note!;
      }
    } else {
      // New product - get discount from product table
      _productDiscount = widget.product.discountAmount ?? 0.0;

      // Initialize required components with their minimum quantities
      // This will be done after the widget builds when we have access to the component data
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _initializeRequiredComponents();
      });
    }
  }

  void _initializeRequiredComponents() {
    final productId = widget.product is OrderItem
        ? (widget.product as OrderItem).productId
        : widget.product.id;

    final componentsAsync = ref.read(productComponentsProvider(productId));

    componentsAsync.whenData((componentsData) {
      bool hasChanges = false;
      for (var componentData in componentsData) {
        final component = componentData['component'];
        final isRequired = componentData['isRequired'] as bool;
        final minQuantity = componentData['minQuantity'] as int;

        // Auto-add required components with minimum quantity if not already added
        if (isRequired && !_componentQuantities.containsKey(component.id)) {
          _componentQuantities[component.id] = minQuantity;
          hasChanges = true;
        }
      }

      if (hasChanges && mounted) {
        setState(() {});
      }
    });
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

  @override
  Widget build(BuildContext context) {
    // Get product details
    final productId = widget.product is OrderItem
        ? (widget.product as OrderItem).productId
        : widget.product.id;
    final productName = widget.product is OrderItem
        ? (widget.product as OrderItem).productName
        : widget.product.name;
    final productPrice = widget.product is OrderItem
        ? (widget.product as OrderItem).subtotalPerItem
        : widget.product.finalPrice;
    final productImageUrl = widget.product is OrderItem
        ? (widget.product as OrderItem).imageUrl
        : widget.product.imageUrl;

    // Get components available for this product
    final componentsAsync = ref.watch(productComponentsProvider(productId));
    final componentGroupsAsync = ref.watch(componentGroupsProvider);
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
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
                      if (productImageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            productImageUrl!,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stack) {
                              return Container(
                                width: 60,
                                height: 60,
                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.fastfood),
                              );
                            },
                          ),
                        ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: componentsAsync.when(
                          data: (componentsData) {
                            // Calculate component total
                            final componentTotal = _calculateComponentTotal(componentsData);
                            final priceWithComponents = productPrice + componentTotal;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  productName,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Base price
                                Text(
                                  currencyFormatter.format(productPrice),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                // Components total if any
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
                                // Total with components
                                Text(
                                  currencyFormatter.format(priceWithComponents),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            );
                          },
                          loading: () => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                productName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currencyFormatter.format(productPrice),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          error: (_, __) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                productName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                currencyFormatter.format(productPrice),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
                  // Quantity Row with on-screen keyboard
                  componentsAsync.when(
                    data: (componentsData) {
                      final componentTotal = _calculateComponentTotal(componentsData);
                      final totalPrice = (productPrice + componentTotal) * _quantity;

                      return Row(
                        children: [
                          Text(
                            '${l10n.translate("quantity")}:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Decrease button
                          IconButton(
                            onPressed: _quantity > 1
                                ? () {
                              setState(() {
                                _quantity--;
                                _quantityController.text = _quantity.toString();
                              });
                            }
                                : null,
                            icon: Icon(
                              Icons.remove_circle,
                              color: _quantity > 1 ? Colors.red : Colors.grey,
                              size: 32,
                            ),
                          ),
                          // Quantity input with on-screen keyboard
                          SizedBox(
                            width: 100,
                            child: OnscreenKeyboardTextField(
                              controller: _quantityController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                isDense: true,
                              ),
                              onChanged: (value) {
                                final parsed = int.tryParse(value);
                                if (parsed != null && parsed > 0) {
                                  setState(() {
                                    _quantity = parsed;
                                  });
                                }
                              },
                            ),
                          ),
                          // Increase button
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _quantity++;
                                _quantityController.text = _quantity.toString();
                              });
                            },
                            icon: Icon(
                              Icons.add_circle,
                              color: Theme.of(context).primaryColor,
                              size: 32,
                            ),
                          ),
                          const Spacer(),
                          // Total for quantity
                          Text(
                            '${l10n.translate("total")}: ${currencyFormatter.format(totalPrice)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      );
                    },
                    loading: () => Row(
                      children: [
                        Text(
                          '${l10n.translate("quantity")}:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Decrease button
                        IconButton(
                          onPressed: _quantity > 1
                              ? () {
                            setState(() {
                              _quantity--;
                              _quantityController.text = _quantity.toString();
                            });
                          }
                              : null,
                          icon: Icon(
                            Icons.remove_circle,
                            color: _quantity > 1 ? Colors.red : Colors.grey,
                            size: 32,
                          ),
                        ),
                        // Quantity input with on-screen keyboard
                        SizedBox(
                          width: 100,
                          child: OnscreenKeyboardTextField(
                            controller: _quantityController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                            ),
                            onChanged: (value) {
                              final parsed = int.tryParse(value);
                              if (parsed != null && parsed > 0) {
                                setState(() {
                                  _quantity = parsed;
                                });
                              }
                            },
                          ),
                        ),
                        // Increase button
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _quantity++;
                              _quantityController.text = _quantity.toString();
                            });
                          },
                          icon: Icon(
                            Icons.add_circle,
                            color: Theme.of(context).primaryColor,
                            size: 32,
                          ),
                        ),
                        const Spacer(),
                        // Total for quantity
                        Text(
                          '${l10n.translate("total")}: ${currencyFormatter.format(productPrice * _quantity)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    error: (_, __) => Row(
                      children: [
                        Text(
                          '${l10n.translate("quantity")}:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Decrease button
                        IconButton(
                          onPressed: _quantity > 1
                              ? () {
                            setState(() {
                              _quantity--;
                              _quantityController.text = _quantity.toString();
                            });
                          }
                              : null,
                          icon: Icon(
                            Icons.remove_circle,
                            color: _quantity > 1 ? Colors.red : Colors.grey,
                            size: 32,
                          ),
                        ),
                        // Quantity input with on-screen keyboard
                        SizedBox(
                          width: 100,
                          child: OnscreenKeyboardTextField(
                            controller: _quantityController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              isDense: true,
                            ),
                            onChanged: (value) {
                              final parsed = int.tryParse(value);
                              if (parsed != null && parsed > 0) {
                                setState(() {
                                  _quantity = parsed;
                                });
                              }
                            },
                          ),
                        ),
                        // Increase button
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _quantity++;
                              _quantityController.text = _quantity.toString();
                            });
                          },
                          icon: Icon(
                            Icons.add_circle,
                            color: Theme.of(context).primaryColor,
                            size: 32,
                          ),
                        ),
                        const Spacer(),
                        // Total for quantity
                        Text(
                          '${l10n.translate("total")}: ${currencyFormatter.format(productPrice * _quantity)}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // TabBar
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              indicatorColor: Theme.of(context).primaryColor,
              tabs: [
                Tab(
                  icon: Icon(Icons.restaurant_menu),
                  text: l10n.translate("components"),
                ),
                Tab(
                  icon: Icon(Icons.attach_money),
                  text: '${l10n.translate("price")} & ${l10n.translate("discounts")}',
                ),
              ],
            ),

            // TabBarView
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Components Tab
                  _buildComponentsTab(componentsAsync, componentGroupsAsync),

                  // Price & Discount Tab
                  _buildPriceDiscountTab(productPrice),
                ],
              ),
            ),

            // Bottom buttons
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    flex: 1,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: AppButtonStyles.textButtonStyle(isLarge: true),
                      child:  Text(l10n.translate("cancel")),
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
                      child: Text(widget.isEditMode ? l10n.translate("update") : l10n.translate("add_to_order")),
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

  Widget _buildComponentsTab(AsyncValue<List<dynamic>> componentsAsync, AsyncValue<List<dynamic>> componentGroupsAsync) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: componentsAsync.when(
        data: (componentsData) {
          if (componentsData.isEmpty) {
            return Center(
              child: Text(l10n.translate("no_notifications")),
            );
          }

          return componentGroupsAsync.when(
            data: (groups) {
              // Group components by their group
              final Map<int?, List<Map<String, dynamic>>> groupedComponents = {};
              for (var componentData in componentsData) {
                final component = componentData['component'];
                final groupId = component?.componentGroupId;
                if (!groupedComponents.containsKey(groupId)) {
                  groupedComponents[groupId] = [];
                }
                groupedComponents[groupId]!.add(componentData);
              }

              return ListView.builder(
                itemCount: groupedComponents.length,
                itemBuilder: (context, groupIndex) {
                  final groupId = groupedComponents.keys.elementAt(groupIndex);
                  final groupComponents = groupedComponents[groupId]!;

                  // Find the group - handle case where it might not exist
                  dynamic group;
                  if (groupId != null) {
                    try {
                      group = groups.firstWhere((g) => g.id == groupId);
                    } catch (e) {
                      group = null;
                    }
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (group != null) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Text(
                            group.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                      ...groupComponents.map((componentData) {
                        final component = componentData['component'];
                        final isRequired = componentData['isRequired'] as bool;
                        final minQuantity = componentData['minQuantity'] as int;
                        final maxQuantity = componentData['maxQuantity'] as int;

                        // Get current quantity for this component
                        // If not in map and is required, initialize it with minQuantity
                        if (isRequired && !_componentQuantities.containsKey(component.id)) {
                          _componentQuantities[component.id] = minQuantity;
                        }
                        final quantity = _componentQuantities[component.id] ?? 0;

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            return GestureDetector(
                              onTapDown: (details) {
                                final cardWidth = constraints.maxWidth;
                                final tapPosition = details.localPosition.dx;
                                
                                // If tapped on right half, add; if left half, subtract
                                if (tapPosition > cardWidth / 2) {
                                  // Right side - Add
                                  if (quantity < maxQuantity) {
                                    setState(() {
                                      _componentQuantities[component.id] = quantity + 1;
                                    });
                                  }
                                } else {
                                  // Left side - Subtract
                                  if (quantity > minQuantity) {
                                    setState(() {
                                      final newQuantity = quantity - 1;
                                      
                                      if (isRequired) {
                                        _componentQuantities[component.id] = newQuantity;
                                      } else {
                                        if (newQuantity > 0) {
                                          _componentQuantities[component.id] = newQuantity;
                                        } else {
                                          _componentQuantities.remove(component.id);
                                          _componentSpecial.remove(component.id);
                                        }
                                      }
                                    });
                                  }
                                }
                              },
                              child: Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                elevation: isRequired ? 3 : 1,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      // Left indicator (subtract zone)
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: quantity > minQuantity
                                              ? Colors.red.withValues(alpha: 0.1)
                                              : Colors.grey.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.remove,
                                          color: quantity > minQuantity ? Colors.red : Colors.grey,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Component info
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
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                                if (isRequired) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.orange,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child:  Text(
                                                      l10n.translate('required').toUpperCase(),
                                                      style: TextStyle(
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
                                                if (component.price > 0)
                                                  Text(
                                                    '+${currencyFormatter.format(component.price)}',
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
                                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Quantity display
                                      Container(
                                        width: 50,
                                        height: 50,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: Theme.of(context).primaryColor,
                                            width: 2,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            quantity.toString(),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 20,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Right indicator (add zone)
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: BoxDecoration(
                                          color: quantity < maxQuantity
                                              ? Colors.green.withValues(alpha: 0.1)
                                              : Colors.grey.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.add,
                                          color: quantity < maxQuantity
                                              ? Colors.green
                                              : Colors.grey,
                                          size: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ],
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text('Error: $error'),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) {
          print(error);
          print(stack);
          return Center(
            child: Text('Error.'),
          );
        },
      ),
    );
  }

  Widget _buildPriceDiscountTab(double basePrice) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final currency = ref.watch(settingsProvider).currency;
    final componentsAsync = ref.watch(productComponentsProvider(
        widget.product is OrderItem
            ? (widget.product as OrderItem).productId
            : widget.product.id
    ));

    return componentsAsync.when(
      data: (componentsData) {
        // Calculate component total
        final componentTotal = _calculateComponentTotal(componentsData);
        final priceWithComponents = basePrice + componentTotal;

        // Calculate total with quantity
        final totalBasePrice = basePrice * _quantity;
        final totalComponentsPrice = componentTotal * _quantity;
        final totalPriceWithComponents = priceWithComponents * _quantity;
        final totalProductDiscount = _productDiscount * _quantity;

        // Calculate max discount value based on type (should be on price with components)
        final maxDiscountValue = _isPercentageDiscount ? 100.0 : (priceWithComponents - _productDiscount);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Base Price Info
              Card(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${l10n.translate("base_price")} (x1):',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            currencyFormatter.format(basePrice),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                      if (componentTotal > 0) ...[
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${l10n.translate("components")} (x1):',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              '+${currencyFormatter.format(componentTotal)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.green[400]
                                    : Colors.green[700],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${l10n.translate("subtotal")} (x1):',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              currencyFormatter.format(priceWithComponents),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (_quantity > 1) ...[
                        const Divider(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${l10n.translate("total")} (x$_quantity):',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                            Text(
                              currencyFormatter.format(totalPriceWithComponents),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ],
                        )
                      ], // Fixed: Added closing bracket for the if statement
                    ],
                  ),
                ), // Fixed: Added closing parenthesis for Padding
              ), // Fixed: Added closing parenthesis for Card

              const SizedBox(height: 2),

              // Product Discount (Read-only)
              if (_productDiscount > 0) ...[
                Text(
                  l10n.translate("product_discount"),
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
                        Icon(
                          Icons.local_offer,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.green[400]
                              : Colors.green[700],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.translate("built_in_discount"),
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

              // Manual Discount Section - Protected by permission
              PermissionGuard(
                permission: Permissions.manualDiscount,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.translate("additional_discount"),
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
                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                            ],
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              prefixIcon: Icon(_isPercentageDiscount ? Icons.percent : Icons.attach_money),
                              hintText: '0.00',
                              suffixText: _isPercentageDiscount ? '%' : currency,
                              errorText: _discountError,
                              helperText: _isPercentageDiscount
                                  ? '${l10n.translate("max")}: 100%'
                                  : '${l10n.translate("max")}: ${currencyFormatter.format(maxDiscountValue > 0 ? maxDiscountValue : 0)}',
                            ),
                            onChanged: (value) {
                              _validateAndUpdateDiscount(value, priceWithComponents);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                value: false,
                                label: Text(currency),
                                icon: Icon(Icons.attach_money, size: 16),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('%'),
                                icon: Icon(Icons.percent, size: 16),
                              ),
                            ],
                            selected: {_isPercentageDiscount},
                            onSelectionChanged: (Set<bool> newSelection) {
                              setState(() {
                                _isPercentageDiscount = newSelection.first;
                                // Re-validate with new type
                                _validateAndUpdateDiscount(_manualDiscountController.text, priceWithComponents);
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

              // Note Section
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
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 2),

              // Preview
              Card(
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      _buildPreviewRow(l10n.translate('base_price'), totalBasePrice, currencyFormatter),
                      if (totalComponentsPrice > 0)
                        _buildPreviewRow(l10n.translate('components'), totalComponentsPrice, currencyFormatter),
                      if (totalProductDiscount > 0)
                        _buildPreviewRow(l10n.translate('product_discount'), totalProductDiscount, currencyFormatter, isDiscount: true),
                      if (_manualDiscountController.text.isNotEmpty && _calculateManualDiscount(priceWithComponents) > 0)
                        _buildPreviewRow(
                            l10n.translate('added_discount'),
                            _calculateManualDiscount(priceWithComponents) * _quantity,
                            currencyFormatter,
                            isDiscount: true
                        ),
                      const Divider(),
                      _buildPreviewRow(
                          l10n.translate('final_price'),
                          (priceWithComponents - _productDiscount - _calculateManualDiscount(priceWithComponents)) * _quantity,
                          currencyFormatter,
                          isFinal: true
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(child: Text(l10n.translate('error_loading_components'))),
    );
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
        // Percentage mode: 0-100
        if (discountValue > 100) {
          _discountError = 'Max 100%';
          // Optionally auto-correct
          _manualDiscountController.text = '100';
          _manualDiscountController.selection = TextSelection.fromPosition(
            TextPosition(offset: _manualDiscountController.text.length),
          );
        } else {
          _discountError = null;
        }
      } else {
        // Fixed amount mode: 0 to (product price - product discount)
        final maxDiscount = basePrice - _productDiscount;
        if (discountValue > maxDiscount) {
          _discountError = 'Max ${maxDiscount.toStringAsFixed(2)}';
          // Optionally auto-correct
          _manualDiscountController.text = maxDiscount.toStringAsFixed(2);
          _manualDiscountController.selection = TextSelection.fromPosition(
            TextPosition(offset: _manualDiscountController.text.length),
          );
        } else {
          _discountError = null;
        }
      }
    });
  }

  void _handleSave(BuildContext context) {
    print('DEBUG: _handleSave called');

    // Validate quantity
    final quantity = int.tryParse(_quantityController.text) ?? 1;
    if (quantity < 1) {
      print('DEBUG: Quantity validation failed: $quantity');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quantity must be at least 1'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Get product ID
    final productId = widget.product is OrderItem
        ? (widget.product as OrderItem).productId
        : widget.product.id;

    print('DEBUG: Product ID: $productId');

    // Get components async data
    final componentsAsync = ref.read(productComponentsProvider(productId));

    // Check if data is available
    if (!componentsAsync.hasValue) {
      print('DEBUG: Components not loaded yet');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Components not loaded yet, please try again'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final componentsData = componentsAsync.value!;
    print('DEBUG: Components loaded: ${componentsData.length} components');

    // Validate required components
    bool hasValidationError = false;
    for (var componentData in componentsData) {
      final component = componentData['component'];
      final isRequired = componentData['isRequired'] as bool;
      final minQuantity = componentData['minQuantity'] as int;

      if (isRequired) {
        final currentQuantity = _componentQuantities[component.id] ?? 0;
        print('DEBUG: Required component ${component.name}: current=$currentQuantity, min=$minQuantity');
        if (currentQuantity < minQuantity) {
          print('DEBUG: Required component validation failed: ${component.name}');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${component.name ?? 'Component'} is required (minimum: $minQuantity)'),
              backgroundColor: Colors.red,
            ),
          );
          hasValidationError = true;
          break;
        }
      }
    }

    if (hasValidationError) return;

    print('DEBUG: Building selected components from ${_componentQuantities.length} entries');

    // Build selected components list
    final selectedComponents = <OrderItemComponent>[];
    try {
      for (final entry in _componentQuantities.entries) {
        print('DEBUG: Processing component ID ${entry.key} with quantity ${entry.value}');

        Map<String, dynamic>? componentData;
        try {
          componentData = componentsData.firstWhere(
            (cd) {
              final comp = cd['component'];
              return comp != null && comp.id == entry.key;
            },
          );
        } catch (e) {
          print('DEBUG: Component not found for ID ${entry.key}');
          componentData = null;
        }

        if (componentData == null || componentData.isEmpty) {
          print('DEBUG: Component data is empty for ID ${entry.key}, skipping');
          continue;
        }

        final component = componentData['component'];
        if (component == null) {
          print('DEBUG: Component is null for ID ${entry.key}, skipping');
          continue;
        }

        final isRequired = componentData['isRequired'] as bool;
        final minQuantity = (componentData['minQuantity'] as int?) ?? 0;
        final componentQuantity = entry.value;

        print('DEBUG: Component ${component.name}: qty=$componentQuantity, min=$minQuantity, required=$isRequired');

        // Add component if:
        // 1. It's required (always include required components)
        // 2. Quantity is greater than 0 (user explicitly selected it)
        // 3. Quantity is greater than minimum (user increased it)
        if (componentQuantity > 0 && (isRequired || componentQuantity != minQuantity)) {
          print('DEBUG: Adding component: ${component.name} x$componentQuantity (required: $isRequired)');
          selectedComponents.add(OrderItemComponent(
            componentId: component.id,
            name: component.name ?? 'Unknown',
            quantity: componentQuantity,
            price: component.price ?? 0.0,
            isSpecial: _componentSpecial[component.id] ?? false,
          ));
        } else {
          print('DEBUG: Skipping component ${component.name}: condition not met (qty>0: ${componentQuantity > 0}, required: $isRequired, qty!=min: ${componentQuantity != minQuantity})');
        }
      }
    } catch (e, stackTrace) {
      print('DEBUG: ERROR in component building: $e');
      print('DEBUG: Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error building components: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('DEBUG: Total selected components: ${selectedComponents.length}');

    // Calculate manual discount
    final productPrice = widget.product is OrderItem
        ? (widget.product as OrderItem).finalPrice
        : widget.product.price;
    final manualDiscount = _calculateManualDiscount(productPrice);

    print('DEBUG: Manual discount: $manualDiscount');
    print('DEBUG: Returning result and closing dialog');

    // Successfully validated, return the result
    Navigator.of(context).pop({
      'components': selectedComponents,
      'discount': _productDiscount, // Product's built-in discount
      'manualDiscount': manualDiscount, // Manual additional discount
      'note': _noteController.text.isEmpty ? null : _noteController.text,
      'quantity': quantity, // Added quantity
    });
  }

  Widget _buildPreviewRow(String label, double value, CurrencyFormatter currencyFormatter, {bool isDiscount = false, bool isFinal = false}) {
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
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? Colors.orange[400]
                      : Colors.orange[700])
                  : isFinal
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  double _calculateManualDiscount(double basePrice) {
    final discountValue = double.tryParse(_manualDiscountController.text) ?? 0.0;
    if (_isPercentageDiscount) {
      return basePrice * (discountValue / 100);
    }
    return discountValue;
  }

  double _calculateComponentTotal(List<dynamic> componentsData) {
    double total = 0.0;

    for (final entry in _componentQuantities.entries) {
      final componentId = entry.key;
      final quantity = entry.value;

      if (quantity > 0) {
        // Find the component data
        try {
          final componentData = componentsData.firstWhere(
            (cd) {
              final comp = cd['component'];
              return comp != null && comp.id == componentId;
            },
          );

          final component = componentData['component'];
          if (component != null && component.price != null) {
            total += component.price * quantity;
          }
        } catch (e) {
          // Component not found, skip
          continue;
        }
      }
    }

    return total;
  }
}


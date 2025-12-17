import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../domain/models/order_models.dart';

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
  bool _isPercentageDiscount = false;
  late TabController _tabController;
  double _productDiscount = 0.0; // Product's built-in discount

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _manualDiscountController = TextEditingController();
    _noteController = TextEditingController();
    
    // Get product discount from product data
    if (widget.product is OrderItem) {
      final item = widget.product as OrderItem;
      _productDiscount = item.discount;

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
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _manualDiscountController.dispose();
    _noteController.dispose();
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
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
              child: Row(
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
                            color: Colors.grey[200],
                            child: const Icon(Icons.fastfood),
                          );
                        },
                      ),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
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
                          '\$${productPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            
            // TabBar
            TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: Theme.of(context).primaryColor,
              tabs: const [
                Tab(
                  icon: Icon(Icons.restaurant_menu),
                  text: 'Components',
                ),
                Tab(
                  icon: Icon(Icons.attach_money),
                  text: 'Price & Discount',
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
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => _handleSave(context),
                      child: Text(widget.isEditMode ? 'Update' : 'Add to Order'),
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

  Widget _buildComponentsTab(AsyncValue componentsAsync, AsyncValue componentGroupsAsync) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: componentsAsync.when(
        data: (components) {
          if (components.isEmpty) {
            return const Center(
              child: Text('No modifications available'),
            );
          }

          return componentGroupsAsync.when(
            data: (groups) {
              // Group components by their group
              final Map<int?, List<dynamic>> groupedComponents = {};
              for (var component in components) {
                final groupId = component.componentGroupId;
                if (!groupedComponents.containsKey(groupId)) {
                  groupedComponents[groupId] = [];
                }
                groupedComponents[groupId]!.add(component);
              }

              return ListView.builder(
                itemCount: groupedComponents.length,
                itemBuilder: (context, groupIndex) {
                  final groupId = groupedComponents.keys.elementAt(groupIndex);
                  final groupComponents = groupedComponents[groupId]!;
                  final group = groupId != null
                      ? groups.cast<dynamic>().firstWhere(
                          (g) => g.id == groupId,
                          orElse: () => null,
                        )
                      : null;

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
                      ...groupComponents.map((component) {
                        final quantity = _componentQuantities[component.id] ?? 0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        component.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (component.price > 0)
                                        Text(
                                          '+\$${component.price.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: quantity > 0
                                          ? () {
                                              setState(() {
                                                _componentQuantities[component.id] = quantity - 1;
                                                if (_componentQuantities[component.id]! <= 0) {
                                                  _componentQuantities.remove(component.id);
                                                  _componentSpecial.remove(component.id);
                                                }
                                              });
                                            }
                                          : null,
                                      icon: const Icon(Icons.remove_circle_outline),
                                    ),
                                    SizedBox(
                                      width: 30,
                                      child: Text(
                                        quantity.toString(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _componentQuantities[component.id] = quantity + 1;
                                        });
                                      },
                                      icon: Icon(
                                        Icons.add_circle,
                                        color: Theme.of(context).primaryColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text('Error loading groups: $error'),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error loading components: $error'),
        ),
      ),
    );
  }

  Widget _buildPriceDiscountTab(double basePrice) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Base Price Info
          Card(
            color: Colors.blue[50],
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Base Price:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '\$${basePrice.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 2),
          
          // Product Discount (Read-only)
          if (_productDiscount > 0) ...[
            const Text(
              'Product Discount',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    Icon(Icons.local_offer, color: Colors.green[700]),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Built-in Discount',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.green[900],
                            ),
                          ),
                          Text(
                            'This discount is included with the product',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '-\$${_productDiscount.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
          ],

          // Manual Discount Section
          const Text(
            'Additional Discount',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Apply an extra discount to this item',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 2),
          
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _manualDiscountController,
                  decoration: InputDecoration(
                    labelText: _isPercentageDiscount ? 'Manual Discount (%)' : 'Manual Discount (\$)',
                    border: const OutlineInputBorder(),
                    prefixIcon: Icon(_isPercentageDiscount ? Icons.percent : Icons.attach_money),
                    hintText: '0.00',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) => setState(() {}),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('\$'),
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
                    });
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Note Section
          const Text(
            'Note',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          
          TextField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Add a note (optional)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.note),
              hintText: 'e.g., No onions, extra sauce',
            ),
            maxLines: 3,
          ),
          
          const SizedBox(height: 2),
          
          // Preview
          Card(
            color: Colors.orange[50],
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Preview',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _buildPreviewRow('Original Price', basePrice),
                  if (_productDiscount > 0)
                    _buildPreviewRow('Product Discount', _productDiscount, isDiscount: true),
                  if (_manualDiscountController.text.isNotEmpty && _calculateManualDiscount(basePrice) > 0)
                    _buildPreviewRow('Manual Discount', _calculateManualDiscount(basePrice), isDiscount: true),
                  const Divider(),
                  _buildPreviewRow(
                    'Final Price',
                    basePrice - _productDiscount - _calculateManualDiscount(basePrice),
                    isFinal: true
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, double value, {bool isDiscount = false, bool isFinal = false}) {
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
            ),
          ),
          Text(
            '${isDiscount ? '-' : ''}\$${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: isFinal ? 18 : 14,
              fontWeight: isFinal ? FontWeight.bold : FontWeight.w600,
              color: isDiscount 
                  ? Colors.orange[700] 
                  : isFinal 
                      ? Theme.of(context).primaryColor 
                      : Colors.black,
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

  void _handleSave(BuildContext context) {
    final componentsAsync = ref.read(componentsProvider);
    componentsAsync.when(
      data: (components) {
        final selectedComponents = <OrderItemComponent>[];
        for (final entry in _componentQuantities.entries) {
          final component = components.firstWhere((c) => c.id == entry.key);
          selectedComponents.add(OrderItemComponent(
            componentId: component.id,
            name: component.name,
            quantity: entry.value,
            price: component.price,
            isSpecial: _componentSpecial[component.id] ?? false,
          ));
        }
        
        // Calculate manual discount
        final productPrice = widget.product is OrderItem
            ? (widget.product as OrderItem).finalPrice 
            : widget.product.price;
        final manualDiscount = _calculateManualDiscount(productPrice);

        Navigator.of(context).pop({
          'components': selectedComponents,
          'discount': _productDiscount, // Product's built-in discount
          'manualDiscount': manualDiscount, // Manual additional discount
          'note': _noteController.text.isEmpty ? null : _noteController.text,
        });
      },
      loading: () {},
      error: (_, __) {},
    );
  }
}


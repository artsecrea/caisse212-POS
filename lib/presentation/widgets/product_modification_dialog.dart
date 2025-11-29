import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../domain/models/order_models.dart';

class ProductModificationDialog extends ConsumerStatefulWidget {
  final dynamic product;

  const ProductModificationDialog({Key? key, required this.product}) : super(key: key);

  @override
  ConsumerState<ProductModificationDialog> createState() => _ProductModificationDialogState();
}

class _ProductModificationDialogState extends ConsumerState<ProductModificationDialog> {
  final Map<int, int> _componentQuantities = {};
  final Map<int, bool> _componentSpecial = {};

  @override
  Widget build(BuildContext context) {
    // Get components available for this product
    final componentsAsync = ref.watch(productComponentsProvider(widget.product.id));
    final componentGroupsAsync = ref.watch(componentGroupsProvider);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.product.imageUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.product.imageUrl!,
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
                        widget.product.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '\$${widget.product.finalPrice.toStringAsFixed(2)}',
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
            const SizedBox(height: 24),
            const Text(
              'Customize your order',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
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
                            ? groups.firstWhere((g) => g.id == groupId, orElse: () => groups.first)
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
                                  margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
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
                              }).toList(),
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
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _componentQuantities.clear();
                        _componentSpecial.clear();
                      });
                    },
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
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
                          Navigator.of(context).pop(selectedComponents);
                        },
                        loading: () {},
                        error: (_, __) {},
                      );
                    },
                    child: const Text('Add to Order'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


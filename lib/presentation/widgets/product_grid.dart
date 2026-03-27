
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/order_models.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';
import 'product_modification_dialog.dart' as dialog;

class ProductGrid extends ConsumerWidget {
  const ProductGrid({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(filteredProductsProvider);
    final showImages = ref.watch(showProductImagesProvider);
    final searchQuery = ref.watch(productSearchQueryProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: productsAsync.when(
        data: (products) {
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    searchQuery.isNotEmpty ? Icons.search_off : Icons.inventory_2_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    searchQuery.isNotEmpty
                        ? 'No products found for "$searchQuery"'
                        : 'No products available',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  if (searchQuery.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        ref.read(productSearchQueryProvider.notifier).state = '';
                      },
                      child: const Text('Clear search'),
                    ),
                  ],
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              mainAxisExtent: showImages ? 200 : 80,
              maxCrossAxisExtent: showImages ? 200 : 150,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return _ProductCard(product: product);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error loading products: $error'),
        ),
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final Product product;

  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showImages = ref.watch(showProductImagesProvider);
    final componentsDataAsync = ref.watch(productComponentsProvider(product.id));

    return GestureDetector(
      onTap: () {
        // Check if product is a variant product - must show dialog to select variant
        final isVariantProduct = product.isVariant;

        if (isVariantProduct) {
          // Variant products MUST go through dialog to select variant
          _showModificationDialog(context, ref);
          return;
        }

        // Check if product has required components
        componentsDataAsync.whenData((componentsData) {
          final hasRequiredComponents = componentsData.any(
            (data) => data['isRequired'] as bool
          );

          if (hasRequiredComponents) {
            // Show dialog for required components
            _showModificationDialog(context, ref);
          } else {
            // Quick add - build default components
            final defaultComponents = <OrderItemComponent>[];

            for (var componentData in componentsData) {
              final component = componentData['component'];
              final defaultQuantity = componentData['defaultQuantity'] as int? ?? 0;
              final defaultPrice = componentData['defaultPrice'] as double? ?? 0.0;

              // Add components with defaultQuantity > 0
              if (defaultQuantity > 0 && component != null) {
                // For default components, we charge the full price
                // Total charge = defaultPrice × defaultQuantity
                defaultComponents.add(OrderItemComponent(
                  componentId: component.id,
                  name: component.name ?? 'Unknown',
                  quantity: defaultQuantity,
                  price: defaultPrice, // Full price per unit
                  isSpecial: false,
                ));
              }
            }

            _addToOrder(context, ref, {
              'components': defaultComponents,
              'discount': product.discountAmount,
              'manualDiscount': 0.0,
              'note': null,
              'quantity': 1,
            });
          }
        });
      },
      onLongPress: () {
        // Show modification dialog
        _showModificationDialog(context, ref);
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
        child: showImages ? _buildWithImage(context,ref) : _buildCompact(context, ref),
      ),
    );
  }

  Widget _buildWithImage(BuildContext context, WidgetRef ref) {
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final componentsDataAsync = ref.watch(productComponentsProvider(product.id));

    return componentsDataAsync.when(
      data: (componentsData) {
        // Calculate display price: base price + (default component prices × default quantities)
        double displayPrice = product.finalPrice;
        for (var componentData in componentsData) {
          final defaultQuantity = componentData['defaultQuantity'] as int? ?? 0;
          final defaultPrice = componentData['defaultPrice'] as double? ?? 0.0;
          displayPrice += (defaultPrice * defaultQuantity);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            child: product.imageUrl != null
                ? CachedNetworkImage(
                    imageUrl: product.imageUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (context, error, stack) {
                      return Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.fastfood,
                          size: 48,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      );
                    },
                  )
                : Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.fastfood,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
        ),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  currencyFormatter.format(displayPrice),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
      },
      loading: () => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(product.name),
            ),
          ),
        ],
      ),
      error: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 3,
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(Icons.fastfood, size: 48),
            ),
          ),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(product.name),
                  Text(currencyFormatter.format(product.finalPrice)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(BuildContext context, WidgetRef ref) {
    final componentsDataAsync = ref.watch(productComponentsProvider(product.id));
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return componentsDataAsync.when(
      data: (componentsData) {
        // Calculate display price: base price + (default component prices × default quantities)
        double displayPrice = product.finalPrice;
        for (var componentData in componentsData) {
          final defaultQuantity = componentData['defaultQuantity'] as int? ?? 0;
          final defaultPrice = componentData['defaultPrice'] as double? ?? 0.0;
          displayPrice += (defaultPrice * defaultQuantity);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  product.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                currencyFormatter.format(displayPrice),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                product.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              currencyFormatter.format(product.finalPrice),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addToOrder(BuildContext context, WidgetRef ref, Map<String, dynamic> modifications) {
    final components = modifications['components'] as List<OrderItemComponent>? ?? [];
    final discount = modifications['discount'] as double? ?? product.discountAmount;
    final manualDiscount = modifications['manualDiscount'] as double? ?? 0.0;
    final note = modifications['note'] as String?;
    final quantity = modifications['quantity'] as int? ?? 1;

    // Variant data
    final variantId = modifications['variantId'] as int?;
    final variantName = modifications['variantName'] as String?;
    final variantPrice = modifications['variantPrice'] as double?;
    final variantTva = modifications['variantTva'] as double?;
    final variantImageUrl = modifications['variantImageUrl'] as String?;

    final orderItem = OrderItem(
      productId: product.id,
      productName: product.name,
      variantId: variantId,
      variantName: variantName,
      imageUrl: variantImageUrl ?? product.imageUrl,
      finalPrice: variantPrice ?? product.finalPrice,
      quantity: quantity,
      components: components,
      tva: variantTva ?? product.tvaAmount,
      discount: discount,
      manualDiscount: manualDiscount,
      note: note,
    );

    ref.read(orderProvider.notifier).addItem(orderItem);

    SnackBarHelper.showSuccessSnackBar(
      context,
      ref,
      '${variantName ?? product.name} added to order',
      duration: const Duration(seconds: 1),
    );
  }

  Future<void> _showModificationDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => dialog.ProductModificationDialog(product: product),
    );

    if (result != null) {
      _addToOrder(context, ref, result);
    }
  }
}


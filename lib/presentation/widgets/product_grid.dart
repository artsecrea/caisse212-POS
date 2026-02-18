
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/order_models.dart';
import '../../utils/currency_formatter.dart';
import 'product_modification_dialog.dart';

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
        // Check if product has required components
        componentsDataAsync.whenData((componentsData) {
          final hasRequiredComponents = componentsData.any(
            (data) => data['isRequired'] as bool
          );

          if (hasRequiredComponents) {
            // Show dialog for required components
            _showModificationDialog(context, ref);
          } else {
            // Quick add - add product to order without modifications
            _addToOrder(context, ref, {
              'components': <OrderItemComponent>[],
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
        child: showImages ? _buildWithImage(context,ref) : _buildCompact(context),
      ),
    );
  }

  Widget _buildWithImage(BuildContext context, WidgetRef ref) {

    final currencyFormatter = ref.watch(currencyFormatterProvider);

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
                  currencyFormatter.format(product.finalPrice),
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
  }

  Widget _buildCompact(BuildContext context) {
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
            '${product.finalPrice.toStringAsFixed(2)} \$',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _addToOrder(BuildContext context, WidgetRef ref, Map<String, dynamic> modifications) {
    final components = modifications['components'] as List<OrderItemComponent>? ?? [];
    final discount = modifications['discount'] as double? ?? product.discountAmount;
    final manualDiscount = modifications['manualDiscount'] as double? ?? 0.0;
    final note = modifications['note'] as String?;
    final quantity = modifications['quantity'] as int? ?? 1;

    final orderItem = OrderItem(
      productId: product.id,
      productName: product.name,
      imageUrl: product.imageUrl,
      finalPrice: product.finalPrice,
      quantity: quantity,
      components: components,
      tva: product.tvaAmount,
      discount: discount,
      manualDiscount: manualDiscount,
      note: note,
    );

    ref.read(orderProvider.notifier).addItem(orderItem);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${product.name} added to order'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showModificationDialog(BuildContext context, WidgetRef ref) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProductModificationDialog(product: product),
    );

    if (result != null) {
      _addToOrder(context, ref, result);
    }
  }
}


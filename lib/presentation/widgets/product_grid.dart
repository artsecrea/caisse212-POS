
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posecrea/data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../domain/models/order_models.dart';
import 'product_modification_dialog.dart';

class ProductGrid extends ConsumerWidget {
  const ProductGrid({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final productsAsync = ref.watch(productsByCategoryProvider(selectedCategory));

    return Container(
      color: Colors.grey[50],
      child: productsAsync.when(
        data: (products) {
          if (products.isEmpty) {
            return const Center(
              child: Text('No products available'),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              mainAxisExtent: 200,
              maxCrossAxisExtent: 200,
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
    return GestureDetector(
      onTap: () {
        // Quick add - add product to order without modifications
        _addToOrder(context, ref, []);
      },
      onLongPress: () {
        // Show modification dialog
        _showModificationDialog(context, ref);
      },
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(0)),
                child: product.imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl : product.imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget : (context, error, stack) {
                          return Container(
                            color: Colors.grey[200],
                            child: Icon(
                              Icons.fastfood,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                          );
                        },
                      )
                    : Container(
                        color: Colors.grey[200],
                        child: Icon(
                          Icons.fastfood,
                          size: 48,
                          color: Colors.grey[400],
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${product.finalPrice.toStringAsFixed(2)} \$',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addToOrder(BuildContext context, WidgetRef ref, List<OrderItemComponent> components) {
    final orderItem = OrderItem(
      productId: product.id,
      productName: product.name,
      imageUrl: product.imageUrl,
      unitPrice: product.finalPrice,
      quantity: 1,
      components: components,
      tva: product.tvaAmount,
      discount: product.discountAmount,

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
    final result = await showDialog<List<OrderItemComponent>>(
      context: context,
      builder: (context) => ProductModificationDialog(product: product),
    );

    if (result != null) {
      _addToOrder(context, ref, result);
    }
  }
}


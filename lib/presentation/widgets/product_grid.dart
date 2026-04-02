
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
              mainAxisExtent: showImages ? 200 : 100,
              maxCrossAxisExtent: showImages ? 200 : 200,
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
        color: _parseColor(product.color) ?? Theme.of(context).cardColor,
        child: showImages ? _buildWithImage(context,ref) : _buildCompact(context, ref),
      ),
    );
  }

  /// Parse a hex color string (e.g. "#FF5733" or "FF5733") into a Color.
  Color? _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return null;
    try {
      String hex = colorStr.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex'; // add full opacity
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return null;
  }

  /// Determine a contrasting text color for a given background.
  Color _textColorFor(Color? bg) {
    if (bg == null) return Colors.black;
    // Use luminance to decide
    return bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  Widget _buildWithImage(BuildContext context, WidgetRef ref) {
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final componentsDataAsync = ref.watch(productComponentsProvider(product.id));
    final cardColor = _parseColor(product.color);
    final textColor = _textColorFor(cardColor);
    final hasImage = product.imageUrl != null && product.imageUrl!.isNotEmpty;

    return componentsDataAsync.when(
      data: (componentsData) {
        // Calculate display price: base price + (default component prices × default quantities)
        double displayPrice = product.finalPrice;
        for (var componentData in componentsData) {
          final defaultQuantity = componentData['defaultQuantity'] as int? ?? 0;
          final defaultPrice = componentData['defaultPrice'] as double? ?? 0.0;
          displayPrice += (defaultPrice * defaultQuantity);
        }

        if (!hasImage) {
          // No image: text fills the entire card
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      product.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: cardColor != null ? textColor : null,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  currencyFormatter.format(displayPrice),
                  style: TextStyle(
                    color: cardColor != null
                        ? textColor.withValues(alpha: 0.85)
                        : Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (context, error, stack) {
                    return Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  },
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: cardColor != null ? textColor : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      currencyFormatter.format(displayPrice),
                      style: TextStyle(
                        color: cardColor != null
                            ? textColor.withValues(alpha: 0.85)
                            : Theme.of(context).colorScheme.primary,
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Center(
                child: Text(
                  product.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cardColor != null ? textColor : null,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Text(
              currencyFormatter.format(product.finalPrice),
              style: TextStyle(
                color: cardColor != null
                    ? textColor.withValues(alpha: 0.85)
                    : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, WidgetRef ref) {
    final componentsDataAsync = ref.watch(productComponentsProvider(product.id));
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final cardColor = _parseColor(product.color);
    final textColor = _textColorFor(cardColor);

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    product.name,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: cardColor != null ? textColor : null,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              Text(
                currencyFormatter.format(displayPrice),
                style: TextStyle(
                  color: cardColor != null
                      ? textColor.withValues(alpha: 0.85)
                      : Theme.of(context).colorScheme.primary,
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  product.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: cardColor != null ? textColor : null,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Text(
              currencyFormatter.format(product.finalPrice),
              style: TextStyle(
                color: cardColor != null
                    ? textColor.withValues(alpha: 0.85)
                    : Theme.of(context).colorScheme.primary,
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


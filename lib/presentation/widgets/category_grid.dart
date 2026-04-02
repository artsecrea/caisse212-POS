// filepath: /home/artecrea/StudioProjects/posecrea/lib/presentation/widgets/category_grid.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';

/// A grid view for displaying categories in full-page mode
class CategoryGrid extends ConsumerWidget {
  const CategoryGrid({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final showImages = ref.watch(showProductImagesProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: categoriesAsync.when(
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.category_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No categories available',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              mainAxisExtent: showImages ? 180 : 100,
              maxCrossAxisExtent: showImages ? 200 : 180,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: categories.length + 1, // +1 for "All" option
            itemBuilder: (context, index) {
              if (index == 0) {
                return _CategoryCard(
                  name: 'All Products',
                  imageUrl: null,
                  showImage: showImages,
                  isAllCategory: true,
                  onTap: () {
                    // Use -1 to indicate "All Products" (show all products, not categories)
                    ref.read(selectedCategoryProvider.notifier).state = -1;
                  },
                );
              }

              final category = categories[index - 1];
              return _CategoryCard(
                name: category.name,
                imageUrl: category.imageUrl,
                showImage: showImages,
                isAllCategory: false,
                colorHex: category.color,
                onTap: () {
                  ref.read(selectedCategoryProvider.notifier).state = category.id;
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error loading categories: $error'),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final bool showImage;
  final bool isAllCategory;
  final String? colorHex;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    this.imageUrl,
    required this.showImage,
    required this.isAllCategory,
    this.colorHex,
    required this.onTap,
  });

  Color? _parseColor(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return null;
    try {
      String hex = colorStr.replaceAll('#', '');
      if (hex.length == 6) hex = 'FF$hex';
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}
    return null;
  }

  Color _textColorFor(Color? bg) {
    if (bg == null) return Colors.black;
    return bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = _parseColor(colorHex);

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: cardColor ?? Theme.of(context).cardColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isAllCategory
                  ? Theme.of(context).primaryColor.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: showImage ? _buildWithImage(context) : _buildCompact(context),
        ),
      ),
    );
  }

  Widget _buildWithImage(BuildContext context) {
    final cardColor = _parseColor(colorHex);
    final textColor = _textColorFor(cardColor);
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty && !isAllCategory;

    if (!hasImage && !isAllCategory) {
      // No image: text fills the entire card
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            name,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: cardColor != null ? textColor : Theme.of(context).colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: _buildImageOrIcon(context),
          ),
        ),
        Expanded(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Center(
              child: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isAllCategory
                      ? Theme.of(context).primaryColor
                      : cardColor != null
                          ? textColor
                          : Theme.of(context).colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    final cardColor = _parseColor(colorHex);
    final textColor = _textColorFor(cardColor);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: isAllCategory
                ? Theme.of(context).primaryColor
                : cardColor != null
                    ? textColor
                    : Theme.of(context).colorScheme.onSurface,
          ),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildImageOrIcon(BuildContext context) {
    if (isAllCategory) {
      return Container(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        child: Center(
          child: Icon(
            Icons.apps,
            size: 48,
            color: Theme.of(context).primaryColor,
          ),
        ),
      );
    }

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        errorWidget: (context, error, stack) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(
              child: Text(
                name,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          );
        },
        placeholder: (context, url) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: CircularProgressIndicator()),
          );
        },
      );
    }

    // No image: show name text
    final cardColor = _parseColor(colorHex);
    final textColor = _textColorFor(cardColor);
    return Center(
      child: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: cardColor != null ? textColor : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}


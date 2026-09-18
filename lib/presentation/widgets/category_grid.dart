// filepath: /home/artecrea/StudioProjects/posecrea/lib/presentation/widgets/category_grid.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';
import 'overlay_label_strip.dart';

/// A grid view for displaying categories in full-page mode
class CategoryGrid extends ConsumerWidget {
  const CategoryGrid({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final showImages = ref.watch(showProductImagesProvider);
    final overlayLabels = ref.watch(productLabelOverlayProvider);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: categoriesAsync.when(
        data: (categories) {
          if (categories.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.category_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  SizedBox(height: 16),
                  Text(
                    'No categories available',
                    style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              // Overlaid labels give back the band the name used to own —
              // a quarter of the tile, which is why the grid gets shorter.
              mainAxisExtent: showImages ? (overlayLabels ? 140 : 180) : 100,
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
                  overlayLabel: overlayLabels,
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
                overlayLabel: overlayLabels,
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

  /// Name printed on the image rather than in a band below it. Shares the
  /// product grid's setting: one till, one answer.
  final bool overlayLabel;

  final bool isAllCategory;
  final String? colorHex;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    this.imageUrl,
    required this.showImage,
    required this.overlayLabel,
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

    final scheme = Theme.of(context).colorScheme;

    return Material(
      elevation: 2,
      borderRadius: AppTheme.brLg,
      // An uncoloured tile used to take `cardColor`, which IS the scaffold
      // background — it only read as a tile thanks to its drop shadow, and a
      // dark theme swallows shadows. A raised surface plus a hairline gives it
      // an edge in both themes.
      color: cardColor ?? scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.brLg,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppTheme.brLg,
            border: Border.all(
              color: isAllCategory
                  ? scheme.primary.withValues(alpha: 0.5)
                  : cardColor == null
                      ? scheme.outlineVariant.withValues(alpha: 0.8)
                      : Colors.transparent,
              width: isAllCategory ? 2 : 1,
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

    if (overlayLabel) {
      // The label rides on the picture, so the picture gets the whole card.
      return ClipRRect(
        borderRadius: AppTheme.brLg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildImageOrIcon(context),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: OverlayLabelStrip(
                title: name,
                titleSize: 14,
                textAlign: TextAlign.center,
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),
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
            borderRadius: AppTheme.brTopMd,
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


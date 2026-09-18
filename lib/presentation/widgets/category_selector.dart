import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../providers/favorites_provider.dart';
import '../../domain/models/app_settings.dart';
import '../../core/theme/app_theme.dart';

class CategorySelector extends ConsumerWidget {
  const CategorySelector({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final displayMode = ref.watch(categoryDisplayModeProvider);
    final showFavorites = ref.watch(settingsProvider.select((s) => s.showFavoritesCategory));

    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      // Categories list or "Select Category" button based on display mode
      child: displayMode == CategoryDisplayMode.topBar
          ? _buildTopBarCategories(
              context, ref, categoriesAsync, selectedCategory, showFavorites)
          : _buildFullPageModeButton(
              context, ref, categoriesAsync, selectedCategory, showFavorites),
    );
  }

  Widget _buildTopBarCategories(BuildContext context, WidgetRef ref,
      AsyncValue<List<dynamic>> categoriesAsync, int? selectedCategory, bool showFavorites) {
    return categoriesAsync.when(
      data: (categories) {
        // prefix chips: optional Favorites + always All
        final prefixCount = showFavorites ? 2 : 1;
        return ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          itemCount: categories.length + prefixCount,
          itemBuilder: (context, index) {
            if (showFavorites && index == 0) {
              return _CategoryChip(
                name: '★',
                imageUrl: null,
                isSelected: selectedCategory == kFavoritesCategoryId,
                icon: Icons.star,
                iconColor: Colors.amber,
                onTap: () {
                  ref.read(selectedCategoryProvider.notifier).state = kFavoritesCategoryId;
                },
              );
            }
            if (index == (showFavorites ? 1 : 0)) {
              return _CategoryChip(
                name: 'All',
                imageUrl: null,
                isSelected: selectedCategory == null,
                onTap: () {
                  ref.read(selectedCategoryProvider.notifier).state = null;
                },
              );
            }

            final category = categories[index - prefixCount];
            return _CategoryChip(
              name: category.name,
              imageUrl: category.imageUrl,
              isSelected: selectedCategory == category.id,
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
    );
  }

  Widget _buildFullPageModeButton(BuildContext context, WidgetRef ref,
      AsyncValue<List<dynamic>> categoriesAsync, int? selectedCategory, bool showFavorites) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: categoriesAsync.when(
        data: (categories) {
          String selectedCategoryName = 'All Categories';

          if (selectedCategory != null && categories.isNotEmpty) {
            if (selectedCategory == kFavoritesCategoryId) {
              selectedCategoryName = '★ Favorites';
            } else if (selectedCategory == -1) {
              selectedCategoryName = 'All Products';
            } else {
              final foundCategory = categories.where((c) => c.id == selectedCategory).firstOrNull;
              if (foundCategory != null) {
                selectedCategoryName = foundCategory.name;
              }
            }
          }

          return Row(
            children: [
              if (selectedCategory != null) ...[
                // Back button to show all categories
                InkWell(
                  onTap: () {
                    ref.read(selectedCategoryProvider.notifier).state = null;
                  },
                  borderRadius: AppTheme.brMd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: AppTheme.brMd,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 20, color: Theme.of(context).colorScheme.onSurface),
                        const SizedBox(width: 4),
                        Text(
                          'Back',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              // Current category indicator / Select category button
              Expanded(
                child: InkWell(
                  onTap: selectedCategory == null
                      ? null // Don't do anything when in category selection mode
                      : () {
                          // Go back to category selection
                          ref.read(selectedCategoryProvider.notifier).state = null;
                        },
                  borderRadius: AppTheme.brMd,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: AppTheme.brMd,
                      border: Border.all(
                        color: Theme.of(context).primaryColor,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          selectedCategory == null ? Icons.category : Icons.label,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            selectedCategoryName,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Theme.of(context).primaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selectedCategory != null) ...[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.swap_horiz,
                            size: 20,
                            color: Theme.of(context).primaryColor,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
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

class _CategoryChip extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final bool isSelected;
  final String? colorHex;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? iconColor;

  const _CategoryChip({
    required this.name,
    this.imageUrl,
    required this.isSelected,
    this.colorHex,
    required this.onTap,
    this.icon,
    this.iconColor,
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
    final chipColor = _parseColor(colorHex);
    final bgColor = isSelected
        ? Theme.of(context).primaryColor
        : chipColor ?? Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = isSelected
        ? Colors.white
        : chipColor != null
            ? _textColorFor(chipColor)
            : Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 90,
          constraints: const BoxConstraints(
            minWidth: 70,
            maxWidth: 90,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : chipColor ?? Theme.of(context).colorScheme.surfaceContainerHighest,
              width: 1.5,
            ),
          ),
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: isSelected ? Colors.white : iconColor),
                const SizedBox(height: 2),
              ],
              Flexible(
                child: Text(
                  name,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

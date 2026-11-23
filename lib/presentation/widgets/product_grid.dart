
import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' show Value;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/favorites_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/order_models.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/responsive_utils.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/app_localizations.dart';
import '../../services/activity_log_service.dart';
import '../../services/permission_service.dart';
import '../../utils/order_permissions.dart';
import '../../utils/zero_price_tva.dart';
import 'product_modification_dialog.dart' as dialog;
import 'quick_product_dialog.dart';
import '../../core/theme/app_theme.dart';
import 'overlay_label_strip.dart';
import '../../services/waiter_kitchen_events.dart';

class ProductGrid extends ConsumerWidget {
  const ProductGrid({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(displayedProductsProvider);
    final showImages = ref.watch(showProductImagesProvider);
    final overlayLabels = ref.watch(productLabelOverlayProvider);
    final cardSize = ref.watch(productCardSizeProvider);
    final showBackTile = ref.watch(productGridBackTileProvider);
    final searchQuery = ref.watch(productSearchQueryProvider);
    // Same permission the empty-state "+ New product" button uses: creating a
    // product from the till (name / barcode / price / category), not the
    // full back-office edit.
    final canCreateProducts = ref
        .watch(permissionServiceProvider)
        .hasPermission(Permissions.catalog);

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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    searchQuery.isNotEmpty
                        ? 'No products found for "$searchQuery"'
                        : 'No products available',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  // "+ New product" right where the search failed: this is the
                  // moment the cashier knows the catalogue is missing something,
                  // and the search text is a sensible name to start from.
                  if (canCreateProducts) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _createProductFromGrid(
                        context,
                        ref,
                        searchQuery: searchQuery,
                      ),
                      icon: const Icon(Icons.add),
                      label: Text(
                          AppLocalizations.of(context)!.translate('new_product')),
                    ),
                  ],
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

          return LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              // Three tiers, measured on the GRID's width rather than the
              // window's, so opening the order panel narrows the tiers exactly
              // as a smaller screen would.
              final isTiny = w < 480;
              final isVeryCompact = w < 700;
              final isCompact = w < kBreakpointCompact;
              final sizeIdx = (cardSize - 1).clamp(0, 2);

              // cardWidth = maxCrossAxisExtent (drives column count)
              // cardHeight = mainAxisExtent (taller than wide to fit text)
              final List<double> cardWidths;
              final List<double> cardHeights;

              if (showImages) {
                // Slightly smaller image cards → more products per row and less
                // wasted space. The name below flexes into whatever height is
                // left (see _buildWithImage), so shrinking never clips text.
                cardWidths = isTiny
                    ? [88.0, 104.0, 124.0]
                    : isVeryCompact
                        ? [104.0, 126.0, 148.0]
                        : isCompact
                            ? [122.0, 148.0, 174.0]
                            : [140.0, 170.0, 205.0];
                // images need extra height (image area + text area)
                // Heights no longer need to reserve room for text: the label
                // block is a fixed height and the image takes the remainder, so
                // these numbers now buy image, not label space.
                cardHeights = isTiny
                    ? [116.0, 132.0, 152.0]
                    : isVeryCompact
                        ? [132.0, 158.0, 188.0]
                        : isCompact
                            ? [154.0, 184.0, 220.0]
                            : [176.0, 210.0, 250.0];
              } else {
                // Wider cards = fewer mid-word breaks; height > width to fit 2-3 name lines
                cardWidths = isVeryCompact
                    ? [90.0, 110.0, 135.0]
                    : isCompact
                        ? [105.0, 130.0, 160.0]
                        : [120.0, 150.0, 185.0];
                cardHeights = isVeryCompact
                    ? [80.0, 95.0, 115.0]
                    : isCompact
                        ? [85.0, 100.0, 125.0]
                        : [90.0, 110.0, 135.0];
              }

              final metrics = CardMetrics.forWidth(
                w,
                cardHeight: cardHeights[sizeIdx],
              );

              // Overlaid labels sit on the picture, so the band that used to
              // hold them is height the grid can hand back — that is the whole
              // reason to choose the layout. Floored so a tile never gets so
              // short that the label covers most of what it is labelling.
              final tileHeight = showImages && overlayLabels
                  ? math.max(96.0, cardHeights[sizeIdx] - metrics.textBlockHeight)
                  : cardHeights[sizeIdx];

              return GridView.builder(
                padding: EdgeInsets.all(isTiny ? 4 : 8),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: cardWidths[sizeIdx],
                  mainAxisExtent: tileHeight,
                  crossAxisSpacing: isTiny ? 4 : 6,
                  mainAxisSpacing: isTiny ? 4 : 6,
                ),
                // Two tiles can bracket the catalogue: a "back" card first and
                // a "+ New product" card last, both in the exact card footprint
                // the grid hands out so neither disturbs the row rhythm.
                //
                // The back tile leads because that is where a thumb already is
                // after tapping a category, and because a way out belongs at
                // the start of a list rather than past the end of it.
                itemCount: products.length +
                    (showBackTile ? 1 : 0) +
                    (canCreateProducts ? 1 : 0),
                itemBuilder: (context, index) {
                  if (showBackTile && index == 0) {
                    return _BackToCategoriesCard(metrics: metrics);
                  }
                  final productIndex = showBackTile ? index - 1 : index;
                  if (productIndex == products.length) {
                    return _NewProductCard(metrics: metrics);
                  }
                  final product = products[productIndex];
                  return _ProductCard(product: product, metrics: metrics);
                },
              );
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

/// Open the quick-create dialog and, if a product comes back, drop it straight
/// onto the open ticket.
///
/// Shared by the empty-state button and the trailing grid card so both behave
/// identically. Seeding the name from the active search is the point of the
/// whole flow: the cashier searched for something that isn't in the catalogue,
/// so that text is the name they want. The search is cleared afterwards
/// because the new product usually won't match the query that failed.
Future<void> _createProductFromGrid(
  BuildContext context,
  WidgetRef ref, {
  required String searchQuery,
}) async {
  final product = await showQuickProductDialog(
    context: context,
    ref: ref,
    initialName: searchQuery.isNotEmpty ? searchQuery : null,
  );
  if (product == null || !context.mounted) return;

  // Creating a catalogue entry and putting a line on a saved order are two
  // different permissions. `pos:catalog` got them this far, so the product is
  // kept either way — but without `pos:orders:item:add` it does not go onto an
  // already-saved order, and the cashier is told why rather than left
  // wondering where their item went.
  if (canAddItemToCurrentOrder(ref)) {
    ref.read(orderProvider.notifier).addItem(
          OrderItem(
            productId: product.id,
            productName: product.name,
            finalPrice: product.finalPrice,
            quantity: 1,
            tva: product.tvaAmount,
            discount: product.discountAmount,
            imageUrl: product.imageUrl,
          ),
        );
  } else {
    SnackBarHelper.error(
      context,
      AppLocalizations.of(context)!.translate('product_created_not_added'),
    );
  }

  if (searchQuery.isNotEmpty) {
    ref.read(productSearchQueryProvider.notifier).state = '';
  }
}

/// The leading "back" tile: returns to the category grid.
///
/// A tile rather than a bar or an app-bar arrow because on a full-page till the
/// grid *is* the screen — a control outside it is a second place to look, and
/// the one thing a cashier does after finishing a category is go back for the
/// next one. Deliberately not styled like a product: filled with the primary
/// tint and carrying an arrow, so nothing about it invites a sale.
class _BackToCategoriesCard extends ConsumerWidget {
  final CardMetrics metrics;

  const _BackToCategoriesCard({required this.metrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final showImages = ref.watch(showProductImagesProvider);

    // With images off the cards are short; the arrow carries the meaning on its
    // own and the tooltip explains it — same rule as the "+" tile.
    final showLabel = showImages;

    return Tooltip(
      message: l10n.translate('back_to_categories'),
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: AppTheme.brSm,
        elevation: 2,
        child: InkWell(
          borderRadius: AppTheme.brSm,
          onTap: () {
            // Clearing the selection is what sends the main screen back to the
            // category grid; the search box has to go with it, or the grid
            // would reopen filtered by a query the cashier cannot see.
            ref.read(selectedCategoryProvider.notifier).state = null;
            if (ref.read(productSearchQueryProvider).isNotEmpty) {
              ref.read(productSearchQueryProvider.notifier).state = '';
            }
          },
          child: Padding(
            padding: EdgeInsets.all(metrics.padding),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.arrow_back_rounded,
                  size: showLabel ? 34 : 26,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                if (showLabel) ...[
                  const SizedBox(height: 4),
                  Text(
                    l10n.translate('back_to_categories'),
                    textAlign: TextAlign.center,
                    maxLines: metrics.nameLines,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: metrics.nameFont,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The trailing "+" tile in the product grid.
///
/// Deliberately does NOT look like a product: a dashed outline and no fill, so
/// it reads as an empty slot inviting a new item rather than something that can
/// be sold. It still takes the exact card footprint the grid hands it, so it
/// never disturbs the row rhythm.
class _NewProductCard extends ConsumerWidget {
  final CardMetrics metrics;

  const _NewProductCard({required this.metrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final searchQuery = ref.watch(productSearchQueryProvider);
    final showImages = ref.watch(showProductImagesProvider);

    // With images off the cards are short; the label would crowd the icon out,
    // so the "+" carries the meaning on its own and the tooltip explains it.
    final showLabel = showImages;

    return Tooltip(
      message: l10n.translate('new_product'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppTheme.brSm,
          onTap: () =>
              _createProductFromGrid(context, ref, searchQuery: searchQuery),
          child: _DottedBorderBox(
            color: theme.colorScheme.primary.withValues(alpha: 0.55),
            radius: AppTheme.brSm,
            child: Padding(
              padding: EdgeInsets.all(metrics.padding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: showLabel ? 34 : 26,
                    color: theme.colorScheme.primary,
                  ),
                  if (showLabel) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.translate('new_product'),
                      textAlign: TextAlign.center,
                      maxLines: metrics.nameLines,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: metrics.nameFont,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A rounded dashed outline. Flutter ships no dashed border, and pulling in a
/// package for one tile isn't worth it, so this paints it directly.
class _DottedBorderBox extends StatelessWidget {
  final Widget child;
  final Color color;
  final BorderRadius radius;

  const _DottedBorderBox({
    required this.child,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final BorderRadius radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final outline = Path()
      ..addRRect(
        radius.toRRect(Offset.zero & size).deflate(0.8),
      );

    const dash = 5.0;
    const gap = 4.0;
    for (final metric in outline.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

/// Card typography, and the height reserved for the label block.
///
/// Text size is deliberately NOT derived from the card-size setting. Shrinking
/// cards used to shrink the labels with them, which is backwards: the point of a
/// smaller card is to fit MORE products, not to make each one harder to read.
/// So the label size is a function of the available width only — it drops by a
/// point on a genuinely narrow screen and stops there.
///
/// [textBlockHeight] is what makes that hold structurally. The label block is
/// given a fixed height and the image takes whatever is left, so making a card
/// shorter takes pixels from the IMAGE and never from the text. The old layout
/// split them proportionally (flex 3:2), which is why a smaller card squeezed
/// both.
class CardMetrics {
  final double nameFont;
  final double priceFont;
  final double padding;
  final double textBlockHeight;
  final int nameLines;

  const CardMetrics({
    required this.nameFont,
    required this.priceFont,
    required this.padding,
    required this.textBlockHeight,
    required this.nameLines,
  });

  /// [availableWidth] is the grid's own width — already minus the order panel,
  /// so a wide monitor with the panel open is treated as the narrower space it
  /// actually is.
  factory CardMetrics.forWidth(double availableWidth,
      {required double cardHeight}) {
    // 12 is the floor: below that, product names stop being scannable at
    // arm's length, which is the only distance that matters on a till.
    final double nameFont = availableWidth < 560
        ? 12.0
        : availableWidth < kBreakpointCompact
            ? 13.0
            : 14.0;
    final double priceFont = nameFont - 1;
    final double padding = availableWidth < 560 ? 6.0 : 8.0;

    // Two lines of name unless the card is too short to afford them, in which
    // case one line plus a taller image beats two cramped lines.
    final int lines = cardHeight >= 150 ? 2 : 1;

    // Font metrics, not a guess: name lines at 1.15 line-height, the 2px gap,
    // the price line at 1.25, and the block's own vertical padding.
    final double textBlockHeight =
        (nameFont * 1.15 * lines) + 2 + (priceFont * 1.25) + 10;

    return CardMetrics(
      nameFont: nameFont,
      priceFont: priceFont,
      padding: padding,
      textBlockHeight: textBlockHeight.ceilToDouble(),
      nameLines: lines,
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final Product product;
  final CardMetrics metrics;

  const _ProductCard({required this.product, required this.metrics});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showImages = ref.watch(showProductImagesProvider);
    final componentsDataAsync = ref.watch(productComponentsProvider(product.id));
    final showFavStar = ref.watch(settingsProvider.select((s) => s.showFavoritesCategory));
    final isFavorite = ref.watch(favoriteProductsProvider.select((s) => s.contains(product.id)));

    // Sized for legibility by the grid, NOT by the card-size setting — see
    // [CardMetrics]. The setting now controls how many products fit and how big
    // the image is, which is what a size control should do.
    final nameFontSize = metrics.nameFont;
    final priceFontSize = metrics.priceFont;
    final cardPadding = metrics.padding;

    return GestureDetector(
      onTap: () {
        // 86'd — the kitchen has run out. Blocked here rather than only greyed
        // out, so a fast double-tap on a busy screen can't sneak it into the
        // cart. Note this is separate from `isActive`: that is the catalogue
        // saying the product exists, this is the kitchen saying it doesn't have
        // any right now.
        if (!product.isAvailable) {
          SnackBarHelper.showErrorSnackBar(
            context,
            ref,
            AppLocalizations.of(context)!.translate('product_unavailable'),
          );
          return;
        }

        // Adding an item to a SAVED order requires the add-item permission.
        // A brand-new (unsaved) cart is unrestricted.
        if (!ensureCanAddItemToOrder(context, ref)) return;

        // Serial-tracked: the exact unit sold must be named, so quick-add is
        // never allowed. Checked before the variant branch because a tracked
        // product without variants would otherwise fall through to quick-add
        // and produce an order the backend rejects at sync time.
        if (product.isSerialTracked) {
          _showModificationDialog(context, ref);
          return;
        }

        // Priced at zero in the catalogue: the price is decided at the
        // counter, so there is nothing to quick-add. Without this the line
        // went onto the ticket at 0.00 and the cashier had to notice and
        // reopen it — and a 0.00 line is easy not to notice.
        if (product.finalPrice <= 0) {
          _showModificationDialog(context, ref);
          return;
        }

        // Check if product is a variant product - must show dialog to select variant
        final isVariantProduct = product.isVariant;

        if (isVariantProduct) {
          // Variant products MUST go through dialog to select variant
          _showModificationDialog(context, ref);
          return;
        }

        // Anything with options goes through the dialog.
        //
        // Quick-add used to fire unless a component was individually flagged
        // isRequired. That missed the group rules completely — a group with
        // minSelection 1 was never asked about — and it added every component
        // carrying a defaultQuantity with no idea of groups, so a radio group
        // whose members both had a default silently put BOTH on the ticket.
        // A product with options is a question to the cashier, not a shortcut.
        componentsDataAsync.whenData((componentsData) {
          if (componentsData.isNotEmpty) {
            _showModificationDialog(context, ref);
          } else {
            _addToOrder(context, ref, {
              'components': const <OrderItemComponent>[],
              'discount': product.discountAmount,
              'manualDiscount': 0.0,
              'note': null,
              'quantity': 1,
            });
          }
        });
      },
      onLongPress: () {
        // An 86'd product can't be modified into the cart, so long-press
        // becomes the way back: offer to put it back on sale instead.
        if (!product.isAvailable) {
          _confirmToggleAvailability(context, ref);
          return;
        }
        _showModificationDialog(context, ref);
      },
      // Right-click / secondary tap is the 86 gesture on desktop; the long-press
      // above is already taken by the modification dialog for available items.
      onSecondaryTap: () => _confirmToggleAvailability(context, ref),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Desaturated and dimmed when 86'd, so it reads as unavailable from
          // across the counter rather than needing to be looked at closely.
          Opacity(
            opacity: product.isAvailable ? 1.0 : 0.45,
            child: ColorFiltered(
              colorFilter: product.isAvailable
                  ? const ColorFilter.mode(
                      Colors.transparent, BlendMode.dst)
                  : const ColorFilter.matrix(<double>[
                      // Standard luminance-preserving greyscale.
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0.2126, 0.7152, 0.0722, 0, 0,
                      0, 0, 0, 1, 0,
                    ]),
              child: Card(
            elevation: 2,
            // A tile with no colour of its own used to be `cardColor`, which is
            // the scaffold background — the card only existed because of its
            // drop shadow, and a dark theme swallows shadows. So an uncoloured
            // tile gets a raised surface AND a hairline outline; a coloured one
            // needs neither, it is already its own block.
            shape: RoundedRectangleBorder(
              borderRadius: AppTheme.brSm,
              side: _parseColor(product.color) == null
                  ? BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .outlineVariant
                          .withValues(alpha: 0.8))
                  : BorderSide.none,
            ),
            color: _parseColor(product.color) ??
                Theme.of(context).colorScheme.surfaceContainerHigh,
            child: showImages
                ? _buildWithImage(context, ref, nameFontSize, priceFontSize, cardPadding)
                : _buildCompact(context, ref, nameFontSize, priceFontSize, cardPadding),
              ),
            ),
          ),
          // Explicit label, not just the grey: greyscale alone is ambiguous next
          // to a product whose own colour happens to be grey, and it says
          // nothing to a colour-blind user.
          if (!product.isAvailable)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 2),
                color: Theme.of(context).colorScheme.error,
                child: Text(
                  AppLocalizations.of(context)!.translate('unavailable_short'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: Theme.of(context).colorScheme.onError,
                  ),
                ),
              ),
            ),
          if (showFavStar)
            Positioned(
              top: 2,
              right: 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () =>
                    ref.read(favoriteProductsProvider.notifier).toggle(product.id),
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Icon(
                    isFavorite ? Icons.star : Icons.star_border,
                    size: 14,
                    color: isFavorite
                        ? Colors.amber
                        : Colors.grey.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
        ],
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
  ///
  /// Only meaningful when the product carries its own colour. With no colour
  /// the caller must fall back to the theme's `onSurface`, never to this — a
  /// hardcoded black label on a dark tile is invisible.
  Color _textColorFor(Color? bg) {
    if (bg == null) return Colors.black;
    // Use luminance to decide
    return bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
  }

  /// Image edge to edge, name and price sitting on top of it.
  ///
  /// The point is height: the label no longer owns a band of its own, so the
  /// same card shows a bigger picture — or the same picture in a shorter tile,
  /// which is what the grid does with the saved space.
  ///
  /// Legibility over an unknown photograph is the whole difficulty. Three
  /// things buy it back, in order of how much work they do: a dark scrim under
  /// the text, a blur of whatever is behind it, and a shadow on the glyphs
  /// themselves. The scrim alone is enough — the blur is what stops a busy
  /// image reading as noise *around* the letters, and the shadow catches the
  /// case where a bright highlight lands directly under a stroke.
  Widget _buildOverlayLayout(
    BuildContext context, {
    required double displayPrice,
    required CurrencyFormatter currencyFormatter,
    required double nameFontSize,
    required double priceFontSize,
    required double cardPadding,
  }) {
    return ClipRRect(
      borderRadius: AppTheme.brSm,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: product.imageUrl!,
            fit: BoxFit.cover,
            errorWidget: (context, error, stack) => Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: OverlayLabelStrip(
              title: product.name,
              subtitle: currencyFormatter.format(displayPrice),
              titleSize: nameFontSize,
              subtitleSize: priceFontSize,
              titleMaxLines: metrics.nameLines,
              padding: EdgeInsets.symmetric(
                  horizontal: cardPadding, vertical: cardPadding - 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWithImage(BuildContext context, WidgetRef ref,
      double nameFontSize, double priceFontSize, double cardPadding) {
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
            padding: EdgeInsets.symmetric(horizontal: cardPadding, vertical: cardPadding - 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.max,
              children: [
                Expanded(
                  child: Center(
                    child: Text(
                      product.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: nameFontSize,
                        color: cardColor != null ? textColor : null,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 4,
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
                    fontSize: priceFontSize,
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                ),
              ],
            ),
          );
        }

        // LayoutBuilder so the card can see its own height and decide whether
        // there is enough room left for an image at all.
        return LayoutBuilder(builder: (context, box) {
          final imageHeight = box.maxHeight - metrics.textBlockHeight;
          // Below this the image is a letterbox sliver that reads as a glitch —
          // better to give the whole card to the label than to show a smear.
          const minImageHeight = 44.0;

          if (imageHeight < minImageHeight) {
            return Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: cardPadding, vertical: cardPadding - 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        product.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: nameFontSize,
                          height: 1.15,
                          color: cardColor != null ? textColor : null,
                        ),
                        maxLines: 2,
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
                      fontSize: priceFontSize,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                  ),
                ],
              ),
            );
          }

          if (ref.watch(productLabelOverlayProvider)) {
            return _buildOverlayLayout(
              context,
              displayPrice: displayPrice,
              currencyFormatter: currencyFormatter,
              nameFontSize: nameFontSize,
              priceFontSize: priceFontSize,
              cardPadding: cardPadding,
            );
          }

          return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: AppTheme.brTopSm,
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (context, error, stack) {
                    return Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(cardPadding - 2),
                          child: Text(
                            product.name,
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: nameFontSize),
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // FIXED height, not a flex share. This is the whole fix: the label
            // keeps exactly the room its own font needs, so shrinking a card
            // shrinks the image above and leaves the text alone.
            SizedBox(
              height: metrics.textBlockHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: cardPadding, vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          product.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: nameFontSize,
                            height: 1.15,
                            color: cardColor != null ? textColor : null,
                          ),
                          // One line on a short card: two cramped lines plus a
                          // squeezed image is worse than one clear line.
                          maxLines: metrics.nameLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      currencyFormatter.format(displayPrice),
                      style: TextStyle(
                        color: cardColor != null
                            ? textColor.withValues(alpha: 0.85)
                            : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: priceFontSize,
                      ),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.fade,
                    ),
                  ],
                ),
              ),
            ),
          ],
          );
        });
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Center(
                child: Text(
                  product.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: cardColor != null ? textColor : null,
                  ),
                  textAlign: TextAlign.center,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompact(BuildContext context, WidgetRef ref,
      double nameFontSize, double priceFontSize, double cardPadding) {
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
          padding: EdgeInsets.symmetric(horizontal: cardPadding, vertical: cardPadding - 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: nameFontSize,
                    color: cardColor != null ? textColor : null,
                    height: 1.3,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                currencyFormatter.format(displayPrice),
                style: TextStyle(
                  color: cardColor != null
                      ? textColor.withValues(alpha: 0.85)
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: priceFontSize,
                ),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: Text(
                product.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: nameFontSize,
                  color: cardColor != null ? textColor : null,
                  height: 1.3,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              currencyFormatter.format(product.finalPrice),
              style: TextStyle(
                color: cardColor != null
                    ? textColor.withValues(alpha: 0.85)
                    : Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
                fontSize: priceFontSize,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
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
    final quantity = (modifications['quantity'] as num?)?.toDouble() ?? 1.0;

    // Variant data
    final variantId = modifications['variantId'] as int?;
    final variantName = modifications['variantName'] as String?;
    final variantPrice = modifications['variantPrice'] as double?;
    final variantTva = modifications['variantTva'] as double?;
    final variantImageUrl = modifications['variantImageUrl'] as String?;

    final serialId = modifications['serialId'] as int?;
    final serialNumber = modifications['serialNumber'] as String?;

    // Manual unit-price override (only present when a permitted user set it).
    // It outranks the variant price the dialog also returns: the cashier typed
    // over whatever was in the field, variant price included.
    final priceOverride = (modifications['priceOverride'] as num?)?.toDouble();
    final basePrice = variantPrice ?? product.finalPrice;
    final unitPrice = priceOverride != null && priceOverride >= 0
        ? priceOverride
        : basePrice;

    final orderItem = OrderItem(
      productId: product.id,
      productName: product.name,
      serialId: serialId,
      serialNumber: serialNumber,
      variantId: variantId,
      variantName: variantName,
      imageUrl: variantImageUrl ?? product.imageUrl,
      finalPrice: unitPrice,
      quantity: quantity,
      components: components,
      tva: lineUnitTva(
        catalogPrice: basePrice,
        catalogTva: variantTva ?? product.tvaAmount,
        unitPrice: unitPrice,
        zeroPriceRate: ref.read(settingsProvider).zeroPriceTvaRate,
      ),
      discount: discount,
      manualDiscount: manualDiscount,
      note: note,
      unitName: product.unitName,
    );

    ref.read(orderProvider.notifier).addItem(orderItem);

    // Same anti-fraud trail the edit path keeps: an override typed on the way
    // into the basket has to be as traceable as one typed afterwards.
    if (priceOverride != null && priceOverride >= 0 && priceOverride != basePrice) {
      final actor = ref.read(currentUserProvider);
      final currency = ref.read(settingsProvider).currency;
      ref.read(activityLogServiceProvider).logPriceChanged(
            variantName ?? product.name,
            CurrencyFormatter.formatWithCurrency(basePrice, currency),
            CurrencyFormatter.formatWithCurrency(priceOverride, currency),
            orderCode: ref.read(orderProvider).orderCode,
            userId: actor?.id,
          );
    }

    // Hold the unit for as long as it sits in the basket, so a second line on
    // this terminal cannot claim it. Released again when the line is removed or
    // the order is cancelled; a catalogue pull re-asserts server truth, which is
    // what recovers a reservation orphaned by a crash.
    if (serialId != null) {
      ref.read(serialServiceProvider).reserve(serialId);
    }

    // Track last-used order (RAM only, most recent first)
    final lastUsed = ref.read(lastUsedProductIdsProvider);
    ref.read(lastUsedProductIdsProvider.notifier).state = [
      product.id,
      ...lastUsed.where((id) => id != product.id),
    ];

    SnackBarHelper.showSuccessSnackBar(
      context,
      ref,
      serialNumber != null
          ? '${variantName ?? product.name} · $serialNumber'
          : '${variantName ?? product.name} added to order',
      duration: const Duration(seconds: 1),
    );
  }

  /// Toggle the local "86" flag after a confirmation.
  ///
  /// Gated on `productsUpdate`: taking an item off the menu mid-service changes
  /// what the whole floor can sell, so it is not a plain cashier action. The
  /// flag is LOCAL — it is never sent to the backend and a catalogue sync will
  /// not clear it (see `Products.isAvailable`).
  Future<void> _confirmToggleAvailability(
      BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    if (!ref
        .read(permissionServiceProvider)
        .hasPermission(Permissions.productsModify)) {
      SnackBarHelper.showErrorSnackBar(
          context, ref, l10n.translate('no_permission'));
      return;
    }

    final makeUnavailable = product.isAvailable;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(makeUnavailable
            ? l10n.translate('mark_unavailable')
            : l10n.translate('mark_available')),
        content: Text(
          (makeUnavailable
                  ? l10n.translate('mark_unavailable_confirm')
                  : l10n.translate('mark_available_confirm'))
              .replaceAll('{0}', product.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: makeUnavailable
                ? ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  )
                : null,
            child: Text(makeUnavailable
                ? l10n.translate('mark_unavailable')
                : l10n.translate('mark_available')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final db = ref.read(databaseProvider);
    await (db.update(db.products)..where((p) => p.id.equals(product.id)))
        .write(ProductsCompanion(isAvailable: Value(!makeUnavailable)));
    ref.read(waiterKitchenEventServiceProvider).productAvailabilityChanged(
          productId: product.id,
          name: product.name,
          isAvailable: !makeUnavailable,
        );
    // The grid watches products via a stream provider, so it repaints itself.
    if (context.mounted) {
      SnackBarHelper.showSuccessSnackBar(
        context,
        ref,
        makeUnavailable
            ? l10n.translate('marked_unavailable')
            : l10n.translate('marked_available'),
      );
    }
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


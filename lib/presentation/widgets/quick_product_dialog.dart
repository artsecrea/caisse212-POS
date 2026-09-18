import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../services/api_service.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import '../../utils/snackbar_helper.dart';
import 'adaptive_text_field.dart';

/// Create a product from the till: **three fields, nothing more**.
///
/// TVA, stock, images and the rest are back-office decisions — the server fills
/// them with its own defaults. Putting them here would turn a ten-second
/// counter action into a form nobody completes correctly under pressure.
///
/// The category is not one of them. The product is filed in the category the
/// cashier is browsing, shown read-only so they know where it landed — the
/// grid in front of them is about to show it there. A product with no category
/// at all is not offered: it would be invisible in a category-driven grid, so
/// the only way to find it again would be to search for its exact name.
///
/// Returns the created (or matched-by-barcode) product, or null on cancel —
/// including when there is no category to file it under, which the cashier is
/// told about rather than left to discover.
Future<Product?> showQuickProductDialog({
  required BuildContext context,
  required WidgetRef ref,
  String? initialBarcode,
  String? initialName,
}) async {
  final l10n = AppLocalizations.of(context)!;

  if (!ref
      .read(permissionServiceProvider)
      .hasPermission(Permissions.catalog)) {
    SnackBarHelper.error(context, l10n.translate('no_permission'));
    return null;
  }

  // Whatever the product grid is currently filtered to. `null` is the "All"
  // view and the virtual categories (Favorites) use negative ids — neither is
  // a real row this product could belong to, so there is nothing to file it
  // under and nothing honest to display.
  final currentCategoryId = ref.read(selectedCategoryProvider);
  if (currentCategoryId == null || currentCategoryId <= 0) {
    SnackBarHelper.warning(
        context, l10n.translate('create_product_needs_category'));
    return null;
  }

  final service = ref.read(quickProductServiceProvider);
  final categories = await service.localCategories();
  if (!context.mounted) return null;

  // The grid is rendering this category's products, so the row is local. The
  // id fallback is for a catalogue sync that landed mid-gesture — better than
  // an empty label, and the create still goes to the right category.
  var categoryName = '#$currentCategoryId';
  for (final c in categories) {
    if (c.id == currentCategoryId) {
      categoryName = c.name;
      break;
    }
  }

  final nameCtrl = TextEditingController(text: initialName ?? '');
  final barcodeCtrl = TextEditingController(text: initialBarcode ?? '');
  final priceCtrl = TextEditingController();
  var busy = false;
  String? error;

  final created = await showDialog<Product>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final cs = Theme.of(ctx).colorScheme;
      // Creating needs the server: it assigns the id and enforces the plan's
      // product cap, so there is no honest offline version of this.
      final isOnline = ref.watch(networkStateProvider);

      Future<void> submit() async {
        final name = nameCtrl.text.trim();
        final price = double.tryParse(priceCtrl.text.replaceAll(',', '.'));
        if (name.isEmpty) {
          setLocal(() => error = l10n.translate('name_required'));
          return;
        }
        if (price == null || price < 0) {
          setLocal(() => error = l10n.translate('valid_price_required'));
          return;
        }
        setLocal(() {
          busy = true;
          error = null;
        });
        try {
          final result = await service.create(
            name: name,
            price: price,
            barcode: barcodeCtrl.text.trim(),
            categoryId: currentCategoryId,
          );
          if (!ctx.mounted) return;
          // created:false means the barcode already existed. Proceed exactly as
          // for a new one — the cashier wants to sell the thing in their hand.
          if (!result.created) {
            SnackBarHelper.warning(
                ctx,
                l10n
                    .translate('product_already_exists')
                    .replaceAll('{0}', result.product.name));
          }
          Navigator.pop(ctx, result.product);
        } on PosCatalogException catch (e) {
          Logger.instance.error('Quick create refused: ${e.message}');
          setLocal(() {
            busy = false;
            // Verbatim: a plan-limit message names the cap and the plan, and
            // paraphrasing it leaves the operator with nothing to act on.
            error = e.isForbidden ? l10n.translate('no_permission') : e.message;
          });
        } catch (e) {
          Logger.instance.error('Quick create failed: $e');
          setLocal(() {
            busy = false;
            error = errorText(e, l10n);
          });
        }
      }

      return AlertDialog(
        title: Row(children: [
          Icon(Icons.add_box_outlined, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.translate('new_product'))),
        ]),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isOnline)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(children: [
                      Icon(Icons.cloud_off, size: 18, color: cs.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(l10n.translate('quick_create_offline'),
                            style: TextStyle(fontSize: 12, color: cs.error)),
                      ),
                    ]),
                  ),
                AdaptiveKeyboardTextField(
                  controller: nameCtrl,
                  autofocus: (initialBarcode ?? '').isNotEmpty,
                  decoration: InputDecoration(
                    labelText: '${l10n.translate('product_name')} *',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.label_outline),
                  ),
                ),
                const SizedBox(height: 12),
                AdaptiveKeyboardTextField(
                  controller: barcodeCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.translate('barcode'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.qr_code),
                  ),
                ),
                const SizedBox(height: 12),
                AdaptiveKeyboardTextField(
                  controller: priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: '${l10n.translate('price')} *',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                // Told, not asked — see the function doc. Styled like the
                // fields above so it reads as part of the form, but with no
                // control to reach for.
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.outlineVariant),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(children: [
                    Icon(Icons.category_outlined,
                        size: 20, color: cs.onSurfaceVariant),
                    const SizedBox(width: 12),
                    Text(
                      '${l10n.translate('category')}: ',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    Expanded(
                      child: Text(
                        categoryName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
                if (error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(children: [
                      Icon(Icons.error_outline, size: 18, color: cs.error),
                      const SizedBox(width: 8),
                      // The server's own words — see submit().
                      Expanded(child: Text(error!)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(ctx),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton.icon(
            onPressed: (busy || !isOnline) ? null : submit,
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(l10n.translate('create')),
          ),
        ],
      );
    }),
  );

  nameCtrl.dispose();
  barcodeCtrl.dispose();
  priceCtrl.dispose();
  return created;
}

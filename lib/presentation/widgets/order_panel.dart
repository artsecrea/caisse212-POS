import 'cancelled_items_dialog.dart'
    show CancelledItemRows, CancelledSummaryRow;
import 'exchange_settle_dialog.dart' show ExchangeBanner;
import 'order_reference_dialog.dart';
import 'order_tag_widgets.dart' show OrderTagChips;
import 'dart:async';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/order_provider.dart';
import '../../providers/held_orders_provider.dart';
import '../../domain/models/order_course.dart';
import '../../domain/models/order_models.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/app_localizations.dart';
import '../../utils/elapsed_label.dart';
import '../../utils/snackbar_helper.dart';
import '../../services/permission_service.dart';
import '../../services/activity_log_service.dart';
import '../../providers/settings_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/network_provider.dart';
import '../../data/database/app_database.dart';
import 'product_modification_dialog.dart' show ProductModificationDialog;
import 'unpaid_orders_dialog.dart';
import '../../utils/button_styles.dart';
import '../../utils/order_permissions.dart';
import '../../utils/zero_price_tva.dart';
import './adaptive_text_field.dart';
import '../../core/theme/app_theme.dart';
import 'order_note_dialog.dart';

class OrderPanel extends ConsumerWidget {
  const OrderPanel({Key? key}) : super(key: key);

  /// Whether [item] can be removed/modified. Always allowed for a brand-new
  /// (unsaved) cart, or for an item that hasn't been persisted yet (`item.id ==
  /// null`) — e.g. just added to a loaded saved order by mistake. Only items that
  /// are already saved in the order require the granular permission (anti-fraud).
  bool _canEditItem(WidgetRef ref, OrderItem item, String permission) {
    final order = ref.read(orderProvider);
    if (order.orderId == null || item.id == null) return true;
    // A waiter's order is not the cashier's to rewrite — see
    // canEditWaiterOrder. Checked before the granular permission because it
    // gates the whole order, not this one line.
    if (!canEditWaiterOrder(ref)) return false;
    return ref.read(permissionServiceProvider).hasPermission(permission);
  }

  /// Whether [item]'s quantity may move from its current value to [newQty].
  ///
  /// On a SAVED order with `savedQuantity = S` and current displayed `O`, the
  /// rule is delta-aware:
  ///   * **Net add** (`newQty > O` AND `newQty > S`) → requires `item:add`.
  ///     Walking up to the saved baseline (restoring units someone reduced
  ///     this session) is free.
  ///   * **Net remove** (`newQty < O` AND `newQty < S`) → requires
  ///     `item:remove`. Reducing extra units someone added this session,
  ///     i.e. staying at or above baseline, is free.
  ///   * Brand-new cart or freshly-added (unsaved) item → always free.
  bool _canSetQuantity(WidgetRef ref, OrderItem item, double newQty) {
    final order = ref.read(orderProvider);
    if (order.orderId == null || item.id == null) return true;
    if (!canEditWaiterOrder(ref)) return false;
    final saved = item.savedQuantity ?? 0.0;
    final oldQty = item.quantity;
    final perm = ref.read(permissionServiceProvider);
    final isAdding = newQty > oldQty && newQty > saved;
    final isRemoving = newQty < oldQty && newQty < saved;
    if (isAdding && !perm.hasPermission(Permissions.ordersItemAdd)) {
      return false;
    }
    if (isRemoving && !perm.hasPermission(Permissions.ordersItemRemove)) {
      return false;
    }
    return true;
  }

  void _showPermissionDenied(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    SnackBarHelper.showErrorSnackBar(
      context,
      ref,
      l10n.translate('no_permission'),
    );
  }

  /// True when the cart is a SAVED order (has an id) holding a single line —
  /// removing that line would leave an empty order row behind, so the order is
  /// cancelled instead. Unsaved (draft) carts return false — emptying them is
  /// harmless (RAM only).
  bool _isLastItemOfSavedOrder(WidgetRef ref) {
    final order = ref.read(orderProvider);
    return order.isSaved() && order.items.length <= 1;
  }

  /// Confirms and CANCELS the whole saved order (used when the user removes
  /// its last item). Returns true if the order was cancelled — callers must
  /// then NOT also remove the individual item.
  ///
  /// Cancelled, never deleted: a deleted order vanishes from the Z, so ringing
  /// something up and swiping it away left no trace of the annulment. The
  /// order and its line stay, reported on the cancellations rows.
  Future<bool> _confirmCancelWholeOrder(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final orderId = ref.read(orderProvider).orderId;
    if (orderId == null) return false; // only saved orders reach here

    if (!ref
        .read(permissionServiceProvider)
        .hasPermission(Permissions.ordersCancel)) {
      _showPermissionDenied(context, ref);
      return false;
    }

    final reasonController = TextEditingController();
    final reason = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.translate('cancel_order')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translate('remove_last_item_cancels_order')),
            const SizedBox(height: 16),
            AdaptiveKeyboardTextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: l10n.translate('cancellation_reason'),
                hintText: l10n.translate('enter_cancellation_reason'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        // Full-width, large touch targets stacked vertically (POS screens).
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: AppButtonStyles.elevatedButtonStyle(
                    isLarge: true,
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(
                    dialogContext,
                    reasonController.text.trim(),
                  ),
                  child: Text(l10n.translate('cancel_order')),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: AppButtonStyles.textButtonStyle(isLarge: true),
                  onPressed: () => Navigator.pop(dialogContext, null),
                  child: Text(l10n.translate('cancel')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    // Not disposed: the closing dialog still rebuilds its field with this
    // controller for a few frames. It is collected with the dialog.
    if (reason == null) return false;

    final repo = ref.read(orderRepositoryProvider);
    try {
      await repo.updateOrderStatus(
        orderId,
        'CANCELED',
        cancellationReason: reason.isNotEmpty ? reason : null,
        userId: ref.read(currentUserProvider)?.id,
      );
      await repo.freeTablesForOrder(orderId);
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showErrorSnackBar(
          context,
          ref,
          '${l10n.translate('error_changing_status')}: $e',
        );
      }
      return false;
    }

    ref.read(orderProvider.notifier).clearOrder();
    if (context.mounted) {
      SnackBarHelper.showSuccessSnackBar(
        context,
        ref,
        l10n.translate('order_canceled_successfully'),
      );
    }
    return true;
  }

  /// Pushes the current cart onto the RAM-hold stack and clears the panel.
  void _holdOrder(WidgetRef ref) {
    final current = ref.read(orderProvider);
    if (current.items.isEmpty) return;
    ref.read(heldOrdersProvider.notifier).update((list) => [...list, current]);
    ref.read(orderProvider.notifier).clearOrder();
  }

  /// Restores held order at [index]. If the panel currently has items they
  /// are auto-pushed back onto the hold stack first.
  void _resumeHeldOrder(WidgetRef ref, int index) {
    final held = List<CurrentOrder>.from(ref.read(heldOrdersProvider));
    final toRestore = held.removeAt(index);

    final current = ref.read(orderProvider);
    if (current.items.isNotEmpty) {
      held.add(current);
    }

    ref.read(heldOrdersProvider.notifier).state = held;
    ref.read(orderProvider.notifier).loadOrder(toRestore);
  }

  /// The trash/clear button. Only empties the in-memory working panel; the
  /// persisted order (if any) is left intact. Order deletion lives in the
  /// dedicated orders-management screen.
  Future<void> _handleClear(BuildContext context, WidgetRef ref) async {
    ref.read(orderProvider.notifier).clearOrder();
  }

  /// Opens the [UnpaidOrdersDialog] so the cashier can pick an existing
  /// unpaid / on-hold order to load into the working cart. Only meant for
  /// the empty-cart state — when there are items, the panel hides this
  /// shortcut.
  Future<void> _openResumeDialog(BuildContext context, WidgetRef ref) async {
    final orderId = await showDialog<int>(
      context: context,
      builder: (_) => const UnpaidOrdersDialog(),
    );
    if (orderId == null || !context.mounted) return;
    final repo = ref.read(orderRepositoryProvider);
    final order = await repo.getOrderById(orderId);
    if (order == null) return;
    ref.read(orderProvider.notifier).loadOrder(order);
  }

  void _showItemOptions(
    BuildContext context,
    WidgetRef ref,
    int index,
    OrderItem item,
  ) async {
    if (!_canEditItem(ref, item, Permissions.ordersItemModify)) {
      _showPermissionDenied(context, ref);
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          ProductModificationDialog(product: item, isEditMode: true),
    );

    if (result != null) {
      // Closing the dialog's qty-edit loophole: a cashier with item:modify
      // but not item:remove could otherwise type a smaller qty here and slip
      // a below-baseline reduction past the gate.
      final newQty = (result['quantity'] as num?)?.toDouble() ?? item.quantity;
      final noteSplits = (result['noteSplits'] as List?) ?? const [];
      // Units split off under other notes leave this line but stay on the
      // order: the line's own quantity is held to the removal floor, the
      // total to the add gate. Otherwise a split of a saved line would be a
      // way to move units onto a fresh line that can be deleted freely.
      final totalQty = newQty +
          noteSplits.fold<double>(
              0, (sum, s) => sum + (s['quantity'] as num).toDouble());
      if ((newQty != item.quantity && !_canSetQuantity(ref, item, newQty)) ||
          (totalQty != item.quantity && !_canSetQuantity(ref, item, totalQty))) {
        if (context.mounted) _showPermissionDenied(context, ref);
        return;
      }
      // Manual unit-price override (only present when a permitted user set it).
      final priceOverride = (result['priceOverride'] as num?)?.toDouble();

      // A new price on an open-price line changes the TVA inside it. The line
      // no longer knows its catalogue price, so ask the catalogue.
      double? newTva;
      final zeroPriceRate = ref.read(settingsProvider).zeroPriceTvaRate;
      if (priceOverride != null && priceOverride >= 0 && zeroPriceRate > 0) {
        final db = ref.read(databaseProvider);
        final catalogue = item.variantId != null
            ? await (db.select(db.productVariants)
                    ..where((v) => v.id.equals(item.variantId!)))
                  .getSingleOrNull()
                  .then((v) => v == null ? null : (v.price, v.tvaAmount))
            : await (db.select(db.products)
                    ..where((p) => p.id.equals(item.productId)))
                  .getSingleOrNull()
                  .then((p) => p == null ? null : (p.finalPrice, p.tvaAmount));
        if (catalogue != null) {
          newTva = lineUnitTva(
            catalogPrice: catalogue.$1,
            catalogTva: catalogue.$2,
            unitPrice: priceOverride,
            zeroPriceRate: zeroPriceRate,
          );
        }
      }

      // Update the item with new modifications
      final updatedItem = item.copyWith(
        components: result['components'] as List<OrderItemComponent>?,
        discount: result['discount'] as double?,
        manualDiscount: result['manualDiscount'] as double?,
        quantity: (result['quantity'] as num?)?.toDouble(),
        note: result['note'] as String?,
        unitPrice: priceOverride != null && priceOverride >= 0
            ? priceOverride
            : null,
        tva: newTva,
      );

      // Audit any unit-price override (anti-fraud trail): only when a permitted
      // user actually changed the price from the item's current unit price.
      if (priceOverride != null &&
          priceOverride >= 0 &&
          priceOverride != item.finalPrice) {
        final actor = ref.read(currentUserProvider);
        final currency = ref.read(settingsProvider).currency;
        ref
            .read(activityLogServiceProvider)
            .logPriceChanged(
              item.displayName,
              CurrencyFormatter.formatWithCurrency(item.finalPrice, currency),
              CurrencyFormatter.formatWithCurrency(priceOverride, currency),
              orderCode: ref.read(orderProvider).orderCode,
              userId: actor?.id,
            );
      }

      final notifier = ref.read(orderProvider.notifier);
      notifier.updateItem(index, updatedItem);
      // Each split is a brand-new line: no ids, nothing sent to the kitchen or
      // printed yet, so it goes out as fresh food under its own note.
      for (final split in noteSplits) {
        notifier.addItem(OrderItem(
          productId: updatedItem.productId,
          productName: updatedItem.productName,
          variantId: updatedItem.variantId,
          variantName: updatedItem.variantName,
          imageUrl: updatedItem.imageUrl,
          finalPrice: updatedItem.finalPrice,
          quantity: (split['quantity'] as num).toDouble(),
          components: updatedItem.components,
          note: split['note'] as String,
          courseNo: updatedItem.courseNo,
          discount: updatedItem.discount,
          manualDiscount: updatedItem.manualDiscount,
          tva: updatedItem.tva,
          unitName: updatedItem.unitName,
        ));
      }
    }
  }

  void _showDeletePaidItemDialog(
    BuildContext context,
    WidgetRef ref,
    OrderItem item,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = ref.read(currentUserProvider);
    final permissionService = PermissionService(currentUser);

    // Check permission
    final hasPermission = permissionService.hasPermission('pos:tickets:delete');

    if (!hasPermission) {
      if (context.mounted) {
        SnackBarHelper.showErrorSnackBar(
          context,
          ref,
          l10n.translate('no_permission'),
        );
      }
      return;
    }

    // Show confirmation dialog
    if (context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: Colors.orange[700]),
              const SizedBox(width: 8),
              const Text('Delete Paid Item?'),
            ],
          ),
          content: Text(
            'Are you sure you want to delete this paid item?\n\n'
            '${item.displayName}\n'
            'Ticket #${item.ticketId}\n\n'
            'This action will update the ticket total.',
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.translate('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirmed == true && context.mounted) {
        try {
          final database = ref.read(databaseProvider);
          final syncService = ref.read(dataSyncServiceProvider);
          final isOnline = ref.read(lastKnownOnlineStatusProvider);

          if (item.id != null && item.ticketId != null) {
            // First, check how many items are in this ticket
            final ticketProducts = await (database.select(
              database.orderProducts,
            )..where((tbl) => tbl.ticketId.equals(item.ticketId!))).get();

            // Delete the order product from database
            await (database.delete(
              database.orderProducts,
            )..where((tbl) => tbl.id.equals(item.id!))).go();

            // Note: Order products are synced as part of the order, not individually

            // If this was the only item in the ticket, delete the ticket
            if (ticketProducts.length == 1) {
              // Get ticket and order info for sync
              final ticket =
                  await (database.select(database.tickets)
                        ..where((tbl) => tbl.id.equals(item.ticketId!)))
                      .getSingleOrNull();

              String? orderCode;
              String? ticketNum;

              if (ticket != null) {
                ticketNum = ticket.num;
                // Get order code
                final order =
                    await (database.select(database.orders)
                          ..where((tbl) => tbl.id.equals(ticket.orderId)))
                        .getSingleOrNull();
                orderCode = order?.code;
              }

              await (database.delete(
                database.tickets,
              )..where((tbl) => tbl.id.equals(item.ticketId!))).go();

              // Queue or execute delete operation for ticket
              if (ticket != null &&
                  ticket.isSynced &&
                  orderCode != null &&
                  ticketNum != null) {
                await syncService.deleteTicketEntity(
                  entityId: item.ticketId!,
                  orderCode: orderCode,
                  ticketNum: ticketNum,
                  isOnline: isOnline,
                );
              }
            } else {
              // Otherwise, update the ticket amount
              final remainingProducts = await (database.select(
                database.orderProducts,
              )..where((tbl) => tbl.ticketId.equals(item.ticketId!))).get();

              final newTicketAmount = remainingProducts.fold<double>(
                0.0,
                (sum, product) =>
                    sum + (product.unitaryPrice * product.quantity),
              );

              await (database.update(
                database.tickets,
              )..where((tbl) => tbl.id.equals(item.ticketId!))).write(
                TicketsCompanion(amount: drift.Value(newTicketAmount)),
              );

              // Queue or execute update operation for ticket
              final ticket =
                  await (database.select(database.tickets)
                        ..where((tbl) => tbl.id.equals(item.ticketId!)))
                      .getSingleOrNull();

              if (ticket != null && ticket.isSynced) {
                // Get order code
                final order =
                    await (database.select(database.orders)
                          ..where((tbl) => tbl.id.equals(ticket.orderId)))
                        .getSingleOrNull();

                if (order != null) {
                  await syncService.updateTicketEntity(
                    entityId: item.ticketId!,
                    orderCode: order.code,
                    ticketNum: ticket.num,
                    updateData: {'amount': newTicketAmount},
                    isOnline: isOnline,
                  );
                }
              }
            }

            // Reload the whole order. Rebuilding the items by hand here left
            // out the print cursors, variant and server id of every remaining
            // line, so the next save told the kitchen the order was unsent.
            final currentOrder = ref.read(orderProvider);
            if (currentOrder.orderId != null) {
              final reloaded = await ref
                  .read(orderRepositoryProvider)
                  .getOrderById(currentOrder.orderId!);
              if (reloaded != null) {
                ref.read(orderProvider.notifier).loadOrder(reloaded);
              }
            } else {
              // If no order ID, just remove from local state
              final itemIndex = currentOrder.items.indexWhere(
                (i) => i.id == item.id,
              );
              if (itemIndex != -1) {
                ref.read(orderProvider.notifier).removeItem(itemIndex);
              }
            }

            if (context.mounted) {
              final message = ticketProducts.length == 1
                  ? 'Paid item and ticket deleted successfully'
                  : 'Paid item deleted successfully';
              SnackBarHelper.showSuccessSnackBar(context, ref, message);
            }
          }
        } catch (e) {
          if (context.mounted) {
            SnackBarHelper.showErrorSnackBar(
              context,
              ref,
              'Error deleting item: $e',
            );
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentOrder = ref.watch(orderProvider);
    final heldOrders = ref.watch(heldOrdersProvider);
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // An exchange under way: what came back and the credit, above the
          // new goods being rung up.
          const ExchangeBanner(),
          if (currentOrder.tagIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OrderTagChips(tagIds: currentOrder.tagIds),
              ),
            ),
          // Header
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 4),
                // Flexible, not fixed: an unconstrained Text here grew with a
                // long order code until it squeezed the Spacer to nothing and
                // pushed the clear and note buttons off the edge of the panel.
                // The title is the least important thing in this row — it can
                // give ground; the buttons cannot.
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [
                          if (currentOrder.sessionOrderNo != null)
                            '#${currentOrder.sessionOrderNo}',
                          currentOrder.orderCode?.toString() ??
                              l10n.translate('current_order'),
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                      // The take-away / delivery reference, tap to change.
                      // Offered on those two types, or whenever one is set.
                      if (currentOrder.type != 'DINE_IN' ||
                          (currentOrder.reference ?? '').trim().isNotEmpty)
                        _ReferenceLine(
                          reference: currentOrder.reference,
                          onTap: () => showOrderReferenceDialog(context, ref),
                        ),
                    ],
                  ),
                ),
                const Spacer(),
                // Order note. Lives here rather than in the action bar because
                // it belongs to the order, not to the till: the cashier reads
                // it off this panel and it prints to the kitchen from here.
                //
                // Shown while a note exists even on an emptied cart, so a note
                // can never become unreachable — it would otherwise still be
                // attached and still print, with no way to open it.
                if (currentOrder.items.isNotEmpty || currentOrder.hasNote)
                  IconButton(
                    onPressed: () async {
                      final result = await showOrderNoteDialog(
                        context: context,
                        ref: ref,
                        currentNote: currentOrder.note,
                      );
                      // null = cancelled (leave as-is); '' = cleared.
                      if (result == null) return;
                      ref
                          .read(orderProvider.notifier)
                          .setNote(result.isEmpty ? null : result);
                    },
                    icon: Icon(
                      currentOrder.hasNote
                          ? Icons.sticky_note_2
                          : Icons.sticky_note_2_outlined,
                      size: 28,
                    ),
                    tooltip: currentOrder.hasNote
                        ? currentOrder.note
                        : l10n.translate('order_note'),
                    // Filled + coloured when set, so "there is a note" reads at
                    // a glance without the banner below being in view.
                    color: currentOrder.hasNote
                        ? Colors.deepPurple
                        : Theme.of(context).colorScheme.primary,
                  ),
                // Hold button — only when panel has items
                if (currentOrder.items.isNotEmpty)
                  IconButton(
                    onPressed: () => _holdOrder(ref),
                    icon: const Icon(Icons.pause_circle_outline, size: 28),
                    tooltip: l10n.translate('hold_order'),
                    color: Theme.of(context).colorScheme.primary,
                  ),
                if (currentOrder.items.isNotEmpty)
                  IconButton(
                    onPressed: () => _handleClear(context, ref),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.red,
                      size: 40,
                    ),
                    tooltip: l10n.translate('clear'),
                  ),
              ],
            ),
          ),

          // Order-level note. Surfaced here, under the header, because it goes
          // to the kitchen — the cashier needs to see that one is attached
          // without reopening the dialog. Tinted like the KDS banner so the two
          // read as the same thing.
          if (currentOrder.hasNote)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              color: const Color(0xFFFFE4E6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.sticky_note_2,
                    size: 16,
                    color: Color(0xFF9F1239),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      currentOrder.note!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF881337),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Ticket-division hint. The actual split (which line goes to which
          // ticket) is drawn and edited on the payment screen — this is just
          // "the cashier should know this order is already divided" while
          // looking at the same order here, on the table/cart panel, before
          // ever opening Pay. Local-only (see [ticketDraftGroupsProvider]):
          // never a fact the server or the printed ticket carries.
          if (currentOrder.orderId != null)
            Consumer(
              builder: (context, ref, _) {
                final ticketCount =
                    ref
                        .watch(
                          ticketDraftTicketCountProvider(currentOrder.orderId!),
                        )
                        .valueOrNull ??
                    0;
                if (ticketCount <= 1) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  color: Theme.of(
                    context,
                  ).colorScheme.primaryContainer.withValues(alpha: 0.5),
                  child: Row(
                    children: [
                      Icon(
                        Icons.call_split_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l10n
                              .translate('order_already_split')
                              .replaceAll('{0}', '$ticketCount'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

          // Order Items
          Expanded(
            child: currentOrder.items.isEmpty
                ? LayoutBuilder(
                    builder: (ctx, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.shopping_cart_outlined,
                              size: 80,
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              l10n.translate('no_items'),
                              style: TextStyle(
                                fontSize: 16,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 20),
                            // Fast-access button to resume an unpaid / on-hold
                            // order. Hidden when items are in the cart so the
                            // cashier can't accidentally swap the working
                            // order mid-build.
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: ElevatedButton.icon(
                                onPressed: () =>
                                    _openResumeDialog(context, ref),
                                icon: const Icon(
                                  Icons.pending_actions,
                                  size: 20,
                                ),
                                label: Text(l10n.translate('resume_order')),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppTheme.brMd,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            // Held RAM orders
                            if (heldOrders.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.pause_circle_outline,
                                      size: 14,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      l10n.translate('held_orders'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...heldOrders.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final held = entry.value;
                                // Units, not lines: "3 articles" should mean three
                                // things to hand over. Formatted so a whole count
                                // reads "3" rather than "3.0", while a weighed line
                                // keeps its decimals.
                                final unitCount = held.items.fold<double>(
                                  0,
                                  (s, i) => s + i.quantity,
                                );
                                final itemCount =
                                    unitCount == unitCount.roundToDouble()
                                    ? unitCount.toStringAsFixed(0)
                                    : unitCount.toStringAsFixed(3);
                                // What is actually in it. A held order is otherwise
                                // just a code and a total — the waiter has no way to
                                // tell two parked tables apart without resuming one.
                                const previewLimit = 3;
                                final preview = held.items
                                    .take(previewLimit)
                                    .map((i) {
                                      final q =
                                          i.quantity ==
                                              i.quantity.roundToDouble()
                                          ? i.quantity.toStringAsFixed(0)
                                          : i.quantity.toStringAsFixed(3);
                                      return '${q}x ${i.productName}';
                                    })
                                    .join(' · ');
                                // Count the REMAINING lines explicitly rather than
                                // relying on the ellipsis: "+4" tells the waiter how
                                // much they cannot see, which a fade does not.
                                final hidden = held.items.length - previewLimit;
                                final total = held.total;
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 3,
                                  ),
                                  child: InkWell(
                                    onTap: () => _resumeHeldOrder(ref, idx),
                                    borderRadius: AppTheme.brMd,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.4),
                                        ),
                                        borderRadius: AppTheme.brMd,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primaryContainer
                                            .withValues(alpha: 0.2),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.shopping_cart_outlined,
                                            size: 16,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  held.orderCode != null
                                                      ? held.orderCode!
                                                      : '${l10n.translate('order')} #${idx + 1}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  '$itemCount ${l10n.translate('items')}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                                if (preview.isNotEmpty)
                                                  Text(
                                                    hidden > 0
                                                        ? '$preview  +$hidden'
                                                        : preview,
                                                    // Two lines then ellipsis: the
                                                    // card must stay a fixed, glanceable
                                                    // size no matter how big the order
                                                    // is, so a 40-line table cannot
                                                    // push the list off screen.
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      height: 1.25,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant
                                                          .withValues(
                                                            alpha: 0.85,
                                                          ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            currencyFormatter.format(total),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Icon(
                                            Icons.chevron_right,
                                            size: 16,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        ), // Column
                      ), // ConstrainedBox
                    ), // SingleChildScrollView
                  ) // LayoutBuilder
                : Builder(
                    builder: (context) {
                      final layout = orderPanelRowOrder(currentOrder.items);
                      final ordered = layout.ordered;
                      final showSeparator = layout.showSeparator;
                      final separatorAt = layout.separatorAt;
                      final cancelledAsRows = ref.watch(settingsProvider
                          .select((s) => s.showCancelledItemsAsRows));
                      final liveRows =
                          currentOrder.items.length + (showSeparator ? 1 : 0);

                      return ListView.builder(
                        padding: const EdgeInsets.all(2),
                        itemCount: liveRows + (cancelledAsRows ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == liveRows) {
                            return CancelledItemRows(order: currentOrder);
                          }
                          if (showSeparator && index == separatorAt) {
                            return _SentToKitchenSeparator(
                              label: l10n.translate('already_sent_to_kitchen'),
                            );
                          }
                          final pos = showSeparator && index > separatorAt
                              ? index - 1
                              : index;
                          // Index into currentOrder.items — removeItem,
                          // _showItemOptions and _CourseChip all address the order
                          // by it, so it must stay the REAL position, not the row.
                          final invertedIndex = ordered[pos];
                          final item = currentOrder.items[invertedIndex];
                          final isPaid = item.ticketId != null;
                          final isHeld = item.state == 'ONHOLD';

                          return Dismissible(
                            dragStartBehavior: DragStartBehavior.down,
                            key: ValueKey("${item.hashCode}"),
                            // Disable dismiss for paid items
                            confirmDismiss: isPaid
                                ? (_) async => false
                                : (direction) async {
                                    if (!_canEditItem(
                                      ref,
                                      item,
                                      Permissions.ordersItemRemove,
                                    )) {
                                      _showPermissionDenied(context, ref);
                                      return false;
                                    }
                                    // Removing the last line of a saved order would leave
                                    // an empty order in the DB — cancel the whole order
                                    // instead. Always return false: the clearOrder()
                                    // rebuild removes the tile on success, and on
                                    // cancel/denied the item must stay put (returning true
                                    // would let onDismissed double-remove it).
                                    if (_isLastItemOfSavedOrder(ref)) {
                                      await _confirmCancelWholeOrder(
                                        context,
                                        ref,
                                      );
                                      return false;
                                    }
                                    return true;
                                  },
                            direction: isPaid
                                ? DismissDirection.none
                                : DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              color: Colors.red,
                              child: const Icon(
                                Icons.delete,
                                color: Colors.white,
                              ),
                            ),
                            onDismissed: (direction) {
                              ref
                                  .read(orderProvider.notifier)
                                  .removeItem(invertedIndex);
                            },
                            child: GestureDetector(
                              onLongPress: isPaid
                                  ? () => _showDeletePaidItemDialog(
                                      context,
                                      ref,
                                      item,
                                    )
                                  : null,
                              child: Opacity(
                                opacity: isPaid ? 0.6 : 1.0,
                                child: Card(
                                  elevation: isPaid ? 0.5 : 1,
                                  color: isPaid
                                      ? Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.5)
                                      : isHeld
                                      ? AppTheme.tintFill(
                                          context,
                                          Colors.orange,
                                        )
                                      : Theme.of(context).cardColor,
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 1.5,
                                    horizontal: 3,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppTheme.brSm,
                                    side: BorderSide(
                                      color: isPaid
                                          ? Theme.of(context)
                                                .colorScheme
                                                .outline
                                                .withValues(alpha: 0.2)
                                          : isHeld
                                          ? AppTheme.tintBorder(
                                              context,
                                              Colors.orange,
                                            )
                                          : Theme.of(context).dividerColor
                                                .withValues(alpha: 0.5),
                                      width: isPaid
                                          ? 0.5
                                          : (isHeld ? 1.5 : 0.5),
                                    ),
                                  ),
                                  child: InkWell(
                                    onTap: isPaid
                                        ? null
                                        : () => _showItemOptions(
                                            context,
                                            ref,
                                            invertedIndex,
                                            item,
                                          ),
                                    borderRadius: AppTheme.brSm,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 4,
                                      ),
                                      child: IntrinsicHeight(
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // 0. Course chip — only when the shop
                                            // works in courses, and never on a
                                            // paid line (its ticket is printed).
                                            if (ref
                                                    .watch(settingsProvider)
                                                    .coursesEnabled &&
                                                !isPaid) ...[
                                              _CourseChip(
                                                item: item,
                                                index: invertedIndex,
                                              ),
                                              const SizedBox(width: 4),
                                            ],
                                            // 1. Quantity Section (Left)
                                            Center(
                                              child: isPaid
                                                  ? Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .surfaceContainerHighest,
                                                        borderRadius:
                                                            AppTheme.brSm,
                                                        border: Border.all(
                                                          color:
                                                              Theme.of(context)
                                                                  .dividerColor
                                                                  .withValues(
                                                                    alpha: 0.5,
                                                                  ),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        formatQty(
                                                          item.quantity,
                                                        ),
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 12,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                      ),
                                                    )
                                                  : item.isWeighedItem
                                                  // Weighed items — show weight badge with long-press to edit.
                                                  ? InkWell(
                                                      onLongPress: () =>
                                                          _showQuantityDialog(
                                                            context,
                                                            ref,
                                                            invertedIndex,
                                                            item,
                                                          ),
                                                      borderRadius:
                                                          AppTheme.brSm,
                                                      child: Container(
                                                        constraints:
                                                            const BoxConstraints(
                                                              minWidth: 36,
                                                              minHeight: 36,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 4,
                                                            ),
                                                        alignment:
                                                            Alignment.center,
                                                        decoration:
                                                            BoxDecoration(
                                                              color: Colors.teal
                                                                  .withValues(
                                                                    alpha: 0.1,
                                                                  ),
                                                              borderRadius:
                                                                  AppTheme.brSm,
                                                              border: Border.all(
                                                                color: Colors
                                                                    .teal
                                                                    .withValues(
                                                                      alpha:
                                                                          0.5,
                                                                    ),
                                                              ),
                                                            ),
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          mainAxisSize:
                                                              MainAxisSize.min,
                                                          children: [
                                                            Text(
                                                              formatQty(
                                                                item.quantity,
                                                              ),
                                                              style: const TextStyle(
                                                                color:
                                                                    Colors.teal,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 11,
                                                              ),
                                                            ),
                                                            const Text(
                                                              'kg',
                                                              style: TextStyle(
                                                                color:
                                                                    Colors.teal,
                                                                fontSize: 9,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    )
                                                  : InkWell(
                                                      onTap: () {
                                                        if (!_canSetQuantity(
                                                          ref,
                                                          item,
                                                          item.quantity + 1,
                                                        )) {
                                                          _showPermissionDenied(
                                                            context,
                                                            ref,
                                                          );
                                                          return;
                                                        }
                                                        ref
                                                            .read(
                                                              orderProvider
                                                                  .notifier,
                                                            )
                                                            .updateItemQuantity(
                                                              invertedIndex,
                                                              item.quantity + 1,
                                                            );
                                                      },
                                                      onLongPress: () =>
                                                          _showQuantityDialog(
                                                            context,
                                                            ref,
                                                            invertedIndex,
                                                            item,
                                                          ),
                                                      borderRadius:
                                                          AppTheme.brSm,
                                                      child: Container(
                                                        constraints:
                                                            const BoxConstraints(
                                                              minWidth: 36,
                                                              minHeight: 36,
                                                            ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 4,
                                                            ),
                                                        alignment:
                                                            Alignment.center,
                                                        decoration: BoxDecoration(
                                                          color:
                                                              Theme.of(context)
                                                                  .colorScheme
                                                                  .primaryContainer
                                                                  .withValues(
                                                                    alpha: 0.7,
                                                                  ),
                                                          borderRadius:
                                                              AppTheme.brSm,
                                                          border: Border.all(
                                                            color:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .primary
                                                                    .withValues(
                                                                      alpha:
                                                                          0.3,
                                                                    ),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          formatQty(
                                                            item.quantity,
                                                          ),
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 16,
                                                            color: Theme.of(context)
                                                                .colorScheme
                                                                .onPrimaryContainer,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                            ),

                                            const SizedBox(width: 8),

                                            // 2. Product Details (Middle)
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  // Product Name and Lock Icon
                                                  Row(
                                                    children: [
                                                      if (isPaid) ...[
                                                        Icon(
                                                          Icons.lock_outline,
                                                          size: 12,
                                                          color: Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant,
                                                        ),
                                                        const SizedBox(
                                                          width: 3,
                                                        ),
                                                      ],
                                                      Expanded(
                                                        child: Text(
                                                          item.displayName,
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 13,
                                                            decoration: isPaid
                                                                ? TextDecoration
                                                                      .lineThrough
                                                                : null,
                                                            decorationColor:
                                                                Theme.of(
                                                                      context,
                                                                    )
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                            color: isPaid
                                                                ? Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .onSurfaceVariant
                                                                : null,
                                                            height: 1.1,
                                                          ),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      ),
                                                      // How long the kitchen has
                                                      // had it. Only on lines that
                                                      // actually went — an unsent
                                                      // line has nothing to count
                                                      // from.
                                                      if (item.kdsPrintedAt !=
                                                          null)
                                                        _ElapsedBadge(
                                                          since: item
                                                              .kdsPrintedAt!,
                                                        ),
                                                    ],
                                                  ),

                                                  // Unit name label
                                                  if (item.unitName != null &&
                                                      item
                                                          .unitName!
                                                          .isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      item.unitName!,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.primary,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        height: 1.1,
                                                      ),
                                                    ),
                                                  ],

                                                  // Components (Compact)
                                                  if (item
                                                      .components
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 2),
                                                    Wrap(
                                                      spacing: 4,
                                                      runSpacing: 2,
                                                      // A removed default reads as
                                                      // "SANS x"; the zero-quantity
                                                      // signal row beside it carries
                                                      // no meaning for a reader and
                                                      // is left out.
                                                      children: item.components
                                                          .where(
                                                            (comp) =>
                                                                comp.removalCharge ||
                                                                comp.quantity >
                                                                    0,
                                                          )
                                                          .map(
                                                            (comp) => Text(
                                                              comp.removalCharge
                                                                  ? '${AppLocalizations.of(context)!.translate('without')} ${comp.name}'
                                                                  : '+ ${comp.name} (${comp.quantity})',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontWeight:
                                                                    comp.removalCharge
                                                                    ? FontWeight
                                                                          .bold
                                                                    : null,
                                                                color: Theme.of(context)
                                                                    .colorScheme
                                                                    .onSurfaceVariant,
                                                                height: 1.1,
                                                              ),
                                                            ),
                                                          )
                                                          .toList(),
                                                    ),
                                                  ],

                                                  // Weighed item detail line
                                                  if (item.isWeighedItem &&
                                                      item.weightKg != null &&
                                                      item.weightKg! > 0) ...[
                                                    const SizedBox(height: 3),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.scale,
                                                          size: 10,
                                                          color:
                                                              Colors.teal[600],
                                                        ),
                                                        const SizedBox(
                                                          width: 3,
                                                        ),
                                                        Flexible(
                                                          child: Text(
                                                            item.pricePerKgDisplay !=
                                                                    null
                                                                ? '${item.weightKg!.toStringAsFixed(3)} kg × ${item.pricePerKgDisplay!.toStringAsFixed(2)}/kg'
                                                                : '${item.weightKg!.toStringAsFixed(3)} kg',
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              color: Colors
                                                                  .teal[700],
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              height: 1.1,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],

                                                  // Serial number. Shown on the
                                                  // line because it is the one
                                                  // detail the cashier has to check
                                                  // against the box in the
                                                  // customer's hand before payment.
                                                  if (item.serialNumber !=
                                                          null &&
                                                      item
                                                          .serialNumber!
                                                          .isNotEmpty) ...[
                                                    const SizedBox(height: 3),
                                                    Row(
                                                      children: [
                                                        Icon(
                                                          Icons.qr_code_2,
                                                          size: 11,
                                                          color: Theme.of(
                                                            context,
                                                          ).colorScheme.primary,
                                                        ),
                                                        const SizedBox(
                                                          width: 3,
                                                        ),
                                                        Expanded(
                                                          child: Text(
                                                            item.serialNumber!,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontFamily:
                                                                  'monospace',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color:
                                                                  Theme.of(
                                                                        context,
                                                                      )
                                                                      .colorScheme
                                                                      .primary,
                                                            ),
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ],

                                                  // Note (Compact)
                                                  if (item.note != null &&
                                                      item
                                                          .note!
                                                          .isNotEmpty) ...[
                                                    const SizedBox(height: 3),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 4,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        borderRadius:
                                                            AppTheme.brSm,
                                                        border: Border.all(),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            Icons.sticky_note_2,
                                                            size: 9,
                                                            color: Colors
                                                                .amber[800],
                                                          ),
                                                          const SizedBox(
                                                            width: 3,
                                                          ),
                                                          Flexible(
                                                            child: Text(
                                                              item.note!,
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                fontStyle:
                                                                    FontStyle
                                                                        .italic,
                                                                height: 1.1,
                                                              ),
                                                              maxLines: 5,
                                                              overflow:
                                                                  TextOverflow
                                                                      .visible,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],

                                                  // Badges Row
                                                  if (isPaid ||
                                                      (isHeld && !isPaid)) ...[
                                                    const SizedBox(height: 4),
                                                    Row(
                                                      children: [
                                                        if (isPaid)
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                            margin:
                                                                const EdgeInsets.only(
                                                                  right: 4,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  AppTheme.tintFill(
                                                                    context,
                                                                    Colors
                                                                        .green,
                                                                  ),
                                                              borderRadius:
                                                                  AppTheme.brSm,
                                                              border: Border.all(
                                                                color:
                                                                    AppTheme.tintBorder(
                                                                      context,
                                                                      Colors
                                                                          .green,
                                                                    ),
                                                              ),
                                                            ),
                                                            child: Text(
                                                              'Ticket #${item.ticketId}',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color:
                                                                    AppTheme.tintOn(
                                                                      context,
                                                                      Colors
                                                                          .green,
                                                                    ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                              ),
                                                            ),
                                                          ),
                                                        if (isHeld && !isPaid)
                                                          Container(
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  horizontal: 6,
                                                                  vertical: 2,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  AppTheme.tintFill(
                                                                    context,
                                                                    Colors
                                                                        .orange,
                                                                  ),
                                                              borderRadius:
                                                                  AppTheme.brSm,
                                                              border: Border.all(
                                                                color:
                                                                    AppTheme.tintBorder(
                                                                      context,
                                                                      Colors
                                                                          .orange,
                                                                    ),
                                                              ),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Icon(
                                                                  Icons
                                                                      .pause_circle_outline,
                                                                  size: 10,
                                                                  color: AppTheme.tintOn(
                                                                    context,
                                                                    Colors
                                                                        .orange,
                                                                  ),
                                                                ),
                                                                const SizedBox(
                                                                  width: 4,
                                                                ),
                                                                Text(
                                                                  'Held',
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        10,
                                                                    color: Colors
                                                                        .orange[800],
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),

                                            const SizedBox(width: 6),

                                            // 3. Price & Actions (Right)
                                            Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.end,
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                // Price
                                                Text(
                                                  currencyFormatter.format(
                                                    item.totalPrice,
                                                  ),
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                    color: isPaid
                                                        ? Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant
                                                        : null,
                                                  ),
                                                ),
                                                // Discount
                                                if (item.totalDiscount > 0)
                                                  Text(
                                                    '-${currencyFormatter.format(item.totalDiscount)}',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      color: Colors.orange[800],
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),

                                                // Action Button (Note)
                                                if (!isPaid) ...[
                                                  const SizedBox(height: 4),
                                                  SizedBox(
                                                    width: 26,
                                                    height: 26,
                                                    child: IconButton(
                                                      onPressed: () =>
                                                          _showNoteDialog(
                                                            context,
                                                            ref,
                                                            invertedIndex,
                                                            item,
                                                          ),
                                                      icon: Icon(
                                                        item.note != null &&
                                                                item
                                                                    .note!
                                                                    .isNotEmpty
                                                            ? Icons
                                                                  .sticky_note_2
                                                            : Icons
                                                                  .sticky_note_2_outlined,
                                                        size: 20,
                                                        color:
                                                            item.note != null &&
                                                                item
                                                                    .note!
                                                                    .isNotEmpty
                                                            ? Colors.amber[700]
                                                            : Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant
                                                                  .withValues(
                                                                    alpha: 0.6,
                                                                  ),
                                                      ),
                                                      tooltip: 'Note',
                                                      padding: EdgeInsets.zero,
                                                      visualDensity:
                                                          VisualDensity.compact,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          // Order Summary
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Subtotal row
                if (currentOrder.discountPercentage > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.translate('subtotal'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        currencyFormatter.format(currentOrder.subtotal),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.percent,
                            size: 12,
                            color: Colors.orange[700],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${l10n.translate('discount')} (${currentOrder.discountPercentage.toStringAsFixed(0)}%):',
                            style: TextStyle(
                              color: Colors.orange[700],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '-${currencyFormatter.format(currentOrder.discountAmount)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${l10n.translate('subtotal')}:',
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text(
                        currencyFormatter.format(currentOrder.subtotal),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${l10n.translate('tax')}:',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      currencyFormatter.format(currentOrder.tax),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                // What was taken off this order — recorded, or swiped away and
                // not saved yet. Informational: it is not subtracted again.
                if (!ref.watch(settingsProvider
                    .select((s) => s.showCancelledItemsAsRows)))
                  CancelledSummaryRow(order: currentOrder),
                // Delivery fee — its own line, deliberately after the tax row
                // and outside the subtotal: it is not a product sale. Shown
                // whenever one is recorded, including an explicit 0, because
                // "Delivery: free" is information the cashier states out loud.
                if (currentOrder.hasDeliveryFee) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.delivery_dining,
                            size: 13,
                            color: Colors.blue[700],
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${l10n.translate('delivery_fee')}:',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue[700],
                            ),
                          ),
                        ],
                      ),
                      Text(
                        currentOrder.deliveryFeeAmount > 0
                            ? currencyFormatter.format(
                                currentOrder.deliveryFeeAmount,
                              )
                            : l10n.translate('free'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                ],
                const Divider(height: 14),
                // Total row — prominent. Carries the delivery fee because this
                // is what the customer hands over; the products total above is
                // what the sales figures are built from.
                Row(
                  children: [
                    Text(
                      '${l10n.translate('total')}:',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currencyFormatter.format(currentOrder.amountDue),
                        textAlign: TextAlign.end,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showQuantityDialog(
    BuildContext context,
    WidgetRef ref,
    int index,
    OrderItem item,
  ) {
    // Note: no up-front _canEditItem gate. The qty dialog opens for any item.
    // The decrement floor is enforced on submit via _canSetQuantity.
    final TextEditingController controller = TextEditingController(
      text: formatQty(item.quantity),
    );

    void trySubmit() {
      final qty = double.tryParse(controller.text.replaceAll(',', '.'));
      if (qty == null || qty <= 0) return;
      final rounded = double.parse(qty.toStringAsFixed(3));
      if (!_canSetQuantity(ref, item, rounded)) {
        _showPermissionDenied(context, ref);
        return;
      }
      ref.read(orderProvider.notifier).updateItemQuantity(index, rounded);
      Navigator.pop(context);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Quantity'),
        content: AdaptiveKeyboardTextField(
          controller: controller,
          autofocus: true, // Auto-focus to show on-screen keyboard immediately
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: AppTheme.brMd),
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
          ),
          onSubmitted: (_) => trySubmit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(onPressed: trySubmit, child: const Text('OK')),
        ],
      ),
    );
  }

  void _showNoteDialog(
    BuildContext context,
    WidgetRef ref,
    int index,
    OrderItem item,
  ) {
    if (!_canEditItem(ref, item, Permissions.ordersItemModify)) {
      _showPermissionDenied(context, ref);
      return;
    }
    final TextEditingController controller = TextEditingController(
      text: item.note ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.sticky_note_2, color: Colors.amber[700]),
            const SizedBox(width: 8),
            const Text('Item Note'),
          ],
        ),
        content: AdaptiveKeyboardTextField(
          controller: controller,
          autofocus: true, // Auto-focus to show on-screen keyboard immediately
          keyboardType: TextInputType.text,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Add special instructions or notes...',
            border: OutlineInputBorder(borderRadius: AppTheme.brMd),
            filled: true,
            fillColor: AppTheme.tintFill(context, Colors.amber),
          ),
        ),
        actions: [
          if (item.note != null && item.note!.isNotEmpty)
            TextButton(
              onPressed: () {
                final updatedItem = item.copyWith(note: '');
                ref.read(orderProvider.notifier).updateItem(index, updatedItem);
                Navigator.pop(context);
              },
              child: const Text('Clear', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final updatedItem = item.copyWith(note: controller.text.trim());
              ref.read(orderProvider.notifier).updateItem(index, updatedItem);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Tag an order line with its course: entrée, plat or dessert.
///
/// A chip rather than a menu entry because assigning courses is a per-line
/// rhythm — the cashier rings in a starter, taps E, rings in a main, taps P —
/// and burying it two taps deep in the modify dialog would make the feature
/// cost more than it saves. Untagged lines show a muted outline, so an order
/// halfway through being tagged is obvious at a glance.
/// Row layout for the order panel: which order line each row shows, and where
/// the "already sent" separator goes.
///
/// Splits the panel into what the kitchen has NOT seen yet and what it already
/// has, so the cashier can tell at a glance which lines this round added.
///
/// A line counts as new while it still has units beyond `kdsPrintedQuantity` —
/// the same predicate the KDS delta runs on
/// (`PrintingService._filterItemsByMode`). So a line bumped from 1 to 3 reads
/// as new, because the kitchen is owed 2 more of it, and a paid line never
/// does.
///
/// Both groups keep the panel's existing newest-first order, so a line only
/// moves when it genuinely has unsent units.
///
/// [ordered] holds indices into [items] — NOT row numbers. Callers address the
/// order by these (removeItem, _showItemOptions, _CourseChip all take the real
/// position), so getting this mapping wrong would act on the wrong line.
({List<int> ordered, int separatorAt, bool showSeparator}) orderPanelRowOrder(
  List<OrderItem> items,
) {
  final newIndices = <int>[];
  final sentIndices = <int>[];
  for (var i = items.length - 1; i >= 0; i--) {
    final it = items[i];
    final hasUnsent =
        it.ticketId == null && it.quantity > it.kdsPrintedQuantity;
    (hasUnsent ? newIndices : sentIndices).add(i);
  }
  return (
    ordered: [...newIndices, ...sentIndices],
    separatorAt: newIndices.length,
    // Only worth a separator when there is something on each side of it — a
    // brand-new order is all new, and a fully sent one has nothing to mark off.
    showSeparator: newIndices.isNotEmpty && sentIndices.isNotEmpty,
  );
}

/// Marks where the newly added lines stop and the ones the kitchen already has
/// begin. Everything ABOVE it is what this round added.
///
/// Only rendered when there is something on both sides of it — see the
/// `showSeparator` check in the order list.
class _SentToKitchenSeparator extends StatelessWidget {
  const _SentToKitchenSeparator({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.outline;

    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 4),
      child: Row(
        children: [
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: color.withValues(alpha: 0.4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 12, color: color),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Divider(
              height: 1,
              thickness: 1,
              color: color.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseChip extends ConsumerWidget {
  final OrderItem item;
  final int index;

  const _CourseChip({required this.item, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final course = OrderCourse.fromNumber(item.courseNo);
    final tagged = course != null;

    // Stretches to the full height of the line (the row is wrapped in an
    // IntrinsicHeight), so a tall line with options is one big target.
    return SizedBox(
      height: double.infinity,
      child: PopupMenuButton<int>(
        tooltip: l10n.translate('set_course'),
        padding: EdgeInsets.zero,
        // 0 is the "no course" entry: null cannot be a PopupMenuItem value and
        // still be told apart from a dismissed menu.
        onSelected: (value) => ref
            .read(orderProvider.notifier)
            .updateItem(
              index,
              item.copyWith(
                courseNo: value == 0 ? null : value,
                clearCourse: value == 0,
              ),
            ),
        itemBuilder: (_) => [
          for (final c in OrderCourse.values)
            PopupMenuItem(
              value: c.number,
              child: Row(
                children: [
                  if (c.number == item.courseNo)
                    const Icon(Icons.check, size: 16)
                  else
                    const SizedBox(width: 16),
                  const SizedBox(width: 8),
                  Text(l10n.translate(c.labelKey)),
                ],
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 0,
            child: Row(
              children: [
                const SizedBox(width: 16),
                const SizedBox(width: 8),
                Text(l10n.translate('no_course')),
              ],
            ),
          ),
        ],
        child: Container(
          // Deliberately larger than a normal chip: this is tapped on every
          // line of a coursed order, on a touchscreen, by someone holding a
          // pad in the other hand. A 26px target was a miss waiting to happen.
          width: 52,
          constraints: const BoxConstraints(minHeight: 44),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tagged
                ? scheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: AppTheme.brSm,
            border: Border.all(
              color: tagged
                  ? scheme.primary.withValues(alpha: 0.5)
                  : scheme.outlineVariant,
            ),
          ),
          child: tagged
              ? Text(
                  l10n.translate(course.badgeKey),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                )
              : Icon(
                  Icons.restaurant_menu,
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }
}

/// "How long ago did this go to the kitchen", ticking on its own.
///
/// Its own widget with its own timer rather than a rebuild of the whole panel:
/// the panel redraws on every cart change and does not need a clock attached
/// to it, and a badge that only refreshed when something else happened would
/// sit reading "2m" through a twenty-minute wait — which is worse than no
/// badge, because it looks like information.
class _ElapsedBadge extends StatefulWidget {
  const _ElapsedBadge({required this.since});

  final DateTime since;

  @override
  State<_ElapsedBadge> createState() => _ElapsedBadgeState();
}

class _ElapsedBadgeState extends State<_ElapsedBadge> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // A minute is the resolution the label itself has, so anything finer would
    // be redraws nobody can see.
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = elapsedLabel(
      widget.since,
      locale: Localizations.localeOf(context).languageCode,
    );
    if (label.isEmpty) return const SizedBox.shrink();

    // Loud once the food has been out there a while. The threshold is the
    // point a cashier would want to go and ask, not an SLA.
    final stale =
        DateTime.now().difference(widget.since) >= const Duration(minutes: 30);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: (stale ? scheme.error : scheme.onSurfaceVariant).withValues(
            alpha: 0.12,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            height: 1.1,
            fontWeight: FontWeight.w600,
            color: stale ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// "🎫 Sara pickup" under the order code, or "+ Reference" when none is set.
class _ReferenceLine extends StatelessWidget {
  final String? reference;
  final VoidCallback onTap;

  const _ReferenceLine({required this.reference, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final text = (reference ?? '').trim();
    final has = text.isNotEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              has ? Icons.confirmation_number_outlined : Icons.add,
              size: 14,
              color: scheme.primary,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                has ? text : l10n.translate('order_reference'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: has ? FontWeight.w600 : FontWeight.normal,
                  color: has ? scheme.onSurface : scheme.primary,
                  decoration: has ? null : TextDecoration.underline,
                ),
              ),
            ),
            if (has) ...[
              const SizedBox(width: 4),
              Icon(Icons.edit_outlined, size: 12, color: scheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}

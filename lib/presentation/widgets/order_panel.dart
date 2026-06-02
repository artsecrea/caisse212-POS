import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/order_provider.dart';
import '../../domain/models/order_models.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/app_localizations.dart';
import '../../utils/snackbar_helper.dart';
import '../../services/permission_service.dart';
import '../../providers/database_providers.dart';
import '../../providers/network_provider.dart';
import '../../data/database/app_database.dart';
import 'product_modification_dialog.dart' show ProductModificationDialog;


class OrderPanel extends ConsumerWidget {
  const OrderPanel({Key? key}) : super(key: key);

  /// Whether [item] can be removed/modified. Always allowed for a brand-new
  /// (unsaved) cart, or for an item that hasn't been persisted yet (`item.id ==
  /// null`) — e.g. just added to a loaded saved order by mistake. Only items that
  /// are already saved in the order require the granular permission (anti-fraud).
  bool _canEditItem(WidgetRef ref, OrderItem item, String permission) {
    final order = ref.read(orderProvider);
    if (order.orderId == null || item.id == null) return true;
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
  bool _canSetQuantity(WidgetRef ref, OrderItem item, int newQty) {
    final order = ref.read(orderProvider);
    if (order.orderId == null || item.id == null) return true;
    final saved = item.savedQuantity ?? 0;
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
    SnackBarHelper.showErrorSnackBar(context, ref, l10n.translate('no_permission'));
  }

  /// The trash/clear button. Only empties the in-memory working panel; the
  /// persisted order (if any) is left intact. Order deletion lives in the
  /// dedicated orders-management screen.
  Future<void> _handleClear(BuildContext context, WidgetRef ref) async {
    ref.read(orderProvider.notifier).clearOrder();
  }

  void _showItemOptions(BuildContext context, WidgetRef ref, int index, OrderItem item) async {
    if (!_canEditItem(ref, item, Permissions.ordersItemModify)) {
      _showPermissionDenied(context, ref);
      return;
    }
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProductModificationDialog(
        product: item,
        isEditMode: true,
      ),
    );

    if (result != null) {
      // Closing the dialog's qty-edit loophole: a cashier with item:modify
      // but not item:remove could otherwise type a smaller qty here and slip
      // a below-baseline reduction past the gate.
      final newQty = result['quantity'] as int? ?? item.quantity;
      if (newQty != item.quantity &&
          !_canSetQuantity(ref, item, newQty)) {
        if (context.mounted) _showPermissionDenied(context, ref);
        return;
      }
      // Update the item with new modifications
      final updatedItem = item.copyWith(
        components: result['components'] as List<OrderItemComponent>?,
        discount: result['discount'] as double?,
        manualDiscount: result['manualDiscount'] as double?,
        quantity: result['quantity'] as int?,
        note: result['note'] as String?,
        planStartAt: result['planStartAt'] as DateTime?,
        planEndAt: result['planEndAt'] as DateTime?,
        planWaiterId: result['planWaiterId'] as int?,
      );
      ref.read(orderProvider.notifier).updateItem(index, updatedItem);
    }
  }

  void _showDeletePaidItemDialog(BuildContext context, WidgetRef ref, OrderItem item) async {
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
            final ticketProducts = await (database.select(database.orderProducts)
              ..where((tbl) => tbl.ticketId.equals(item.ticketId!)))
                .get();

            // Delete the order product from database
            await (database.delete(database.orderProducts)
              ..where((tbl) => tbl.id.equals(item.id!)))
                .go();

            // Note: Order products are synced as part of the order, not individually

            // If this was the only item in the ticket, delete the ticket
            if (ticketProducts.length == 1) {
              // Get ticket and order info for sync
              final ticket = await (database.select(database.tickets)
                ..where((tbl) => tbl.id.equals(item.ticketId!)))
                  .getSingleOrNull();

              String? orderCode;
              String? ticketNum;

              if (ticket != null) {
                ticketNum = ticket.num;
                // Get order code
                final order = await (database.select(database.orders)
                  ..where((tbl) => tbl.id.equals(ticket.orderId)))
                    .getSingleOrNull();
                orderCode = order?.code;
              }

              await (database.delete(database.tickets)
                ..where((tbl) => tbl.id.equals(item.ticketId!)))
                  .go();

              // Queue or execute delete operation for ticket
              if (ticket != null && ticket.isSynced && orderCode != null && ticketNum != null) {
                await syncService.deleteTicketEntity(
                  entityId: item.ticketId!,
                  orderCode: orderCode,
                  ticketNum: ticketNum,
                  isOnline: isOnline,
                );
              }
            } else {
              // Otherwise, update the ticket amount
              final remainingProducts = await (database.select(database.orderProducts)
                ..where((tbl) => tbl.ticketId.equals(item.ticketId!)))
                  .get();

              final newTicketAmount = remainingProducts.fold<double>(
                0.0,
                (sum, product) => sum + (product.unitaryPrice * product.quantity),
              );

              await (database.update(database.tickets)
                ..where((tbl) => tbl.id.equals(item.ticketId!)))
                  .write(TicketsCompanion(
                amount: drift.Value(newTicketAmount),
              ));

              // Queue or execute update operation for ticket
              final ticket = await (database.select(database.tickets)
                ..where((tbl) => tbl.id.equals(item.ticketId!)))
                  .getSingleOrNull();

              if (ticket != null && ticket.isSynced) {
                // Get order code
                final order = await (database.select(database.orders)
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

            // Reload the current order from database to get updated state
            final currentOrder = ref.read(orderProvider);
            if (currentOrder.orderId != null) {
              // Fetch the updated order from database
              final orderRow = await (database.select(database.orders)
                ..where((tbl) => tbl.id.equals(currentOrder.orderId!)))
                  .getSingleOrNull();

              if (orderRow != null) {
                // Reload all order items with updated ticket IDs
                final orderProducts = await (database.select(database.orderProducts)
                  ..where((tbl) => tbl.orderId.equals(currentOrder.orderId!)))
                    .get();

                // Build updated items list
                final updatedItems = <OrderItem>[];
                for (final orderProduct in orderProducts) {
                  final product = await (database.select(database.products)
                    ..where((tbl) => tbl.id.equals(orderProduct.productId)))
                      .getSingleOrNull();

                  if (product != null) {
                    // Get components for this order product
                    final components = await (database.select(database.orderProductComponents)
                      ..where((tbl) => tbl.orderProductId.equals(orderProduct.id)))
                        .get();

                    final orderItemComponents = <OrderItemComponent>[];
                    for (final comp in components) {
                      final component = await (database.select(database.components)
                        ..where((tbl) => tbl.id.equals(comp.componentId)))
                          .getSingleOrNull();

                      if (component != null) {
                        orderItemComponents.add(OrderItemComponent(
                          componentId: component.id,
                          name: component.name,
                          price: component.price,
                          quantity: comp.quantity,
                          isSpecial: comp.isSpecial,
                        ));
                      }
                    }

                    updatedItems.add(OrderItem(
                      id: orderProduct.id,
                      productId: orderProduct.productId,
                      productName: product.name,
                      finalPrice: orderProduct.unitaryPrice,
                      quantity: orderProduct.quantity,
                      // Re-establish the decrement floor — without this the
                      // floor check in [_canSetQuantity] treats `saved` as 0
                      // and skips the `item:remove` gate entirely.
                      savedQuantity: orderProduct.quantity,
                      discount: orderProduct.unitaryDiscount,
                      manualDiscount: orderProduct.manualDiscount,
                      tva: orderProduct.unitaryTva,
                      components: orderItemComponents,
                      ticketId: orderProduct.ticketId,
                      state: orderProduct.state,
                      imageUrl: product.imageUrl,
                    ));
                  }
                }

                // Update the order with refreshed items
                ref.read(orderProvider.notifier).loadOrder(
                  currentOrder.copyWith(items: updatedItems),
                );
              }
            } else {
              // If no order ID, just remove from local state
              final itemIndex = currentOrder.items.indexWhere((i) => i.id == item.id);
              if (itemIndex != -1) {
                ref.read(orderProvider.notifier).removeItem(itemIndex);
              }
            }

            if (context.mounted) {
              final message = ticketProducts.length == 1
                  ? 'Paid item and ticket deleted successfully'
                  : 'Paid item deleted successfully';
              SnackBarHelper.showSuccessSnackBar(
                context,
                ref,
                message,
              );
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
          // Header
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
              border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shopping_cart,
                  color: Theme.of(context).colorScheme.primary,
                ),
                Text(
                  currentOrder.orderCode?.toString() ?? l10n.translate('current_order'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
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

          // Order Items
          Expanded(
            child: currentOrder.items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          size: 80,
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.translate('no_items'),
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(2),
                    itemCount: currentOrder.items.length,
                    itemBuilder: (context, index) {
                      final invertedIndex = currentOrder.items.length - 1 - index;
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
                          if (!_canEditItem(ref, item, Permissions.ordersItemRemove)) {
                            _showPermissionDenied(context, ref);
                            return false;
                          }
                          return true;
                        },
                        direction: isPaid ? DismissDirection.none : DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        onDismissed: (direction) {
                          ref.read(orderProvider.notifier).removeItem(invertedIndex);
                        },
                        child: GestureDetector(
                          onLongPress: isPaid
                              ? () => _showDeletePaidItemDialog(context, ref, item)
                              : null,
                          child: Opacity(
                            opacity: isPaid ? 0.6 : 1.0,
                            child: Card(
                              elevation: isPaid ? 0.5 : 1,
                              color: isPaid
                                  ? Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                                  : isHeld
                                      ? Colors.orange[50]
                                      : Theme.of(context).cardColor,
                              margin: const EdgeInsets.symmetric(vertical: 1.5, horizontal: 3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(
                                  color: isPaid
                                      ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)
                                      : isHeld
                                          ? Colors.orange[200]!
                                          : Theme.of(context).dividerColor.withValues(alpha: 0.5),
                                  width: isPaid ? 0.5 : (isHeld ? 1.5 : 0.5),
                                ),
                              ),
                              child: InkWell(
                                onTap: isPaid ? null : () => _showItemOptions(context, ref, invertedIndex, item),
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                  child: IntrinsicHeight(
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 1. Quantity Section (Left)
                                        Center(
                                          child: isPaid
                                              ? Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
                                                  ),
                                                  child: Text(
                                                    '${item.quantity}',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 12,
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                )
                                              : item.isWeighedItem
                                                  // Weighed items — show scale icon badge instead of qty tap button.
                                                  ? Container(
                                                      width: 36,
                                                      height: 36,
                                                      alignment: Alignment.center,
                                                      decoration: BoxDecoration(
                                                        color: Colors.teal.withValues(alpha: 0.1),
                                                        borderRadius: BorderRadius.circular(6),
                                                        border: Border.all(color: Colors.teal.withValues(alpha: 0.5)),
                                                      ),
                                                      child: const Icon(Icons.scale, color: Colors.teal, size: 18),
                                                    )
                                                  : InkWell(
                                                      onTap: () {
                                                        if (!_canSetQuantity(ref, item, item.quantity + 1)) {
                                                          _showPermissionDenied(context, ref);
                                                          return;
                                                        }
                                                        ref.read(orderProvider.notifier).updateItemQuantity(
                                                          invertedIndex,
                                                          item.quantity + 1
                                                        );
                                                      },
                                                      onLongPress: () => _showQuantityDialog(context, ref, invertedIndex, item),
                                                      borderRadius: BorderRadius.circular(6),
                                                      child: Container(
                                                        width: 36,
                                                        height: 36,
                                                        alignment: Alignment.center,
                                                        decoration: BoxDecoration(
                                                          color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.7),
                                                          borderRadius: BorderRadius.circular(6),
                                                          border: Border.all(
                                                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                                          ),
                                                        ),
                                                        child: Text(
                                                          '${item.quantity}',
                                                          style: TextStyle(
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 16,
                                                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                        ),

                                        const SizedBox(width: 8),

                                        // 2. Product Details (Middle)
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              // Product Name and Lock Icon
                                              Row(
                                                children: [
                                                  if (isPaid) ...[
                                                    Icon(
                                                      Icons.lock_outline,
                                                      size: 12,
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                    ),
                                                    const SizedBox(width: 3),
                                                  ],
                                                  Expanded(
                                                    child: Text(
                                                      item.displayName,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w600,
                                                        fontSize: 13,
                                                        decoration: isPaid ? TextDecoration.lineThrough : null,
                                                        decorationColor: Theme.of(context).colorScheme.onSurfaceVariant,
                                                        color: isPaid ? Theme.of(context).colorScheme.onSurfaceVariant : null,
                                                        height: 1.1,
                                                      ),
                                                      maxLines: 2,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),

                                              // Components (Compact)
                                              if (item.components.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Wrap(
                                                  spacing: 4,
                                                  runSpacing: 2,
                                                  children: item.components.map((comp) => Text(
                                                    '+ ${comp.name} (${comp.quantity})',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                      height: 1.1,
                                                    ),
                                                  )).toList(),
                                                ),
                                              ],

                                              // Weighed item detail line
                                              if (item.isWeighedItem && item.weightKg != null && item.weightKg! > 0) ...[
                                                const SizedBox(height: 3),
                                                Row(
                                                  children: [
                                                    Icon(Icons.scale, size: 10, color: Colors.teal[600]),
                                                    const SizedBox(width: 3),
                                                    Flexible(
                                                      child: Text(
                                                        item.pricePerKgDisplay != null
                                                            ? '${item.weightKg!.toStringAsFixed(3)} kg × ${item.pricePerKgDisplay!.toStringAsFixed(2)}/kg'
                                                            : '${item.weightKg!.toStringAsFixed(3)} kg',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          color: Colors.teal[700],
                                                          fontWeight: FontWeight.w600,
                                                          height: 1.1,
                                                        ),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],

                                              // Note (Compact)
                                              if (item.note != null && item.note!.isNotEmpty) ...[
                                                const SizedBox(height: 3),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    borderRadius: BorderRadius.circular(3),
                                                    border: Border.all(),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.sticky_note_2, size: 9, color: Colors.amber[800]),
                                                      const SizedBox(width: 3),
                                                      Flexible(
                                                        child: Text(
                                                          item.note!,
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            fontStyle: FontStyle.italic,
                                                            height: 1.1,
                                                          ),
                                                          maxLines: 5,
                                                          overflow: TextOverflow.visible,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],

                                              // Badges Row
                                              if (isPaid || (isHeld && !isPaid)) ...[
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    if (isPaid)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        margin: const EdgeInsets.only(right: 4),
                                                        decoration: BoxDecoration(
                                                          color: Colors.green[50],
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.green[200]!),
                                                        ),
                                                        child: Text(
                                                          'Ticket #${item.ticketId}',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.green[800],
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    if (isHeld && !isPaid)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: Colors.orange[50],
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.orange[200]!),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(Icons.pause_circle_outline, size: 10, color: Colors.orange[800]),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              'Held',
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: Colors.orange[800],
                                                                fontWeight: FontWeight.w600,
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
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            // Price
                                            Text(
                                              currencyFormatter.format(item.totalPrice),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                                color: isPaid ? Theme.of(context).colorScheme.onSurfaceVariant : null,
                                              ),
                                            ),
                                            // Discount
                                            if (item.totalDiscount > 0)
                                              Text(
                                                '-${currencyFormatter.format(item.totalDiscount)}',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  color: Colors.orange[800],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),

                                            // Action Button (Note)
                                            if (!isPaid) ...[
                                               const SizedBox(height: 4),
                                              SizedBox(
                                                width: 26,
                                                height: 26,
                                                child: IconButton(
                                                  onPressed: () => _showNoteDialog(context, ref, invertedIndex, item),
                                                  icon: Icon(
                                                    item.note != null && item.note!.isNotEmpty
                                                        ? Icons.sticky_note_2
                                                        : Icons.sticky_note_2_outlined,
                                                    size: 20,
                                                    color: item.note != null && item.note!.isNotEmpty
                                                        ? Colors.amber[700]
                                                        : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                                  ),
                                                  tooltip: 'Note',
                                                  padding: EdgeInsets.zero,
                                                  visualDensity: VisualDensity.compact,
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
                  ),
          ),
          // Order Summary
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Subtotal row
                if (currentOrder.discountPercentage > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.translate('subtotal'),
                          style: const TextStyle(fontSize: 12)),
                      Text(
                        currencyFormatter.format(currentOrder.subtotal),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.percent, size: 12, color: Colors.orange[700]),
                          const SizedBox(width: 3),
                          Text(
                            '${l10n.translate('discount')} (${currentOrder.discountPercentage.toStringAsFixed(0)}%):',
                            style: TextStyle(color: Colors.orange[700], fontSize: 12),
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
                      Text('${l10n.translate('subtotal')}:',
                          style: const TextStyle(fontSize: 12)),
                      Text(
                        currencyFormatter.format(currentOrder.subtotal),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${l10n.translate('tax')}:',
                        style: const TextStyle(fontSize: 12)),
                    Text(
                      currencyFormatter.format(currentOrder.tax),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(height: 14),
                // Total row — prominent
                Row(
                  children: [
                    Text(
                      '${l10n.translate('total')}:',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        currencyFormatter.format(currentOrder.total),
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

  void _showQuantityDialog(BuildContext context, WidgetRef ref, int index, OrderItem item) {
    // Note: no up-front _canEditItem gate. The qty dialog opens for any item.
    // The decrement floor is enforced on submit via _canSetQuantity.
    final TextEditingController controller =
        TextEditingController(text: '${item.quantity}');

    void trySubmit() {
      final qty = int.tryParse(controller.text);
      if (qty == null || qty <= 0) return;
      if (!_canSetQuantity(ref, item, qty)) {
        _showPermissionDenied(context, ref);
        return;
      }
      ref.read(orderProvider.notifier).updateItemQuantity(index, qty);
      Navigator.pop(context);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Quantity'),
        content: OnscreenKeyboardTextField(
          controller: controller,
          autofocus: true, // Auto-focus to show on-screen keyboard immediately
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(vertical: 20),
          ),
          onSubmitted: (_) => trySubmit(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: trySubmit,
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showNoteDialog(BuildContext context, WidgetRef ref, int index, OrderItem item) {
    if (!_canEditItem(ref, item, Permissions.ordersItemModify)) {
      _showPermissionDenied(context, ref);
      return;
    }
    final TextEditingController controller = TextEditingController(text: item.note ?? '');

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
        content: OnscreenKeyboardTextField(
          controller: controller,
          autofocus: true, // Auto-focus to show on-screen keyboard immediately
          keyboardType: TextInputType.text,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Add special instructions or notes...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: Colors.amber[50],
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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../providers/order_provider.dart';
import '../../domain/models/order_models.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/app_localizations.dart';
import '../../services/permission_service.dart';
import '../../providers/database_providers.dart';
import '../../providers/network_provider.dart';
import '../../data/database/app_database.dart';
import 'product_modification_dialog.dart';


class OrderPanel extends ConsumerWidget {
  const OrderPanel({Key? key}) : super(key: key);

  void _showItemOptions(BuildContext context, WidgetRef ref, int index, OrderItem item) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProductModificationDialog(
        product: item,
        isEditMode: true,
      ),
    );

    if (result != null) {
      // Update the item with new modifications
      final updatedItem = item.copyWith(
        components: result['components'] as List<OrderItemComponent>?,
        discount: result['discount'] as double?,
        manualDiscount: result['manualDiscount'] as double?,
        quantity: result['quantity'] as int?,
        note: result['note'] as String?,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('no_permission')),
            backgroundColor: Colors.red,
          ),
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
            '${item.productName}\n'
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
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: Colors.green,
                ),
              );
            }
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error deleting item: $e'),
                backgroundColor: Colors.red,
              ),
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
            padding: const EdgeInsets.all(16),
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
                const SizedBox(width: 8),
                Text(
                  currentOrder.orderCode?.toString() ?? l10n.translate('current_order'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (currentOrder.items.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      ref.read(orderProvider.notifier).clearOrder();
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
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
                    reverse: true,
                    itemBuilder: (context, index) {
                      final item = currentOrder.items[index];
                      final isPaid = item.ticketId != null;
                      final isHeld = item.state == 'ONHOLD';

                      return Dismissible(
                        dragStartBehavior: DragStartBehavior.down,
                        key: ValueKey("${item.hashCode}"),
                        // Disable dismiss for paid items
                        confirmDismiss: isPaid
                            ? (_) async => false
                            : (direction) async {
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
                          ref.read(orderProvider.notifier).removeItem(index);
                        },
                        child: GestureDetector(
                          onLongPress: isPaid
                              ? () => _showDeletePaidItemDialog(context, ref, item)
                              : null,
                          child: Opacity(
                            opacity: isPaid ? 0.6 : 1.0,
                            child: Card(
                              elevation: isPaid ? 1 : 2,
                              color: isPaid
                                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                                  : isHeld
                                      ? Colors.orange[50]
                                      : Theme.of(context).cardColor,
                              margin: EdgeInsets.only(
                                bottom: isPaid ? 4 : 8,
                                left: 4,
                                right: 4,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(isPaid ? 6 : 8),
                                side: BorderSide(
                                  color: isPaid
                                      ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
                                      : isHeld
                                          ? Colors.orange[300]!
                                          : Theme.of(context).dividerColor,
                                  width: isPaid ? 0.5 : (isHeld ? 2 : 1),
                                ),
                              ),
                              child: InkWell(
                                onTap: isPaid ? null : () => _showItemOptions(context, ref, index, item),
                                borderRadius: BorderRadius.circular(isPaid ? 6 : 8),
                                child: Padding(
                                  padding: EdgeInsets.all(isPaid ? 8 : 12),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                    // Header: Name and Note button
                                    Row(
                                      children: [
                                        if (isPaid) ...[
                                          Icon(
                                            Icons.lock,
                                            size: isPaid ? 12 : 14,
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Expanded(
                                          child: Text(
                                            item.productName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: isPaid ? 13 : 15,
                                              decoration: isPaid ? TextDecoration.lineThrough : null,
                                              decorationColor: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                            maxLines: isPaid ? 1 : 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Note icon button
                                        if (!isPaid) ...[
                                          IconButton(
                                            onPressed: () => _showNoteDialog(context, ref, index, item),
                                            icon: Icon(
                                              item.note != null && item.note!.isNotEmpty
                                                  ? Icons.sticky_note_2
                                                  : Icons.sticky_note_2_outlined,
                                              size: 30,
                                              color: item.note != null && item.note!.isNotEmpty
                                                  ? Colors.amber[700]
                                                  : Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                            tooltip: 'Add note',
                                            padding: const EdgeInsets.all(4),
                                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                          ),
                                        ],
                                      ],
                                    ),

                                    // Show note if exists
                                    if (item.note != null && item.note!.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.amber[50],
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.amber[200]!),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.note, size: 12, color: Colors.amber[900]),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                item.note!,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.amber[900],
                                                  fontStyle: FontStyle.italic,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    // Paid status badge
                                    if (isPaid) ...[
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.green[50],
                                          borderRadius: BorderRadius.circular(3),
                                          border: Border.all(color: Colors.green[200]!),
                                        ),
                                        child: Text(
                                          'Paid - Ticket #${item.ticketId}',
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: Colors.green[700],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],

                                    // Held status badge
                                    if (isHeld && !isPaid) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.orange[50],
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.orange[300]!),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.pause_circle, size: 12, color: Colors.orange[700]),
                                            const SizedBox(width: 4),
                                            Text(
                                              'On Hold',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.orange[700],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],

                                    // Components
                                    if (item.components.isNotEmpty) ...[
                                      SizedBox(height: 4),
                                      ...item.components.map((comp) => Padding(
                                        padding: const EdgeInsets.only(left: 4, top: 2),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.add,
                                              size: isPaid ? 8 : 10,
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                '${comp.name} x${comp.quantity}',
                                                style: TextStyle(
                                                  fontSize: isPaid ? 9 : 11,
                                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )),
                                    ],

                                    SizedBox(height: 4),
                                    const Divider(height: 1),
                                    SizedBox(height: 4),

                                    // Bottom: Quantity and Price
                                    Row(
                                      children: [
                                        // Quantity - tappable button that opens dialog with on-screen keyboard
                                        if (!isPaid)
                                          InkWell(
                                            onTap: () => _showQuantityDialog(context, ref, index, item),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                              constraints: const BoxConstraints(minWidth: 40),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context).colorScheme.onInverseSurface,
                                                borderRadius: BorderRadius.circular(10),


                                                border: Border.all(
                                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                '${item.quantity}',

                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 24,

                                                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          // Paid item - show quantity in smaller format
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: Theme.of(context).dividerColor),
                                            ),
                                            child: Text(
                                              'x${item.quantity}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),

                                        const Spacer(),

                                        // Price and discount
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              currencyFormatter.format(item.totalPrice),
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: isPaid ? 13 : 16,
                                              ),
                                            ),
                                            if (item.totalDiscount > 0) ...[
                                              SizedBox(height: isPaid ? 1 : 2),
                                              Text(
                                                'Discount: -${currencyFormatter.format(item.totalDiscount)}',
                                                style: TextStyle(
                                                  fontSize: isPaid ? 9 : 11,
                                                  color: Colors.orange[700],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],)

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
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
            ),
            child: Column(
              children: [
                // Show subtotal before discount if discount is applied
                if (currentOrder.discountPercentage > 0) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(l10n.translate('subtotal')),
                      Text(
                        currencyFormatter.format(currentOrder.subtotal),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.percent, size: 14, color: Colors.orange[700]),
                          const SizedBox(width: 4),
                          Text(
                            '${l10n.translate('discount')} (${currentOrder.discountPercentage.toStringAsFixed(0)}%):',
                            style: TextStyle(color: Colors.orange[700]),
                          ),
                        ],
                      ),
                      Text(
                        '-${currencyFormatter.format(currentOrder.discountAmount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${l10n.translate('subtotal')}:'),
                      Text(
                        currencyFormatter.format(currentOrder.subtotal),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${l10n.translate('tax')}:'),
                    Text(
                      currencyFormatter.format(currentOrder.tax),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${l10n.translate('total')}:',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      currencyFormatter.format(currentOrder.total),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
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
    final TextEditingController controller = TextEditingController(text: '${item.quantity}');

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
          onSubmitted: (value) {
            final qty = int.tryParse(value);
            if (qty != null && qty > 0) {
              ref.read(orderProvider.notifier).updateItemQuantity(index, qty);
              Navigator.pop(context);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(controller.text);
              if (qty != null && qty > 0) {
                ref.read(orderProvider.notifier).updateItemQuantity(index, qty);
                Navigator.pop(context);
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showNoteDialog(BuildContext context, WidgetRef ref, int index, OrderItem item) {
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

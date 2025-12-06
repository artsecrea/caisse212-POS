import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/order_provider.dart';
import '../../domain/models/order_models.dart';
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
      );
      ref.read(orderProvider.notifier).updateItem(index, updatedItem);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentOrder = ref.watch(orderProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.shopping_cart,
                  color: Theme.of(context).primaryColor,
                ),
                const SizedBox(width: 8),
                Text(
                  currentOrder.orderId?.toString() ?? 'Current Order*',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (currentOrder.items.isNotEmpty)
                  IconButton(
                    onPressed: () {
                      ref.read(orderProvider.notifier).clearOrder();
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'Clear Order',
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
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'click a product to start new order',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(2),
                    itemCount: currentOrder.items.length,
                    itemBuilder: (context, index) {
                      final item = currentOrder.items[index];
                      final isPaid = item.ticketId != null;
                      final isHeld = item.state == 'ONHOLD';

                      return Dismissible(
                        dragStartBehavior: DragStartBehavior.down,
                        key: ValueKey("${item.id}_$index"),
                        // Disable dismiss for paid items
                        confirmDismiss: isPaid
                            ? (_) async => false
                            : (direction) async {
                          // Return true to confirm dismissal
                          return true;
                        },
                        direction: isPaid ? DismissDirection.none : DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: Colors.red,
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        child: Opacity(
                          opacity: isPaid ? 0.5 : 1.0,
                          child: Card(
                            elevation: 2,
                            color: isPaid
                                ? Colors.grey[100]
                                : isHeld
                                    ? Colors.orange[50]
                                    : Colors.white,
                            margin: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isPaid
                                    ? Colors.grey[400]!
                                    : isHeld
                                        ? Colors.orange[300]!
                                        : Colors.grey[200]!,
                                width: isHeld ? 2 : 1,
                              ),
                            ),
                            child: InkWell(
                              onTap: isPaid ? null : () => _showItemOptions(context, ref, index, item),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Header: Name and Delete button
                                    Row(
                                      children: [
                                        if (isPaid) ...[
                                          Icon(Icons.lock, size: 14, color: Colors.grey[600]),
                                          const SizedBox(width: 6),
                                        ],
                                        Expanded(
                                          child: Text(
                                            item.productName,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15,
                                              decoration: isPaid ? TextDecoration.lineThrough : null,
                                              decorationColor: Colors.grey[600],
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (!isPaid)
                                          IconButton(
                                            onPressed: () {
                                              ref.read(orderProvider.notifier).removeItem(index);
                                            },
                                            icon: Icon(Icons.close, size: 18, color: Colors.grey[600]),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                      ],
                                    ),

                                    // Paid status badge
                                    if (isPaid) ...[
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green[50],
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: Colors.green[200]!),
                                        ),
                                        child: Text(
                                          'Paid - Ticket #${item.ticketId}',
                                          style: TextStyle(
                                            fontSize: 10,
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
                                      const SizedBox(height: 6),
                                      ...item.components.map((comp) => Padding(
                                        padding: const EdgeInsets.only(left: 4, top: 2),
                                        child: Row(
                                          children: [
                                            Icon(Icons.add, size: 10, color: Colors.grey[500]),
                                            const SizedBox(width: 4),
                                            Expanded(
                                              child: Text(
                                                '${comp.name} x${comp.quantity}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.grey[600],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      )),
                                    ],

                                    const SizedBox(height: 10),
                                    const Divider(height: 1),
                                    const SizedBox(height: 10),

                                    // Bottom: Quantity controls and Price
                                    Row(
                                      children: [
                                        // Quantity controls
                                        Container(
                                          decoration: BoxDecoration(
                                            color: isPaid ? Colors.grey[200] : Colors.grey[50],
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.grey[300]!),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                onPressed: isPaid ? null : () {
                                                  ref.read(orderProvider.notifier).updateItemQuantity(
                                                    index,
                                                    item.quantity - 1,
                                                  );
                                                },
                                                icon: const Icon(Icons.remove, size: 16),
                                                padding: const EdgeInsets.all(4),
                                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                              Container(
                                                constraints: const BoxConstraints(minWidth: 24),
                                                child: Text(
                                                  item.quantity.toString(),
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                              IconButton(
                                                onPressed: isPaid ? null : () {
                                                  ref.read(orderProvider.notifier).updateItemQuantity(
                                                    index,
                                                    item.quantity + 1,
                                                  );
                                                },
                                                icon: const Icon(Icons.add, size: 16),
                                                padding: const EdgeInsets.all(4),
                                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                            ],
                                          ),
                                        ),

                                        const Spacer(),

                                        // Price and discount
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '\$${item.totalPrice.toStringAsFixed(2)}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Theme.of(context).primaryColor,
                                                fontSize: 16,
                                              ),
                                            ),
                                            if (item.totalDiscount > 0) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                'Discount: -\$${item.totalDiscount.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.orange[700],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        onDismissed: (it) {
                          ref.read(orderProvider.notifier)
                              .removeItem(index);
                        },
                      );
                    },
                  ),
          ),
          // Order Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border(top: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal:'),
                    Text(
                      '\$${currentOrder.subtotal.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Tax:'),
                    Text(
                      '\$${currentOrder.tax.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total:',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '\$${currentOrder.total.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
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
}

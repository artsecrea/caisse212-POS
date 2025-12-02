import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/order_provider.dart';


class OrderPanel extends ConsumerWidget {
  const OrderPanel({Key? key}) : super(key: key);

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
                          child: Card.filled(
                            color: isPaid ? Colors.grey[200] : Colors.white,
                            shadowColor: Colors.black,
                            shape: BeveledRectangleBorder(
                              borderRadius: BorderRadius.zero,
                            ),
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: InkWell(
                                onTap: isPaid ? null : () {
                                  ref.read(orderProvider.notifier).updateItemQuantity(index, item.quantity+1);
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              if (isPaid) ...[
                                                Icon(Icons.lock, size: 16, color: Colors.grey[600]),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Paid (T${item.ticketId}) ',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey[600],
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                              Flexible(
                                                child: Text(
                                                  item.productName,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 14,
                                                    decoration: isPaid ? TextDecoration.lineThrough : null,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!isPaid)
                                          IconButton(
                                            onPressed: () {
                                              ref
                                                  .read(orderProvider.notifier)
                                                  .removeItem(index);
                                            },
                                            icon: const Icon(Icons.close, size: 18),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                      ],
                                    ),
                                  if (item.components.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    ...item.components.map(
                                          (comp) => Padding(
                                        padding: const EdgeInsets.only(
                                          left: 8,
                                          top: 2,
                                        ),
                                        child: Text(
                                          '+ ${comp.name} x${comp.quantity}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey[300]!,
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            IconButton(
                                              onPressed: isPaid ? null : () {
                                                ref
                                                    .read(orderProvider.notifier)
                                                    .updateItemQuantity(
                                                  index,
                                                  item.quantity - 1,
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.remove,
                                                size: 16,
                                              ),
                                              padding: const EdgeInsets.all(4),
                                              constraints: const BoxConstraints(),
                                            ),
                                            SizedBox(
                                              width: 30,
                                              child: Text(
                                                item.quantity.toString(),
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: isPaid ? null : () {
                                                ref
                                                    .read(orderProvider.notifier)
                                                    .updateItemQuantity(
                                                  index,
                                                  item.quantity + 1,
                                                );
                                              },
                                              icon: const Icon(
                                                Icons.add,
                                                size: 16,
                                              ),
                                              padding: const EdgeInsets.all(4),
                                              constraints: const BoxConstraints(),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        '\$${item.totalPrice.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).primaryColor,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Spacer(),
                                      Text("discount :\$${item.totalDiscount}")
                                    ],
                                  ),
                                ],
                              ),
                            )
                          ),
                        )),
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

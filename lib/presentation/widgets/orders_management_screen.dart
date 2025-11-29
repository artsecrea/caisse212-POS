// filepath: /home/arecrea/prj/posecrea/lib/presentation/widgets/orders_management_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/order_provider.dart';
import '../../data/database/app_database.dart';

class OrdersManagementScreen extends ConsumerStatefulWidget {
  const OrdersManagementScreen({super.key});

  @override
  ConsumerState<OrdersManagementScreen> createState() => _OrdersManagementScreenState();
}

class _OrdersManagementScreenState extends ConsumerState<OrdersManagementScreen> {
  String _statusFilter = 'ALL';

  @override
  Widget build(BuildContext context) {
    final orderRepo = ref.watch(orderRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orders Management'),
        actions: [
          PopupMenuButton<String>(
            initialValue: _statusFilter,
            onSelected: (value) {
              setState(() {
                _statusFilter = value;
              });
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'ALL', child: Text('All Orders')),
              const PopupMenuItem(value: 'ONHOLD', child: Text('On Hold')),
              const PopupMenuItem(value: 'PENDING', child: Text('Pending')),
              const PopupMenuItem(value: 'PREPARING', child: Text('Preparing')),
              const PopupMenuItem(value: 'READY', child: Text('Ready')),
              const PopupMenuItem(value: 'DELIVERED', child: Text('Delivered')),
            ],
          ),
        ],
      ),
      body: FutureBuilder(
        future: orderRepo.getAllOrdersWithDetails(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          var orders = snapshot.data ?? [];
          
          // Apply filter
          if (_statusFilter != 'ALL') {
            orders = orders.where((o) => o.order.status == _statusFilter).toList();
          }

          if (orders.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No orders found',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final orderWithDetails = orders[index];
              final order = orderWithDetails.order as Order;
              
              return _OrderCard(
                order: order,
                tableName: orderWithDetails.tableName,
                itemCount: orderWithDetails.itemCount,
                total: orderWithDetails.total,
                onTap: () => _showOrderDetails(context, order),
              );
            },
          );
        },
      ),
    );
  }

  void _showOrderDetails(BuildContext context, Order order) async {
    final orderRepo = ref.read(orderRepositoryProvider);
    final currentOrder = await orderRepo.loadOrderDetails(order);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => _OrderDetailsDialog(
        order: order,
        currentOrder: currentOrder,
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final String? tableName;
  final int itemCount;
  final double total;
  final VoidCallback onTap;

  const _OrderCard({
    required this.order,
    required this.tableName,
    required this.itemCount,
    required this.total,
    required this.onTap,
  });

  Color _getStatusColor(String status) {
    switch (status) {
      case 'ONHOLD':
        return Colors.orange;
      case 'PENDING':
        return Colors.blue;
      case 'PREPARING':
        return Colors.purple;
      case 'READY':
        return Colors.green;
      case 'DELIVERED':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor(order.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Order Code
                  Expanded(
                    child: Text(
                      order.code,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      order.status,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  // Table info
                  if (tableName != null) ...[
                    Icon(Icons.table_restaurant, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      tableName!,
                      style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 16),
                  ],
                  // Order type
                  Icon(
                    order.type == 'DINE_IN' ? Icons.restaurant : 
                    order.type == 'TAKE_AWAY' ? Icons.shopping_bag : Icons.delivery_dining,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    order.type.replaceAll('_', ' '),
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  const Spacer(),
                  // Item count
                  Text(
                    '$itemCount items',
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Date/Time
                  Text(
                    _formatDateTime(order.date),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                  // Total
                  Text(
                    '\$${total.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      return 'Today ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else if (difference.inDays == 1) {
      return 'Yesterday ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
}

class _OrderDetailsDialog extends StatelessWidget {
  final Order order;
  final dynamic currentOrder;

  const _OrderDetailsDialog({
    required this.order,
    required this.currentOrder,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).primaryColor,
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.code,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Order Details',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Body
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Order info
                    _InfoRow(label: 'Status', value: order.status),
                    _InfoRow(label: 'Type', value: order.type.replaceAll('_', ' ')),
                    if (currentOrder.tableName != null)
                      _InfoRow(label: 'Table', value: currentOrder.tableName!),
                    _InfoRow(label: 'Date', value: _formatFullDateTime(order.date)),
                    
                    const SizedBox(height: 24),
                    const Text(
                      'Order Items',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Divider(),
                    // Order items
                    ...currentOrder.items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (item.ticketNum != null) ...[
                                      Icon(Icons.check_circle, size: 16, color: Colors.green[700]),
                                      const SizedBox(width: 4),
                                      Text(
                                        '(Paid) ',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green[700],
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    Flexible(
                                      child: Text(
                                        item.productName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (item.components.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  ...item.components.map((comp) => Padding(
                                    padding: const EdgeInsets.only(left: 16, top: 2),
                                    child: Text(
                                      '+ ${comp.name} x${comp.quantity}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  )),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            'x${item.quantity}',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '\$${item.totalPrice.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    )),
                    const Divider(),
                    // Totals
                    _TotalRow(label: 'Subtotal', amount: currentOrder.subtotal),
                    if (currentOrder.tax > 0)
                      _TotalRow(label: 'Tax', amount: currentOrder.tax),
                    const Divider(thickness: 2),
                    _TotalRow(
                      label: 'Total',
                      amount: currentOrder.total,
                      isBold: true,
                      fontSize: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatFullDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final double amount;
  final bool isBold;
  final double fontSize;

  const _TotalRow({
    required this.label,
    required this.amount,
    this.isBold = false,
    this.fontSize = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '$label:',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '\$${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}


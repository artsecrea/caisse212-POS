import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:posecrea/data/database/app_database.dart';
import 'package:posecrea/providers/database_providers.dart';
import 'package:posecrea/providers/order_provider.dart';
import 'package:posecrea/presentation/paymen_screen/payment_screen.dart';
import 'package:posecrea/utils/app_localizations.dart';
import 'package:posecrea/utils/currency_formatter.dart';

class OrderConfirmationScreen extends ConsumerStatefulWidget {
  const OrderConfirmationScreen({super.key});

  @override
  ConsumerState<OrderConfirmationScreen> createState() => _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState extends ConsumerState<OrderConfirmationScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Order? _selectedOrder;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<Order>> _getOnHoldOrders() async {
    final database = ref.read(databaseProvider);
    final query = database.select(database.orders)
      ..where((tbl) => tbl.status.equals('ONHOLD'))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]);

    final orders = await query.get();

    if (_searchQuery.isEmpty) {
      return orders;
    }

    return orders.where((order) {
      return order.code.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }

  Future<void> _confirmOrder(Order order) async {
    try {
      final orderRepo = ref.read(orderRepositoryProvider);

      // Update order status to PENDING
      await orderRepo.updateOrderStatus(order.id, 'PENDING');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order ${order.code} confirmed and sent to KDS'),
            backgroundColor: Colors.green[700],
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming order: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmAndPay(Order order) async {
    try {
      final orderRepo = ref.read(orderRepositoryProvider);

      // Update order status to PENDING first
      await orderRepo.updateOrderStatus(order.id, 'PENDING');

      // Load the order for payment
      final fullOrder = await orderRepo.getOrderById(order.id);
      if (fullOrder == null) {
        throw Exception('Order not found');
      }

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PaymentScreen(order: fullOrder),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<int> _getOrderItemCount(int orderId) async {
    final database = ref.read(databaseProvider);
    final items = await (database.select(database.orderProducts)
          ..where((tbl) => tbl.orderId.equals(orderId)))
        .get();
    return items.length;
  }

  Future<double> _getOrderTotal(int orderId) async {
    final database = ref.read(databaseProvider);
    final items = await (database.select(database.orderProducts)
          ..where((tbl) => tbl.orderId.equals(orderId)))
        .get();

    double total = 0.0;
    for (final item in items) {
      // Get components for this order product
      final orderComponents = await (database.select(database.orderProductComponents)
            ..where((tbl) => tbl.orderProductId.equals(item.id)))
          .get();

      double componentTotal = 0.0;
      for (final orderComp in orderComponents) {
        // Use stored price instead of looking up component
        componentTotal += orderComp.price * orderComp.quantity;
      }

      // Calculate based on pricing rules
      final subtotal = item.unitaryPrice * item.quantity;
      final discountAmount = (item.unitaryDiscount + item.manualDiscount) * item.quantity;
      final taxableAmount = subtotal - discountAmount;
      final taxAmount = item.unitaryTva * item.quantity;
      total += (taxableAmount + taxAmount + componentTotal);
    }

    return total;
  }

  Future<List<Map<String, dynamic>>> _getOrderItemsWithDetails(int orderId) async {
    final database = ref.read(databaseProvider);
    final orderProducts = await (database.select(database.orderProducts)
          ..where((tbl) => tbl.orderId.equals(orderId)))
        .get();

    final items = <Map<String, dynamic>>[];
    for (final orderProduct in orderProducts) {
      final product = await (database.select(database.products)
            ..where((tbl) => tbl.id.equals(orderProduct.productId)))
          .getSingleOrNull();

      // Get components for this order product
      final orderComponents = await (database.select(database.orderProductComponents)
            ..where((tbl) => tbl.orderProductId.equals(orderProduct.id)))
          .get();

      final components = <Map<String, dynamic>>[];
      for (final orderComp in orderComponents) {
        // Still need component name for display, but use stored price
        final component = await (database.select(database.components)
              ..where((tbl) => tbl.id.equals(orderComp.componentId)))
            .getSingleOrNull();

        if (component != null) {
          components.add({
            'name': component.name,
            'quantity': orderComp.quantity,
            'price': orderComp.price, // Use stored price from order time
            'isSpecial': orderComp.isSpecial,
          });
        }
      }

      items.add({
        'orderProduct': orderProduct,
        'productName': product?.name ?? 'Unknown Product',
        'components': components,
      });
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('confirm_order')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.translate('search_by_code'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.white,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        ),
      ),
      body: Row(
        children: [
          // Left panel - Order list
          Expanded(
            flex: 2,
            child: FutureBuilder<List<Order>>(
              future: _getOnHoldOrders(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error: ${snapshot.error}'),
                  );
                }

                final orders = snapshot.data ?? [];

                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.translate('no_onhold_orders'),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final order = orders[index];
                    final isSelected = _selectedOrder?.id == order.id;

                    return FutureBuilder<Map<String, dynamic>>(
                      future: Future.wait([
                        _getOrderItemCount(order.id),
                        _getOrderTotal(order.id),
                      ]).then((results) => {
                            'itemCount': results[0],
                            'total': results[1],
                          }),
                      builder: (context, detailsSnapshot) {
                        final itemCount = detailsSnapshot.data?['itemCount'] as int? ?? 0;
                        final total = detailsSnapshot.data?['total'] as double? ?? 0.0;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          color: isSelected
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: ListTile(
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.pending_actions,
                                color: Colors.orange[700],
                              ),
                            ),
                            title: Text(
                              order.code,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  '${l10n.translate('items')}: $itemCount',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                Text(
                                  '${l10n.translate('type')}: ${order.type}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                if (order.persons > 1)
                                  Text(
                                    '${l10n.translate('persons')}: ${order.persons}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                              ],
                            ),
                            trailing: Text(
                              currencyFormatter.format(total),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            selected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedOrder = order;
                              });
                            },
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          // Right panel - Order details and actions
          Expanded(
            flex: 1,
            child: _selectedOrder == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.touch_app,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.translate('select_order_to_confirm'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  )
                : _buildOrderDetails(),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetails() {
    final order = _selectedOrder!;
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.watch(currencyFormatterProvider);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange[50],
              border: Border(
                bottom: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.pending_actions, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.translate('order_on_hold'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[700],
                          fontSize: 18,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  order.code,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Order items
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _getOrderItemsWithDetails(order.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = snapshot.data ?? [];

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final orderProduct = item['orderProduct'] as OrderProduct;
                    final productName = item['productName'] as String;
                    final components = item['components'] as List<Map<String, dynamic>>;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${orderProduct.quantity}x',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    productName,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                Text(
                                  currencyFormatter.format(orderProduct.unitaryPrice * orderProduct.quantity),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            if (components.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.only(left: 52),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.translate('components'),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    ...components.map((comp) {
                                      final quantity = comp['quantity'] as int;
                                      final name = comp['name'] as String;
                                      final price = comp['price'] as double;
                                      final isSpecial = comp['isSpecial'] as bool;

                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 2),
                                        child: Row(
                                          children: [
                                            if (isSpecial)
                                              Icon(
                                                Icons.star,
                                                size: 12,
                                                color: Colors.orange[700],
                                              ),
                                            if (isSpecial) const SizedBox(width: 4),
                                            Text(
                                              '${quantity}x $name',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                                              ),
                                            ),
                                            if (price > 0) ...[
                                              const SizedBox(width: 4),
                                              Text(
                                                '(+${currencyFormatter.format(price * quantity)})',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Action buttons
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: () => _confirmOrder(order),
                  icon: const Icon(Icons.check_circle),
                  label: Text(l10n.translate('confirm_order')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => _confirmAndPay(order),
                  icon: const Icon(Icons.payment),
                  label: Text(l10n.translate('confirm_and_pay')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedOrder = null;
                    });
                  },
                  icon: const Icon(Icons.cancel),
                  label: Text(l10n.translate('cancel')),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

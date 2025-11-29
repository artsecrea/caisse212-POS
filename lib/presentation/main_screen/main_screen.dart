import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../paymen_screen/payment_screen.dart';
import '../widgets/category_selector.dart';
import '../widgets/commercial_selection_dialog.dart';
import '../widgets/customer_selection_dialog.dart';
import '../widgets/product_grid.dart';
import '../widgets/order_panel.dart';
import '../widgets/table_selection_dialog.dart';
import '../widgets/top_bar.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  @override
  Widget build(BuildContext context) {
    final currentOrder = ref.watch(orderProvider);
    return Scaffold(
      body: Column(
        children: [
          // Top Bar with status, network state, and update button
          const TopBar(),
          Expanded(
            child: Row(
              children: [
                // Main content area
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      // Category selector (horizontal scroll)
                      const CategorySelector(),
                      // Products grid
                      const Expanded(
                        child: ProductGrid(),
                      ),
                    ],
                  ),
                ),
                // Order panel (right side)
                const SizedBox(
                  width: 400,
                  child: OrderPanel(),
                ),
              ],
            ),
          ),
          Container(
            height: 150,
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: 8,
              children: [




                _buildActionButton(icon: Icons.table_bar_sharp, label: "Table", onPressed: () async {
                  final currentOrder = ref.read(orderProvider);
                  final hasUnpaidItems = currentOrder.unpaidItems.isNotEmpty;

                  final result = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (context) => const TableSelectionDialog(),
                  );

                  if (result != null && context.mounted) {
                    final action = result['action'];
                    final existingOrder = result['existingOrder'];
                    final tableId = result['id'];
                    final tableName = result['name'];

                    // Handle different actions
                    if (action == 'pay' && result['order'] != null) {
                      // Open payment screen
                      // TODO: Navigate to payment screen with order
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payment screen - coming soon')),
                      );
                      return;
                    }

                    if (action == 'clear') {
                      // Clear table
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Table $tableName cleared')),
                      );
                      return;
                    }
                    if (existingOrder != null) {
                      // No current items, just load existing order
                      ref.read(orderProvider.notifier).loadOrder(existingOrder);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Loaded order for $tableName'),
                            backgroundColor: Colors.blue,
                          ),
                        );
                      }
                    } else {
                      // No existing order, just set the table
                      ref.read(orderProvider.notifier).setTable(tableId, tableName);
                    }
                  }
                },),
                _buildActionButton(icon: Icons.person, label: "Customer", onPressed: () async {
                  final result =
                  await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (context) =>
                    const CustomerSelectionDialog(),
                  );
                  if (result != null) {
                    ref
                        .read(orderProvider.notifier)
                        .setCustomer(result['id'], result['name']);
                  }
                },),
                _buildActionButton(icon: Icons.badge, label: "Commercial", onPressed:() async {
                  final result =
                  await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (context) =>
                    const CommercialSelectionDialog(),
                  );
                  if (result != null) {
                    ref
                        .read(orderProvider.notifier)
                        .setCommercial(result['id'], result['name']);
                  }
                },),
                _buildActionButton(icon: Icons.discount, label: "Coupon", onPressed: (){}),
                _buildActionButton(icon: Icons.discount, label: "Manual Discount", onPressed: (){}),
                _buildActionButton(
                  icon: Icons.print,
                  label: 'Print',
                  onPressed: currentOrder.items.isEmpty
                      ? null
                      : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Printing...')),
                    );
                  },
                ),
                _buildActionButton(
                  icon: Icons.pause_circle_outline,
                  label: 'Hold',
                  onPressed: currentOrder.items.isEmpty
                      ? null
                      : () async {
                    final orderRepo = ref.read(orderRepositoryProvider);
                    final currentUser = ref.read(currentUserProvider);

                    if (currentUser == null) return;

                    try {
                      await orderRepo.holdOrder(currentOrder, currentUser.id);
                      ref.read(orderProvider.notifier).clearOrder();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Order held successfully'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error holding order: $e')),
                        );
                      }
                    }
                  },
                ),
                _buildActionButton(
                  icon: Icons.payment,
                  label: 'Pay',
                  color: Colors.green[700],
                  onPressed: currentOrder.items.isEmpty
                      ? null
                      : () async {
                    final result = await showDialog<bool>(
                      context: context,
                      builder: (context) => PaymentScreen(order: currentOrder),
                    );

                    if (result == true && context.mounted) {
                      ref.read(orderProvider.notifier).clearOrder();
                    }
                  },
                ),
                _buildActionButton(
                  icon: Icons.check_circle,
                  label: 'Proceed',
                  isPrimary: true,
                  onPressed: currentOrder.items.isEmpty
                      ? null
                      : () async {
                    final orderRepo = ref.read(orderRepositoryProvider);
                    final currentUser = ref.read(currentUserProvider);

                    if (currentUser == null) return;

                    try {
                      print(currentOrder.orderId);

                      if (currentOrder.isSaved()) {
                        print("order updated");
                        await orderRepo.updateOrder(currentOrder);
                      } else {
                        print("new order created");
                        final orderId = await orderRepo.saveOrder(
                          currentOrder,
                          currentUser.id,
                        );

                        if (currentOrder.tableId != null) {
                          await orderRepo.setTableOrderId(currentOrder.tableId!, orderId);
                        }
                      }

                      ref.read(orderProvider.notifier).clearOrder();

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Order placed successfully'),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                ),

              ],
            ),
          )

        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
    bool isPrimary = false,
  }) {
    return SizedBox(
      width: 130,
      height: 130,
      child: isPrimary
          ? ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 8),
            Text(label,
            textAlign: TextAlign.justify,),
          ],
        ),
      )
          : OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color ?? Colors.grey),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 8),
            Text(label, textAlign: TextAlign.justify,),
          ],
        ),
      ),
    );
  }

}


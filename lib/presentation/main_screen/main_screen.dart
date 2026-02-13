import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../providers/settings_provider.dart';
import '../../domain/models/app_settings.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
import '../order_confirmation/order_confirmation_screen.dart';
import '../paymen_screen/payment_screen.dart';
import '../widgets/category_selector.dart';
import '../widgets/category_grid.dart';
import '../widgets/commercial_selection_dialog.dart';
import '../widgets/customer_selection_dialog.dart';
import '../widgets/manual_discount_dialog.dart';
import '../widgets/print_options_dialog.dart';
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
  final _logger = Logger.instance;
  final _focusNode = FocusNode();
  
  @override
  void initState() {
    super.initState();
    _initializeBarcodeScanner();
  }

  void _initializeBarcodeScanner() {
    final barcodeService = ref.read(barcodeScannerServiceProvider);
    barcodeService.initialize(_focusNode);
    
    // Listen to barcode scans
    barcodeService.barcodeStream.listen((barcode) {
      _handleBarcodeScanned(barcode);
    });
    
    // Request focus for barcode scanner
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _handleBarcodeScanned(String barcode) async {
    _logger.info('Barcode scanned: $barcode');
    
    final orderRepo = ref.read(orderRepositoryProvider);
    
    try {
      // Search for order by code
      final order = await orderRepo.getOrderByCode(barcode);
      
      if (order != null) {
        // Load the order
        ref.read(orderProvider.notifier).loadOrder(order);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order $barcode loaded'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Order $barcode not found'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      _logger.error('Error loading order from barcode: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentOrder = ref.watch(orderProvider);
    final settings = ref.watch(settingsProvider);
    final displayMode = ref.watch(categoryDisplayModeProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final l10n = AppLocalizations.of(context)!;

    // In fullPage mode, show CategoryGrid when no category selected, otherwise ProductGrid
    final showCategoryGrid = displayMode == CategoryDisplayMode.fullPage &&
                             selectedCategory == null;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        final barcodeService = ref.read(barcodeScannerServiceProvider);
        return barcodeService.handleKeyEvent(event);
      },
      child: Scaffold(
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
                      // Products grid or Category grid based on display mode
                      Expanded(
                        child: showCategoryGrid
                            ? const CategoryGrid()
                            : const ProductGrid(),
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
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Number of persons button
                  if (settings.showPersonsButton)
                    _buildActionButton(
                      icon: Icons.people,
                      label: "${currentOrder.numberOfPersons} ${currentOrder.numberOfPersons == 1 ? l10n.translate('person') : l10n.translate('persons')}",
                      color: currentOrder.numberOfPersons > 1 ? Colors.blue : null,
                      onPressed: () async {
                        final result = await showDialog<int>(
                          context: context,
                          builder: (context) => _NumberOfPersonsDialog(
                            currentNumber: currentOrder.numberOfPersons,
                          ),
                        );
                        if (result != null) {
                          ref.read(orderProvider.notifier).setNumberOfPersons(result);
                        }
                      },
                    ),
                  if (settings.showPersonsButton)
                    const SizedBox(width: 8),
                  // Order type toggle button
                  if (settings.showOrderTypeButton)
                    _buildActionButton(
                      icon: currentOrder.type == 'DINE_IN' ? Icons.restaurant : Icons.takeout_dining,
                      label: currentOrder.type == 'DINE_IN' ? l10n.translate('dine_in') : l10n.translate('take_away'),
                      color: currentOrder.type == 'TAKE_AWAY' ? Colors.orange : Colors.green,
                      onPressed: () {
                        final newType = currentOrder.type == 'DINE_IN' ? 'TAKE_AWAY' : 'DINE_IN';
                        ref.read(orderProvider.notifier).setOrderType(newType);
                      },
                    ),
                  if (settings.showOrderTypeButton)
                    const SizedBox(width: 8),
                  // Confirm Order button
                  if (settings.showConfirmOrderButton)
                    _buildActionButton(
                      icon: Icons.task_alt,
                      label: l10n.translate('confirm_order'),
                      color: Colors.purple,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const OrderConfirmationScreen(),
                          ),
                        );
                      },
                    ),
                  if (settings.showConfirmOrderButton)
                    const SizedBox(width: 8),
                  // Table button - conditionally shown
                  if (settings.showTableButton)
                    _buildActionButton(
                      icon: Icons.table_bar_sharp,
                      label: currentOrder.tableName ?? l10n.translate('table'),
                      color: currentOrder.tableId != null ? Colors.blue : null,
                      onPressed: () async {

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
                      // Open payment screen with the order
                      final order = result['order'];
                      final paymentResult = await showDialog<bool>(
                        context: context,
                        builder: (context) => PaymentScreen(order: order),
                      );

                      if (paymentResult == true && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.translate('payment_successful')),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                      return;
                    }

                    if (action == 'cleared') {
                      // Table was cleared
                      final clearedTableName = result['tableName'];
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$clearedTableName ${l10n.translate('table_cleared')}'),
                          backgroundColor: Colors.green,
                        ),
                      );
                      return;
                    }

                    if (action == 'addItems') {
                      // Add items to existing order
                      if (existingOrder != null) {
                        ref.read(orderProvider.notifier).loadOrder(existingOrder);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Adding items to $tableName order'),
                              backgroundColor: Colors.blue,
                            ),
                          );
                        }
                      }
                      return;
                    }

                    if (existingOrder != null) {
                      // No current items, just load existing order
                      ref.read(orderProvider.notifier).loadOrder(existingOrder);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('${l10n.translate('order')} ${l10n.translate('for')} $tableName'),
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
                  const SizedBox(width: 8),
                  // Customer - Protected by permission and settings
                  if (settings.showCustomerButton && ref.read(permissionServiceProvider).hasPermission(Permissions.customerSet))
                    _buildActionButton(
                      icon: Icons.person,
                      label: currentOrder.customerName ?? "Customer",
                      color: currentOrder.customerId != null ? Colors.green : null,
                      onPressed: () async {
                      final result =
                      await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (context) =>
                        const CustomerSelectionDialog(),
                      );
                      if (result != null) {
                        if (result['id'] == null) {
                          // Unselect customer
                          ref.read(orderProvider.notifier).clearCustomer();
                        } else {
                          ref
                              .read(orderProvider.notifier)
                              .setCustomer(result['id'], result['name']);
                        }
                      }
                    },),
                  if (settings.showCustomerButton && ref.read(permissionServiceProvider).hasPermission(Permissions.customerSet))
                    const SizedBox(width: 8),
                  // Commercial - Protected by permission and settings
                  if (settings.showCommercialButton && ref.read(permissionServiceProvider).hasPermission(Permissions.commercialSet))
                    _buildActionButton(
                      icon: Icons.badge,
                      label: currentOrder.commercialName ?? "Commercial",
                      color: currentOrder.commercialId != null ? Colors.purple : null,
                      onPressed:() async {
                      final result =
                      await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (context) =>
                        const CommercialSelectionDialog(),
                    );
                    if (result != null) {
                      if (result['id'] == null) {
                        // Unselect commercial
                        ref.read(orderProvider.notifier).clearCommercial();
                      } else {
                        ref
                            .read(orderProvider.notifier)
                            .setCommercial(result['id'], result['name']);
                      }
                    }
                  },),
                  if (settings.showCommercialButton && ref.read(permissionServiceProvider).hasPermission(Permissions.commercialSet))
                    const SizedBox(width: 8),
                  // Coupon button - conditionally shown
                  if (settings.showCouponButton)
                    _buildActionButton(icon: Icons.discount, label: "Coupon", onPressed: (){}),
                  if (settings.showCouponButton)
                    const SizedBox(width: 8),
                  // Manual Discount - Protected by permission and settings
                  if (settings.showDiscountButton && ref.read(permissionServiceProvider).hasPermission(Permissions.manualDiscount))
                    _buildActionButton(
                      icon: Icons.percent,
                      label: currentOrder.discountPercentage > 0
                        ? "Discount ${currentOrder.discountPercentage.toStringAsFixed(0)}%"
                        : "Manual Discount",
                      color: currentOrder.discountPercentage > 0 ? Colors.orange : null,
                      onPressed: currentOrder.hasPaidItems
                        ? null  // Disable if any item is paid
                        : () async {
                        final result = await showDialog<double>(
                          context: context,
                          builder: (context) => ManualDiscountDialog(
                            currentPercentage: currentOrder.discountPercentage,
                          ),
                        );
                        if (result != null) {
                          ref.read(orderProvider.notifier).setDiscountPercentage(result);
                        }
                      },
                    ),
                  if (settings.showDiscountButton && ref.read(permissionServiceProvider).hasPermission(Permissions.manualDiscount))
                    const SizedBox(width: 8),
                  // Print - Protected by permission and settings
                  if (settings.showPrintButton && ref.read(permissionServiceProvider).hasPermission(Permissions.printing))
                    _buildActionButton(
                      icon: Icons.print,
                      label: l10n.translate('print'),
                      onPressed: currentOrder.items.isEmpty
                          ? null
                          : () async {
                      final currentUser = ref.read(currentUserProvider);
                    final orderRepo = ref.read(orderRepositoryProvider);
                    final settings = ref.read(settingsProvider);

                    // Save order first if not saved
                    int? orderId = currentOrder.orderId;
                    if (!currentOrder.isSaved() && currentUser != null) {
                      try {
                        orderId = await orderRepo.saveOrder(
                          currentOrder,
                          currentUser.id,
                          status: settings.defaultOrderStatus,
                        );

                        if (currentOrder.tableId != null) {
                          await orderRepo.setTableOrderId(currentOrder.tableId!, orderId);
                        }

                        // Reload the order
                        final reloadedOrder = await orderRepo.getOrderById(orderId);
                        if (reloadedOrder != null) {
                          ref.read(orderProvider.notifier).loadOrder(reloadedOrder);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error saving order: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                        return;
                      }
                    }

                    // Show print options dialog
                    if (context.mounted) {
                      final orderToPrint = currentOrder.isSaved()
                          ? currentOrder
                          : (orderId != null ? await orderRepo.getOrderById(orderId) : null);

                      if (orderToPrint != null) {
                        await showPrintOptionsDialog(
                          context,
                          order: orderToPrint,
                          cashierName: currentUser?.firstName,
                          storeName: "", // TODO: Get from settings
                        );
                      }
                    }
                  },
                ),
                // _buildActionButton(
                //   icon: Icons.pause_circle_outline,
                //   label: 'Hold',
                //   onPressed: currentOrder.items.isEmpty
                //       ? null
                //       : () async {
                //     final orderRepo = ref.read(orderRepositoryProvider);
                //     final currentUser = ref.read(currentUserProvider);
                //
                //     if (currentUser == null) return;
                //
                //     try {
                //       await orderRepo.holdOrder(currentOrder, currentUser.id);
                //       ref.read(orderProvider.notifier).clearOrder();
                //
                //       if (context.mounted) {
                //         ScaffoldMessenger.of(context).showSnackBar(
                //           const SnackBar(
                //             content: Text('Order held successfully'),
                //             backgroundColor: Colors.orange,
                //           ),
                //         );
                //       }
                //     } catch (e) {
                //       if (context.mounted) {
                //         ScaffoldMessenger.of(context).showSnackBar(
                //           SnackBar(
                //             content: Text('$e'),
                //             backgroundColor: Colors.red,
                //           ),
                //         );
                //       }
                //     }
                //   },
                // ),
                // Pay button
                if (settings.showPayButton)
                  _buildActionButton(
                    icon: Icons.payment,
                    label: l10n.translate('pay'),
                    color: Colors.green[700],
                    onPressed: currentOrder.items.isEmpty
                        ? null
                        : () async {
                      final orderRepo = ref.read(orderRepositoryProvider);
                      final currentUser = ref.read(currentUserProvider);
                      final settings = ref.read(settingsProvider);

                      if (currentUser == null) return;

                      try {
                        int orderId;
                        // Save or update order first
                        if (currentOrder.isSaved()) {
                          _logger.error("order updated before payment");
                          await orderRepo.updateOrder(currentOrder);
                          orderId = currentOrder.orderId!;
                        } else {
                          _logger.error("new order created before payment");
                          orderId = await orderRepo.saveOrder(
                            currentOrder,
                            currentUser.id,
                            status: settings.defaultOrderStatus, // Use default status from settings
                          );

                          if (currentOrder.tableId != null) {
                            await orderRepo.setTableOrderId(currentOrder.tableId!, orderId);
                          }
                        }

                        // Reload the order from database to get updated IDs and states
                        final reloadedOrder = await orderRepo.getOrderById(orderId);
                        if (reloadedOrder == null) {
                          throw Exception('Failed to reload order');
                        }

                        if (context.mounted) {
                          // Open payment screen with reloaded order
                          final result = await showDialog<bool>(
                            context: context,
                            builder: (context) => PaymentScreen(order: reloadedOrder),
                          );

                          if (result == true && context.mounted) {
                            // Payment completed, clear order
                            ref.read(orderProvider.notifier).clearOrder();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Payment completed successfully'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else if (context.mounted) {
                            // Payment screen closed without completion, reload order to show updated state
                            final updatedOrder = await orderRepo.getOrderById(orderId);
                            if (updatedOrder != null) {
                              ref.read(orderProvider.notifier).loadOrder(updatedOrder);
                            }
                          }
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                  ),
                _buildActionButton(
                  icon: Icons.check_circle,
                  label: l10n.translate('proceed'),
                  isPrimary: true,
                  onPressed: currentOrder.items.isEmpty
                      ? null
                      : () async {
                    final orderRepo = ref.read(orderRepositoryProvider);
                    final currentUser = ref.read(currentUserProvider);
                    final settings = ref.read(settingsProvider);
                    final printingService = ref.read(printingServiceProvider);

                    if (currentUser == null) return;

                    try {
                      int orderId;
                      if (currentOrder.isSaved()) {
                        _logger.error("order updated");
                        await orderRepo.updateOrder(currentOrder);
                        orderId = currentOrder.orderId!;
                      } else {
                        _logger.error("new order created");
                        orderId = await orderRepo.saveOrder(
                          currentOrder,
                          currentUser.id,
                          status: settings.defaultOrderStatus, // Use default status from settings
                        );

                        if (currentOrder.tableId != null) {
                          await orderRepo.setTableOrderId(currentOrder.tableId!, orderId);
                        }
                      }

                      // Reload the order from database to show it with updated IDs and states
                      final reloadedOrder = await orderRepo.getOrderById(orderId);

                      // Print order receipt and KDS ticket
                      if (reloadedOrder != null) {
                        try {
                          // Print receipt
                          await printingService.printOrderReceipt(
                            order: reloadedOrder,
                            cashierName: currentUser.firstName,
                            storeName: '#',
                          );

                          // Print KDS ticket if enabled
                          if (printingService.config.kdsEnabled) {
                            await printingService.printKdsTicket(
                              order: reloadedOrder,
                              cashierName: currentUser.firstName,
                            );
                          }
                        } catch (printError) {
                          _logger.error('Print error on proceed: $printError');
                          // Don't fail if printing fails
                        }

                        ref.read(orderProvider.notifier).clearOrder();
                      }

                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Order saved successfully'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
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

// Dialog for selecting number of persons
class _NumberOfPersonsDialog extends StatefulWidget {
  final int currentNumber;

  const _NumberOfPersonsDialog({required this.currentNumber});

  @override
  State<_NumberOfPersonsDialog> createState() => _NumberOfPersonsDialogState();
}

class _NumberOfPersonsDialogState extends State<_NumberOfPersonsDialog> {
  late int _selectedNumber;

  @override
  void initState() {
    super.initState();
    _selectedNumber = widget.currentNumber;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Number of Persons'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _selectedNumber > 1
                      ? () {
                          setState(() {
                            _selectedNumber--;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  iconSize: 40,
                ),
                Container(
                  width: 80,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '$_selectedNumber',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _selectedNumber < 99
                      ? () {
                          setState(() {
                            _selectedNumber++;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                  iconSize: 40,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (int i in [1, 2, 3, 4, 5, 6, 8, 10])
                  ChoiceChip(
                    label: Text('$i'),
                    selected: _selectedNumber == i,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedNumber = i;
                        });
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selectedNumber),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

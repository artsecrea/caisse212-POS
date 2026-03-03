import 'dart:async';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:drift/drift.dart' hide Column;
import '../../core/enums.dart';
import '../../data/database/app_database.dart';
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
import '../widgets/daily_summary_dialog.dart';
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
  StreamSubscription<String>? _barcodeSubscription;

  @override
  void initState() {
    super.initState();
    _initializeBarcodeScanner();
    _requestSearchFocus();
  }

  void _requestSearchFocus() {
    // Request focus on search bar after a short delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Clear any search query when returning to main screen
        // This ensures fresh start for search
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            // Request focus will be handled by TopBar
          }
        });
      }
    });
  }

  void _initializeBarcodeScanner() {
    final barcodeService = ref.read(barcodeScannerServiceProvider);
    barcodeService.initialize(_focusNode);

    // Listen to barcode scans
    _barcodeSubscription = barcodeService.barcodeStream.listen((barcode) {
      // Check if widget is still mounted before processing
      if (mounted) {
        _handleBarcodeScanned(barcode);
      }
    });

    // Request focus for barcode scanner
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _handleBarcodeScanned(String barcode) async {
    // Double check mounted state before accessing ref
    if (!mounted) return;

    // Check scan mode
    final scanMode = ref.read(barcodeScanModeProvider);

    if (scanMode == BarcodeScanMode.disabled) {
      _logger.info('Barcode scanning is disabled');
      return;
    }

    _logger.info('Barcode scanned: $barcode (mode: ${scanMode.name})');

    if (scanMode == BarcodeScanMode.orders) {
      await _handleOrderBarcode(barcode);
    } else if (scanMode == BarcodeScanMode.products) {
      await _handleProductBarcode(barcode);
    }
  }

  Future<void> _handleOrderBarcode(String barcode) async {
    final orderRepo = ref.read(orderRepositoryProvider);
    final currentOrder = ref.read(orderProvider);

    try {
      // Search for order by code
      final order = await orderRepo.getOrderByCode(barcode);

      if (order != null) {
        // Check if there's a current order with items
        if (currentOrder.items.isNotEmpty && mounted) {
          final l10n = AppLocalizations.of(context);
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(l10n?.translate('clear_current_order') ?? 'Clear Current Order?'),
              content: Text(
                l10n?.translate('clear_order_warning') ??
                'This will clear the current order. Are you sure you want to load order $barcode?'
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n?.translate('cancel') ?? 'Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                  child: Text(l10n?.translate('clear_and_load') ?? 'Clear & Load'),
                ),
              ],
            ),
          );

          if (confirm != true) return;
        }

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

  Future<void> _handleProductBarcode(String barcode) async {
    final database = ref.read(databaseProvider);

    try {
      // Search for product by barcode
      final product = await (database.select(database.products)
        ..where((tbl) => tbl.barcode.equals(barcode))
        ..where((tbl) => tbl.isActive.equals(true)))
        .getSingleOrNull();


      if (product != null) {
        // Add product to current order
        ref.read(orderProvider.notifier).addItem(
          OrderItem(productId: product.id, productName: product.name, finalPrice: product.price,quantity: 1, tva: product.tvaAmount, discount: product.discountAmount),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${product.name} added to order'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Product with barcode $barcode not found'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      _logger.error('Error loading product from barcode: $e');
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
    _barcodeSubscription?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentOrder = ref.watch(orderProvider);
    final settings = ref.watch(settingsProvider);
    final displayMode = ref.watch(categoryDisplayModeProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final searchQuery = ref.watch(productSearchQueryProvider);
    final l10n = AppLocalizations.of(context)!;

    // In fullPage mode:
    // - Show ProductGrid if searching (regardless of category selection)
    // - Show CategoryGrid when no category selected AND not searching
    // - Show ProductGrid when category selected
    final showCategoryGrid = displayMode == CategoryDisplayMode.fullPage &&
                             selectedCategory == null &&
                             searchQuery.isEmpty;

    final orderPanelOnRight = settings.orderPanelOnRight;

    final orderPanel = const SizedBox(
      width: 400,
      child: OrderPanel(),
    );

    final mainContent = Expanded(
      flex: 2,
      child: Column(
        children: [
          const CategorySelector(),
          Expanded(
            // ✅ Use showCategoryGrid instead of settings.categoryDisplayMode
            child: showCategoryGrid
                ? const CategoryGrid()
                : const ProductGrid(),
          ),
        ],
      ),
    );


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
              children: orderPanelOnRight
                  ? [mainContent, orderPanel] // Order panel on right
                  : [orderPanel, mainContent], // Order panel on left
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

                    // Handle unselect action
                    if (action == 'unselect') {
                      ref.read(orderProvider.notifier).clearTable();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l10n.translate('table_unselected')),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

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
                      label: currentOrder.customerName ?? l10n.translate('customer'),
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
                      label: currentOrder.commercialName ?? l10n.translate('commercial'),
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
                    _buildActionButton(icon: Icons.discount, label: l10n.translate('coupon'), onPressed: (){}),
                  if (settings.showCouponButton)
                    const SizedBox(width: 8),
                  // Manual Discount - Protected by permission and settings
                  if (settings.showDiscountButton && ref.read(permissionServiceProvider).hasPermission(Permissions.manualDiscount))
                    _buildActionButton(
                      icon: Icons.percent,
                      label: currentOrder.discountPercentage > 0
                        ? "${l10n.translate('discount')} ${currentOrder.discountPercentage.toStringAsFixed(0)}%"
                        : l10n.translate('manual_discount'),
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
                if (settings.showPrintButton && ref.read(permissionServiceProvider).hasPermission(Permissions.printing))
                    const SizedBox(width: 8),
                // Daily Summary Report button
                if (settings.showDailySummaryButton)
                  _buildActionButton(
                    icon: Icons.summarize,
                    label: l10n.translate('daily_summary'),
                    color: Colors.teal,
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => const DailySummaryDialog(),
                      );
                    },
                  ),
                if (settings.showDailySummaryButton)
                  const SizedBox(width: 8),
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
                // Pay button - Single click: direct payment, Long press: show payment dialog
                if (settings.showPayButton)
                  _buildActionButton(
                    icon: Icons.payment,
                    label: l10n.translate('pay'),
                    color: Colors.green[700],
                    onPressed: currentOrder.items.isEmpty ? null : () => _payDirectly(),
                    onLongPress: currentOrder.items.isEmpty ? null : () => _showPaymentDialog(),
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
    VoidCallback? onLongPress,
    Color? color,
    bool isPrimary = false,
  }) {
    return SizedBox(
      width: 130,
      height: 130,
      child: isPrimary
          ? ElevatedButton(
        onPressed: onPressed,
        onLongPress: onLongPress,
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
            Text(label, textAlign: TextAlign.justify,),
          ],
        ),
      )
          : OutlinedButton(
        onPressed: onPressed,
        onLongPress: onLongPress,
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

  /// Pay directly with a single ticket (no dialog)
  Future<void> _payDirectly() async {
    final currentOrder = ref.read(orderProvider);
    final orderRepo = ref.read(orderRepositoryProvider);
    final currentUser = ref.read(currentUserProvider);
    final settings = ref.read(settingsProvider);
    final database = ref.read(databaseProvider);
    final session = ref.read(currentSessionProvider);
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);

    if (currentUser == null) return;

    try {
      int orderId;
      // Save or update order first
      if (currentOrder.isSaved()) {
        await orderRepo.updateOrder(currentOrder);
        orderId = currentOrder.orderId!;
      } else {
        orderId = await orderRepo.saveOrder(
          currentOrder,
          currentUser.id,
          status: settings.defaultOrderStatus,
        );
        if (currentOrder.tableId != null) {
          await orderRepo.setTableOrderId(currentOrder.tableId!, orderId);
        }
      }

      // ✅ RELOAD order from database to get the auto-generated product IDs
      final reloadedOrder = await orderRepo.getOrderById(orderId);
      if (reloadedOrder == null) {
        throw Exception('Failed to reload order after saving');
      }

      // Get next ticket number
      final existingTickets = await (database.select(database.tickets)
        ..where((t) => t.orderId.equals(orderId))).get();

      final maxTicketNum = existingTickets.isEmpty
          ? 0
          : existingTickets.map((t) => int.tryParse(t.num) ?? 0).reduce((a, b) => a > b ? a : b);

      final newTicketNum = maxTicketNum + 1;
      final ticketNumStr = newTicketNum.toString().padLeft(4, '0');

      // Calculate total from reloaded order
      final total = reloadedOrder.total;

      // Insert ticket with default payment method (cash)
      final ticketId = await database.into(database.tickets).insert(
        TicketsCompanion.insert(
          num: ticketNumStr,
          orderId: orderId,
          paymentMethod: TransactionType.cash.value,
          amount: total,
          sessionId: Value(session?.id),
          isPaid: const Value(true),
          printCount: const Value(0),
        ),
      );

      // ✅ Update ALL order items using the RELOADED order (which has database IDs)
      for (final item in reloadedOrder.items) {
        if (item.id != null) {
          await (database.update(database.orderProducts)
            ..where((tbl) => tbl.id.equals(item.id!))).write(
            OrderProductsCompanion(
              ticketId: Value(ticketId),
              state: const Value('PAID'),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }

      // Print receipt using reloaded order items
      try {
        final businessName = prefs.getString('business_name') ?? 'THANK YOU FOR YOUR PURCHASE';

        final itemsForPrint = reloadedOrder.items.map((item) {
          return {
            'name': item.productName,
            'quantity': item.quantity,
            'price': item.totalPrice,
            'components': item.components.map((c) => {'name': c.name, 'quantity': c.quantity}).toList(),
          };
        }).toList();

        // Print KDS ticket first (for kitchen)
        if (printingService.config.kdsEnabled) {
          try {
            await printingService.printKdsTicket(
              order: reloadedOrder,
              cashierName: currentUser.firstName,
            );
          } catch (kdsError) {
            _logger.error('KDS print failed on direct payment: $kdsError');
            // Continue even if KDS fails
          }
        }

        // Then print customer receipt
        await printingService.printTicketReceipt(
          ticketId: ticketId,
          ticketNumber: ticketNumStr,
          amount: total,
          paymentMethod: TransactionType.cash.value,
          createdAt: DateTime.now(),
          items: itemsForPrint,
          orderCode: reloadedOrder.orderCode,
          cashierName: currentUser.firstName,
          storeName: businessName,
        );

        await database.customStatement(
          'UPDATE tickets SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
          [ticketId],
        );
      } catch (e) {
        _logger.error('Print failed: $e');
      }

      if (context.mounted) {
        // Clear order
        ref.read(orderProvider.notifier).clearOrder();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment completed! Ticket #$ticketNumStr'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      _logger.error('Direct payment failed: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Show payment dialog for split payment
  Future<void> _showPaymentDialog() async {
    final currentOrder = ref.read(orderProvider);
    final orderRepo = ref.read(orderRepositoryProvider);
    final currentUser = ref.read(currentUserProvider);
    final settings = ref.read(settingsProvider);

    if (currentUser == null) return;

    try {
      int orderId;
      // Save or update order first
      if (currentOrder.isSaved()) {
        await orderRepo.updateOrder(currentOrder);
        orderId = currentOrder.orderId!;
      } else {
        orderId = await orderRepo.saveOrder(
          currentOrder,
          currentUser.id,
          status: settings.defaultOrderStatus,
        );
        if (currentOrder.tableId != null) {
          await orderRepo.setTableOrderId(currentOrder.tableId!, orderId);
        }
      }

      // Reload the order from database to get updated IDs
      final reloadedOrder = await orderRepo.getOrderById(orderId);
      if (reloadedOrder == null) {
        throw Exception('Failed to reload order');
      }

      if (context.mounted) {
        // Open payment screen dialog
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
          // Dialog closed without completion, reload order state
          final updatedOrder = await orderRepo.getOrderById(orderId);
          if (updatedOrder != null) {
            ref.read(orderProvider.notifier).loadOrder(updatedOrder);
          }
        }
      }
    } catch (e) {
      _logger.error('Error opening payment dialog: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.translate('number_of_persons')),
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
          child: Text(l10n.translate('cancel')),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selectedNumber),
          child: Text(l10n.translate('ok')),
        ),
      ],
    );
  }
}

import 'dart:async';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
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
import '../../services/printing_service.dart';
import '../../utils/app_localizations.dart';
import '../order_confirmation/order_confirmation_screen.dart';
import '../paymen_screen/payment_screen.dart';
// TEMP-TIP-HIDDEN: pourboire flow disabled — restore this import together
// with the four commented-out blocks below (`case 'tip'`, the two payment
// helpers, the table-pay branch).
// import '../widgets/tip_flow.dart';
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
import '../widgets/waiter_selection_dialog.dart';
import '../widgets/top_bar.dart';
import '../../utils/order_validation.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/responsive_utils.dart';
import '../../providers/sync_manager_provider.dart';
import '../../providers/network_provider.dart';
import '../../providers/sse_provider.dart';
import '../../providers/session_rules_provider.dart';
import '../../services/session_service.dart';
import '../../services/customer_display_service.dart';
import '../../services/scale_barcode_service.dart';
import '../../domain/models/scale_config.dart';
import '../../providers/scale_config_provider.dart';

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  final _logger = Logger.instance;
  final _focusNode = FocusNode();
  StreamSubscription<String>? _barcodeSubscription;
  Timer? _autoCloseTimer;

  // Responsive sizing — updated in build() from MediaQuery
  double _btnSize = 130;
  double _barHeight = 150;

  /// True while a Proceed/Pay handler has a save (insert or update) in
  /// flight. Used to disable the Proceed/Pay buttons so a slow DB write
  /// can't be triggered twice by an impatient double-tap (root cause of
  /// duplicate-order inserts).
  bool _isSavingOrder = false;

  @override
  void initState() {
    super.initState();
    _initializeBarcodeScanner();
    _requestSearchFocus();
    _startAutoCloseTimer();
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
          SnackBarHelper.showSuccessSnackBar(
            context,
            ref,
            'Order $barcode loaded',
            duration: const Duration(seconds: 2),
          );
        }
      } else {
        if (mounted) {
          SnackBarHelper.showWarningSnackBar(
            context,
            ref,
            'Order $barcode not found',
            duration: const Duration(seconds: 2),
          );
        }
      }
    } catch (e) {
      _logger.error('Error loading order from barcode: $e');
      if (mounted) {
        SnackBarHelper.showErrorSnackBar(
          context,
          ref,
          'Error: $e',
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  Future<void> _handleProductBarcode(String barcode) async {
    final scaleConfig = ref.read(scaleConfigProvider);
    final result = classifyBarcode(barcode, scaleConfig);

    switch (result) {
      case StaticItem():
        await _handleStaticBarcode(result.raw);
      case WeightedItem():
        await _handleWeightedBarcode(result);
      case ConfigMismatch():
        // Wrong length for a scale label but starts with the scale prefix —
        // fall back to a normal product lookup so regular product barcodes
        // that share the prefix still work.
        await _handleStaticBarcode(barcode);
      case MalformedWeightBarcode():
        if (mounted) {
          SnackBarHelper.error(
            context,
            'Malformed scale barcode: ${result.reason}',
          );
        }
    }
  }

  Future<void> _handleStaticBarcode(String barcode) async {
    final database = ref.read(databaseProvider);

    try {
      final product = await (database.select(database.products)
        ..where((tbl) => tbl.barcode.equals(barcode))
        ..where((tbl) => tbl.isActive.equals(true)))
        .getSingleOrNull();

      if (product != null) {
        // Adding to a SAVED order requires the add-item permission.
        final currentOrder = ref.read(orderProvider);
        if (currentOrder.orderId != null &&
            !ref.read(permissionServiceProvider).hasPermission(Permissions.ordersItemAdd)) {
          if (mounted) {
            SnackBarHelper.error(
              context, AppLocalizations.of(context)!.translate('no_permission'));
          }
          return;
        }
        ref.read(orderProvider.notifier).addItem(
          OrderItem(
            productId: product.id,
            productName: product.name,
            finalPrice: product.finalPrice,
            quantity: 1,
            tva: product.tvaAmount,
            discount: product.discountAmount,
            imageUrl: product.imageUrl,
          ),
        );

        if (mounted) {
          SnackBarHelper.success(
            context,
            '${product.name} added to order',
            duration: const Duration(seconds: 1),
          );
        }
      } else {
        _logger.warning('Barcode lookup: no active product found for barcode "$barcode"');
        if (mounted) {
          SnackBarHelper.warning(
            context,
            'Product with barcode $barcode not found',
            duration: const Duration(seconds: 2),
          );
        }
      }
    } catch (e) {
      _logger.error('Error loading product from barcode: $e');
      if (mounted) {
        SnackBarHelper.error(
          context,
          'Error: $e',
          duration: const Duration(seconds: 2),
        );
      }
    }
  }

  Future<void> _handleWeightedBarcode(WeightedItem result) async {
    final l10n = AppLocalizations.of(context);
    final scaleConfig = ref.read(scaleConfigProvider);
    final orderRepo = ref.read(orderRepositoryProvider);

    // Look up product by MBW/PLU code.
    _logger.info('Scale barcode: PLU="${result.plu}" value=${result.extractedValue}');
    final product = await orderRepo.findByMbwCode(result.plu);
    if (product == null) {
      _logger.warning('Scale barcode: no active product found for PLU "${result.plu}"');
      if (mounted) {
        SnackBarHelper.error(
          context,
          l10n?.translate('scale_item_not_found') ?? 'Scale item not found. PLU: ${result.plu}',
          duration: const Duration(seconds: 4),
        );
      }
      return;
    }

    // Compute line total.
    double lineTotal;
    double pricePerKgDisplay;

    if (product.pricePerKg != null && product.pricePerKg! > 0) {
      pricePerKgDisplay = product.pricePerKg! / 100.0;
    } else {
      // Fall back to the product's default sale price as the per-kg rate.
      pricePerKgDisplay = product.finalPrice;
    }

    if (pricePerKgDisplay <= 0) {
      if (mounted) {
        SnackBarHelper.error(
          context,
          l10n?.translate('scale_no_price_per_kg') ??
              'Product "${product.name}" has no price configured.',
          duration: const Duration(seconds: 4),
        );
      }
      return;
    }

    if (scaleConfig.barcodeType == ScaleBarcodeType.weightEmbedded) {
      // extractedValue IS the weight in kg.
      lineTotal = double.parse(
        (result.extractedValue * pricePerKgDisplay).toStringAsFixed(2),
      );
    } else {
      // PRICE_EMBEDDED — extractedValue IS the line total; derive weight from it.
      lineTotal = double.parse(result.extractedValue.toStringAsFixed(2));
    }

    // Hard stop on zero total.
    if (lineTotal <= 0 || result.extractedValue <= 0) {
      if (mounted) {
        SnackBarHelper.error(
          context,
          l10n?.translate('scale_zero_total') ??
              'Zero weight or total — item not added.',
          duration: const Duration(seconds: 3),
        );
      }
      return;
    }

    // Both directions: quantity = weightKg, unitPrice = price/kg.
    // WEIGHT_EMBEDDED: weight from barcode → derive total.
    // PRICE_EMBEDDED:  total from barcode → derive weight = total / price/kg.
    final double weightKg;
    if (scaleConfig.barcodeType == ScaleBarcodeType.weightEmbedded) {
      weightKg = result.extractedValue;
    } else {
      weightKg = double.parse(
        (lineTotal / pricePerKgDisplay).toStringAsFixed(3),
      );
    }

    ref.read(orderProvider.notifier).addWeighedItem(
      productId: product.id,
      productName: product.name,
      imageUrl: product.imageUrl,
      quantity: weightKg,
      unitPrice: pricePerKgDisplay,
      weightKg: weightKg,
      pricePerKgDisplay: pricePerKgDisplay,
      unitName: product.unitName,
    );

    if (mounted) {
      SnackBarHelper.success(
        context,
        '${product.name} ${weightKg.toStringAsFixed(3)} kg added',
        duration: const Duration(seconds: 1),
      );
    }
  }

  void _startAutoCloseTimer() {
    _autoCloseTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final rules = ref.read(sessionRulesProvider);
      if (rules.maxEndHour == null && rules.maxSessionDurationMinutes == null) {
        return;
      }
      final session = ref.read(currentSessionProvider);
      if (session == null) return;

      // Only auto-close when the panel is truly empty.
      final order = ref.read(orderProvider);
      if (order.items.isNotEmpty) return;

      final now = DateTime.now();

      if (rules.maxEndHour != null && now.hour >= rules.maxEndHour!) {
        _autoCloseSession(session, 'auto_close_max_end_hour');
        return;
      }

      if (rules.maxSessionDurationMinutes != null) {
        final elapsed = now.difference(session.startedAt).inMinutes;
        if (elapsed >= rules.maxSessionDurationMinutes!) {
          _autoCloseSession(session, 'auto_close_max_duration');
        }
      }
    });
  }

  /// Called when the server pushes a close_session / close_all_sessions /
  /// force_logout command via SSE. Syncs remaining data then navigates to login.
  Future<void> _handleSseSessionClose() async {
    try {
      final syncService = ref.read(dataSyncServiceProvider);
      await Future.wait([
        syncService.syncPendingOperations(),
        syncService.syncSessionsBulk(),
        syncService.syncOrdersBulk(),
        syncService.syncTicketsBulk(),
      ]).timeout(const Duration(seconds: 15));
    } catch (e) {
      _logger.warning('SSE session-close pre-logout sync failed: $e');
    }
    ref.read(currentUserProvider.notifier).state = null;
    ref.read(currentSessionProvider.notifier).state = null;
    ref.read(orderProvider.notifier).clearOrder();
    if (mounted) {
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  Future<void> _autoCloseSession(
      CashSession session, String reasonKey) async {
    _autoCloseTimer?.cancel();
    try {
      final db = ref.read(databaseProvider);
      final sessionService = SessionService(db);
      await sessionService.endSession(sessionId: session.id);
      ref.read(currentSessionProvider.notifier).state = null;
      // Sync all pending data to server before returning to login.
      try {
        final syncService = ref.read(dataSyncServiceProvider);
        await Future.wait([
          syncService.syncPendingOperations(),
          syncService.syncSessionsBulk(),
          syncService.syncOrdersBulk(),
          syncService.syncTicketsBulk(),
        ]).timeout(const Duration(seconds: 15));
      } catch (e) {
        _logger.warning('Pre-logout sync failed (non-blocking): $e');
      }
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.translate(reasonKey)),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
        ));
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pushReplacementNamed('/login');
        });
      }
    } catch (e) {
      _logger.error('Auto-close session failed: $e');
      // Restart the timer so we retry on the next tick.
      _startAutoCloseTimer();
    }
  }

  @override
  void dispose() {
    _autoCloseTimer?.cancel();
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

    // Activate SSE connection while MainScreen is mounted
    ref.watch(sseLifecycleProvider);

    // Force-logout: fires when the server rejects the refresh token (4xx on
    // /pos/refresh). Clears focus and navigates to login on the next frame.
    ref.listen<AsyncValue<void>>(forceLogoutStreamProvider, (_, next) {
      next.whenData((_) {
        if (!mounted) return;
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pushReplacementNamed('/login');
        });
      });
    });

    // When sync updates an order that is currently open in the panel, reload
    // it so the cashier sees the latest items/prices without manual refresh.
    ref.listen<AsyncValue<int>>(syncedOrderUpdatedProvider, (_, next) {
      next.whenData((updatedOrderId) async {
        final panelOrderId = ref.read(orderProvider).orderId;
        if (panelOrderId != updatedOrderId) return;
        final refreshed = await ref
            .read(orderRepositoryProvider)
            .getOrderById(updatedOrderId);
        if (refreshed != null && mounted) {
          ref.read(orderProvider.notifier).setOrder(refreshed);
        }
      });
    });

    // When the server commands a session close or force-logout via SSE,
    // sync remaining data and return to the login screen.
    ref.listen<int>(sseSessionClosedProvider, (prev, next) {
      if (prev == next) return;
      _handleSseSessionClose();
    });

    // Show SnackBar when admin pushes a DISPLAY_ALERT command
    ref.listen<String?>(sseAlertProvider, (_, message) {
      if (message == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.campaign, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.deepOrange,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () =>
                ref.read(sseAlertProvider.notifier).state = null,
          ),
        ),
      );
      // Clear after showing so re-watch doesn't retrigger
      ref.read(sseAlertProvider.notifier).state = null;
    });

    // Push order updates to customer display if enabled
    ref.listen<CurrentOrder>(orderProvider, (previous, next) {
      final s = ref.read(settingsProvider);
      if (!s.enableCustomerDisplay) return;
      final displayService = ref.read(customerDisplayServiceProvider);
      if (displayService.isOpen) {
        if (next.items.isEmpty) {
          displayService.clearDisplay();
        } else {
          displayService.sendOrderUpdate(next);
        }
      }
    });

    // In fullPage mode:
    // - Show ProductGrid if searching (regardless of category selection)
    // - Show CategoryGrid when no category selected AND not searching
    // - Show ProductGrid when category selected
    final showCategoryGrid = displayMode == CategoryDisplayMode.fullPage &&
                             selectedCategory == null &&
                             searchQuery.isEmpty;

    final orderPanelOnRight = settings.orderPanelOnRight;

    final screenWidth = MediaQuery.sizeOf(context).width;
    _btnSize = actionButtonSize(screenWidth);
    _barHeight = actionBarHeight(screenWidth);
    final panelWidth = orderPanelWidth(screenWidth);

    final orderPanel = SizedBox(
      width: panelWidth,
      child: const OrderPanel(),
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
        body: Stack(
          children: [
            Column(
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
                height: _barHeight,
                padding: const EdgeInsets.all(8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: _buildOrderedActionButtons(context, ref, currentOrder, settings, l10n),
                  ),
                ),
              ),
            ],
          ),
          // Printing status overlay
          StreamBuilder<String?>(
            stream: ref.read(printingServiceProvider).printingStatusStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data == null) {
                return const SizedBox.shrink();
              }
              return Container(
                color: Colors.black54,
                child: Center(
                  child: Card(
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 48,
                            height: 48,
                            child: CircularProgressIndicator(strokeWidth: 4),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            snapshot.data!,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      ),
    );
  }



  IconData _orderTypeIcon(String type) {
    switch (type) {
      case 'TAKE_AWAY':
        return Icons.takeout_dining;
      case 'DELIVERY':
        return Icons.delivery_dining;
      default:
        return Icons.restaurant;
    }
  }

  String _orderTypeLabel(String type, AppLocalizations l10n) {
    switch (type) {
      case 'TAKE_AWAY':
        return l10n.translate('take_away');
      case 'DELIVERY':
        return l10n.translate('delivery');
      default:
        return l10n.translate('dine_in');
    }
  }

  Color _orderTypeColor(String type) {
    switch (type) {
      case 'TAKE_AWAY':
        return Colors.orange;
      case 'DELIVERY':
        return Colors.blue;
      default:
        return Colors.green;
    }
  }

  /// Dialog chooser for the order type — three big, touch-friendly buttons.
  /// Picking Delivery also prompts for the delivery address.
  Future<void> _showOrderTypeChooser(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SizedBox(
          width: 400,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.translate('order_type'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                for (final type in const ['DINE_IN', 'TAKE_AWAY', 'DELIVERY']) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 96,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, type),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _orderTypeColor(type),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_orderTypeIcon(type), size: 40),
                          const SizedBox(width: 16),
                          Text(
                            _orderTypeLabel(type, l10n),
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.translate('cancel')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null) return;
    ref.read(orderProvider.notifier).setOrderType(selected);
    if (selected == 'DELIVERY' && context.mounted) {
      await _showDeliveryAddressDialog(context);
    }
  }

  /// Touch-friendly delivery-address entry (uses the on-screen keyboard).
  Future<void> _showDeliveryAddressDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(
        text: ref.read(orderProvider).deliveryAddress ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.delivery_dining, color: Colors.blue),
            const SizedBox(width: 8),
            Text(l10n.translate('delivery_address')),
          ],
        ),
        content: OnscreenKeyboardTextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: l10n.translate('enter_delivery_address'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.translate('save')),
          ),
        ],
      ),
    );
    if (result != null) {
      ref.read(orderProvider.notifier).setDeliveryAddress(result);
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    VoidCallback? onLongPress,
    Color? color,
    bool isPrimary = false,
  }) {
    // Keep the label visible even on the smallest buttons — just scale the
    // icon and text down so both fit. A label too long to fit (e.g. a long
    // table name) scrolls back and forth via [_MarqueeLabel] instead of being
    // hidden or hard-cropped.
    final iconSize = _btnSize < 80 ? 18.0 : (_btnSize < 100 ? 22.0 : 30.0);
    final labelStyle = TextStyle(
      fontSize: _btnSize < 80 ? 9.5 : (_btnSize < 100 ? 10.5 : 12.5),
      fontWeight: FontWeight.w600,
      height: 1.05,
    );

    final child = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: iconSize),
        SizedBox(height: _btnSize < 80 ? 2 : 4),
        SizedBox(
          width: double.infinity,
          child: _MarqueeLabel(text: label, style: labelStyle),
        ),
      ],
    );

    return SizedBox(
      width: _btnSize,
      height: _btnSize,
      child: isPrimary
          ? ElevatedButton(
              onPressed: onPressed,
              onLongPress: onLongPress,
              style: ElevatedButton.styleFrom(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: EdgeInsets.all(_btnSize < 90 ? 4 : 8),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: onPressed,
              onLongPress: onLongPress,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: color ?? Colors.grey),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.zero,
                ),
                padding: EdgeInsets.all(_btnSize < 90 ? 4 : 8),
              ),
              child: child,
            ),
    );
  }

  /// Build action buttons in the order specified by settings.buttonOrder
  List<Widget> _buildOrderedActionButtons(
    BuildContext context,
    WidgetRef ref,
    dynamic currentOrder,
    AppSettings settings,
    AppLocalizations l10n,
  ) {
    final List<Widget> buttons = [];
    final permissionService = ref.read(permissionServiceProvider);

    // Check if table is selected - if so, order type is locked to DINE_IN
    final bool isTableSelected = currentOrder.tableId != null;

    // Ensure order type is DINE_IN when table is selected
    if (isTableSelected && currentOrder.type != 'DINE_IN') {
      // Auto-set to DINE_IN when table is selected
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(orderProvider.notifier).setOrderType('DINE_IN');
      });
    }

    for (final buttonKey in settings.buttonOrder) {
      Widget? button;
      bool shouldShow = true;

      switch (buttonKey) {
        case 'persons':
          shouldShow = settings.showPersonsButton;
          if (shouldShow) {
            button = _buildActionButton(
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
            );
          }
          break;

        case 'orderType':
          shouldShow = settings.showOrderTypeButton;
          if (shouldShow) {
            button = _buildActionButton(
              icon: _orderTypeIcon(currentOrder.type),
              label: _orderTypeLabel(currentOrder.type, l10n),
              color: isTableSelected
                  ? Colors.grey // Disabled look when table is selected
                  : _orderTypeColor(currentOrder.type),
              onPressed: isTableSelected
                  ? null // Disable when a table is selected (table ⇒ dine-in)
                  : () => _showOrderTypeChooser(context),
            );
          }
          break;

        case 'confirmOrder':
          shouldShow = settings.showConfirmOrderButton;
          if (shouldShow) {
            button = _buildActionButton(
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
            );
          }
          break;

        case 'table':
          shouldShow = settings.showTableButton &&
              permissionService.hasPermission(Permissions.tablesSet);
          if (shouldShow) {
            button = _buildActionButton(
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

                  // Handle transfer action
                  if (action == 'transfer') {
                    final oldTableId = result['oldTableId'] as int?;
                    final orderId = currentOrder.orderId;

                    if (oldTableId != null && orderId != null && tableId != null) {
                      final orderRepo = ref.read(orderRepositoryProvider);
                      await orderRepo.transferOrderToTable(orderId, oldTableId, tableId);

                      // Update current order state with new table
                      ref.read(orderProvider.notifier).updateTable(tableId, tableName);

                      // Refresh tables provider
                      ref.invalidate(areaTablesProvider);

                      if (context.mounted) {
                        SnackBarHelper.showSuccessSnackBar(
                          context,
                          ref,
                          '${l10n.translate('order_transferred_to')} $tableName',
                        );
                      }
                    }
                    return;
                  }

                  // "Switch" — saved order stays where it is; just empty the
                  // working panel and move the cashier to the new table.
                  if (action == 'switch') {
                    ref.read(orderProvider.notifier).clearOrder();
                    if (tableId != null) {
                      ref
                          .read(orderProvider.notifier)
                          .setTable(tableId, tableName);
                      ref
                          .read(orderProvider.notifier)
                          .setOrderType('DINE_IN');
                    }
                    return;
                  }

                  // Handle different actions
                  if (action == 'pay' && result['order'] != null) {
                    final order = result['order'] as CurrentOrder;
                    // TEMP-TIP-HIDDEN: pourboire flow disabled.
                    // if (context.mounted) {
                    //   order = await applyTipIfEnabled(context, ref, order);
                    // }
                    if (!context.mounted) return;
                    final paymentResult = await showDialog<bool>(
                      context: context,
                      builder: (context) => PaymentScreen(order: order),
                    );

                    if (paymentResult == true && context.mounted) {
                      SnackBarHelper.showSuccessSnackBar(
                        context,
                        ref,
                        l10n.translate('payment_successful'),
                      );
                    }
                    return;
                  }

                  if (action == 'cleared') {
                    final clearedTableName = result['tableName'];
                    SnackBarHelper.showSuccessSnackBar(
                      context,
                      ref,
                      '$clearedTableName ${l10n.translate('table_cleared')}',
                    );
                    return;
                  }

                  if (action == 'addItems') {
                    if (existingOrder != null) {
                      ref.read(orderProvider.notifier).loadOrder(existingOrder);
                      if (context.mounted) {
                        SnackBarHelper.showInfoSnackBar(
                          context,
                          ref,
                          'Adding items to $tableName order',
                        );
                      }
                    }
                    return;
                  }

                  final hasItems =
                      ref.read(orderProvider).items.isNotEmpty;

                  if (existingOrder != null) {
                    // Table already has an open order. If the cashier has
                    // their own items in the cart, ask before discarding
                    // them.
                    if (hasItems) {
                      final confirmed =
                          await _confirmDiscardCurrentForTableOrder(
                        context,
                        tableName: tableName,
                        existingOrder: existingOrder,
                        l10n: l10n,
                      );
                      if (confirmed != true) {
                        return; // cart preserved, no table attached
                      }
                    }
                    ref.read(orderProvider.notifier).loadOrder(existingOrder);
                    if (context.mounted) {
                      SnackBarHelper.showInfoSnackBar(
                        context,
                        ref,
                        '${l10n.translate('order')} ${l10n.translate('for')} $tableName',
                      );
                    }
                  } else {
                    // Empty table — preserve the cashier's current cart and
                    // just attach the table. setTable() clears items, so we
                    // only use it when there's nothing to lose.
                    if (hasItems) {
                      ref
                          .read(orderProvider.notifier)
                          .updateTable(tableId, tableName);
                    } else {
                      ref
                          .read(orderProvider.notifier)
                          .setTable(tableId, tableName);
                    }
                    ref.read(orderProvider.notifier).setOrderType('DINE_IN');
                  }
                }
              },
            );
          }
          break;

        case 'customer':
          shouldShow = settings.showCustomerButton &&
                       permissionService.hasPermission(Permissions.customerSet);
          if (shouldShow) {
            button = _buildActionButton(
              icon: Icons.person,
              label: currentOrder.customerName ?? l10n.translate('customer'),
              color: currentOrder.customerId != null ? Colors.green : null,
              onPressed: () async {
                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (context) => const CustomerSelectionDialog(),
                );
                if (result != null) {
                  if (result['id'] == null) {
                    ref.read(orderProvider.notifier).clearCustomer();
                  } else {
                    ref.read(orderProvider.notifier).setCustomer(
                      result['id'],
                      result['name'],
                      customerPhone: result['phone'],
                    );
                  }
                }
              },
            );
          }
          break;

        case 'commercial':
          shouldShow = settings.showCommercialButton &&
                       permissionService.hasPermission(Permissions.commercialSet);
          if (shouldShow) {
            button = _buildActionButton(
              icon: Icons.badge,
              label: currentOrder.commercialName ?? l10n.translate('commercial'),
              color: currentOrder.commercialId != null ? Colors.purple : null,
              onPressed: () async {
                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (context) => const CommercialSelectionDialog(),
                );
                if (result != null) {
                  if (result['id'] == null) {
                    ref.read(orderProvider.notifier).clearCommercial();
                  } else {
                    ref.read(orderProvider.notifier).setCommercial(result['id'], result['name']);
                  }
                }
              },
            );
          }
          break;

        case 'waiter':
          shouldShow = settings.showWaiterButton &&
                       permissionService.hasPermission(Permissions.waiterSet);
          if (shouldShow) {
            button = _buildActionButton(
              icon: Icons.person_pin,
              label: currentOrder.waiterName ?? l10n.translate('waiter'),
              color: currentOrder.waiterId != null ? Colors.teal : null,
              onPressed: () async {
                final result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (context) => WaiterSelectionDialog(
                    currentTableId: currentOrder.tableId,
                    currentWaiterId: currentOrder.waiterId,
                  ),
                );
                if (result != null) {
                  final action = result['action'];
                  if (action == 'unselect') {
                    ref.read(orderProvider.notifier).clearWaiter();
                    // Update database if order is saved
                    if (currentOrder.orderId != null) {
                      final updatedOrder = ref.read(orderProvider);
                      await ref.read(orderRepositoryProvider).updateOrder(updatedOrder);
                    }
                  } else if (action == 'select') {
                    ref.read(orderProvider.notifier).setWaiter(
                      result['waiterId'],
                      result['waiterName'],
                    );
                    // Update database if order is saved
                    if (currentOrder.orderId != null) {
                      final updatedOrder = ref.read(orderProvider);
                      await ref.read(orderRepositoryProvider).updateOrder(updatedOrder);
                    }
                  }
                }
              },
            );
          }
          break;

        case 'coupon':
          shouldShow = settings.showCouponButton;
          if (shouldShow) {
            button = _buildActionButton(
              icon: Icons.discount,
              label: l10n.translate('coupon'),
              onPressed: () {},
            );
          }
          break;

        case 'discount':
          shouldShow = settings.showDiscountButton &&
                       permissionService.hasPermission(Permissions.manualDiscount);
          if (shouldShow) {
            button = _buildActionButton(
              icon: Icons.percent,
              label: currentOrder.discountPercentage > 0
                  ? "${l10n.translate('discount')} ${currentOrder.discountPercentage.toStringAsFixed(0)}%"
                  : l10n.translate('manual_discount'),
              color: currentOrder.discountPercentage > 0 ? Colors.orange : null,
              onPressed: currentOrder.hasPaidItems
                  ? null
                  : () async {
                      final result = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (context) => ManualDiscountDialog(
                          currentPercentage: currentOrder.discountPercentage,
                          currentNote: currentOrder.note,
                        ),
                      );
                      if (result != null) {
                        final percentage = result['percentage'] as double? ?? 0.0;
                        final note = result['note'] as String?;
                        ref.read(orderProvider.notifier).setDiscountPercentage(percentage);
                        ref.read(orderProvider.notifier).setNote(note);
                      }
                    },
            );
          }
          break;

        case 'print':
          shouldShow = settings.showPrintButton &&
                       permissionService.hasPermission(Permissions.printing);
          if (shouldShow) {
            button = _buildActionButton(
              icon: Icons.print,
              label: l10n.translate('print'),
              onPressed: currentOrder.items.isEmpty
                  ? null
                  : () async {
                      final currentUser = ref.read(currentUserProvider);
                      final printSession = ref.read(currentSessionProvider);
                      final orderRepo = ref.read(orderRepositoryProvider);
                      final settings = ref.read(settingsProvider);

                      int? orderId = currentOrder.orderId;
                      if (!currentOrder.isSaved() && currentUser != null) {
                        if (printSession == null) {
                          if (context.mounted) SnackBarHelper.showErrorSnackBar(context, ref, 'No active session');
                          return;
                        }
                        try {
                          _logger.debug('Print: Saving new order with ${currentOrder.items.length} items');
                          orderId = await orderRepo.saveOrder(
                            currentOrder,
                            currentUser.id,
                            status: settings.defaultOrderStatus,
                            sessionId: printSession.id,
                          );

                          if (currentOrder.tableId != null) {
                            await orderRepo.setTableOrderId(currentOrder.tableId!, orderId);
                          }

                          final reloadedOrder = await orderRepo.getOrderById(orderId);
                          if (reloadedOrder != null) {
                            ref.read(orderProvider.notifier).loadOrder(reloadedOrder);
                          }
                        } catch (e) {
                          _logger.error('Error saving order for print: $e');
                          if (context.mounted) {
                            SnackBarHelper.showErrorSnackBar(
                              context,
                              ref,
                              'Error saving order: $e',
                            );
                          }
                          return;
                        }
                      }

                      if (context.mounted) {
                        final orderToPrint = currentOrder.isSaved()
                            ? currentOrder
                            : (orderId != null ? await orderRepo.getOrderById(orderId) : null);

                        if (orderToPrint != null) {
                          await showPrintOptionsDialog(
                            context,
                            order: orderToPrint,
                            cashierName: currentUser?.firstName,
                            storeName: "",
                          );
                        }
                      }
                    },
            );
          }
          break;

        case 'dailySummary':
          shouldShow = settings.showDailySummaryButton &&
              permissionService.hasPermission(Permissions.reportsView);
          if (shouldShow) {
            button = _buildActionButton(
              icon: Icons.summarize,
              label: l10n.translate('daily_summary'),
              color: Colors.teal,
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const DailySummaryDialog(),
                );
              },
            );
          }
          break;

        // TEMP-TIP-HIDDEN: tip toolbar button branch disabled. Restore the
        // whole `case 'tip':` block (and the `import 'tip_flow.dart'`
        // up top) to re-enable. Falls through to the default — no button
        // renders for the 'tip' key in buttonOrder.
        /*
        case 'tip':
          // Tip button. Pure in-memory tip mutation — no save-first dance.
          // If the order is already saved, persist via the normal update
          // path so the row reflects the new tip immediately. If not,
          // setting the tip on the OrderNotifier is enough; the cashier's
          // next Proceed / Pay will save the order with the tip already on
          // it (the row's first write includes the tip — never a "save
          // then add tip" round-trip).
          shouldShow = settings.showTipButton;
          if (shouldShow) {
            final currencySymbol = settings.currency;
            final hasTip = currentOrder.tip > 0;
            button = _buildActionButton(
              icon: Icons.attach_money,
              label: hasTip
                  ? '${l10n.translate('tip')}: ${currentOrder.tip.toStringAsFixed(0)} $currencySymbol'
                  : l10n.translate('tip'),
              color: hasTip ? Colors.amber.shade700 : null,
              onPressed: (currentOrder.items.isEmpty || _isSavingOrder)
                  ? null
                  : () async {
                      final order = ref.read(orderProvider);
                      final updated = await runTipFlow(context, ref, order);
                      if (updated.tip == order.tip) return;
                      ref.read(orderProvider.notifier).setTip(updated.tip);
                      // Already-saved orders: push the tip change via the
                      // normal update path so it doesn't get lost if the
                      // cashier abandons the order or refreshes.
                      if (updated.orderId != null) {
                        try {
                          await ref
                              .read(orderRepositoryProvider)
                              .updateOrder(updated);
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$e'),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                          }
                        }
                      }
                    },
            );
          }
          break;
        */

        case 'pay':
          // Taking payment creates a ticket -> tickets:create.
          shouldShow = settings.showPayButton &&
              permissionService.hasPermission(Permissions.ticketsCreate);
          if (shouldShow) {
            button = _buildActionButton(
              icon: Icons.payment,
              label: l10n.translate('pay'),
              color: Colors.green[700],
              onPressed: (currentOrder.items.isEmpty || _isSavingOrder)
                  ? null
                  : () => _payDirectly(),
              onLongPress: (currentOrder.items.isEmpty || _isSavingOrder)
                  ? null
                  : () => _showPaymentDialog(),
            );
          }
          break;

        case 'proceed':
          // Proceed button is always shown (primary button).
          // New order needs orders:create; persisting a saved order is allowed if
          // the user can make any kind of edit (add/remove/modify) or has update.
          final canProceed = currentOrder.isSaved()
              ? permissionService.hasAnyPermission([
                  Permissions.ordersUpdate,
                  Permissions.ordersItemAdd,
                  Permissions.ordersItemRemove,
                  Permissions.ordersItemModify,
                ])
              : permissionService.hasPermission(Permissions.ordersCreate);
          button = _buildActionButton(
            icon: Icons.check_circle,
            label: l10n.translate('proceed'),
            isPrimary: true,
            onPressed:
                (currentOrder.items.isEmpty || !canProceed || _isSavingOrder)
                    ? null
                    : () async {
                    if (_isSavingOrder) return;
                    final orderRepo = ref.read(orderRepositoryProvider);
                    final currentUser = ref.read(currentUserProvider);
                    final settings = ref.read(settingsProvider);
                    final printingService = ref.read(printingServiceProvider);

                    if (currentUser == null) return;
                    final session = ref.read(currentSessionProvider);
                    if (session == null) return;

                    final ok = await _resolveRuleViolations();
                    if (!ok) return;
                    // Refresh in case the cashier just attached a table /
                    // waiter / customer via the inline fix dialog.
                    currentOrder = ref.read(orderProvider);

                    setState(() => _isSavingOrder = true);
                    try {
                      int orderId;
                      if (currentOrder.isSaved()) {
                        _logger.error("order updated");
                        await orderRepo.updateOrder(currentOrder);
                        orderId = currentOrder.orderId!;
                      } else {
                        _logger.error("new order created with ${currentOrder.items.length} items");
                        orderId = await orderRepo.saveOrder(
                          currentOrder,
                          currentUser.id,
                          status: settings.defaultOrderStatus,
                          sessionId: session.id,
                        );

                        if (currentOrder.tableId != null) {
                          await orderRepo.setTableOrderId(currentOrder.tableId!, orderId);
                        }
                      }

                      final reloadedOrder = await orderRepo.getOrderById(orderId);

                      if (reloadedOrder != null) {
                        try {
                          final prefs = ref.read(sharedPreferencesProvider);
                          final businessName = prefs.getString('business_name');
                          final hasTable = reloadedOrder.tableId != null;

                          if (printingService.shouldPrint(
                            PrintOutput.orderTicket,
                            orderType: reloadedOrder.type,
                            hasTable: hasTable,
                          )) {
                            await printingService.printOrderReceipt(
                              order: reloadedOrder,
                              cashierName: currentUser.firstName,
                              storeName: businessName,
                            );
                          }

                          if (printingService.config.kdsEnabled &&
                              printingService.shouldPrint(
                                PrintOutput.kds,
                                orderType: reloadedOrder.type,
                                hasTable: hasTable,
                              )) {
                            await printingService.printKdsTicket(
                              order: reloadedOrder,
                              cashierName: currentUser.firstName,
                            );
                          }
                        } catch (printError) {
                          _logger.error('Print error on proceed: $printError');
                        }
                      } else {
                        _logger.error('Failed to reload order after save - orderId: $orderId');
                      }
                      
                      // Always clear order after successful save, regardless of reload/print outcome
                      ref.read(orderProvider.notifier).clearOrder();

                      // Auto-sync if online
                      {
                        final isOnline = ref.read(lastKnownOnlineStatusProvider);
                        if (isOnline) {
                          try {
                            final syncManager = ref.read(syncManagerProvider.notifier);
                            await syncManager.autoSyncOrder(orderId);
                            _logger.info('Auto-synced COMPLETED order #$orderId on proceed');
                          } catch (e) {
                            _logger.error('Auto-sync failed on proceed: $e');
                          }
                        }
                      }

                      if (context.mounted) {
                        SnackBarHelper.showSuccessSnackBar(
                          context,
                          ref,
                          'Order saved successfully',
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        SnackBarHelper.showErrorSnackBar(
                          context,
                          ref,
                          'Error: $e',
                        );
                      }
                    } finally {
                      if (mounted) {
                        setState(() => _isSavingOrder = false);
                      }
                    }
                  },
          );
          break;
      }

      if (button != null && shouldShow) {
        buttons.add(button);
      }
    }

    return buttons;
  }

  /// Pay directly with a single ticket (no dialog)
  Future<void> _payDirectly() async {
    if (_isSavingOrder) return;
    var currentOrder = ref.read(orderProvider);
    final orderRepo = ref.read(orderRepositoryProvider);
    final currentUser = ref.read(currentUserProvider);
    final settings = ref.read(settingsProvider);
    final database = ref.read(databaseProvider);
    final session = ref.read(currentSessionProvider);
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);

    if (currentUser == null) return;
    if (session == null) {
      if (mounted) SnackBarHelper.showErrorSnackBar(context, ref, 'No active session');
      return;
    }

    // Validate order has items
    if (currentOrder.items.isEmpty) {
      if (mounted) {
        SnackBarHelper.showErrorSnackBar(
          context,
          ref,
          'Cannot save order with no items',
        );
      }
      return;
    }

    final ok = await _resolveRuleViolations();
    if (!ok) return;
    currentOrder = ref.read(orderProvider);

    // TEMP-TIP-HIDDEN: pre-save tip dialog disabled.
    // if (mounted) {
    //   final withTip = await applyTipIfEnabled(context, ref, currentOrder);
    //   if (withTip.tip != currentOrder.tip) {
    //     ref.read(orderProvider.notifier).setTip(withTip.tip);
    //     currentOrder = ref.read(orderProvider);
    //   }
    // }

    setState(() => _isSavingOrder = true);
    try {
      int orderId;
      // Save or update order first.
      if (currentOrder.isSaved()) {
        _logger.debug('Updating existing order with ${currentOrder.items.length} items');
        await orderRepo.updateOrder(currentOrder);
        orderId = currentOrder.orderId!;
      } else {
        _logger.debug('Creating new order with ${currentOrder.items.length} items');
        orderId = await orderRepo.saveOrder(
          currentOrder,
          currentUser.id,
          status: settings.defaultOrderStatus,
          sessionId: session.id,
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

      // Only pay unpaid items (items not already assigned to a ticket)
      final unpaidItems = reloadedOrder.unpaidItems;
      if (unpaidItems.isEmpty) {
        throw Exception('No unpaid items to pay');
      }

      // Get next ticket number
      final existingTickets = await (database.select(database.tickets)
        ..where((t) => t.orderId.equals(orderId))).get();

      final maxTicketNum = existingTickets.isEmpty
          ? 0
          : existingTickets.map((t) => int.tryParse(t.num) ?? 0).reduce((a, b) => a > b ? a : b);

      final newTicketNum = maxTicketNum + 1;
      final ticketNumStr = newTicketNum.toString().padLeft(4, '0');

      // Calculate total only from unpaid items (apply order-level discount proportionally)
      final unpaidTotal = unpaidItems.fold(0.0, (sum, item) => sum + item.totalPrice);
      final total = reloadedOrder.discountPercentage > 0
          ? unpaidTotal * (1 - reloadedOrder.discountPercentage / 100)
          : unpaidTotal;

      // Insert ticket with default payment method (cash)
      final ticketId = await database.into(database.tickets).insert(
        TicketsCompanion.insert(
          num: ticketNumStr,
          orderId: orderId,
          paymentMethod: TransactionType.cash.value,
          amount: total,
          sessionId: Value(session.id),
          // z_day = the session's opening calendar day (constant across midnight).
          zDay: Value(ref.read(currentZDayProvider)),
          isPaid: const Value(true),
          printCount: const Value(0),
          date: Value(DateTime.now()),
        ),
      );

      // ✅ Update only UNPAID order items (don't touch already-paid items)
      for (final item in unpaidItems) {
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

      // Print receipt using only the unpaid items being paid now
      try {
        final businessName = prefs.getString('business_name') ?? 'THANK YOU FOR YOUR PURCHASE';

        final itemsForPrint = unpaidItems.map((item) {
          return {
            'name': item.displayName,
            'quantity': item.quantity,
            'price': item.totalPrice,
            'components': item.components.map((c) => {'name': c.name, 'quantity': c.quantity}).toList(),
          };
        }).toList();

        final hasTable = reloadedOrder.tableId != null;

        // Print KDS ticket first (for kitchen)
        if (printingService.config.kdsEnabled &&
            printingService.shouldPrint(
              PrintOutput.kds,
              orderType: reloadedOrder.type,
              hasTable: hasTable,
            )) {
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

        // Then print customer receipt + store copy + drawer via orchestrator
        await printingService.printPaymentDocuments(
          ticketId: ticketId,
          ticketNumber: ticketNumStr,
          amount: total,
          paymentMethod: TransactionType.cash.value,
          createdAt: DateTime.now(),
          items: itemsForPrint,
          orderType: reloadedOrder.type,
          hasTable: hasTable,
          orderCode: reloadedOrder.orderCode,
          cashierName: currentUser.firstName,
          storeName: businessName,
          storeAddress: prefs.getString('business_address'),
          storePhone: prefs.getString('business_phone'),
          customerName: reloadedOrder.customerName,
          customerPhone: reloadedOrder.customerPhone,
          deliveryAddress: reloadedOrder.deliveryAddress,
          tableName: reloadedOrder.tableName,
          numberOfPersons: reloadedOrder.numberOfPersons,
        );

        await database.customStatement(
          'UPDATE tickets SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
          [ticketId],
        );
      } catch (e) {
        _logger.error('Print failed: $e');
      }

      // Check if ALL order items are now paid
      final updatedOrder = await orderRepo.getOrderById(orderId);
      final allItemsPaid = updatedOrder != null && updatedOrder.unpaidItems.isEmpty;

      if (allItemsPaid) {
        // Update order status to paid default status (skip internal sync, we handle it below)
        final paidStatus = settings.paidOrderDefaultStatus;
        await orderRepo.updateOrderStatus(orderId, paidStatus, queueSyncOperation: false);

        // Optional: free the table now that the whole order is paid.
        if (settings.autoClearTableAfterPaying &&
            currentOrder.tableId != null) {
          try {
            await orderRepo.clearTableOrder(currentOrder.tableId!);
            ref.invalidate(areaTablesProvider);
          } catch (e) {
            _logger.error('Auto-clear table failed: $e');
          }
        }

        // Auto-sync if online
        final isOnline = ref.read(lastKnownOnlineStatusProvider);
        if (isOnline) {
          try {
            final syncManager = ref.read(syncManagerProvider.notifier);
            await syncManager.autoSyncOrder(orderId);
            _logger.info('Auto-synced $paidStatus order #$orderId after direct payment');
          } catch (e) {
            _logger.error('Auto-sync failed after direct payment: $e');
          }
        }
      }

      if (context.mounted) {
        // Clear order
        ref.read(orderProvider.notifier).clearOrder();

        SnackBarHelper.showSuccessSnackBar(
          context,
          ref,
          'Payment completed! Ticket #$ticketNumStr',
        );
      }
    } catch (e) {
      _logger.error('Direct payment failed: $e');
      if (context.mounted) {
        SnackBarHelper.showErrorSnackBar(
          context,
          ref,
          'Payment failed: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingOrder = false);
      }
    }
  }

  /// Show payment dialog for split payment
  Future<void> _showPaymentDialog() async {
    if (_isSavingOrder) return;
    var currentOrder = ref.read(orderProvider);
    final orderRepo = ref.read(orderRepositoryProvider);
    final currentUser = ref.read(currentUserProvider);
    final settings = ref.read(settingsProvider);

    if (currentUser == null) return;
    final session = ref.read(currentSessionProvider);
    if (session == null) {
      if (mounted) SnackBarHelper.showErrorSnackBar(context, ref, 'No active session');
      return;
    }

    final ok = await _resolveRuleViolations();
    if (!ok) return;
    currentOrder = ref.read(orderProvider);

    // TEMP-TIP-HIDDEN: pre-save tip dialog disabled.
    // if (mounted) {
    //   final withTip = await applyTipIfEnabled(context, ref, currentOrder);
    //   if (withTip.tip != currentOrder.tip) {
    //     ref.read(orderProvider.notifier).setTip(withTip.tip);
    //     currentOrder = ref.read(orderProvider);
    //   }
    // }

    setState(() => _isSavingOrder = true);
    try {
      int orderId;
      // Save or update order first.
      if (currentOrder.isSaved()) {
        await orderRepo.updateOrder(currentOrder);
        orderId = currentOrder.orderId!;
      } else {
        orderId = await orderRepo.saveOrder(
          currentOrder,
          currentUser.id,
          status: settings.defaultOrderStatus,
          sessionId: session.id,
        );
        if (currentOrder.tableId != null) {
          await orderRepo.setTableOrderId(currentOrder.tableId!, orderId);
        }
      }

      // Reload the order from database to get updated IDs (and the tip
      // we just persisted).
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
          // Payment completed - order already marked COMPLETED and synced by PaymentScreen
          // Clear order
          ref.read(orderProvider.notifier).clearOrder();
          SnackBarHelper.showSuccessSnackBar(
            context,
            ref,
            'Payment completed successfully',
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
        SnackBarHelper.showErrorSnackBar(
          context,
          ref,
          'Error: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingOrder = false);
      }
    }
  }

  /// Walk the cashier through any rule violations by **directly opening the
  /// matching sub-dialog** (table / waiter / customer / address) — no
  /// intermediate "missing required field" alert. After each pick we
  /// re-validate; we bail out only if the cashier cancels a picker without
  /// supplying a value, so they never get trapped in an infinite re-prompt.
  Future<bool> _resolveRuleViolations() async {
    final settings = ref.read(settingsProvider);
    while (true) {
      final order = ref.read(orderProvider);
      final violation = validateOrderRules(order, settings);
      if (violation == null) return true;
      final picked = await _runRuleFix(violation.fix);
      if (!picked) return false; // cancelled the picker — abort save/pay
    }
  }

  /// Opens the fix dialog for [fix] and returns `true` only if the cashier
  /// actually picked / typed a value. Closing the picker without a selection
  /// returns `false`, which lets the outer loop bail out instead of looping
  /// forever on the same violated rule.
  Future<bool> _runRuleFix(OrderRuleFix fix) {
    switch (fix) {
      case OrderRuleFix.setTable:
        return _openTablePickerForFix();
      case OrderRuleFix.setWaiter:
        return _openWaiterPickerForFix();
      case OrderRuleFix.setCustomer:
        return _openCustomerPickerForFix();
      case OrderRuleFix.setDeliveryAddress:
        return _runDeliveryAddressFix();
    }
  }

  Future<bool> _openTablePickerForFix() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const TableSelectionDialog(),
    );
    if (result == null || result['id'] == null) return false;
    final tableId = result['id'] as int;
    final tableName = result['name'] as String;
    final existingOrder = result['existingOrder'] as CurrentOrder?;

    if (existingOrder != null) {
      // Reuse the same conflict prompt the normal table-pick flow uses.
      final hasItems = ref.read(orderProvider).items.isNotEmpty;
      if (hasItems && context.mounted) {
        final l10n = AppLocalizations.of(context)!;
        final confirmed = await _confirmDiscardCurrentForTableOrder(
          context,
          tableName: tableName,
          existingOrder: existingOrder,
          l10n: l10n,
        );
        if (confirmed != true) return false;
      }
      ref.read(orderProvider.notifier).loadOrder(existingOrder);
    } else {
      final hasItems = ref.read(orderProvider).items.isNotEmpty;
      if (hasItems) {
        ref.read(orderProvider.notifier).updateTable(tableId, tableName);
      } else {
        ref.read(orderProvider.notifier).setTable(tableId, tableName);
      }
      ref.read(orderProvider.notifier).setOrderType('DINE_IN');
    }
    return true;
  }

  Future<bool> _openWaiterPickerForFix() async {
    final currentOrder = ref.read(orderProvider);
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => WaiterSelectionDialog(
        currentTableId: currentOrder.tableId,
        currentWaiterId: currentOrder.waiterId,
      ),
    );
    if (result == null) return false;
    if (result['action'] == 'select') {
      ref.read(orderProvider.notifier).setWaiter(
            result['waiterId'],
            result['waiterName'],
          );
      return true;
    }
    return false;
  }

  Future<bool> _openCustomerPickerForFix() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const CustomerSelectionDialog(),
    );
    if (result == null || result['id'] == null) return false;
    ref.read(orderProvider.notifier).setCustomer(
          result['id'],
          result['name'],
          customerPhone: result['phone'],
        );
    return true;
  }

  /// Wrap [_showDeliveryAddressDialog] to report whether the cashier saved a
  /// non-empty address. The existing method only mutates state on Save, so we
  /// snapshot the address before and after to detect a real change.
  Future<bool> _runDeliveryAddressFix() async {
    final before = ref.read(orderProvider).deliveryAddress ?? '';
    await _showDeliveryAddressDialog(context);
    final after = ref.read(orderProvider).deliveryAddress ?? '';
    return after.trim().isNotEmpty && after != before
        ? true
        : after.trim().isNotEmpty;
  }

  /// Prompt the cashier before throwing away their current cart to load a
  /// table's existing order. Returns `true` only if the user confirms.
  Future<bool?> _confirmDiscardCurrentForTableOrder(
    BuildContext context, {
    required String tableName,
    required CurrentOrder existingOrder,
    required AppLocalizations l10n,
  }) {
    final code = existingOrder.orderCode ??
        (existingOrder.orderId != null ? '#${existingOrder.orderId}' : '?');
    final body = l10n
        .translate('table_has_open_order_body')
        .replaceAll('{table}', tableName)
        .replaceAll('{code}', code)
        .replaceAll('{count}', '${existingOrder.items.length}');
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 8),
            Expanded(
                child: Text(l10n.translate('table_has_open_order_title'))),
          ],
        ),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.translate('continue_with_table_order')),
          ),
        ],
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

/// A single-line label that shows its text in full whenever it fits, and
/// gently scrolls it back and forth (marquee) when it's too wide for the
/// available space — so action-button labels like a long table name stay
/// readable on small screens instead of being hidden or cropped.
class _MarqueeLabel extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeLabel({required this.text, required this.style});

  @override
  State<_MarqueeLabel> createState() => _MarqueeLabelState();
}

class _MarqueeLabelState extends State<_MarqueeLabel>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..addListener(_onTick);
  }

  void _onTick() {
    if (!_scroll.hasClients) return;
    final max = _scroll.position.maxScrollExtent;
    if (max <= 0) return;
    // easeInOut gives a slow start/stop at each end that reads as a short pause.
    _scroll.jumpTo(max * Curves.easeInOut.transform(_ctrl.value));
  }

  @override
  void didUpdateWidget(covariant _MarqueeLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Label text changed (e.g. table assigned/cleared) — restart from the head
    // so the new text isn't left mid-scroll.
    if (oldWidget.text != widget.text && _scroll.hasClients) {
      _scroll.jumpTo(0);
      _ctrl.reset();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final tp = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: dir,
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final fits = tp.width <= constraints.maxWidth + 0.5;

        if (fits) {
          if (_ctrl.isAnimating) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _ctrl.isAnimating) _ctrl.stop();
            });
          }
          return Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: widget.style,
          );
        }

        // Overflows: kick off the ping-pong loop once we have a scroll extent.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_ctrl.isAnimating) {
            _ctrl.repeat(reverse: true);
          }
        });

        return SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            style: widget.style,
          ),
        );
      },
    );
  }
}

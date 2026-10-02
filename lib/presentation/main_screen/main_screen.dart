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
import '../../domain/models/external_order_models.dart';
import '../../services/permission_service.dart';
import '../../services/printing_service.dart';
import '../../services/sound_service.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/app_localizations.dart';
import '../order_confirmation/order_confirmation_screen.dart';
import '../paymen_screen/payment_screen.dart';
// TEMP-TIP-HIDDEN: pourboire flow disabled — restore this import together
// with the four commented-out blocks below (`case 'tip'`, the two payment
// helpers, the table-pay branch).
// import '../widgets/tip_flow.dart';
import '../widgets/print_status_indicator.dart';
import '../widgets/category_selector.dart';
import '../widgets/category_grid.dart';
import '../widgets/commercial_selection_dialog.dart';
import '../widgets/customer_selection_dialog.dart';
import '../widgets/daily_summary_dialog.dart';
import '../widgets/manual_discount_dialog.dart';
import '../widgets/print_options_dialog.dart';
import '../widgets/quick_product_dialog.dart';
import '../widgets/product_grid.dart';
import '../widgets/order_panel.dart';
import '../widgets/serial_conflict_alert.dart';
import '../widgets/table_selection_dialog.dart';
import '../widgets/waiter_selection_dialog.dart';
import '../widgets/top_bar.dart';
import '../../utils/order_permissions.dart';
import '../../utils/order_validation.dart';
import '../../utils/snackbar_helper.dart';
import '../../services/waiter_call_service.dart' show WaiterCall, waiterCallAckProvider;
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
import '../widgets/adaptive_text_field.dart';
import '../../core/theme/app_theme.dart';

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

  /// Guard against a second dialog stacking on the first: the stream fires
  /// again the moment the rows are acknowledged.
  bool _serialConflictShowing = false;

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

    // Request focus for barcode scanner — but never over a modal. This node
    // wraps the whole scaffold and swallows key events into the scan buffer, so
    // holding focus while a dialog is open sends the cashier's typing to the
    // barcode parser instead of the field in front of them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) return;
      _focusNode.requestFocus();
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
      // Match a scanned/typed code against barcode OR reference (SKU).
      final matches = await (database.select(database.products)
        ..where((tbl) =>
            tbl.barcode.equals(barcode) | tbl.reference.equals(barcode))
        ..where((tbl) => tbl.isActive.equals(true)))
        .get();
      // Prefer an exact barcode hit if a reference on another product collides.
      final product = matches.isEmpty
          ? null
          : matches.firstWhere((p) => p.barcode == barcode,
              orElse: () => matches.first);

      if (product != null) {
        // Adding to a SAVED order requires the add-item permission.
        if (!mounted) return;
        if (!ensureCanAddItemToOrder(context, ref)) return;
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

      } else {
        _logger.warning('Barcode lookup: no active product found for barcode "$barcode"');
        if (!mounted) return;

        // Scan-to-create: the cashier is holding an item the catalogue does not
        // know. Offering to create it here — barcode already filled — turns a
        // dead end into one gesture. Gated: without pos:catalog this stays the
        // plain "not found" it always was.
        final canCreate = ref
            .read(permissionServiceProvider)
            .hasPermission(Permissions.catalog);
        if (!canCreate) {
          SnackBarHelper.warning(
            context,
            'Product with barcode $barcode not found',
            duration: const Duration(seconds: 2),
          );
          return;
        }

        final l10n = AppLocalizations.of(context)!;
        final create = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.qr_code_scanner, size: 36),
            title: Text(l10n.translate('unknown_barcode')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(barcode,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 8),
                Text(l10n.translate('create_product_with_barcode')),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.translate('cancel')),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                icon: const Icon(Icons.add),
                label: Text(l10n.translate('create')),
              ),
            ],
          ),
        );
        if (create != true || !mounted) return;

        final product = await showQuickProductDialog(
          context: context,
          ref: ref,
          initialBarcode: barcode,
        );
        // Straight onto the open ticket: creating it and then making the
        // cashier find it again would defeat the point of scanning. The
        // catalogue entry stands either way — only the add is gated, and it
        // says so, so a scan never ends in silence.
        if (product != null && mounted) {
          if (canAddItemToCurrentOrder(ref)) {
            _addProductToOrder(product);
          } else {
            SnackBarHelper.error(
              context,
              AppLocalizations.of(context)!
                  .translate('product_created_not_added'),
            );
          }
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

  /// Add a freshly created product to the open ticket.
  void _addProductToOrder(Product product) {
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

  }

  void _startAutoCloseTimer() {
    _autoCloseTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;

      // No day-rollover close here: a Z is never closed by the clock while
      // the till is in use. It stays open past midnight until someone closes
      // it.
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
      await sessionService.endSession(sessionId: session.id, autoClosed: true);
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
        SnackBarHelper.showToast(l10n.translate(reasonKey), kind: ToastKind.warning, duration: const Duration(seconds: 5));
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

    // The SSE connection is owned by main.dart now, so it survives navigating
    // away from the till. Nothing to activate here.

    // Force-logout (refresh token rejected, 4xx on /pos/refresh) is now handled
    // by the app-wide obligatory re-auth overlay (main.dart / reauthProvider),
    // which re-authenticates in place instead of kicking to the login screen
    // and losing the cart. Nothing to do here.

    // A unit this till sold that another till got first. Raised here rather
    // than swallowed into a log, because the shop-floor problem it describes —
    // two customers holding paperwork for one box — is not one the software
    // can settle on its own.
    ref.listen<AsyncValue<List<SerialConflict>>>(
        unacknowledgedSerialConflictsProvider, (_, next) {
      final pending = next.valueOrNull ?? const <SerialConflict>[];
      if (pending.isEmpty || _serialConflictShowing) return;
      _serialConflictShowing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await showSerialConflictAlert(context, ref, pending);
        if (mounted) _serialConflictShowing = false;
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

    // A waiter dismissed a call on their phone. Worth a line on screen: the
    // cashier's alternative to knowing is ringing again, which is exactly the
    // nuisance the acknowledgement exists to prevent.
    ref.listen<AsyncValue<WaiterCall>>(waiterCallAckProvider, (_, next) {
      final call = next.valueOrNull;
      if (call == null || !mounted) return;
      SnackBarHelper.info(
        context,
        l10n
            .translate('call_waiter_acknowledged')
            .replaceAll('{0}', call.waiterName),
      );
    });

    // Show SnackBar when admin pushes a DISPLAY_ALERT command
    ref.listen<String?>(sseAlertProvider, (_, message) {
      if (message == null || !mounted) return;
      SnackBarHelper.showToast(message, kind: ToastKind.warning, duration: const Duration(seconds: 6), action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () =>
                ref.read(sseAlertProvider.notifier).state = null,
          ));
      // Clear after showing so re-watch doesn't retrigger
      ref.read(sseAlertProvider.notifier).state = null;
    });

    // A queued order was cancelled on the platform. Two very different cases:
    // if it was still pending, a toast is enough — nothing was started. If it
    // was already CONFIRMED, the kitchen may be cooking food nobody will
    // collect, so it gets a blocking dialog and the alert sound. That is worth
    // interrupting someone for; a toast at the bottom of a busy screen is not.
    ref.listen<({String? orderCode, String? reason, bool wasConfirmed})?>(
        sseOrderCancelledProvider, (_, cancelled) {
      if (cancelled == null || !mounted) return;
      ref.read(sseOrderCancelledProvider.notifier).state = null;

      final l10n = AppLocalizations.of(context);
      final code = cancelled.orderCode ?? '';

      if (!cancelled.wasConfirmed) {
        SnackBarHelper.warning(
          context,
          '${l10n?.translate('external_order_cancelled') ?? 'Online order cancelled'} $code',
        );
        return;
      }

      ref.read(soundServiceProvider).newOrderAlert();
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.cancel_schedule_send,
              color: Theme.of(ctx).colorScheme.error, size: 40),
          title: Text(l10n?.translate('external_order_cancelled') ??
              'Online order cancelled'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (code.isNotEmpty)
                Text(code,
                    style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
              const SizedBox(height: 8),
              Text(l10n?.translate('external_order_cancelled_confirmed') ??
                  'This order was already accepted. Stop preparing it and check '
                      'with the kitchen.'),
              if ((cancelled.reason ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(cancelled.reason!,
                    style: TextStyle(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n?.translate('ok') ?? 'OK'),
            ),
          ],
        ),
      );
    });

    // Chime + toast when an online order lands. Until now `sseNewOrderProvider`
    // was set by the SSE handler and read by nobody, so an order could sit in
    // the queue unnoticed until someone happened to open the Orders screen.
    // This listener is on MainScreen rather than on the external-orders tab on
    // purpose: the whole point is to reach a cashier who is NOT looking at that
    // tab. MainScreen stays mounted under pushed routes, so the toast still
    // surfaces (via the root ScaffoldMessenger) while another screen is open.
    ref.listen<Map<String, dynamic>?>(sseNewOrderProvider, (_, payload) {
      if (payload == null || !mounted) return;
      ref.read(sseNewOrderProvider.notifier).state = null;

      ref.read(soundServiceProvider).newOrderAlert();

      ExternalQueueItem? item;
      try {
        item = ExternalQueueItem.fromJson(payload);
      } catch (e) {
        // A payload shape we can't read is still an order that arrived — chime
        // and toast generically rather than swallowing the event.
        Logger.instance.error('new-order toast: unreadable payload: $e');
      }

      final l10n = AppLocalizations.of(context);
      final title = l10n?.translate('new_order') ?? 'New Order';
      final currency = ref.read(currencySymbolProvider);

      final details = <String>[];
      if (item != null) {
        details.add(item.sourceLabel);
        details.add(item.orderCode);
        final count = item.order.items.length;
        if (count > 0) details.add('$count×');
        final total = item.order.total;
        if (total != null && total > 0) {
          details.add(CurrencyFormatter.formatWithCurrency(total, currency));
        }
      }

      final unmapped = item?.order.hasUnmappedItems ?? false;

      SnackBarHelper.showToast(
          [
            if (details.isNotEmpty) details.join('  ·  '),
            // Surfaced here because it decides what the cashier can do next:
            // an unmapped line blocks confirm, so sending them to the tab
            // expecting a one-tap accept would waste the trip.
            if (unmapped)
              l10n?.translate('unmapped_items_blocked') ??
                  'Some items are not mapped — confirm is blocked',
          ].join('\n'),
          title: title,
          kind: unmapped ? ToastKind.warning : ToastKind.info,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(
            label: l10n?.translate('view') ?? 'View',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  // Tab 1 = the online queue on the confirm screen, where the
                  // queue now lives, so "View" lands on the order that just
                  // arrived with its Confirm/Cancel actions to hand.
                  builder: (_) => const OrderConfirmationScreen(),
                ),
              );
            },
          ),
        );
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

    // The back tile does the bar's whole job in full-page mode — return to the
    // categories — so keeping both is two controls for one action and 70px of
    // screen for nothing. The calculator that used to live in the bar moved to
    // the top bar, so nothing is lost with it.
    //
    // Gone at BOTH levels, not just inside a category: on the category page
    // the bar was a button reading "All Categories" directly above a grid of
    // categories, which is a label for what the reader is already looking at.
    final hideCategoryBar = ref.watch(categoryBarHiddenProvider);

    final mainContent = Expanded(
      flex: 2,
      child: Column(
        children: [
          if (!hideCategoryBar) const CategorySelector(),
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
        // Belt and braces with the focus guard above: even if this node somehow
        // holds focus while a dialog is open, the scan buffer must not eat the
        // keystrokes meant for that dialog's fields.
        final route = ModalRoute.of(context);
        if (route != null && !route.isCurrent) return KeyEventResult.ignored;
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      // The Row is unbounded inside the scroll view, so
                      // mainAxisAlignment alone does nothing. Forcing it to at
                      // least the viewport width gives the alignment something
                      // to work against while still letting it scroll once the
                      // buttons overflow.
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: switch (settings.actionButtonAlignment) {
                            ActionButtonAlignment.left => MainAxisAlignment.start,
                            ActionButtonAlignment.center => MainAxisAlignment.center,
                            ActionButtonAlignment.right => MainAxisAlignment.end,
                          },
                          children: _buildOrderedActionButtons(context, ref, currentOrder, settings, l10n),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          // Print status — a corner pill, not the full-screen scrim this used
          // to be. Prints no longer block the cashier's tap, so a background
          // job must not black out the till to report on itself. Print
          // FAILURES still stick here until acknowledged, which is what stops
          // a dead printer from being silent now that nothing waits on it.
          const PrintStatusIndicator(),
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
        shape: RoundedRectangleBorder(borderRadius: AppTheme.brLg),
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
                            borderRadius: AppTheme.brLg),
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

  /// Touch-friendly delivery details — address plus the delivery fee (uses the
  /// on-screen keyboard).
  ///
  /// The fee field distinguishes empty from zero on purpose: leaving it blank
  /// means "no delivery fee recorded", typing `0` means "delivery is free".
  /// See [CurrentOrder.deliveryFee].
  Future<void> _showDeliveryAddressDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final order = ref.read(orderProvider);
    final addressController =
        TextEditingController(text: order.deliveryAddress ?? '');
    final feeController = TextEditingController(
      text: order.hasDeliveryFee ? _trimAmount(order.deliveryFee!) : '',
    );
    final currency = ref.read(currencySymbolProvider);

    // The shop's own one-tap fees. Most deliveries cost one of two or three
    // amounts, and typing the same number every time is the slow part.
    final feePresets = ref.read(settingsProvider).deliveryFeePresets;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final media = MediaQuery.of(ctx).size;
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(
              children: [
                const Icon(Icons.delivery_dining, color: Colors.blue, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(l10n.translate('delivery_details'),
                      style: const TextStyle(fontSize: 22)),
                ),
              ],
            ),
            content: SizedBox(
              width: media.width * 0.72 > 820 ? 820 : media.width * 0.72,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdaptiveKeyboardTextField(
                      controller: addressController,
                      autofocus: true,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        labelText: l10n.translate('delivery_address'),
                        hintText: l10n.translate('enter_delivery_address'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AdaptiveKeyboardTextField(
                      controller: feeController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        labelText:
                            '${l10n.translate('delivery_fee')} ($currency)',
                        hintText: l10n.translate('delivery_fee_hint'),
                        helperText: l10n.translate('delivery_fee_helper'),
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (_) => setLocal(() {}),
                    ),
                    if (feePresets.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final fee in feePresets)
                            ChoiceChip(
                              label: Text(
                                '${_trimAmount(fee)} $currency',
                                style: const TextStyle(fontSize: 17),
                              ),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              // A preset REPLACES the fee rather than appending
                              // to it — unlike a note, two fees are not a fee.
                              selected: feeController.text.trim() ==
                                  _trimAmount(fee),
                              onSelected: (_) {
                                feeController.text = _trimAmount(fee);
                                feeController.selection =
                                    TextSelection.collapsed(
                                        offset: feeController.text.length);
                                setLocal(() {});
                              },
                            ),
                          if (feeController.text.trim().isNotEmpty)
                            ActionChip(
                              avatar: const Icon(Icons.close, size: 18),
                              label: Text(l10n.translate('clear'),
                                  style: const TextStyle(fontSize: 17)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              onPressed: () {
                                feeController.clear();
                                setLocal(() {});
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    textStyle: const TextStyle(fontSize: 17)),
                child: Text(l10n.translate('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 16),
                    textStyle: const TextStyle(fontSize: 17)),
                child: Text(l10n.translate('save')),
              ),
            ],
          );
        });
      },
    );

    if (saved != true) return;

    final notifier = ref.read(orderProvider.notifier);
    notifier.setDeliveryAddress(addressController.text.trim());

    // Blank (or unparseable) clears the fee rather than storing 0 — the two
    // states carry different meanings all the way to the server.
    final raw = feeController.text.trim().replaceAll(',', '.');
    notifier.setDeliveryFee(raw.isEmpty ? null : double.tryParse(raw));
  }

  /// Money as the cashier would type it: drop a trailing `.00` so reopening
  /// the dialog shows `15`, not `15.00`.
  static String _trimAmount(double value) {
    final fixed = value.toStringAsFixed(2);
    return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
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
                side: BorderSide(color: color ?? Theme.of(context).colorScheme.outline),
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
                  ? Theme.of(context).colorScheme.onSurfaceVariant // Disabled look when table is selected
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

                  // Explicit transfer: the cashier armed the Transfer button
                  // in the picker and then chose a free table. The repository
                  // moves both table pointers and the order's own tableId in
                  // one transaction, and marks the order unsynced so the move
                  // reaches the backend.
                  if (action == 'transfer') {
                    final oldTableId = result['oldTableId'] as int?;
                    final orderId = currentOrder.orderId;
                    if (oldTableId != null &&
                        orderId != null &&
                        tableId != null) {
                      await ref
                          .read(orderRepositoryProvider)
                          .transferOrderToTable(orderId, oldTableId, tableId);
                      ref
                          .read(orderProvider.notifier)
                          .updateTable(tableId, tableName);
                      ref.invalidate(areaTablesProvider);
                      if (context.mounted) {
                        SnackBarHelper.showSuccessSnackBar(
                          context,
                          ref,
                          AppLocalizations.of(context)!
                              .translate('order_transferred')
                              .replaceAll('{table}', '$tableName'),
                        );
                      }
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
                    // The result is not inspected: PaymentScreen already
                    // committed the payment and cleared the order, and the
                    // confirmation snackbar this used to show is gone.
                    await showDialog<bool>(
                      context: context,
                      builder: (context) => PaymentScreen(order: order),
                    );
                    return;
                  }

                  if (action == 'cleared') {
                    return;
                  }

                  if (action == 'addItems') {
                    if (existingOrder != null) {
                      ref.read(orderProvider.notifier).loadOrder(existingOrder);
                    }
                    return;
                  }

                  final hasItems =
                      ref.read(orderProvider).hasUnsavedChanges;

                  if (existingOrder != null) {
                    // Table already has an open order. Ask only when the cart
                    // holds work that switching would actually lose — a saved
                    // order stays on its own table either way.
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

        // Coupon button hidden. Its handler was an empty `onPressed: () {}` —
        // it drew a button that did nothing at all, which is worse than not
        // being there. With no case here `button` stays null and the loop
        // below skips the key, so a saved button order containing 'coupon'
        // simply renders nothing. Uncomment to bring it back, and give it a
        // handler before you do.
        //
        // case 'coupon':
        //   shouldShow = settings.showCouponButton;
        //   if (shouldShow) {
        //     button = _buildActionButton(
        //       icon: Icons.discount,
        //       label: l10n.translate('coupon'),
        //       onPressed: () {},
        //     );
        //   }
        //   break;

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
                          // The base the percentage multiplies, so the dialog
                          // can convert an amount the cashier types into the
                          // percentage the order actually stores.
                          orderTotal: currentOrder.totalBeforeDiscount,
                          currencySymbol:
                              ref.read(currencyFormatterProvider).symbol,
                          // The dialog's field is "reason for discount" — it
                          // used to be stored in `order.note`, which the KDS
                          // and the kitchen ticket read, so a discount wiped
                          // the kitchen instruction. It has its own field now.
                          currentNote: currentOrder.discountReason,
                        ),
                      );
                      if (result != null) {
                        final percentage = result['percentage'] as double? ?? 0.0;
                        final reason = result['note'] as String?;
                        ref.read(orderProvider.notifier).setDiscountPercentage(percentage);
                        ref.read(orderProvider.notifier).setDiscountReason(reason);
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

                      if (currentUser == null) return;
                      if (printSession == null) {
                        if (context.mounted) SnackBarHelper.showErrorSnackBar(context, ref, 'No active session');
                        return;
                      }

                      // Printing PERSISTS first, on update as well as on
                      // insert. It used to save only a brand-new order and
                      // print `currentOrder` straight from memory for one that
                      // already existed, so items added since the last save
                      // were printed but never written. Two things went wrong
                      // with that: the added lines were lost on the next
                      // reload, and — because an unsaved line has no id —
                      // `_markItemsAsPrinted` skipped them, so the kitchen and
                      // the additions-only order ticket both re-sent them the
                      // next time round.
                      //
                      // On a waiter's order the cashier may still have set a
                      // remise or a note, and Print is where that has to stick:
                      // this used to skip the save entirely, so the discount
                      // showed on screen, never reached the database, and the
                      // ticket printed at full price. Their LINES are still off
                      // limits — `headerOnly` is what enforces that, in the
                      // repository, rather than trusting the panel.
                      final mayEditLines = canEditWaiterOrder(ref);

                      int? orderId = currentOrder.orderId;
                      try {
                        if (currentOrder.isSaved()) {
                          _logger.debug(
                              'Print: Updating order $orderId with ${currentOrder.items.length} items'
                              '${mayEditLines ? '' : ' (header only — waiter order)'}');
                          await orderRepo.updateOrder(currentOrder,
                              headerOnly: !mayEditLines);
                        } else {
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

                      if (context.mounted) {
                        // Always print the reloaded row, never the in-memory
                        // cart: the reload is what gives every line its
                        // database id and its true printed quantities, which
                        // is what the delta filter and the printed-mark both
                        // run on.
                        final orderToPrint =
                            orderId == null ? null : await orderRepo.getOrderById(orderId);
                        if (orderToPrint != null) {
                          ref.read(orderProvider.notifier).loadOrder(orderToPrint);
                        }

                        if (orderToPrint != null) {
                          // Identity deliberately not passed: the printing
                          // service resolves the store name, address and phone
                          // from settings. This site used to pass an EMPTY
                          // store name, which is not null, so the header
                          // printed a blank line and the shop's name never
                          // appeared on a button-printed ticket while the
                          // automatic one carried it.
                          final printed = await showPrintOptionsDialog(
                            context,
                            order: orderToPrint,
                            cashierName: currentUser.firstName,
                          );

                          // Reload once the print has landed. Printing stamps
                          // kdsPrintedQuantity / orderTicketPrintedQuantity on
                          // the rows it actually sent, and updateOrder
                          // re-inserts every unpaid line FROM MEMORY — so a
                          // cart still holding the pre-print zeros writes them
                          // straight back over the stamps, and the next round
                          // re-sends the kitchen everything it already has.
                          if (printed == true && context.mounted && orderId != null) {
                            final refreshed = await orderRepo.getOrderById(orderId);
                            if (refreshed != null) {
                              ref.read(orderProvider.notifier).loadOrder(refreshed);
                            }
                          }
                        }
                      }
                    },
            );
          }
          break;

        case 'cancelOrder':
          shouldShow = settings.showCancelOrderButton &&
              permissionService.hasPermission(Permissions.ordersCancel);
          if (shouldShow) {
            // Only ever enabled for an order that has been saved. Cancelling
            // an unsaved basket is what the clear button is for, and there is
            // nothing on the server to cancel.
            final canCancel = currentOrder.isSaved() &&
                currentOrder.status != 'CANCELED' &&
                !_isSavingOrder;
            button = _buildActionButton(
              icon: Icons.cancel_outlined,
              label: l10n.translate('cancel_order'),
              color: canCancel ? Colors.red[700] : null,
              onPressed: canCancel ? _cancelCurrentOrder : null,
            );
          }
          break;

        case 'cashDrawer':
          shouldShow = settings.showCashDrawerButton;
          if (shouldShow) {
            button = _buildActionButton(
              icon: Icons.point_of_sale,
              label: l10n.translate('open_drawer_now_action'),
              color: Colors.brown,
              // Independent of the auto-open-on-payment setting: that one is
              // about what happens when a payment lands, this is the cashier
              // needing the drawer open between sales — for change, a float
              // top-up, or a spot count.
              onPressed: () async {
                final ok = await ref
                    .read(printingServiceProvider)
                    .kickCashDrawer();
                if (!context.mounted) return;
                // Only the failure is worth a snackbar: a drawer that opened
                // announced itself, one that stayed shut needs saying.
                if (ok) return;
                SnackBarHelper.showToast(l10n.translate('drawer_open_failed'),
                    kind: ToastKind.error);
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
                            SnackBarHelper.showToast('$e', kind: ToastKind.error);
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
              // A tap does whatever settings say. A long press always opens
              // the payment screen with the ticket-division grid forced
              // open, so a cashier can divide the order into tickets before
              // anything is paid — independent of payButtonAction, which
              // only governs what a plain tap does.
              onPressed: (currentOrder.items.isEmpty || _isSavingOrder)
                  ? null
                  : (settings.payButtonAction == PayButtonAction.quickCash
                      ? _payDirectly
                      : _showPaymentDialog),
              onLongPress: (currentOrder.items.isEmpty || _isSavingOrder)
                  ? null
                  : () => _showPaymentDialog(forceSplitOpen: true),
            );
          }
          break;

        case 'proceed':
          // Primary button, but now hideable from settings like the others.
          shouldShow = settings.showProceedButton;
          // New order needs orders:create; persisting a saved order is allowed if
          // the user can make any kind of edit (add/remove/modify) or has update.
          final canProceed = currentOrder.isSaved()
              // A waiter's order is NOT off limits here: settling it is exactly
              // what the cashier is for, and the remise they just applied has
              // to persist. The lines are protected by `headerOnly` inside
              // updateOrder, so satisfying the item guards line-by-line can no
              // longer write food back through this path.
              ? permissionService.hasAnyPermission([
                  Permissions.ordersUpdate,
                  Permissions.ordersItemAdd,
                  Permissions.ordersItemRemove,
                  Permissions.ordersItemModify,
                ])
              : permissionService.hasPermission(Permissions.ordersCreate);
          // Long-press additionally opens the payment screen (with the
          // ticket-division grid forced open) — same downstream action the
          // Pay button gates behind ticketsCreate, so the long-press on
          // Proceed can't reach it when Pay itself would refuse to.
          final canOpenPaymentFromProceed =
              permissionService.hasPermission(Permissions.ticketsCreate);
          button = _buildActionButton(
            icon: Icons.check_circle,
            label: l10n.translate('proceed'),
            isPrimary: true,
            onLongPress: (currentOrder.items.isEmpty ||
                    !canProceed ||
                    !canOpenPaymentFromProceed ||
                    _isSavingOrder)
                ? null
                : () => _showPaymentDialog(
                      forceSplitOpen: true,
                      // Stands in for a Continue, so it owes the kitchen its
                      // ticket — see [_firePostSavePrints].
                      printOnSave: true,
                    ),
            onPressed:
                (currentOrder.items.isEmpty || !canProceed || _isSavingOrder)
                    ? null
                    : () async {
                    if (_isSavingOrder) return;
                    final orderRepo = ref.read(orderRepositoryProvider);
                    final currentUser = ref.read(currentUserProvider);
                    final settings = ref.read(settingsProvider);
                    // Printing now goes through _firePostSavePrints, which
                    // reads the service itself.

                    if (currentUser == null) return;
                    final session = ref.read(currentSessionProvider);
                    if (session == null) {
                      // Surface the reason instead of silently doing nothing —
                      // otherwise the cashier thinks the order saved when it
                      // didn't. No session ⇒ no order (would be orphaned).
                      if (mounted) {
                        SnackBarHelper.showErrorSnackBar(
                            context, ref, 'No active session — open a session first');
                      }
                      return;
                    }

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
                        // Lines stay the waiter's; the header is the cashier's.
                        await orderRepo.updateOrder(currentOrder,
                            headerOnly: !canEditWaiterOrder(ref));
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

                      // The order is committed and durable at this point, so
                      // the till is free. Clearing HERE — before the prints —
                      // is the whole point: printing used to be awaited first,
                      // which left the cart on screen for the duration of the
                      // order slip plus every KDS station ticket.
                      ref.read(orderProvider.notifier).clearOrder();

                      // Prints are detached and self-serialising: PrintingService
                      // queues them behind anything a waiter is already printing.
                      // Failures are logged there and cannot lose kitchen work —
                      // items are only marked printed on a confirmed success, so
                      // KdsPrintMode.modificationsOnly re-sends them next time.
                      final reloadedOrder = await orderRepo.getOrderById(orderId);

                      if (reloadedOrder != null) {
                        unawaited(_firePostSavePrints(reloadedOrder));
                      } else {
                        _logger.error('Failed to reload order after save - orderId: $orderId');
                      }

                      // NOTE: no autoSyncOrder here. OrderRepository.saveOrder /
                      // updateOrder already push this order (detached), and the
                      // isSynced=false sweep is the backstop either way — this
                      // call was a second, awaited copy of the same two HTTP
                      // round-trips.

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
        // Lines stay the waiter's; the header is the cashier's.
        await orderRepo.updateOrder(currentOrder,
            headerOnly: !canEditWaiterOrder(ref));
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

      // Insert ticket + mark the unpaid items PAID atomically — mirrors
      // payment_screen._processPayment. Without the transaction, a failure
      // between the ticket insert and the item updates would leave a paid
      // ticket with still-PENDING items: the order reads as paid on the ticket
      // but unpaid on the lines, so settleOrderAndFreeTable never completes it
      // and the table is never freed.
      final zDay = ref.read(currentZDayProvider);
      late final int ticketId;
      await database.transaction(() async {
        ticketId = await database.into(database.tickets).insert(
          TicketsCompanion.insert(
            num: ticketNumStr,
            orderId: orderId,
            paymentMethod: TransactionType.cash.value,
            amount: total,
            sessionId: Value(session.id),
            // z_day = the session's opening calendar day (constant across midnight).
            zDay: Value(zDay),
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
      });

      // Everything below builds the paperwork for the items just paid. All of
      // it is read off local state NOW and printed DETACHED further down, so
      // the cashier never waits on a printer to get the till back.
      final businessName = prefs.getString('business_name');
      final storeAddress = prefs.getString('business_address');
      final storePhone = prefs.getString('business_phone');

      final itemsForPrint = unpaidItems.map((item) {
        return {
          'name': item.displayName,
          'quantity': item.quantity,
          'price': item.totalPrice,
          'components': item.components.map((c) => {'name': c.name, 'quantity': c.quantity}).toList(),
        };
      }).toList();

      final hasTable = reloadedOrder.tableId != null;
      final feeForThisTicket = PrintingService.feeForThisTicket(
        reloadedOrder.deliveryFee,
        anythingAlreadyPaid: existingTickets.any((t) => t.isPaid),
      );

      // Detached print job. PrintingService serialises it behind anything a
      // waiter is already printing, and a failure cannot lose kitchen work:
      // items are only marked printed on a confirmed success, so
      // KdsPrintMode.modificationsOnly re-sends them on the next fire.
      unawaited(() async {
        try {
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
                // Marked PAID above, before this detached job runs.
                paidLinesStillOwed: {
                  for (final item in unpaidItems)
                    if (item.id != null) item.id!,
                },
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
            // Products only — the figure the ticket row carries and every sales
            // total is built from. The fee travels beside it as its own line.
            amount: total,
            deliveryFee: feeForThisTicket,
            paymentMethod: TransactionType.cash.value,
            createdAt: DateTime.now(),
            items: itemsForPrint,
            orderType: reloadedOrder.type,
            hasTable: hasTable,
            orderCode: reloadedOrder.orderCode,
            cashierName: currentUser.firstName,
            waiterName: reloadedOrder.waiterName,
            storeName: businessName,
            storeAddress: storeAddress,
            storePhone: storePhone,
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
      }());

      // Finalize atomically: mark paid + free the table (occupancy-based, so a
      // stale in-memory tableId can't strand the table) in one transaction.
      // Tolerates CANCELED lines. See OrderRepository.settleOrderAndFreeTable.
      // Local writes, kept on the critical path: the table must be released
      // before the cashier is told the till is free.
      final paidStatus = settings.paidOrderDefaultStatus;
      // Paying it here makes it this cashier's, wherever it came from.
      await orderRepo.claimOrderForCurrentUser(orderId);

      final completed = await orderRepo.settleOrderAndFreeTable(
        orderId,
        paidStatus: paidStatus,
        clearTable: settings.autoClearTableAfterPaying,
      );

      // Money is recorded and the table is released — the till is free.
      if (context.mounted) {
        ref.read(orderProvider.notifier).clearOrder();
      }

      if (completed) {
        // Detached. Kept rather than deleted (unlike the Proceed path, where
        // the repository already pushes): settleOrderAndFreeTable passes
        // queueSyncOperation: false, so this is the paid order's only prompt
        // push. It still writes isSynced = false, so the periodic sweep
        // remains the backstop if this fails.
        final isOnline = ref.read(lastKnownOnlineStatusProvider);
        if (isOnline) {
          final syncManager = ref.read(syncManagerProvider.notifier);
          unawaited(() async {
            try {
              await syncManager.autoSyncOrder(orderId);
              _logger.info('Auto-synced $paidStatus order #$orderId after direct payment');
            } catch (e) {
              _logger.error('Auto-sync failed after direct payment: $e');
            }
          }());
        }
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
  /// Cancel the saved order currently on the panel.
  ///
  /// Asks first, and asks for a reason — a cancelled order is a hole in the
  /// day's takings that somebody will ask about, and "no reason given" is a
  /// worse answer than a hurried one. The reason is optional because refusing
  /// to cancel until a cashier types something just gets a full stop typed.
  ///
  /// The status change flows through OrderRepository, which is what flags the
  /// order's tickets as cancelled so its money leaves the session totals and
  /// the Z report.
  Future<void> _cancelCurrentOrder() async {
    final l10n = AppLocalizations.of(context)!;
    final order = ref.read(orderProvider);
    if (!order.isSaved() || order.orderId == null) return;

    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.cancel_outlined,
            color: Theme.of(ctx).colorScheme.error, size: 30),
        title: Text(l10n.translate('cancel_order')),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${l10n.translate('cancel_saved_order_confirm')}\n'
                '${order.orderCode ?? ''}',
                style: const TextStyle(fontSize: 15),
              ),
              const SizedBox(height: 14),
              AdaptiveKeyboardTextField(
                controller: reasonCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.translate('cancellation_reason'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('no')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(l10n.translate('cancel_order')),
          ),
        ],
      ),
    );
    final reason = reasonCtrl.text.trim();
    // Not disposed: the closing dialog still rebuilds its field with this controller for a few frames. It is collected with the dialog.
    if (confirmed != true || !mounted) return;

    try {
      await ref.read(orderRepositoryProvider).updateOrderStatus(
            order.orderId!,
            'CANCELED',
            cancellationReason: reason.isEmpty ? null : reason,
            userId: ref.read(currentUserProvider)?.id,
          );
      // The table is only freed once the cancel actually landed — releasing it
      // first would hand the table to the next party while the order it is
      // still carrying failed to cancel.
      if (order.tableId != null) {
        await ref
            .read(orderRepositoryProvider)
            .setTableOrderId(order.tableId!, null);
      }
      ref.read(orderProvider.notifier).clearOrder();
    } catch (e) {
      if (mounted) SnackBarHelper.failure(context, e);
    }
  }

  /// The order ticket + kitchen ticket a just-saved order fires, honouring the
  /// cashier's per-output print rules.
  ///
  /// Shared by the Continue (Proceed) tap and by the long-press that opens the
  /// payment screen to divide an order before collecting — that long-press
  /// stands in for a Continue, so the kitchen has to receive the order exactly
  /// as it would have. Without this, dividing a bill before paying sent the
  /// food order nowhere.
  ///
  /// KDS mode is deliberately left to `config.defaultKdsMode`, the same as
  /// every other caller: a shop on `modificationsOnly` gets only the items the
  /// kitchen has not already seen, which is what makes re-firing this on an
  /// order that was already sent safe.
  ///
  /// Print failures are logged and swallowed — the order is saved either way,
  /// and a dead printer must not look like a failed save.
  ///
  /// [beforePayment] is set by the Pay path: the cashier may settle the order
  /// before this queued job reaches the printer, so the lines unpaid right now
  /// must still go to the kitchen once they carry a ticket.
  Future<void> _firePostSavePrints(CurrentOrder reloadedOrder,
      {bool beforePayment = false}) async {
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final hasTable = reloadedOrder.tableId != null;

    try {
      if (printingService.shouldPrint(
        PrintOutput.orderTicket,
        orderType: reloadedOrder.type,
        hasTable: hasTable,
      )) {
        await printingService.printOrderReceipt(
          order: reloadedOrder,
          cashierName: currentUser?.firstName,
          storeName: prefs.getString('business_name'),
          storeAddress: prefs.getString('business_address'),
          storePhone: prefs.getString('business_phone'),
          // Only the round just added. Continue on an open table used to
          // reprint the whole bill every time — a table on its third round
          // got three full bills instead of a slip per round. The kitchen
          // has worked this way since KdsPrintMode existed; this brings the
          // customer slip in line. A full bill is still one tap away from
          // the division window's print button.
          mode: OrderTicketPrintMode.additionsOnly,
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
          cashierName: currentUser?.firstName,
          paidLinesStillOwed: beforePayment
              ? {
                  for (final item in reloadedOrder.unpaidItems)
                    if (item.id != null) item.id!,
                }
              : const {},
        );
      }
    } catch (e) {
      _logger.error('Post-save print failed: $e');
    }
  }

  /// [printOnSave] forces [_firePostSavePrints] after the save — true for the
  /// long-press on Continue, which replaces a Proceed and therefore owes the
  /// kitchen its ticket. Pay does not pass it, but still fires the prints for
  /// an order that was never saved (see `kitchenOwed`).
  Future<void> _showPaymentDialog({
    bool forceSplitOpen = false,
    bool printOnSave = false,
  }) async {
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

    // An order that was never proceeded has never reached the kitchen, and
    // the payment screen prints no kitchen ticket of its own — so a plain Pay
    // on a fresh takeaway used to send the food nowhere. A saved order is
    // re-fired only under modificationsOnly, which sends just the lines added
    // since the last Continue and nothing at all when there are none.
    final kitchenOwed = printOnSave ||
        !currentOrder.isSaved() ||
        ref.read(printingServiceProvider).config.defaultKdsMode ==
            KdsPrintMode.modificationsOnly;

    setState(() => _isSavingOrder = true);
    try {
      int orderId;
      // Save or update order first.
      if (currentOrder.isSaved()) {
        // Lines stay the waiter's; the header is the cashier's.
        await orderRepo.updateOrder(currentOrder,
            headerOnly: !canEditWaiterOrder(ref));
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

      // Fired before the dialog, not after: the kitchen should start on the
      // food while the cashier is still dividing the bill. Detached, so the
      // division window opens immediately rather than behind the kitchen
      // ticket — the print is already queued by the time it appears.
      if (kitchenOwed) {
        unawaited(_firePostSavePrints(reloadedOrder, beforePayment: true));
      }

      if (context.mounted) {
        // Straight to the payment screen: it owns the cash pad, so there is
        // no prompt in front of it to answer the same question twice.
        final result = await showDialog<bool>(
          context: context,
          builder: (context) => PaymentScreen(
            order: reloadedOrder,
            forceSplitOpen: forceSplitOpen,
          ),
        );

        if (result == true && context.mounted) {
          // Payment completed - order already marked COMPLETED and synced by PaymentScreen
          // Clear order
          ref.read(orderProvider.notifier).clearOrder();
        } else if ((result == false || forceSplitOpen) && context.mounted) {
          // "Divide now, collect later": the order is saved, its table is
          // linked and its division is remembered, so the till should be free
          // for the next customer — exactly as a plain Continue leaves it.
          // Reloading it into the panel instead (what the branch below does)
          // left the cashier unable to start another order without manually
          // clearing this one.
          //
          // `result == false` is the payment screen's own "Save & continue"
          // button, which means the same thing however the screen was opened
          // — a cashier who reached it through plain Pay and then chose to
          // save the division rather than collect wants the till freed too.
          ref.read(orderProvider.notifier).clearOrder();
        } else if (context.mounted) {
          // Backed out of a normal payment: keep the order in the panel, the
          // cashier is still working on it.
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
  /// Walk the order past every rule it breaks, one picker at a time.
  ///
  /// Returns false when the cashier backs out of a picker, and SAYS SO before
  /// it does. Silence here was the bug behind "I press pay, the table dialog
  /// opens, I close it, and nothing happens": the payment was abandoned
  /// correctly and invisibly, so the button looked broken rather than blocked.
  ///
  /// It also refuses to carry on into a payment for a DIFFERENT order than the
  /// one the cashier pressed pay on. Picking a table that already has an open
  /// order swaps the whole basket for that order — carrying straight on would
  /// take money for a ticket nobody had looked at.
  /// Ask the cashier to finish tagging courses, when they started.
  ///
  /// Returns false only if they back out entirely — "Send anyway" is a real
  /// answer, because a kitchen waiting on food should never be held up by a
  /// bookkeeping prompt. The untagged lines then print under "Other", which
  /// is honest about what the cashier actually said.
  Future<bool> _resolveRuleViolations() async {
    final settings = ref.read(settingsProvider);
    final startedOnOrderId = ref.read(orderProvider).orderId;
    while (true) {
      final order = ref.read(orderProvider);
      final violation = validateOrderRules(order, settings);
      if (violation == null) {
        if (order.orderId != startedOnOrderId) {
          if (mounted) {
            SnackBarHelper.showErrorSnackBar(
              context,
              ref,
              AppLocalizations.of(context)!
                  .translate('order_switched_check_before_paying'),
            );
          }
          return false;
        }
        return true;
      }
      final picked = await _runRuleFix(violation.fix);
      if (!picked) {
        // Say which rule stopped it. The picker they just closed is the clue,
        // but only if they connect the two.
        if (mounted) {
          SnackBarHelper.showErrorSnackBar(
            context,
            ref,
            AppLocalizations.of(context)!.translate(violation.errorKey),
          );
        }
        return false;
      }
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
      // Reuse the same conflict prompt the normal table-pick flow uses, on the
      // same terms: only unsaved work is worth stopping the cashier for.
      final hasItems = ref.read(orderProvider).hasUnsavedChanges;
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

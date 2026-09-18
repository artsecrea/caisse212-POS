import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:caisse212/domain/models/external_order_models.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/external_order_provider.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/presentation/paymen_screen/payment_screen.dart';
import 'package:caisse212/presentation/widgets/external_customer_review_dialog.dart';
import 'package:caisse212/presentation/widgets/external_queue_controls.dart';
// TEMP-TIP-HIDDEN: restore together with the two commented blocks in
// _confirmAndPay and _confirmExternalAndPay.
// import 'package:caisse212/presentation/widgets/tip_flow.dart';
import 'package:caisse212/presentation/order_confirmation/external_orders_live_page.dart';
import 'package:caisse212/providers/settings_provider.dart';
import 'package:caisse212/presentation/widgets/order_source_badge.dart';
import 'package:caisse212/utils/app_localizations.dart';
import 'package:caisse212/utils/currency_formatter.dart';
import 'package:caisse212/utils/snackbar_helper.dart';
import 'package:caisse212/services/printing_service.dart';

/// The external order queue — marketplace and messaging orders (DealUp,
/// WhatsApp, Glovo) waiting to be accepted into the POS.
///
/// On-hold orders used to share this screen as a second tab. They are ordinary
/// saved orders, not incoming work, and they already have a home in Orders
/// Management with its own ONHOLD filter — so the tab bar is gone and this is
/// a single-purpose queue screen again.
class OrderConfirmationScreen extends ConsumerStatefulWidget {
  const OrderConfirmationScreen({super.key});

  @override
  ConsumerState<OrderConfirmationScreen> createState() =>
      _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState
    extends ConsumerState<OrderConfirmationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  ExternalQueueItem? _selectedExternalItem;
  bool _isConfirmingExternal = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Pull the queue when the screen opens. Nothing else does: the SSE listener
    // that refreshes on `connected` is off by default, so without this the tab
    // sat empty (and the tab badge read 0) until the cashier found the refresh
    // button. Post-frame so the provider isn't mutated during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(externalOrderProvider.notifier).load();
    });
  }

  Future<List<Map<String, dynamic>>> _resolveExternalItems(
      ExternalQueueItem item) async {
    final db = ref.read(databaseProvider);
    final result = <Map<String, dynamic>>[];
    for (final qi in item.order.items) {
      final product = await (db.select(db.products)
            ..where((p) => p.id.equals(qi.productId)))
          .getSingleOrNull();
      // Variant price wins when the queue item picked a variant — variants
      // typically have a different price than the base product (e.g. Large
      // size, special edition). Falls back to the product price otherwise.
      double unitPrice = product?.finalPrice ?? 0.0;
      String? variantName;
      if (qi.variantId != null) {
        final variant = await (db.select(db.productVariants)
              ..where((v) => v.id.equals(qi.variantId!)))
            .getSingleOrNull();
        if (variant != null) {
          unitPrice = variant.price;
          variantName = variant.name;
        }
      }
      // The price the order was actually validated at wins over the local
      // catalogue, which may have moved since the customer ordered. It is the
      // bare product/variant price on every source now — options never ride
      // in it — so the components below can be added on top without
      // double-counting.
      unitPrice = qi.unitPrice ?? unitPrice;
      // Components carry the option money: what was charged after any free
      // allowance, and a partly-covered selection arrives already split into a
      // 0.00 row and a charged row. Take the sent price when there is one —
      // falling back to the catalogue would re-bill a free row at full price
      // and quote the cashier more than the customer agreed to.
      final comps = <Map<String, dynamic>>[];
      double componentsPerItem = 0.0;
      for (final c in qi.components) {
        final comp = await (db.select(db.components)
              ..where((cc) => cc.id.equals(c.componentId)))
            .getSingleOrNull();
        if (comp == null) continue;
        final compPrice = c.price ?? comp.price;
        componentsPerItem += compPrice * c.quantity;
        comps.add({
          'name': comp.name,
          'quantity': c.quantity,
          'price': compPrice,
        });
      }
      // Line total = quantity × (unit price + components total per unit).
      final lineTotal = qi.quantity * (unitPrice + componentsPerItem);
      final displayName = variantName != null
          ? '${product?.name ?? 'Product #${qi.productId}'} — $variantName'
          : (product?.name ?? 'Product #${qi.productId}');
      result.add({
        'name': displayName,
        'quantity': qi.quantity,
        'note': qi.note,
        'components': comps, // List<Map> now, not List<String>
        'unitPrice': unitPrice,
        'lineTotal': lineTotal,
      });
    }
    return result;
  }

  /// Shows the customer review dialog before the server ack runs.
  /// Returns the resolved local customer id, or null if the cashier
  /// cancelled (in which case the confirm should abort entirely — no
  /// server ack, no local row, queue item stays PENDING).
  Future<int?> _resolveExternalCustomer(ExternalQueueItem item) {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExternalCustomerReviewDialog(
        suggestedName: item.order.customerName,
        suggestedPhone: item.order.customerPhone,
      ),
    );
  }

  Future<void> _confirmExternalOrder(ExternalQueueItem item) async {
    final overrideClientId = await _resolveExternalCustomer(item);
    if (overrideClientId == null) return; // cashier cancelled
    if (!mounted) return;
    setState(() => _isConfirmingExternal = true);
    try {
      final userId = ref.read(currentUserProvider)?.id;
      final orderId = await ref
          .read(externalOrderProvider.notifier)
          .confirm(
            item.id,
            userId: userId,
            overrideClientId: overrideClientId,
          );
      if (mounted) {
        if (orderId != null) {
          SnackBarHelper.showSuccessSnackBar(context, ref,
              'Order ${item.orderCode} confirmed and sent to KDS');
          setState(() {
            _selectedExternalItem = null;
            _isConfirmingExternal = false;
          });
        } else {
          // The notifier sets state.error to the literal "TAKEN" sentinel
          // for the 409-already-taken case so we can translate it; any
          // other error string flows through verbatim.
          final l10n = AppLocalizations.of(context)!;
          final err = ref.read(externalOrderProvider).error;
          if (err == 'TAKEN') {
            SnackBarHelper.showErrorSnackBar(
                context, ref, l10n.translate('order_already_taken'));
            setState(() {
              _selectedExternalItem = null;
              _isConfirmingExternal = false;
            });
          } else {
            SnackBarHelper.showErrorSnackBar(
                context, ref, err ?? 'Failed to confirm order');
            setState(() => _isConfirmingExternal = false);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.failure(context, e);
        setState(() => _isConfirmingExternal = false);
      }
    }
  }

  /// Glovo has no inbound cancel: the server logs the rejection and nothing
  /// reaches the platform. Kooul does reject properly, and DealUp/Web are ours.
  bool _isGlovo(ExternalQueueItem item) =>
      item.source.toUpperCase() == 'GLOVO';

  Future<void> _cancelExternalOrder(ExternalQueueItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('reject_order')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translate('cancel_order_confirm')),
            // Rejecting a Glovo order does NOT reach Glovo — the platform has
            // no inbound cancel for us. Said before the tap, not after, because
            // afterwards the cashier believes it is handled.
            if (_isGlovo(item)) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.phone_in_talk,
                        size: 18, color: Colors.deepOrange),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.translate('glovo_cancel_warning'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.tintFill(context, Colors.red),
              foregroundColor: AppTheme.tintOn(context, Colors.red),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.translate('reject_order')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isConfirmingExternal = true);
    try {
      final userId = ref.read(currentUserProvider)?.id;
      final orderId = await ref
          .read(externalOrderProvider.notifier)
          .cancel(item.id, userId: userId);
      if (!mounted) return;
      if (orderId != null) {
        setState(() {
          _selectedExternalItem = null;
          _isConfirmingExternal = false;
        });
        if (_isGlovo(item)) {
          // Removed from OUR queue only. Telling the cashier it was "rejected"
          // would be a lie that ends with a courier arriving for an order
          // nobody made — Glovo still believes it is live until someone phones.
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(Icons.phone_in_talk,
                  color: Colors.deepOrange, size: 40),
              title: Text(l10n.translate('call_glovo_title')),
              content: Text(l10n
                  .translate('call_glovo_body')
                  .replaceAll('{0}', item.orderCode)),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(l10n.translate('ok')),
                ),
              ],
            ),
          );
        } else {
          SnackBarHelper.showSuccessSnackBar(context, ref,
              'Order ${item.orderCode} rejected');
        }
      } else {
        final err = ref.read(externalOrderProvider).error ??
            'Failed to reject order';
        SnackBarHelper.showErrorSnackBar(context, ref, err);
        setState(() => _isConfirmingExternal = false);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.failure(context, e);
        setState(() => _isConfirmingExternal = false);
      }
    }
  }

  Future<void> _confirmExternalAndPay(ExternalQueueItem item) async {
    final overrideClientId = await _resolveExternalCustomer(item);
    if (overrideClientId == null) return; // cashier cancelled
    if (!mounted) return;
    setState(() => _isConfirmingExternal = true);
    try {
      final userId = ref.read(currentUserProvider)?.id;
      final orderId = await ref
          .read(externalOrderProvider.notifier)
          .confirm(
            item.id,
            userId: userId,
            overrideClientId: overrideClientId,
          );
      if (!mounted) return;
      if (orderId == null) {
        final err =
            ref.read(externalOrderProvider).error ?? 'Failed to confirm';
        SnackBarHelper.showErrorSnackBar(context, ref, err);
        setState(() => _isConfirmingExternal = false);
        return;
      }
      final fullOrder =
          await ref.read(orderRepositoryProvider).getOrderById(orderId);
      if (!mounted) return;
      if (fullOrder == null) {
        SnackBarHelper.showErrorSnackBar(context, ref, 'Order not found');
        setState(() => _isConfirmingExternal = false);
        return;
      }
      // TEMP-TIP-HIDDEN: tip dialog before PaymentScreen disabled.
      // final withTip = await applyTipIfEnabled(context, ref, fullOrder);
      // if (withTip.tip != fullOrder.tip) {
      //   await ref.read(orderRepositoryProvider).updateOrder(withTip);
      // }
      if (!mounted) return;
      Navigator.of(context).pop();
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PaymentScreen(order: fullOrder)));
    } catch (e) {
      if (mounted) {
        SnackBarHelper.failure(context, e);
        setState(() => _isConfirmingExternal = false);
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final externalState = ref.watch(externalOrderProvider);
    // Waiting-work badge. Uses the server's total for the PENDING filter, not
    // items.length — that is one page, so 64 pending across 4 pages used to
    // read "20". Hidden while the cashier is browsing another status, where a
    // count of cancelled rows would not mean "work waiting".
    final externalCount = externalState.statusFilter == 'PENDING'
        ? externalState.totalElements
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('external_orders')),
        actions: [
          // Only the queue has two shapes to switch between; the in-progress
          // page is one card per order by nature.
          if (_tabController.index == 0)
            IconButton(
              tooltip: l10n.translate(
                  _queueAsGrid ? 'view_as_list' : 'view_as_grid'),
              icon: Icon(_queueAsGrid
                  ? Icons.view_list_outlined
                  : Icons.grid_view_outlined),
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .setExternalQueueGridView(!_queueAsGrid),
            ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tabController,
          // The action button above depends on which tab is showing.
          onTap: (_) => setState(() {}),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_download_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(l10n.translate('incoming')),
                  if (externalCount > 0) ...[
                    const SizedBox(width: 6),
                    _CountBadge(count: externalCount),
                  ],
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_shipping_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(l10n.translate('in_progress')),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildExternalTab(l10n, cs, externalState),
          const ExternalOrdersLivePage(),
        ],
      ),
    );
  }

  bool get _queueAsGrid => ref.watch(settingsProvider).externalQueueGridView;

  Widget _buildExternalTab(
      AppLocalizations l10n, ColorScheme cs, ExternalOrderState state) {
    // Resolve the selection out of the CURRENT page rather than trusting the
    // stored object. Now that filters and paging exist, the selected item can
    // leave the list under the cashier (filter change, page turn, or another
    // terminal confirming it), and a stale right-hand pane would offer Confirm
    // on a row that is no longer there. Deriving also means the pane picks up
    // the item's new status after a refresh instead of showing the old one.
    ExternalQueueItem? selected;
    if (_selectedExternalItem != null) {
      for (final i in state.items) {
        if (i.id == _selectedExternalItem!.id) {
          selected = i;
          break;
        }
      }
    }

    return Row(
      children: [
        // Left: external items list
        Expanded(
          flex: 5,
          child: Column(
            children: [
              if (state.error != null)
                _ErrorBanner(
                  message: state.error!,
                  onDismiss: () =>
                      ref.read(externalOrderProvider.notifier).load(),
                ),
              // Status + per-source filters with live counts. The old header
              // here showed only "N pending" and a refresh button, which made
              // the CONFIRMED / CANCELLED history and the other platforms
              // unreachable from the screen the cashier actually works in.
              ExternalQueueFilterBar(state: state, l10n: l10n),
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : state.items.isEmpty
                        // Filter-aware: with status/source filters in play,
                        // "no pending orders" would be a lie on the CANCELLED
                        // or Glovo chip. Says what is actually true — nothing
                        // matches the current filters.
                        ? _EmptyPane(
                            icon: Icons.cloud_off_outlined,
                            label: l10n.translate('no_orders_for_filters'),
                            subtitle:
                                l10n.translate('no_orders_for_filters_hint'),
                          )
                        : _buildQueueItems(state, selected),
              ),
              ExternalQueuePager(state: state, l10n: l10n),
            ],
          ),
        ),
        // Right: external order details
        Expanded(
          flex: 4,
          child: selected == null
              ? const _EmptyPane(
                  icon: Icons.touch_app,
                  label: 'Select an order to review',
                )
              : _buildExternalOrderDetails(selected, l10n),
        ),
      ],
    );
  }

  /// The queue, as a list or a grid.
  ///
  /// Same card either way — only the arrangement changes, so nothing about an
  /// order reads differently depending on the shape. The grid sizes itself off
  /// the available width rather than a fixed column count, because this pane
  /// is half a till on one site and a whole tablet on another.
  Widget _buildQueueItems(ExternalOrderState state, ExternalQueueItem? selected) {
    void select(ExternalQueueItem item) => setState(() {
          _selectedExternalItem = item;
          _isConfirmingExternal = false;
        });

    if (!_queueAsGrid) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        itemCount: state.items.length,
        itemBuilder: (context, i) {
          final item = state.items[i];
          return _ExternalItemCard(
            key: ValueKey(item.id),
            item: item,
            isSelected: selected?.id == item.id,
            onTap: () => select(item),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // ~260px is the narrowest a card stays readable at; below that the
        // grid degrades to a single column rather than clipping.
        final columns = (constraints.maxWidth / 260).floor().clamp(1, 4);
        return GridView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 4,
            crossAxisSpacing: 8,
            // Tall enough for the card's own content, which is a fixed set of
            // rows — a ratio, not a height, so it scales with the column width.
            childAspectRatio: 1.35,
          ),
          itemCount: state.items.length,
          itemBuilder: (context, i) {
            final item = state.items[i];
            return _ExternalItemCard(
              key: ValueKey(item.id),
              item: item,
              isSelected: selected?.id == item.id,
              onTap: () => select(item),
            );
          },
        );
      },
    );
  }

  Widget _buildExternalOrderDetails(
      ExternalQueueItem item, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final order = item.order;

    return Container(
      decoration: BoxDecoration(
        border:
            Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          // Safety and money first, above everything else on the pane. These
          // three change what staff physically DO — cook differently, take
          // money, or read a code to a courier — so they must not be findable
          // only by scrolling past the item list.
          if (order.hasAllergyInfo)
            _AlertBanner(
              icon: Icons.warning_amber_rounded,
              background: Colors.red.shade700,
              title: l10n.translate('allergy_warning'),
              body: order.allergyInfo!,
            ),
          if (order.isCashOnHandover)
            _AlertBanner(
              icon: Icons.payments,
              background: Colors.green.shade800,
              title: l10n.translate('collect_cash'),
              body: order.totalCustomerToPay != null
                  ? '${order.totalCustomerToPay!.toStringAsFixed(2)} ${order.currency ?? ''}'.trim()
                  : l10n.translate('collect_cash_hint'),
            ),

          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            color: isDark ? cs.surfaceContainerHigh : Colors.deepPurple.shade50,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                OrderSourceBadge(source: item.source),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.orderCode,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          _TypeChip(type: order.type),
                        ],
                      ),
                      // The platform's code is what the courier reads out; ours
                      // means nothing to them. GLOVO/KOOUL only — DealUp and Web
                      // have no courier and no such code.
                      if (PrintingService.sourceHasCourierCode(item.source) &&
                          ((order.externalOrderCode ?? '').isNotEmpty ||
                              (order.pickUpCode ?? '').isNotEmpty))
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Wrap(
                            spacing: 8,
                            children: [
                              if ((order.externalOrderCode ?? '').isNotEmpty)
                                _CodeChip(
                                  label: l10n.translate('platform_code'),
                                  value: order.externalOrderCode!,
                                ),
                              if ((order.pickUpCode ?? '').isNotEmpty)
                                _CodeChip(
                                  // Fuller label on screen; the printed line
                                  // uses the short form to fit 58mm.
                                  label: l10n.translate('pickup_code_label'),
                                  value: order.pickUpCode!,
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          OrderSourceLabel(source: item.source),
                          const SizedBox(width: 8),
                          Icon(Icons.access_time,
                              size: 12,
                              color: cs.onSurface.withValues(alpha: 0.5)),
                          const SizedBox(width: 3),
                          Text(
                            _formatTimeAgo(item.createdAt),
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.5)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Customer info
          if (order.customerName != null || order.customerPhone != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 16,
                      color: cs.onSurface.withValues(alpha: 0.6)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (order.customerName != null)
                          Text(order.customerName!,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        if (order.customerPhone != null)
                          Text(order.customerPhone!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color:
                                      cs.onSurface.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Note
          if (order.note != null && order.note!.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.notes, size: 14, color: Colors.orange[700]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.note!,
                      style: TextStyle(
                          color: Colors.orange[800],
                          fontSize: 12,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
            ),

          // Items + totals
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _resolveExternalItems(item),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return Center(
                    child: Text('No items',
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: 0.5))),
                  );
                }
                // Sum every item's pre-computed line total. Each line total
                // already factors in quantity and per-item components, so the
                // total here is the queue order's grand subtotal — no extra
                // multiplication or component math at this level.
                final currency = ref.read(currencySymbolProvider);
                final orderTotal = items.fold<double>(
                    0.0, (sum, it) => sum + (it['lineTotal'] as double));
                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final it = items[i];
                          final comps = (it['components'] as List)
                              .cast<Map<String, dynamic>>();
                          return _ItemCard(
                            quantityLabel: '${it['quantity']}x',
                            name: it['name'] as String,
                            note: it['note'] as String?,
                            // Per-line currency total to the right of the
                            // product name. Two decimals + currency symbol
                            // for parity with the receipt printer.
                            trailingLabel: CurrencyFormatter.formatWithCurrency(
                                it['lineTotal'] as double, currency),
                            chips: comps
                                .map((c) => _CompChip(
                                      label: _composeComponentLabel(
                                          c, currency),
                                      isSpecial:
                                          (c['isSpecial'] as bool?) ?? false,
                                    ))
                                .toList(),
                          );
                        },
                      ),
                    ),
                    // Totals row — Subtotal-equivalent (no discount /
                    // tip context on an unconfirmed external order yet).
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color:
                                cs.primary.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long,
                              size: 18, color: cs.primary),
                          const SizedBox(width: 8),
                          Text(
                            l10n.translate('total'),
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Text(
                            CurrencyFormatter.formatWithCurrency(
                                orderTotal, currency),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Actions
          _buildExternalActions(item, l10n),
        ],
      ),
    );
  }

  Widget _buildExternalActions(
      ExternalQueueItem item, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: Theme.of(context).dividerColor))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConfirmingExternal
                      ? null
                      : () => _confirmExternalOrder(item),
                  icon: _isConfirmingExternal
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white))
                      : const Icon(Icons.check_circle, size: 18),
                  label: Text(_isConfirmingExternal
                      ? 'Confirming…'
                      : 'Accept & Confirm'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isConfirmingExternal
                      ? null
                      : () => _confirmExternalAndPay(item),
                  icon: const Icon(Icons.payment, size: 18),
                  label: const Text('Accept & Pay'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Reject — destructive, full-width, between the accept row and
          // "Back to list". Red 100/900 palette signals destructive
          // without screaming; the dialog inside `_cancelExternalOrder`
          // is what guards against misclicks.
          ElevatedButton.icon(
            onPressed: _isConfirmingExternal
                ? null
                : () => _cancelExternalOrder(item),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: Text(l10n.translate('reject_order')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.tintFill(context, Colors.red),
              foregroundColor: AppTheme.tintOn(context, Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: _isConfirmingExternal
                ? null
                : () => setState(() {
                      _selectedExternalItem = null;
                      _isConfirmingExternal = false;
                    }),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back to list'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ],
      ),
    );
  }

  /// Build a chip label for a single component: "2× Cheese (+5.00 $)"
  /// when the component is priced, "2× Cheese" when it's free. Keeps the
  /// chip readable on a narrow column while still surfacing the cost so
  /// the order total adds up.
  String _composeComponentLabel(Map<String, dynamic> c, String currency) {
    final qty = c['quantity'] as int;
    final name = c['name'] as String;
    final price = (c['price'] as num?)?.toDouble() ?? 0.0;
    if (price <= 0) return '$qty× $name';
    final lineExtra = price * qty;
    return '$qty× $name (+${lineExtra.toStringAsFixed(2)} $currency)';
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ── Shared sub-widgets ──────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final String quantityLabel;
  final String name;
  final String? trailingLabel;
  final String? note;
  final List<Widget> chips;

  const _ItemCard({
    required this.quantityLabel,
    required this.name,
    this.trailingLabel,
    this.note,
    this.chips = const [],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: cs.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    quantityLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: cs.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(name,
                      style:
                          const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (trailingLabel != null)
                  Text(trailingLabel!,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
              ],
            ),
            if (note != null && note!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 42),
                child: Text(
                  '— $note',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.orange[700],
                      fontStyle: FontStyle.italic),
                ),
              ),
            ],
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 42),
                child: Wrap(spacing: 6, runSpacing: 4, children: chips),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompChip extends StatelessWidget {
  final String label;
  final bool isSpecial;
  const _CompChip({required this.label, this.isSpecial = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isSpecial)
          Icon(Icons.star, size: 11, color: Colors.orange[600]),
        Text(
          label,
          style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.65)),
        ),
      ],
    );
  }
}

class _ExternalItemCard extends StatelessWidget {
  final ExternalQueueItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _ExternalItemCard({
    super.key,
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final order = item.order;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelected ? 3 : 1,
      color: isSelected ? cs.secondaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? BorderSide(color: cs.secondary, width: 2)
            : BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              OrderSourceBadge(source: item.source, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.orderCode,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _TypeChip(type: order.type),
                        const SizedBox(width: 6),
                        Text(
                          '${order.items.length} item${order.items.length == 1 ? '' : 's'}',
                          style: TextStyle(
                              fontSize: 11,
                              color:
                                  cs.onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                    if (order.customerName != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        order.customerName!,
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.7)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  OrderSourceLabel(source: item.source),
                  const SizedBox(height: 4),
                  Text(
                    _formatTimeAgo(item.createdAt),
                    style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});
  final String type;

  @override
  Widget build(BuildContext context) {
    Color bg;
    String label;
    switch (type) {
      case 'DINE_IN':
        bg = AppTheme.tintFill(context, Colors.blue);
        label = 'Dine In';
        break;
      case 'TAKE_AWAY':
        bg = AppTheme.tintFill(context, Colors.purple);
        label = 'Take Away';
        break;
      case 'DELIVERY':
        bg = AppTheme.tintFill(context, Colors.teal);
        label = 'Delivery';
        break;
      default:
        bg = Theme.of(context).colorScheme.surfaceContainerHighest;
        label = type;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(label,
          style:
              const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

/// Full-width, high-contrast banner for the facts that change what staff do.
///
/// Deliberately loud: a coloured chip among other chips is exactly what gets
/// skimmed past on a busy counter, and the two things this carries — an allergy
/// and "collect the money" — are the two that cost the most when missed.
class _AlertBanner extends StatelessWidget {
  final IconData icon;
  final Color background;
  final String title;
  final String body;

  const _AlertBanner({
    required this.icon,
    required this.background,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  body,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
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

/// A code the courier will say out loud, in monospace so it can be compared
/// character by character.
class _CodeChip extends StatelessWidget {
  final String label;
  final String value;

  const _CodeChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Copyable: staff read this code to Glovo/Kooul support on the phone, and
    // re-typing a 10-character code off a screen is how digits get transposed.
    return InkWell(
      onLongPress: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$label: $value'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: _chip(context, cs),
    );
  }

  Widget _chip(BuildContext context, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label ',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int count;
  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.red[600],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white),
      ),
    );
  }
}

class _EmptyPane extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  const _EmptyPane(
      {required this.icon, required this.label, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 64,
              color: cs.onSurface.withValues(alpha: 0.25)),
          const SizedBox(height: 12),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.55)),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.4)),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: const TextStyle(color: Colors.red, fontSize: 13))),
          TextButton(
            onPressed: onDismiss,
            child: const Text('Retry',
                style: TextStyle(color: Colors.red, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

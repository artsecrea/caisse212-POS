import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/external_order_models.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/external_order_provider.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/presentation/paymen_screen/payment_screen.dart';
import 'package:caisse212/presentation/widgets/external_customer_review_dialog.dart';
// TEMP-TIP-HIDDEN: restore together with the two commented blocks in
// _confirmAndPay and _confirmExternalAndPay.
// import 'package:caisse212/presentation/widgets/tip_flow.dart';
import 'package:caisse212/utils/app_localizations.dart';
import 'package:caisse212/utils/currency_formatter.dart';
import 'package:caisse212/utils/snackbar_helper.dart';

final _waitersProvider = FutureProvider.autoDispose<List<Waiter>>((ref) async {
  final db = ref.read(databaseProvider);
  return (db.select(db.waiters)..where((w) => w.isActive.equals(true))).get();
});

class OrderConfirmationScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const OrderConfirmationScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<OrderConfirmationScreen> createState() =>
      _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState
    extends ConsumerState<OrderConfirmationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // On-hold order state
  Order? _selectedOrder;
  Waiter? _selectedWaiter;
  bool _waiterMissing = false;

  // External order state
  ExternalQueueItem? _selectedExternalItem;
  bool _isConfirmingExternal = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _selectedOrder = null;
          _selectedExternalItem = null;
          _selectedWaiter = null;
          _waiterMissing = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ── On-hold helpers ─────────────────────────────────────────────────────────

  Future<List<Order>> _getOnHoldOrders() async {
    final database = ref.read(databaseProvider);
    final orders = await (database.select(database.orders)
          ..where((tbl) => tbl.status.equals('ONHOLD'))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]))
        .get();
    if (_searchQuery.isEmpty) return orders;
    return orders
        .where((o) =>
            o.code.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  bool _requireWaiter(Order order) {
    if (order.type != 'DINE_IN') return true;
    if (order.waiterId != null) return true;
    if (_selectedWaiter != null) return true;
    setState(() => _waiterMissing = true);
    return false;
  }

  Future<void> _confirmOrder(Order order) async {
    if (!_requireWaiter(order)) return;
    setState(() => _waiterMissing = false);
    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final sessionId = ref.read(currentSessionProvider)?.id;
      final userId = ref.read(currentUserProvider)?.id;
      final waiterId = _selectedWaiter?.id ?? order.waiterId;
      await orderRepo.updateOrderStatus(order.id, 'PENDING',
          sessionId: sessionId, userId: userId, waiterId: waiterId);
      if (mounted) {
        SnackBarHelper.showSuccessSnackBar(
            context, ref, 'Order ${order.code} confirmed and sent to KDS');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showErrorSnackBar(
            context, ref, 'Error confirming order: $e');
      }
    }
  }

  Future<void> _confirmAndPay(Order order) async {
    if (!_requireWaiter(order)) return;
    setState(() => _waiterMissing = false);
    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final sessionId = ref.read(currentSessionProvider)?.id;
      final userId = ref.read(currentUserProvider)?.id;
      final waiterId = _selectedWaiter?.id ?? order.waiterId;
      await orderRepo.updateOrderStatus(order.id, 'PENDING',
          sessionId: sessionId, userId: userId, waiterId: waiterId);
      final fullOrder = await orderRepo.getOrderById(order.id);
      if (fullOrder == null) throw Exception('Order not found');
      // TEMP-TIP-HIDDEN: tip dialog before PaymentScreen disabled.
      // Original kept the order in a `withTip` local so it could swap
      // for the tipped copy; with the flow hidden we go straight to
      // fullOrder.
      // var withTip = fullOrder;
      // if (mounted) {
      //   withTip = await applyTipIfEnabled(context, ref, fullOrder);
      //   if (withTip.tip != fullOrder.tip) {
      //     await orderRepo.updateOrder(withTip);
      //   }
      // }
      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PaymentScreen(order: fullOrder)));
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showErrorSnackBar(context, ref, 'Error: $e');
      }
    }
  }

  Future<void> _cancelOrder(Order order) async {
    final l10n = AppLocalizations.of(context)!;
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('cancel_order')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l10n.translate('confirm_cancel_order')} ${order.code}?'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                labelText: l10n.translate('cancellation_reason'),
                hintText: l10n.translate('enter_cancellation_reason'),
                border: const OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white),
            child: Text(l10n.translate('cancel_order')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final reason = reasonController.text.trim().isEmpty
          ? null
          : reasonController.text.trim();
      await orderRepo.updateOrderStatus(order.id, 'CANCELLED',
          cancellationReason: reason);
      if (mounted) {
        setState(() => _selectedOrder = null);
        SnackBarHelper.showSuccessSnackBar(
            context, ref, l10n.translate('order_canceled_successfully'));
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showErrorSnackBar(context, ref,
            '${l10n.translate('error_canceling_order')}: $e');
      }
    } finally {
      reasonController.dispose();
    }
  }

  Future<void> _deleteOrder(Order order) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('delete_order')),
        content: Text(
            '${l10n.translate('confirm_delete_order')} ${order.code}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white),
            child: Text(l10n.translate('delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      await orderRepo.deleteOrder(order.id);
      if (mounted) {
        setState(() => _selectedOrder = null);
        SnackBarHelper.showSuccessSnackBar(
            context, ref, l10n.translate('order_deleted_successfully'));
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showErrorSnackBar(
            context, ref, 'Error deleting order: $e');
      }
    }
  }

  Future<int> _getOrderItemCount(int orderId) async {
    final db = ref.read(databaseProvider);
    final items = await (db.select(db.orderProducts)
          ..where((tbl) => tbl.orderId.equals(orderId)))
        .get();
    return items.length;
  }

  Future<double> _getOrderTotal(int orderId) async {
    final db = ref.read(databaseProvider);
    final items = await (db.select(db.orderProducts)
          ..where((tbl) => tbl.orderId.equals(orderId)))
        .get();
    double total = 0;
    for (final item in items) {
      final comps = await (db.select(db.orderProductComponents)
            ..where((tbl) => tbl.orderProductId.equals(item.id)))
          .get();
      final compTotal =
          comps.fold<double>(0, (s, c) => s + c.price * c.quantity);
      total += (item.unitaryPrice + compTotal - item.manualDiscount) *
          item.quantity;
    }
    return total;
  }

  Future<List<Map<String, dynamic>>> _getOrderItemsWithDetails(
      int orderId) async {
    final db = ref.read(databaseProvider);
    final orderProducts = await (db.select(db.orderProducts)
          ..where((tbl) => tbl.orderId.equals(orderId)))
        .get();
    final items = <Map<String, dynamic>>[];
    for (final op in orderProducts) {
      final product = await (db.select(db.products)
            ..where((tbl) => tbl.id.equals(op.productId)))
          .getSingleOrNull();
      final orderComps = await (db.select(db.orderProductComponents)
            ..where((tbl) => tbl.orderProductId.equals(op.id)))
          .get();
      final components = <Map<String, dynamic>>[];
      for (final oc in orderComps) {
        final comp = await (db.select(db.components)
              ..where((tbl) => tbl.id.equals(oc.componentId)))
            .getSingleOrNull();
        if (comp != null) {
          components.add({
            'name': comp.name,
            'quantity': oc.quantity,
            'price': oc.price,
            'isSpecial': oc.isSpecial,
          });
        }
      }
      items.add({
        'orderProduct': op,
        'productName': product?.name ?? 'Unknown Product',
        'components': components,
      });
    }
    return items;
  }

  // ── External order helpers ──────────────────────────────────────────────────

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
      // Components carry their own unit price + quantity per the
      // OrderProductComponent contract; for the display layer we surface
      // each one's per-unit cost and sum them into a per-item components
      // total: Σ (component.price × component.quantity).
      final comps = <Map<String, dynamic>>[];
      double componentsPerItem = 0.0;
      for (final c in qi.components) {
        final comp = await (db.select(db.components)
              ..where((cc) => cc.id.equals(c.componentId)))
            .getSingleOrNull();
        if (comp == null) continue;
        final compPrice = comp.price;
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
        SnackBarHelper.showErrorSnackBar(context, ref, 'Error: $e');
        setState(() => _isConfirmingExternal = false);
      }
    }
  }

  Future<void> _cancelExternalOrder(ExternalQueueItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('reject_order')),
        content: Text(l10n.translate('cancel_order_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red[100],
              foregroundColor: Colors.red[900],
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
        SnackBarHelper.showSuccessSnackBar(context, ref,
            'Order ${item.orderCode} rejected');
        setState(() {
          _selectedExternalItem = null;
          _isConfirmingExternal = false;
        });
      } else {
        final err = ref.read(externalOrderProvider).error ??
            'Failed to reject order';
        SnackBarHelper.showErrorSnackBar(context, ref, err);
        setState(() => _isConfirmingExternal = false);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showErrorSnackBar(context, ref, 'Error: $e');
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
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PaymentScreen(order: fullOrder)));
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showErrorSnackBar(context, ref, 'Error: $e');
        setState(() => _isConfirmingExternal = false);
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final externalState = ref.watch(externalOrderProvider);
    final externalCount = externalState.items.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('confirm_order')),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pending_actions, size: 18),
                  const SizedBox(width: 6),
                  const Text('On Hold'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_download_outlined, size: 18),
                  const SizedBox(width: 6),
                  const Text('External'),
                  if (externalCount > 0) ...[
                    const SizedBox(width: 6),
                    _CountBadge(count: externalCount),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 0: On Hold ───────────────────────────────────────────────
          _buildOnHoldTab(l10n, isDark, cs),
          // ── Tab 1: External orders ───────────────────────────────────────
          _buildExternalTab(l10n, cs, externalState),
        ],
      ),
    );
  }

  // ── On-hold tab ─────────────────────────────────────────────────────────────

  Widget _buildOnHoldTab(
      AppLocalizations l10n, bool isDark, ColorScheme cs) {
    return Row(
      children: [
        // Left: search + list
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.translate('search_by_code'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor:
                        isDark ? Colors.grey[800] : Colors.white,
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Order>>(
                  future: _getOnHoldOrders(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                          child: Text('Error: ${snapshot.error}'));
                    }
                    final orders = snapshot.data ?? [];
                    if (orders.isEmpty) {
                      return _EmptyPane(
                        icon: Icons.inbox,
                        label: l10n.translate('no_onhold_orders'),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.all(8),
                      itemCount: orders.length,
                      itemBuilder: (context, i) {
                        final order = orders[i];
                        final isSelected =
                            _selectedOrder?.id == order.id;
                        return FutureBuilder<Map<String, dynamic>>(
                          future: Future.wait([
                            _getOrderItemCount(order.id),
                            _getOrderTotal(order.id),
                          ]).then((r) =>
                              {'itemCount': r[0], 'total': r[1]}),
                          builder: (context, ds) {
                            final itemCount =
                                ds.data?['itemCount'] as int? ?? 0;
                            final total =
                                ds.data?['total'] as double? ?? 0.0;
                            return _OnHoldCard(
                              order: order,
                              isSelected: isSelected,
                              itemCount: itemCount,
                              total: total,
                              l10n: l10n,
                              onTap: () => setState(() {
                                _selectedOrder = order;
                                _selectedExternalItem = null;
                                _selectedWaiter = null;
                                _waiterMissing = false;
                              }),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Right: details
        Expanded(
          flex: 4,
          child: _selectedOrder == null
              ? _EmptyPane(
                  icon: Icons.touch_app,
                  label: l10n.translate('select_order_to_confirm'),
                )
              : _buildOrderDetails(_selectedOrder!, l10n),
        ),
      ],
    );
  }

  // ── External tab ─────────────────────────────────────────────────────────────

  Widget _buildExternalTab(
      AppLocalizations l10n, ColorScheme cs, ExternalOrderState state) {
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text(
                      '${state.items.length} pending',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 20),
                      tooltip: l10n.translate('refresh'),
                      onPressed: state.isLoading
                          ? null
                          : () => ref
                              .read(externalOrderProvider.notifier)
                              .load(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: state.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : state.items.isEmpty
                        ? const _EmptyPane(
                            icon: Icons.cloud_off_outlined,
                            label: 'No pending external orders',
                            subtitle:
                                'DealUp / WhatsApp orders will appear here',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            itemCount: state.items.length,
                            itemBuilder: (context, i) {
                              final item = state.items[i];
                              final isSelected =
                                  _selectedExternalItem?.id == item.id;
                              return _ExternalItemCard(
                                key: ValueKey(item.id),
                                item: item,
                                isSelected: isSelected,
                                onTap: () => setState(() {
                                  _selectedExternalItem = item;
                                  _selectedOrder = null;
                                  _isConfirmingExternal = false;
                                }),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
        // Right: external order details
        Expanded(
          flex: 4,
          child: _selectedExternalItem == null
              ? const _EmptyPane(
                  icon: Icons.touch_app,
                  label: 'Select an order to review',
                )
              : _buildExternalOrderDetails(_selectedExternalItem!, l10n),
        ),
      ],
    );
  }

  // ── On-hold detail pane ─────────────────────────────────────────────────────

  Widget _buildOrderDetails(Order order, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        border:
            Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? cs.surfaceContainerHigh : Colors.orange.shade50,
            child: Row(
              children: [
                Icon(Icons.pending_actions,
                    color: Colors.orange[700], size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.code,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _TypeChip(type: order.type),
                          if (order.persons > 1) ...[
                            const SizedBox(width: 6),
                            Icon(Icons.people,
                                size: 14,
                                color: cs.onSurface.withValues(alpha: 0.6)),
                            const SizedBox(width: 2),
                            Text('${order.persons}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface
                                        .withValues(alpha: 0.6))),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Items
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _getOrderItemsWithDetails(order.id),
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
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final item = items[i];
                    final op = item['orderProduct'] as OrderProduct;
                    final name = item['productName'] as String;
                    final comps =
                        item['components'] as List<Map<String, dynamic>>;
                    final compLineTotal = comps.fold<double>(0.0,
                        (s, c) =>
                            s +
                            (c['price'] as double) *
                                (c['quantity'] as int));
                    final lineTotal =
                        (op.unitaryPrice + compLineTotal - op.manualDiscount) *
                            op.quantity;
                    return _ItemCard(
                      quantityLabel: '${op.quantity}x',
                      name: name,
                      trailingLabel: currencyFormatter.format(lineTotal),
                      chips: comps.map((c) {
                        return _CompChip(
                          label: '${c['quantity']}x ${c['name']}',
                          isSpecial: c['isSpecial'] as bool,
                        );
                      }).toList(),
                    );
                  },
                );
              },
            ),
          ),

          // Waiter
          if (order.type == 'DINE_IN') _buildWaiterSection(order),

          // Actions
          _buildOnHoldActions(order, l10n),
        ],
      ),
    );
  }

  Widget _buildWaiterSection(Order order) {
    final cs = Theme.of(context).colorScheme;
    final waitersAsync = ref.watch(_waitersProvider);

    if (order.waiterId != null) {
      return waitersAsync.maybeWhen(
        data: (waiters) {
          final w =
              waiters.where((w) => w.id == order.waiterId).firstOrNull;
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                const Icon(Icons.person, size: 18, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  w != null
                      ? '${w.firstName} ${w.lastName}'.trim()
                      : 'Waiter #${order.waiterId}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.green),
                ),
              ],
            ),
          );
        },
        orElse: () => const SizedBox.shrink(),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _waiterMissing ? cs.error : cs.outline,
          width: _waiterMissing ? 2 : 1,
        ),
        color: _waiterMissing
            ? cs.errorContainer.withValues(alpha: 0.15)
            : cs.surfaceContainerLow,
      ),
      child: waitersAsync.when(
        loading: () => const SizedBox(
            height: 40,
            child: Center(
                child: CircularProgressIndicator(strokeWidth: 2))),
        error: (_, __) => const Text('Failed to load waiters'),
        data: (waiters) => Row(
          children: [
            Icon(Icons.person_search,
                size: 18,
                color: _waiterMissing
                    ? cs.error
                    : cs.onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<Waiter>(
                  isExpanded: true,
                  isDense: true,
                  hint: Text(
                    _waiterMissing
                        ? 'Waiter required *'
                        : 'Assign waiter',
                    style: TextStyle(
                        fontSize: 13,
                        color: _waiterMissing
                            ? cs.error
                            : cs.onSurface.withValues(alpha: 0.6)),
                  ),
                  value: _selectedWaiter,
                  items: waiters.map((w) => DropdownMenuItem(
                        value: w,
                        child: Text(
                            '${w.firstName} ${w.lastName}'.trim(),
                            style: const TextStyle(fontSize: 13)),
                      )).toList(),
                  onChanged: (w) => setState(() {
                    _selectedWaiter = w;
                    _waiterMissing = false;
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnHoldActions(Order order, AppLocalizations l10n) {
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
                  onPressed: () => _confirmOrder(order),
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: Text(l10n.translate('confirm_order')),
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
                  onPressed: () => _confirmAndPay(order),
                  icon: const Icon(Icons.payment, size: 18),
                  label: Text(l10n.translate('confirm_and_pay')),
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _cancelOrder(order),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: Text(l10n.translate('cancel_order')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange[700],
                    side: BorderSide(color: Colors.orange.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _deleteOrder(order),
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: Text(l10n.translate('delete_order')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[700],
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _selectedOrder = null;
              _selectedWaiter = null;
              _waiterMissing = false;
            }),
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(l10n.translate('cancel')),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12)),
          ),
        ],
      ),
    );
  }

  // ── External order detail pane ──────────────────────────────────────────────

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
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            color: isDark ? cs.surfaceContainerHigh : Colors.deepPurple.shade50,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SourceIcon(source: item.source),
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
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _SourceLabel(source: item.source),
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
              backgroundColor: Colors.red[100],
              foregroundColor: Colors.red[900],
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

class _OnHoldCard extends StatelessWidget {
  final Order order;
  final bool isSelected;
  final int itemCount;
  final double total;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  const _OnHoldCard({
    required this.order,
    required this.isSelected,
    required this.itemCount,
    required this.total,
    required this.l10n,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelected ? 3 : 1,
      color: isSelected ? cs.primaryContainer : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? BorderSide(color: cs.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.orange[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.pending_actions,
                    color: Colors.orange[700]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.code,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        _TypeChip(type: order.type),
                        const SizedBox(width: 6),
                        Text('$itemCount items',
                            style: TextStyle(
                                fontSize: 11,
                                color:
                                    cs.onSurface.withValues(alpha: 0.6))),
                      ],
                    ),
                  ],
                ),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final fmt = ref.watch(currencyFormatterProvider);
                  return Text(fmt.format(total),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15));
                },
              ),
            ],
          ),
        ),
      ),
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
              _SourceIcon(source: item.source, size: 44),
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
                  _SourceLabel(source: item.source),
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
        bg = Colors.blue.shade100;
        label = 'Dine In';
        break;
      case 'TAKE_AWAY':
        bg = Colors.purple.shade100;
        label = 'Take Away';
        break;
      case 'DELIVERY':
        bg = Colors.teal.shade100;
        label = 'Delivery';
        break;
      default:
        bg = Colors.grey.shade200;
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

class _SourceIcon extends StatelessWidget {
  final String source;
  final double size;
  const _SourceIcon({required this.source, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (source.toUpperCase()) {
      'DEALUP' => (Colors.deepPurple, Icons.local_offer),
      'WHATSAPP' => (Colors.green[700]!, Icons.chat),
      _ => (Colors.blueGrey, Icons.cloud),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: color, size: size * 0.45),
    );
  }
}

class _SourceLabel extends StatelessWidget {
  final String source;
  const _SourceLabel({required this.source});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (source.toUpperCase()) {
      'DEALUP' => (Colors.deepPurple, 'DealUp'),
      'WHATSAPP' => (Colors.green[700]!, 'WhatsApp'),
      _ => (Colors.blueGrey as Color, source),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color)),
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

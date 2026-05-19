import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/presentation/paymen_screen/payment_screen.dart';
import 'package:caisse212/utils/app_localizations.dart';
import 'package:caisse212/utils/currency_formatter.dart';
import 'package:caisse212/utils/snackbar_helper.dart';

final _waitersProvider = FutureProvider.autoDispose<List<Waiter>>((ref) async {
  final db = ref.read(databaseProvider);
  return (db.select(db.waiters)..where((w) => w.isActive.equals(true))).get();
});

class OrderConfirmationScreen extends ConsumerStatefulWidget {
  const OrderConfirmationScreen({super.key});

  @override
  ConsumerState<OrderConfirmationScreen> createState() =>
      _OrderConfirmationScreenState();
}

class _OrderConfirmationScreenState
    extends ConsumerState<OrderConfirmationScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Order? _selectedOrder;
  Waiter? _selectedWaiter;
  bool _waiterMissing = false; // highlight picker when confirm pressed without waiter

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

      await orderRepo.updateOrderStatus(
        order.id,
        'PENDING',
        sessionId: sessionId,
        userId: userId,
        waiterId: waiterId,
      );

      if (mounted) {
        SnackBarHelper.showSuccessSnackBar(
          context,
          ref,
          'Order ${order.code} confirmed and sent to KDS',
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showErrorSnackBar(
          context,
          ref,
          'Error confirming order: $e',
        );
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

      await orderRepo.updateOrderStatus(
        order.id,
        'PENDING',
        sessionId: sessionId,
        userId: userId,
        waiterId: waiterId,
      );

      final fullOrder = await orderRepo.getOrderById(order.id);
      if (fullOrder == null) throw Exception('Order not found');

      if (mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PaymentScreen(order: fullOrder)),
        );
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
        SnackBarHelper.showErrorSnackBar(
            context, ref, '${l10n.translate('error_canceling_order')}: $e');
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
        content:
            Text('${l10n.translate('confirm_delete_order')} ${order.code}?'),
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
      // unitaryPrice already includes tva and has the pre-discount baked in.
      // componentTotal is per-unit, so it gets multiplied by quantity.
      // manualDiscount is per-item, so it also gets multiplied by quantity.
      final compTotal = comps.fold<double>(0, (s, c) => s + c.price * c.quantity);
      total += (item.unitaryPrice + compTotal - item.manualDiscount) * item.quantity;
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('confirm_order')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.translate('search_by_code'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: isDark ? Colors.grey[800] : Colors.white,
                isDense: true,
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
        ),
      ),
      body: Row(
        children: [
          // ── Left: order list ──────────────────────────────────────
          Expanded(
            flex: 5,
            child: FutureBuilder<List<Order>>(
              future: _getOnHoldOrders(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final orders = snapshot.data ?? [];
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          l10n.translate('no_onhold_orders'),
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: orders.length,
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    final isSelected = _selectedOrder?.id == order.id;
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
                        return _OrderCard(
                          order: order,
                          isSelected: isSelected,
                          itemCount: itemCount,
                          total: total,
                          l10n: l10n,
                          onTap: () => setState(() {
                            _selectedOrder = order;
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

          // ── Right: details + actions ──────────────────────────────
          Expanded(
            flex: 4,
            child: _selectedOrder == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.touch_app,
                            size: 64,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          l10n.translate('select_order_to_confirm'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  )
                : _buildOrderDetails(_selectedOrder!, l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetails(Order order, AppLocalizations l10n) {
    final cs = Theme.of(context).colorScheme;
    final currencyFormatter = ref.watch(currencyFormatterProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            color: isDark ? cs.surfaceContainerHigh : Colors.orange.shade50,
            child: Row(
              children: [
                Icon(Icons.pending_actions, color: Colors.orange[700], size: 28),
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
                            Icon(Icons.people, size: 14, color: cs.onSurface.withValues(alpha: 0.6)),
                            const SizedBox(width: 2),
                            Text('${order.persons}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface.withValues(alpha: 0.6))),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Items list ─────────────────────────────────────────
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
                    child: Text(
                      'No items',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5)),
                    ),
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
                    // unitaryPrice already contains tva and the pre-discount.
                    // componentTotal and manualDiscount are both per-item,
                    // so they scale with quantity.
                    final compLineTotal = comps.fold<double>(
                      0.0,
                      (s, c) => s + (c['price'] as double) * (c['quantity'] as int),
                    );
                    final lineTotal =
                        (op.unitaryPrice + compLineTotal - op.manualDiscount) *
                            op.quantity;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
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
                                    '${op.quantity}x',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: cs.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600)),
                                ),
                                Text(
                                  currencyFormatter.format(lineTotal),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                            if (comps.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Padding(
                                padding: const EdgeInsets.only(left: 42),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: comps.map((c) {
                                    final isSpecial = c['isSpecial'] as bool;
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isSpecial)
                                          Icon(Icons.star,
                                              size: 11,
                                              color: Colors.orange[600]),
                                        Text(
                                          '${c['quantity']}x ${c['name']}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: cs.onSurface
                                                  .withValues(alpha: 0.65)),
                                        ),
                                      ],
                                    );
                                  }).toList(),
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

          // ── Waiter picker (DINE_IN only) ───────────────────────
          if (order.type == 'DINE_IN')
            _buildWaiterSection(order),

          // ── Actions ────────────────────────────────────────────
          _buildActions(order, l10n),
        ],
      ),
    );
  }

  Widget _buildWaiterSection(Order order) {
    final cs = Theme.of(context).colorScheme;
    final waitersAsync = ref.watch(_waitersProvider);

    // Already assigned
    if (order.waiterId != null) {
      return waitersAsync.maybeWhen(
        data: (waiters) {
          final w =
              waiters.where((w) => w.id == order.waiterId).firstOrNull;
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      fontWeight: FontWeight.w600, color: Colors.green),
                ),
              ],
            ),
          );
        },
        orElse: () => const SizedBox.shrink(),
      );
    }

    // Need to pick
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
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (_, __) =>
            const Text('Failed to load waiters'),
        data: (waiters) => Row(
          children: [
            Icon(
              Icons.person_search,
              size: 18,
              color: _waiterMissing ? cs.error : cs.onSurface.withValues(alpha: 0.6),
            ),
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
                          : cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  value: _selectedWaiter,
                  items: waiters.map((w) {
                    return DropdownMenuItem(
                      value: w,
                      child: Text(
                        '${w.firstName} ${w.lastName}'.trim(),
                        style: const TextStyle(fontSize: 13),
                      ),
                    );
                  }).toList(),
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

  Widget _buildActions(Order order, AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
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
}

// ── Small helpers ──────────────────────────────────────────────────────────

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.isSelected,
    required this.itemCount,
    required this.total,
    required this.l10n,
    required this.onTap,
  });

  final Order order;
  final bool isSelected;
  final int itemCount;
  final double total;
  final AppLocalizations l10n;
  final VoidCallback onTap;

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
                child:
                    Icon(Icons.pending_actions, color: Colors.orange[700]),
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
                                color: cs.onSurface
                                    .withValues(alpha: 0.6))),
                      ],
                    ),
                  ],
                ),
              ),
              Consumer(
                builder: (context, ref, _) {
                  final fmt = ref.watch(currencyFormatterProvider);
                  return Text(
                    fmt.format(total),
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
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
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

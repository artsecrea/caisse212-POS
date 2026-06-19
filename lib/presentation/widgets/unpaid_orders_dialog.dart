import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart'
    show OnscreenKeyboardTextField;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';

/// Dialog opened from the empty [OrderPanel] to let the cashier pick an
/// existing unpaid order to resume.
///
/// Returns the chosen order's id via [Navigator.pop] (an `int`), or
/// `null` if the cashier dismissed without picking. The caller is
/// responsible for actually loading that order into the working cart
/// (the dialog stays pure-UI — no provider mutations).
class UnpaidOrdersDialog extends ConsumerStatefulWidget {
  const UnpaidOrdersDialog({super.key});

  @override
  ConsumerState<UnpaidOrdersDialog> createState() => _UnpaidOrdersDialogState();
}

class _UnpaidOrdersDialogState extends ConsumerState<UnpaidOrdersDialog> {
  // Filters
  String _typeFilter = 'ALL';
  int? _tableId;
  // Customer filter is split into two states:
  //   - `_customerQuery` is the live text in the search box, used to
  //     drive the autocomplete suggestion list.
  //   - `_selectedCustomerId` / `_selectedCustomerName` are set when the
  //     cashier picks a suggestion. Once picked, orders are filtered by
  //     that exact id (not by free-text on the name).
  String _customerQuery = '';
  int? _selectedCustomerId;
  String? _selectedCustomerName;
  final _customerController = TextEditingController();
  final _customerFocusNode = FocusNode();
  // Customers that match the live query — refreshed each keystroke.
  // Capped so the suggestion panel doesn't grow unboundedly.
  List<Customer> _customerMatches = const [];

  // Data
  List<AreaTable> _tables = const [];
  Map<int, AreaTable> _tablesById = const {};
  Map<int, Customer> _customersByOrderClientId = const {};
  Map<int, double> _totalsByOrderId = const {};
  List<Order> _orders = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _customerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final db = ref.read(databaseProvider);
    final tables = await (db.select(db.areaTables)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
    if (!mounted) return;
    setState(() {
      _tables = tables;
      _tablesById = {for (final t in tables) t.id: t};
    });
    await _query();
  }

  /// Live-search customers by name/phone/email substring. Called from
  /// the OnscreenKeyboardTextField's onChanged on every keystroke.
  Future<void> _refreshCustomerMatches(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.length < 2) {
      // Below the threshold we don't pop a suggestion list. Avoids
      // spamming the UI with hundreds of customers on a single keystroke.
      if (mounted) setState(() => _customerMatches = const []);
      return;
    }
    final db = ref.read(databaseProvider);
    // Pull a small candidate pool from the DB. Drift doesn't have a
    // case-insensitive LIKE without `customStatement` so we filter in
    // Dart after a coarse name pull.
    final all = await db.select(db.customers).get();
    final matches = <Customer>[];
    for (final c in all) {
      final fullName = '${c.firstName} ${c.lastName}'.toLowerCase();
      final phone = (c.phone ?? '').toLowerCase();
      final phoneNorm = (c.phoneNormalized ?? '').toLowerCase();
      final email = (c.email ?? '').toLowerCase();
      if (fullName.contains(needle) ||
          phone.contains(needle) ||
          phoneNorm.contains(needle) ||
          email.contains(needle)) {
        matches.add(c);
        if (matches.length >= 8) break;
      }
    }
    if (!mounted) return;
    setState(() => _customerMatches = matches);
  }

  Future<void> _query() async {
    setState(() => _isLoading = true);
    final orderRepo = ref.read(orderRepositoryProvider);
    final db = ref.read(databaseProvider);

    // When the cashier has picked a specific customer, filter orders
    // strictly by that id. Otherwise fall back to the free-text query
    // (lets them filter without committing to a specific row, e.g. all
    // customers named "Ali").
    final orders = await orderRepo.getUnpaidOrdersForResume(
      typeFilter: _typeFilter,
      tableId: _tableId,
      customerQuery: _selectedCustomerId != null
          ? null
          : (_customerQuery.isEmpty ? null : _customerQuery),
    );

    final filtered = _selectedCustomerId == null
        ? orders
        : orders.where((o) => o.clientId == _selectedCustomerId).toList();

    // Bulk-load customers + per-order totals up front so each list row
    // doesn't fire an N+1 query during build(). Plus totals now go
    // through the corrected `getOrderTotals` math (components + manual
    // discount + order-level discount %).
    final clientIds = filtered
        .where((o) => o.clientId != null)
        .map((o) => o.clientId!)
        .toSet();
    Map<int, Customer> byClientId = const {};
    if (clientIds.isNotEmpty) {
      final customers = await (db.select(db.customers)
            ..where((c) => c.id.isIn(clientIds)))
          .get();
      byClientId = {for (final c in customers) c.id: c};
    }

    final orderIds = filtered.map((o) => o.id).toList();
    final totalsByOrderId =
        await orderRepo.getOrderTotals(orderIds);

    if (!mounted) return;
    setState(() {
      _orders = filtered;
      _customersByOrderClientId = byClientId;
      _totalsByOrderId = totalsByOrderId;
      _isLoading = false;
    });
  }

  void _selectCustomer(Customer c) {
    final name = '${c.firstName} ${c.lastName}'.trim();
    setState(() {
      _selectedCustomerId = c.id;
      _selectedCustomerName = name.isEmpty ? (c.phone ?? '#${c.id}') : name;
      _customerController.text = _selectedCustomerName!;
      _customerQuery = _customerController.text;
      _customerMatches = const [];
    });
    _customerFocusNode.unfocus();
    _query();
  }

  void _clearSelectedCustomer() {
    setState(() {
      _selectedCustomerId = null;
      _selectedCustomerName = null;
      _customerController.clear();
      _customerQuery = '';
      _customerMatches = const [];
    });
    _query();
  }

  String _formatTimeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  String _orderTypeLabel(String type, AppLocalizations l10n) {
    switch (type) {
      case 'DINE_IN':
        return l10n.translate('dine_in');
      case 'TAKE_AWAY':
        return l10n.translate('take_away');
      case 'DELIVERY':
        return l10n.translate('delivery');
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.pending_actions, color: colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.translate('unpaid_orders'),
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Filters ───────────────────────────────────────────────
            _buildTypeFilter(l10n),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _buildTableFilter(l10n)),
                if (_tableId != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: l10n.translate('clear'),
                    onPressed: () {
                      setState(() => _tableId = null);
                      _query();
                    },
                    icon: const Icon(Icons.clear, size: 20),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            _buildCustomerFilter(l10n, colors),
            const SizedBox(height: 12),
            const Divider(height: 1),

            // ── List ──────────────────────────────────────────────────
            Expanded(child: _buildList(l10n, colors)),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeFilter(AppLocalizations l10n) {
    return SegmentedButton<String>(
      style: SegmentedButton.styleFrom(
        textStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      segments: [
        ButtonSegment(
            value: 'ALL', label: Text(l10n.translate('all_types'))),
        ButtonSegment(
            value: 'DINE_IN', label: Text(l10n.translate('dine_in'))),
        ButtonSegment(
            value: 'TAKE_AWAY',
            label: Text(l10n.translate('take_away'))),
        ButtonSegment(
            value: 'DELIVERY', label: Text(l10n.translate('delivery'))),
      ],
      selected: {_typeFilter},
      onSelectionChanged: (s) {
        setState(() => _typeFilter = s.first);
        _query();
      },
    );
  }

  Widget _buildTableFilter(AppLocalizations l10n) {
    return DropdownButtonFormField<int?>(
      value: _tableId,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.table_restaurant, size: 20),
        labelText: l10n.translate('table'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        isDense: true,
      ),
      items: [
        DropdownMenuItem<int?>(
          value: null,
          child: Text(l10n.translate('all_tables')),
        ),
        for (final t in _tables)
          DropdownMenuItem<int?>(
            value: t.id,
            child: Text(t.name),
          ),
      ],
      onChanged: (value) {
        setState(() => _tableId = value);
        _query();
      },
    );
  }

  Widget _buildCustomerFilter(AppLocalizations l10n, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnscreenKeyboardTextField(
          controller: _customerController,
          focusNode: _customerFocusNode,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.person_search, size: 20),
            labelText: l10n.translate('customer'),
            hintText: l10n.translate('search_by_name_phone_email'),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 12),
            isDense: true,
            suffixIcon: (_customerController.text.isNotEmpty)
                ? IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: _clearSelectedCustomer,
                  )
                : null,
          ),
          onChanged: (value) async {
            // Editing the field clears any prior pick — the cashier is
            // searching again. Keeps the model consistent: either a
            // suggestion is selected, or the field is free-text.
            if (_selectedCustomerId != null) {
              _selectedCustomerId = null;
              _selectedCustomerName = null;
            }
            setState(() => _customerQuery = value);
            await _refreshCustomerMatches(value);
            // Don't re-query orders on every keystroke when matches are
            // shown — the cashier should pick a suggestion first. Only
            // re-query when the matches list is empty (e.g. nothing
            // matches, or below the threshold) so free-text filtering
            // still works.
            if (_customerMatches.isEmpty) await _query();
          },
        ),
        // Suggestion list — only shown while the cashier is typing AND
        // there are matches. Stays compact so it doesn't push the order
        // list off-screen.
        if (_customerMatches.isNotEmpty) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _customerMatches.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = _customerMatches[i];
                final name =
                    '${c.firstName} ${c.lastName}'.trim();
                final subtitle = [
                  if ((c.phone ?? '').isNotEmpty) c.phone!,
                  if ((c.email ?? '').isNotEmpty) c.email!,
                ].join(' · ');
                return InkWell(
                  onTap: () => _selectCustomer(c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: colors.primaryContainer,
                          child: Text(
                            (name.isNotEmpty ? name[0] : '#').toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name.isEmpty
                                    ? (c.phone ?? '#${c.id}')
                                    : name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                              if (subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildList(AppLocalizations l10n, ColorScheme colors) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox,
                size: 48,
                color: colors.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text(
              l10n.translate('no_orders_found'),
              style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }

    final currency = ref.read(currencySymbolProvider);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _orders.length,
      itemBuilder: (context, i) {
        final order = _orders[i];
        final table = order.tableId == null ? null : _tablesById[order.tableId!];
        final customer = order.clientId == null
            ? null
            : _customersByOrderClientId[order.clientId!];

        final metaParts = <String>[
          _orderTypeLabel(order.type, l10n),
          if (table != null) table.name,
          if (customer != null)
            '${customer.firstName} ${customer.lastName}'.trim(),
        ].where((s) => s.trim().isNotEmpty).toList();

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          elevation: 0,
          color: colors.surfaceContainerLow,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => Navigator.of(context).pop(order.id),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(order.status)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      order.code,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _statusColor(order.status),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          metaParts.join(' · '),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.access_time,
                                size: 11,
                                color: colors.onSurface
                                    .withValues(alpha: 0.5)),
                            const SizedBox(width: 3),
                            Text(
                              _formatTimeAgo(order.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: colors.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyFormatter.formatWithCurrency(
                        _totalsByOrderId[order.id] ?? 0.0, currency),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right,
                      color: colors.onSurface.withValues(alpha: 0.4)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'ONHOLD':
        return Colors.orange.shade700;
      case 'PENDING':
        return Colors.blue.shade700;
      case 'PREPARING':
        return Colors.deepPurple.shade400;
      case 'READY':
        return Colors.teal.shade700;
      case 'DELIVERED':
        return Colors.green.shade700;
      default:
        return Colors.grey.shade700;
    }
  }
}

import 'dart:async';
// filepath: /home/artecrea/StudioProjects/posecrea/lib/presentation/widgets/orders_management_screen.dart

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_elevation_provider.dart';
import '../../utils/admin_auth.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/customer_display.dart';

import 'package:data_table_2/data_table_2.dart';
import '../../domain/models/order_models.dart';
import '../../providers/order_provider.dart';
import '../../services/local_order_service.dart';
import '../../providers/sync_manager_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/floor_repository.dart';
import '../../providers/settings_provider.dart';
import '../../data/database/app_database.dart';
import '../../services/permission_service.dart';
import 'admin_mode_chip.dart';
import 'delivery_fee_totals_chip.dart';
import 'permission_guard.dart';
import 'order_details_dialog.dart';
import 'refund_dialog.dart';
import 'order_tag_widgets.dart';
import '../../domain/models/order_tag_codec.dart';
import 'order_refunds_panel.dart';
import 'waiter_settlement_dialog.dart';
import '../../utils/snackbar_helper.dart';
import '../paymen_screen/payment_screen.dart';
import './adaptive_text_field.dart';
// TEMP-TIP-HIDDEN: restore together with the commented block in _payOrder.
// import 'tip_flow.dart';

class OrdersManagementScreen extends ConsumerStatefulWidget {
  const OrdersManagementScreen({super.key});

  @override
  ConsumerState<OrdersManagementScreen> createState() => _OrdersManagementScreenState();
}

class _OrdersManagementScreenState
    extends ConsumerState<OrdersManagementScreen> {
  // Filters
  String _statusFilter = 'ALL';
  // ALL | DINE_IN | TAKE_AWAY | DELIVERY — matches the values stored in
  // orders.type. ALL skips the SQL where clause.
  String _typeFilter = 'ALL';
  // When true, hide orders whose total is fully paid (totalPaid >= total).
  // Applied as an in-memory post-filter in the repo because it requires
  // comparing computed sums (tickets vs order line items).
  bool _unpaidOnly = false;
  // Order tags: ANY of these, plus untagged orders when [_untaggedOnly].
  Set<int> _tagFilter = {};
  bool _untaggedOnly = false;
  // Filter orders to those whose `orders.waiterId` matches. null = no filter
  // (show all). Drives the dropdown above the table and is the trigger for
  // the "Settle waiter" affordance in Phase 3.
  int? _waiterFilter;
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  int? _selectedCustomerId;
  int? _selectedTableId;
  String? _selectedTableName;

  // Pagination
  int _currentPage = 0;
  int _rowsPerPage = 10;

  // Paginated data
  PaginatedOrders? _paginatedOrders;
  bool _isLoading = true;
  String? _errorMessage;

  // Sorting
  String _sortColumn = 'createdAt';
  bool _sortAscending = false;

  // Grouping
  String _groupBy = 'none'; // none, status, date

  // Sync state
  bool _isSyncing = false;

  // View mode: my orders vs all orders (requires tenant password)
  bool _showAllOrders = false;

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customerSearchController = TextEditingController();
  final FocusNode _customerSearchFocusNode = FocusNode();
  String? _selectedCustomerName;

  /// Persistent ScrollController for the DataTable2 in `_buildOrdersTable`.
  /// MUST live in state — allocating a fresh ScrollController on every
  /// `build()` leaves the previous one's listeners stranded on the
  /// InheritedNotifier (DataTable2's internal scroll-position widgets
  /// hold refs to it), which trips
  /// `InheritedElement.debugDeactivated`'s `_dependents.isEmpty`
  /// assertion the next time the tree rebuilds — and then DataTable2's
  /// intrinsic-size pass goes haywire and overflows by ~100k pixels.
  /// Symptom showed up specifically when toggling admin mode because
  /// `setState(() => _showAllOrders = true)` was the most common
  /// rebuild source.
  final ScrollController _ordersTableScrollController = ScrollController();

  // Customers list for filter (search results)
  List<Customer> _customers = [];

  int? _autoOpenOrderId;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map && args['orderId'] != null && _autoOpenOrderId == null) {
      _autoOpenOrderId = args['orderId'] as int;
      // Wait for the first frame and orders to load, then show the detail.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoOpenOrder());
    }
  }

  Future<void> _tryAutoOpenOrder() async {
    if (_autoOpenOrderId == null) return;
    final targetId = _autoOpenOrderId!;
    _autoOpenOrderId = null;

    // The orders may still be loading — wait up to 3 s.
    for (var i = 0; i < 30 && _isLoading; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    if (!mounted) return;

    try {
      final order =
          await ref.read(orderRepositoryProvider).getOrderRow(targetId);
      if (order != null && mounted) _showOrderDetails(order);
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customerSearchController.dispose();
    _customerSearchFocusNode.dispose();
    _ordersTableScrollController.dispose();
    super.dispose();
  }

  Future<void> _searchCustomersInDb(String query) async {
    if (query.length < 3) {
      setState(() => _customers = []);
      return;
    }
    try {
      final lowerQuery = query.toLowerCase();
      final allCustomers = await ref.read(customerServiceProvider).getAll();
      final filtered = allCustomers.where((c) {
        final fullName = c.displayLabel.toLowerCase();
        final phone = c.phone?.toLowerCase() ?? '';
        final phoneNorm = c.phoneNormalized?.toLowerCase() ?? '';
        final email = c.email?.toLowerCase() ?? '';
        return fullName.contains(lowerQuery) ||
            phone.contains(lowerQuery) ||
            phoneNorm.contains(lowerQuery) ||
            email.contains(lowerQuery);
      }).toList();
      if (mounted) setState(() => _customers = filtered);
    } catch (e) {
      // Ignore errors
    }
  }

  // Each load's ticket: a page or filter clicked before the previous load
  // returns must not be overwritten by it.
  int _loadSeq = 0;

  Future<void> _loadOrders() async {
    final seq = ++_loadSeq;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final currentUser = ref.read(currentUserProvider);
      // Admin elevation bypasses both the "my orders" cashier filter and
      // any session scoping — when an admin opens this screen they see
      // every order across every session + every cashier, regardless of
      // the _showAllOrders toggle state. The toggle remains the affordance
      // for non-admin cashiers who want to peek at their colleagues'
      // orders within their own session scope.
      final isAdmin = ref.read(adminElevationProvider) != null;
      // What is still owed is the floor's business, not one cashier's.
      // Whoever is on the till next has to be able to find an open order,
      // add to it and settle it — including one raised in an earlier session
      // by somebody who has since gone home, which is exactly the case the
      // "my orders" scope used to hide. That scope exists to keep a cashier's
      // *history* out of a colleague's view, so it is lifted only while the
      // list is restricted to what has not been paid.
      //
      // Nothing else is relaxed: the list stays unscoped by session (this
      // screen never passes sessionId), and the full history still needs the
      // admin credentials that `_toggleShowAllOrders` prompts for.
      final scopeToSelf = !isAdmin && !_showAllOrders && !_unpaidOnly;
      final result = await orderRepo.getPaginatedOrdersWithFullDetails(
        page: _currentPage,
        pageSize: _rowsPerPage,
        statusFilter: _statusFilter,
        typeFilter: _typeFilter,
        unpaidOnly: _unpaidOnly,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        customerId: _selectedCustomerId,
        cashierId: scopeToSelf ? currentUser?.id : null,
        tableId: _selectedTableId,
        waiterId: _waiterFilter,
        startDate: _startDate,
        endDate: _endDate,
        sortColumn: _sortColumn,
        sortAscending: _sortAscending,
        tagIds: _tagFilter,
        untagged: _untaggedOnly,
      );

      if (mounted && seq == _loadSeq) {
        setState(() {
          _paginatedOrders = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && seq == _loadSeq) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _onFilterChanged() {
    _currentPage = 0;
    _loadOrders();
  }

  void _onPageChanged(int newPage) {
    _currentPage = newPage;
    _loadOrders();
  }

  void _onSort(String column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
    });
    _loadOrders();
  }

  /// Toggle between "my orders" and "all orders".
  /// Switching to "all orders" requires admin credentials.
  /// Switching back to "my orders" is always allowed.
  Future<void> _toggleShowAllOrders() async {
    final l10n = AppLocalizations.of(context)!;

    if (_showAllOrders) {
      // Switching back to my orders — no auth needed
      setState(() => _showAllOrders = false);
      _currentPage = 0;
      _loadOrders();
      return;
    }

    // Admin already elevated this session — no need to re-prompt.
    if (ref.read(adminElevationProvider) != null) {
      setState(() => _showAllOrders = true);
      _currentPage = 0;
      _loadOrders();
      return;
    }

    final admin = await showAdminCredentialDialog(
      context,
      ref,
      title: l10n.translate('view_all_orders'),
      description: l10n.translate('enter_admin_credentials'),
    );
    if (admin == null) return;

    setState(() => _showAllOrders = true);
    _currentPage = 0;
    _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencySymbolProvider);
    final l10n = AppLocalizations.of(context)!;
    // Admin mode widens the order scope (every session, every cashier), so
    // toggling it from this screen's chip must re-run the query, not just
    // repaint the rows already loaded.
    ref.listen(adminElevationProvider, (prev, next) {
      if ((prev == null) == (next == null)) return;
      _currentPage = 0;
      _loadOrders();
    });

    return Scaffold(
      appBar: _buildAppBar(l10n),
      // Single view. The online/external queue used to be a second tab here,
      // but it belongs with the confirm-order flow — the cashier accepts an
      // online order and rings it up, which is what that screen is for. This
      // page is the local order history.
      body: Column(
        children: [
          _buildFiltersBar(l10n),
          _buildSecondaryFiltersBar(l10n),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorView(_errorMessage!, l10n)
                    : _paginatedOrders == null ||
                            _paginatedOrders!.orders.isEmpty
                        ? _buildEmptyView(l10n)
                        : _groupBy == 'none'
                            ? _buildOrdersTable(currency, l10n)
                            : _buildGroupedView(currency, l10n),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n) {
    final isOnline = ref.watch(networkStateProvider);
    final syncState = ref.watch(syncManagerProvider);

    return AppBar(
      title: Row(
        children: [
          Text(l10n.translate('orders_management')),
          if (_paginatedOrders != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_paginatedOrders!.totalCount} ${l10n.translate('orders')}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        const AdminModeChip(),
        // Sync indicator
        if (_isSyncing || syncState.isSyncing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
            ),
          ),
        // Online/Offline indicator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Tooltip(
            message: isOnline ? l10n.translate('online') : l10n.translate('offline'),
            child: Icon(
              isOnline ? Icons.wifi : Icons.wifi_off,
              color: isOnline ? Colors.green : Colors.red,
              size: 20,
            ),
          ),
        ),
        // My orders / All orders toggle
        Tooltip(
          message: _showAllOrders
              ? l10n.translate('showing_all_orders')
              : l10n.translate('showing_my_orders'),
          child: TextButton.icon(
            onPressed: _toggleShowAllOrders,
            icon: Icon(
              _showAllOrders ? Icons.people : Icons.person,
              size: 20,
              color: _showAllOrders
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
            label: Text(
              _showAllOrders
                  ? l10n.translate('all_orders')
                  : l10n.translate('my_orders'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _showAllOrders
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            style: TextButton.styleFrom(
              backgroundColor: _showAllOrders
                  ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5)
                  : null,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: _showAllOrders
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Search by code button
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: _showSearchByCodeDialog,
          tooltip: l10n.translate('search_order_by_code'),
        ),
        // View pending operations queue
        PermissionIconButton(
          permission: Permissions.viewPendingOperations,
          onPressed: _showPendingOperationsDialog,
          icon: const Icon(Icons.pending_actions),
          tooltip: l10n.translate('view_pending_operations'),
        ),
        // Sync all button
        PermissionIconButton(
          permission: Permissions.syncAll,
          onPressed: (_isSyncing || syncState.isSyncing) ? () {} : _syncAll,
          icon: const Icon(Icons.cloud_sync),
          tooltip: l10n.translate('sync_all'),
        ),
        // Refresh
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadOrders,
          tooltip: l10n.translate('refresh'),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFiltersBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          // Three breakpoints:
          //   wide  ≥ 1000 px → single row, full controls.
          //   med   600–999  → search on top, 3 controls below.
          //   narrow< 600    → fully stacked, each control gets its own row.
          if (width >= 1000) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 3, child: _buildSearchField(l10n)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _buildStatusDropdown(l10n)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _buildCustomerDropdown(l10n)),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: _buildTableFilterField(l10n)),
                const SizedBox(width: 12),
                _buildDateRangeButton(l10n),
                const SizedBox(width: 12),
                const DeliveryFeeTotalsChip(),
                if (_hasAnyFilter()) ...[
                  const SizedBox(width: 4),
                  _buildResetAllButton(l10n),
                ],
              ],
            );
          }
          if (width >= 600) {
            return Column(
              children: [
                _buildSearchField(l10n),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildStatusDropdown(l10n)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildCustomerDropdown(l10n)),
                    const SizedBox(width: 10),
                    Expanded(child: _buildTableFilterField(l10n)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _buildDateRangeButton(l10n)),
                    const SizedBox(width: 8),
                    const DeliveryFeeTotalsChip(),
                    if (_hasAnyFilter()) ...[
                      const SizedBox(width: 8),
                      _buildResetAllButton(l10n),
                    ],
                  ],
                ),
              ],
            );
          }
          // Narrow — fully stacked.
          return Column(
            children: [
              _buildSearchField(l10n),
              const SizedBox(height: 8),
              _buildStatusDropdown(l10n),
              const SizedBox(height: 8),
              _buildCustomerDropdown(l10n),
              const SizedBox(height: 8),
              _buildTableFilterField(l10n),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildDateRangeButton(l10n)),
                  if (_hasAnyFilter()) ...[
                    const SizedBox(width: 8),
                    _buildResetAllButton(l10n),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: AlignmentDirectional.centerStart,
                child: DeliveryFeeTotalsChip(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchField(AppLocalizations l10n) {
    return AdaptiveKeyboardTextField(
      controller: _searchController,
      decoration: InputDecoration(
        hintText: l10n.translate('search_by_code_username_customer'),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  _searchQuery = '';
                  _onFilterChanged();
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      ),
      onSubmitted: (value) {
        _searchQuery = value;
        _onFilterChanged();
      },
    );
  }

  Widget _buildDateRangeButton(AppLocalizations l10n) {
    final has = _startDate != null || _endDate != null;
    return OutlinedButton.icon(
      onPressed: _showDateRangePicker,
      icon: Icon(Icons.date_range, size: 18, color: has ? null : Theme.of(context).colorScheme.onSurfaceVariant),
      label: Text(
        _getDateRangeText(l10n),
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        side: BorderSide(
          color: has
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _buildResetAllButton(AppLocalizations l10n) {
    return Tooltip(
      message: l10n.translate('clear_all_filters'),
      child: OutlinedButton.icon(
        onPressed: _resetAllFilters,
        icon: const Icon(Icons.filter_alt_off, size: 18),
        label: Text(l10n.translate('reset'),
            style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          foregroundColor: Colors.red[700],
          side: BorderSide(color: Colors.red.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  bool _hasAnyFilter() {
    return _statusFilter != 'ALL' ||
        _typeFilter != 'ALL' ||
        _unpaidOnly ||
        _tagFilter.isNotEmpty ||
        _untaggedOnly ||
        _searchQuery.isNotEmpty ||
        _selectedCustomerId != null ||
        _selectedTableId != null ||
        _waiterFilter != null ||
        _startDate != null ||
        _endDate != null;
  }

  void _resetAllFilters() {
    setState(() {
      _statusFilter = 'ALL';
      _typeFilter = 'ALL';
      _unpaidOnly = false;
      _tagFilter = {};
      _untaggedOnly = false;
      _searchQuery = '';
      _searchController.clear();
      _selectedCustomerId = null;
      _selectedCustomerName = null;
      _customerSearchController.clear();
      _selectedTableId = null;
      _selectedTableName = null;
      _waiterFilter = null;
      _startDate = null;
      _endDate = null;
      _customers = [];
    });
    _onFilterChanged();
  }

  Widget _buildTableFilterField(AppLocalizations l10n) {
    return InkWell(
      onTap: _showTablePicker,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.translate('filter_by_table'),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          prefixIcon: const Icon(Icons.table_restaurant, size: 20),
          suffixIcon: _selectedTableId != null
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    setState(() {
                      _selectedTableId = null;
                      _selectedTableName = null;
                    });
                    _onFilterChanged();
                  },
                )
              : const Icon(Icons.arrow_drop_down),
          isDense: true,
        ),
        child: Text(
          _selectedTableName ?? l10n.translate('all_tables'),
          style: TextStyle(
            color: _selectedTableId != null
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            fontSize: 14,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Future<void> _showTablePicker() async {
    final l10n = AppLocalizations.of(context)!;
    final tables = await ref.read(floorRepositoryProvider).allTables();
    if (!mounted) return;
    final selectedId = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        String search = '';
        return StatefulBuilder(builder: (ctx, setLocal) {
          final filtered = search.isEmpty
              ? tables
              : tables
                  .where((t) =>
                      t.name.toLowerCase().contains(search.toLowerCase()))
                  .toList();
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.table_restaurant),
                const SizedBox(width: 8),
                Text(l10n.translate('filter_by_table')),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AdaptiveKeyboardTextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: l10n.translate('search_tables'),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                    onChanged: (v) => setLocal(() => search = v),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: tables.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child:
                                Text(l10n.translate('no_tables_available')),
                          )
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.public),
                                title: Text(l10n.translate('all_tables'),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                                onTap: () =>
                                    Navigator.of(ctx).pop<int?>(null),
                                selected: _selectedTableId == null,
                              ),
                              const Divider(height: 1),
                              ...filtered.map((t) => ListTile(
                                    leading:
                                        const Icon(Icons.table_restaurant),
                                    title: Text(t.name),
                                    subtitle: Text(
                                        '${l10n.translate('capacity')}: ${t.capacity}'),
                                    onTap: () =>
                                        Navigator.of(ctx).pop<int?>(t.id),
                                    selected: _selectedTableId == t.id,
                                  )),
                            ],
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop<int?>(-1),
                child: Text(l10n.translate('cancel')),
              ),
            ],
          );
        });
      },
    );
    if (selectedId == -1) return; // cancelled
    if (!mounted) return;
    setState(() {
      _selectedTableId = selectedId;
      _selectedTableName = selectedId == null
          ? null
          : tables.firstWhere((t) => t.id == selectedId).name;
    });
    _onFilterChanged();
  }

  Widget _buildSecondaryFiltersBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border:
            Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 700;
          final groupBySegment = SegmentedButton<String>(
            segments: [
              ButtonSegment(
                  value: 'none',
                  label: Text(l10n.translate('none'),
                      style: const TextStyle(fontSize: 12))),
              ButtonSegment(
                  value: 'status',
                  label: Text(l10n.translate('status'),
                      style: const TextStyle(fontSize: 12))),
              ButtonSegment(
                  value: 'date',
                  label: Text(l10n.translate('date'),
                      style: const TextStyle(fontSize: 12))),
            ],
            selected: {_groupBy},
            onSelectionChanged: (selected) {
              setState(() => _groupBy = selected.first);
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
          final rowsPerPageDropdown = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${l10n.translate('rows_per_page')}: ',
                  style: const TextStyle(fontSize: 12)),
              DropdownButton<int>(
                value: _rowsPerPage,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 10, child: Text('10')),
                  DropdownMenuItem(value: 25, child: Text('25')),
                  DropdownMenuItem(value: 50, child: Text('50')),
                  DropdownMenuItem(value: 100, child: Text('100')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _rowsPerPage = value;
                    _currentPage = 0;
                    _loadOrders();
                  }
                },
              ),
            ],
          );
          final quickChips = Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _buildQuickFilterChips(l10n),
          );

          if (isNarrow) {
            // Compact two-row layout: chips on top, controls below.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                quickChips,
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          Text('${l10n.translate('group_by')}: ',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                          groupBySegment,
                        ]),
                      ),
                    ),
                    rowsPerPageDropdown,
                  ],
                ),
              ],
            );
          }

          // Wide layout — one row.
          return Row(
            children: [
              Text('${l10n.translate('group_by')}: ',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              groupBySegment,
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: false,
                  child: quickChips,
                ),
              ),
              const SizedBox(width: 12),
              rowsPerPageDropdown,
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildQuickFilterChips(AppLocalizations l10n) {
    return [
      FilterChip(
        label: Text(l10n.translate('today'),
            style: const TextStyle(fontSize: 11)),
        selected: _isRangeToday(),
        onSelected: (selected) {
          if (selected) {
            final now = DateTime.now();
            _startDate = DateTime(now.year, now.month, now.day);
            _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          } else {
            _startDate = null;
            _endDate = null;
          }
          _onFilterChanged();
        },
      ),
      FilterChip(
        label: Text(l10n.translate('yesterday'),
            style: const TextStyle(fontSize: 11)),
        selected: _isRangeYesterday(),
        onSelected: (selected) {
          if (selected) {
            final y =
                DateTime.now().subtract(const Duration(days: 1));
            _startDate = DateTime(y.year, y.month, y.day);
            _endDate = DateTime(y.year, y.month, y.day, 23, 59, 59);
          } else {
            _startDate = null;
            _endDate = null;
          }
          _onFilterChanged();
        },
      ),
      FilterChip(
        label: Text(l10n.translate('this_week'),
            style: const TextStyle(fontSize: 11)),
        selected: _isRangeThisWeek(),
        onSelected: (selected) {
          if (selected) {
            final now = DateTime.now();
            final start =
                now.subtract(Duration(days: now.weekday - 1));
            _startDate = DateTime(start.year, start.month, start.day);
            _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          } else {
            _startDate = null;
            _endDate = null;
          }
          _onFilterChanged();
        },
      ),
      FilterChip(
        label: Text(l10n.translate('this_month'),
            style: const TextStyle(fontSize: 11)),
        selected: _isRangeThisMonth(),
        onSelected: (selected) {
          if (selected) {
            final now = DateTime.now();
            _startDate = DateTime(now.year, now.month, 1);
            _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
          } else {
            _startDate = null;
            _endDate = null;
          }
          _onFilterChanged();
        },
      ),
      FilterChip(
        label: Text(l10n.translate('on_hold'),
            style: const TextStyle(fontSize: 11)),
        selected: _statusFilter == 'ONHOLD',
        onSelected: (selected) {
          _statusFilter = selected ? 'ONHOLD' : 'ALL';
          _onFilterChanged();
        },
      ),
      FilterChip(
        label: Text(l10n.translate('canceled'),
            style: const TextStyle(fontSize: 11)),
        selected: _statusFilter == 'CANCELED',
        onSelected: (selected) {
          _statusFilter = selected ? 'CANCELED' : 'ALL';
          _onFilterChanged();
        },
      ),
      // Type filters — exclusive across DINE_IN / TAKE_AWAY / DELIVERY.
      // Selecting one clears the others; deselecting reverts to ALL.
      // Same chip pattern as the status filters above so the visual
      // grammar stays consistent across the toolbar.
      FilterChip(
        label: Text(l10n.translate('dine_in'),
            style: const TextStyle(fontSize: 11)),
        selected: _typeFilter == 'DINE_IN',
        onSelected: (selected) {
          _typeFilter = selected ? 'DINE_IN' : 'ALL';
          _onFilterChanged();
        },
      ),
      FilterChip(
        label: Text(l10n.translate('take_away'),
            style: const TextStyle(fontSize: 11)),
        selected: _typeFilter == 'TAKE_AWAY',
        onSelected: (selected) {
          _typeFilter = selected ? 'TAKE_AWAY' : 'ALL';
          _onFilterChanged();
        },
      ),
      FilterChip(
        label: Text(l10n.translate('delivery'),
            style: const TextStyle(fontSize: 11)),
        selected: _typeFilter == 'DELIVERY',
        onSelected: (selected) {
          _typeFilter = selected ? 'DELIVERY' : 'ALL';
          _onFilterChanged();
        },
      ),
      // Unpaid filter — independent toggle, not exclusive with the
      // others. Hides orders whose tickets already cover the total.
      FilterChip(
        label: Text(l10n.translate('unpaid'),
            style: const TextStyle(fontSize: 11)),
        selected: _unpaidOnly,
        onSelected: (selected) {
          _unpaidOnly = selected;
          _onFilterChanged();
        },
      ),
      // Order tags — ANY of the chosen ones, and/or untagged orders.
      FilterChip(
        avatar: const Icon(Icons.label_outline, size: 16),
        label: Text(
            _tagFilter.isEmpty && !_untaggedOnly
                ? l10n.translate('order_tags')
                : '${l10n.translate('order_tags')} (${_tagFilter.length + (_untaggedOnly ? 1 : 0)})',
            style: const TextStyle(fontSize: 11)),
        selected: _tagFilter.isNotEmpty || _untaggedOnly,
        onSelected: (_) => _pickTagFilter(l10n),
      ),
      // Waiter dropdown — independent filter. Driving state for the
      // "Settle waiter" affordance which appears only when a single
      // waiter is selected.
      _buildWaiterFilterDropdown(l10n),
      // Settlement chip appears only when a waiter is picked. Opens the
      // settlement dialog (cash-only batch pay + slip print).
      if (_waiterFilter != null) _buildSettleWaiterButton(l10n),
    ];
  }

  Future<void> _pickTagFilter(AppLocalizations l10n) async {
    final chosen = <int>{..._tagFilter};
    var untagged = _untaggedOnly;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Consumer(builder: (ctx, ref, _) {
        final catalogue = ref.watch(orderTagsProvider).valueOrNull ?? const [];
        return StatefulBuilder(builder: (ctx, setLocal) {
          return AlertDialog(
            title: Text(l10n.translate('order_tags_filter')),
            content: SizedBox(
              width: 420,
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in catalogue)
                  FilterChip(
                    label: Text(t.label,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    avatar: CircleAvatar(
                        backgroundColor: orderTagColor(ctx, t), radius: 7),
                    selected: chosen.contains(t.id),
                    onSelected: (on) => setLocal(
                        () => on ? chosen.add(t.id) : chosen.remove(t.id)),
                  ),
                FilterChip(
                  label: Text(l10n.translate('order_tags_untagged')),
                  selected: untagged,
                  onSelected: (on) => setLocal(() => untagged = on),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => setLocal(() {
                  chosen.clear();
                  untagged = false;
                }),
                child: Text(l10n.translate('order_tags_clear')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.translate('apply')),
              ),
            ],
          );
        });
      }),
    );
    if (ok != true) return;
    _tagFilter = chosen;
    _untaggedOnly = untagged;
    _onFilterChanged();
  }

  /// Re-tag a saved order. Allowed whatever its session or Z: tags move no
  /// money.
  Future<void> _tagOrder(Order order) async {
    final ids = await showOrderTagPicker(
        context: context, ref: ref, initial: parseTagIds(order.tagIds));
    if (ids == null || !mounted) return;
    await ref.read(orderServiceProvider).setTags(order.id, ids);
    _loadOrders();
  }

  Widget _buildSettleWaiterButton(AppLocalizations l10n) {
    final waitersAsync = ref.watch(waitersProvider);
    return waitersAsync.maybeWhen(
      data: (waiters) {
        final w = waiters.firstWhere(
          (x) => x.id == _waiterFilter,
          orElse: () => waiters.first,
        );
        if (w.id != _waiterFilter) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final label = (w.lastName != null && w.lastName!.isNotEmpty)
            ? '${w.firstName} ${w.lastName}'
            : w.firstName;
        return SizedBox(
          height: 32,
          child: ElevatedButton.icon(
            onPressed: () async {
              final settled = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => WaiterSettlementDialog(
                  waiterId: w.id,
                  waiterName: label,
                ),
              );
              if (settled == true && mounted) _loadOrders();
            },
            icon: const Icon(Icons.payments, size: 14),
            label: Text(
              l10n.translate('settle_waiter'),
              style: const TextStyle(fontSize: 11),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(fontSize: 11),
              minimumSize: const Size(0, 32),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _buildWaiterFilterDropdown(AppLocalizations l10n) {
    final waitersAsync = ref.watch(waitersProvider);
    return waitersAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (waiters) {
        final activeWaiters = waiters.where((w) => w.isActive).toList()
          ..sort((a, b) => a.firstName.compareTo(b.firstName));
        if (activeWaiters.isEmpty) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final selected = _waiterFilter != null;
        return Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? cs.secondaryContainer
                : cs.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int?>(
              value: _waiterFilter,
              isDense: true,
              icon: Icon(Icons.arrow_drop_down,
                  size: 18, color: cs.onSurfaceVariant),
              style: TextStyle(fontSize: 11, color: cs.onSurface),
              hint: Text(l10n.translate('waiter'),
                  style: const TextStyle(fontSize: 11)),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(l10n.translate('all_waiters'),
                      style: const TextStyle(fontSize: 11)),
                ),
                ...activeWaiters.map((w) {
                  final label = (w.lastName != null && w.lastName!.isNotEmpty)
                      ? '${w.firstName} ${w.lastName}'
                      : w.firstName;
                  return DropdownMenuItem<int?>(
                    value: w.id,
                    child: Text(label,
                        style: const TextStyle(fontSize: 11)),
                  );
                }),
              ],
              onChanged: (value) {
                _waiterFilter = value;
                _onFilterChanged();
              },
            ),
          ),
        );
      },
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isRangeToday() {
    if (_startDate == null) return false;
    return _isSameDay(_startDate!, DateTime.now());
  }

  bool _isRangeYesterday() {
    if (_startDate == null) return false;
    final y = DateTime.now().subtract(const Duration(days: 1));
    return _isSameDay(_startDate!, y);
  }

  bool _isRangeThisWeek() {
    if (_startDate == null) return false;
    final now = DateTime.now();
    final start = now.subtract(Duration(days: now.weekday - 1));
    return _isSameDay(_startDate!, start) &&
        (_endDate == null || _isSameDay(_endDate!, now));
  }

  bool _isRangeThisMonth() {
    if (_startDate == null) return false;
    final now = DateTime.now();
    return _startDate!.year == now.year &&
        _startDate!.month == now.month &&
        _startDate!.day == 1;
  }

  Widget _buildStatusDropdown(AppLocalizations l10n) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: l10n.translate('status'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      isExpanded: true,
      items: [
        DropdownMenuItem(value: 'ALL', child: Text(l10n.translate('all_statuses'))),
        DropdownMenuItem(value: 'ONHOLD', child: Text(l10n.translate('on_hold'))),
        DropdownMenuItem(value: 'PENDING', child: Text(l10n.translate('pending'))),
        DropdownMenuItem(value: 'PREPARING', child: Text(l10n.translate('preparing'))),
        DropdownMenuItem(value: 'READY', child: Text(l10n.translate('ready'))),
        DropdownMenuItem(value: 'DELIVERED', child: Text(l10n.translate('delivered'))),
        DropdownMenuItem(value: 'COMPLETED', child: Text(l10n.translate('completed'))),
        DropdownMenuItem(value: 'CANCELED', child: Text(l10n.translate('canceled'))),
      ],
      onChanged: (value) {
        if (value != null) {
          _statusFilter = value;
          _onFilterChanged();
        }
      },
    );
  }

  Widget _buildCustomerDropdown(AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RawAutocomplete<Customer>(
          textEditingController: _customerSearchController,
          focusNode: _customerSearchFocusNode,
          optionsBuilder: (TextEditingValue textEditingValue) async {
            final query = textEditingValue.text.trim();
            if (query.length < 3) return [];
            await _searchCustomersInDb(query);
            return _customers;
          },
          displayStringForOption: (Customer c) => c.displayLabel,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            // AdaptiveKeyboardTextField is the on-screen keyboard variant
            // of the basic TextField; RawAutocomplete still drives the
            // controller/focusNode lifecycle and listens for changes, so
            // the suggestion list keeps working exactly as before.
            return AdaptiveKeyboardTextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: l10n.translate('customer'),
                hintText: l10n.translate('search_by_name_phone_email'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                prefixIcon: const Icon(Icons.person_search, size: 20),
                suffixIcon: _selectedCustomerId != null || controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          controller.clear();
                          _selectedCustomerId = null;
                          _selectedCustomerName = null;
                          setState(() => _customers = []);
                          _onFilterChanged();
                        },
                      )
                    : null,
              ),
              onSubmitted: (_) => onFieldSubmitted(),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: 250,
                    maxWidth: constraints.maxWidth,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final customer = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          child: Text(
                            customer.displayInitial,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        title: Text(
                          customer.displayLabel,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        subtitle: customer.phone != null
                            ? Text(customer.phone!, style: const TextStyle(fontSize: 12))
                            : null,
                        onTap: () => onSelected(customer),
                      );
                    },
                  ),
                ),
              ),
            );
          },
          onSelected: (Customer customer) {
            _selectedCustomerId = customer.id;
            _selectedCustomerName = customer.displayLabel;
            _customerSearchController.text = _selectedCustomerName!;
            _onFilterChanged();
          },
        );
      },
    );
  }

  Widget _buildGroupedView(String currency, AppLocalizations l10n) {
    final orders = _paginatedOrders!.orders;

    Map<String, List<OrderFullDetails>> grouped = {};

    if (_groupBy == 'status') {
      for (final order in orders) {
        final key = order.order.status;
        grouped.putIfAbsent(key, () => []).add(order);
      }
    } else if (_groupBy == 'date') {
      for (final order in orders) {
        final date = order.order.date;
        final key = '${date.day}/${date.month}/${date.year}';
        grouped.putIfAbsent(key, () => []).add(order);
      }
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            itemCount: grouped.length,
            itemBuilder: (context, index) {
              final key = grouped.keys.elementAt(index);
              final groupOrders = grouped[key]!;

              return ExpansionTile(
                initiallyExpanded: true,
                title: Row(
                  children: [
                    if (_groupBy == 'status') _buildStatusChip(key, l10n),
                    if (_groupBy == 'date') Text(key, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${groupOrders.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
                children: groupOrders.map((order) => _buildOrderListTile(order, currency, l10n)).toList(),
              );
            },
          ),
        ),
        _buildPaginationControls(l10n),
      ],
    );
  }

  Widget _buildOrderListTile(OrderFullDetails orderDetails, String currency, AppLocalizations l10n) {
    final order = orderDetails.order;
    // Sync state is meaningful for every status except ONHOLD — open
    // tabs intentionally don't sync (they're not real orders yet). Same
    // rule used in `_buildDataRow` so the two views agree on which rows
    // show a cloud icon.
    final isSyncRelevant = order.status != 'ONHOLD';
    final needsSync = isSyncRelevant && !order.isSynced;
    final isZLocked = orderDetails.isZLocked;
    final isUnpaid = orderDetails.totalPaid < orderDetails.total;
    // Refunding a cancelled order is meaningless: cancelling already reversed
    // the sale and its stock, so refunding on top would give the money back
    // twice. Hidden rather than disabled — there is no reading of this the
    // cashier should be reaching for.
    final isCancelled = order.status == 'CANCELED';
    // Gated leniently: a role seeded before the refund permissions existed
    // holds none of them, and hiding the button for the whole floor on upgrade
    // would be worse than the status quo. See hasRefundPermission.
    final canRefund = ref
        .read(permissionServiceProvider)
        .hasRefundPermission(Permissions.refundsCreate);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getStatusColor(order.status).withValues(alpha: 0.2),
        child: Text(
          order.code.substring(0, 2).toUpperCase(),
          style: TextStyle(color: _getStatusColor(order.status)),
        ),
      ),
      title: Row(
        children: [
          ..._orderNoBadge(order),
          Text(order.code, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          OrderTagChips(tagIds: parseTagIds(order.tagIds), inline: true),
          if (isZLocked)
            const Tooltip(
              message: 'Z-Report locked',
              child: Icon(Icons.lock, size: 14, color: Colors.purple),
            )
          else if (needsSync)
            Tooltip(
              message: l10n.translate('not_synced'),
              child: const Icon(Icons.cloud_off, size: 14, color: Colors.orange),
            )
          else if (isSyncRelevant && order.isSynced)
            Tooltip(
              message: l10n.translate('synced'),
              child: const Icon(Icons.cloud_done, size: 14, color: Colors.green),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          if (orderDetails.customerName != null) ...[
            Icon(Icons.person, size: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(orderDetails.customerName!, style: const TextStyle(fontSize: 11)),
            const SizedBox(width: 12),
          ],
          Text(
            // With the fee by default: a delivery order's bill includes it, so
            // products-only does not match the money taken. The operator can
            // switch that off. The paid/unpaid decision always uses `total` —
            // see OrderFullDetails.deliveryFee.
            CurrencyFormatter.formatWithCurrency(
                _displayTotal(orderDetails), currency),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Text(_formatDate(order.date), style: const TextStyle(fontSize: 11)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStatusChip(order.status, l10n),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleOrderAction(value, order, orderDetails),
            itemBuilder: (context) {
              final permissionService = ref.read(permissionServiceProvider);
              final canUpdate = permissionService.hasPermission(Permissions.ordersUpdate);
              final canCancel = permissionService.hasPermission(Permissions.ordersCancel);
              final canPay = permissionService.hasPermission(Permissions.ticketsCreate);
              return [
                PopupMenuItem(value: 'view', child: Row(children: [const Icon(Icons.visibility, size: 18), const SizedBox(width: 8), Text(l10n.translate('view'))])),
                // Tags move no money, so they stay editable on any order,
                // locked Z or not.
                PopupMenuItem(value: 'tags', child: Row(children: [const Icon(Icons.label_outline, size: 18), const SizedBox(width: 8), Text(l10n.translate('order_tags'))])),
                if (isUnpaid && canPay)
                  PopupMenuItem(value: 'pay', child: Row(children: [const Icon(Icons.payment, size: 18, color: Colors.teal), SizedBox(width: 8), Text(l10n.translate('pay'), style: const TextStyle(color: Colors.teal))]))
                else ...[
                  // Refunding is a money movement on an already-paid order, so
                  // it rides on the same permission as taking the payment.
                  //
                  // Offered whatever the order's session or Z: the refund is
                  // booked into TODAY's session and Z, and the closed one is
                  // never touched. Whether a past sale may be refunded is the
                  // refund policy's call (window, closed-Z permission), made
                  // inside the dialog where it can say why.
                  if (canPay && !isCancelled && canRefund)
                    PopupMenuItem(value: 'refund', child: Row(children: [Icon(Icons.assignment_return, size: 18, color: Colors.deepOrange), const SizedBox(width: 8), Text(l10n.translate('refund'), style: const TextStyle(color: Colors.deepOrange))])),
                  if (!isZLocked) ...[
                  if (canUpdate)
                    PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit, size: 18), const SizedBox(width: 8), Text(l10n.translate('edit'))])),
                  if (canUpdate)
                    PopupMenuItem(value: 'status', child: Row(children: [const Icon(Icons.swap_horiz, size: 18), const SizedBox(width: 8), Text(l10n.translate('change_status'))])),
                  if (canCancel)
                    PopupMenuItem(value: 'cancel', child: Row(children: [const Icon(Icons.cancel, size: 18, color: Colors.orange), const SizedBox(width: 8), Text(l10n.translate('cancel_order'), style: const TextStyle(color: Colors.orange))])),
                  ],
                ],
              ];
            },
          ),
        ],
      ),
      onTap: isZLocked ? () => _showOrderDetails(order) : () => _editOrder(order),
    );
  }

  Widget _buildOrdersTable(String currency, AppLocalizations l10n) {
    final orders = _paginatedOrders!.orders;

    return Column(
      children: [
        Expanded(
          child: DataTable2(
            key: ValueKey(_showAllOrders),
            columnSpacing: 12,
            horizontalMargin: 12,
            minWidth: 1200,
            fixedLeftColumns: 1,
            scrollController: _ordersTableScrollController,
            showCheckboxColumn: false,
            headingRowColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            headingTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            dataRowHeight: 56,
            columns: [
              DataColumn2(label: Text(l10n.translate('actions')), size: ColumnSize.S),
              DataColumn2(
                label: Text(l10n.translate('code')),
                size: ColumnSize.M,
                onSort: (_, __) => _onSort('code'),
              ),
              DataColumn2(label: Text(l10n.translate('customer')), size: ColumnSize.M),
              DataColumn2(
                label: Text(l10n.translate('user')),
                size: ColumnSize.S,
                onSort: (_, __) => _onSort('takenBy'),
              ),
              DataColumn2(label: Text(l10n.translate('products')), size: ColumnSize.S, numeric: true),
              DataColumn2(label: Text(l10n.translate('total')), size: ColumnSize.S, numeric: true),
              DataColumn2(label: Text(l10n.translate('paid')), size: ColumnSize.S, numeric: true),
              DataColumn2(
                label: Text(l10n.translate('status')),
                size: ColumnSize.M,
                onSort: (_, __) => _onSort('status'),
              ),
              DataColumn2(
                label: Text(l10n.translate('date')),
                size: ColumnSize.M,
                onSort: (_, __) => _onSort('createdAt'),
              ),
            ],
            rows: orders.map((orderDetails) => _buildDataRow(orderDetails, currency, l10n)).toList(),
          ),
        ),
        _buildPaginationControls(l10n),
      ],
    );
  }

  /// The order's total as the list shows it: with or without the delivery
  /// fee, per the toolbar toggle.
  double _displayTotal(OrderFullDetails d) =>
      ref.watch(settingsProvider).totalsIncludeDeliveryFee
          ? d.grandTotal
          : d.total;

  /// "#12" ahead of the order code, when the per-session number is switched
  /// on for lists and the order has one.
  List<Widget> _orderNoBadge(Order order) {
    final no = order.sessionOrderNo;
    if (no == null || !ref.watch(settingsProvider).showOrderNumberInLists) {
      return const [];
    }
    final scheme = Theme.of(context).colorScheme;
    return [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '#$no',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: scheme.onPrimaryContainer,
          ),
        ),
      ),
      const SizedBox(width: 6),
    ];
  }

  DataRow _buildDataRow(OrderFullDetails orderDetails, String currency, AppLocalizations l10n) {
    final order = orderDetails.order;
    final isSynced = order.isSynced;
    // Sync state is meaningful for every status except ONHOLD. Previous
    // gate (`isCompleted && !isSynced`) suppressed the icon for every
    // PENDING/PREPARING/READY/DELIVERED/CANCELED row that was actually
    // out of sync, so the table looked clean even when half the orders
    // were waiting to push.
    final isSyncRelevant = order.status != 'ONHOLD';
    final needsSync = isSyncRelevant && !isSynced;
    final isZLocked = orderDetails.isZLocked;
    final isUnpaid = orderDetails.totalPaid < orderDetails.total;

    return DataRow(
      color: isZLocked
          ? WidgetStateProperty.all(Colors.purple.withValues(alpha: 0.04))
          : null,
      onSelectChanged: (_) => isZLocked ? _showOrderDetails(order) : _editOrder(order),
      cells: [
        DataCell(
          // Whole-cell tap target: switching from the `icon:` to the
          // `child:` constructor wraps the child in an InkWell that
          // fills the cell, so taps anywhere in the actions column
          // open the menu (the InkWell also consumes the tap so the
          // row's onSelectChanged doesn't fire).
          PopupMenuButton<String>(
            tooltip: l10n.translate('actions'),
            padding: EdgeInsets.zero,
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value == 'view') _showOrderDetails(order);
              else if (value == 'pay') _payOrder(order);
              else if (value == 'edit') _editOrder(order);
              else if (value == 'status') _showChangeStatusDialog(order);
              else if (value == 'cancel') _cancelOrder(order);
            },
            child: const SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: Center(child: Icon(Icons.more_vert)),
            ),
            itemBuilder: (context) {
              final permissionService = ref.read(permissionServiceProvider);
              final canUpdate = permissionService.hasPermission(Permissions.ordersUpdate);
              final canCancel = permissionService.hasPermission(Permissions.ordersCancel);
              final canPay = permissionService.hasPermission(Permissions.ticketsCreate);
              return [
                PopupMenuItem(
                  value: 'view',
                  child: Row(
                    children: [
                      const Icon(Icons.visibility, size: 18),
                      const SizedBox(width: 8),
                      Text(l10n.translate('view')),
                    ],
                  ),
                ),
                if (isUnpaid && canPay)
                  PopupMenuItem(
                    value: 'pay',
                    child: Row(
                      children: [
                        const Icon(Icons.payment, size: 18, color: Colors.teal),
                        const SizedBox(width: 8),
                        Text(l10n.translate('pay')),
                      ],
                    ),
                  ),
                if (!isZLocked) ...[
                  if (canUpdate)
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(Icons.edit, size: 18, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(l10n.translate('edit')),
                        ],
                      ),
                    ),
                  if (canUpdate)
                    PopupMenuItem(
                      value: 'status',
                      child: Row(
                        children: [
                          const Icon(Icons.swap_horiz, size: 18, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(l10n.translate('status')),
                        ],
                      ),
                    ),
                  if (canCancel)
                    PopupMenuItem(
                      value: 'cancel',
                      child: Row(
                        children: [
                          const Icon(Icons.cancel, size: 18, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(l10n.translate('cancel_order')),
                        ],
                      ),
                    ),
                ],
              ];
            },
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._orderNoBadge(order),
              Text(order.code, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(width: 4),
              OrderTagChips(tagIds: parseTagIds(order.tagIds), inline: true),
              if (isZLocked)
                const Tooltip(
                  message: 'Z-Report locked',
                  child: Icon(Icons.lock, size: 14, color: Colors.purple),
                )
              else if (isSyncRelevant)
                Tooltip(
                  message: needsSync ? l10n.translate('not_synced') : l10n.translate('synced'),
                  child: Icon(
                    needsSync ? Icons.cloud_off : Icons.cloud_done,
                    size: 14,
                    color: needsSync ? Colors.orange : Colors.green,
                  ),
                ),
            ],
          ),
        ),
        DataCell(
          orderDetails.customerName != null
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        orderDetails.customerName!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                )
              : Text('—', style: TextStyle(color: Theme.of(context).hintColor)),
        ),
        DataCell(Text(orderDetails.userName ?? '—', style: const TextStyle(fontSize: 12))),
        DataCell(Text(orderDetails.productCount.toString())),
        DataCell(
          Text(
            CurrencyFormatter.formatWithCurrency(
                _displayTotal(orderDetails), currency),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        DataCell(
          Text(
            CurrencyFormatter.formatWithCurrency(orderDetails.totalPaid, currency),
            style: TextStyle(
              color: orderDetails.totalPaid >= orderDetails.total ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        DataCell(_buildStatusChip(order.status, l10n)),
        DataCell(Text(_formatDate(order.date), style: const TextStyle(fontSize: 11))),
      ],
    );
  }

  Widget _buildStatusChip(String status, AppLocalizations l10n) {
    final color = _getStatusColor(status);
    String translatedStatus;
    switch (status) {
      case 'ONHOLD':
        translatedStatus = l10n.translate('on_hold');
        break;
      case 'PENDING':
        translatedStatus = l10n.translate('pending');
        break;
      case 'PREPARING':
        translatedStatus = l10n.translate('preparing');
        break;
      case 'READY':
        translatedStatus = l10n.translate('ready');
        break;
      case 'DELIVERED':
        translatedStatus = l10n.translate('delivered');
        break;
      case 'COMPLETED':
        translatedStatus = l10n.translate('completed');
        break;
      case 'CANCELED':
        translatedStatus = l10n.translate('canceled');
        break;
      default:
        translatedStatus = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        translatedStatus,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'ONHOLD':
        return Colors.orange;
      case 'PENDING':
        return Colors.blue;
      case 'PREPARING':
        return Colors.purple;
      case 'READY':
        return Colors.green;
      case 'DELIVERED':
        return Colors.teal;
      case 'COMPLETED':
        return Colors.green.shade800;
      case 'CANCELED':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  Widget _buildPaginationControls(AppLocalizations l10n) {
    final totalItems = _paginatedOrders?.totalCount ?? 0;
    final totalPages = _paginatedOrders?.totalPages ?? 0;
    final startItem = totalItems > 0 ? _currentPage * _rowsPerPage + 1 : 0;
    final endItem = ((_currentPage + 1) * _rowsPerPage).clamp(0, totalItems);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            totalItems > 0
                ? '${l10n.translate('showing')} $startItem-$endItem ${l10n.translate('of')} $totalItems ${l10n.translate('orders')}'
                : l10n.translate('no_orders'),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _currentPage > 0 ? () => _onPageChanged(0) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 0 ? () => _onPageChanged(_currentPage - 1) : null,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${l10n.translate('page')} ${_currentPage + 1} ${l10n.translate('of')} ${totalPages > 0 ? totalPages : 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages - 1 ? () => _onPageChanged(_currentPage + 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _currentPage < totalPages - 1 ? () => _onPageChanged(totalPages - 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyView(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            l10n.translate('no_orders_found'),
            style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.translate('try_adjusting_filters'),
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _resetAllFilters,
            icon: const Icon(Icons.clear_all),
            label: Text(l10n.translate('clear_filters')),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(String error, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            l10n.translate('error_loading_orders'),
            style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadOrders,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.translate('retry')),
          ),
        ],
      ),
    );
  }

  // Helper Functions
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getDateRangeText(AppLocalizations l10n) {
    if (_startDate == null && _endDate == null) {
      return l10n.translate('date_range');
    }
    final start = _startDate != null ? '${_startDate!.day}/${_startDate!.month}' : '...';
    final end = _endDate != null ? '${_endDate!.day}/${_endDate!.month}' : '...';
    return '$start - $end';
  }

  void _showDateRangePicker() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (result != null) {
      _startDate = result.start;
      _endDate = result.end;
      _onFilterChanged();
    }
  }

  void _handleOrderAction(String action, Order order, OrderFullDetails details) {
    if (details.isZLocked && action != 'view' && action != 'pay') {
      SnackBarHelper.showToast('Z-Report locked: session is closed. Only view or pay allowed.', kind: ToastKind.info, duration: Duration(seconds: 3));
      return;
    }
    switch (action) {
      case 'view':
        _showOrderDetails(order);
        break;
      case 'edit':
        _editOrder(order);
        break;
      case 'pay':
        _payOrder(order);
        break;
      case 'status':
        _showChangeStatusDialog(order);
        break;
      case 'cancel':
        _cancelOrder(order);
        break;
      case 'refund':
        _refundOrder(order);
        break;
      case 'tags':
        _tagOrder(order);
        break;
    }
  }

  Future<void> _refundOrder(Order order) async {
    // Online-only: the order and its refunds on every till are re-read from
    // the server first (see startRefund).
    final refunded =
        await startRefund(context: context, ref: ref, orderCode: order.code);
    if (!refunded || !mounted) return;
    _loadOrders();
  }

  // CRUD Operations
  void _showOrderDetails(Order order) async {
    final orderRepo = ref.read(orderRepositoryProvider);
    final fullDetails = await orderRepo.getOrderFullDetails(order.id);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => _OrderDetailsDialog(fullDetails: fullDetails),
    );
  }

  void _editOrder(Order order) async {
    final currentOrderNotifier = ref.read(orderProvider.notifier);
    final orderRepo = ref.read(orderRepositoryProvider);
    final currentOrder = await orderRepo.getOrderById(order.id);
    currentOrderNotifier.loadOrder(currentOrder!);

    if (!mounted) return;
    Navigator.pop(context);
  }

  /// Open the payment screen dialog directly for an unpaid order without
  /// navigating away from the management screen.
  Future<void> _payOrder(Order order) async {
    final l10n = AppLocalizations.of(context)!;
    final orderRepo = ref.read(orderRepositoryProvider);
    final currentOrderRaw = await orderRepo.getOrderById(order.id);
    if (currentOrderRaw == null) return;
    if (!mounted) return;

    // TEMP-TIP-HIDDEN: tip dialog before PaymentScreen disabled.
    // final currentOrder = await applyTipIfEnabled(context, ref, currentOrderRaw);
    // if (currentOrder.tip != currentOrderRaw.tip) {
    //   await orderRepo.updateOrder(currentOrder);
    // }
    final currentOrder = currentOrderRaw;
    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => PaymentScreen(order: currentOrder),
    );

    if (result == true && mounted) {
      SnackBarHelper.showToast(l10n.translate('payment_successful'), kind: ToastKind.success);
      _loadOrders();
    }
  }

  void _cancelOrder(Order order) async {
    final l10n = AppLocalizations.of(context)!;
    if (!ref.read(permissionServiceProvider).hasPermission(Permissions.ordersCancel)) {
      SnackBarHelper.showToast(l10n.translate('no_permission'), kind: ToastKind.error);
      return;
    }
    final reasonController = TextEditingController();

    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.translate('cancel_order')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${l10n.translate('confirm_cancel_order')} ${order.code}?'),
            const SizedBox(height: 16),
            AdaptiveKeyboardTextField(
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
            onPressed: () => Navigator.pop(dialogContext, null),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, reasonController.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(l10n.translate('confirm')),
          ),
        ],
      ),
    );

    // Not disposed: the closing dialog still rebuilds its field with this controller for a few frames. It is collected with the dialog.

    if (result != null) {
      await _changeOrderStatus(order, 'CANCELED', cancellationReason: result.isNotEmpty ? result : null);
    }
  }

  void _showChangeStatusDialog(Order order) async {
    final l10n = AppLocalizations.of(context)!;
    final statuses = ['ONHOLD', 'PENDING', 'PREPARING', 'READY', 'DELIVERED', 'COMPLETED', 'CANCELED'];
    String? selectedStatus = order.status;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) {
          return AlertDialog(
            title: Text('${l10n.translate('change_status')} - ${order.code}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${l10n.translate('current')}: ', style: const TextStyle(fontWeight: FontWeight.w500)),
                    _buildStatusChip(order.status, l10n),
                    const SizedBox(width: 8),
                    if (order.isSynced)
                      const Icon(Icons.cloud_done, size: 16, color: Colors.green)
                    else if (order.status != 'ONHOLD')
                      const Icon(Icons.cloud_off, size: 16, color: Colors.orange),
                  ],
                ),
                const SizedBox(height: 16),
                Text('${l10n.translate('new_status')}:', style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: statuses.map((status) => ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_getTranslatedStatus(status, l10n), style: const TextStyle(fontSize: 11)),
                        // Show cloud icon for all statuses except ONHOLD
                        if (status != 'ONHOLD') ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.cloud_upload, size: 12),
                        ],
                      ],
                    ),
                    selected: selectedStatus == status,
                    onSelected: (selected) {
                      setDialogState(() {
                        selectedStatus = selected ? status : null;
                      });
                    },
                  )).toList(),
                ),
                const SizedBox(height: 12),
                // Info about sync behavior
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l10n.translate('sync_info_all_except_onhold'),
                          style: const TextStyle(fontSize: 11, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(l10n.translate('cancel')),
              ),
              ElevatedButton(
                onPressed: selectedStatus != null && selectedStatus != order.status
                    ? () => Navigator.pop(dialogContext, selectedStatus)
                    : null,
                child: Text(l10n.translate('change')),
              ),
            ],
          );
        },
      ),
    );

    if (result != null && result != order.status) {
      // If changing to CANCELED, show reason dialog
      if (result == 'CANCELED') {
        _cancelOrder(order);
      } else {
        await _changeOrderStatus(order, result);
      }
    }
  }

  String _getTranslatedStatus(String status, AppLocalizations l10n) {
    switch (status) {
      case 'ONHOLD':
        return l10n.translate('on_hold');
      case 'PENDING':
        return l10n.translate('pending');
      case 'PREPARING':
        return l10n.translate('preparing');
      case 'READY':
        return l10n.translate('ready');
      case 'DELIVERED':
        return l10n.translate('delivered');
      case 'COMPLETED':
        return l10n.translate('completed');
      case 'CANCELED':
        return l10n.translate('canceled');
      default:
        return status;
    }
  }

  Future<void> _changeOrderStatus(Order order, String newStatus, {String? cancellationReason}) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final isOnline = ref.read(networkStateProvider);
      final synced = await ref
          .read(orderServiceProvider)
          .changeStatus(order.id, newStatus, reason: cancellationReason);

      _loadOrders();

      if (mounted) {
        String message = '${l10n.translate('status_changed_to')} ${_getTranslatedStatus(newStatus, l10n)}';
        if (newStatus == 'ONHOLD') {
          message += ' (${l10n.translate('will_not_sync')})';
        } else if (isOnline) {
          message += synced ? ' ${l10n.translate('and_synced')}' : ' (${l10n.translate('sync_pending')})';
        } else {
          message += ' (${l10n.translate('will_sync_when_online')})';
        }

        SnackBarHelper.showToast(message, kind: (synced) ? ToastKind.success : ToastKind.warning);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast('${l10n.translate('error_changing_status')}: $e', kind: ToastKind.error);
      }
    }
  }

  Future<void> _syncAll() async {
    final l10n = AppLocalizations.of(context)!;
    final isOnline = ref.read(networkStateProvider);

    if (!isOnline) {
      if (mounted) {
        SnackBarHelper.showToast(l10n.translate('no_network_connection'), kind: ToastKind.error);
      }
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final syncManager = ref.read(syncManagerProvider.notifier);
      final result = await syncManager.performFullSync();

      if (mounted) {
        setState(() => _isSyncing = false);

        SnackBarHelper.showToast(result.message, kind: (result.success && result.totalSynced > 0) ? ToastKind.success : ToastKind.error, duration: const Duration(seconds: 4));

        if (result.totalSynced > 0) {
          _loadOrders();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        SnackBarHelper.showToast('${l10n.translate('sync_error')}: $e', kind: ToastKind.error);
      }
    }
  }

  Future<void> _showPendingOperationsDialog() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final pendingOps = ref.read(pendingOperationsServiceProvider);
      final operations = await pendingOps.getAllOperationsNewestFirst();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.pending_actions),
              const SizedBox(width: 12),
              Text('${l10n.translate('pending_operations')} (${operations.length})'),
            ],
          ),
          content: SizedBox(
            width: 600,
            height: 400,
            child: operations.isEmpty
                ? Center(child: Text(l10n.translate('no_pending_operations')))
                : ListView.builder(
                    itemCount: operations.length,
                    itemBuilder: (listContext, index) {
                      final op = operations[index];
                      final isDelete = op.operationType == 'DELETE';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            isDelete ? Icons.delete : Icons.edit,
                            color: isDelete ? Colors.red : Colors.blue,
                          ),
                          title: Text('${op.operationType} ${op.entityType} #${op.entityId}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${l10n.translate('server_id')}: ${op.serverId ?? l10n.translate('not_synced_yet')}'),
                              Text('${l10n.translate('created')}: ${_formatDate(op.createdAt)}'),
                              if (op.retryCount > 0)
                                Text('${l10n.translate('retries')}: ${op.retryCount}', style: const TextStyle(color: Colors.orange)),
                              if (op.lastError != null)
                                Text('${l10n.translate('error')}: ${op.lastError}', style: const TextStyle(color: Colors.red, fontSize: 11)),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_forever, color: Colors.red),
                            onPressed: () async {
                              await pendingOps.markCompleted(op.id);
                              Navigator.pop(dialogContext);
                              _showPendingOperationsDialog();
                            },
                            tooltip: l10n.translate('remove_from_queue'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.translate('close')),
            ),
            if (operations.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _syncAll();
                },
                icon: const Icon(Icons.sync),
                label: Text(l10n.translate('sync_now')),
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast('${l10n.translate('error_loading_operations')}: $e', kind: ToastKind.error);
      }
    }
  }

  // ========== SEARCH BY CODE FUNCTIONALITY ==========

  void _showSearchByCodeDialog() {
    final l10n = AppLocalizations.of(context)!;
    final TextEditingController codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.search),
            const SizedBox(width: 12),
            Text(l10n.translate('search_order_by_code')),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: AdaptiveKeyboardTextField(
            controller: codeController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: l10n.translate('enter_order_code'),
              prefixIcon: const Icon(Icons.qr_code),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.of(dialogContext).pop();
                _searchOrderByCode(value.trim());
              }
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              final code = codeController.text.trim();
              if (code.isNotEmpty) {
                Navigator.of(dialogContext).pop();
                _searchOrderByCode(code);
              }
            },
            child: Text(l10n.translate('search')),
          ),
        ],
      ),
    );
  }

  Future<void> _searchOrderByCode(String orderCode) async {
    final l10n = AppLocalizations.of(context)!;
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Center(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(l10n.translate('searching_for_order')),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // Step 1: Search in local database first
      final order =
          await ref.read(orderRepositoryProvider).findOrderRowByCode(orderCode);

      if (order != null) {
        // Order found in local database
        if (mounted) Navigator.of(context).pop(); // Close loading dialog

        if (mounted) {
          _showOrderDetails(order);
        }
        return;
      }

      // Step 2: Order not found locally, try API
      final isOnline = ref.read(networkStateProvider);
      if (!isOnline) {
        if (mounted) Navigator.of(context).pop(); // Close loading dialog
        if (mounted) _showErrorSnackBar(l10n.translate('order_not_found_offline'));
        return;
      }

      final apiService = ref.read(apiServiceProvider);
      final orderData = await apiService.fetchOrderByCode(orderCode);

      if (mounted) Navigator.of(context).pop(); // Close loading dialog

      // Convert to WebOrderResponse and show dialog
      final webOrder = WebOrderResponse.fromJson(orderData);
      if (mounted) {
        showDialog(
          context: context,
          builder: (dialogContext) => OrderDetailsDialog(order: webOrder),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        _showErrorSnackBar(errorText(e, AppLocalizations.of(context)!));
      }
    }
  }

  void _showErrorSnackBar(String message) {
    SnackBarHelper.showToast(message, kind: ToastKind.error, action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {},
        ));
  }
}

// Order Details Dialog
class _OrderDetailsDialog extends ConsumerWidget {
  final OrderFullDetails fullDetails;

  const _OrderDetailsDialog({super.key, required this.fullDetails});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final order = fullDetails.order;
    final currency = ref.watch(currencySymbolProvider);

    return Dialog(
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.bar(Theme.of(context).colorScheme),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${l10n.translate('order')} ${order.code}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          l10n.translate('order_details'),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Refunds first: an order that was partly given back still
                    // shows its original total everywhere else on this dialog,
                    // so this is the only thing on screen that says otherwise.
                    OrderRefundsPanel(orderId: order.id),
                    const SizedBox(height: 20),
                    Text(l10n.translate('order_information'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildInfoRow(context, l10n.translate('order_id'), '#${order.id}'),
                            _buildInfoRow(context, l10n.translate('order_code'), order.code),
                            if (order.sessionOrderNo != null &&
                                ref.watch(settingsProvider).showOrderNumberInLists)
                              _buildInfoRow(context, l10n.translate('order_number_section'),
                                  '#${order.sessionOrderNo}'),
                            _buildInfoRow(context, l10n.translate('status'), _getTranslatedStatus(order.status, l10n)),
                            _buildInfoRow(context, l10n.translate('type'), order.type.replaceAll('_', ' ')),
                            _buildInfoRow(context, l10n.translate('number_of_persons'), '${order.persons}'),
                            if (fullDetails.tableName != null)
                              _buildInfoRow(context, l10n.translate('table'), fullDetails.tableName!),
                            if (fullDetails.customerName != null)
                              _buildInfoRow(context, l10n.translate('customer'), fullDetails.customerName!),
                            _buildInfoRow(context, l10n.translate('username'), fullDetails.userName ?? 'N/A'),
                            _buildInfoRow(context, l10n.translate('date'), _formatFullDateTime(order.date)),
                            _buildInfoRow(context, l10n.translate('synced'), order.isSynced ? l10n.translate('yes') : l10n.translate('no')),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(l10n.translate('order_items'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...fullDetails.items.map((item) => _buildOrderItem(context, item, currency, l10n)),
                    const SizedBox(height: 24),
                    Text(l10n.translate('financial_summary'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildFinancialCard(context, currency, l10n,
                        includeDeliveryFee: ref
                            .watch(settingsProvider)
                            .totalsIncludeDeliveryFee),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTranslatedStatus(String status, AppLocalizations l10n) {
    switch (status) {
      case 'ONHOLD':
        return l10n.translate('on_hold');
      case 'PENDING':
        return l10n.translate('pending');
      case 'PREPARING':
        return l10n.translate('preparing');
      case 'READY':
        return l10n.translate('ready');
      case 'DELIVERED':
        return l10n.translate('delivered');
      case 'COMPLETED':
        return l10n.translate('completed');
      case 'CANCELED':
        return l10n.translate('canceled');
      default:
        return status;
    }
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Where the line is in the kitchen, and when it got there:
  /// "Cooking · sent 12:03 · started 12:05".
  Widget _kitchenLine(
      BuildContext context, OrderItemDetails item, AppLocalizations l10n) {
    final state = (item.kitchenState ?? '').toUpperCase();
    if (state.isEmpty || state == 'ONHOLD') return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    String hm(DateTime d) =>
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    final (IconData icon, Color color, String label) = switch (state) {
      'PREPARING' => (Icons.local_fire_department_rounded, scheme.primary,
          l10n.translate('kitchen_cooking')),
      'CANCELED' || 'CANCELLED' => (Icons.block, scheme.error,
          l10n.translate('canceled')),
      'PENDING' => (Icons.hourglass_top_rounded, scheme.outline,
          l10n.translate('kitchen_waiting')),
      _ => (Icons.check_circle_rounded, scheme.secondary,
          l10n.translate('kitchen_ready')),
    };
    final parts = <String>[
      label,
      if (item.kitchenAt != null) '${l10n.translate('kitchen_sent')} ${hm(item.kitchenAt!)}',
      if (item.preparingAt != null)
        '${l10n.translate('kitchen_started')} ${hm(item.preparingAt!)}',
      if (item.kitchenDoneAt != null) ...[
        '${l10n.translate('kitchen_ready')} ${hm(item.kitchenDoneAt!)}',
        if (item.kitchenAt != null)
          '(${item.kitchenDoneAt!.difference(item.kitchenAt!).inMinutes} min)',
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(parts.join(' · '),
                style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(BuildContext context, OrderItemDetails item, String currency, AppLocalizations l10n) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (item.isPaid) ...[
                            Icon(Icons.check_circle, size: 18, color: Colors.green[700]),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              item.displayName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                        ],
                      ),
                      if (item.components.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ...item.components.map((comp) => Padding(
                              padding: const EdgeInsets.only(left: 24, top: 4),
                              child: Text(
                                '+ ${comp.name} x${comp.quantity}',
                                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'x${item.quantity}',
                      style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      CurrencyFormatter.formatWithCurrency(item.totalPrice, currency),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
            if (item.isPaid) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green),
                ),
                child: Text(
                  '${l10n.translate('paid_in_ticket')} #${item.ticketNum ?? 'N/A'}',
                  style: TextStyle(fontSize: 12, color: Colors.green[800], fontWeight: FontWeight.w600),
                ),
              ),
            ],
            _kitchenLine(context, item, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialCard(BuildContext context, String currency, AppLocalizations l10n,
      {required bool includeDeliveryFee}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildFinancialRow(l10n.translate('product_count'), fullDetails.productCount.toString(), isBold: false),
            const Divider(height: 20),
            _buildFinancialRow(l10n.translate('subtotal'), CurrencyFormatter.formatWithCurrency(fullDetails.subtotal, currency)),
            if (fullDetails.itemDiscount > 0)
              _buildFinancialRow(l10n.translate('item_discounts'), '-${CurrencyFormatter.formatWithCurrency(fullDetails.itemDiscount, currency)}', color: Colors.orange),
            if (fullDetails.discountPercentage > 0)
              _buildFinancialRow(
                '${l10n.translate('manual_discount')} (${fullDetails.discountPercentage.toStringAsFixed(0)}%)',
                '-${CurrencyFormatter.formatWithCurrency(fullDetails.manualDiscountAmount, currency)}',
                color: Colors.deepOrange,
              ),
            if (fullDetails.totalDiscount > 0)
              _buildFinancialRow(l10n.translate('total_discount'), '-${CurrencyFormatter.formatWithCurrency(fullDetails.totalDiscount, currency)}', color: Colors.red),
            _buildFinancialRow(l10n.translate('total_tva'), CurrencyFormatter.formatWithCurrency(fullDetails.totalTva, currency)),
            const Divider(height: 20, thickness: 2),
            // Products, then delivery, then what is actually owed. Broken out
            // rather than folded in so the products figure still reconciles
            // with the ticket rows and every sales total built from them.
            if (fullDetails.deliveryFee > 0 && includeDeliveryFee) ...[
              _buildFinancialRow(l10n.translate('total'),
                  CurrencyFormatter.formatWithCurrency(fullDetails.total, currency)),
              _buildFinancialRow(
                  l10n.translate('delivery_fee'),
                  CurrencyFormatter.formatWithCurrency(
                      fullDetails.deliveryFee, currency)),
              _buildFinancialRow(
                  l10n.translate('total_collected'),
                  CurrencyFormatter.formatWithCurrency(
                      fullDetails.grandTotal, currency),
                  fontSize: 18,
                  isBold: true),
            ] else
              _buildFinancialRow(l10n.translate('total'), CurrencyFormatter.formatWithCurrency(fullDetails.total, currency), fontSize: 18, isBold: true),
            const Divider(height: 20),
            _buildFinancialRow(
              l10n.translate('total_paid'),
              CurrencyFormatter.formatWithCurrency(fullDetails.totalPaid, currency),
              color: fullDetails.totalPaid >= fullDetails.total ? Colors.green : Colors.orange,
              isBold: true,
            ),
            _buildFinancialRow(
              l10n.translate('balance'),
              CurrencyFormatter.formatWithCurrency(fullDetails.total - fullDetails.totalPaid, currency),
              color: fullDetails.totalPaid >= fullDetails.total ? Colors.green : Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialRow(String label, String value, {Color? color, double fontSize = 14, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _formatFullDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}


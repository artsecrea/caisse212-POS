// filepath: /home/artecrea/StudioProjects/posecrea/lib/presentation/widgets/orders_management_screen.dart

import 'package:drift/drift.dart' show OrderingTerm, OrderingMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/app_localizations.dart';

import 'package:data_table_2/data_table_2.dart';
import '../../domain/models/order_models.dart';
import '../../providers/order_provider.dart';
import '../../providers/sync_manager_provider.dart';
import '../../providers/database_providers.dart';
import '../../data/database/app_database.dart';
import '../../services/permission_service.dart';
import 'permission_guard.dart';
import 'order_details_dialog.dart';

class OrdersManagementScreen extends ConsumerStatefulWidget {
  const OrdersManagementScreen({super.key});

  @override
  ConsumerState<OrdersManagementScreen> createState() => _OrdersManagementScreenState();
}

class _OrdersManagementScreenState extends ConsumerState<OrdersManagementScreen> {
  // Filters
  String _statusFilter = 'ALL';
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;
  int? _selectedCustomerId;

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

  final TextEditingController _searchController = TextEditingController();

  // Customers list for filter
  List<Customer> _customers = [];

  @override
  void initState() {
    super.initState();
    _loadCustomers();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    try {
      final database = ref.read(databaseProvider);
      _customers = await database.select(database.customers).get();
      if (mounted) setState(() {});
    } catch (e) {
      // Ignore errors loading customers
    }
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final result = await orderRepo.getPaginatedOrdersWithFullDetails(
        page: _currentPage,
        pageSize: _rowsPerPage,
        statusFilter: _statusFilter,
        searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
        customerId: _selectedCustomerId,
        startDate: _startDate,
        endDate: _endDate,
        sortColumn: _sortColumn,
        sortAscending: _sortAscending,
      );

      if (mounted) {
        setState(() {
          _paginatedOrders = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
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

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(currencySymbolProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: _buildAppBar(l10n),
      body: Column(
        children: [
          _buildFiltersBar(l10n),
          _buildSecondaryFiltersBar(l10n),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorView(_errorMessage!, l10n)
                    : _paginatedOrders == null || _paginatedOrders!.orders.isEmpty
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
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          // Search field
          Expanded(
            flex: 2,
            child: TextField(
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onSubmitted: (value) {
                _searchQuery = value;
                _onFilterChanged();
              },
            ),
          ),
          const SizedBox(width: 16),
          // Status filter
          Expanded(
            child: _buildStatusDropdown(l10n),
          ),
          const SizedBox(width: 16),
          // Customer filter
          Expanded(
            child: _buildCustomerDropdown(l10n),
          ),
          const SizedBox(width: 16),
          // Date range picker
          OutlinedButton.icon(
            onPressed: _showDateRangePicker,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(_getDateRangeText(l10n), style: const TextStyle(fontSize: 12)),
          ),
          if (_startDate != null || _endDate != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () {
                _startDate = null;
                _endDate = null;
                _onFilterChanged();
              },
              tooltip: l10n.translate('clear_date_filter'),
            ),
        ],
      ),
    );
  }

  Widget _buildSecondaryFiltersBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          // Group by
          Text('${l10n.translate('group_by')}: ', style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'none', label: Text(l10n.translate('none'), style: const TextStyle(fontSize: 12))),
              ButtonSegment(value: 'status', label: Text(l10n.translate('status'), style: const TextStyle(fontSize: 12))),
              ButtonSegment(value: 'date', label: Text(l10n.translate('date'), style: const TextStyle(fontSize: 12))),
            ],
            selected: {_groupBy},
            onSelectionChanged: (selected) {
              setState(() {
                _groupBy = selected.first;
              });
            },
            style: const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const Spacer(),
          // Rows per page
          Text('${l10n.translate('rows_per_page')}: ', style: const TextStyle(fontSize: 12)),
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
          const SizedBox(width: 16),
          // Quick filters
          Wrap(
            spacing: 8,
            children: [
              FilterChip(
                label: Text(l10n.translate('today'), style: const TextStyle(fontSize: 11)),
                selected: _isToday(),
                onSelected: (selected) {
                  if (selected) {
                    final now = DateTime.now();
                    _startDate = DateTime(now.year, now.month, now.day);
                    _endDate = now;
                  } else {
                    _startDate = null;
                    _endDate = null;
                  }
                  _onFilterChanged();
                },
              ),
              FilterChip(
                label: Text(l10n.translate('unsynced'), style: const TextStyle(fontSize: 11)),
                selected: _statusFilter == 'COMPLETED',
                onSelected: (selected) {
                  _statusFilter = selected ? 'COMPLETED' : 'ALL';
                  _onFilterChanged();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isToday() {
    if (_startDate == null) return false;
    final now = DateTime.now();
    return _startDate!.year == now.year &&
           _startDate!.month == now.month &&
           _startDate!.day == now.day;
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
    return DropdownButtonFormField<int?>(
      decoration: InputDecoration(
        labelText: l10n.translate('customer'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        suffixIcon: _selectedCustomerId != null
            ? IconButton(
                icon: const Icon(Icons.clear, size: 18),
                onPressed: () {
                  _selectedCustomerId = null;
                  _onFilterChanged();
                },
              )
            : null,
      ),
      isExpanded: true,
      items: [
        DropdownMenuItem(value: null, child: Text(l10n.translate('all_customers'))),
        ..._customers.map((c) => DropdownMenuItem(
              value: c.id,
              child: Text('${c.firstName} ${c.lastName}', overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: (value) {
        _selectedCustomerId = value;
        _onFilterChanged();
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
    final needsSync = order.status == 'COMPLETED' && !order.isSynced;

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
          Text(order.code, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          if (needsSync)
            const Icon(Icons.cloud_off, size: 14, color: Colors.orange),
          if (order.isSynced && order.status == 'COMPLETED')
            const Icon(Icons.cloud_done, size: 14, color: Colors.green),
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
            CurrencyFormatter.formatWithCurrency(orderDetails.total, currency),
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
            itemBuilder: (context) => [
              PopupMenuItem(value: 'view', child: Row(children: [const Icon(Icons.visibility, size: 18), const SizedBox(width: 8), Text(l10n.translate('view'))])),
              PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit, size: 18), const SizedBox(width: 8), Text(l10n.translate('edit'))])),
              PopupMenuItem(value: 'status', child: Row(children: [const Icon(Icons.swap_horiz, size: 18), const SizedBox(width: 8), Text(l10n.translate('change_status'))])),
              PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete, size: 18, color: Colors.red), const SizedBox(width: 8), Text(l10n.translate('delete'), style: const TextStyle(color: Colors.red))])),
            ],
          ),
        ],
      ),
      onTap: () => _editOrder(order),
    );
  }

  Widget _buildOrdersTable(String currency, AppLocalizations l10n) {
    final orders = _paginatedOrders!.orders;

    return Column(
      children: [
        Expanded(
          child: DataTable2(
            columnSpacing: 12,
            horizontalMargin: 12,
            minWidth: 1200,
            scrollController: ScrollController(),
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
              DataColumn2(label: Text(l10n.translate('actions')), size: ColumnSize.L),
            ],
            rows: orders.map((orderDetails) => _buildDataRow(orderDetails, currency, l10n)).toList(),
          ),
        ),
        _buildPaginationControls(l10n),
      ],
    );
  }

  DataRow _buildDataRow(OrderFullDetails orderDetails, String currency, AppLocalizations l10n) {
    final order = orderDetails.order;
    final isCompleted = order.status == 'COMPLETED';
    final isSynced = order.isSynced;
    final needsSync = isCompleted && !isSynced;

    return DataRow(
      onSelectChanged: (_) => _editOrder(order),
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(order.code, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(width: 4),
              if (isCompleted)
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
            CurrencyFormatter.formatWithCurrency(orderDetails.total, currency),
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
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility, size: 18),
                onPressed: () => _showOrderDetails(order),
                tooltip: l10n.translate('view'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              PermissionIconButton(
                permission: Permissions.ordersUpdate,
                icon: const Icon(Icons.edit, size: 18, color: Colors.green),
                onPressed: () => _editOrder(order),
                tooltip: l10n.translate('edit'),
              ),
              PermissionIconButton(
                permission: Permissions.ordersUpdate,
                icon: const Icon(Icons.swap_horiz, size: 18, color: Colors.blue),
                onPressed: () => _showChangeStatusDialog(order),
                tooltip: l10n.translate('status'),
              ),
              PermissionIconButton(
                permission: Permissions.ordersDelete,
                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                onPressed: () => _deleteOrder(order),
                tooltip: l10n.translate('delete'),
              ),
            ],
          ),
        ),
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
        return Colors.grey;
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
          Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            l10n.translate('no_orders_found'),
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.translate('try_adjusting_filters'),
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              _statusFilter = 'ALL';
              _searchQuery = '';
              _searchController.clear();
              _selectedCustomerId = null;
              _startDate = null;
              _endDate = null;
              _onFilterChanged();
            },
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
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
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
    switch (action) {
      case 'view':
        _showOrderDetails(order);
        break;
      case 'edit':
        _editOrder(order);
        break;
      case 'status':
        _showChangeStatusDialog(order);
        break;
      case 'delete':
        _deleteOrder(order);
        break;
    }
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

  void _deleteOrder(Order order) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.translate('delete_order')),
        content: Text('${l10n.translate('confirm_delete_order')} ${order.code}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.translate('delete')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final orderRepo = ref.read(orderRepositoryProvider);
        await orderRepo.deleteOrder(order.id);
        _loadOrders();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.translate('order_deleted_successfully'))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.translate('error_deleting_order')}: $e')),
          );
        }
      }
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
                    else if (order.status == 'COMPLETED')
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
                        if (status == 'COMPLETED') ...[
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
      await _changeOrderStatus(order, result);
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

  Future<void> _changeOrderStatus(Order order, String newStatus) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final orderRepo = ref.read(orderRepositoryProvider);
      final isOnline = ref.read(networkStateProvider);

      await orderRepo.updateOrderStatus(order.id, newStatus);

      bool synced = false;
      if (newStatus == 'COMPLETED' && isOnline) {
        try {
          final syncManager = ref.read(syncManagerProvider.notifier);
          synced = await syncManager.autoSyncOrder(order.id);
        } catch (e) {
          // Ignore sync errors
        }
      }

      _loadOrders();

      if (mounted) {
        String message = '${l10n.translate('status_changed_to')} ${_getTranslatedStatus(newStatus, l10n)}';
        if (newStatus == 'COMPLETED') {
          message += synced ? ' ${l10n.translate('and_synced')}' : (isOnline ? ' (${l10n.translate('sync_pending')})' : ' (${l10n.translate('will_sync_when_online')})');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: synced || newStatus != 'COMPLETED' ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.translate('error_changing_status')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _syncAll() async {
    final l10n = AppLocalizations.of(context)!;
    final isOnline = ref.read(networkStateProvider);

    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.translate('no_network_connection')), backgroundColor: Colors.red),
        );
      }
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final syncManager = ref.read(syncManagerProvider.notifier);
      final result = await syncManager.performFullSync();

      if (mounted) {
        setState(() => _isSyncing = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message),
            backgroundColor: result.success && result.totalSynced > 0
                ? Colors.green
                : (result.success ? Colors.orange : Colors.red),
            duration: const Duration(seconds: 4),
          ),
        );

        if (result.totalSynced > 0) {
          _loadOrders();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.translate('sync_error')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showPendingOperationsDialog() async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final database = ref.read(databaseProvider);
      final operations = await (database.select(database.pendingSyncOperations)
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
          .get();

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
                              await (database.delete(database.pendingSyncOperations)
                                    ..where((t) => t.id.equals(op.id)))
                                  .go();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.translate('error_loading_operations')}: $e'), backgroundColor: Colors.red),
        );
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
          child: TextField(
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
      final database = ref.read(databaseProvider);
      final localOrders = await (database.select(database.orders)
            ..where((tbl) => tbl.code.equals(orderCode)))
          .get();

      if (localOrders.isNotEmpty) {
        // Order found in local database
        if (mounted) Navigator.of(context).pop(); // Close loading dialog

        final order = localOrders.first;
        final orderRepo = ref.read(orderRepositoryProvider);
        final fullDetails = await orderRepo.getOrderFullDetails(order.id);

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
        _showErrorSnackBar('Error: ${e.toString()}');
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
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
                color: Theme.of(context).primaryColor,
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
                    Text(l10n.translate('order_information'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildInfoRow(l10n.translate('order_id'), '#${order.id}'),
                            _buildInfoRow(l10n.translate('order_code'), order.code),
                            _buildInfoRow(l10n.translate('status'), _getTranslatedStatus(order.status, l10n)),
                            _buildInfoRow(l10n.translate('type'), order.type.replaceAll('_', ' ')),
                            _buildInfoRow(l10n.translate('number_of_persons'), '${order.persons}'),
                            if (fullDetails.tableName != null)
                              _buildInfoRow(l10n.translate('table'), fullDetails.tableName!),
                            if (fullDetails.customerName != null)
                              _buildInfoRow(l10n.translate('customer'), fullDetails.customerName!),
                            _buildInfoRow(l10n.translate('username'), fullDetails.userName ?? 'N/A'),
                            _buildInfoRow(l10n.translate('date'), _formatFullDateTime(order.date)),
                            _buildInfoRow(l10n.translate('synced'), order.isSynced ? l10n.translate('yes') : l10n.translate('no')),
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
                    _buildFinancialCard(context, currency, l10n),
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

  Widget _buildInfoRow(String label, String value) {
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
                color: Colors.grey[700],
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
                                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
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
                      style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w600),
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
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialCard(BuildContext context, String currency, AppLocalizations l10n) {
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


// filepath: /home/artecrea/StudioProjects/posecrea/lib/presentation/widgets/orders_management_screen.dart

import 'package:drift/drift.dart' show OrderingTerm, OrderingMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/currency_formatter.dart';

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

    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildFiltersBar(),
          _buildSecondaryFiltersBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? _buildErrorView(_errorMessage!)
                    : _paginatedOrders == null || _paginatedOrders!.orders.isEmpty
                        ? _buildEmptyView()
                        : _groupBy == 'none'
                            ? _buildOrdersTable(currency)
                            : _buildGroupedView(currency),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isOnline = ref.watch(networkStateProvider);
    final syncState = ref.watch(syncManagerProvider);

    return AppBar(
      title: Row(
        children: [
          const Text('Orders Management'),
          if (_paginatedOrders != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_paginatedOrders!.totalCount} orders',
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
            message: isOnline ? 'Online' : 'Offline',
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
          tooltip: 'Search Order by Code',
        ),
        // View pending operations queue
        PermissionIconButton(
          permission: Permissions.viewPendingOperations,
          onPressed: _showPendingOperationsDialog,
          icon: const Icon(Icons.pending_actions),
          tooltip: 'View Pending Operations',
        ),
        // Sync all button
        PermissionIconButton(
          permission: Permissions.syncAll,
          onPressed: (_isSyncing || syncState.isSyncing) ? () {} : _syncAll,
          icon: const Icon(Icons.cloud_sync),
          tooltip: 'Sync All',
        ),
        // Refresh
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadOrders,
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildFiltersBar() {
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
                hintText: 'Search by code, username, customer...',
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
            child: _buildStatusDropdown(),
          ),
          const SizedBox(width: 16),
          // Customer filter
          Expanded(
            child: _buildCustomerDropdown(),
          ),
          const SizedBox(width: 16),
          // Date range picker
          OutlinedButton.icon(
            onPressed: _showDateRangePicker,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(_getDateRangeText(), style: const TextStyle(fontSize: 12)),
          ),
          if (_startDate != null || _endDate != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () {
                _startDate = null;
                _endDate = null;
                _onFilterChanged();
              },
              tooltip: 'Clear date filter',
            ),
        ],
      ),
    );
  }

  Widget _buildSecondaryFiltersBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          // Group by
          const Text('Group by: ', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'none', label: Text('None', style: TextStyle(fontSize: 12))),
              ButtonSegment(value: 'status', label: Text('Status', style: TextStyle(fontSize: 12))),
              ButtonSegment(value: 'date', label: Text('Date', style: TextStyle(fontSize: 12))),
            ],
            selected: {_groupBy},
            onSelectionChanged: (selected) {
              setState(() {
                _groupBy = selected.first;
              });
            },
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const Spacer(),
          // Rows per page
          const Text('Rows per page: ', style: TextStyle(fontSize: 12)),
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
                label: const Text('Today', style: TextStyle(fontSize: 11)),
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
                label: const Text('Unsynced', style: TextStyle(fontSize: 11)),
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

  Widget _buildStatusDropdown() {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: 'Status',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      isExpanded: true,
      items: const [
        DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
        DropdownMenuItem(value: 'ONHOLD', child: Text('On Hold')),
        DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
        DropdownMenuItem(value: 'PREPARING', child: Text('Preparing')),
        DropdownMenuItem(value: 'READY', child: Text('Ready')),
        DropdownMenuItem(value: 'DELIVERED', child: Text('Delivered')),
        DropdownMenuItem(value: 'COMPLETED', child: Text('Completed')),
        DropdownMenuItem(value: 'CANCELED', child: Text('Canceled')),
      ],
      onChanged: (value) {
        if (value != null) {
          _statusFilter = value;
          _onFilterChanged();
        }
      },
    );
  }

  Widget _buildCustomerDropdown() {
    return DropdownButtonFormField<int?>(
      decoration: InputDecoration(
        labelText: 'Customer',
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
        const DropdownMenuItem(value: null, child: Text('All Customers')),
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

  Widget _buildGroupedView(String currency) {
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
                    if (_groupBy == 'status') _buildStatusChip(key),
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
                children: groupOrders.map((order) => _buildOrderListTile(order, currency)).toList(),
              );
            },
          ),
        ),
        _buildPaginationControls(),
      ],
    );
  }

  Widget _buildOrderListTile(OrderFullDetails orderDetails, String currency) {
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
          _buildStatusChip(order.status),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleOrderAction(value, order, orderDetails),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'view', child: Row(children: [Icon(Icons.visibility, size: 18), SizedBox(width: 8), Text('View')])),
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
              const PopupMenuItem(value: 'status', child: Row(children: [Icon(Icons.swap_horiz, size: 18), SizedBox(width: 8), Text('Change Status')])),
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
            ],
          ),
        ],
      ),
      onTap: () => _editOrder(order),
    );
  }

  Widget _buildOrdersTable(String currency) {
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
                label: const Text('Code'),
                size: ColumnSize.M,
                onSort: (_, __) => _onSort('code'),
              ),
              const DataColumn2(label: Text('Customer'), size: ColumnSize.M),
              DataColumn2(
                label: const Text('User'),
                size: ColumnSize.S,
                onSort: (_, __) => _onSort('takenBy'),
              ),
              const DataColumn2(label: Text('Products'), size: ColumnSize.S, numeric: true),
              const DataColumn2(label: Text('Total'), size: ColumnSize.S, numeric: true),
              const DataColumn2(label: Text('Paid'), size: ColumnSize.S, numeric: true),
              DataColumn2(
                label: const Text('Status'),
                size: ColumnSize.M,
                onSort: (_, __) => _onSort('status'),
              ),
              DataColumn2(
                label: const Text('Date'),
                size: ColumnSize.M,
                onSort: (_, __) => _onSort('createdAt'),
              ),
              const DataColumn2(label: Text('Actions'), size: ColumnSize.L),
            ],
            rows: orders.map((orderDetails) => _buildDataRow(orderDetails, currency)).toList(),
          ),
        ),
        _buildPaginationControls(),
      ],
    );
  }

  DataRow _buildDataRow(OrderFullDetails orderDetails, String currency) {
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
                  message: needsSync ? 'Not synced' : 'Synced',
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
        DataCell(_buildStatusChip(order.status)),
        DataCell(Text(_formatDate(order.date), style: const TextStyle(fontSize: 11))),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility, size: 18),
                onPressed: () => _showOrderDetails(order),
                tooltip: 'View',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              PermissionIconButton(
                permission: Permissions.ordersUpdate,
                icon: const Icon(Icons.edit, size: 18, color: Colors.green),
                onPressed: () => _editOrder(order),
                tooltip: 'Edit',
              ),
              PermissionIconButton(
                permission: Permissions.ordersUpdate,
                icon: const Icon(Icons.swap_horiz, size: 18, color: Colors.blue),
                onPressed: () => _showChangeStatusDialog(order),
                tooltip: 'Status',
              ),
              PermissionIconButton(
                permission: Permissions.ordersDelete,
                icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                onPressed: () => _deleteOrder(order),
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        status,
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

  Widget _buildPaginationControls() {
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
                ? 'Showing $startItem-$endItem of $totalItems orders'
                : 'No orders',
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
                  'Page ${_currentPage + 1} of ${totalPages > 0 ? totalPages : 1}',
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

  Widget _buildEmptyView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No orders found',
            style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
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
            label: const Text('Clear Filters'),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            'Error loading orders',
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
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  // Helper Functions
  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getDateRangeText() {
    if (_startDate == null && _endDate == null) {
      return 'Date Range';
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Order'),
        content: Text('Are you sure you want to delete order ${order.code}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
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
            const SnackBar(content: Text('Order deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting order: $e')),
          );
        }
      }
    }
  }

  void _showChangeStatusDialog(Order order) async {
    final statuses = ['ONHOLD', 'PENDING', 'PREPARING', 'READY', 'DELIVERED', 'COMPLETED', 'CANCELED'];
    String? selectedStatus = order.status;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) {
          return AlertDialog(
            title: Text('Change Status - ${order.code}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Current: ', style: TextStyle(fontWeight: FontWeight.w500)),
                    _buildStatusChip(order.status),
                    const SizedBox(width: 8),
                    if (order.isSynced)
                      const Icon(Icons.cloud_done, size: 16, color: Colors.green)
                    else if (order.status == 'COMPLETED')
                      const Icon(Icons.cloud_off, size: 16, color: Colors.orange),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('New status:', style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: statuses.map((status) => ChoiceChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(status, style: const TextStyle(fontSize: 11)),
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
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selectedStatus != null && selectedStatus != order.status
                    ? () => Navigator.pop(dialogContext, selectedStatus)
                    : null,
                child: const Text('Change'),
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

  Future<void> _changeOrderStatus(Order order, String newStatus) async {
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
        String message = 'Status changed to $newStatus';
        if (newStatus == 'COMPLETED') {
          message += synced ? ' and synced' : (isOnline ? ' (sync pending)' : ' (will sync when online)');
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
          SnackBar(content: Text('Error changing status: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _syncAll() async {
    final isOnline = ref.read(networkStateProvider);

    if (!isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No network connection'), backgroundColor: Colors.red),
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
          SnackBar(content: Text('Sync error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showPendingOperationsDialog() async {
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
              Text('Pending Operations (${operations.length})'),
            ],
          ),
          content: SizedBox(
            width: 600,
            height: 400,
            child: operations.isEmpty
                ? const Center(child: Text('No pending operations'))
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
                              Text('Server ID: ${op.serverId ?? "Not synced yet"}'),
                              Text('Created: ${_formatDate(op.createdAt)}'),
                              if (op.retryCount > 0)
                                Text('Retries: ${op.retryCount}', style: const TextStyle(color: Colors.orange)),
                              if (op.lastError != null)
                                Text('Error: ${op.lastError}', style: const TextStyle(color: Colors.red, fontSize: 11)),
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
                            tooltip: 'Remove from queue',
                          ),
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            if (operations.isNotEmpty)
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _syncAll();
                },
                icon: const Icon(Icons.sync),
                label: const Text('Sync Now'),
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading operations: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ========== SEARCH BY CODE FUNCTIONALITY ==========

  void _showSearchByCodeDialog() {
    final TextEditingController codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.search),
            SizedBox(width: 12),
            Text('Search Order by Code'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: codeController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Enter order code (e.g., ORD-001)',
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
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final code = codeController.text.trim();
              if (code.isNotEmpty) {
                Navigator.of(dialogContext).pop();
                _searchOrderByCode(code);
              }
            },
            child: const Text('Search'),
          ),
        ],
      ),
    );
  }

  Future<void> _searchOrderByCode(String orderCode) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Searching for order...'),
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
        if (mounted) _showErrorSnackBar('Order not found locally and you are offline');
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
                          'Order ${order.code}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Order Details',
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
                    const Text('Order Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildInfoRow('Order ID', '#${order.id}'),
                            _buildInfoRow('Order Code', order.code),
                            _buildInfoRow('Status', order.status),
                            _buildInfoRow('Type', order.type.replaceAll('_', ' ')),
                            _buildInfoRow('Number of Persons', '${order.persons}'),
                            if (fullDetails.tableName != null)
                              _buildInfoRow('Table', fullDetails.tableName!),
                            if (fullDetails.customerName != null)
                              _buildInfoRow('Customer', fullDetails.customerName!),
                            _buildInfoRow('Username', fullDetails.userName ?? 'N/A'),
                            _buildInfoRow('Date', _formatFullDateTime(order.date)),
                            _buildInfoRow('Synced', order.isSynced ? 'Yes' : 'No'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Order Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...fullDetails.items.map((item) => _buildOrderItem(context, item, currency)),
                    const SizedBox(height: 24),
                    const Text('Financial Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildFinancialCard(context, currency),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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

  Widget _buildOrderItem(BuildContext context, OrderItemDetails item, String currency) {
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
                              item.productName,
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
                  'Paid in Ticket #${item.ticketNum ?? 'N/A'}',
                  style: TextStyle(fontSize: 12, color: Colors.green[800], fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialCard(BuildContext context, String currency) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildFinancialRow('Product Count', fullDetails.productCount.toString(), isBold: false),
            const Divider(height: 20),
            _buildFinancialRow('Subtotal', CurrencyFormatter.formatWithCurrency(fullDetails.subtotal, currency)),
            if (fullDetails.itemDiscount > 0)
              _buildFinancialRow('Item Discounts', '-${CurrencyFormatter.formatWithCurrency(fullDetails.itemDiscount, currency)}', color: Colors.orange),
            if (fullDetails.discountPercentage > 0)
              _buildFinancialRow(
                'Manual Discount (${fullDetails.discountPercentage.toStringAsFixed(0)}%)',
                '-${CurrencyFormatter.formatWithCurrency(fullDetails.manualDiscountAmount, currency)}',
                color: Colors.deepOrange,
              ),
            if (fullDetails.totalDiscount > 0)
              _buildFinancialRow('Total Discount', '-${CurrencyFormatter.formatWithCurrency(fullDetails.totalDiscount, currency)}', color: Colors.red),
            _buildFinancialRow('Total TVA', CurrencyFormatter.formatWithCurrency(fullDetails.totalTva, currency)),
            const Divider(height: 20, thickness: 2),
            _buildFinancialRow('Total', CurrencyFormatter.formatWithCurrency(fullDetails.total, currency), fontSize: 18, isBold: true),
            const Divider(height: 20),
            _buildFinancialRow(
              'Total Paid',
              CurrencyFormatter.formatWithCurrency(fullDetails.totalPaid, currency),
              color: fullDetails.totalPaid >= fullDetails.total ? Colors.green : Colors.orange,
              isBold: true,
            ),
            _buildFinancialRow(
              'Balance',
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


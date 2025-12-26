// filepath: /home/arecrea/prj/posecrea/lib/presentation/widgets/orders_management_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../domain/models/order_models.dart';
import '../../providers/order_provider.dart';
import '../../data/database/app_database.dart';

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

  // Pagination
  int _currentPage = 0;
  final int _rowsPerPage = 10;

  // Sorting
  int? _sortColumnIndex;
  bool _sortAscending = true;

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderRepo = ref.watch(orderRepositoryProvider);
    final currentOrderAsync = ref.watch(orderProvider);

    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildFiltersBar(),
          Expanded(
            child: FutureBuilder(
              future: orderRepo.getAllOrdersWithFullDetails(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _buildErrorView(snapshot.error.toString());
                }

                List<OrderFullDetails> orders = snapshot.data ?? [];
                orders = _applyFilters(orders);
                orders = _applySorting(orders);

                if (orders.isEmpty) {
                  return _buildEmptyView();
                }

                return _buildOrdersTable(orders);
              },
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Orders Management'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(() {}),
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
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by code, username...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                  _currentPage = 0;
                });
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildStatusDropdown(),
          ),
          const SizedBox(width: 16),
          OutlinedButton.icon(
            onPressed: _showDateRangePicker,
            icon: const Icon(Icons.date_range),
            label: Text(_getDateRangeText()),
          ),
          const SizedBox(width: 8),
          if (_startDate != null || _endDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _startDate = null;
                  _endDate = null;
                });
              },
              tooltip: 'Clear date filter',
            ),
        ],
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return DropdownButtonFormField<String>(
      value: _statusFilter,
      decoration: InputDecoration(
        labelText: 'Status',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: const [
        DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
        DropdownMenuItem(value: 'ONHOLD', child: Text('On Hold')),
        DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
        DropdownMenuItem(value: 'PREPARING', child: Text('Preparing')),
        DropdownMenuItem(value: 'READY', child: Text('Ready')),
        DropdownMenuItem(value: 'DELIVERED', child: Text('Delivered')),
        DropdownMenuItem(value: 'CANCELED', child: Text('Canceled')),
      ],
      onChanged: (value) {
        setState(() {
          _statusFilter = value!;
          _currentPage = 0;
        });
      },
    );
  }

  Widget _buildOrdersTable(List orders) {
    final paginatedOrders = _paginateOrders(orders);
    final totalPages = (orders.length / _rowsPerPage).ceil();

    return Column(
      children: [
        Expanded(
          child: DataTable2(
            columnSpacing: 12,
            horizontalMargin: 12,
            minWidth: 1200,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            headingRowColor: MaterialStateProperty
                .all(Colors.grey[200]),
            columns: [
              DataColumn2(label: const Text('ID', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S, onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)),
              DataColumn2(label: const Text('Code', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.M, onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)),
              DataColumn2(label: const Text('Username', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.M, onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)),
              DataColumn2(label: const Text('Products', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S, numeric: true, onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)),
              DataColumn2(label: const Text('Discount', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S, numeric: true, onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)),
              DataColumn2(label: const Text('TVA',
                  style: TextStyle(fontWeight: FontWeight.bold)),
                  size: ColumnSize.S,
                  numeric: true,
                  onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)),

              DataColumn2(label: const Text('Subtotal',
                  style: TextStyle(fontWeight: FontWeight.bold)),
                  size: ColumnSize.S,
                  numeric: true,
                  onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)
              ),
              DataColumn2(label: const Text('Total', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S, numeric: true, onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)),

              DataColumn2(label: const Text('Paid', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S, numeric: true, onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)),

              DataColumn2(label: const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.M, onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)),

              DataColumn2(label: const Text('Date',
                  style: TextStyle(fontWeight: FontWeight.bold)),
                  size: ColumnSize.M,
                  onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending)),
              DataColumn2(label: const Text('Actions',
                  style: TextStyle(fontWeight: FontWeight.bold)),
                  size: ColumnSize.L,
                  fixedWidth: 150
              ),
            ],
            rows: paginatedOrders.map((orderDetails) => _buildDataRow(orderDetails)).toList(),
          ),
        ),
        _buildPaginationControls(orders.length, totalPages),
      ],
    );
  }

  DataRow _buildDataRow(OrderFullDetails orderDetails) {
    final order = orderDetails.order;
    return DataRow(
      cells: [
        DataCell(Text(order.id.toString())),
        DataCell(Text(order.code)),
        DataCell(Text(orderDetails.userName ?? 'N/A')),
        DataCell(Text(orderDetails.productCount.toString())),
        DataCell(Text('\$${orderDetails.totalDiscount.toStringAsFixed(2)}')),
        DataCell(Text('\$${orderDetails.totalTva.toStringAsFixed(2)}')),
        DataCell(Text('\$${orderDetails.subtotal.toStringAsFixed(2)}')),
        DataCell(
          Text(
            '\$${orderDetails.total.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        DataCell(
          Text(
            '\$${orderDetails.totalPaid.toStringAsFixed(2)}',
            style: TextStyle(
              color: orderDetails.totalPaid >= orderDetails.total ? Colors.green : Colors.orange,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        DataCell(_buildStatusChip(order.status)),
        DataCell(Text(_formatDate(order.date))),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility, size: 20),
                onPressed: () => _showOrderDetails(order),
                tooltip: 'View Details',
              ),
              IconButton(
                icon: const Icon(Icons.edit, size: 20),
                onPressed: () => _editOrder(order),
                tooltip: 'Edit Order',
              ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                onPressed: () => _deleteOrder(order),
                tooltip: 'Delete Order',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'ONHOLD':
        color = Colors.orange;
        break;
      case 'PENDING':
        color = Colors.blue;
        break;
      case 'PREPARING':
        color = Colors.purple;
        break;
      case 'READY':
        color = Colors.green;
        break;
      case 'DELIVERED':
        color = Colors.grey;
        break;
      case 'CANCELED':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildPaginationControls(int totalItems, int totalPages) {
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
            'Showing ${_currentPage * _rowsPerPage + 1}-${((_currentPage + 1) * _rowsPerPage).clamp(0, totalItems)} of $totalItems orders',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _currentPage > 0 ? () => setState(() => _currentPage = 0) : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
              ),
              Text(
                'Page ${_currentPage + 1} of $totalPages',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage = totalPages - 1) : null,
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
        ],
      ),
    );
  }

  // Helper Functions

  List<OrderFullDetails> _applyFilters(List<OrderFullDetails> orders) {
    var filtered = orders;

    if (_statusFilter != 'ALL') {
      filtered = filtered.where((o) => o.order.status == _statusFilter).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((o) {
        return o.order.code.toLowerCase().contains(query) ||
            (o.userName?.toLowerCase().contains(query) ?? false);
      }).toList();
    }

    if (_startDate != null) {
      filtered = filtered.where((o) => o.order.date.isAfter(_startDate!)).toList();
    }
    if (_endDate != null) {
      filtered = filtered.where((o) => o.order.date.isBefore(_endDate!.add(const Duration(days: 1)))).toList();
    }

    return filtered;
  }

  List<OrderFullDetails> _applySorting(List<OrderFullDetails> orders) {
    if (_sortColumnIndex == null) return orders;

    orders.sort((a, b) {
      int comparison = 0;
      switch (_sortColumnIndex) {
        case 0: // ID
          comparison = a.order.id.compareTo(b.order.id);
          break;
        case 1: // Code
          comparison = a.order.code.compareTo(b.order.code);
          break;
        case 2: // Username
          comparison = (a.userName ?? '').compareTo(b.userName ?? '');
          break;
        case 3: // Products
          comparison = a.productCount.compareTo(b.productCount);
          break;
        case 4: // Discount
          comparison = a.totalDiscount.compareTo(b.totalDiscount);
          break;
        case 5: // TVA
          comparison = a.totalTva.compareTo(b.totalTva);
          break;
        case 6: // Subtotal
          comparison = a.subtotal.compareTo(b.subtotal);
          break;
        case 7: // Total
          comparison = a.total.compareTo(b.total);
          break;
        case 8: // Paid
          comparison = a.totalPaid.compareTo(b.totalPaid);
          break;
        case 9: // Status
          comparison = a.order.status.compareTo(b.order.status);
          break;
        case 10: // Date
          comparison = a.order.date.compareTo(b.order.date);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });
    return orders;
  }

  List _paginateOrders(List orders) {
    final start = _currentPage * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, orders.length);
    return orders.sublist(start, end);
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getDateRangeText() {
    if (_startDate == null && _endDate == null) {
      return 'Date Range';
    }
    final start = _startDate != null ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}' : '...';
    final end = _endDate != null ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}' : '...';
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
      setState(() {
        _startDate = result.start;
        _endDate = result.end;
        _currentPage = 0;
      });
    }
  }

  // CRUD Operations
  void _showOrderDetails(Order order) async {
    final orderRepo = ref.read(orderRepositoryProvider);
    final fullDetails = await orderRepo.getOrderFullDetails(order.id);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => _OrderDetailsDialog(fullDetails: fullDetails),
    );
  }

  void _editOrder(Order order) async {
    // sets the current order to the selected order
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
      builder: (context) => AlertDialog(
        title: const Text('Delete Order'),
        content: Text('Are you sure you want to delete order ${order.code}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
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
        setState(() {});
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
}

// Order Details Dialog
class _OrderDetailsDialog extends StatelessWidget {

  final OrderFullDetails fullDetails;

  const _OrderDetailsDialog({required this.fullDetails});

  @override
  Widget build(BuildContext context) {
    final order = fullDetails.order;

    return Dialog(
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 800),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                            color: Colors.white.withOpacity(0.9),
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
                            _buildInfoRow('Number of Persons', '${order.persons ?? 1}'),
                            if (fullDetails.tableName != null)
                              _buildInfoRow('Table', fullDetails.tableName!),
                            _buildInfoRow('Username', fullDetails.userName ?? 'N/A'),
                            _buildInfoRow('Date', _formatFullDateTime(order.date)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Order Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...fullDetails.items.map((item) => _buildOrderItem(item)),
                    const SizedBox(height: 24),
                    const Text('Financial Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    _buildFinancialCard(),
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
            width: 120,
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
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderItem(dynamic item) {
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
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
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
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
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
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${item.totalPrice.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.green),
                ),
                child: Text(
                  'Paid in Ticket #${item.ticketNum ?? 'N/A'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFinancialCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildFinancialRow('Product Count', fullDetails.productCount.toString(), isBold: false),
            const Divider(height: 20),
            _buildFinancialRow('Subtotal', '\$${fullDetails.subtotal.toStringAsFixed(2)}'),
            if (fullDetails.itemDiscount > 0)
              _buildFinancialRow('Item Discounts', '-\$${fullDetails.itemDiscount.toStringAsFixed(2)}', color: Colors.orange),
            if (fullDetails.discountPercentage > 0)
              _buildFinancialRow(
                'Manual Discount (${fullDetails.discountPercentage.toStringAsFixed(0)}%)',
                '-\$${fullDetails.manualDiscountAmount.toStringAsFixed(2)}',
                color: Colors.deepOrange,
              ),
            if (fullDetails.totalDiscount > 0)
              _buildFinancialRow('Total Discount', '-\$${fullDetails.totalDiscount.toStringAsFixed(2)}', color: Colors.red),
            _buildFinancialRow('Total TVA', '\$${fullDetails.totalTva.toStringAsFixed(2)}'),
            const Divider(height: 20, thickness: 2),
            _buildFinancialRow('Total', '\$${fullDetails.total.toStringAsFixed(2)}', fontSize: 18, isBold: true),
            const Divider(height: 20),
            _buildFinancialRow(
              'Total Paid',
              '\$${fullDetails.totalPaid.toStringAsFixed(2)}',
              color: fullDetails.totalPaid >= fullDetails.total ? Colors.green : Colors.orange,
              isBold: true,
            ),
            _buildFinancialRow(
              'Balance',
              '\$${(fullDetails.total - fullDetails.totalPaid).toStringAsFixed(2)}',
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


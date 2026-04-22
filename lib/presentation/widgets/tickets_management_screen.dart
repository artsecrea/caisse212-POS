import 'package:flutter/material.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data_table_2/data_table_2.dart';
import 'package:drift/drift.dart' hide Column;
import '../../data/database/app_database.dart';
import '../../providers/ticket_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/network_provider.dart';
import '../../services/data_sync_service.dart';
import '../../services/pending_operations_service.dart';
import '../../services/permission_service.dart';

class TicketsManagementScreen extends ConsumerStatefulWidget {
  const TicketsManagementScreen({super.key});

  @override
  ConsumerState<TicketsManagementScreen> createState() => _TicketsManagementScreenState();
}

class _TicketsManagementScreenState extends ConsumerState<TicketsManagementScreen> {
  // Filters
  String _statusFilter = 'ALL';
  String _searchQuery = '';

  // Pagination
  int _currentPage = 0;
  final int _rowsPerPage = 10;

  // Sorting
  int? _sortColumnIndex;
  bool _sortAscending = true;

  // Sync state
  bool _isSyncing = false;
  int _pendingOperationsCount = 0;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPendingOperationsCount();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPendingOperationsCount() async {
    try {
      final database = ref.read(databaseProvider);
      final pendingOpsService = PendingOperationsService(database);
      final operations = await pendingOpsService.getPendingOperationsByType('TICKET');
      if (mounted) {
        setState(() {
          _pendingOperationsCount = operations.length;
        });
      }
    } catch (e) {
      // Ignore errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticketRepo = ref.watch(ticketRepositoryProvider);

    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildFiltersBar(),
          Expanded(
            child: FutureBuilder<List<TicketWithDetails>>(
              future: ticketRepo.getTicketsWithDetails(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _buildErrorView(snapshot.error.toString());
                }

                List<TicketWithDetails> tickets = snapshot.data ?? [];
                tickets = _applyFilters(tickets);
                tickets = _applySorting(tickets);

                if (tickets.isEmpty) {
                  return _buildEmptyView();
                }

                return _buildTicketsTable(tickets);
              },
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isOnline = ref.watch(lastKnownOnlineStatusProvider);

    return AppBar(
      title: const Text('Tickets Management'),
      actions: [
        // Pending operations indicator
        if (_pendingOperationsCount > 0)
          Builder(
            builder: (context) {
              final permissionService = ref.watch(permissionServiceProvider);
              final hasPermission = permissionService.hasPermission(Permissions.viewPendingOperations);
              return IconButton(
                icon: Badge(
                  label: Text('$_pendingOperationsCount'),
                  child: const Icon(Icons.pending_actions),
                ),
                onPressed: hasPermission ? _showPendingOperationsDialog : null,
                tooltip: hasPermission ? 'Pending Operations' : 'Insufficient permissions',
              );
            },
          ),
        // Sync all button
        Builder(
          builder: (context) {
            final permissionService = ref.watch(permissionServiceProvider);
            final hasPermission = permissionService.hasPermission(Permissions.syncTickets);
            return IconButton(
              icon: _isSyncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isOnline ? Icons.cloud_sync : Icons.cloud_off,
                      color: isOnline ? null : Colors.grey,
                    ),
              onPressed: hasPermission && isOnline && !_isSyncing ? _syncAllTickets : null,
              tooltip: !hasPermission
                  ? 'Insufficient permissions'
                  : isOnline
                      ? 'Sync All Tickets'
                      : 'Offline',
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            setState(() {});
            _loadPendingOperationsCount();
          },
          tooltip: 'Refresh',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Future<void> _syncAllTickets() async {
    setState(() => _isSyncing = true);

    try {
      final database = ref.read(databaseProvider);
      final apiService = ref.read(apiServiceProvider);
      final syncService = DataSyncService(database, apiService);

      // Sync pending operations first
      await syncService.syncPendingOperations();

      // Sync unsynced tickets
      final syncedCount = await syncService.syncTicketsBulk();

      await _loadPendingOperationsCount();

      if (mounted) {
        setState(() {}); // Refresh the list
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synced $syncedCount tickets'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _showPendingOperationsDialog() async {
    final database = ref.read(databaseProvider);
    final pendingOpsService = PendingOperationsService(database);
    final operations = await pendingOpsService.getPendingOperationsByType('TICKET');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pending Ticket Operations'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: operations.isEmpty
              ? const Center(child: Text('No pending operations'))
              : ListView.builder(
                  itemCount: operations.length,
                  itemBuilder: (context, index) {
                    final op = operations[index];
                    return ListTile(
                      leading: Icon(
                        op.operationType == 'DELETE' ? Icons.delete : Icons.edit,
                        color: op.operationType == 'DELETE' ? Colors.red : Colors.blue,
                      ),
                      title: Text('${op.operationType} Ticket #${op.entityId}'),
                      subtitle: Text(
                        'Created: ${_formatDateTime(op.createdAt)}\n'
                        'Retries: ${op.retryCount}${op.lastError != null ? '\nError: ${op.lastError}' : ''}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.grey),
                        onPressed: () async {
                          await pendingOpsService.markCompleted(op.id);
                          Navigator.of(context).pop();
                          _loadPendingOperationsCount();
                        },
                        tooltip: 'Remove from queue',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (operations.isNotEmpty)
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _syncAllTickets();
              },
              child: const Text('Sync Now'),
            ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
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
                hintText: 'Search by ticket number, order ID...',
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
        ],
      ),
    );
  }

  Widget _buildStatusDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _statusFilter,
      decoration: InputDecoration(
        labelText: 'Status',
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      items: const [
        DropdownMenuItem(value: 'ALL', child: Text('All Statuses')),
        DropdownMenuItem(value: 'PAID', child: Text('Paid')),
        DropdownMenuItem(value: 'UNPAID', child: Text('Unpaid')),
        DropdownMenuItem(value: 'CANCELLED', child: Text('Cancelled')),
      ],
      onChanged: (value) {
        setState(() {
          _statusFilter = value!;
          _currentPage = 0;
        });
      },
    );
  }

  Widget _buildTicketsTable(List<TicketWithDetails> tickets) {
    final paginatedTickets = _paginateTickets(tickets);
    final totalPages = (tickets.length / _rowsPerPage).ceil();

    return Column(
      children: [
        Expanded(
          child: DataTable2(
            columnSpacing: 12,
            horizontalMargin: 12,
            minWidth: 1000,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            columns: [
              DataColumn2(
                label: const Text('ID', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Ticket #', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Order ID', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                numeric: true,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Items', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                numeric: true,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Amount', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                numeric: true,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: (columnIndex, ascending) => _onSort(columnIndex, ascending),
              ),
              DataColumn2(
                label: const Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.L,
                fixedWidth: 120,
              ),
            ],
            rows: paginatedTickets.map((ticketDetails) => _buildDataRow(ticketDetails)).toList(),
          ),
        ),
        _buildPaginationControls(tickets.length, totalPages),
      ],
    );
  }

  DataRow _buildDataRow(TicketWithDetails ticketDetails) {
    final ticket = ticketDetails.ticket;
    final needsSync = ticket.isPaid && !ticket.isSynced && !ticket.isCancelled;

    return DataRow(
      color: ticket.isCancelled
          ? WidgetStateProperty.all(Colors.red.withValues(alpha: 0.05))
          : null,
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ticket.id.toString(),
                style: ticket.isCancelled
                    ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 4),
              if (ticket.isCancelled)
                const Tooltip(
                  message: 'Cancelled',
                  child: Icon(Icons.cancel, size: 14, color: Colors.red),
                )
              else if (ticket.isPaid)
                Tooltip(
                  message: needsSync ? 'Not synced to server' : 'Synced to server',
                  child: Icon(
                    needsSync ? Icons.cloud_off : Icons.cloud_done,
                    size: 14,
                    color: needsSync ? Colors.orange : Colors.green,
                  ),
                ),
            ],
          ),
        ),
        DataCell(Text(
          ticket.num,
          style: ticket.isCancelled
              ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)
              : null,
        )),
        DataCell(Text(ticket.orderId.toString())),
        DataCell(Text(ticketDetails.itemCount.toString())),
        DataCell(Text(
          '\$${ticket.amount.toStringAsFixed(2)}',
          style: ticket.isCancelled
              ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.grey)
              : null,
        )),
        DataCell(Text(ticket.paymentMethod.toUpperCase())),
        DataCell(_buildStatusChip(ticket.isPaid, isCancelled: ticket.isCancelled)),
        DataCell(Text(_formatDate(ticket.date))),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility, size: 20),
                onPressed: () => _showTicketDetails(ticket, ticketDetails.itemCount),
                tooltip: 'View Details',
              ),
              if (!ticket.isPaid)
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editTicket(ticket),
                  tooltip: 'Edit Ticket',
                ),
              IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                onPressed: () => _deleteTicket(ticket),
                tooltip: 'Delete Ticket',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(bool isPaid, {bool isCancelled = false}) {
    final Color color;
    final String text;

    if (isCancelled) {
      color = Colors.red;
      text = 'CANCELLED';
    } else if (isPaid) {
      color = Colors.green;
      text = 'PAID';
    } else {
      color = Colors.orange;
      text = 'UNPAID';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
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
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${_currentPage * _rowsPerPage + 1}-${((_currentPage + 1) * _rowsPerPage).clamp(0, totalItems)} of $totalItems tickets',
            style: TextStyle(color: Colors.grey[700]),
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
          Icon(Icons.receipt, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No tickets found',
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
            'Error loading tickets',
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

  List<TicketWithDetails> _applyFilters(List<TicketWithDetails> tickets) {
    var filtered = tickets;

    if (_statusFilter != 'ALL') {
      if (_statusFilter == 'CANCELLED') {
        filtered = filtered.where((t) => t.ticket.isCancelled).toList();
      } else if (_statusFilter == 'PAID') {
        filtered = filtered.where((t) => t.ticket.isPaid && !t.ticket.isCancelled).toList();
      } else if (_statusFilter == 'UNPAID') {
        filtered = filtered.where((t) => !t.ticket.isPaid && !t.ticket.isCancelled).toList();
      }
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((t) {
        return t.ticket.num.toLowerCase().contains(query) ||
            t.ticket.orderId.toString().contains(query);
      }).toList();
    }

    return filtered;
  }

  List<TicketWithDetails> _applySorting(List<TicketWithDetails> tickets) {
    if (_sortColumnIndex == null) return tickets;

    tickets.sort((a, b) {
      int comparison = 0;
      switch (_sortColumnIndex) {
        case 0: // ID
          comparison = a.ticket.id.compareTo(b.ticket.id);
          break;
        case 1: // Ticket #
          comparison = a.ticket.num.compareTo(b.ticket.num);
          break;
        case 2: // Order ID
          comparison = a.ticket.orderId.compareTo(b.ticket.orderId);
          break;
        case 3: // Items
          comparison = a.itemCount.compareTo(b.itemCount);
          break;
        case 4: // Amount
          comparison = a.ticket.amount.compareTo(b.ticket.amount);
          break;
        case 5: // Payment Method
          comparison = a.ticket.paymentMethod.compareTo(b.ticket.paymentMethod);
          break;
        case 6: // Status
          comparison = (a.ticket.isPaid ? 1 : 0).compareTo(b.ticket.isPaid ? 1 : 0);
          break;
        case 7: // Date
          comparison = a.ticket.date.compareTo(b.ticket.date);
          break;
      }
      return _sortAscending ? comparison : -comparison;
    });
    return tickets;
  }

  List<TicketWithDetails> _paginateTickets(List<TicketWithDetails> tickets) {
    final start = _currentPage * _rowsPerPage;
    final end = (start + _rowsPerPage).clamp(0, tickets.length);
    return tickets.sublist(start, end);
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

  // CRUD Operations
  void _showTicketDetails(Ticket ticket, int itemCount) async {
    // Get order products for this ticket
    final database = ref.read(databaseProvider);
    final items = await (database.select(database.orderProducts)
          ..where((tbl) => tbl.ticketId.equals(ticket.id)))
        .get();

    // Get product names for each item
    final itemsWithNames = <Map<String, dynamic>>[];
    for (final item in items) {
      final product = await (database.select(database.products)
            ..where((tbl) => tbl.id.equals(item.productId)))
          .getSingleOrNull();

      itemsWithNames.add({
        'product': item,
        'productName': product?.name ?? 'Unknown Product',
      });
    }

    // Get order details
    final orderData = await (database.select(database.orders)
          ..where((tbl) => tbl.id.equals(ticket.orderId)))
        .getSingleOrNull();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => _TicketDetailsDialog(
        ticket: ticket,
        itemCount: itemCount,
        items: itemsWithNames,
        orderCode: orderData?.code ?? 'N/A',
      ),
    );
  }

  void _editTicket(Ticket ticket) async {
    // Show edit dialog
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditTicketDialog(ticket: ticket),
    );

    if (result != null && mounted) {
      try {
        final ticketRepo = ref.read(ticketRepositoryProvider);
        await ticketRepo.updateTicket(
          ticket.id,
          TicketsCompanion(
            paymentMethod: Value(result['paymentMethod'] as String),
            amount: Value(result['amount'] as double),
            updatedAt: Value(DateTime.now()),
          ),
        );

        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ticket updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating ticket: $e')),
          );
        }
      }
    }
  }

  void _deleteTicket(Ticket ticket) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Ticket'),
        content: Text('Are you sure you want to delete ticket ${ticket.num}? This will unlink all items from this ticket.'),
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
        final ticketRepo = ref.read(ticketRepositoryProvider);
        await ticketRepo.deleteTicket(ticket.id);
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ticket deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting ticket: $e')),
          );
        }
      }
    }
  }
}

// Ticket Details Dialog
class _TicketDetailsDialog extends ConsumerWidget {
  final Ticket ticket;
  final int itemCount;
  final List<Map<String, dynamic>> items; // Changed to Map to include product name
  final String orderCode;

  const _TicketDetailsDialog({
    required this.ticket,
    required this.itemCount,
    required this.items,
    required this.orderCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
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
                  const Icon(Icons.receipt, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ticket ${ticket.num}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Ticket Details',
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
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ticket Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildInfoRow('Ticket ID', '#${ticket.id}'),
                            _buildInfoRow('Ticket Number', ticket.num),
                            _buildInfoRow('Order Code', orderCode),
                            _buildInfoRow('Order ID', '#${ticket.orderId}'),
                            _buildInfoRow('Status', ticket.isPaid ? 'PAID' : 'UNPAID'),
                            _buildInfoRow('Payment Method', ticket.paymentMethod.toUpperCase()),
                            _buildInfoRow('Amount', '\$${ticket.amount.toStringAsFixed(2)}'),
                            _buildInfoRow('Print Count', ticket.printCount.toString()),
                            _buildInfoRow('Date', _formatFullDateTime(ticket.date)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text('Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildInfoRow('Total Items', itemCount.toString()),
                            const SizedBox(height: 12),
                            ...items.map((itemData) {
                              final item = itemData['product'] as OrderProduct;
                              final productName = itemData['productName'] as String;

                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        productName,
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    Text(
                                      'x${item.quantity}',
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '\$${item.unitaryPrice.toStringAsFixed(2)}',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _printTicketFromDetails(context, ref, ticket, items),
                      icon: const Icon(Icons.print),
                      label: Text('Print ${ticket.isPaid ? "(Paid)" : "(Unpaid)"}'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ticket.isPaid ? Colors.green : Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printTicketFromDetails(
    BuildContext context,
    WidgetRef ref,
    Ticket ticket,
    List<Map<String, dynamic>> items,
  ) async {
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);
    final database = ref.read(databaseProvider);

    // Get order code
    final orderData = await (database.select(database.orders)
          ..where((tbl) => tbl.id.equals(ticket.orderId)))
        .getSingleOrNull();

    // Build items list for printing with components
    final itemsForPrint = <Map<String, dynamic>>[];
    for (final itemData in items) {
      final item = itemData['product'] as OrderProduct;
      final productName = itemData['productName'] as String;

      // Get components for this order product
      final orderComponents = await (database.select(database.orderProductComponents)
            ..where((tbl) => tbl.orderProductId.equals(item.id)))
          .get();

      // Build components list
      final componentsForPrint = <Map<String, dynamic>>[];
      for (final orderComp in orderComponents) {
        final component = await (database.select(database.components)
              ..where((tbl) => tbl.id.equals(orderComp.componentId)))
            .getSingleOrNull();

        if (component != null) {
          componentsForPrint.add({
            'name': component.name,
            'quantity': orderComp.quantity,
            'price': orderComp.price,
            'isSpecial': orderComp.isSpecial,
          });
        }
      }

      itemsForPrint.add({
        'name': productName,
        'quantity': item.quantity,
        'price': item.unitaryPrice * item.quantity,
        'components': componentsForPrint,
      });
    }

    // Get business name from SharedPreferences
    final prefs = ref.read(sharedPreferencesProvider);
    final businessName = prefs.getString('business_name') ?? 'POS Store';

    try {
      final success = await printingService.printTicketReceipt(
        ticketId: ticket.id,
        ticketNumber: ticket.num,
        amount: ticket.amount,
        paymentMethod: ticket.paymentMethod,
        createdAt: ticket.date,
        items: itemsForPrint,
        orderCode: orderData?.code,
        cashierName: currentUser?.firstName,
        storeName: businessName,
      );

      if (success) {
        // Update print count in database
        await database.customStatement(
          'UPDATE tickets SET print_count = COALESCE(print_count, 0) + 1 WHERE id = ?',
          [ticket.id],
        );

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ticket #${ticket.num} printed successfully${ticket.isPaid ? " (Paid)" : " (Unpaid)"}'),
              backgroundColor: Colors.green,
            ),
          );
          // Refresh the screen
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to print. Check printer connection.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFullDateTime(DateTime date) {
    return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}:${date.second.toString().padLeft(2, '0')}';
  }
}

// Edit Ticket Dialog
class _EditTicketDialog extends StatefulWidget {
  final Ticket ticket;

  const _EditTicketDialog({required this.ticket});

  @override
  State<_EditTicketDialog> createState() => _EditTicketDialogState();
}

class _EditTicketDialogState extends State<_EditTicketDialog> {
  late String _paymentMethod;
  late TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _paymentMethod = widget.ticket.paymentMethod;
    _amountController = TextEditingController(text: widget.ticket.amount.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit Ticket ${widget.ticket.num}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Payment Method',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
              DropdownMenuItem(value: 'check', child: Text('Check')),
              DropdownMenuItem(value: 'other', child: Text('Other')),
            ],
            onChanged: (value) {
              setState(() {
                _paymentMethod = value!;
              });
            },
          ),
          const SizedBox(height: 16),

          OnscreenKeyboardTextField(
            controller: _amountController,
            decoration: const InputDecoration(
              labelText: 'Amount',
              border: OutlineInputBorder(),
              prefixText: '\$',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final amount = double.tryParse(_amountController.text);
            if (amount == null || amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invalid amount')),
              );
              return;
            }

            Navigator.pop(context, {
              'paymentMethod': _paymentMethod,
              'amount': amount,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}


import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../data/database/app_database.dart';
import '../../providers/catalogue_repository.dart';
import '../../providers/floor_repository.dart';
import '../../providers/order_provider.dart';
import '../../providers/ticket_provider.dart';
import '../../services/local_payment_service.dart';
import '../../providers/database_providers.dart';
import '../../providers/network_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/customer_display.dart';
import '../../utils/currency_formatter.dart';
import 'admin_mode_chip.dart';
import 'delivery_fee_totals_chip.dart';
import './adaptive_text_field.dart';
import '../../utils/snackbar_helper.dart';

class TicketsManagementScreen extends ConsumerStatefulWidget {
  const TicketsManagementScreen({super.key});

  @override
  ConsumerState<TicketsManagementScreen> createState() => _TicketsManagementScreenState();
}

class _TicketsManagementScreenState extends ConsumerState<TicketsManagementScreen> {
  // Filters
  String _statusFilter = 'ALL';
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;

  // Batch reprint state
  bool _isReprintingAll = false;

  // Pagination
  int _currentPage = 0;
  final int _rowsPerPage = 10;

  // Sorting — default: id DESC (newest first)
  int _sortColumnIndex = 0;
  bool _sortAscending = false;

  // Sync state
  bool _isSyncing = false;
  int _pendingOperationsCount = 0;

  // DB-paged future — rebuilt whenever filters / sort / page change
  late Future<(List<TicketWithDetails>, int)> _pageFuture;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPendingOperationsCount();
    _refreshFuture();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refreshFuture() {
    final repo = ref.read(ticketRepositoryProvider);
    setState(() {
      _pageFuture = repo.getTicketsPage(
        offset: _currentPage * _rowsPerPage,
        limit: _rowsPerPage,
        statusFilter: _statusFilter,
        searchQuery: _searchQuery,
        startDate: _startDate,
        endDate: _endDate,
        sortColumn: _sortColumnIndex,
        sortAscending: _sortAscending,
      );
    });
  }

  Future<void> _loadPendingOperationsCount() async {
    try {
      final pendingOpsService = ref.read(pendingOperationsServiceProvider);
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
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildFiltersBar(),
          Expanded(
            child: FutureBuilder<(List<TicketWithDetails>, int)>(
              future: _pageFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return _buildErrorView(snapshot.error.toString());
                }

                final (tickets, total) = snapshot.data ?? (<TicketWithDetails>[], 0);

                if (tickets.isEmpty) {
                  return _buildEmptyView();
                }

                return _buildTicketsTable(tickets, total);
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
        const AdminModeChip(),
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
                      color: isOnline ? null : Theme.of(context).colorScheme.onSurfaceVariant,
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
        // Batch reprint all filtered tickets
        Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context)!;
            final permissionService = ref.watch(permissionServiceProvider);
            final hasPermission =
                permissionService.hasPermission(Permissions.ticketsPrint);
            return IconButton(
              icon: _isReprintingAll
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print),
              onPressed: hasPermission && !_isReprintingAll
                  ? _reprintAllFiltered
                  : null,
              tooltip: hasPermission
                  ? l10n.translate('reprint_all_tooltip')
                  : 'Insufficient permissions',
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            _loadPendingOperationsCount();
            _refreshFuture();
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
      final apiService = ref.read(apiServiceProvider);
      final syncService = ref.read(dataSyncServiceFactoryProvider)(apiService);

      // Sync pending operations first
      await syncService.syncPendingOperations();

      // Sync unsynced tickets
      final syncedCount = await syncService.syncTicketsBulk();

      await _loadPendingOperationsCount();

      if (mounted) {
        _refreshFuture();
        SnackBarHelper.showToast('Synced $syncedCount tickets', kind: ToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast('Sync failed: $e', kind: ToastKind.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _showPendingOperationsDialog() async {
    final pendingOpsService = ref.read(pendingOperationsServiceProvider);
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
                        icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                _searchQuery = value;
                _currentPage = 0;
                _refreshFuture();
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildStatusDropdown(),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: _buildDateRangeControl(),
          ),
          const SizedBox(width: 16),
          const DeliveryFeeTotalsChip(),
        ],
      ),
    );
  }

  Widget _buildDateRangeControl() {
    final l10n = AppLocalizations.of(context)!;
    final hasRange = _startDate != null || _endDate != null;
    String label;
    if (_startDate != null && _endDate != null) {
      label = '${_formatShortDate(_startDate!)} - ${_formatShortDate(_endDate!)}';
    } else if (_startDate != null) {
      label = '${l10n.translate('date_from')} ${_formatShortDate(_startDate!)}';
    } else if (_endDate != null) {
      label = '${l10n.translate('date_to')} ${_formatShortDate(_endDate!)}';
    } else {
      label = l10n.translate('date_range');
    }

    return InputDecorator(
      decoration: InputDecoration(
        labelText: l10n.translate('date_range'),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        prefixIcon: const Icon(Icons.date_range),
        suffixIcon: hasRange
            ? IconButton(
                icon: const Icon(Icons.clear),
                tooltip: l10n.translate('clear_dates'),
                onPressed: () {
                  _startDate = null;
                  _endDate = null;
                  _currentPage = 0;
                  _refreshFuture();
                },
              )
            : null,
      ),
      child: InkWell(
        onTap: _pickDateRange,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(label, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = (_startDate != null && _endDate != null)
        ? DateTimeRange(start: _startDate!, end: _endDate!)
        : DateTimeRange(
            start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day),
          );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
    );
    if (picked != null) {
      _startDate = picked.start;
      _endDate = picked.end;
      _currentPage = 0;
      _refreshFuture();
    }
  }

  String _formatShortDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

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
        _statusFilter = value!;
        _currentPage = 0;
        _refreshFuture();
      },
    );
  }

  Widget _buildTicketsTable(List<TicketWithDetails> tickets, int totalCount) {
    final totalPages = (totalCount / _rowsPerPage).ceil().clamp(1, 99999);

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
            rows: tickets.map((ticketDetails) => _buildDataRow(ticketDetails)).toList(),
          ),
        ),
        _buildPaginationControls(totalCount, totalPages),
      ],
    );
  }

  DataRow _buildDataRow(TicketWithDetails ticketDetails) {
    final ticket = ticketDetails.ticket;
    final needsSync = ticket.isPaid && !ticket.isSynced && !ticket.isCancelled;
    final isZLocked = ticketDetails.isZLocked;

    return DataRow(
      color: ticket.isCancelled
          ? WidgetStateProperty.all(Colors.red.withValues(alpha: 0.05))
          : isZLocked
              ? WidgetStateProperty.all(Colors.purple.withValues(alpha: 0.04))
              : null,
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ticket.id.toString(),
                style: ticket.isCancelled
                    ? TextStyle(decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.onSurfaceVariant)
                    : null,
              ),
              const SizedBox(width: 4),
              if (isZLocked)
                const Tooltip(
                  message: 'Z-Report locked',
                  child: Icon(Icons.lock, size: 14, color: Colors.purple),
                )
              else if (ticket.isCancelled)
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
              ? TextStyle(decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.onSurfaceVariant)
              : null,
        )),
        // The per-session number rides in the order column rather than its
        // own: sorting is keyed on column index.
        DataCell(Text(
          ticketDetails.orderNumber != null &&
                  ref.watch(settingsProvider).showOrderNumberInLists
              ? '#${ticketDetails.orderNumber} · ${ticket.orderId}'
              : ticket.orderId.toString(),
        )),
        DataCell(Text(ticketDetails.itemCount.toString())),
        DataCell(Text(
          ref.watch(currencyFormatterProvider).format(
              ticketDetails.displayAmount(
                  includeDeliveryFee:
                      ref.watch(settingsProvider).totalsIncludeDeliveryFee)),
          style: ticket.isCancelled
              ? TextStyle(decoration: TextDecoration.lineThrough, color: Theme.of(context).colorScheme.onSurfaceVariant)
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
              if (!ticket.isPaid &&
                  !isZLocked &&
                  ref.read(permissionServiceProvider).hasPermission(Permissions.ticketsUpdate))
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editTicket(ticket),
                  tooltip: 'Edit Ticket',
                ),
              Builder(
                builder: (context) {
                  final canDelete = ref
                      .read(permissionServiceProvider)
                      .hasPermission(Permissions.ticketsDelete);
                  return IconButton(
                    icon: Icon(Icons.delete,
                        size: 20,
                        color: (isZLocked || !canDelete) ? Theme.of(context).colorScheme.onSurfaceVariant : Colors.red),
                    onPressed:
                        (isZLocked || !canDelete) ? null : () => _deleteTicket(ticket),
                    tooltip: isZLocked
                        ? 'Z-Report locked'
                        : (canDelete
                            ? 'Delete Ticket'
                            : 'Insufficient permissions'),
                  );
                },
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
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing ${_currentPage * _rowsPerPage + 1}-${((_currentPage + 1) * _rowsPerPage).clamp(0, totalItems)} of $totalItems tickets',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.first_page),
                onPressed: _currentPage > 0 ? () { _currentPage = 0; _refreshFuture(); } : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _currentPage > 0 ? () { _currentPage--; _refreshFuture(); } : null,
              ),
              Text(
                'Page ${_currentPage + 1} of $totalPages',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _currentPage < totalPages - 1 ? () { _currentPage++; _refreshFuture(); } : null,
              ),
              IconButton(
                icon: const Icon(Icons.last_page),
                onPressed: _currentPage < totalPages - 1 ? () { _currentPage = totalPages - 1; _refreshFuture(); } : null,
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
          Icon(Icons.receipt, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            'No tickets found',
            style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters',
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
            style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _onSort(int columnIndex, bool ascending) {
    _sortColumnIndex = columnIndex;
    _sortAscending = ascending;
    _currentPage = 0;
    _refreshFuture();
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Reprint a single ticket without UI feedback. Returns whether it succeeded.
  Future<bool> _reprintSingleTicket(Ticket ticket) async {
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);
    final ticketRepo = ref.read(ticketRepositoryProvider);
    final prefs = ref.read(sharedPreferencesProvider);

    final orderData =
        await ref.read(orderRepositoryProvider).getOrderRow(ticket.orderId);

    String? customerName;
    String? customerPhone;
    if (orderData?.clientId != null) {
      final customer = await ref
          .read(customerRepositoryProvider)
          .getById(orderData!.clientId!);
      if (customer != null) {
        customerName = customer.displayLabel;
        customerPhone = customer.phone;
      }
    }

    // Resolve table name for the metadata block — the Order row only
    // holds tableId. Same lookup pattern the order receipt uses.
    String? tableName;
    if (orderData?.tableId != null) {
      final table =
          await ref.read(floorRepositoryProvider).tableById(orderData!.tableId!);
      tableName = table?.name;
    }

    final itemsForPrint = await ticketRepo.printItemsOf(ticket.id);
    final businessName = prefs.getString('business_name');

    final success = await printingService.printTicketReceipt(
      ticketId: ticket.id,
      ticketNumber: ticket.num,
      amount: ticket.amount,
      deliveryFee: orderData == null
          ? null
          : await ticketRepo.deliveryFeeForTicket(orderData.id, ticket.id),
      tvaAmount: await ticketRepo.tvaTotalOf(ticket.id),
      discountAmount: await ticketRepo.discountTotalOf(
          ticket.id, orderData?.discountPercentage ?? 0),
      discountReason: orderData?.discountReason,
      paymentMethod: ticket.paymentMethod,
      createdAt: ticket.date,
      items: itemsForPrint,
      orderCode: orderData?.code,
      cashierName: currentUser?.firstName,
      storeName: businessName,
      storeAddress: prefs.getString('business_address'),
      storePhone: prefs.getString('business_phone'),
      customerName: customerName,
      customerPhone: customerPhone,
      deliveryAddress: orderData?.address,
      reference: orderData?.reference,
      tableName: tableName,
      numberOfPersons: orderData?.persons,
      orderType: orderData?.type,
      isReprint: true,
    );

    if (success) {
      await ref.read(paymentServiceProvider).recordPrint(ticket.id);
    }
    return success;
  }

  /// Reprint every ticket currently matching the active filters, oldest first.
  Future<void> _reprintAllFiltered() async {
    final l10n = AppLocalizations.of(context)!;
    final ticketRepo = ref.read(ticketRepositoryProvider);
    // getAllFilteredTickets already sorts by date ASC
    final filtered = await ticketRepo.getAllFilteredTickets(
      statusFilter: _statusFilter,
      searchQuery: _searchQuery,
      startDate: _startDate,
      endDate: _endDate,
    );

    if (filtered.isEmpty) {
      if (mounted) {
        SnackBarHelper.showToast(l10n.translate('no_tickets_found'), kind: ToastKind.info);
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('reprint_all')),
        content: Text(l10n
            .translate('reprint_all_confirm')
            .replaceAll('{0}', filtered.length.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('reprint_all')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isReprintingAll = true);
    var printed = 0;
    try {
      for (final ticket in filtered) {
        final ok = await _reprintSingleTicket(ticket);
        if (ok) printed++;
      }
    } finally {
      if (mounted) setState(() => _isReprintingAll = false);
    }

    if (mounted) {
      SnackBarHelper.showToast(l10n
              .translate('reprinted_tickets')
              .replaceAll('{0}', printed.toString()), kind: ToastKind.success);
    }
  }

  // CRUD Operations
  void _showTicketDetails(Ticket ticket, int itemCount) async {
    // Get order products for this ticket
    final ticketRepo = ref.read(ticketRepositoryProvider);
    final catalogueRepo = ref.read(catalogueRepositoryProvider);
    final items = await ticketRepo.linesOfTicket(ticket.id);

    // Get product names for each item
    final itemsWithNames = <Map<String, dynamic>>[];
    for (final item in items) {
      final product = await catalogueRepo.productById(item.productId);

      itemsWithNames.add({
        'product': item,
        'productName': product?.name ?? 'Unknown Product',
      });
    }

    // Get order details
    final orderData =
        await ref.read(orderRepositoryProvider).getOrderRow(ticket.orderId);

    final deliveryFee = orderData == null
        ? 0.0
        : await ticketRepo.deliveryFeeForTicket(orderData.id, ticket.id) ??
            0.0;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => _TicketDetailsDialog(
        ticket: ticket,
        itemCount: itemCount,
        items: itemsWithNames,
        orderCode: orderData?.code ?? 'N/A',
        deliveryFee: deliveryFee,
      ),
    );
  }

  void _editTicket(Ticket ticket) async {
    final currencySymbol = ref.read(currencyFormatterProvider).symbol;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditTicketDialog(ticket: ticket, currencySymbol: currencySymbol),
    );

    if (result != null && mounted) {
      try {
        await ref.read(paymentServiceProvider).editTicket(
              ticket.id,
              paymentMethod: result['paymentMethod'] as String,
              amount: result['amount'] as double,
            );

        _refreshFuture();
        if (mounted) {
          SnackBarHelper.showToast('Ticket updated successfully', kind: ToastKind.info);
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showToast('Error updating ticket: $e', kind: ToastKind.error);
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
        await ref.read(paymentServiceProvider).deleteTicket(ticket.id);
        _refreshFuture();
        if (mounted) {
          SnackBarHelper.showToast('Ticket deleted successfully', kind: ToastKind.info);
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showToast('Error deleting ticket: $e', kind: ToastKind.error);
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
  final double deliveryFee; // Non-zero only on the ticket that collected it

  const _TicketDetailsDialog({
    required this.ticket,
    required this.itemCount,
    required this.items,
    required this.orderCode,
    this.deliveryFee = 0.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currencyFormatter = ref.watch(currencyFormatterProvider);
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
                color: AppTheme.bar(Theme.of(context).colorScheme),
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
                            _buildInfoRow(context, 'Ticket ID', '#${ticket.id}'),
                            _buildInfoRow(context, 'Ticket Number', ticket.num),
                            _buildInfoRow(context, 'Order Code', orderCode),
                            _buildInfoRow(context, 'Order ID', '#${ticket.orderId}'),
                            _buildInfoRow(context, 'Status', ticket.isPaid ? 'PAID' : 'UNPAID'),
                            _buildInfoRow(context, 'Payment Method', ticket.paymentMethod.toUpperCase()),
                            if (deliveryFee > 0 &&
                                ref.watch(settingsProvider).totalsIncludeDeliveryFee) ...[
                              _buildInfoRow(context, 'Amount', currencyFormatter.format(ticket.amount)),
                              _buildInfoRow(context, AppLocalizations.of(context)!.translate('delivery_fee'),
                                  currencyFormatter.format(deliveryFee)),
                              _buildInfoRow(context, AppLocalizations.of(context)!.translate('total_collected'),
                                  currencyFormatter.format(ticket.amount + deliveryFee)),
                            ] else
                              _buildInfoRow(context, 'Amount', currencyFormatter.format(ticket.amount)),
                            _buildInfoRow(context, 'Print Count', ticket.printCount.toString()),
                            _buildInfoRow(context, 'Date', _formatFullDateTime(ticket.date)),
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
                            _buildInfoRow(context, 'Total Items', itemCount.toString()),
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
                                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      currencyFormatter.format(item.unitaryPrice),
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
                    child: Builder(
                      builder: (context) {
                        final canPrint = ref
                            .read(permissionServiceProvider)
                            .hasPermission(Permissions.ticketsPrint);
                        return ElevatedButton.icon(
                          onPressed: canPrint
                              ? () => _printTicketFromDetails(context, ref, ticket)
                              : null,
                          icon: const Icon(Icons.print),
                          label: Text('Print ${ticket.isPaid ? "(Paid)" : "(Unpaid)"}'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                ticket.isPaid ? Colors.green : Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        );
                      },
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
  ) async {
    final printingService = ref.read(printingServiceProvider);
    final currentUser = ref.read(currentUserProvider);
    final ticketRepo = ref.read(ticketRepositoryProvider);

    // Get order code
    final orderData =
        await ref.read(orderRepositoryProvider).getOrderRow(ticket.orderId);

    // Get customer information from order
    String? customerName;
    String? customerPhone;
    if (orderData?.clientId != null) {
      final customer = await ref
          .read(customerRepositoryProvider)
          .getById(orderData!.clientId!);
      if (customer != null) {
        customerName = customer.displayLabel;
        customerPhone = customer.phone;
      }
    }

    // Resolve table name for the metadata block — same lookup the order
    // receipt does, kept inline so the reprint path is self-contained.
    String? tableName;
    if (orderData?.tableId != null) {
      final table =
          await ref.read(floorRepositoryProvider).tableById(orderData!.tableId!);
      tableName = table?.name;
    }

    // Build items list for printing with components
    final itemsForPrint = await ticketRepo.printItemsOf(ticket.id);

    // Get business name from SharedPreferences
    final prefs = ref.read(sharedPreferencesProvider);
    final businessName = prefs.getString('business_name');

    try {
      final success = await printingService.printTicketReceipt(
        ticketId: ticket.id,
        ticketNumber: ticket.num,
        amount: ticket.amount,
        deliveryFee: orderData == null
            ? null
            : await ticketRepo.deliveryFeeForTicket(orderData.id, ticket.id),
        tvaAmount: await ticketRepo.tvaTotalOf(ticket.id),
        discountAmount: await ticketRepo.discountTotalOf(
            ticket.id, orderData?.discountPercentage ?? 0),
        discountReason: orderData?.discountReason,
        paymentMethod: ticket.paymentMethod,
        createdAt: ticket.date,
        items: itemsForPrint,
        orderCode: orderData?.code,
        cashierName: currentUser?.firstName,
        storeName: businessName,
        storeAddress: prefs.getString('business_address'),
        storePhone: prefs.getString('business_phone'),
        customerName: customerName,
        customerPhone: customerPhone,
        deliveryAddress: orderData?.address,
        reference: orderData?.reference,
        tableName: tableName,
        numberOfPersons: orderData?.persons,
        orderType: orderData?.type,
        isReprint: true,
      );

      if (success) {
        // Update print count in database
        await ref.read(paymentServiceProvider).recordPrint(ticket.id);

        if (context.mounted) {
          SnackBarHelper.showToast('Ticket #${ticket.num} printed successfully${ticket.isPaid ? " (Paid)" : " (Unpaid)"}', kind: ToastKind.success);
          // Refresh the screen
        }
      } else {
        if (context.mounted) {
          SnackBarHelper.showToast('Failed to print. Check printer connection.', kind: ToastKind.warning);
        }
      }
    } catch (e) {
      if (context.mounted) {
        SnackBarHelper.showToast('Print error: $e', kind: ToastKind.error);
      }
    }
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
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
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
  final String currencySymbol;

  const _EditTicketDialog({required this.ticket, required this.currencySymbol});

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

          AdaptiveKeyboardTextField(
            controller: _amountController,
            decoration: InputDecoration(
              labelText: 'Amount',
              border: const OutlineInputBorder(),
              prefixText: '${widget.currencySymbol} ',
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
              SnackBarHelper.showToast('Invalid amount', kind: ToastKind.error);
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


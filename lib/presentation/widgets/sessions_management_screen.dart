import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/network_provider.dart';
import '../../services/session_service.dart';
import '../../services/activity_log_service.dart';
import '../../services/permission_service.dart';
import '../../services/data_sync_service.dart';
import '../../services/pending_operations_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import 'admin_mode_chip.dart';
import 'close_session_dialog.dart';
import 'permission_guard.dart';
import 'x_report_dialog.dart';

class SessionsManagementScreen extends ConsumerStatefulWidget {
  const SessionsManagementScreen({super.key});

  @override
  ConsumerState<SessionsManagementScreen> createState() => _SessionsManagementScreenState();
}

class _SessionsManagementScreenState extends ConsumerState<SessionsManagementScreen> {
  // Filters
  String _statusFilter = 'ALL';
  String _searchQuery = '';
  DateTime? _startDate;
  DateTime? _endDate;

  // Pagination
  int _currentPage = 0;
  final int _rowsPerPage = 10;

  // Sorting — default: startedAt DESC
  int _sortColumnIndex = 2;
  bool _sortAscending = false;

  // Sync state
  bool _isSyncing = false;
  int _pendingOperationsCount = 0;

  // DB-paged future — rebuilt on filter/sort/page change
  late Future<(List<SessionWithCashier>, int)> _pageFuture;

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
    final db = ref.read(databaseProvider);
    final sessionService = SessionService(db);
    setState(() {
      _pageFuture = sessionService.getSessionsPage(
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
      final database = ref.read(databaseProvider);
      final pendingOpsService = PendingOperationsService(database);
      final operations = await pendingOpsService.getPendingOperationsByType('SESSION');
      if (mounted) {
        setState(() => _pendingOperationsCount = operations.length);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: _buildAppBar(l10n),
      body: Column(
        children: [
          _buildFiltersBar(l10n),
          Expanded(
            child: FutureBuilder<(List<SessionWithCashier>, int)>(
              future: _pageFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _buildErrorView(snapshot.error.toString());
                }
                final (sessions, total) = snapshot.data ?? (<SessionWithCashier>[], 0);
                if (sessions.isEmpty) {
                  return _buildEmptyView(l10n);
                }
                return _buildSessionsTable(sessions, total, l10n);
              },
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(AppLocalizations l10n) {
    final isOnline = ref.watch(lastKnownOnlineStatusProvider);

    return AppBar(
      title: Text(l10n.translate('sessions_management')),
      actions: [
        const AdminModeChip(),
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
                tooltip: hasPermission
                    ? l10n.translate('pending_operations')
                    : l10n.translate('insufficient_permissions'),
              );
            },
          ),
        Builder(
          builder: (context) {
            final permissionService = ref.watch(permissionServiceProvider);
            final hasPermission = permissionService.hasPermission(Permissions.syncSessions);
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
              onPressed: hasPermission && isOnline && !_isSyncing ? _syncAllSessions : null,
              tooltip: !hasPermission
                  ? l10n.translate('insufficient_permissions')
                  : isOnline
                      ? l10n.translate('sync_all_sessions')
                      : l10n.translate('offline'),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () {
            _loadPendingOperationsCount();
            _refreshFuture();
          },
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
          Expanded(
            flex: 2,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.translate('search_by_id'),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
            child: DropdownButtonFormField<String>(
              key: const ValueKey('sessions_filter_status'),
              initialValue: _statusFilter,
              decoration: InputDecoration(
                labelText: l10n.translate('status'),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              items: [
                DropdownMenuItem(value: 'ALL', child: Text(l10n.translate('all_status'))),
                DropdownMenuItem(value: 'active', child: Text(l10n.translate('active'))),
                DropdownMenuItem(value: 'paused', child: Text(l10n.translate('paused'))),
                DropdownMenuItem(value: 'ended', child: Text(l10n.translate('ended'))),
              ],
              onChanged: (value) {
                _statusFilter = value!;
                _currentPage = 0;
                _refreshFuture();
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: _buildDateRangeControl(l10n),
          ),
        ],
      ),
    );
  }

  Widget _buildDateRangeControl(AppLocalizations l10n) {
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

  Widget _buildSessionsTable(List<SessionWithCashier> rows, int totalCount, AppLocalizations l10n) {
    final currencyFormatter = ref.read(currencyFormatterProvider);
    final totalPages = (totalCount / _rowsPerPage).ceil().clamp(1, 99999);

    return Column(
      children: [
        Expanded(
          child: DataTable2(
            key: ValueKey('${_statusFilter}_${_sortColumnIndex}_$_sortAscending'),
            columnSpacing: 12,
            horizontalMargin: 12,
            minWidth: 1000,
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            headingRowColor: WidgetStateProperty.all(
              Theme.of(context).colorScheme.surfaceContainerHighest,
            ),
            headingTextStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            columns: [
              DataColumn2(
                label: Text(l10n.translate('code')),
                size: ColumnSize.M,
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn2(
                label: Text(l10n.translate('cashier')),
                size: ColumnSize.M,
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn2(
                label: Text(l10n.translate('started_at')),
                size: ColumnSize.M,
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn2(
                label: Text(l10n.translate('status')),
                size: ColumnSize.S,
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn2(
                label: Text(l10n.translate('start_balance')),
                size: ColumnSize.S,
                numeric: true,
                onSort: (i, asc) => _onSort(i, asc),
              ),
              DataColumn2(
                label: Text(l10n.translate('total_sales')),
                size: ColumnSize.S,
                numeric: true,
              ),
              DataColumn2(
                label: Text(l10n.translate('duration')),
                size: ColumnSize.S,
              ),
              DataColumn2(
                label: Text(l10n.translate('actions')),
                size: ColumnSize.M,
              ),
            ],
            rows: rows.map((row) => _buildDataRow(row, currencyFormatter, l10n)).toList(),
          ),
        ),
        _buildPaginationControls(totalCount, totalPages),
      ],
    );
  }

  DataRow _buildDataRow(SessionWithCashier row, dynamic currencyFormatter, AppLocalizations l10n) {
    final session = row.session;
    final isEnded = session.status == 'ended';

    Icon cloudIcon;
    String cloudTooltip;
    if (session.isSynced) {
      cloudIcon = const Icon(Icons.cloud_done, size: 14, color: Colors.green);
      cloudTooltip = l10n.translate('synced_to_server');
    } else if (isEnded) {
      cloudIcon = const Icon(Icons.cloud_off, size: 14, color: Colors.orange);
      cloudTooltip = l10n.translate('not_synced_to_server');
    } else {
      cloudIcon = Icon(Icons.cloud_queue, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant);
      cloudTooltip = 'Pending — will sync when session ends';
    }

    return DataRow(
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text('#${session.code}', overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 4),
              Tooltip(message: cloudTooltip, child: cloudIcon),
            ],
          ),
        ),
        DataCell(Text(row.cashierName, overflow: TextOverflow.ellipsis)),
        DataCell(Text(_formatDateTime(session.startedAt), overflow: TextOverflow.ellipsis)),
        DataCell(_buildStatusChip(session.status)),
        DataCell(Text(currencyFormatter.format(session.moneyAtStart), overflow: TextOverflow.ellipsis)),
        DataCell(Text(currencyFormatter.format(row.summary?.totalAmount ?? 0), overflow: TextOverflow.ellipsis)),
        DataCell(Text(_formatDuration(session.startedAt, session.endedAt), overflow: TextOverflow.ellipsis)),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.visibility, size: 20),
                color: Colors.blue,
                tooltip: l10n.translate('view_details'),
                onPressed: () => _showSessionDetails(row),
              ),
              if (session.status != 'ended')
                PermissionIconButton(
                  permission: Permissions.sessionsEnd,
                  icon: const Icon(Icons.stop, size: 20),
                  color: Colors.red,
                  tooltip: l10n.translate('end_session_action'),
                  onPressed: () => _endSession(session),
                ),
              // A closed session belongs to its Z's totals; only an open
              // one may be deleted (the server refuses the rest).
              if (session.status != 'ended')
              PermissionIconButton(
                permission: Permissions.sessionsDelete,
                icon: const Icon(Icons.delete, size: 20),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                tooltip: l10n.translate('delete'),
                onPressed: () => _deleteSession(session),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String status) {
    final Color color;
    switch (status.toLowerCase()) {
      case 'active':
        color = Colors.green;
        break;
      case 'paused':
        color = Colors.orange;
        break;
      default:
        color = Theme.of(context).colorScheme.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
        overflow: TextOverflow.ellipsis,
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
            'Showing ${_currentPage * _rowsPerPage + 1}–${((_currentPage + 1) * _rowsPerPage).clamp(0, totalItems)} of $totalItems sessions',
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
                onPressed: _currentPage < totalPages - 1
                    ? () { _currentPage = totalPages - 1; _refreshFuture(); }
                    : null,
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
          Icon(Icons.access_time, size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            l10n.translate('no_sessions_found'),
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
            'Error loading sessions',
            style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
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

  // ── Action methods ────────────────────────────────────────────────────────

  Future<void> _deleteSession(CashSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('delete')),
        content: Text(
          '${l10n.translate('are_you_sure')} ${l10n.translate('session')} #${session.code}?\n'
          '${l10n.translate('delete_confirm')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.translate('delete')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final database = ref.read(databaseProvider);
        final sessionService = SessionService(database);
        await sessionService.deleteSession(session.id);
        _refreshFuture();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.translate('success'))),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.translate('error')}: $e')),
          );
        }
      }
    }
  }

  Future<void> _endSession(CashSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = ref.read(currentUserProvider);
    final isCurrentUserSession = currentUser != null &&
        session.cashierId == currentUser.id &&
        (session.status == 'active' || session.status == 'paused');

    final result = await showCloseSessionDialog(
      context: context,
      ref: ref,
      sessionId: session.id,
    );

    if (result.closed) {
      try {
        await ref.read(activityLogServiceProvider).logSessionEnd(
              userId: currentUser?.id,
              username: currentUser?.effectiveDisplayName,
            );

        if (isCurrentUserSession) {
          ref.read(currentUserProvider.notifier).state = null;
          ref.read(currentSessionProvider.notifier).state = null;

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.translate('session_ended_logout')),
                backgroundColor: Colors.green,
              ),
            );

            // Sync all pending data to server before leaving.
            try {
              final syncService = ref.read(dataSyncServiceProvider);
              await Future.wait([
                syncService.syncPendingOperations(),
                syncService.syncSessionsBulk(),
                syncService.syncOrdersBulk(),
                syncService.syncTicketsBulk(),
              ]).timeout(const Duration(seconds: 15));
            } catch (_) {}

            FocusManager.instance.primaryFocus?.unfocus();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            });
          }
        } else {
          _refreshFuture();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.translate('session_ended_success'))),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${l10n.translate('failed_to_end_session')}: $e')),
          );
        }
      }
    }
  }

  void _showSessionDetails(SessionWithCashier row) {
    final session = row.session;
    final l10n = AppLocalizations.of(context)!;
    final summary = row.summary;
    final currencyFormatter = ref.read(currencyFormatterProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('session_details_title').replaceAll('#{0}', session.code)),
        content: SizedBox(
          width: 400,
          child: ListView(
            key: ValueKey('session_dialog_${session.id}'),
            shrinkWrap: true,
            children: [
              _buildDetailRow(l10n.translate('cashier'), row.cashierName),
              _buildDetailRow(l10n.translate('status'), session.status.toUpperCase(), _getStatusColor(session.status)),
              _buildDetailRow(l10n.translate('started_at'), _formatDateTime(session.startedAt)),
              if (session.endedAt != null)
                _buildDetailRow(l10n.translate('ended_at'), _formatDateTime(session.endedAt!)),
              if (session.pausedAt != null)
                _buildDetailRow(l10n.translate('paused_at'), _formatDateTime(session.pausedAt!)),
              const Divider(height: 24),
              _buildDetailRow(l10n.translate('starting_balance'), currencyFormatter.format(session.moneyAtStart)),
              if (session.moneyAtEnd != null)
                _buildDetailRow(l10n.translate('ending_balance'), currencyFormatter.format(session.moneyAtEnd!)),
              const Divider(height: 24),
              if (summary != null) ...[
                Text(
                  l10n.translate('ticket_summary'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                _buildDetailRow(l10n.translate('total_tickets'), '${summary.ticketCount}'),
                _buildDetailRow(l10n.translate('cash_total'), currencyFormatter.format(summary.totalCash)),
                _buildDetailRow(l10n.translate('card_total'), currencyFormatter.format(summary.totalCard)),
                _buildDetailRow(l10n.translate('mobile_total'), currencyFormatter.format(summary.totalMobile)),
                if (summary.totalOther > 0)
                  _buildDetailRow(l10n.translate('other_total'), currencyFormatter.format(summary.totalOther)),
                const Divider(height: 16),
                _buildDetailRow(
                  l10n.translate('total_paid'),
                  currencyFormatter.format(summary.totalPaid),
                  Colors.blue,
                ),
                _buildDetailRow(
                  l10n.translate('expected_cash'),
                  currencyFormatter.format(summary.expectedCashAtEnd),
                  Colors.green,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => showPrintXReportDialog(
              context: context,
              ref: ref,
              session: session,
            ),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(l10n.translate('print_x_report')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.translate('close')),
          ),
          if (session.status == 'active' || session.status == 'paused')
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _endSession(session);
              },
              child: Text(l10n.translate('end_session_action')),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, [Color? valueColor]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: valueColor),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'paused':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(DateTime start, DateTime? end) {
    final duration = (end ?? DateTime.now()).difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  Future<void> _syncAllSessions() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isSyncing = true);

    try {
      final database = ref.read(databaseProvider);
      final apiService = ref.read(apiServiceProvider);
      final syncService = DataSyncService(database, apiService);

      await syncService.syncPendingOperations();
      final syncedCount = await syncService.syncSessionsBulk();

      await _loadPendingOperationsCount();

      if (mounted) {
        _refreshFuture();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('synced_sessions').replaceAll('{0}', '$syncedCount')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.translate('sync_failed')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _showPendingOperationsDialog() async {
    final l10n = AppLocalizations.of(context)!;
    final database = ref.read(databaseProvider);
    final pendingOpsService = PendingOperationsService(database);
    final operations = await pendingOpsService.getPendingOperationsByType('SESSION');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('pending_session_operations')),
        content: SizedBox(
          width: 400,
          height: 300,
          child: operations.isEmpty
              ? Center(child: Text(l10n.translate('no_pending_operations')))
              : ListView.builder(
                  itemCount: operations.length,
                  itemBuilder: (context, index) {
                    final op = operations[index];
                    return ListTile(
                      leading: Icon(
                        op.operationType == 'DELETE' ? Icons.delete : Icons.edit,
                        color: op.operationType == 'DELETE' ? Colors.red : Colors.blue,
                      ),
                      title: Text('${op.operationType} ${l10n.translate('session')} #${op.entityId}'),
                      subtitle: Text(
                        '${l10n.translate('created')}: ${_formatDateTime(op.createdAt)}\n'
                        '${l10n.translate('retries')}: ${op.retryCount}'
                        '${op.lastError != null ? '\n${l10n.translate('error')}: ${op.lastError}' : ''}',
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_forever, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () async {
                          await pendingOpsService.markCompleted(op.id);
                          if (context.mounted) Navigator.of(context).pop();
                          _loadPendingOperationsCount();
                        },
                        tooltip: l10n.translate('remove_from_queue'),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.translate('close')),
          ),
          if (operations.isNotEmpty)
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _syncAllSessions();
              },
              child: Text(l10n.translate('sync_now')),
            ),
        ],
      ),
    );
  }
}

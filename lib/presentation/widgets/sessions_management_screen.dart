import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/network_provider.dart';
import '../../services/session_service.dart';
import '../../services/permission_service.dart';
import '../../services/data_sync_service.dart';
import '../../services/api_service.dart';
import '../../services/pending_operations_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import 'permission_guard.dart';

class SessionsManagementScreen extends ConsumerStatefulWidget {
  const SessionsManagementScreen({super.key});

  @override
  ConsumerState<SessionsManagementScreen> createState() => _SessionsManagementScreenState();
}

class _SessionsManagementScreenState extends ConsumerState<SessionsManagementScreen> {
  List<CashSession> _sessions = [];
  Map<int, SessionSummary> _summaries = {};
  bool _isLoading = true;
  bool _isSyncing = false;
  int _pendingOperationsCount = 0;
  String _statusFilter = 'ALL';
  String _searchQuery = '';
  int _sortColumnIndex = 0;
  bool _sortAscending = false;
  int _currentPage = 0;
  final int _rowsPerPage = 10;

  @override
  void initState() {
    super.initState();
    _loadSessions();
    _loadPendingOperationsCount();
  }

  Future<void> _loadPendingOperationsCount() async {
    try {
      final database = ref.read(databaseProvider);
      final pendingOpsService = PendingOperationsService(database);
      final operations = await pendingOpsService.getPendingOperationsByType('SESSION');
      setState(() {
        _pendingOperationsCount = operations.length;
      });
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);

    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      final sessions = await sessionService.getAllSessions();

      // Load summaries for all sessions
      final summaries = <int, SessionSummary>{};
      for (final session in sessions) {
        try {
          summaries[session.id] = await sessionService.getSessionSummary(session.id);
        } catch (e) {
          // Skip if summary fails
        }
      }

      setState(() {
        _sessions = sessions;
        _summaries = summaries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.translate('failed_to_load_sessions')}: $e')),
        );
      }
    }
  }

  Future<void> _deleteSession(CashSession session) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('delete')),
        content: Text('${l10n.translate('are_you_sure')} ${l10n.translate('session')} #${session.code}?\n${l10n.translate('delete_confirm')}'),
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
        await _loadSessions();
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

  Future<void> _pauseSession(CashSession session) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.pauseSession(session.id);
      await _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('session_paused')),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.translate('failed_to_pause_session')}: $e')),
        );
      }
    }
  }

  Future<void> _resumeSession(CashSession session) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.resumeSession(session.id);
      await _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.translate('session_resumed_success')),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.translate('failed_to_resume_session')}: $e')),
        );
      }
    }
  }

  Future<void> _endSession(CashSession session) async {
    final l10n = AppLocalizations.of(context)!;
    // Check if this is the current user's active session
    final currentUser = ref.read(currentUserProvider);
    final isCurrentUserSession = currentUser != null && session.cashierId == currentUser.id &&
                                  (session.status == 'active' || session.status == 'paused');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('end_session_action')),
        content: Text(
          isCurrentUserSession
              ? '${l10n.translate('end_session_question').replaceAll('#{0}', session.code)}\n${l10n.translate('ending_balance_calculated')}\n\n${l10n.translate('will_logout_warning')}'
              : '${l10n.translate('end_session_question').replaceAll('#{0}', session.code)}\n${l10n.translate('ending_balance_calculated')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.translate('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.translate('end_session_action')),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final database = ref.read(databaseProvider);
        final sessionService = SessionService(database);
        await sessionService.endSession(sessionId: session.id);

        if (isCurrentUserSession) {
          // Clear current user and session
          ref.read(currentUserProvider.notifier).state = null;
          ref.read(currentSessionProvider.notifier).state = null;

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.translate('session_ended_logout')),
                backgroundColor: Colors.green,
              ),
            );

            FocusManager.instance.primaryFocus?.unfocus();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/login', (route) => false);
              }
            });
          }
        } else {
          await _loadSessions();
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

  void _showSessionDetails(CashSession session) {
    final l10n = AppLocalizations.of(context)!;
    final summary = _summaries[session.id];
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
                Text(l10n.translate('ticket_summary'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                _buildDetailRow(l10n.translate('total_tickets'), '${summary.ticketCount}'),
                _buildDetailRow(l10n.translate('cash_total'), currencyFormatter.format(summary.totalCash)),
                _buildDetailRow(l10n.translate('card_total'), currencyFormatter.format(summary.totalCard)),
                _buildDetailRow(l10n.translate('check_total'), currencyFormatter.format(summary.totalCheck)),
                _buildDetailRow(l10n.translate('other_total'), currencyFormatter.format(summary.totalOther)),
                const Divider(height: 16),
                _buildDetailRow(l10n.translate('total_amount'), currencyFormatter.format(summary.totalAmount), Colors.blue),
                _buildDetailRow(l10n.translate('expected_cash'), currencyFormatter.format(summary.expectedCashAtEnd), Colors.green),
              ],
            ],
          ),
        ),
        actions: [
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
          Text(label, style: TextStyle(color: Colors.grey[600])),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
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
      case 'ended':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(DateTime start, DateTime? end) {
    final duration = (end ?? DateTime.now()).difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }

  List<CashSession> _filterSessions() {
    var filtered = _sessions;

    if (_statusFilter != 'ALL') {
      filtered = filtered.where((s) => s.status.toLowerCase() == _statusFilter.toLowerCase()).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((s) =>
        s.id.toString().contains(_searchQuery) ||
        s.cashierId.toString().contains(_searchQuery)
      ).toList();
    }

    return filtered;
  }

  List<CashSession> _sortSessions(List<CashSession> sessions) {
    sessions.sort((a, b) {
      int comparison;
      switch (_sortColumnIndex) {
        case 0:
          comparison = a.id.compareTo(b.id);
          break;
        case 1:
          comparison = a.cashierId.compareTo(b.cashierId);
          break;
        case 2:
          comparison = a.startedAt.compareTo(b.startedAt);
          break;
        case 3:
          comparison = a.status.compareTo(b.status);
          break;
        case 4:
          comparison = a.moneyAtStart.compareTo(b.moneyAtStart);
          break;
        case 5:
          final aTotal = _summaries[a.id]?.totalAmount ?? 0;
          final bTotal = _summaries[b.id]?.totalAmount ?? 0;
          comparison = aTotal.compareTo(bTotal);
          break;
        default:
          comparison = 0;
      }
      return _sortAscending ? comparison : -comparison;
    });
    return sessions;
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(lastKnownOnlineStatusProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('sessions_management')),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
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
                  tooltip: hasPermission ? l10n.translate('pending_operations') : l10n.translate('insufficient_permissions'),
                  color: Colors.white,
                );
              },
            ),
          // Sync all button
          Builder(
            builder: (context) {
              final permissionService = ref.watch(permissionServiceProvider);
              final hasPermission = permissionService.hasPermission(Permissions.syncSessions);
              return IconButton(
                icon: _isSyncing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(
                        isOnline ? Icons.cloud_sync : Icons.cloud_off,
                        color: isOnline ? Colors.white : Colors.grey,
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
            onPressed: _loadSessions,
            tooltip: l10n.translate('refresh'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildFilters(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildSessionsTable()),
                ],
              ),
            ),
    );
  }

  Future<void> _syncAllSessions() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isSyncing = true);

    try {
      final database = ref.read(databaseProvider);
      final apiService = ref.read(apiServiceProvider);
      final syncService = DataSyncService(database, apiService);

      // Sync pending operations first
      await syncService.syncPendingOperations();

      // Sync unsynced sessions
      final syncedCount = await syncService.syncSessionsBulk();

      await _loadSessions();
      await _loadPendingOperationsCount();

      if (mounted) {
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
      if (mounted) {
        setState(() => _isSyncing = false);
      }
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
                        '${l10n.translate('retries')}: ${op.retryCount}${op.lastError != null ? '\n${l10n.translate('error')}: ${op.lastError}' : ''}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.grey),
                        onPressed: () async {
                          await pendingOpsService.markCompleted(op.id);
                          Navigator.of(context).pop();
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

  Widget _buildFilters() {
    final l10n = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: TextField(
            key: const ValueKey('sessions_filter_search'),
            decoration: InputDecoration(
              hintText: l10n.translate('search_by_id'),
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
          flex: 1,
          child: DropdownButtonFormField<String>(
            key: const ValueKey('sessions_filter_status'),
            initialValue: _statusFilter,
            decoration: InputDecoration(
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
              setState(() {
                _statusFilter = value!;
                _currentPage = 0;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSessionsTable() {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormatter = ref.read(currencyFormatterProvider);
    final filteredSessions = _filterSessions();
    final sortedSessions = _sortSessions(filteredSessions);
    final totalPages = (sortedSessions.length / _rowsPerPage).ceil();
    final paginatedSessions = sortedSessions
        .skip(_currentPage * _rowsPerPage)
        .take(_rowsPerPage)
        .toList();

    if (sortedSessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.access_time, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(l10n.translate('no_sessions_found'), style: TextStyle(fontSize: 18, color: Colors.grey[600])),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: DataTable2(
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
                label: Text(l10n.translate('code'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              ),
              DataColumn2(
                label: Text(l10n.translate('cashier'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              ),
              DataColumn2(
                label: Text(l10n.translate('started_at'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              ),
              DataColumn2(
                label: Text(l10n.translate('status'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              ),
              DataColumn2(
                label: Text(l10n.translate('start_balance'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                numeric: true,
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              ),
              DataColumn2(
                label: Text(l10n.translate('total_sales'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                numeric: true,
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              ),
              DataColumn2(
                label: Text(l10n.translate('duration'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
              ),
              DataColumn2(
                label: Text(l10n.translate('actions'), style: const TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
              ),
            ],
            rows: paginatedSessions.map((session) {
              final summary = _summaries[session.id];
              final isEnded = session.status == 'ended';
              final needsSync = isEnded && !session.isSynced;

              return DataRow2(
                key: ValueKey('row_${session.id}'),
                cells: [
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            '#${session.code}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        if (isEnded)
                          Tooltip(
                            message: needsSync ? l10n.translate('not_synced_to_server') : l10n.translate('synced_to_server'),
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
                    Text(
                      '#${session.cashierId}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatDateTime(session.startedAt),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(session.status).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        session.status.toUpperCase(),
                        style: TextStyle(
                          color: _getStatusColor(session.status),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(
                    Text(
                      currencyFormatter.format(session.moneyAtStart),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(
                    Text(
                      currencyFormatter.format(summary?.totalAmount ?? 0),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(
                    Text(
                      _formatDuration(session.startedAt, session.endedAt),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility, size: 20),
                          color: Colors.blue,
                          tooltip: l10n.translate('view_details'),
                          onPressed: () => _showSessionDetails(session),
                        ),
                        if (session.status != 'ended')
                          PermissionIconButton(
                            permission: Permissions.sessionsEnd,
                            icon: const Icon(Icons.stop, size: 20),
                            color: Colors.red,
                            tooltip: l10n.translate('end_session_action'),
                            onPressed: () => _endSession(session),
                          ),
                        // Delete - Protected by permission
                        PermissionIconButton(
                          permission: Permissions.sessionsDelete,
                          icon: const Icon(Icons.delete, size: 20),
                          color: Colors.grey,
                          tooltip: l10n.translate('delete'),
                          onPressed: () => _deleteSession(session),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        _buildPagination(totalPages),
      ],
    );
  }

  Widget _buildPagination(int totalPages) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.first_page),
          onPressed: _currentPage > 0 ? () => setState(() => _currentPage = 0) : null,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: _currentPage > 0 ? () => setState(() => _currentPage--) : null,
        ),
        Text('Page ${_currentPage + 1} of ${totalPages == 0 ? 1 : totalPages}'),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
        ),
        IconButton(
          icon: const Icon(Icons.last_page),
          onPressed: _currentPage < totalPages - 1 ? () => setState(() => _currentPage = totalPages - 1) : null,
        ),
      ],
    );
  }
}


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:data_table_2/data_table_2.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../services/session_service.dart';
import '../../services/permission_service.dart';
import '../../utils/app_localizations.dart';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load sessions: $e')),
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
        content: Text('${l10n.translate('are_you_sure')} ${l10n.translate('session')} #${session.id}?\n${l10n.translate('delete_confirm')}'),
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
    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.pauseSession(session.id);
      await _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session paused'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pause session: $e')),
        );
      }
    }
  }

  Future<void> _resumeSession(CashSession session) async {
    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.resumeSession(session.id);
      await _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session resumed'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resume session: $e')),
        );
      }
    }
  }

  Future<void> _endSession(CashSession session) async {
    // Check if this is the current user's active session
    final currentUser = ref.read(currentUserProvider);
    final isCurrentUserSession = currentUser != null && session.cashierId == currentUser.id &&
                                  (session.status == 'active' || session.status == 'paused');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session'),
        content: Text(
          isCurrentUserSession
              ? 'Are you sure you want to end session #${session.id}?\nThe ending balance will be calculated from tickets.\n\n⚠️ You will be logged out automatically.'
              : 'Are you sure you want to end session #${session.id}?\nThe ending balance will be calculated from tickets.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End Session'),
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
              const SnackBar(
                content: Text('Session ended. Logging out...'),
                backgroundColor: Colors.green,
              ),
            );

            // Navigate to login screen
            Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
          }
        } else {
          await _loadSessions();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Session ended')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to end session: $e')),
          );
        }
      }
    }
  }

  void _showSessionDetails(CashSession session) {
    final summary = _summaries[session.id];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Session #${session.id} Details'),
        content: SizedBox(
          width: 400,
          child: ListView(
            key: ValueKey('session_dialog_${session.id}'),
            shrinkWrap: true,
            children: [
              _buildDetailRow('Status', session.status.toUpperCase(), _getStatusColor(session.status)),
              _buildDetailRow('Started At', _formatDateTime(session.startedAt)),
              if (session.endedAt != null)
                _buildDetailRow('Ended At', _formatDateTime(session.endedAt!)),
              if (session.pausedAt != null)
                _buildDetailRow('Paused At', _formatDateTime(session.pausedAt!)),
              const Divider(height: 24),
              _buildDetailRow('Starting Balance', '\$${session.moneyAtStart.toStringAsFixed(2)}'),
              if (session.moneyAtEnd != null)
                _buildDetailRow('Ending Balance', '\$${session.moneyAtEnd!.toStringAsFixed(2)}'),
              const Divider(height: 24),
              if (summary != null) ...[
                const Text('Ticket Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                _buildDetailRow('Total Tickets', '${summary.ticketCount}'),
                _buildDetailRow('Cash Total', '\$${summary.totalCash.toStringAsFixed(2)}'),
                _buildDetailRow('Card Total', '\$${summary.totalCard.toStringAsFixed(2)}'),
                _buildDetailRow('Check Total', '\$${summary.totalCheck.toStringAsFixed(2)}'),
                _buildDetailRow('Other Total', '\$${summary.totalOther.toStringAsFixed(2)}'),
                const Divider(height: 16),
                _buildDetailRow('Total Amount', '\$${summary.totalAmount.toStringAsFixed(2)}', Colors.blue),
                _buildDetailRow('Expected Cash', '\$${summary.expectedCashAtEnd.toStringAsFixed(2)}', Colors.green),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          if (session.status == 'active' || session.status == 'paused')
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _endSession(session);
              },
              child: const Text('End Session'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions Management'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSessions,
            tooltip: 'Refresh',
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

// dart
// dart
  Widget _buildFilters() {
    return Row(
      children: [
        Expanded(
          flex: 1,
          child: TextField(
            key: const ValueKey('sessions_filter_search'),
            decoration: InputDecoration(
              hintText: 'Search by ID...',
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
            value: _statusFilter,
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: const [
              DropdownMenuItem(value: 'ALL', child: Text('All Status')),
              DropdownMenuItem(value: 'active', child: Text('Active')),
              DropdownMenuItem(value: 'paused', child: Text('Paused')),
              DropdownMenuItem(value: 'ended', child: Text('Ended')),
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
            Text('No sessions found', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
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
            headingRowColor: WidgetStateProperty.all(Colors.grey[100]),
            columns: [
              DataColumn2(
                label: const Text('ID', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              ),
              DataColumn2(
                label: const Text('Cashier', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              ),
              DataColumn2(
                label: const Text('Started At', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              ),
              DataColumn2(
                label: const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
                onSort: (columnIndex, ascending) {
                  setState(() {
                    _sortColumnIndex = columnIndex;
                    _sortAscending = ascending;
                  });
                },
              ),
              DataColumn2(
                label: const Text('Start Balance', style: TextStyle(fontWeight: FontWeight.bold)),
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
                label: const Text('Total Sales', style: TextStyle(fontWeight: FontWeight.bold)),
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
                label: const Text('Duration', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.S,
              ),
              const DataColumn2(
                label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold)),
                size: ColumnSize.M,
              ),
            ],
            rows: paginatedSessions.map((session) {
              final summary = _summaries[session.id];
              return DataRow2(
                key: ValueKey('row_${session.id}'),
                cells: [
                  DataCell(Text('#${session.id}')),
                  DataCell(Text('#${session.cashierId}')),
                  DataCell(Text(_formatDateTime(session.startedAt))),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(session.status).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        session.status.toUpperCase(),
                        style: TextStyle(
                          color: _getStatusColor(session.status),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text('\$${session.moneyAtStart.toStringAsFixed(2)}')),
                  DataCell(Text('\$${(summary?.totalAmount ?? 0).toStringAsFixed(2)}')),
                  DataCell(Text(_formatDuration(session.startedAt, session.endedAt))),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.visibility, size: 20),
                          color: Colors.blue,
                          tooltip: 'View Details',
                          onPressed: () => _showSessionDetails(session),
                        ),
                        if (session.status != 'ended')
                          PermissionIconButton(
                            permission: Permissions.sessionsEnd,
                            icon: const Icon(Icons.stop, size: 20),
                            color: Colors.red,
                            tooltip: 'End Session',
                            onPressed: () => _endSession(session),
                          ),
                        // Delete - Protected by permission
                        PermissionIconButton(
                          permission: Permissions.sessionsDelete,
                          icon: const Icon(Icons.delete, size: 20),
                          color: Colors.grey,
                          tooltip: 'Delete',
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


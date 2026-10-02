import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../services/session_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import '../../utils/snackbar_helper.dart';

class SessionDetailsScreen extends ConsumerStatefulWidget {
  const SessionDetailsScreen({super.key});

  @override
  ConsumerState<SessionDetailsScreen> createState() => _SessionDetailsScreenState();
}

class _SessionDetailsScreenState extends ConsumerState<SessionDetailsScreen> {
  CashSession? _currentSession;
  SessionSummary? _sessionSummary;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentSession();
  }

  Future<void> _loadCurrentSession() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      final currentUser = ref.read(currentUserProvider);

      if (currentUser != null) {
        final session = await sessionService.getActiveSession(currentUser.id);
        if (session != null) {
          final summary = await sessionService.getSessionSummary(session.id);
          setState(() {
            _currentSession = session;
            _sessionSummary = summary;
            _isLoading = false;
          });
        } else {
          setState(() {
            _currentSession = null;
            _sessionSummary = null;
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'No user logged in';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = errorText(e, AppLocalizations.of(context)!);
        _isLoading = false;
      });
    }
  }

  Future<void> _pauseSession() async {
    if (_currentSession == null) return;

    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.pauseSession(_currentSession!.id);
      await _loadCurrentSession();
      if (mounted) {
        SnackBarHelper.showToast('Session paused', kind: ToastKind.warning);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast(errorText(e, AppLocalizations.of(context)!), kind: ToastKind.error);
      }
    }
  }

  Future<void> _resumeSession() async {
    if (_currentSession == null) return;

    try {
      final database = ref.read(databaseProvider);
      final sessionService = SessionService(database);
      await sessionService.resumeSession(_currentSession!.id);
      await _loadCurrentSession();
      if (mounted) {
        SnackBarHelper.showToast('Session resumed', kind: ToastKind.success);
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.showToast(errorText(e, AppLocalizations.of(context)!), kind: ToastKind.error);
      }
    }
  }

  Future<void> _endSession() async {
    if (_currentSession == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Are you sure you want to end this session?'),
            const SizedBox(height: 16),
            if (_sessionSummary != null) ...[
              Text('Total Sales: \$${_sessionSummary!.totalAmount.toStringAsFixed(2)}'),
              Text('Expected Cash: \$${_sessionSummary!.expectedCashAtEnd.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              const Text(
                'The ending balance will be calculated automatically from your tickets.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),
              const Text(
                '⚠️ You will be logged out automatically.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final database = ref.read(databaseProvider);
        final sessionService = SessionService(database);
        await sessionService.endSession(sessionId: _currentSession!.id);

        // Clear current user and session
        ref.read(currentUserProvider.notifier).state = null;
        ref.read(currentSessionProvider.notifier).state = null;

        if (mounted) {
          SnackBarHelper.showToast('Session ended successfully. Logging out...', kind: ToastKind.success);

          FocusManager.instance.primaryFocus?.unfocus();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.of(context)
                  .pushNamedAndRemoveUntil('/login', (route) => false);
            }
          });
        }
      } catch (e) {
        if (mounted) {
          SnackBarHelper.showToast(errorText(e, AppLocalizations.of(context)!), kind: ToastKind.error);
        }
      }
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

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'paused':
        return Colors.orange;
      case 'ended':
        return Theme.of(context).colorScheme.onSurfaceVariant;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Details'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCurrentSession,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
                      const SizedBox(height: 16),
                      Text(_errorMessage!, style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : _currentSession == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.access_time, size: 64, color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 16),
                          Text('No active session', style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Text('Please login to start a new session', style: TextStyle(fontSize: 14, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      key: ValueKey('session_${_currentSession!.id}'),
                      onRefresh: _loadCurrentSession,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Session Info Card
                            Card(
                              elevation: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Session #${_currentSession!.id}',
                                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(_currentSession!.status),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            _currentSession!.status.toUpperCase(),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(height: 24),
                                    _buildInfoRow('Started', _formatDateTime(_currentSession!.startedAt)),
                                    _buildInfoRow('Duration', _formatDuration(_currentSession!.startedAt, _currentSession!.endedAt)),
                                    if (_currentSession!.endedAt != null)
                                      _buildInfoRow('Ended', _formatDateTime(_currentSession!.endedAt!)),
                                    if (_currentSession!.pausedAt != null)
                                      _buildInfoRow('Paused At', _formatDateTime(_currentSession!.pausedAt!)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Financial Summary Card
                            Card(
                              elevation: 2,
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Financial Summary',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    ),
                                    const Divider(height: 24),
                                    _buildInfoRow('Starting Balance', '\$${_currentSession!.moneyAtStart.toStringAsFixed(2)}'),
                                    if (_currentSession!.endedAt != null && _currentSession!.moneyAtEnd != null)
                                      _buildInfoRow('Ending Balance', '\$${_currentSession!.moneyAtEnd!.toStringAsFixed(2)}'),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Ticket Summary Card
                            if (_sessionSummary != null) ...[
                              Card(
                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Ticket Summary',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                      ),
                                      const Divider(height: 24),
                                      _buildInfoRow('Total Tickets', '${_sessionSummary!.ticketCount}'),
                                      const SizedBox(height: 8),
                                      _buildInfoRow('Cash Sales', '\$${_sessionSummary!.totalCash.toStringAsFixed(2)}'),
                                      _buildInfoRow('Card Sales', '\$${_sessionSummary!.totalCard.toStringAsFixed(2)}'),
                                      _buildInfoRow('Mobile Sales', '\$${_sessionSummary!.totalMobile.toStringAsFixed(2)}'),
                                      if (_sessionSummary!.totalOther > 0)
                                        _buildInfoRow('Other Sales', '\$${_sessionSummary!.totalOther.toStringAsFixed(2)}'),
                                      if (_sessionSummary!.cancelledAmount > 0)
                                        _buildInfoRow('Cancelled', '\$${_sessionSummary!.cancelledAmount.toStringAsFixed(2)}'),
                                      const Divider(height: 24),
                                      _buildInfoRow(
                                        'Total Paid',
                                        '\$${_sessionSummary!.totalPaid.toStringAsFixed(2)}',
                                        valueColor: Colors.blue,
                                        bold: true,
                                      ),
                                      _buildInfoRow(
                                        'Expected Cash',
                                        '\$${_sessionSummary!.expectedCashAtEnd.toStringAsFixed(2)}',
                                        valueColor: Colors.green,
                                        bold: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            // Action Button
                            if (_currentSession!.endedAt == null)
                              ElevatedButton.icon(
                                onPressed: _currentSession!.status.toLowerCase() == 'active' ? _pauseSession : _resumeSession,
                                icon: Icon(_currentSession!.status.toLowerCase() == 'active' ? Icons.pause : Icons.play_arrow),
                                label: Text(_currentSession!.status.toLowerCase() == 'active' ? 'Pause Session' : 'Resume Session'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.red, width: 2),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                ),
                              ),
                            ],
                        ),
                      ),
                    ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}


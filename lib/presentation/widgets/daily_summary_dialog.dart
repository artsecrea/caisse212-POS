import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/daily_summary_service.dart';
import '../../services/printing_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';

class DailySummaryDialog extends ConsumerStatefulWidget {
  const DailySummaryDialog({Key? key}) : super(key: key);

  @override
  ConsumerState<DailySummaryDialog> createState() => _DailySummaryDialogState();
}

class _DailySummaryDialogState extends ConsumerState<DailySummaryDialog> {
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  List<CashSession> _availableSessions = [];
  Set<int> _selectedSessionIds = {};
  bool _isLoading = true;
  bool _isGenerating = false;
  DailySummaryReport? _report;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);

    try {
      final database = ref.read(databaseProvider);
      final service = DailySummaryService(database);
      final sessions = await service.getSessionsInRange(_startDate, _endDate);

      setState(() {
        _availableSessions = sessions;
        // Select all sessions by default
        _selectedSessionIds = sessions.map((s) => s.id).toSet();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sessions: $e')),
        );
      }
    }
  }

  Future<void> _generateReport() async {
    if (_selectedSessionIds.isEmpty) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n?.translate('select_at_least_one_session') ?? 'Please select at least one session')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final database = ref.read(databaseProvider);
      final service = DailySummaryService(database);
      final report = await service.generateReport(
        startDate: _startDate,
        endDate: _endDate,
        sessionIds: _selectedSessionIds.toList(),
      );

      setState(() {
        _report = report;
        _isGenerating = false;
      });
    } catch (e) {
      setState(() => _isGenerating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating report: $e')),
        );
      }
    }
  }

  Future<void> _selectDateRange() async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      helpText: l10n?.translate('select_date_range') ?? 'Select Date Range',
      cancelText: l10n?.translate('cancel') ?? 'Cancel',
      confirmText: l10n?.translate('confirm') ?? 'Confirm',
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _report = null;
      });
      await _loadSessions();
    }
  }

  Future<void> _printReport() async {
    if (_report == null) return;

    final l10n = AppLocalizations.of(context);
    final currencyFormatter = ref.read(currencyFormatterProvider);
    final printingService = ref.read(printingServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final businessName = prefs.getString('business_name') ?? 'POS System';

    try {
      await printingService.printDailySummaryReport(
        report: _report!,
        l10n: l10n,
        currencyFormatter: currencyFormatter,
        businessName: businessName,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n?.translate('report_printed_successfully') ?? 'Report printed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n?.translate('print_error') ?? 'Print error'}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDateTime(DateTime date) {
    return '${_formatDate(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currencyFormatter = ref.read(currencyFormatterProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.9,
        constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 800),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.summarize, color: Colors.white, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n?.translate('daily_summary') ?? 'Daily Summary',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Date range selector
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _selectDateRange,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.primaryColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: theme.primaryColor),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n?.translate('date_range') ?? 'Date Range',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    _startDate == _endDate
                                        ? _formatDate(_startDate)
                                        : '${_formatDate(_startDate)} - ${_formatDate(_endDate)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_drop_down, color: theme.primaryColor),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Quick date buttons
                  _buildQuickDateButton(
                    l10n?.translate('today') ?? 'Today',
                    () {
                      setState(() {
                        _startDate = DateTime.now();
                        _endDate = DateTime.now();
                        _report = null;
                      });
                      _loadSessions();
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildQuickDateButton(
                    l10n?.translate('yesterday') ?? 'Yesterday',
                    () {
                      final yesterday = DateTime.now().subtract(const Duration(days: 1));
                      setState(() {
                        _startDate = yesterday;
                        _endDate = yesterday;
                        _report = null;
                      });
                      _loadSessions();
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildQuickDateButton(
                    l10n?.translate('this_week') ?? 'This Week',
                    () {
                      final now = DateTime.now();
                      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
                      setState(() {
                        _startDate = startOfWeek;
                        _endDate = now;
                        _report = null;
                      });
                      _loadSessions();
                    },
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _report == null
                      ? _buildSessionSelector(l10n, currencyFormatter)
                      : _buildReportPreview(l10n, currencyFormatter),
            ),

            // Footer with action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[100],
                border: Border(
                  top: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_report != null)
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _report = null);
                      },
                      icon: const Icon(Icons.arrow_back),
                      label: Text(l10n?.translate('back') ?? 'Back'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      ),
                    ),
                  const SizedBox(width: 12),
                  if (_report == null)
                    ElevatedButton.icon(
                      onPressed: _isGenerating || _selectedSessionIds.isEmpty
                          ? null
                          : _generateReport,
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.preview),
                      label: Text(l10n?.translate('preview') ?? 'Preview'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        minimumSize: const Size(150, 50),
                      ),
                    ),
                  if (_report != null) ...[
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _printReport,
                      icon: const Icon(Icons.print),
                      label: Text(l10n?.translate('print') ?? 'Print'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        minimumSize: const Size(150, 50),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickDateButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label),
    );
  }

  Widget _buildSessionSelector(AppLocalizations? l10n, CurrencyFormatter currencyFormatter) {
    if (_availableSessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              l10n?.translate('no_sessions_in_range') ?? 'No sessions found in this date range',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Select all / Deselect all
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                '${l10n?.translate('sessions') ?? 'Sessions'} (${_availableSessions.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedSessionIds = _availableSessions.map((s) => s.id).toSet();
                  });
                },
                child: Text(l10n?.translate('select_all') ?? 'Select All'),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _selectedSessionIds.clear();
                  });
                },
                child: Text(l10n?.translate('deselect_all') ?? 'Deselect All'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Session list
        Expanded(
          child: ListView.builder(
            itemCount: _availableSessions.length,
            itemBuilder: (context, index) {
              final session = _availableSessions[index];
              final isSelected = _selectedSessionIds.contains(session.id);

              return CheckboxListTile(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedSessionIds.add(session.id);
                    } else {
                      _selectedSessionIds.remove(session.id);
                    }
                  });
                },
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(session.status).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#${session.code}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(session.status),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${l10n?.translate('cashier') ?? 'Cashier'}: #${session.cashierId}',
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(session.status).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        session.status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _getStatusColor(session.status),
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  '${_formatDateTime(session.startedAt)} • ${l10n?.translate('starting_balance') ?? 'Starting'}: ${currencyFormatter.format(session.moneyAtStart)}',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReportPreview(AppLocalizations? l10n, CurrencyFormatter currencyFormatter) {
    final report = _report!;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Report header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  l10n?.translate('daily_summary_report') ?? 'Daily Summary Report',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${l10n?.translate('date_range') ?? 'Date Range'}: ${_formatDate(report.startDate)} - ${_formatDate(report.endDate)}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n?.translate('number_of_sessions') ?? 'Number of Sessions'}: ${report.totalSessions}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Sessions details
          Text(
            l10n?.translate('sessions_details') ?? 'Sessions Details',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          ...report.sessions.map((session) => _buildSessionCard(session, l10n, currencyFormatter)),

          const SizedBox(height: 16),

          // Summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.primaryColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.translate('summary') ?? 'Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                  ),
                ),
                const Divider(height: 24),
                _buildSummaryRow(l10n?.translate('total_orders') ?? 'Total Orders', '${report.totalOrders}'),
                _buildSummaryRow(l10n?.translate('expected_from_orders') ?? 'Expected from Orders', currencyFormatter.format(report.totalExpectedFromOrders)),
                _buildSummaryRow(l10n?.translate('total_tickets') ?? 'Total Tickets', '${report.totalTickets}'),
                _buildSummaryRow(l10n?.translate('expected_from_tickets') ?? 'Expected from Tickets', currencyFormatter.format(report.totalExpectedFromTickets)),
                const Divider(height: 16),
                _buildSummaryRow(l10n?.translate('unpaid_orders') ?? 'Unpaid Orders', '${report.totalUnpaidOrders}', Colors.orange),
                _buildSummaryRow(l10n?.translate('unpaid_amount') ?? 'Unpaid Amount', currencyFormatter.format(report.totalUnpaidAmount), Colors.orange),
                if (report.totalCancelledTickets > 0) ...[
                  const Divider(height: 16),
                  _buildSummaryRow(l10n?.translate('cancelled_tickets') ?? 'Cancelled Tickets', '${report.totalCancelledTickets}', Colors.red),
                  _buildSummaryRow(l10n?.translate('cancelled_amount') ?? 'Cancelled Amount', currencyFormatter.format(report.totalCancelledAmount), Colors.red),
                ],
                const Divider(height: 16),
                _buildSummaryRow(l10n?.translate('paid_by_cash') ?? 'Paid by Cash', currencyFormatter.format(report.totalPaidByCash), Colors.green),
                _buildSummaryRow(l10n?.translate('paid_by_card') ?? 'Paid by Card', currencyFormatter.format(report.totalPaidByCard), Colors.blue),
                _buildSummaryRow(l10n?.translate('paid_by_phone') ?? 'Paid by Phone', currencyFormatter.format(report.totalPaidByPhone), Colors.purple),
                _buildSummaryRow(l10n?.translate('paid_by_other') ?? 'Paid by Other', currencyFormatter.format(report.totalPaidByOther), Colors.grey),
                const Divider(height: 16),
                _buildSummaryRow(
                  l10n?.translate('total_paid') ?? 'Total Paid',
                  currencyFormatter.format(report.totalPaid),
                  theme.primaryColor,
                  true,
                ),
                _buildSummaryRow(l10n?.translate('total_starting_balance') ?? 'Total Starting Balance', currencyFormatter.format(report.totalStartingBalance)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(SessionSummaryReport session, AppLocalizations? l10n, CurrencyFormatter currencyFormatter) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Session header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(session.status).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${l10n?.translate('session') ?? 'Session'} #${session.sessionCode}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(session.status),
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(session.status).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  session.status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _getStatusColor(session.status),
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          // Session details in grid
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _buildDetailItem(l10n?.translate('cashier') ?? 'Cashier', session.cashierName ?? '#${session.cashierId}'),
              _buildDetailItem(l10n?.translate('starting_balance') ?? 'Starting Balance', currencyFormatter.format(session.startingBalance)),
              _buildDetailItem(l10n?.translate('total_orders') ?? 'Total Orders', '${session.totalOrders}'),
              _buildDetailItem(l10n?.translate('expected_from_orders') ?? 'Expected from Orders', currencyFormatter.format(session.expectedFromOrders)),
              _buildDetailItem(l10n?.translate('total_tickets') ?? 'Total Tickets', '${session.totalTickets}'),
              _buildDetailItem(l10n?.translate('expected_from_tickets') ?? 'Expected from Tickets', currencyFormatter.format(session.expectedFromTickets)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _buildDetailItem(l10n?.translate('unpaid_orders') ?? 'Unpaid Orders', '${session.unpaidOrders}', Colors.orange),
              _buildDetailItem(l10n?.translate('unpaid_amount') ?? 'Unpaid Amount', currencyFormatter.format(session.unpaidAmount), Colors.orange),
              if (session.cancelledTickets > 0) ...[
                _buildDetailItem(l10n?.translate('cancelled_tickets') ?? 'Cancelled Tickets', '${session.cancelledTickets}', Colors.red),
                _buildDetailItem(l10n?.translate('cancelled_amount') ?? 'Cancelled Amount', currencyFormatter.format(session.cancelledAmount), Colors.red),
              ],
            ],
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _buildDetailItem(l10n?.translate('paid_by_cash') ?? 'Cash', currencyFormatter.format(session.paidByCash), Colors.green),
              _buildDetailItem(l10n?.translate('paid_by_card') ?? 'Card', currencyFormatter.format(session.paidByCard), Colors.blue),
              _buildDetailItem(l10n?.translate('paid_by_phone') ?? 'Phone', currencyFormatter.format(session.paidByPhone), Colors.purple),
              _buildDetailItem(l10n?.translate('paid_by_other') ?? 'Other', currencyFormatter.format(session.paidByOther), Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, [Color? valueColor]) {
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
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

  Widget _buildSummaryRow(String label, String value, [Color? valueColor, bool isBold = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: valueColor,
              fontSize: isBold ? 16 : 14,
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
}




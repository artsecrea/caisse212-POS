import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../services/daily_summary_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';

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
        final l10n = AppLocalizations.of(context);
        SnackBarHelper.error(
          context,
          '${l10n?.translate('error_loading_sessions') ?? 'Error loading sessions'}: $e',
        );
      }
    }
  }

  Future<void> _generateReport() async {
    if (_selectedSessionIds.isEmpty) {
      final l10n = AppLocalizations.of(context);
      SnackBarHelper.warning(
        context,
        l10n?.translate('select_at_least_one_session') ??
            'Please select at least one session',
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
        final l10n = AppLocalizations.of(context);
        SnackBarHelper.error(
          context,
          '${l10n?.translate('error_generating_report') ?? 'Error generating report'}: $e',
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
        SnackBarHelper.success(
          context,
          l10n?.translate('report_printed_successfully') ??
              'Report printed successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarHelper.error(
          context,
          '${l10n?.translate('print_error') ?? 'Print error'}: $e',
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
    final cs = theme.colorScheme;

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
                color: cs.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.summarize, color: cs.onPrimary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n?.translate('daily_summary') ?? 'Daily Summary',
                      style: TextStyle(
                        color: cs.onPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: cs.onPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Date range selector
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
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
                          border: Border.all(color: cs.primary),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today, color: cs.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n?.translate('date_range') ?? 'Date Range',
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
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
                            Icon(Icons.arrow_drop_down, color: cs.primary),
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
                color: cs.surfaceContainer,
                border: Border(
                  top: BorderSide(color: cs.outlineVariant),
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
                        backgroundColor: cs.tertiary,
                        foregroundColor: cs.onTertiary,
                      ),
                    ),
                    // "Reprint Z" surfaces when the selection narrows to a
                    // single session that has a counted-cash figure. The
                    // printer pipeline already appends the variance block for
                    // that shape, so this button just re-fires the same call
                    // with a clearer label.
                    if (_report!.sessions.length == 1 &&
                        _report!.sessions.first.countedCash != null) ...[
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _printReport,
                        icon: const Icon(Icons.receipt_long),
                        label: Text(l10n?.translate('z_report') ?? 'Z report'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          minimumSize: const Size(150, 50),
                          backgroundColor: cs.primary,
                          foregroundColor: cs.onPrimary,
                        ),
                      ),
                    ],
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
    final cs = Theme.of(context).colorScheme;
    if (_availableSessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_busy,
                size: 64,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              l10n?.translate('no_sessions_in_range') ?? 'No sessions found in this date range',
              style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant),
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
    final cs = theme.colorScheme;
    final ch = _channelColors(context);

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
              color: cs.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
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
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n?.translate('number_of_sessions') ?? 'Number of Sessions'}: ${report.totalSessions}',
                  style: TextStyle(color: cs.onSurfaceVariant),
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
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.primary),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n?.translate('summary') ?? 'Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const Divider(height: 24),
                _buildSummaryRow(l10n?.translate('total_orders') ?? 'Total Orders', '${report.totalOrders}'),
                _buildSummaryRow(l10n?.translate('expected_from_orders') ?? 'Expected from Orders', currencyFormatter.format(report.totalExpectedFromOrders)),
                _buildSummaryRow(l10n?.translate('total_tickets') ?? 'Total Tickets', '${report.totalTickets}'),
                _buildSummaryRow(l10n?.translate('expected_from_tickets') ?? 'Expected from Tickets', currencyFormatter.format(report.totalExpectedFromTickets)),
                const Divider(height: 16),
                _buildSummaryRow(l10n?.translate('unpaid_orders') ?? 'Unpaid Orders', '${report.totalUnpaidOrders}', ch.unpaid),
                _buildSummaryRow(l10n?.translate('unpaid_amount') ?? 'Unpaid Amount', currencyFormatter.format(report.totalUnpaidAmount), ch.unpaid),
                if (report.totalCancelledTickets > 0) ...[
                  const Divider(height: 16),
                  _buildSummaryRow(l10n?.translate('cancelled_tickets') ?? 'Cancelled Tickets', '${report.totalCancelledTickets}', cs.error),
                  _buildSummaryRow(l10n?.translate('cancelled_amount') ?? 'Cancelled Amount', currencyFormatter.format(report.totalCancelledAmount), cs.error),
                ],
                const Divider(height: 16),
                _buildSummaryRow(l10n?.translate('paid_by_cash') ?? 'Paid by Cash', currencyFormatter.format(report.totalPaidByCash), ch.cash),
                _buildSummaryRow(l10n?.translate('paid_by_card') ?? 'Paid by Card', currencyFormatter.format(report.totalPaidByCard), ch.card),
                _buildSummaryRow(l10n?.translate('paid_by_phone') ?? 'Paid by Phone', currencyFormatter.format(report.totalPaidByPhone), ch.phone),
                _buildSummaryRow(l10n?.translate('paid_by_other') ?? 'Paid by Other', currencyFormatter.format(report.totalPaidByOther), ch.other),
                const Divider(height: 16),
                _buildSummaryRow(
                  l10n?.translate('total_paid') ?? 'Total Paid',
                  currencyFormatter.format(report.totalPaid),
                  cs.primary,
                  true,
                ),
                _buildSummaryRow(l10n?.translate('total_starting_balance') ?? 'Total Starting Balance', currencyFormatter.format(report.totalStartingBalance)),
              ],
            ),
          ),
          if (report.totalWaiterBreakdown.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildWaiterBreakdownBlock(
                report.totalWaiterBreakdown, l10n, currencyFormatter),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionCard(SessionSummaryReport session, AppLocalizations? l10n, CurrencyFormatter currencyFormatter) {
    final cs = Theme.of(context).colorScheme;
    final ch = _channelColors(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
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
              _buildDetailItem(l10n?.translate('unpaid_orders') ?? 'Unpaid Orders', '${session.unpaidOrders}', ch.unpaid),
              _buildDetailItem(l10n?.translate('unpaid_amount') ?? 'Unpaid Amount', currencyFormatter.format(session.unpaidAmount), ch.unpaid),
              if (session.cancelledTickets > 0) ...[
                _buildDetailItem(l10n?.translate('cancelled_tickets') ?? 'Cancelled Tickets', '${session.cancelledTickets}', cs.error),
                _buildDetailItem(l10n?.translate('cancelled_amount') ?? 'Cancelled Amount', currencyFormatter.format(session.cancelledAmount), cs.error),
              ],
            ],
          ),
          const Divider(height: 24),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _buildDetailItem(l10n?.translate('paid_by_cash') ?? 'Cash', currencyFormatter.format(session.paidByCash), ch.cash),
              _buildDetailItem(l10n?.translate('paid_by_card') ?? 'Card', currencyFormatter.format(session.paidByCard), ch.card),
              _buildDetailItem(l10n?.translate('paid_by_phone') ?? 'Phone', currencyFormatter.format(session.paidByPhone), ch.phone),
              _buildDetailItem(l10n?.translate('paid_by_other') ?? 'Other', currencyFormatter.format(session.paidByOther), ch.other),
            ],
          ),
          if (session.countedCash != null)
            _buildZReportBlock(session, l10n, currencyFormatter),
          if (session.waiterBreakdown.isNotEmpty)
            _buildWaiterBreakdownBlock(
                session.waiterBreakdown, l10n, currencyFormatter),
        ],
      ),
    );
  }

  /// On-screen twin of the per-section "BY WAITER" block on the printed Z
  /// report. Single waiter row per attribution, with orders count, paid
  /// total, and owed total when non-zero. Same widget is reused for the
  /// report-level aggregate at the bottom of `_buildReportPreview`.
  Widget _buildWaiterBreakdownBlock(
    List<WaiterBreakdown> waiters,
    AppLocalizations? l10n,
    CurrencyFormatter fmt,
  ) {
    final cs = Theme.of(context).colorScheme;
    final ch = _channelColors(context);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.room_service, color: cs.primary, size: 18),
              const SizedBox(width: 6),
              Text(
                l10n?.translate('by_waiter') ?? 'By waiter',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final w in waiters)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      w.waiterName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${w.ordersCount} ${l10n?.translate('orders') ?? 'orders'}',
                      style: TextStyle(color: cs.onSurfaceVariant),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(
                      fmt.format(w.paid),
                      style: TextStyle(
                        color: ch.cash,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: Text(
                      w.owed > 0.005 ? fmt.format(w.owed) : '—',
                      style: TextStyle(
                        color:
                            w.owed > 0.005 ? cs.error : cs.onSurfaceVariant,
                        fontWeight: w.owed > 0.005
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Z-report reconciliation block — shown only for sessions whose cashier
  /// entered a counted-cash figure on close. Mirrors the variance block the
  /// printer appends to the receipt; this is the on-screen twin.
  Widget _buildZReportBlock(
    SessionSummaryReport session,
    AppLocalizations? l10n,
    CurrencyFormatter currencyFormatter,
  ) {
    final cs = Theme.of(context).colorScheme;
    final ch = _channelColors(context);
    final expected = session.startingBalance + session.paidByCash;
    final counted = session.countedCash ?? expected;
    final variance = session.variance ?? (counted - expected);
    // Variance semantics: on-target → cash/success tone; short → error;
    // over → warning. Tonal palette so contrast works in both modes.
    final varianceColor = variance.abs() < 0.005
        ? ch.cash
        : (variance < 0 ? cs.error : ch.unpaid);
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: cs.primary, size: 18),
              const SizedBox(width: 6),
              Text(
                l10n?.translate('z_report') ?? 'Z report',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                    fontSize: 14),
              ),
              const SizedBox(width: 8),
              Text(
                l10n?.translate('z_report_subtitle') ?? 'Session reconciliation',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _buildDetailItem(
                l10n?.translate('expected_cash') ?? 'Expected cash',
                currencyFormatter.format(expected),
              ),
              _buildDetailItem(
                l10n?.translate('counted_cash') ?? 'Counted cash',
                currencyFormatter.format(counted),
              ),
              _buildDetailItem(
                l10n?.translate('variance') ?? 'Variance',
                '${variance >= 0 ? '+' : ''}${currencyFormatter.format(variance)}',
                varianceColor,
              ),
              if (session.countedAt != null)
                _buildDetailItem(
                  l10n?.translate('printed_at') ?? 'Counted at',
                  _formatDateTime(session.countedAt!),
                ),
            ],
          ),
          if (session.countNotes != null &&
              session.countNotes!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n?.translate('count_notes') ?? 'Notes',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              session.countNotes!,
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, [Color? valueColor]) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 180,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant,
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
    final ch = _channelColors(context);
    final cs = Theme.of(context).colorScheme;
    switch (status.toLowerCase()) {
      case 'active':
        return ch.cash; // green-toned "live" indicator
      case 'paused':
        return ch.unpaid; // amber-toned "attention"
      case 'ended':
        return cs.onSurfaceVariant; // muted
      default:
        return cs.onSurfaceVariant;
    }
  }

  /// Distinct payment-channel colors. M3's `colorScheme` only carries 3
  /// accent slots (primary/secondary/tertiary), but the daily summary needs
  /// 6+ visually distinct semantic colors at a glance: cash, card, phone,
  /// other, unpaid, cancelled. So we keep the named colors but pick tonal
  /// shades that have legible contrast on BOTH light and dark surfaces.
  ({
    Color cash,
    Color card,
    Color phone,
    Color other,
    Color unpaid,
  }) _channelColors(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return (
      cash: isDark ? Colors.green.shade300 : Colors.green.shade700,
      card: isDark ? Colors.lightBlue.shade300 : Colors.blue.shade700,
      phone: isDark ? Colors.purple.shade200 : Colors.purple.shade700,
      other: Theme.of(context).colorScheme.onSurfaceVariant,
      unpaid: isDark ? Colors.orange.shade300 : Colors.orange.shade800,
    );
  }
}




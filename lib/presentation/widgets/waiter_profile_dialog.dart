import 'package:drift/drift.dart' show OrderingMode, OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart' as db;
import '../../domain/models/order_models.dart';
import '../../providers/admin_elevation_provider.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/snackbar_helper.dart';
import 'waiter_settlement_dialog.dart';

/// Validate a URL before handing it to [NetworkImage]. Returns false for
/// null, blank, or relative values (which Flutter would otherwise resolve
/// against the working directory and throw "No host specified in URI").
bool _isValidImageUrl(String? url) {
  if (url == null) return false;
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  return trimmed.startsWith('http://') || trimmed.startsWith('https://');
}

/// Per-waiter profile view. Long-press on a waiter card in
/// [WaiterSelectionDialog] opens this dialog (regular tap still selects
/// the waiter for the active order — gesture isolation is upstream).
///
/// Shows three KPI tiles (orders / paid / owed), a tabbed list (unpaid +
/// paid history), and three actions: close, print summary, settle all
/// (cash). The settle action composes [WaiterSettlementDialog] (the Phase
/// 3 transaction surface); on its result the profile reloads so KPIs and
/// lists reflect the just-paid orders.
///
/// **Time window:** scoped to the active [currentSessionProvider]. If no
/// session is open, falls back to today (00:00 → now).
class WaiterProfileDialog extends ConsumerStatefulWidget {
  final int waiterId;
  final String waiterName;
  final String? waiterImageUrl;
  final List<String> areaNames;

  const WaiterProfileDialog({
    super.key,
    required this.waiterId,
    required this.waiterName,
    this.waiterImageUrl,
    this.areaNames = const [],
  });

  @override
  ConsumerState<WaiterProfileDialog> createState() =>
      _WaiterProfileDialogState();
}

class _WaiterProfileDialogState extends ConsumerState<WaiterProfileDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _isLoading = true;
  bool _hasLoadedOnce = false;
  String? _error;

  // Resolved-window contents.
  List<OrderFullDetails> _orders = const [];
  List<db.Ticket> _paidTicketsForWindow = const [];
  int _ordersCount = 0;
  double _totalPaid = 0.0;
  double _totalOwed = 0.0;
  String _sessionLabel = '';

  // Cashier-side multi-select on the Unpaid tab. Empty = "pay all owed"
  // path; non-empty = "pay only these N" path. Cleared after a successful
  // settlement (the paid orders leave the unpaid tab anyway).
  final Set<int> _selectedUnpaidIds = {};

  /// When non-null, the dialog ignores the active-session-or-today default
  /// and queries the explicit date range instead. Set by tapping the date
  /// chip in the header → [showDateRangePicker].
  DateTimeRange? _overrideRange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // NOTE: `_load()` deliberately runs from `didChangeDependencies` — not
    // here. The label resolution needs `AppLocalizations.of(context)`,
    // which does `dependOnInheritedWidgetOfExactType` under the hood and
    // throws from initState.
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_hasLoadedOnce) return;
    _hasLoadedOnce = true;
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// SQL-side time window. Priority order:
  ///   1. An explicit override range set via the date-range picker.
  ///   2. Active cash session (matched by sessionId — so the dialog scopes
  ///      to "what's been rung up this shift").
  ///   3. Today, midnight → now.
  /// No L10n here — safe to call from initState/didChangeDependencies.
  ({DateTime? start, DateTime? end, int? sessionId}) _windowFilter() {
    if (_overrideRange != null) {
      final s = _overrideRange!.start;
      final e = _overrideRange!.end;
      return (
        start: DateTime(s.year, s.month, s.day),
        end: DateTime(e.year, e.month, e.day, 23, 59, 59),
        sessionId: null,
      );
    }
    // Admin elevation bypasses session scoping — admins see every order
    // ever attributed to the waiter, not just the current shift's. Mirrors
    // the orders-management bypass: admins audit, cashiers operate.
    final isAdmin = ref.read(adminElevationProvider) != null;
    final session = ref.read(currentSessionProvider);
    if (!isAdmin && session != null) {
      return (start: null, end: null, sessionId: session.id);
    }
    if (isAdmin) {
      return (start: null, end: null, sessionId: null);
    }
    final now = DateTime.now();
    return (
      start: DateTime(now.year, now.month, now.day),
      end: null,
      sessionId: null,
    );
  }

  /// Cashier-visible label for the window. Needs [AppLocalizations] so it
  /// is only resolved during/after build (not from initState).
  String _windowLabel(AppLocalizations l10n) {
    if (_overrideRange != null) {
      final s = _overrideRange!.start;
      final e = _overrideRange!.end;
      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      if (s.year == e.year && s.month == e.month && s.day == e.day) {
        return fmt(s);
      }
      return '${fmt(s)} → ${fmt(e)}';
    }
    // Admin elevation shows the all-time view — reflect that in the
    // label so the cashier knows what they're looking at.
    final isAdmin = ref.read(adminElevationProvider) != null;
    if (isAdmin) {
      return l10n.translate('session_label_all_time');
    }
    final session = ref.read(currentSessionProvider);
    if (session != null) {
      return l10n
          .translate('session_label_with_id')
          .replaceAll('{0}', session.id.toString());
    }
    return l10n.translate('session_label_today');
  }

  /// Open Flutter's built-in date-range picker, defaulting to the current
  /// active window so the cashier doesn't have to retap the right month
  /// when they just want to fine-tune. "Clear" reverts to the default
  /// (today + active session).
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final initial = _overrideRange ??
        DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: DateTime(now.year, now.month, now.day),
        );
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: initial,
      helpText: AppLocalizations.of(context)!.translate('select_date_range'),
    );
    if (picked == null) return;
    setState(() => _overrideRange = picked);
    await _load();
  }

  void _clearDateOverride() {
    if (_overrideRange == null) return;
    setState(() => _overrideRange = null);
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final repo = ref.read(orderRepositoryProvider);
      final w = _windowFilter();
      // Capture the label here too so the header subtitle stays in sync
      // with the window the data was fetched for (a session change
      // mid-fetch would otherwise leave a stale label).
      final label = mounted ? _windowLabel(AppLocalizations.of(context)!) : '';
      final result = await repo.getPaginatedOrdersWithFullDetails(
        page: 0,
        pageSize: 200,
        waiterId: widget.waiterId,
        sessionId: w.sessionId,
        startDate: w.start,
        endDate: w.end,
      );

      // KPI math. `result.totalCount` is the SQL-side count after every
      // filter the count phase ran (status/type/unpaid/etc. are all
      // unused here, so it tracks `result.orders.length` for our window).
      // We sum paid + owed off `result.orders` for the same reason — no
      // pagination cutoff in play for the typical session size.
      var paid = 0.0;
      var owed = 0.0;
      for (final o in result.orders) {
        paid += o.totalPaid;
        final due = o.total - o.totalPaid;
        if (due > 0) owed += due;
      }

      // Ticket-level paid history. Pull tickets for the orders we just
      // loaded so we can show per-payment rows (a single order may have
      // multiple tickets). Cap at 50 — older history lives in the orders
      // management screen.
      final database = ref.read(databaseProvider);
      final orderIds = result.orders.map((o) => o.order.id).toList();
      final tickets = orderIds.isEmpty
          ? <db.Ticket>[]
          : await (database.select(database.tickets)
                ..where((t) => t.orderId.isIn(orderIds))
                ..where((t) => t.isPaid.equals(true))
                ..orderBy([(t) => OrderingTerm(
                      expression: t.date,
                      mode: OrderingMode.desc,
                    )])
                ..limit(50))
              .get();

      if (!mounted) return;
      setState(() {
        _orders = result.orders;
        _ordersCount = result.totalCount;
        _totalPaid = paid;
        _totalOwed = owed;
        _paidTicketsForWindow = tickets;
        _sessionLabel = label;
        _isLoading = false;
      });
    } catch (e, st) {
      // Print the underlying error so it shows in the console — the
      // on-screen message is fine for the cashier but useless for
      // debugging once they've closed the dialog.
      // ignore: avoid_print
      print('WaiterProfileDialog._load failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _printSummary() async {
    final printingService = ref.read(printingServiceProvider);
    final cashier = ref.read(currentUserProvider);
    final unpaid = _orders.where((o) => (o.total - o.totalPaid) > 0).toList();

    final ok = await printingService.printWaiterProfileSummary(
      waiterName: widget.waiterName,
      sessionLabel: _sessionLabel,
      ordersCount: _ordersCount,
      totalPaid: _totalPaid,
      totalOwed: _totalOwed,
      unpaidOrders: unpaid
          .map((o) {
            final due = o.total - o.totalPaid;
            return (
              code: o.order.code,
              due: due > 0 ? due : 0.0,
              tableName: o.tableName,
            );
          })
          .toList(),
      paidTickets: _paidTicketsForWindow
          .map((t) => (
                ticketNum: t.num,
                paymentMethod: t.paymentMethod,
                amount: t.amount,
                at: t.date,
              ))
          .toList(),
      cashierName: cashier?.firstName,
    );
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    if (ok) {
      SnackBarHelper.success(context, l10n.translate('printed_successfully'));
    } else {
      SnackBarHelper.error(context, l10n.translate('print_error'));
    }
  }

  Future<void> _openSettlement() async {
    // Empty selection → full settlement (today's default). Non-empty →
    // narrow the settlement dialog to just those order ids so the cashier
    // doesn't have to re-uncheck rows they already filtered out here.
    final restricted = _selectedUnpaidIds.isEmpty
        ? null
        : Set<int>.of(_selectedUnpaidIds);
    final settled = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => WaiterSettlementDialog(
        waiterId: widget.waiterId,
        waiterName: widget.waiterName,
        restrictedOrderIds: restricted,
      ),
    );
    if (settled == true && mounted) {
      setState(_selectedUnpaidIds.clear);
      // Refresh so KPIs + tabs reflect the just-paid orders.
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final fmt = ref.read(currencyFormatterProvider);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 720,
        height: 580,
        child: Column(
          children: [
            _buildHeader(l10n, cs),
            const Divider(height: 1),
            Expanded(child: _buildBody(l10n, cs, fmt)),
            const Divider(height: 1),
            _buildActions(l10n, cs),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppLocalizations l10n, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: cs.primary,
            // Guard against null, empty, or non-URL imageUrls — passing an
            // empty string to NetworkImage resolves to the working dir as a
            // `file:///…` URI and throws "No host specified in URI".
            backgroundImage: _isValidImageUrl(widget.waiterImageUrl)
                ? NetworkImage(widget.waiterImageUrl!)
                : null,
            child: !_isValidImageUrl(widget.waiterImageUrl)
                ? Text(
                    widget.waiterName.isNotEmpty
                        ? widget.waiterName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cs.onPrimary,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.waiterName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (widget.areaNames.isNotEmpty)
                  Text(
                    widget.areaNames.join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                if (_sessionLabel.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Tap chip → open the range picker. Visually
                        // pops to a "filter active" tone when the override
                        // is set so the cashier sees they're looking at a
                        // custom window, not the default session/today.
                        InputChip(
                          avatar: Icon(
                            Icons.calendar_today,
                            size: 14,
                            color: _overrideRange != null
                                ? cs.onPrimary
                                : cs.onSurfaceVariant,
                          ),
                          label: Text(
                            _sessionLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: _overrideRange != null
                                  ? cs.onPrimary
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                          onPressed: _pickDateRange,
                          backgroundColor: _overrideRange != null
                              ? cs.primary
                              : cs.surfaceContainerHigh,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                        ),
                        if (_overrideRange != null)
                          IconButton(
                            tooltip: l10n.translate('clear'),
                            icon: Icon(Icons.clear,
                                size: 16, color: cs.onSurfaceVariant),
                            onPressed: _clearDateOverride,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            padding: EdgeInsets.zero,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ColorScheme cs, CurrencyFormatter fmt) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: SelectableText(
            _error!,
            style: TextStyle(color: cs.error),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _kpiTile(
                  label: l10n.translate('kpi_orders'),
                  value: '$_ordersCount',
                  icon: Icons.receipt_long,
                  color: cs.primary),
              const SizedBox(width: 8),
              _kpiTile(
                  label: l10n.translate('kpi_paid'),
                  value: fmt.format(_totalPaid),
                  icon: Icons.check_circle,
                  color: cs.tertiary),
              const SizedBox(width: 8),
              _kpiTile(
                  label: l10n.translate('kpi_owed'),
                  value: fmt.format(_totalOwed),
                  icon: Icons.account_balance_wallet,
                  color: _totalOwed > 0.005 ? cs.error : cs.onSurfaceVariant),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          tabs: [
            Tab(text: '${l10n.translate('tab_unpaid')} (${_unpaidCount()})'),
            Tab(
                text:
                    '${l10n.translate('tab_paid_history')} (${_paidTicketsForWindow.length})'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildUnpaidTab(l10n, cs, fmt),
              _buildPaidHistoryTab(l10n, cs, fmt),
            ],
          ),
        ),
      ],
    );
  }

  int _unpaidCount() {
    var n = 0;
    for (final o in _orders) {
      if ((o.total - o.totalPaid) > 0.005) n++;
    }
    return n;
  }

  Widget _kpiTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnpaidTab(
      AppLocalizations l10n, ColorScheme cs, CurrencyFormatter fmt) {
    final unpaid = _orders.where((o) => (o.total - o.totalPaid) > 0.005).toList();
    if (unpaid.isEmpty) {
      return Center(
        child: Text(
          l10n.translate('settle_no_unpaid'),
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    // Prune selection of any ids that no longer exist (orders settled
    // through another path while the dialog was open). Keeps the bottom
    // button label honest.
    final liveIds = unpaid.map((o) => o.order.id).toSet();
    _selectedUnpaidIds.removeWhere((id) => !liveIds.contains(id));

    return ListView.separated(
      itemCount: unpaid.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final o = unpaid[i];
        final due = o.total - o.totalPaid;
        final isSelected = _selectedUnpaidIds.contains(o.order.id);
        return CheckboxListTile(
          dense: true,
          value: isSelected,
          onChanged: (v) {
            setState(() {
              if (v == true) {
                _selectedUnpaidIds.add(o.order.id);
              } else {
                _selectedUnpaidIds.remove(o.order.id);
              }
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
          title: Row(
            children: [
              Expanded(
                child: Text(
                  o.order.code,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                fmt.format(due),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          subtitle: Text(
            [
              o.order.type,
              if (o.tableName != null) o.tableName!,
              if (o.customerName != null) o.customerName!,
            ].join(' • '),
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        );
      },
    );
  }

  Widget _buildPaidHistoryTab(
      AppLocalizations l10n, ColorScheme cs, CurrencyFormatter fmt) {
    if (_paidTicketsForWindow.isEmpty) {
      return Center(
        child: Text(
          '—',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      itemCount: _paidTicketsForWindow.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final t = _paidTicketsForWindow[i];
        final timeStr =
            '${t.date.hour.toString().padLeft(2, '0')}:${t.date.minute.toString().padLeft(2, '0')}';
        return ListTile(
          dense: true,
          leading: Icon(
            Icons.check_circle,
            color: cs.tertiary,
            size: 18,
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '#${t.num}  ·  ${t.paymentMethod}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                fmt.format(t.amount),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          subtitle: Text(timeStr,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
        );
      },
    );
  }

  Widget _buildActions(AppLocalizations l10n, ColorScheme cs) {
    // Button mode follows the Unpaid tab selection:
    //   - none selected → "Pay all (cash)" against everything owed
    //   - 1+ selected   → "Pay N selected (cash)" against just those orders
    // Enabled only when there's something to pay in the chosen scope.
    final hasSelection = _selectedUnpaidIds.isNotEmpty;
    final canSettle = hasSelection
        ? _selectedUnpaidIds.isNotEmpty
        : _totalOwed > 0.005;
    final settleLabel = hasSelection
        ? l10n
            .translate('settle_pay_n_selected_cash')
            .replaceAll('{0}', _selectedUnpaidIds.length.toString())
        : l10n.translate('settle_pay_all_cash');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.translate('close')),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _isLoading ? null : _printSummary,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(l10n.translate('settle_print_slip')),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: (canSettle && !_isLoading) ? _openSettlement : null,
            icon: const Icon(Icons.payments, size: 18),
            label: Text(settleLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

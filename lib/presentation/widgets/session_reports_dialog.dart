import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../data/database/app_database.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/daily_summary_service.dart';
import '../../services/permission_service.dart';
import '../../services/unpaid_orders_service.dart';
import '../../utils/admin_auth.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/escpos_text.dart';
import '../../utils/snackbar_helper.dart';

/// The reports a session's Reports panel offers, in print order.
enum _Report { x, products, options, orders }

/// Read and print a session's reports — the X, products sold, options sold
/// and the orders list — for the session or for its whole trading day.
///
/// Everything here is a read: nothing closes, nothing is written, so it is
/// safe on a live session. That is also why every report is stamped
/// PROVISIONAL while its scope is still trading — a mid-day read must never be
/// filed as the closing figures.
///
/// The X is one report among the others rather than a mandatory first page:
/// a manager who only wants the products ticket gets only that.
///
/// The whole-day scope shows other cashiers' takings, and the till is usually
/// left signed in as whoever is on, so it asks for a manager (`pos:z:view`) or
/// an admin unless the signed-in user already is one.
Future<void> showSessionReportsDialog({
  required BuildContext context,
  required WidgetRef ref,
  required CashSession session,
}) async {
  final l10n = AppLocalizations.of(context)!;
  if (!ref
      .read(permissionServiceProvider)
      .hasPermission(Permissions.reportsView)) {
    SnackBarHelper.error(context, l10n.translate('no_permission'));
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => _SessionReportsDialog(session: session),
  );
}

/// What the X tab needs: the figures to print, and the paper as text to show.
class _XData {
  final DailySummaryReport report;
  final UnpaidOrdersSummary? outstanding;
  final String paper;

  const _XData(this.report, this.outstanding, this.paper);
}

class _SessionReportsDialog extends ConsumerStatefulWidget {
  final CashSession session;

  const _SessionReportsDialog({required this.session});

  @override
  ConsumerState<_SessionReportsDialog> createState() =>
      _SessionReportsDialogState();
}

class _SessionReportsDialogState extends ConsumerState<_SessionReportsDialog> {
  bool _dayScope = false;
  bool _dayUnlocked = false;
  _Report _viewing = _Report.x;
  late final Set<_Report> _toPrint;

  late bool _productsByCategory;
  ProductsSort _productsSort = ProductsSort.quantity;
  bool _productsQty = true;
  bool _productsAmounts = true;
  bool _optionsQty = true;
  bool _optionsAmounts = true;

  Future<({ReportScope scope, bool provisional})>? _scope;
  final Map<_Report, Future<Object>> _data = {};
  DateTime _asOf = DateTime.now();
  bool _printing = false;

  DailySummaryService get _summaries =>
      DailySummaryService(ref.read(databaseProvider));

  @override
  void initState() {
    super.initState();
    // Seeded from the close-time ticks, never written back: this is an ad-hoc
    // read, and re-configuring what session close prints from here would be
    // a surprise.
    final s = ref.read(settingsProvider);
    _productsByCategory = s.printProductsByCategoryOnClose;
    _toPrint = {
      _Report.x,
      if (s.printProductSummaryOnClose) _Report.products,
      if (s.printOrdersListOnClose) _Report.orders,
    };
  }

  // ── Data ─────────────────────────────────────────────────────────────────

  Future<({ReportScope scope, bool provisional})> _resolveScope() async {
    final db = ref.read(databaseProvider);
    final session = widget.session;
    if (!_dayScope) {
      final fresh = await (db.select(db.cashSessions)
            ..where((s) => s.id.equals(session.id)))
          .getSingleOrNull();
      return (
        scope: (
          sessionIds: [session.id],
          label: session.code,
          sessionCodes: [session.code],
          zCode: null,
          zNumber: null,
        ),
        provisional: (fresh ?? session).endedAt == null,
      );
    }
    final scope = await _summaries.dayScopeFor(session);
    final rows = await (db.select(db.cashSessions)
          ..where((s) => s.id.isIn(scope.sessionIds)))
        .get();
    var provisional = rows.any((s) => s.endedAt == null);
    if (!provisional) {
      // Every shift ended, but the day is only settled once its Z is closed;
      // without Z tracking, today can still take another shift.
      if (session.zId != null) {
        final z = await (db.select(db.zs)
              ..where((t) => t.id.equals(session.zId!)))
            .getSingleOrNull();
        provisional = z != null && z.status != 'closed';
      } else {
        final now = DateTime.now();
        final d = session.startedAt;
        provisional =
            d.year == now.year && d.month == now.month && d.day == now.day;
      }
    }
    return (scope: scope, provisional: provisional);
  }

  Future<({ReportScope scope, bool provisional})> get _scopeFuture =>
      _scope ??= _resolveScope();

  Future<Object> _load(_Report r) => _data[r] ??= _build(r);

  Future<Object> _build(_Report r) async {
    final resolved = await _scopeFuture;
    final scope = resolved.scope;
    switch (r) {
      case _Report.x:
        final DailySummaryReport report;
        if (_dayScope) {
          final d = widget.session.startedAt;
          report = await _summaries.generateReport(
            startDate: DateTime(d.year, d.month, d.day),
            endDate: DateTime.now(),
            sessionIds: scope.sessionIds,
          );
        } else {
          report = await _summaries.generateSessionReport(widget.session.id);
        }
        UnpaidOrdersSummary? outstanding;
        try {
          outstanding =
              await UnpaidOrdersService(ref.read(databaseProvider)).summary();
        } catch (e) {
          Logger.instance.error('Reports: outstanding lookup failed: $e');
        }
        if (!mounted) throw StateError('closed');
        // The on-screen X is decoded from the very bytes the printer would
        // get, so the screen and the paper cannot disagree.
        final bytes =
            await ref.read(printingServiceProvider).buildDailySummaryReportBytes(
                  report: report,
                  reportType: 'X',
                  l10n: AppLocalizations.of(context),
                  currencyFormatter: ref.read(currencyFormatterProvider),
                  businessName: _businessName,
                  outstanding: outstanding,
                  zLabel: scope.zCode,
                  provisional: resolved.provisional,
                );
        return _XData(report, outstanding, escPosToText(bytes));
      case _Report.products:
        return _summaries.generateProductsSummary(
          sessionIds: scope.sessionIds,
          scopeLabel: scope.label,
          sessionCodes: scope.sessionCodes,
          zCode: scope.zCode,
          zNumber: scope.zNumber,
        );
      case _Report.options:
        return _summaries.generateOptionsSummary(
          sessionIds: scope.sessionIds,
          scopeLabel: scope.label,
          sessionCodes: scope.sessionCodes,
          zCode: scope.zCode,
          zNumber: scope.zNumber,
        );
      case _Report.orders:
        return _summaries.generateOrdersList(
          sessionIds: scope.sessionIds,
          scopeLabel: scope.label,
          sessionCodes: scope.sessionCodes,
          zCode: scope.zCode,
          zNumber: scope.zNumber,
        );
    }
  }

  String? get _businessName =>
      ref.read(sharedPreferencesProvider).getString('business_name');

  void _refresh() {
    setState(() {
      _scope = null;
      _data.clear();
      _asOf = DateTime.now();
    });
  }

  // ── Scope ────────────────────────────────────────────────────────────────

  Future<void> _setDayScope(bool day) async {
    if (day == _dayScope) return;
    if (day && !_dayUnlocked) {
      final l10n = AppLocalizations.of(context)!;
      if (!ref
          .read(permissionServiceProvider)
          .hasPermission(Permissions.zView)) {
        final elevation = await showAdminCredentialDialog(
          context,
          ref,
          title: l10n.translate('scope_whole_day'),
          description: l10n.translate('scope_day_needs_manager'),
          permission: Permissions.zView,
        );
        if (elevation == null || !mounted) return;
      }
      _dayUnlocked = true;
    }
    setState(() => _dayScope = day);
    _refresh();
  }

  // ── Printing ─────────────────────────────────────────────────────────────

  Future<bool> _print(_Report r) async {
    final printing = ref.read(printingServiceProvider);
    final provisional = (await _scopeFuture).provisional;
    final data = await _load(r);
    final scope = (await _scopeFuture).scope;
    switch (r) {
      case _Report.x:
        final x = data as _XData;
        if (!mounted) return false;
        return printing.printDailySummaryReport(
          report: x.report,
          reportType: 'X',
          l10n: AppLocalizations.of(context),
          currencyFormatter: ref.read(currencyFormatterProvider),
          businessName: _businessName,
          outstanding: x.outstanding,
          zLabel: scope.zCode,
          provisional: provisional,
        );
      case _Report.products:
        return printing.printProductsSummary(
          report: data as ProductsSummaryReport,
          businessName: _businessName,
          groupByCategory: _productsByCategory,
          sort: _productsSort,
          showQuantities: _productsQty,
          showAmounts: _productsAmounts,
          provisional: provisional,
        );
      case _Report.options:
        return printing.printOptionsSummary(
          report: data as OptionsSummaryReport,
          businessName: _businessName,
          showQuantities: _optionsQty,
          showAmounts: _optionsAmounts,
          provisional: provisional,
        );
      case _Report.orders:
        return printing.printOrdersList(
          report: data as OrdersListReport,
          businessName: _businessName,
          provisional: provisional,
        );
    }
  }

  /// Each report prints on its own cut, and a failure is isolated so one dead
  /// report cannot swallow the rest; the cashier is told what actually came
  /// out rather than handed a bare success.
  Future<void> _printReports(List<_Report> reports) async {
    final l10n = AppLocalizations.of(context)!;
    if (reports.isEmpty) {
      SnackBarHelper.info(context, l10n.translate('reports_nothing_selected'));
      return;
    }
    setState(() => _printing = true);
    var printed = 0;
    for (final r in reports) {
      try {
        if (await _print(r)) printed++;
      } catch (e) {
        Logger.instance.error('Reports: printing ${r.name} failed: $e');
      }
    }
    if (!mounted) return;
    setState(() => _printing = false);
    if (printed == reports.length) {
      SnackBarHelper.success(context,
          l10n.translate('reports_printed').replaceAll('{0}', '$printed'));
    } else {
      SnackBarHelper.error(
          context,
          l10n
              .translate('reports_printed_partial')
              .replaceAll('{0}', '$printed')
              .replaceAll('{1}', '${reports.length}'));
    }
  }

  List<_Report> get _selectedInOrder =>
      _Report.values.where(_toPrint.contains).toList();

  // ── UI ───────────────────────────────────────────────────────────────────

  String _title(AppLocalizations l10n, _Report r) => switch (r) {
        _Report.x => l10n.translate('x_report_short'),
        _Report.products => l10n.translate('report_products_sold'),
        _Report.options => l10n.translate('options_report'),
        _Report.orders => l10n.translate('orders_report'),
      };

  IconData _icon(_Report r) => switch (r) {
        _Report.x => Icons.receipt_long_rounded,
        _Report.products => Icons.inventory_2_outlined,
        _Report.options => Icons.tune_rounded,
        _Report.orders => Icons.list_alt_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 820;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): () {
          if (!_printing) _printReports(_selectedInOrder);
        },
        const SingleActivator(LogicalKeyboardKey.f5): _refresh,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          insetPadding: EdgeInsets.all(wide ? 32 : 12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 1180,
              maxHeight: size.height * 0.92,
            ),
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: Column(
                children: [
                  _header(l10n, scheme, wide),
                  _provisionalBar(l10n, scheme),
                  const Divider(height: 1),
                  Expanded(
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(width: 290, child: _sidebar(l10n, scheme)),
                              const VerticalDivider(width: 1),
                              Expanded(child: _preview(l10n, scheme)),
                            ],
                          )
                        : Column(
                            children: [
                              _compactPicker(l10n),
                              const Divider(height: 1),
                              Expanded(child: _preview(l10n, scheme)),
                            ],
                          ),
                  ),
                  const Divider(height: 1),
                  _footer(l10n, scheme, wide),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AppLocalizations l10n, ColorScheme scheme, bool wide) {
    final scope = SegmentedButton<bool>(
      segments: [
        ButtonSegment(
          value: false,
          icon: const Icon(Icons.person_outline, size: 18),
          label: Text(l10n.translate('scope_this_session')),
        ),
        ButtonSegment(
          value: true,
          icon: Icon(
            _dayUnlocked ? Icons.calendar_today_outlined : Icons.lock_outline,
            size: 18,
          ),
          label: Text(l10n.translate('scope_whole_day')),
          tooltip: l10n.translate('scope_day_needs_manager'),
        ),
      ],
      selected: {_dayScope},
      showSelectedIcon: false,
      onSelectionChanged: _printing ? null : (v) => _setDayScope(v.first),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 10,
        spacing: 16,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assessment_outlined, color: scheme.primary),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.translate('session_reports_title'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  FutureBuilder(
                    future: _scopeFuture,
                    builder: (context, snap) {
                      final s = snap.data?.scope;
                      final parts = [
                        '${l10n.translate('session')} ${widget.session.code}',
                        if (_dayScope && s != null) ...[
                          s.zCode ?? s.label,
                          l10n
                              .translate('report_sessions_count')
                              .replaceAll('{0}', '${s.sessionIds.length}'),
                        ],
                        l10n
                            .translate('report_as_of')
                            .replaceAll('{0}', _clock(_asOf)),
                      ];
                      return Text(
                        parts.join('  ·  '),
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              scope,
              const SizedBox(width: 4),
              IconButton(
                tooltip: '${l10n.translate('refresh')} (F5)',
                onPressed: _printing ? null : _refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
              IconButton(
                tooltip: l10n.translate('close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _provisionalBar(AppLocalizations l10n, ColorScheme scheme) {
    return FutureBuilder(
      future: _scopeFuture,
      builder: (context, snap) {
        if (snap.data?.provisional != true) return const SizedBox.shrink();
        return Container(
          width: double.infinity,
          color: scheme.tertiaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.hourglass_top_rounded,
                  size: 18, color: scheme.onTertiaryContainer),
              const SizedBox(width: 10),
              Text(
                l10n.translate('report_provisional_stamp'),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.translate('report_provisional_banner'),
                  style: TextStyle(color: scheme.onTertiaryContainer),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sidebar(AppLocalizations l10n, ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final r in _Report.values) _reportTile(l10n, scheme, r),
        const Divider(height: 24),
        ..._displayOptions(l10n, scheme),
      ],
    );
  }

  Widget _reportTile(AppLocalizations l10n, ColorScheme scheme, _Report r) {
    final selected = _viewing == r;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? scheme.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _viewing = r),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                Tooltip(
                  message: l10n.translate('report_include_in_print'),
                  child: Checkbox(
                    value: _toPrint.contains(r),
                    onChanged: _printing
                        ? null
                        : (v) => setState(() =>
                            v == true ? _toPrint.add(r) : _toPrint.remove(r)),
                  ),
                ),
                Icon(_icon(r),
                    size: 20,
                    color: selected
                        ? scheme.onSecondaryContainer
                        : scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _title(l10n, r),
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w600 : null,
                      color: selected ? scheme.onSecondaryContainer : null,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.chevron_right_rounded,
                      color: scheme.onSecondaryContainer),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The view options of the report on screen. They shape the paper too, so
  /// what is printed is what was looked at.
  List<Widget> _displayOptions(AppLocalizations l10n, ColorScheme scheme) {
    Widget heading() => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
          child: Text(
            '${l10n.translate('report_display')} — ${_title(l10n, _viewing)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        );

    Widget toggle(String label, bool value, void Function(bool) set,
            {bool locked = false}) =>
        SwitchListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: Text(label),
          value: value,
          // The last visible column cannot be switched off — a ticket of bare
          // names says nothing.
          onChanged: _printing || (value && locked)
              ? null
              : (v) => setState(() => set(v)),
        );

    switch (_viewing) {
      case _Report.products:
        return [
          heading(),
          toggle(l10n.translate('show_quantities'), _productsQty,
              (v) => _productsQty = v,
              locked: !_productsAmounts),
          toggle(l10n.translate('report_show_prices'), _productsAmounts,
              (v) => _productsAmounts = v,
              locked: !_productsQty),
          toggle(l10n.translate('report_group_by_category'),
              _productsByCategory, (v) => _productsByCategory = v),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(l10n.translate('report_sort_by'),
                style: const TextStyle(fontSize: 13)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ProductsSort>(
              segments: [
                ButtonSegment(
                    value: ProductsSort.quantity,
                    label: Text(l10n.translate('report_sort_quantity'))),
                ButtonSegment(
                    value: ProductsSort.amount,
                    label: Text(l10n.translate('report_sort_amount'))),
                ButtonSegment(
                    value: ProductsSort.name,
                    label: Text(l10n.translate('report_sort_name'))),
              ],
              selected: {_productsSort},
              showSelectedIcon: false,
              onSelectionChanged: _printing
                  ? null
                  : (v) => setState(() => _productsSort = v.first),
            ),
          ),
        ];
      case _Report.options:
        return [
          heading(),
          toggle(l10n.translate('show_quantities'), _optionsQty,
              (v) => _optionsQty = v,
              locked: !_optionsAmounts),
          toggle(l10n.translate('report_show_prices'), _optionsAmounts,
              (v) => _optionsAmounts = v,
              locked: !_optionsQty),
        ];
      case _Report.x:
      case _Report.orders:
        return const [];
    }
  }

  /// Narrow screens: the report list as chips above the preview.
  Widget _compactPicker(AppLocalizations l10n) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          for (final r in _Report.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InputChip(
                avatar: Icon(_icon(r), size: 18),
                label: Text(_title(l10n, r)),
                selected: _viewing == r,
                onPressed: () => setState(() => _viewing = r),
                deleteIcon: Icon(
                  _toPrint.contains(r)
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 18,
                ),
                deleteButtonTooltipMessage:
                    l10n.translate('report_include_in_print'),
                onDeleted: () => setState(() => _toPrint.contains(r)
                    ? _toPrint.remove(r)
                    : _toPrint.add(r)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _preview(AppLocalizations l10n, ColorScheme scheme) {
    final r = _viewing;
    return FutureBuilder<Object>(
      // Keyed so switching report or scope never shows the previous one's
      // data for a frame.
      key: ValueKey('$r-$_dayScope-${_asOf.microsecondsSinceEpoch}'),
      future: _load(r),
      builder: (context, snap) {
        if (snap.hasError) {
          Logger.instance.error('Reports: ${r.name} failed: ${snap.error}');
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: scheme.error, size: 36),
                const SizedBox(height: 8),
                Text(l10n.translate('report_load_failed')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.translate('retry')),
                ),
              ],
            ),
          );
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data!;
        return switch (r) {
          _Report.x => _XPaper(text: (data as _XData).paper),
          _Report.products => _ProductsView(
              report: data as ProductsSummaryReport,
              byCategory: _productsByCategory,
              sort: _productsSort,
              showQty: _productsQty,
              showAmounts: _productsAmounts,
            ),
          _Report.options => _OptionsView(
              report: data as OptionsSummaryReport,
              showQty: _optionsQty,
              showAmounts: _optionsAmounts,
            ),
          _Report.orders => _OrdersView(report: data as OrdersListReport),
        };
      },
    );
  }

  Widget _footer(AppLocalizations l10n, ColorScheme scheme, bool wide) {
    final selected = _selectedInOrder;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 12),
      child: Row(
        children: [
          if (wide)
            Expanded(
              child: Text(
                selected.map((r) => _title(l10n, r)).join(' · '),
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          if (_printing)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          OutlinedButton.icon(
            onPressed: _printing ? null : () => _printReports([_viewing]),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(l10n.translate('print_this_report')),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Ctrl+P',
            child: FilledButton.icon(
              onPressed: _printing || selected.isEmpty
                  ? null
                  : () => _printReports(selected),
              icon: const Icon(Icons.print_rounded, size: 18),
              label: Text(l10n
                  .translate('print_selected_reports')
                  .replaceAll('{0}', '${selected.length}')),
            ),
          ),
        ],
      ),
    );
  }
}

String _clock(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _qty(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

/// The X as it comes off the printer, on a strip of "paper".
class _XPaper extends StatelessWidget {
  final String text;

  const _XPaper({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerLow,
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Material(
          elevation: 2,
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: SelectableText(
              text.trimRight(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: ['Consolas', 'Courier New', 'Courier'],
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A plain report table: header row, body rows, and an optional bold total.
class _ReportTable extends StatelessWidget {
  final List<String> columns;

  /// Column indexes that hold figures — right-aligned.
  final Set<int> numeric;
  final Map<int, int> flex;
  final List<_Row> rows;
  final String? emptyText;

  const _ReportTable({
    required this.columns,
    required this.rows,
    this.numeric = const {},
    this.flex = const {},
    this.emptyText,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (rows.isEmpty && emptyText != null) {
      return Center(
        child: Text(emptyText!,
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    Widget line(List<String> cells,
        {TextStyle? style, Color? background, bool strike = false}) {
      return Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                flex: flex[i] ?? 1,
                child: Text(
                  cells[i],
                  textAlign:
                      numeric.contains(i) ? TextAlign.end : TextAlign.start,
                  overflow: TextOverflow.ellipsis,
                  style: (style ?? const TextStyle()).copyWith(
                    decoration: strike ? TextDecoration.lineThrough : null,
                    fontFeatures: numeric.contains(i)
                        ? const [FontFeature.tabularFigures()]
                        : null,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Column(
      children: [
        line(
          columns,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
            color: scheme.onSurfaceVariant,
          ),
          background: scheme.surfaceContainerHigh,
        ),
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final r = rows[i];
              return switch (r.kind) {
                _RowKind.section => line(r.cells,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: scheme.primary),
                    background: scheme.surfaceContainerLow),
                _RowKind.subtotal => line(r.cells,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                _RowKind.total => line(r.cells,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                    background: scheme.secondaryContainer),
                _RowKind.normal => line(r.cells,
                    background: i.isOdd
                        ? scheme.surfaceContainerLowest
                        : null,
                    strike: r.strike,
                    style: r.muted
                        ? TextStyle(color: scheme.onSurfaceVariant)
                        : null),
              };
            },
          ),
        ),
      ],
    );
  }
}

enum _RowKind { normal, section, subtotal, total }

class _Row {
  final List<String> cells;
  final _RowKind kind;
  final bool strike;
  final bool muted;

  const _Row(this.cells,
      {this.kind = _RowKind.normal, this.strike = false, this.muted = false});
}

class _ProductsView extends ConsumerWidget {
  final ProductsSummaryReport report;
  final bool byCategory;
  final ProductsSort sort;
  final bool showQty;
  final bool showAmounts;

  const _ProductsView({
    required this.report,
    required this.byCategory,
    required this.sort,
    required this.showQty,
    required this.showAmounts,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final money = ref.watch(currencyFormatterProvider);

    // Columns: name, [category], [qty], [discount, amount]
    final columns = <String>[
      l10n.translate('report_products_sold'),
      if (!byCategory) l10n.translate('category'),
      if (showQty) l10n.translate('quantity'),
      if (showAmounts) ...[
        l10n.translate('discount'),
        l10n.translate('amount'),
      ],
    ];
    final firstFigure = byCategory ? 1 : 2;
    final numeric = {
      for (var i = firstFigure; i < columns.length; i++) i,
    };

    List<String> cells(String name, String? category, double q, double disc,
            double net) =>
        [
          name,
          if (!byCategory) category ?? '',
          if (showQty) _qty(q),
          if (showAmounts) ...[
            disc.abs() > 0.005 ? '-${money.format(disc)}' : '',
            money.format(net),
          ],
        ];

    final sorted = sortProductRows(report.rows, sort);
    final rows = <_Row>[];
    if (byCategory) {
      final sections = <String, List<ProductSummaryEntry>>{};
      for (final r in sorted) {
        final key = (r.categoryName ?? '').trim().isEmpty
            ? l10n.translate('uncategorized')
            : r.categoryName!.trim();
        sections.putIfAbsent(key, () => []).add(r);
      }
      double sum(List<ProductSummaryEntry> l,
              double Function(ProductSummaryEntry) f) =>
          l.fold(0.0, (s, r) => s + f(r));
      final ordered = sections.entries.toList()
        ..sort((a, b) => switch (sort) {
              ProductsSort.quantity => sum(b.value, (r) => r.quantity)
                  .compareTo(sum(a.value, (r) => r.quantity)),
              ProductsSort.amount =>
                sum(b.value, (r) => r.net).compareTo(sum(a.value, (r) => r.net)),
              ProductsSort.name =>
                a.key.toLowerCase().compareTo(b.key.toLowerCase()),
            });
      for (final e in ordered) {
        rows.add(_Row([e.key.toUpperCase(), for (var i = 1; i < columns.length; i++) ''],
            kind: _RowKind.section));
        for (final r in e.value) {
          rows.add(_Row(cells(r.name, null, r.quantity, r.discount, r.net)));
        }
        rows.add(_Row(
          cells(
            l10n.translate('subtotal'),
            null,
            sum(e.value, (r) => r.quantity),
            sum(e.value, (r) => r.discount),
            sum(e.value, (r) => r.net),
          ),
          kind: _RowKind.subtotal,
        ));
      }
    } else {
      for (final r in sorted) {
        rows.add(
            _Row(cells(r.name, r.categoryName, r.quantity, r.discount, r.net)));
      }
    }
    if (report.rows.isNotEmpty) {
      rows.add(_Row(
        cells(l10n.translate('total'), '', report.totalQuantity,
            report.totalDiscount, report.totalNet),
        kind: _RowKind.total,
      ));
    }

    return _ReportTable(
      columns: columns,
      numeric: numeric,
      flex: const {0: 3},
      rows: rows,
      emptyText: l10n.translate('no_orders_in_scope'),
    );
  }
}

class _OptionsView extends ConsumerWidget {
  final OptionsSummaryReport report;
  final bool showQty;
  final bool showAmounts;

  const _OptionsView({
    required this.report,
    required this.showQty,
    required this.showAmounts,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final money = ref.watch(currencyFormatterProvider);
    final without = l10n.translate('option_removed_prefix');

    List<String> cells(String name, double q, double amount) => [
          name,
          if (showQty) _qty(q),
          if (showAmounts) money.format(amount),
        ];
    final columns = [
      l10n.translate('options_report'),
      if (showQty) l10n.translate('quantity'),
      if (showAmounts) l10n.translate('amount'),
    ];

    return _ReportTable(
      columns: columns,
      numeric: {for (var i = 1; i < columns.length; i++) i},
      flex: const {0: 3},
      emptyText: l10n.translate('no_options_in_scope'),
      rows: [
        for (final r in report.rows)
          _Row(
            cells(r.removal ? '$without ${r.name}' : r.name, r.quantity,
                r.amount),
            muted: r.removal,
          ),
        if (report.rows.isNotEmpty)
          _Row(
            cells(l10n.translate('total'), report.totalQuantity,
                report.totalAmount),
            kind: _RowKind.total,
          ),
      ],
    );
  }
}

class _OrdersView extends ConsumerWidget {
  final OrdersListReport report;

  const _OrdersView({required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final money = ref.watch(currencyFormatterProvider);

    String orNothing(String? s) => (s ?? '').trim();

    return _ReportTable(
      columns: [
        l10n.translate('report_order_no'),
        l10n.translate('time'),
        l10n.translate('type'),
        l10n.translate('table'),
        l10n.translate('waiter'),
        l10n.translate('payment_method'),
        l10n.translate('total'),
        l10n.translate('paid'),
        l10n.translate('report_due'),
      ],
      numeric: const {6, 7, 8},
      flex: const {4: 2, 5: 2},
      emptyText: l10n.translate('no_orders_in_scope'),
      rows: [
        for (final o in report.orders)
          _Row(
            [
              '#${o.code}',
              _clock(o.createdAt),
              o.type,
              orNothing(o.tableName),
              orNothing(o.waiterName),
              o.paymentMethods,
              money.format(o.total),
              money.format(o.paid),
              o.isCancelled || o.due <= 0.005 ? '' : money.format(o.due),
            ],
            strike: o.isCancelled,
            muted: o.isCancelled,
          ),
        if (report.orders.isNotEmpty) ...[
          if (report.cancelledCount > 0)
            _Row(
              [
                l10n.translate('cancelled'),
                '${report.cancelledCount}',
                '', '', '', '',
                money.format(report.cancelledTotal),
                '', '',
              ],
              kind: _RowKind.subtotal,
            ),
          _Row(
            [
              l10n.translate('total'),
              '${report.count}',
              '', '', '', '',
              money.format(report.total),
              money.format(report.paid),
              report.unpaid > 0.005 ? money.format(report.unpaid) : '',
            ],
            kind: _RowKind.total,
          ),
        ],
      ],
    );
  }
}

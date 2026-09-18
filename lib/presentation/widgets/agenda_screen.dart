import 'dart:math';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/database/app_database.dart';
import '../../domain/models/booking_models.dart';
import '../../providers/booking_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/booking_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/customer_display.dart';

// ═══════════════════════════════════════════════════════════════════════════
// View mode
// ═══════════════════════════════════════════════════════════════════════════

enum _ViewMode { waiterGrid, orderTimeline, list }

// ═══════════════════════════════════════════════════════════════════════════
// Data model
// ═══════════════════════════════════════════════════════════════════════════

class AgendaEntry {
  /// This device's `order_products.id`, or null for a booking pulled from the
  /// diary whose order this terminal has never held.
  final int? orderProductId;

  /// The server's `order_products.id` — the only id `PATCH`/`DELETE
  /// /order-products/{id}/schedule` understands. Null until the order has been
  /// synced, which is exactly when booking must refuse to act.
  final int? serverOrderProductId;

  final int orderId;
  final String orderCode;
  final String productName;
  final String? customerName;
  final String? customerPhone;
  final String? note;
  final DateTime start;
  final DateTime end;
  final int? waiterId;
  final String? waiterName;
  final int? resourceId;
  final String? resourceName;
  /// Kitchen line state. Display only — never a booking decision. Scheduling
  /// status comes from the plan times alone, and the server already excludes
  /// canceled orders, so everything that arrives here is live.
  final String state;

  /// Net line value (no TVA): money expected on this booking.
  final double? value;

  final Color color;

  const AgendaEntry({
    required this.orderProductId,
    this.serverOrderProductId,
    required this.orderId,
    required this.orderCode,
    required this.productName,
    this.customerName,
    this.customerPhone,
    this.note,
    required this.start,
    required this.end,
    this.waiterId,
    this.waiterName,
    this.resourceId,
    this.resourceName,
    required this.state,
    this.value,
    required this.color,
  });

  Duration get duration => end.difference(start);

  /// Where this booking sits relative to [now]. Derived, never stored — see
  /// [bookingTimeStatus].
  BookingTimeStatus timeStatus({DateTime? now}) =>
      bookingTimeStatus(start, end, now: now);

  bool get isCancelled => state == 'CANCELED';

  /// Whether this booking can be rescheduled or freed from here. A row that
  /// only exists in the pulled diary still can — the server id is what the
  /// schedule endpoints address.
  bool get isActionable => serverOrderProductId != null && !isCancelled;
}

// ═══════════════════════════════════════════════════════════════════════════
// Providers
// ═══════════════════════════════════════════════════════════════════════════

final agendaEntriesProvider =
    FutureProvider.family<List<AgendaEntry>, DateTime>((ref, date) async {
  final db = ref.watch(databaseProvider);
  final dayStart = DateTime(date.year, date.month, date.day);
  final dayEnd = dayStart.add(const Duration(days: 1));

  // Overlap, matching the endpoint: an appointment that started at 23:30
  // yesterday and runs past midnight is occupying a chair today, and a
  // start-in-day filter would leave it off the grid it is sitting on.
  final rows = await (db.select(db.orderProducts)
        ..where((t) =>
            t.planStartAt.isNotNull() &
            t.planEndAt.isNotNull() &
            t.planStartAt.isSmallerThanValue(dayEnd) &
            t.planEndAt.isBiggerThanValue(dayStart)))
      .get();
  final ops =
      rows.where((op) => op.planStartAt != null && op.planEndAt != null).toList();
  if (ops.isEmpty) return const [];

  // Batch-load every referenced entity in one query each (no per-entry N+1).
  final productIds = ops.map((o) => o.productId).toSet().toList();
  final orderIds = ops.map((o) => o.orderId).toSet().toList();
  final waiterIds =
      ops.map((o) => o.planWaiterId).whereType<int>().toSet().toList();
  final resourceIds =
      ops.map((o) => o.planResourceId).whereType<int>().toSet().toList();

  final products = {
    for (final p in await (db.select(db.products)
          ..where((t) => t.id.isIn(productIds)))
        .get())
      p.id: p
  };
  final orders = {
    for (final o
        in await (db.select(db.orders)..where((t) => t.id.isIn(orderIds))).get())
      o.id: o
  };
  final clientIds =
      orders.values.map((o) => o.clientId).whereType<int>().toSet().toList();
  final customers = clientIds.isEmpty
      ? const <int, Customer>{}
      : {
          for (final c in await (db.select(db.customers)
                ..where((t) => t.id.isIn(clientIds)))
              .get())
            c.id: c
        };
  final waiters = waiterIds.isEmpty
      ? const <int, Waiter>{}
      : {
          for (final w in await (db.select(db.waiters)
                ..where((t) => t.id.isIn(waiterIds)))
              .get())
            w.id: w
        };
  final resources = resourceIds.isEmpty
      ? const <int, Resource>{}
      : {
          for (final r in await (db.select(db.resources)
                ..where((t) => t.id.isIn(resourceIds)))
              .get())
            r.id: r
        };

  // Bookable staff first, waiters as the fallback: `planWaiterId` is a
  // provider employee id, and a shop that has migrated to providers may have
  // no waiter row with that id at all.
  final serviceProviders = {
    for (final sp in await db.select(db.providers).get()) sp.id: sp
  };

  final entries = <AgendaEntry>[];
  for (final op in ops) {
    final order = orders[op.orderId];
    final product = products[op.productId];
    final customer =
        order?.clientId != null ? customers[order!.clientId!] : null;
    final waiter = op.planWaiterId != null ? waiters[op.planWaiterId!] : null;
    final resource =
        op.planResourceId != null ? resources[op.planResourceId!] : null;

    final sp = op.planWaiterId != null ? serviceProviders[op.planWaiterId!] : null;
    final staffName = sp != null
        ? '${sp.firstName} ${sp.lastName ?? ''}'.trim()
        : (waiter == null
            ? null
            : '${waiter.firstName} ${waiter.lastName ?? ''}'.trim());

    entries.add(AgendaEntry(
      orderProductId: op.id,
      serverOrderProductId: op.serverId,
      orderId: op.orderId,
      orderCode: order?.code ?? '#${op.orderId}',
      productName: product?.name ?? 'Product #${op.productId}',
      customerName: customer?.displayLabel,
      customerPhone: customer?.phone,
      note: op.note,
      start: op.planStartAt!,
      end: op.planEndAt!,
      waiterId: op.planWaiterId,
      waiterName: staffName,
      resourceId: op.planResourceId,
      resourceName: resource?.name,
      state: op.state,
      color: _entryColor(
          bookingTimeStatus(op.planStartAt!, op.planEndAt!)),
    ));
  }

  // Fold in the pulled diary. A booking can belong to an order this terminal
  // never held — another till's sale, or one taken on the web — and it still
  // occupies a chair here. Local rows win where both exist: they carry this
  // device's ids and any edit made since the last pull.
  final localServerIds = entries
      .map((e) => e.serverOrderProductId)
      .whereType<int>()
      .toSet();

  final cached = await (db.select(db.agendaBookings)
        ..where((t) =>
            t.planStartAt.isSmallerThanValue(dayEnd) &
            t.planEndAt.isBiggerThanValue(dayStart)))
      .get();

  for (final b in cached) {
    if (localServerIds.contains(b.orderProductId)) continue;
    final sp = b.planWaiterId != null ? serviceProviders[b.planWaiterId!] : null;
    entries.add(AgendaEntry(
      orderProductId: null,
      serverOrderProductId: b.orderProductId,
      orderId: b.orderId ?? -1,
      orderCode: b.orderCode ?? '#${b.orderId ?? '?'}',
      productName: b.productName ?? 'Product #${b.productId ?? '?'}',
      customerName: b.customerName,
      customerPhone: b.customerPhone,
      note: b.note,
      start: b.planStartAt,
      end: b.planEndAt,
      waiterId: b.planWaiterId,
      waiterName: b.planWaiterName ??
          (sp == null ? null : '${sp.firstName} ${sp.lastName ?? ''}'.trim()),
      resourceId: b.planResourceId,
      resourceName: b.planResourceName,
      state: b.state,
      value: b.value,
      color: _entryColor(bookingTimeStatus(b.planStartAt, b.planEndAt)),
    ));
  }

  entries.sort((a, b) => a.start.compareTo(b.start));
  return entries;
});

/// The colour a booking is drawn in — from the clock, and nothing else.
///
/// There is deliberately no booking-status axis to blend in: the line's
/// kitchen state answers a different question, and a canceled order's lines
/// never reach the agenda at all because cancelling frees the slot server-side.
/// So the only thing worth colouring is when the appointment sits.
Color _entryColor(BookingTimeStatus status) {
  switch (status) {
    case BookingTimeStatus.notYet:
      return const Color(0xFF1E88E5); // upcoming
    case BookingTimeStatus.inProgress:
      return const Color(0xFFFB8C00); // in the chair now
    case BookingTimeStatus.done:
      return const Color(0xFF43A047); // finished
  }
}

/// Colour for the line's own state chip (COMPLETED / PREPARING / CANCELED).
/// Distinct from [_entryColor], which answers "when", not "what stage".
Color _lineStateColor(String state) {
  switch (state) {
    case 'COMPLETED':
      return const Color(0xFF43A047);
    case 'PREPARING':
      return const Color(0xFFFB8C00);
    case 'CANCELED':
      return const Color(0xFFE53935);
    default:
      return const Color(0xFF1E88E5);
  }
}

String timeStatusLabel(BookingTimeStatus status, AppLocalizations l10n) {
  switch (status) {
    case BookingTimeStatus.notYet:
      return l10n.translate('booking_not_yet');
    case BookingTimeStatus.inProgress:
      return l10n.translate('booking_in_progress');
    case BookingTimeStatus.done:
      return l10n.translate('booking_done');
  }
}

Color _waiterColor(int? id) {
  if (id == null) return const Color(0xFF9E9E9E);
  const palette = [
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF66BB6A),
    Color(0xFFFFA726),
    Color(0xFF29B6F6),
    Color(0xFFEC407A),
  ];
  return palette[id % palette.length];
}

String _waiterInitials(String? name) {
  if (name == null || name.isEmpty) return '?';
  final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

final allWaitersProvider = FutureProvider<List<Waiter>>((ref) async {
  final db = ref.watch(databaseProvider);
  return db.select(db.waiters).get();
});

// ═══════════════════════════════════════════════════════════════════════════
// Connector painter
// ═══════════════════════════════════════════════════════════════════════════

class _ConnLine {
  final Offset from;
  final Offset fromCp;
  final Offset toCp;
  final Offset to;
  final Color color;

  const _ConnLine({
    required this.from,
    required this.fromCp,
    required this.toCp,
    required this.to,
    required this.color,
  });
}

class _ConnectorPainter extends CustomPainter {
  final List<_ConnLine> lines;
  _ConnectorPainter(this.lines);

  @override
  void paint(Canvas canvas, Size size) {
    for (final line in lines) {
      final paint = Paint()
        ..color = line.color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path()
        ..moveTo(line.from.dx, line.from.dy)
        ..cubicTo(
          line.fromCp.dx, line.fromCp.dy,
          line.toCp.dx, line.toCp.dy,
          line.to.dx, line.to.dy,
        );
      canvas.drawPath(path, paint);

      final dir = (line.to - line.toCp).direction;
      const aSize = 7.0;
      final p1 = line.to - Offset.fromDirection(dir - 0.42, aSize);
      final p2 = line.to - Offset.fromDirection(dir + 0.42, aSize);
      canvas.drawLine(line.to, p1, paint..strokeWidth = 1.5);
      canvas.drawLine(line.to, p2, paint);
    }
  }

  @override
  bool shouldRepaint(_ConnectorPainter old) => old.lines != lines;
}

// ═══════════════════════════════════════════════════════════════════════════
// Agenda Screen
// ═══════════════════════════════════════════════════════════════════════════

class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  DateTime _selectedDate = DateTime.now();
  _ViewMode _viewMode = _ViewMode.waiterGrid;

  static const int _startHour = 7;
  static const int _endHour = 23;
  static const double _hourHeight = 80.0;
  static const double _headerHeight = 72.0;
  static const double _timeColWidth = 60.0;
  static const double _colWidth = 220.0;

  static const double _ganttLabelWidth = 170.0;
  static const double _ganttRowHeight = 76.0;
  static const double _ganttHeaderHeight = 44.0;
  static const double _ganttHourWidth = 90.0;

  final ScrollController _vScrollCtrl = ScrollController();
  final ScrollController _hScrollCtrl = ScrollController();
  final ScrollController _ganttVScrollCtrl = ScrollController();
  final ScrollController _ganttHScrollCtrl = ScrollController();
  bool _scrolledToNow = false;

  final GlobalKey _timelineKey = GlobalKey();
  List<int?> _waiterIds = [];
  double _cachedColWidth = _colWidth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncDay());
  }

  /// Pull the day's diary, then repaint from the cache. Silent on failure —
  /// offline the screen keeps showing the last pull, which beats a blank grid.
  Future<void> _syncDay() async {
    final ok = await _pullAgenda();
    if (ok && mounted) ref.invalidate(agendaEntriesProvider(_selectedDate));
  }

  @override
  void dispose() {
    _vScrollCtrl.dispose();
    _hScrollCtrl.dispose();
    _ganttVScrollCtrl.dispose();
    _ganttHScrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToCurrentHour() {
    if (_vScrollCtrl.hasClients && !_scrolledToNow) {
      final offset =
          ((TimeOfDay.now().hour - _startHour).clamp(0, _endHour - _startHour))
                  .toDouble() *
              _hourHeight;
      _vScrollCtrl.animateTo(offset,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic);
      _scrolledToNow = true;
    }
  }

  void _previousDay() {
    final previous = _selectedDate;
    setState(() {
      _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      _scrolledToNow = false;
    });
    _syncWeekIfChanged(previous);
  }

  void _nextDay() {
    final previous = _selectedDate;
    setState(() {
      _selectedDate = _selectedDate.add(const Duration(days: 1));
      _scrolledToNow = false;
    });
    _syncWeekIfChanged(previous);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Root build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final entriesAsync = ref.watch(agendaEntriesProvider(_selectedDate));
    final waitersAsync = ref.watch(allWaitersProvider);
    final timeStep = ref.watch(settingsProvider).agendaTimeStep;
    final canBook = ref.watch(canBookProvider);
    // Repaints once a minute so blocks change colour as bookings start and
    // finish — the time status is derived from the clock, so without this the
    // grid would keep showing 9am as "upcoming" all afternoon.
    ref.watch(clockTickProvider);

    entriesAsync.whenData((_) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToCurrentHour());
    });

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 1,
        title: Text(l10n.translate('agenda')),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _viewToggleBtn(
                  icon: Icons.view_column_outlined,
                  mode: _ViewMode.waiterGrid,
                  tooltip: 'By Waiter',
                  theme: theme,
                ),
                _viewToggleBtn(
                  icon: Icons.view_timeline_outlined,
                  mode: _ViewMode.orderTimeline,
                  tooltip: 'By Order',
                  theme: theme,
                ),
                _viewToggleBtn(
                  icon: Icons.list_alt_outlined,
                  mode: _ViewMode.list,
                  tooltip: 'List',
                  theme: theme,
                ),
              ],
            ),
          ),
          PopupMenuButton<int>(
            icon: Icon(Icons.tune_outlined,
                size: 20,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65)),
            tooltip: 'Time step',
            initialValue: timeStep,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (m) =>
                ref.read(settingsProvider.notifier).setAgendaTimeStep(m),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 60, child: Text('1 Hour')),
              PopupMenuItem(value: 30, child: Text('30 Minutes')),
              PopupMenuItem(value: 15, child: Text('15 Minutes')),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // Says the diary on screen may be behind, without hiding it. A shop
          // mid-outage still needs to know who is coming at 3pm.
          if (!canBook)
            Container(
              width: double.infinity,
              color: theme.colorScheme.secondaryContainer,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded,
                      size: 18,
                      color: theme.colorScheme.onSecondaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      l10n.translate('agenda_offline_cached'),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _buildDateHeader(context, theme),
          _buildWeekSummary(theme, l10n),
          Expanded(
            child: entriesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (entries) => waitersAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) =>
                    _buildContent(context, entries, [], timeStep, theme),
                data: (waiters) =>
                    _buildContent(context, entries, waiters, timeStep, theme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Bookings and money on the books for the week on screen.
  ///
  /// Labelled *reserved*, and kept away from any takings figure, because it is
  /// a forecast: a service becomes revenue on the day it is performed, not the
  /// day it was booked or the day a deposit landed. Only shown when the server
  /// has actually summarised the week — an invented total is worse than none.
  Widget _buildWeekSummary(ThemeData theme, AppLocalizations l10n) {
    final monday = weekOf(_selectedDate).start;
    final summary = ref.watch(agendaWeekSummaryProvider)[monday];
    if (summary == null || summary.count == 0) return const SizedBox.shrink();

    final formatter = ref.watch(currencyFormatterProvider);
    final today = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day);
    final day = summary.days
        .where((d) => DateTime(d.date.year, d.date.month, d.date.day) == today)
        .firstOrNull;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.event_note_outlined,
              size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            '${day?.count ?? 0} ${l10n.translate('today')}'
            '  ·  ${summary.count} ${l10n.translate('this_week')}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Text(
            '${l10n.translate('reserved_value')}: '
            '${formatter.format(summary.reservedValue)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, List<AgendaEntry> entries,
      List<Waiter> waiters, int timeStep, ThemeData theme) {
    switch (_viewMode) {
      case _ViewMode.waiterGrid:
        return _buildWaiterGrid(context, entries, waiters, timeStep);
      case _ViewMode.orderTimeline:
        return _buildOrderTimeline(context, entries);
      case _ViewMode.list:
        return _buildListView(context, entries, theme);
    }
  }

  Widget _viewToggleBtn({
    required IconData icon,
    required _ViewMode mode,
    required String tooltip,
    required ThemeData theme,
  }) {
    final active = _viewMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => setState(() => _viewMode = mode),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: active ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Date header — Planify-style with week strip
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildDateHeader(BuildContext context, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surface
            : theme.colorScheme.surfaceContainerLow,
        border: Border(
            bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.4))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _previousDay,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Previous day',
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(context),
                    child: Column(
                      children: [
                        Text(
                          DateFormat('MMMM yyyy').format(_selectedDate),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.5),
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          DateFormat('EEEE, d').format(_selectedDate),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _nextDay,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Next day',
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selectedDate = DateTime.now();
                    _scrolledToNow = false;
                  }),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Today'),
                ),
              ],
            ),
          ),
          _buildWeekStrip(theme),
        ],
      ),
    );
  }

  Widget _buildWeekStrip(ThemeData theme) {
    final today = DateTime.now();
    final weekday = _selectedDate.weekday;
    final weekStart = _selectedDate.subtract(Duration(days: weekday - 1));
    const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
      child: Row(
        children: List.generate(7, (i) {
          final day = weekStart.add(Duration(days: i));
          final isSelected = _isSameDay(day, _selectedDate);
          final isToday = _isSameDay(day, today);
          final isWeekend = i >= 5;

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedDate = day;
                _scrolledToNow = false;
              }),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dayLetters[i],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
                            : isWeekend
                                ? theme.colorScheme.onSurface
                                    .withValues(alpha: 0.3)
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.45),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: isToday && !isSelected
                          ? BoxDecoration(
                              border: Border.all(
                                  color: theme.colorScheme.primary, width: 1.5),
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Text(
                        '${day.day}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: (isSelected || isToday)
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? theme.colorScheme.onPrimary
                              : isToday
                                  ? theme.colorScheme.primary
                                  : isWeekend
                                      ? theme.colorScheme.onSurface
                                          .withValues(alpha: 0.4)
                                      : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _scrolledToNow = false;
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIST VIEW
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildListView(
      BuildContext context, List<AgendaEntry> entries, ThemeData theme) {
    if (entries.isEmpty) return _buildEmptyState(context, theme);

    final Map<int, List<AgendaEntry>> byHour = {};
    for (final e in entries) {
      byHour.putIfAbsent(e.start.hour, () => []).add(e);
    }
    final hours = byHour.keys.toList()..sort();

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: hours.length,
      itemBuilder: (ctx, i) {
        final hour = hours[i];
        final hourEntries = byHour[hour]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: 8, top: i == 0 ? 0 : 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${hour.toString().padLeft(2, '0')}:00',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Divider(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            ...hourEntries
                .map((e) => _buildListCard(context, e, theme)),
          ],
        );
      },
    );
  }

  Widget _buildListCard(
      BuildContext context, AgendaEntry e, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: () => _showEntryDetail(context, e),
      onLongPress: () => _editEntryTime(context, e),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: e.color.withValues(alpha: isDark ? 0.18 : 0.09),
          borderRadius: BorderRadius.circular(12),
          border: Border(left: BorderSide(color: e.color, width: 4)),
          boxShadow: [
            BoxShadow(
              color: e.color.withValues(alpha: 0.07),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 44,
                child: Column(
                  children: [
                    Text(
                      DateFormat.Hm().format(e.start),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: e.color),
                    ),
                    Container(
                      width: 1,
                      height: 12,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: e.color.withValues(alpha: 0.4),
                    ),
                    Text(
                      DateFormat.Hm().format(e.end),
                      style: TextStyle(
                          fontSize: 10.5,
                          color: e.color.withValues(alpha: 0.65)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.productName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: isDark
                            ? e.color.lighten(0.1)
                            : e.color.darken(0.15),
                      ),
                    ),
                    if (e.customerName != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(Icons.person_outline,
                              size: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.45)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(e.customerName!,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(fontSize: 11.5),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                    if (e.waiterName != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.badge_outlined,
                              size: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.45)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(e.waiterName!,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(fontSize: 11.5),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                    ],
                    if (e.note != null && e.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        e.note!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.5),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _stateChipSmall(e.state),
                  const SizedBox(height: 6),
                  Text(
                    _formatDuration(e.duration),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.event_note_outlined,
              size: 40,
              color: theme.colorScheme.primary.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No bookings',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            DateFormat('EEEE, MMMM d').format(_selectedDate),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.chevron_right, size: 16),
            label: const Text('Next day'),
            onPressed: _nextDay,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
              side: BorderSide(
                  color: theme.colorScheme.primary.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stateChipSmall(String state) {
    final color = _lineStateColor(state);
    final label = switch (state) {
      'COMPLETED' => 'Done',
      'PREPARING' => 'Prep',
      'CANCELED' => 'Cxld',
      _ => 'Plan',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WAITER GRID VIEW
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWaiterGrid(BuildContext context, List<AgendaEntry> entries,
      List<Waiter> allWaiters, int timeStep) {
    final Map<int?, String> waiterLabels = {null: 'Unassigned'};
    for (final w in allWaiters) {
      waiterLabels[w.id] = '${w.firstName} ${w.lastName ?? ''}'.trim();
    }
    for (final e in entries) {
      if (e.waiterId != null && !waiterLabels.containsKey(e.waiterId)) {
        waiterLabels[e.waiterId] = e.waiterName ?? 'Waiter ${e.waiterId}';
      }
    }

    final waiterIds = waiterLabels.keys.toList()
      ..sort((a, b) {
        if (a == null) return -1;
        if (b == null) return 1;
        return a.compareTo(b);
      });

    final Map<int?, List<AgendaEntry>> byWaiter = {
      for (final id in waiterIds) id: []
    };
    for (final e in entries) {
      byWaiter[e.waiterId]!.add(e);
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final totalHours = _endHour - _startHour;
    final double totalHeight = totalHours * _hourHeight;
    final double availableWidth =
        MediaQuery.of(context).size.width - _timeColWidth;
    final double colWidth = waiterIds.length <= 1
        ? availableWidth
        : max(_colWidth, availableWidth / waiterIds.length);
    final double totalTimelineWidth =
        _timeColWidth + colWidth * waiterIds.length;

    _waiterIds = waiterIds;
    _cachedColWidth = colWidth;

    final connLines =
        _computeWaiterConnectors(byWaiter, waiterIds, colWidth);

    return Scrollbar(
      controller: _vScrollCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _vScrollCtrl,
        child: SizedBox(
          width: double.infinity,
          child: Scrollbar(
            controller: _hScrollCtrl,
            thumbVisibility: true,
            notificationPredicate: (n) => n.depth == 1,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              controller: _hScrollCtrl,
              child: SizedBox(
                width: totalTimelineWidth,
                child: Column(
                  children: [
                    // Avatar column headers
                    SizedBox(
                      height: _headerHeight,
                      child: Row(
                        children: [
                          SizedBox(
                            width: _timeColWidth,
                            child: Container(
                              color: isDark
                                  ? theme.colorScheme.surfaceContainerLow
                                  : theme.colorScheme.surfaceContainerHighest,
                            ),
                          ),
                          ...waiterIds.map((wId) => _buildWaiterHeader(
                              wId,
                              waiterLabels[wId],
                              byWaiter[wId]?.length ?? 0,
                              colWidth,
                              theme,
                              isDark)),
                        ],
                      ),
                    ),
                    // Timeline
                    DragTarget<AgendaEntry>(
                      onAcceptWithDetails: (details) =>
                          _onEntryDropped(details, timeStep),
                      builder: (context, candidates, rejected) {
                        return SizedBox(
                          key: _timelineKey,
                          height: totalHeight,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _buildHourGrid(context, totalHours,
                                  colWidth * waiterIds.length, timeStep),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _ConnectorPainter(connLines),
                                ),
                              ),
                              if (candidates.isNotEmpty)
                                Positioned.fill(
                                  child: Container(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: 0.04),
                                  ),
                                ),
                              ...waiterIds.asMap().entries.expand((colEntry) {
                                final colIdx = colEntry.key;
                                final wId = colEntry.value;
                                return (byWaiter[wId] ?? []).map((e) =>
                                    _buildEntryBlock(
                                        context, e, colIdx, colWidth, theme));
                              }),
                              _buildCurrentTimeLine(
                                  context, colWidth * waiterIds.length),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWaiterHeader(int? wId, String? label, int count,
      double colWidth, ThemeData theme, bool isDark) {
    final name = label ?? 'Waiter $wId';
    final initials = _waiterInitials(name);
    final color = _waiterColor(wId);

    return Container(
      width: colWidth,
      height: _headerHeight,
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerLow
            : theme.colorScheme.surfaceContainerHighest,
        border: Border(
          left: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              shape: BoxShape.circle,
              border: Border.all(
                  color: color.withValues(alpha: 0.35), width: 1.5),
            ),
            alignment: Alignment.center,
            child: wId == null
                ? Icon(Icons.person_off_outlined, size: 15, color: color)
                : Text(
                    initials,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              name,
              style: theme.textTheme.labelSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (count > 0)
            Container(
              margin: const EdgeInsets.only(top: 3),
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count booking${count > 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<_ConnLine> _computeWaiterConnectors(
    Map<int?, List<AgendaEntry>> byWaiter,
    List<int?> waiterIds,
    double colWidth,
  ) {
    final Map<
        int,
        List<({
          int colIdx,
          double top,
          double height,
          Color color,
          DateTime start
        })>> groups = {};

    for (int colIdx = 0; colIdx < waiterIds.length; colIdx++) {
      final wId = waiterIds[colIdx];
      for (final e in byWaiter[wId] ?? []) {
        final top = _entryTopOffset(e.start);
        final height = max(28.0, _hourHeight * e.duration.inMinutes / 60.0);
        groups.putIfAbsent(e.orderId, () => []).add((
          colIdx: colIdx,
          top: top,
          height: height,
          color: e.color,
          start: e.start,
        ));
      }
    }

    final lines = <_ConnLine>[];
    for (final group in groups.values) {
      if (group.length < 2) continue;
      final sorted = [...group]..sort((a, b) => a.start.compareTo(b.start));

      for (int i = 0; i < sorted.length - 1; i++) {
        final a = sorted[i];
        final b = sorted[i + 1];
        final Offset from, fromCp, toCp, to;

        if (a.colIdx == b.colIdx) {
          final aBottom = a.top + a.height;
          final bTop = b.top;
          final centerX =
              _timeColWidth + a.colIdx * colWidth + colWidth / 2;
          final dy = (bTop - aBottom) * 0.45;
          from = Offset(centerX, aBottom);
          to = Offset(centerX, bTop);
          fromCp = Offset(centerX, aBottom + dy);
          toCp = Offset(centerX, bTop - dy);
        } else {
          final aRight =
              _timeColWidth + a.colIdx * colWidth + colWidth - 6;
          final bLeft = _timeColWidth + b.colIdx * colWidth + 6;
          final aCenterY = a.top + a.height / 2;
          final bCenterY = b.top + b.height / 2;
          final dx = ((bLeft - aRight) * 0.5).abs();
          from = Offset(aRight, aCenterY);
          to = Offset(bLeft, bCenterY);
          fromCp = Offset(aRight + dx, aCenterY);
          toCp = Offset(bLeft - dx, bCenterY);
        }

        lines.add(_ConnLine(
          from: from,
          fromCp: fromCp,
          toCp: toCp,
          to: to,
          color: a.color.withValues(alpha: 0.55),
        ));
      }
    }
    return lines;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ORDER TIMELINE (GANTT) VIEW
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOrderTimeline(
      BuildContext context, List<AgendaEntry> entries) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (entries.isEmpty) return _buildEmptyState(context, theme);

    final Map<int, List<AgendaEntry>> byOrder = {};
    for (final e in entries) {
      byOrder.putIfAbsent(e.orderId, () => []).add(e);
    }

    final orderIds = byOrder.keys.toList()
      ..sort((a, b) {
        final aMin = byOrder[a]!
            .map((e) => e.start)
            .reduce((v, e) => v.isBefore(e) ? v : e);
        final bMin = byOrder[b]!
            .map((e) => e.start)
            .reduce((v, e) => v.isBefore(e) ? v : e);
        return aMin.compareTo(bMin);
      });

    final totalHours = _endHour - _startHour;
    final double totalTimeWidth = totalHours * _ganttHourWidth;
    final double totalWidth = _ganttLabelWidth + totalTimeWidth;
    final double blockHeight = _ganttRowHeight - 20;
    final double totalHeight =
        _ganttHeaderHeight + orderIds.length * _ganttRowHeight;

    final connLines = <_ConnLine>[];
    for (int ri = 0; ri < orderIds.length; ri++) {
      final oes = [...byOrder[orderIds[ri]]!]
        ..sort((a, b) => a.start.compareTo(b.start));
      final rowCenterY =
          _ganttHeaderHeight + ri * _ganttRowHeight + _ganttRowHeight / 2;

      for (int bi = 0; bi < oes.length - 1; bi++) {
        final a = oes[bi];
        final b = oes[bi + 1];
        final aEndMin = (a.end.hour - _startHour) * 60 + a.end.minute;
        final bStartMin = (b.start.hour - _startHour) * 60 + b.start.minute;
        final aRight =
            _ganttLabelWidth + aEndMin / 60.0 * _ganttHourWidth - 2;
        final bLeft =
            _ganttLabelWidth + bStartMin / 60.0 * _ganttHourWidth + 2;
        final midX = (aRight + bLeft) / 2;

        connLines.add(_ConnLine(
          from: Offset(aRight, rowCenterY),
          fromCp: Offset(midX, rowCenterY),
          toCp: Offset(midX, rowCenterY),
          to: Offset(bLeft, rowCenterY),
          color: a.color.withValues(alpha: 0.7),
        ));
      }
    }

    return Scrollbar(
      controller: _ganttVScrollCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _ganttVScrollCtrl,
        child: Scrollbar(
          controller: _ganttHScrollCtrl,
          thumbVisibility: true,
          notificationPredicate: (n) => n.depth == 1,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            controller: _ganttHScrollCtrl,
            child: SizedBox(
              width: totalWidth,
              height: totalHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        Container(
                          height: _ganttHeaderHeight,
                          decoration: BoxDecoration(
                            color: isDark
                                ? theme.colorScheme.surfaceContainerLow
                                : theme.colorScheme.surfaceContainerHighest,
                            border: Border(
                                bottom: BorderSide(
                                    color: theme.dividerColor, width: 1)),
                          ),
                        ),
                        ...orderIds.asMap().entries.map((e) => Container(
                              height: _ganttRowHeight,
                              decoration: BoxDecoration(
                                color: e.key.isEven
                                    ? Colors.transparent
                                    : theme.colorScheme.surfaceContainerLowest
                                        .withValues(alpha: 0.4),
                                border: Border(
                                    bottom: BorderSide(
                                        color: theme.dividerColor
                                            .withValues(alpha: 0.25))),
                              ),
                            )),
                      ],
                    ),
                  ),
                  ...List.generate(totalHours + 1, (i) {
                    final x = _ganttLabelWidth + i * _ganttHourWidth;
                    return Positioned(
                      left: x,
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: i == 0 ? 1.0 : 0.5,
                        color: theme.dividerColor
                            .withValues(alpha: i == 0 ? 0.7 : 0.18),
                      ),
                    );
                  }),
                  Positioned(
                    top: 0,
                    left: _ganttLabelWidth,
                    width: totalTimeWidth,
                    height: _ganttHeaderHeight,
                    child: Row(
                      children: List.generate(totalHours, (i) {
                        final hour = _startHour + i;
                        return SizedBox(
                          width: _ganttHourWidth,
                          child: Center(
                            child: Text(
                              '${hour.toString().padLeft(2, '0')}:00',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  Positioned(
                    top: _ganttHeaderHeight,
                    left: 0,
                    width: _ganttLabelWidth,
                    height: orderIds.length * _ganttRowHeight,
                    child: Column(
                      children: orderIds.asMap().entries.map((e) {
                        final ri = e.key;
                        final oId = e.value;
                        final oes = byOrder[oId]!;
                        final first = oes.first;
                        return Container(
                          height: _ganttRowHeight,
                          decoration: BoxDecoration(
                            color: ri.isEven
                                ? Colors.transparent
                                : theme.colorScheme.surfaceContainerLowest
                                    .withValues(alpha: 0.4),
                            border: Border(
                              right: BorderSide(
                                  color: theme.dividerColor, width: 1),
                              bottom: BorderSide(
                                  color: theme.dividerColor
                                      .withValues(alpha: 0.25)),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 4,
                                    height: 16,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: first.color,
                                      borderRadius:
                                          BorderRadius.circular(2),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      first.orderCode,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: first.color
                                          .withValues(alpha: 0.12),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${oes.length}',
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              color: first.color,
                                              fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              if (first.customerName != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 3),
                                  child: Row(
                                    children: [
                                      Icon(Icons.person_outline,
                                          size: 11,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.4)),
                                      const SizedBox(width: 3),
                                      Expanded(
                                        child: Text(
                                          first.customerName!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  fontSize: 10,
                                                  color: theme.colorScheme
                                                      .onSurface
                                                      .withValues(alpha: 0.5)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                        painter: _ConnectorPainter(connLines)),
                  ),
                  ...orderIds.asMap().entries.expand((entry) {
                    final ri = entry.key;
                    final oId = entry.value;
                    return byOrder[oId]!.map((e) =>
                        _buildGanttBlock(context, e, ri, blockHeight, theme));
                  }),
                  _buildGanttCurrentTimeLine(context, totalHeight),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGanttBlock(BuildContext context, AgendaEntry e, int rowIndex,
      double blockHeight, ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    final startMin = (e.start.hour - _startHour) * 60 + e.start.minute;
    final width =
        max(44.0, e.duration.inMinutes / 60.0 * _ganttHourWidth);
    final left = _ganttLabelWidth + startMin / 60.0 * _ganttHourWidth;
    final top = _ganttHeaderHeight +
        rowIndex * _ganttRowHeight +
        (_ganttRowHeight - blockHeight) / 2;

    return Positioned(
      left: left,
      top: top,
      width: width,
      height: blockHeight,
      child: GestureDetector(
        onTap: () => _showEntryDetail(context, e),
        onLongPress: () => _editEntryTime(context, e),
        child: Container(
          decoration: BoxDecoration(
            color: e.color.withValues(alpha: isDark ? 0.24 : 0.11),
            borderRadius: BorderRadius.circular(7),
            border: Border(left: BorderSide(color: e.color, width: 4)),
            boxShadow: [
              BoxShadow(
                color: e.color.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          padding:
              const EdgeInsets.only(left: 6, right: 4, top: 3, bottom: 3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.productName,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? e.color.lighten(0.1)
                      : e.color.darken(0.15),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (blockHeight > 26)
                Text(
                  '${DateFormat.Hm().format(e.start)}–${DateFormat.Hm().format(e.end)}',
                  style: TextStyle(
                    fontSize: 9,
                    color: isDark
                        ? e.color.withValues(alpha: 0.7)
                        : e.color.darken(0.1).withValues(alpha: 0.65),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGanttCurrentTimeLine(
      BuildContext context, double totalHeight) {
    final now = DateTime.now();
    if (now.hour < _startHour ||
        now.hour >= _endHour ||
        !_isSameDay(now, _selectedDate)) {
      return const SizedBox.shrink();
    }
    final minFromStart = (now.hour - _startHour) * 60 + now.minute;
    final x = _ganttLabelWidth + minFromStart / 60.0 * _ganttHourWidth;
    return Positioned(
      left: x,
      top: 0,
      height: totalHeight,
      child: Column(
        children: [
          SizedBox(
            height: _ganttHeaderHeight,
            child: Center(
              child: Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                    color: Colors.red, shape: BoxShape.circle),
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: 1.5,
              color: Colors.red.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HOUR GRID (waiter grid)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHourGrid(BuildContext context, int totalHours,
      double totalWidth, int timeStep) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final stepsPerHour = 60 ~/ timeStep;

    return Column(
      children: List.generate(totalHours, (i) {
        final hour = _startHour + i;
        return SizedBox(
          height: _hourHeight,
          child: Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _timeColWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 2, right: 10),
                      child: Text(
                        '${hour.toString().padLeft(2, '0')}:00',
                        textAlign: TextAlign.right,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: i == 0
                                ? theme.dividerColor.withValues(alpha: 0.5)
                                : theme.dividerColor.withValues(alpha: 0.22),
                          ),
                        ),
                        color: isDark
                            ? (i.isEven
                                ? Colors.transparent
                                : theme.colorScheme.surfaceContainerLowest
                                    .withValues(alpha: 0.18))
                            : (i.isEven
                                ? Colors.transparent
                                : theme.colorScheme.surfaceContainerLowest
                                    .withValues(alpha: 0.32)),
                      ),
                    ),
                  ),
                ],
              ),
              for (int s = 1; s < stepsPerHour; s++)
                Positioned(
                  top: _hourHeight * s / stepsPerHour,
                  left: _timeColWidth,
                  right: 0,
                  child: Container(
                    height: 0.5,
                    color: theme.dividerColor.withValues(alpha: 0.13),
                  ),
                ),
              if (timeStep <= 30)
                for (int s = 1; s < stepsPerHour; s++)
                  Positioned(
                    top: _hourHeight * s / stepsPerHour - 8,
                    left: 0,
                    width: _timeColWidth,
                    child: Text(
                      '${hour.toString().padLeft(2, '0')}:${(s * timeStep).toString().padLeft(2, '0')}',
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 9,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.22),
                      ),
                    ),
                  ),
            ],
          ),
        );
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ENTRY BLOCK (waiter grid)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildEntryBlock(BuildContext context, AgendaEntry e, int colIndex,
      double colWidth, ThemeData theme) {
    final topOffset = _entryTopOffset(e.start);
    final blockHeight = max(28.0, _hourHeight * e.duration.inMinutes / 60.0);
    final leftOffset = _timeColWidth + colIndex * colWidth + 3;

    return Positioned(
      top: topOffset,
      left: leftOffset,
      width: colWidth - 6,
      height: blockHeight,
      child: Draggable<AgendaEntry>(
        data: e,
        feedback: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(10),
          shadowColor: e.color.withValues(alpha: 0.4),
          child: SizedBox(
            width: colWidth - 6,
            height: blockHeight,
            child: _buildEntryContent(e, blockHeight, colWidth - 6, theme,
                dragging: true),
          ),
        ),
        childWhenDragging: Opacity(
          opacity: 0.2,
          child:
              _buildEntryContent(e, blockHeight, colWidth - 6, theme),
        ),
        child: GestureDetector(
          onTap: () => _showEntryDetail(context, e),
          onLongPress: () => _editEntryTime(context, e),
          child: _buildEntryContent(e, blockHeight, colWidth - 6, theme),
        ),
      ),
    );
  }

  // Planify-style: pastel bg + colored left border + readable text
  Widget _buildEntryContent(
      AgendaEntry e, double blockHeight, double width, ThemeData theme,
      {bool dragging = false}) {
    final isDark = theme.brightness == Brightness.dark;
    final bgAlpha = isDark
        ? (dragging ? 0.32 : 0.22)
        : (dragging ? 0.18 : 0.11);
    final textColor =
        isDark ? e.color.lighten(0.12) : e.color.darken(0.18);
    final subColor = e.color.withValues(alpha: isDark ? 0.72 : 0.65);

    return Container(
      decoration: BoxDecoration(
        color: e.color.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(9),
        border: Border(
          left: BorderSide(color: e.color, width: 4),
          top: BorderSide(
              color: e.color.withValues(alpha: 0.2), width: 0.5),
          right: BorderSide(
              color: e.color.withValues(alpha: 0.18), width: 0.5),
          bottom: BorderSide(
              color: e.color.withValues(alpha: 0.18), width: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: e.color.withValues(alpha: dragging ? 0.28 : 0.08),
            blurRadius: dragging ? 14 : 4,
            spreadRadius: dragging ? 1 : 0,
            offset: Offset(dragging ? 4 : 0, dragging ? 6 : 2),
          ),
        ],
      ),
      padding:
          const EdgeInsets.only(left: 7, right: 5, top: 5, bottom: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  e.productName,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                    color: textColor,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              _stateIndicator(e.state),
            ],
          ),
          if (blockHeight > 42 && e.customerName != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 10, color: subColor),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      e.customerName!,
                      style:
                          TextStyle(fontSize: 10, color: subColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          if (blockHeight > 58)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(Icons.schedule,
                      size: 10,
                      color: subColor.withValues(alpha: 0.7)),
                  const SizedBox(width: 3),
                  Text(
                    '${DateFormat.Hm().format(e.start)}–${DateFormat.Hm().format(e.end)}',
                    style: TextStyle(
                        fontSize: 9.5,
                        color: subColor.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
          if (blockHeight > 74 &&
              e.note != null &&
              e.note!.isNotEmpty)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  e.note!,
                  style: TextStyle(
                    fontSize: 9,
                    color: subColor.withValues(alpha: 0.55),
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stateIndicator(String state) {
    final color = _lineStateColor(state);
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  double _entryTopOffset(DateTime dt) {
    final minutesFromStart = (dt.hour - _startHour) * 60 + dt.minute;
    return minutesFromStart * _hourHeight / 60.0;
  }

  Widget _buildCurrentTimeLine(BuildContext context, double totalWidth) {
    final now = DateTime.now();
    if (now.hour < _startHour ||
        now.hour >= _endHour ||
        !_isSameDay(now, _selectedDate)) {
      return const SizedBox.shrink();
    }
    final top = _entryTopOffset(now);
    return Positioned(
      top: top,
      left: _timeColWidth,
      width: totalWidth,
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Colors.red.withValues(alpha: 0.4),
                    blurRadius: 6,
                    spreadRadius: 1),
              ],
            ),
          ),
          Expanded(
            child: Container(
              height: 1.5,
              color: Colors.red.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ─────────────────────────────────────────────────────────────────────────
  // DRAG & DROP
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onEntryDropped(
      DragTargetDetails<AgendaEntry> details, int timeStep) async {
    final entry = details.data;
    final box =
        _timelineKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;

    final local = box.globalToLocal(details.offset);
    final rawMinutes = local.dy / _hourHeight * 60.0;
    final maxStart =
        (_endHour - _startHour) * 60 - entry.duration.inMinutes;
    final snapped =
        ((rawMinutes / timeStep).round() * timeStep)
            .clamp(0, maxStart < 0 ? 0 : maxStart)
            .toInt();

    final newHour = _startHour + snapped ~/ 60;
    final newMin = snapped % 60;
    final newStart = DateTime(_selectedDate.year, _selectedDate.month,
        _selectedDate.day, newHour, newMin);
    final newEnd = newStart.add(entry.duration);

    int? newWaiterId = entry.waiterId;
    final xInColumns = local.dx - _timeColWidth;
    if (xInColumns >= 0 && _waiterIds.isNotEmpty) {
      final colIdx = (xInColumns / _cachedColWidth)
          .floor()
          .clamp(0, _waiterIds.length - 1);
      newWaiterId = _waiterIds[colIdx];
    }

    await _commitSchedule(
      entry: entry,
      newStart: newStart,
      newEnd: newEnd,
      newWaiterId: newWaiterId,
      successMessage:
          '${entry.productName} → ${DateFormat.Hm().format(newStart)}',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DETAIL DIALOG
  // ─────────────────────────────────────────────────────────────────────────

  void _showEntryDetail(BuildContext context, AgendaEntry e) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        titlePadding: EdgeInsets.zero,
        contentPadding: EdgeInsets.zero,
        title: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: e.color.withValues(alpha: 0.11),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(left: BorderSide(color: e.color, width: 5)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: e.color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: e.color.withValues(alpha: 0.35), width: 1.5),
                ),
                child: Icon(Icons.event_note_outlined,
                    color: e.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  e.productName,
                  style: TextStyle(
                    color: e.color.darken(0.1),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              _stateChip(e.state, e.color),
            ],
          ),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow(context, Icons.confirmation_number_outlined,
                    'Order', e.orderCode),
                const Divider(height: 12),
                if (e.customerName != null) ...[
                  _detailRow(context, Icons.person, 'Customer',
                      e.customerName!),
                  if (e.customerPhone != null)
                    _detailRow(context, Icons.phone_outlined, 'Phone',
                        e.customerPhone!),
                  const Divider(height: 12),
                ],
                _detailRow(
                    context,
                    Icons.play_circle_outline,
                    'Start',
                    DateFormat('dd/MM/yyyy HH:mm').format(e.start)),
                _detailRow(
                    context,
                    Icons.stop_circle_outlined,
                    'End',
                    DateFormat('dd/MM/yyyy HH:mm').format(e.end)),
                _detailRow(context, Icons.timer_outlined, 'Duration',
                    _formatDuration(e.duration)),
                if (e.value != null)
                  _detailRow(
                    context,
                    Icons.sell_outlined,
                    AppLocalizations.of(context)!.translate('reserved_value'),
                    ref.read(currencyFormatterProvider).format(e.value!),
                  ),
                const Divider(height: 12),
                if (e.waiterName != null)
                  _detailRow(context, Icons.badge_outlined, 'With',
                      e.waiterName!),
                if (e.resourceName != null)
                  _detailRow(context, Icons.meeting_room_outlined,
                      AppLocalizations.of(context)?.translate('resource') ??
                          'Resource',
                      e.resourceName!),
                _detailRow(
                    context, Icons.info_outline, 'Status', e.state),
                _detailRow(
                  context,
                  Icons.schedule_outlined,
                  'Timing',
                  timeStatusLabel(e.timeStatus(),
                      AppLocalizations.of(context)!),
                ),
                if (e.note != null && e.note!.isNotEmpty) ...[
                  const Divider(height: 12),
                  _detailRow(context, Icons.sticky_note_2_outlined,
                      'Note', e.note!),
                ],
              ],
            ),
          ),
        ),
        actionsPadding:
            const EdgeInsets.fromLTRB(16, 0, 16, 14),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
          // Freeing a slot only makes sense for a booking the server knows
          // about, and only online — the diary it belongs to lives there.
          if (e.isActionable)
            TextButton.icon(
              icon: const Icon(Icons.event_busy_outlined, size: 16),
              label: Text(
                  AppLocalizations.of(ctx)!.translate('unschedule')),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () {
                Navigator.pop(ctx);
                _unschedule(e);
              },
            ),
          FilledButton.icon(
            icon: const Icon(Icons.edit_calendar, size: 16),
            label: const Text('Edit Time'),
            style: FilledButton.styleFrom(
              backgroundColor: e.color,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _editEntryTime(context, e);
            },
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h == 0) return '${m}min';
    if (m == 0) return '${h}h';
    return '${h}h ${m}min';
  }

  Widget _stateChip(String state, Color color) {
    final label = switch (state) {
      'COMPLETED' => 'Done',
      'PREPARING' => 'Preparing',
      'CANCELED' => 'Canceled',
      _ => 'Planned',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color.darken(0.08),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _detailRow(
      BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 16,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.42)),
          const SizedBox(width: 10),
          SizedBox(
            width: 68,
            child: Text(
              '$label:',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EDIT DIALOG
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _editEntryTime(BuildContext context, AgendaEntry e) async {
    DateTime newStart = e.start;
    DateTime newEnd = e.end;
    final waiters = await ref.read(allWaitersProvider.future);
    if (!context.mounted) return;

    int? newWaiterId = e.waiterId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final valid = newEnd.isAfter(newStart);
          final durationText = valid
              ? _formatDuration(newEnd.difference(newStart))
              : null;

          return AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18)),
            title: Row(
              children: [
                Icon(Icons.edit_calendar, color: e.color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    e.productName,
                    style: const TextStyle(fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _timeChip(ctx,
                            label: 'Start',
                            time: newStart,
                            color: const Color(0xFF43A047),
                            icon: Icons.play_arrow_rounded,
                            onPick: (p) => setDlg(() {
                                  newStart = DateTime(
                                      newStart.year,
                                      newStart.month,
                                      newStart.day,
                                      p.hour,
                                      p.minute);
                                })),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _timeChip(ctx,
                            label: 'End',
                            time: newEnd,
                            color: const Color(0xFFE53935),
                            icon: Icons.stop_rounded,
                            onPick: (p) => setDlg(() {
                                  newEnd = DateTime(newEnd.year,
                                      newEnd.month, newEnd.day, p.hour,
                                      p.minute);
                                })),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: durationText != null
                        ? Chip(
                            key: const ValueKey('ok'),
                            avatar: const Icon(Icons.timer, size: 16),
                            label: Text(durationText),
                            backgroundColor:
                                Colors.green.withValues(alpha: 0.1),
                          )
                        : Chip(
                            key: const ValueKey('err'),
                            avatar: const Icon(Icons.warning,
                                size: 16, color: Colors.red),
                            label: const Text('End before start',
                                style: TextStyle(color: Colors.red)),
                            backgroundColor:
                                Colors.red.withValues(alpha: 0.08),
                          ),
                  ),
                  const Divider(height: 20),
                  DropdownButtonFormField<int?>(
                    decoration: const InputDecoration(
                      labelText: 'Assigned to',
                      prefixIcon: Icon(Icons.badge_outlined),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    initialValue: newWaiterId,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<int?>(
                          value: null, child: Text('Unassigned')),
                      ...waiters.map((w) => DropdownMenuItem<int?>(
                            value: w.id,
                            child: Text(
                                '${w.firstName} ${w.lastName ?? ''}'.trim()),
                          )),
                    ],
                    onChanged: (v) => setDlg(() => newWaiterId = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed:
                    valid ? () => Navigator.pop(ctx, true) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: e.color,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );

    if (saved != true || !context.mounted) return;

    await _commitSchedule(
      entry: e,
      newStart: newStart,
      newEnd: newEnd,
      newWaiterId: newWaiterId,
      successMessage: AppLocalizations.of(context)?.translate('booking_updated') ??
          'Booking updated',
    );
  }

  /// Move or reassign a booking.
  ///
  /// Server first, local second, and **never** queued. Scheduling is the one
  /// POS action that may not ride the offline queue: the slot lives in the
  /// shop's single diary, so a local write held for later reconciliation is a
  /// promise this terminal cannot keep — two tills offline would each hand out
  /// the same chair. Writing local state only after the server accepts also
  /// means a rejected move never leaves the agenda showing an appointment
  /// nobody owns, so there is nothing to revert.
  Future<void> _commitSchedule({
    required AgendaEntry entry,
    required DateTime newStart,
    required DateTime newEnd,
    required int? newWaiterId,
    int? newResourceId,
    String? successMessage,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    final booking = ref.read(bookingServiceProvider);

    if (!booking.canBook) {
      _agendaToast(l10n.translate('reconnect_to_book'), isError: true);
      return;
    }

    final serverId = entry.serverOrderProductId ??
        (entry.orderProductId == null
            ? null
            : await booking.resolveServerLineId(entry.orderProductId!));
    if (serverId == null) {
      // The order has never reached the backend, so there is no line for
      // /schedule to address. Selling it offline was fine; booking it is not.
      if (mounted) {
        _agendaToast(l10n.translate('booking_order_sync_failed'), isError: true);
      }
      return;
    }

    try {
      await booking.schedule(
        serverOrderProductId: serverId,
        localOrderProductId: entry.orderProductId,
        planStartAt: newStart,
        planEndAt: newEnd,
        planWaiterId: newWaiterId,
        planResourceId: newResourceId ?? entry.resourceId,
      );
      await _pullAgenda();
      ref.invalidate(agendaEntriesProvider(_selectedDate));
      if (mounted && successMessage != null) _agendaToast(successMessage);
    } on ScheduleConflict catch (c) {
      final detail =
          c.capacity != null ? ' (${c.current ?? '?'}/${c.capacity})' : '';
      // The diary moved under us — pull it so the grid shows what actually
      // holds that time before staff try again.
      await _pullAgenda();
      ref.invalidate(agendaEntriesProvider(_selectedDate));
      if (mounted) _agendaToast('${c.message}$detail', isError: true);
    } on ScheduleValidationError catch (v) {
      if (mounted) _agendaToast(v.message, isError: true);
    } on OfflineBookingException {
      if (mounted) {
        _agendaToast(l10n.translate('reconnect_to_book'), isError: true);
      }
    } catch (e) {
      if (mounted) _agendaToast(errorText(e, l10n), isError: true);
    }
  }

  /// Pull the whole week around the day on screen. Silent on failure: the grid
  /// keeps showing the last pull rather than emptying itself.
  ///
  /// A week, not a day, because staff step through days constantly — one
  /// request covers the whole run, and the days either side are already there
  /// if the connection drops before the next tap.
  Future<bool> _pullAgenda() async {
    final summary = await refreshAgendaWeek(
      api: ref.read(apiServiceProvider),
      sync: ref.read(dataSyncServiceProvider),
      isOnline: ref.read(bookingServiceProvider).canBook,
      date: _selectedDate,
    );
    if (summary == null) return false;
    if (mounted) {
      final monday = weekOf(_selectedDate).start;
      ref.read(agendaWeekSummaryProvider.notifier).update(
            (m) => {...m, monday: summary},
          );
    }
    return true;
  }

  /// Skip the pull when the week on screen has not changed — flicking between
  /// Tuesday and Wednesday should not re-fetch the same seven days.
  Future<void> _syncWeekIfChanged(DateTime previous) async {
    if (weekOf(previous).start == weekOf(_selectedDate).start) return;
    await _syncDay();
  }

  /// Free a slot. The sale stays on the order — only the appointment goes.
  Future<void> _unschedule(AgendaEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final booking = ref.read(bookingServiceProvider);

    if (!booking.canBook) {
      _agendaToast(l10n.translate('reconnect_to_book'), isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('unschedule')),
        content: Text(l10n.translate('unschedule_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.translate('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.translate('unschedule')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final serverId = entry.serverOrderProductId ??
        (entry.orderProductId == null
            ? null
            : await booking.resolveServerLineId(entry.orderProductId!));
    if (serverId == null) {
      if (mounted) {
        _agendaToast(l10n.translate('booking_order_sync_failed'), isError: true);
      }
      return;
    }

    try {
      await booking.unschedule(
        serverOrderProductId: serverId,
        localOrderProductId: entry.orderProductId,
      );
      ref.invalidate(agendaEntriesProvider(_selectedDate));
      if (mounted) _agendaToast(l10n.translate('unscheduled'));
    } on OfflineBookingException {
      if (mounted) {
        _agendaToast(l10n.translate('reconnect_to_book'), isError: true);
      }
    } catch (e) {
      if (mounted) _agendaToast(errorText(e, l10n), isError: true);
    }
  }

  void _agendaToast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: isError ? 4 : 2),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _timeChip(
    BuildContext context, {
    required String label,
    required DateTime time,
    required Color color,
    required IconData icon,
    required void Function(TimeOfDay) onPick,
  }) {
    return GestureDetector(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(time),
          helpText: 'Select $label time',
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: color.withValues(alpha: 0.35), width: 1.2),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  DateFormat.Hm().format(time),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Color extension
// ═══════════════════════════════════════════════════════════════════════════

extension _ColorDarken on Color {
  Color darken(double amount) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
        .toColor();
  }

  Color lighten(double amount) {
    final hsl = HSLColor.fromColor(this);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }
}
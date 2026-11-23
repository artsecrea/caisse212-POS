import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../data/database/app_database.dart' show Resource;
import '../../domain/models/reservation_models.dart';
import '../../providers/reservation_providers.dart';
import '../../providers/resource_providers.dart';
import '../../providers/settings_provider.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import 'agenda_conflicts.dart';
import 'reservation_panel.dart';
import 'reservation_actions.dart';
import 'reservation_detail_sheet.dart';

enum _AgendaView { day, list }

/// One service of a reservation, placed in one agenda column.
class _Placed {
  final Reservation reservation;
  final ReservationItem item;
  int lane = 0;
  int lanes = 1;
  _Placed(this.reservation, this.item);
}

/// What is dragged when a booked service is moved.
class _Drag {
  final Reservation reservation;
  final ReservationItem item;
  final int? fromResourceId;
  const _Drag(this.reservation, this.item, this.fromResourceId);
}

/// The shop's diary, built to be worked directly:
///
///   * tap an empty slot, or press and sweep down a column, to pick the time —
///     a side panel opens with the time and the person already set;
///   * press and hold a card to drag it to another time or person;
///   * drag a card's bottom edge to make it longer or shorter;
///   * tap a card for its details and the till.
///
/// Reads the local cache, so it still shows the last pull offline; pulls the
/// week on open, on day change and on every SSE `reservation-updated`.
/// The till's cart, to be booked as a reservation instead of sold now.
class CartBooking {
  /// Fresh lines for each attempt: the panel edits them in place.
  final List<BasketLine> Function() lines;
  final PanelCustomer? customer;

  /// What the cart holds, for the banner ("Coupe, Soin + 1 product").
  final String summary;

  /// Lines that had options (modifiers): reservations carry none.
  final bool hadOptions;

  /// Called once the reservation is saved: the cart is emptied, unsold.
  final VoidCallback onBooked;

  const CartBooking({
    required this.lines,
    this.customer,
    required this.summary,
    this.hadOptions = false,
    required this.onBooked,
  });
}

class AgendaScreen extends ConsumerStatefulWidget {
  /// Set when the agenda was opened from the till's "Reserve" button.
  final CartBooking? booking;
  const AgendaScreen({super.key, this.booking});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen> {
  static const double _hourHeight = 96;
  static const double _rulerWidth = 60;
  static const double _minColWidth = 200;
  static const double _headerHeight = 68;
  static const double _sidebarWidth = 300;

  DateTime _date = dayStartOf(DateTime.now());
  _AgendaView _view = _AgendaView.day;
  bool _pulling = false;

  /// Columns staff chose to hide from the sidebar.
  final Set<int> _hidden = {};

  final _vScroll = ScrollController();
  final _hBody = ScrollController();
  final _hHeader = ScrollController();
  bool _scrolledToNow = false;

  // A slot being picked: the column and the two y's of the sweep.
  int? _selColumn;
  double _selA = 0, _selB = 0;

  /// Last pointer was a mouse: cards drag at once (Planity on a desktop).
  /// A finger keeps press-and-hold, so scrolling the day never moves one.
  bool _mouse = false;

  /// Mouse over an empty slot: a faint "+ 10:15" where a click would book.
  ({int column, DateTime start})? _hover;

  /// What the open panel is about to book, outlined service by service in
  /// each one's column. Replaces the sweep once the panel reports.
  List<PreviewSegment> _preview = const [];
  int? _previewDefault;

  /// Where a dragged card would land.
  ({int column, DateTime start, Duration length})? _ghost;

  void _setMouse(bool v) {
    if (_mouse != v) setState(() => _mouse = v);
  }

  // A card being stretched from its bottom edge.
  int? _resizeItem;
  double _resizeDy = 0;

  late final StateController<DateTime?> _visible;

  @override
  void initState() {
    super.initState();
    _visible = ref.read(agendaVisibleDateProvider.notifier);
    _hBody.addListener(() {
      if (_hHeader.hasClients) _hHeader.jumpTo(_hBody.offset);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visible.state = _date;
      _pull();
    });
  }

  @override
  void dispose() {
    final visible = _visible;
    Future.microtask(() {
      // The whole scope may be going away with us (logout, app exit).
      if (visible.mounted) visible.state = null;
    });
    _vScroll.dispose();
    _hBody.dispose();
    _hHeader.dispose();
    super.dispose();
  }

  Future<void> _pull() async {
    setState(() => _pulling = true);
    await pullAgendaWeekFromWidget(ref, _date);
    if (mounted) setState(() => _pulling = false);
  }

  void _goTo(DateTime d) {
    final before = weekOf(_date).start;
    setState(() {
      _date = dayStartOf(d);
      _scrolledToNow = false;
      _selColumn = null;
    });
    _visible.state = _date;
    if (weekOf(_date).start != before) _pull();
  }

  int get _snap {
    final step = ref.read(settingsProvider).agendaTimeStep;
    return step >= 60 || step <= 0 ? 15 : step;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final online = ref.watch(canReserveProvider);
    final dayAsync = ref.watch(agendaDayProvider(_date));
    ref.watch(clockTickProvider);
    final wide = MediaQuery.of(context).size.width >= 1150;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Listener(
        onPointerDown: (e) => _setMouse(e.kind == PointerDeviceKind.mouse),
        child: MouseRegion(
          onHover: (_) => _setMouse(true),
          child: SafeArea(
            child: Column(
              children: [
                _toolbar(context, l10n, online, dayAsync.valueOrNull),
                if (widget.booking != null) _bookingBanner(theme, l10n),
                if (!online) _offlineBanner(theme, l10n, dayAsync.valueOrNull),
                if (!wide) _weekStrip(theme),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (wide) _sidebar(context, l10n, dayAsync.valueOrNull),
                      if (wide) const VerticalDivider(width: 1),
                      Expanded(
                        child: dayAsync.when(
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('$e')),
                          data: (day) => _view == _AgendaView.day
                              ? _grid(context, day, online)
                              : _list(context, day),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bookingBanner(ThemeData theme, AppLocalizations l10n) {
    final cs = theme.colorScheme;
    final b = widget.booking!;
    return Container(
      width: double.infinity,
      color: cs.primaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, color: cs.onPrimaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n
                      .translate('res_cart_pick_slot')
                      .replaceAll('{items}', b.summary),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                if (b.hadOptions)
                  Text(
                    l10n.translate('res_cart_options_dropped'),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.translate('cancel')),
          ),
        ],
      ),
    );
  }

  Widget _toolbar(
    BuildContext context,
    AppLocalizations l10n,
    bool online,
    AgendaDay? day,
  ) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final label = DateFormat('EEEE d MMMM y', locale).format(_date);
    final isToday = _date == dayStartOf(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
      child: Row(
        children: [
          if (Navigator.of(context).canPop())
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          const SizedBox(width: 4),
          OutlinedButton(
            onPressed: isToday ? null : () => _goTo(DateTime.now()),
            child: Text(l10n.translate('today')),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () =>
                _goTo(DateTime(_date.year, _date.month, _date.day - 1)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () =>
                _goTo(DateTime(_date.year, _date.month, _date.day + 1)),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 730)),
                );
                if (picked != null) _goTo(picked);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Text(
                  label.isEmpty
                      ? label
                      : label[0].toUpperCase() + label.substring(1),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _daySummary(theme, l10n, day),
          if (day != null) _conflictChip(theme, l10n, day),
          const Spacer(),
          IconButton(
            tooltip: l10n.translate('search'),
            icon: const Icon(Icons.search_rounded),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _SearchDialog(),
            ),
          ),
          IconButton(
            tooltip: l10n.translate('refresh'),
            onPressed: online && !_pulling ? _pull : null,
            icon: _pulling
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
          SegmentedButton<_AgendaView>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: _AgendaView.day,
                icon: const Icon(Icons.view_column_outlined, size: 18),
                label: Text(l10n.translate('res_view_day')),
              ),
              ButtonSegment(
                value: _AgendaView.list,
                icon: const Icon(Icons.list_alt_outlined, size: 18),
                label: Text(l10n.translate('res_view_list')),
              ),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: online ? () => _newFromButton(day) : null,
            icon: const Icon(Icons.add_rounded),
            label: Text(l10n.translate('new_reservation')),
          ),
        ],
      ),
    );
  }

  /// The day's count and reserved money, from the pulled summary.
  Widget _daySummary(ThemeData theme, AppLocalizations l10n, AgendaDay? day) {
    final summary = ref.watch(agendaWeekSummaryProvider)[weekOf(_date).start];
    final today = summary?.forDay(dayKey(_date));
    final count =
        today?.count ?? day?.reservations.where((r) => r.holdsSlot).length ?? 0;
    if (count == 0) return const SizedBox.shrink();
    final money = ref.watch(currencyFormatterProvider);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        today == null
            ? appointmentCount(count, l10n)
            : '${appointmentCount(count, l10n)} · ${money.format(today.value)}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }

  /// "2 to sort out": overlapping bookings, opening the conflicts panel.
  Widget _conflictChip(ThemeData theme, AppLocalizations l10n, AgendaDay day) {
    final resources = _allColumns(day).whereType<AgendaResource>().toList();
    final n = findConflicts(day, resources).length;
    if (n == 0) return const SizedBox.shrink();
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: ActionChip(
        backgroundColor: cs.tertiaryContainer,
        side: BorderSide.none,
        avatar: Icon(
          Icons.layers_rounded,
          size: 18,
          color: cs.onTertiaryContainer,
        ),
        label: Text(
          l10n.translate('res_conflicts_count').replaceAll('{n}', '$n'),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: cs.onTertiaryContainer,
          ),
        ),
        onPressed: () => showConflictsPanel(context, _date, resources),
      ),
    );
  }

  Widget _offlineBanner(
    ThemeData theme,
    AppLocalizations l10n,
    AgendaDay? day,
  ) {
    final at = day?.fetchedAt;
    final text = at == null
        ? l10n.translate('res_offline_writes')
        : '${l10n.translate('res_offline_writes')} · '
              '${l10n.translate('res_last_pulled').replaceAll('{time}', DateFormat('dd/MM HH:mm').format(at))}';
    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 18,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Narrow screens: the week as a strip instead of the sidebar calendar.
  Widget _weekStrip(ThemeData theme) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = dayStartOf(DateTime.now());
    final week = weekOf(_date);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: () {
                final d = DateTime(
                  week.start.year,
                  week.start.month,
                  week.start.day + i,
                );
                final selected = d == _date;
                final fg = selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _goTo(d),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? theme.colorScheme.primary : null,
                        borderRadius: BorderRadius.circular(10),
                        border: d == today && !selected
                            ? Border.all(color: theme.colorScheme.primary)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(
                            DateFormat('EEE', locale).format(d),
                            style: TextStyle(fontSize: 11, color: fg),
                          ),
                          Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: fg,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }(),
            ),
        ],
      ),
    );
  }

  Widget _sidebar(BuildContext context, AppLocalizations l10n, AgendaDay? day) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final columns = day == null ? const <AgendaResource?>[] : _allColumns(day);
    TextStyle? heading() => theme.textTheme.labelMedium?.copyWith(
      letterSpacing: 0.8,
      fontWeight: FontWeight.w700,
      color: cs.onSurfaceVariant,
    );
    return SizedBox(
      width: _sidebarWidth,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          CalendarDatePicker(
            key: ValueKey(_date),
            initialDate: _date,
            firstDate: DateTime(2020),
            lastDate: DateTime.now().add(const Duration(days: 730)),
            onDateChanged: _goTo,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              l10n.translate('res_team').toUpperCase(),
              style: heading(),
            ),
          ),
          for (final c in columns.whereType<AgendaResource>())
            CheckboxListTile(
              dense: true,
              controlAffinity: ListTileControlAffinity.trailing,
              value: !_hidden.contains(c.id),
              onChanged: (v) => setState(
                () => v == true ? _hidden.remove(c.id) : _hidden.add(c.id),
              ),
              secondary: ResourceAvatar(resource: c, radius: 15),
              title: Text(c.name, overflow: TextOverflow.ellipsis),
              subtitle: Text(appointmentCount(_countFor(day!, c), l10n)),
            ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              l10n.translate('res_legend').toUpperCase(),
              style: heading(),
            ),
          ),
          for (final s in const [
            ReservationStatus.booked,
            ReservationStatus.confirmed,
            ReservationStatus.arrived,
            ReservationStatus.converted,
          ])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
              child: Row(
                children: [
                  Icon(
                    _statusIcon(s) ?? Icons.circle_outlined,
                    size: 16,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(reservationStatusLabel(s, l10n)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              l10n.translate('res_gesture_hint'),
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }

  int _countFor(AgendaDay day, AgendaResource c) => day.reservations
      .where(
        (r) => r.holdsSlot && r.items.any((i) => i.resourceIds.contains(c.id)),
      )
      .length;

  static IconData? _statusIcon(String status) {
    switch (status) {
      case ReservationStatus.confirmed:
        return Icons.verified_rounded;
      case ReservationStatus.arrived:
        return Icons.how_to_reg_rounded;
      case ReservationStatus.converted:
        return Icons.receipt_long_rounded;
      default:
        return null;
    }
  }

  // ── Columns and time ─────────────────────────────────────────────────────

  /// Every column the day can show: its resources as pulled, or the synced
  /// list when it was never pulled; "unassigned" (null) only when a service
  /// has no resource drawn here.
  List<AgendaResource?> _allColumns(AgendaDay day) {
    final List<AgendaResource> cols =
        day.resources.isNotEmpty
              ? day.resources
                    .where((r) => r.isActive || _usedBy(day, r.id))
                    .toList()
              : [
                  for (final Resource r
                      in ref.watch(resourcesProvider).valueOrNull ?? const [])
                    AgendaResource(
                      id: r.id,
                      name: r.name,
                      type: r.type,
                      color: r.color,
                      sortOrder: r.sortOrder,
                      capacity: r.capacity,
                    ),
                ]
          ..sort((a, b) {
            if (a.isStaff != b.isStaff) return a.isStaff ? -1 : 1;
            final s = a.sortOrder.compareTo(b.sortOrder);
            return s != 0 ? s : a.name.compareTo(b.name);
          });
    final ids = cols.map((c) => c.id).toSet();
    final orphan = day.reservations
        .where((r) => r.holdsSlot)
        .any(
          (r) => r.items.any(
            (i) =>
                i.timed &&
                (i.resourceIds.isEmpty || !i.resourceIds.any(ids.contains)),
          ),
        );
    return [...cols, if (orphan) null];
  }

  List<AgendaResource?> _columns(AgendaDay day) => _allColumns(
    day,
  ).where((c) => c == null || !_hidden.contains(c.id)).toList();

  bool _usedBy(AgendaDay day, int resourceId) => day.reservations.any(
    (r) => r.items.any((i) => i.resourceIds.contains(resourceId)),
  );

  /// Visible hours: opening hours and anything booked, padded to whole hours,
  /// never less than 8:00–20:00.
  (int, int) _hourRange(AgendaDay day) {
    var first = 8, last = 20;
    final from = _date;
    void take(DateTime s, DateTime e) {
      if (!s.isBefore(from)) first = math.min(first, s.hour);
      final endH = e.isAfter(from.add(const Duration(days: 1)))
          ? 24
          : (e.minute > 0 ? e.hour + 1 : e.hour);
      last = math.max(last, endH);
    }

    for (final r in day.openHours) {
      take(r.start, r.end);
    }
    for (final res in day.reservations) {
      if (res.holdsSlot) take(res.startAt, res.endAt);
    }
    return (first.clamp(0, 23), last.clamp(first + 1, 24));
  }

  double _y(DateTime t, int startHour) {
    final from = _date.add(Duration(hours: startHour));
    return t.difference(from).inMinutes * _hourHeight / 60;
  }

  DateTime _timeAt(double y, int startHour, {bool ceil = false}) {
    final raw = y / _hourHeight * 60;
    final steps = ceil ? (raw / _snap).ceil() : (raw / _snap).floor();
    return _date.add(
      Duration(hours: startHour, minutes: math.max(0, steps * _snap)),
    );
  }

  // ── Grid ─────────────────────────────────────────────────────────────────

  Widget _grid(BuildContext context, AgendaDay day, bool online) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final columns = _columns(day);
    if (columns.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.translate('res_no_resources'),
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final (startHour, endHour) = _hourRange(day);
    final bodyHeight = (endHour - startHour) * _hourHeight;

    if (!_scrolledToNow) {
      _scrolledToNow = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_vScroll.hasClients) return;
        final now = DateTime.now();
        final target = dayStartOf(now) == _date
            ? (now.hour - startHour - 1) * _hourHeight
            : 0.0;
        _vScroll.jumpTo(
          target.clamp(0.0, _vScroll.position.maxScrollExtent).toDouble(),
        );
      });
    }

    return LayoutBuilder(
      builder: (context, box) {
        final colWidth = math.max(
          _minColWidth,
          (box.maxWidth - _rulerWidth) / columns.length,
        );
        final totalWidth = colWidth * columns.length;
        return Column(
          children: [
            SizedBox(
              height: _headerHeight,
              child: Row(
                children: [
                  const SizedBox(width: _rulerWidth),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _hHeader,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Row(
                        children: [
                          for (final c in columns)
                            _columnHeader(theme, l10n, c, day, colWidth),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: _vScroll,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _ruler(theme, startHour, endHour),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _hBody,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: totalWidth,
                          height: bodyHeight,
                          child: Row(
                            children: [
                              for (final c in columns)
                                _column(
                                  context,
                                  day,
                                  c,
                                  columns,
                                  colWidth,
                                  bodyHeight,
                                  startHour,
                                  online,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _columnHeader(
    ThemeData theme,
    AppLocalizations l10n,
    AgendaResource? c,
    AgendaDay day,
    double width,
  ) {
    final cs = theme.colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: BorderDirectional(
          start: BorderSide(color: cs.outlineVariant, width: 0.6),
        ),
      ),
      child: Row(
        children: [
          if (c != null)
            ResourceAvatar(resource: c)
          else
            CircleAvatar(
              radius: 18,
              backgroundColor: cs.surfaceContainerHighest,
              child: Icon(
                Icons.help_outline_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c?.name ?? l10n.translate('res_unassigned'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (c != null)
                  Text(
                    appointmentCount(_countFor(day, c), l10n),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ruler(ThemeData theme, int startHour, int endHour) {
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final isToday = dayStartOf(now) == _date;
    return SizedBox(
      width: _rulerWidth,
      height: (endHour - startHour) * _hourHeight,
      child: Stack(
        children: [
          for (var h = startHour + 1; h < endHour; h++)
            Positioned(
              top: (h - startHour) * _hourHeight - 7,
              right: 8,
              child: Text(
                '${h.toString().padLeft(2, '0')}:00',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (isToday && now.hour >= startHour && now.hour < endHour)
            Positioned(
              top: _y(now, startHour) - 9,
              right: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.error,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  hm(now),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: cs.onError,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _column(
    BuildContext context,
    AgendaDay day,
    AgendaResource? c,
    List<AgendaResource?> columns,
    double width,
    double height,
    int startHour,
    bool online,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final key = dayKey(_date);
    final ids = columns.whereType<AgendaResource>().map((r) => r.id).toSet();

    final placed = <_Placed>[
      for (final r in day.reservations)
        if (r.holdsSlot)
          for (final it in r.items)
            if (it.timed &&
                (c == null
                    ? (it.resourceIds.isEmpty ||
                          !it.resourceIds.any(ids.contains))
                    : it.resourceIds.contains(c.id)))
              _Placed(r, it),
    ]..sort((a, b) => a.item.startAt.compareTo(b.item.startAt));
    _assignLanes(placed);
    final conflicted = c == null
        ? const <int>{}
        : conflictItemIds(findConflicts(day, [c]));

    final open =
        c?.availabilityOn(key) ??
        (day.openHours.isEmpty ? null : day.openHours);
    final blocks = c == null
        ? const <AgendaBlock>[]
        : day.blocks.where((b) => b.resourceId == c.id).toList();
    final busy = c == null
        ? const <ForeignBusy>[]
        : day.foreignBusy.where((b) => b.resourceId == c.id).toList();
    // A frame that was never pulled has no hours: shade nothing rather than
    // claim the whole day is closed.
    final shade = day.fetchedAt != null && open != null;
    final canPick = online && c != null;
    final selecting = c != null && _selColumn == c.id;

    // Sweeping: press-and-hold then slide (touch), or click-and-drag (mouse).
    void selStart(double y) {
      HapticFeedback.selectionClick();
      setState(() {
        _selColumn = c!.id;
        _selA = _selB = y;
      });
    }

    void selMove(double y) =>
        setState(() => _selB = y.clamp(0.0, height).toDouble());
    void selEnd() => _openQuick(
      c!,
      columns,
      startHour,
      math.min(_selA, _selB),
      math.max(_selA, _selB),
    );

    return Builder(
      builder: (colContext) {
        // With the child anchor the offset is the card's new top edge;
        // rounding to the nearest step (not down) follows the pointer.
        DateTime landing(Offset global) {
          final box = colContext.findRenderObject() as RenderBox;
          final local = box.globalToLocal(global);
          return _timeAt(local.dy + _hourHeight * _snap / 120, startHour);
        }

        return DragTarget<_Drag>(
          onWillAcceptWithDetails: (d) => online && c != null,
          onMove: (d) {
            if (c == null) return;
            final start = landing(d.offset);
            final ghost = (
              column: c.id,
              start: start,
              length: d.data.item.endAt.difference(d.data.item.startAt),
            );
            if (_ghost != ghost) setState(() => _ghost = ghost);
          },
          onLeave: (_) {
            if (_ghost?.column == c?.id) setState(() => _ghost = null);
          },
          onAcceptWithDetails: (d) {
            setState(() => _ghost = null);
            _drop(d.data, c!, landing(d.offset));
          },
          builder: (context, candidate, _) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: canPick
                  ? (d) => _openQuick(
                      c,
                      columns,
                      startHour,
                      d.localPosition.dy,
                      null,
                    )
                  : null,
              onLongPressStart: canPick
                  ? (d) => selStart(d.localPosition.dy)
                  : null,
              onLongPressMoveUpdate: canPick
                  ? (d) => selMove(d.localPosition.dy)
                  : null,
              onLongPressEnd: canPick ? (_) => selEnd() : null,
              child: GestureDetector(
                supportedDevices: const {PointerDeviceKind.mouse},
                onVerticalDragStart: canPick
                    ? (d) => selStart(d.localPosition.dy)
                    : null,
                onVerticalDragUpdate: canPick
                    ? (d) => selMove(d.localPosition.dy)
                    : null,
                onVerticalDragEnd: canPick ? (_) => selEnd() : null,
                child: MouseRegion(
                  cursor: canPick
                      ? SystemMouseCursors.click
                      : MouseCursor.defer,
                  onHover: canPick
                      ? (e) {
                          final h = (
                            column: c.id,
                            start: _timeAt(e.localPosition.dy, startHour),
                          );
                          if (_hover != h) setState(() => _hover = h);
                        }
                      : null,
                  onExit: (_) {
                    if (_hover?.column == c?.id) setState(() => _hover = null);
                  },
                  child: Container(
                    width: width,
                    height: height,
                    decoration: BoxDecoration(
                      color: candidate.isNotEmpty
                          ? cs.primary.withValues(alpha: 0.05)
                          : null,
                      border: BorderDirectional(
                        start: BorderSide(color: cs.outlineVariant, width: 0.6),
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _ColumnPainter(
                              hourHeight: _hourHeight,
                              line: cs.outlineVariant,
                              closed: cs.onSurface.withValues(alpha: 0.045),
                              open: shade
                                  ? [
                                      for (final r in open)
                                        (
                                          _y(r.start, startHour),
                                          _y(r.end, startHour),
                                        ),
                                    ]
                                  : null,
                            ),
                          ),
                        ),
                        for (final b in busy)
                          _band(
                            top: _y(b.start, startHour),
                            bottom: _y(b.end, startHour),
                            color: cs.outline.withValues(alpha: 0.22),
                            label: l10n.translate('res_busy_elsewhere'),
                            fg: cs.onSurfaceVariant,
                            icon: Icons.block_rounded,
                          ),
                        for (final b in blocks)
                          _band(
                            top: _y(b.startAt, startHour),
                            bottom: _y(b.endAt, startHour),
                            color: cs.surfaceContainerHighest,
                            label:
                                b.title ??
                                l10n.translate(
                                  'res_block_${b.kind.toLowerCase()}',
                                ),
                            fg: cs.onSurfaceVariant,
                            icon: Icons.coffee_outlined,
                            onTap: online ? () => _blockTapped(b) : null,
                          ),
                        if (canPick &&
                            !selecting &&
                            _ghost == null &&
                            _hover?.column == c.id)
                          _hoverHint(cs, _hover!.start, startHour),
                        for (final p in placed)
                          _card(
                            context,
                            p,
                            c,
                            width,
                            startHour,
                            online,
                            conflict:
                                p.item.id != null &&
                                conflicted.contains(p.item.id),
                          ),
                        if (selecting) _selection(cs, startHour),
                        if (c != null)
                          for (final seg in _preview)
                            if ((seg.resourceId ?? _previewDefault) == c.id)
                              _segmentBox(cs, seg.start, seg.end, startHour),
                        if (_ghost != null && _ghost!.column == c?.id)
                          _ghostBox(
                            cs,
                            _ghost!.start,
                            _ghost!.length,
                            startHour,
                          ),
                        if (dayStartOf(DateTime.now()) == _date)
                          Positioned(
                            top: _y(DateTime.now(), startHour) - 4,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: cs.error,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 2,
                                      color: cs.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// "+ 10:15" under the mouse: where a click would book.
  Widget _hoverHint(ColorScheme cs, DateTime start, int startHour) {
    final top = _y(start, startHour);
    return Positioned(
      top: top,
      left: 3,
      right: 3,
      height: _hourHeight * math.max(30, _snap) / 60,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.06),
            border: Border.all(color: cs.primary.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: AlignmentDirectional.topStart,
          child: Text(
            '+ ${hm(start)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.primary.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }

  /// Where the dragged card would land, with its new times.
  Widget _ghostBox(
    ColorScheme cs,
    DateTime start,
    Duration length,
    int startHour,
  ) {
    final top = _y(start, startHour);
    return Positioned(
      top: top,
      left: 3,
      right: 3,
      height: math.max(24, _y(start.add(length), startHour) - top),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.12),
            border: Border.all(color: cs.primary, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: AlignmentDirectional.topStart,
          child: Text(
            hmRange(start, start.add(length)),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: cs.primary,
            ),
          ),
        ),
      ),
    );
  }

  /// One service of the booking being prepared in the panel.
  Widget _segmentBox(
    ColorScheme cs,
    DateTime start,
    DateTime end,
    int startHour,
  ) {
    final top = _y(start, startHour);
    return Positioned(
      top: top,
      left: 3,
      right: 3,
      height: math.max(20, _y(end, startHour) - top),
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.16),
            border: Border.all(color: cs.primary, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: AlignmentDirectional.topStart,
          child: Text(
            hmRange(start, end),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
        ),
      ),
    );
  }

  /// The slot being swept, with its snapped times.
  Widget _selection(ColorScheme cs, int startHour) {
    final a = math.min(_selA, _selB), b = math.max(_selA, _selB);
    final start = _timeAt(a, startHour);
    var end = _timeAt(b, startHour, ceil: true);
    if (!end.isAfter(start)) end = start.add(Duration(minutes: _snap));
    final top = _y(start, startHour);
    return Positioned(
      top: top,
      left: 3,
      right: 3,
      height: _y(end, startHour) - top,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.16),
            border: Border.all(color: cs.primary, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: AlignmentDirectional.topStart,
          child: Text(
            hmRange(start, end),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
        ),
      ),
    );
  }

  static void _assignLanes(List<_Placed> placed) {
    var cluster = <_Placed>[];
    DateTime? clusterEnd;
    void close() {
      final n = cluster.fold<int>(0, (m, p) => math.max(m, p.lane + 1));
      for (final p in cluster) {
        p.lanes = n;
      }
      cluster = [];
    }

    for (final p in placed) {
      if (clusterEnd != null && !p.item.startAt.isBefore(clusterEnd)) {
        close();
        clusterEnd = null;
      }
      final laneEnds = <int, DateTime>{};
      for (final q in cluster) {
        final e = laneEnds[q.lane];
        if (e == null || q.item.endAt.isAfter(e)) {
          laneEnds[q.lane] = q.item.endAt;
        }
      }
      var lane = 0;
      while (laneEnds[lane] != null &&
          laneEnds[lane]!.isAfter(p.item.startAt)) {
        lane++;
      }
      p.lane = lane;
      cluster.add(p);
      if (clusterEnd == null || p.item.endAt.isAfter(clusterEnd)) {
        clusterEnd = p.item.endAt;
      }
    }
    close();
  }

  Widget _band({
    required double top,
    required double bottom,
    required Color color,
    required Color fg,
    required String label,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    final h = math.max(14.0, bottom - top);
    return Positioned(
      top: top,
      left: 2,
      right: 2,
      height: h,
      // Swallows taps and presses either way, so a break or a slot busy
      // elsewhere never opens a new appointment underneath it.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap ?? () {},
        onLongPress: () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: h < 18
              ? null
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 12, color: fg),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: fg),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _card(
    BuildContext context,
    _Placed p,
    AgendaResource? c,
    double colWidth,
    int startHour,
    bool online, {
    bool conflict = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final r = p.reservation;
    final it = p.item;
    final top = _y(it.startAt, startHour);
    final stretching = it.id != null && _resizeItem == it.id;
    final minHeight = _hourHeight * _snap / 60 - 2;
    final baseHeight = _y(it.endAt, startHour) - top - 2;
    final height = math.max(
      24.0,
      stretching ? math.max(minHeight, baseHeight + _resizeDy) : baseHeight,
    );
    final laneWidth = (colWidth - 6) / p.lanes;
    final accent = c == null ? cs.outline : resourceColor(c.color, c.id, cs);
    final tint = c == null ? cs.surfaceContainerHighest : resourceTint(c, cs);
    final inProgress = r.timeStatus() == BookingTimeStatus.inProgress;
    final converted = r.status == ReservationStatus.converted;
    final icon = _statusIcon(r.status);
    final movable = online && c != null && (r.isEditable || converted);
    final timeEnd = stretching
        ? it.startAt.add(
            Duration(
              minutes:
                  (((height + 2) / _hourHeight * 60) / _snap).round() * _snap,
            ),
          )
        : it.endAt;
    final ink = cs.onSurface;

    final card = Opacity(
      opacity: converted ? 0.7 : 1,
      child: Material(
        color: tint,
        elevation: inProgress ? 3 : 0,
        // An overlap to sort out: outlined so it reads at a glance.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: conflict
              ? BorderSide(color: cs.tertiary, width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showReservationDetail(context, r),
          child: Container(
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: accent, width: 4),
              ),
            ),
            padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 6, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      // Too short for a third line: the service rides on the
                      // time line instead.
                      child: Text(
                        height > 54
                            ? hmRange(it.startAt, timeEnd)
                            : '${hmRange(it.startAt, timeEnd)} · ${it.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: ink.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                    if (conflict)
                      Icon(Icons.layers_rounded, size: 14, color: cs.tertiary)
                    else if (icon != null)
                      Icon(icon, size: 13, color: ink.withValues(alpha: 0.7)),
                  ],
                ),
                if (height > 34)
                  Text(
                    r.customerLabel.isEmpty ? r.code : r.customerLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: ink,
                    ),
                  ),
                if (height > 54)
                  Text(
                    it.name,
                    maxLines: height > 76 ? 2 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: ink.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // The bottom edge stretches the service; the rest of the card drags it.
    final withHandle = !movable || it.id == null
        ? card
        : Stack(
            children: [
              Positioned.fill(child: card),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 14,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpDown,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: (_) => setState(() {
                      _resizeItem = it.id;
                      _resizeDy = 0;
                    }),
                    onVerticalDragUpdate: (d) =>
                        setState(() => _resizeDy += d.delta.dy),
                    onVerticalDragEnd: (_) => _finishResize(
                      it,
                      timeEnd,
                      tentative: r.status == ReservationStatus.booked,
                    ),
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 4,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );

    return Positioned(
      top: top + 1,
      height: height,
      left: 3 + p.lane * laneWidth,
      width: laneWidth - 2,
      child: !movable
          ? withHandle
          : _mouse
          // Mouse: grab and go, like a desktop agenda.
          ? Draggable<_Drag>(
              data: _Drag(r, it, c.id),
              dragAnchorStrategy: childDragAnchorStrategy,
              onDragEnd: (_) => setState(() => _ghost = null),
              feedback: SizedBox(
                width: laneWidth - 2,
                height: height,
                // See-through, so the landing time outlined beneath shows.
                child: Opacity(opacity: 0.45, child: card),
              ),
              childWhenDragging: Opacity(opacity: 0.25, child: card),
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: withHandle,
              ),
            )
          // Finger: a short hold first, so scrolling never moves a card.
          : LongPressDraggable<_Drag>(
              data: _Drag(r, it, c.id),
              delay: const Duration(milliseconds: 350),
              dragAnchorStrategy: childDragAnchorStrategy,
              onDragStarted: HapticFeedback.mediumImpact,
              onDragEnd: (_) => setState(() => _ghost = null),
              feedback: SizedBox(
                width: laneWidth - 2,
                height: height,
                // See-through, so the landing time outlined beneath shows.
                child: Opacity(opacity: 0.45, child: card),
              ),
              childWhenDragging: Opacity(opacity: 0.25, child: card),
              child: withHandle,
            ),
    );
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  /// Opens the quick panel for the slot at [y0] (a tap) or [y0]..[y1] (a
  /// sweep). A tap books the default length; the services set the real end.
  Future<void> _openQuick(
    AgendaResource c,
    List<AgendaResource?> columns,
    int startHour,
    double y0,
    double? y1,
  ) async {
    final start = _timeAt(y0, startHour);
    var end = y1 == null
        ? start.add(Duration(minutes: math.max(30, _snap)))
        : _timeAt(y1, startHour, ceil: true);
    if (!end.isAfter(start)) end = start.add(Duration(minutes: _snap));
    setState(() {
      _selColumn = c.id;
      _selA = _y(start, startHour);
      _selB = _y(end, startHour);
    });
    await _showQuick(
      c,
      columns.whereType<AgendaResource>().toList(),
      start,
      end,
    );
  }

  Future<void> _showQuick(
    AgendaResource c,
    List<AgendaResource> resources,
    DateTime start,
    DateTime end,
  ) async {
    final booking = widget.booking;
    final result = await showReservationPanel(
      context,
      start: start,
      end: end,
      resourceId: c.id,
      lines: booking?.lines() ?? const [],
      customer: booking?.customer,
      stepMinutes: _snap,
      // The outline on the grid follows what the panel will book.
      onRangeChanged: (segments) {
        if (!mounted) return;
        setState(() {
          _selColumn = null;
          _preview = segments;
          _previewDefault = c.id;
        });
      },
    );
    if (!mounted) return;
    setState(() {
      _selColumn = null;
      _preview = const [];
    });
    if (result is Reservation) {
      if (booking != null) {
        // Booked, not sold: the cart empties and the till comes back.
        booking.onBooked();
        Navigator.of(context).maybePop();
        return;
      }
      // "Next free times" may have moved it to another day.
      if (dayStartOf(result.startAt) != _date) _goTo(result.startAt);
    }
  }

  /// "New appointment" from the toolbar: the next step from now today (or
  /// the opening hour another day) on the first person.
  void _newFromButton(AgendaDay? day) {
    final columns = day == null
        ? const <AgendaResource>[]
        : _columns(day).whereType<AgendaResource>().toList();
    final now = DateTime.now();
    final DateTime start;
    if (dayStartOf(now) == _date) {
      final m = (now.minute / _snap).ceil() * _snap;
      start = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
      ).add(Duration(minutes: m));
    } else {
      start = (day?.openHours.isNotEmpty ?? false)
          ? day!.openHours.first.start
          : _date.add(const Duration(hours: 9));
    }
    final end = start.add(Duration(minutes: math.max(30, _snap)));
    if (columns.isEmpty) {
      showReservationPanel(
        context,
        start: start,
        end: end,
        lines: widget.booking?.lines() ?? const [],
        customer: widget.booking?.customer,
        stepMinutes: _snap,
      );
      return;
    }
    _showQuick(columns.first, columns, start, end);
  }

  Future<void> _drop(_Drag d, AgendaResource target, DateTime start) async {
    final r = d.reservation;
    if (start == d.item.startAt && target.id == d.fromResourceId) return;
    final service = ref.read(reservationServiceProvider);
    final changesResource = target.id != d.fromResourceId;
    final tentative = r.status == ReservationStatus.booked;
    if (r.items.length == 1) {
      // The whole reservation moves; onto another column if dropped there.
      await runReservationWrite(
        ref,
        context,
        () => service.move(
          r.id,
          startAt: start,
          resourceId: changesResource ? target.id : null,
        ),
        successKey: 'res_moved',
        overbook: () => service.move(
          r.id,
          startAt: start,
          resourceId: changesResource ? target.id : null,
          overbook: true,
        ),
        // An unconfirmed booking may be dropped over another, flagged.
        allowOverlap: tentative
            ? () => service.move(
                r.id,
                startAt: start,
                resourceId: changesResource ? target.id : null,
                allowOverlap: true,
              )
            : null,
      );
    } else if (d.item.id != null) {
      // One service of several moves on its own.
      final ids = [
        for (final id in d.item.resourceIds)
          if (id == d.fromResourceId) target.id else id,
      ];
      await runReservationWrite(
        ref,
        context,
        () => service.moveItem(
          d.item.id!,
          startAt: start,
          endAt: start.add(d.item.endAt.difference(d.item.startAt)),
          resourceIds: changesResource ? ids : null,
        ),
        successKey: 'res_moved',
        overbook: () => service.moveItem(
          d.item.id!,
          startAt: start,
          endAt: start.add(d.item.endAt.difference(d.item.startAt)),
          resourceIds: changesResource ? ids : null,
          overbook: true,
        ),
        allowOverlap: tentative
            ? () => service.moveItem(
                d.item.id!,
                startAt: start,
                endAt: start.add(d.item.endAt.difference(d.item.startAt)),
                resourceIds: changesResource ? ids : null,
                allowOverlap: true,
              )
            : null,
      );
    }
  }

  Future<void> _finishResize(
    ReservationItem it,
    DateTime newEnd, {
    bool tentative = false,
  }) async {
    setState(() {
      _resizeItem = null;
      _resizeDy = 0;
    });
    if (newEnd == it.endAt || !newEnd.isAfter(it.startAt)) return;
    final service = ref.read(reservationServiceProvider);
    await runReservationWrite(
      ref,
      context,
      () => service.moveItem(it.id!, startAt: it.startAt, endAt: newEnd),
      successKey: 'res_saved',
      overbook: () => service.moveItem(
        it.id!,
        startAt: it.startAt,
        endAt: newEnd,
        overbook: true,
      ),
      allowOverlap: tentative
          ? () => service.moveItem(
              it.id!,
              startAt: it.startAt,
              endAt: newEnd,
              allowOverlap: true,
            )
          : null,
    );
  }

  Future<void> _blockTapped(AgendaBlock b) async {
    final l10n = AppLocalizations.of(context)!;
    final remove = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          b.title ?? l10n.translate('res_block_${b.kind.toLowerCase()}'),
        ),
        content: Text(hmRange(b.startAt, b.endAt)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.translate('close')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.translate('res_delete_block')),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    final service = ref.read(reservationServiceProvider);
    await runReservationWrite(
      ref,
      context,
      () => service.deleteBlock(b.id),
      successKey: 'res_saved',
    );
    if (mounted) await pullAgendaWeekFromWidget(ref, _date);
  }

  // ── List ─────────────────────────────────────────────────────────────────

  Widget _list(BuildContext context, AgendaDay day) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (day.reservations.isEmpty) {
      return Center(
        child: Text(
          l10n.translate('res_no_results'),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: day.reservations.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) =>
          ReservationTile(reservation: day.reservations[i]),
    );
  }
}

/// A reservation in a list: time, customer, services, status, value.
class ReservationTile extends ConsumerWidget {
  final Reservation reservation;
  final bool showDate;
  const ReservationTile({
    super.key,
    required this.reservation,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final money = ref.watch(currencyFormatterProvider);
    final r = reservation;
    final colors = reservationStatusColors(r.status, cs);
    return ListTile(
      onTap: () => showReservationDetail(context, r),
      leading: SizedBox(
        width: showDate ? 84 : 52,
        // Scales down rather than overflowing the tile's 56px.
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showDate)
                Text(
                  DateFormat('dd/MM').format(r.startAt),
                  style: const TextStyle(fontSize: 11),
                ),
              Text(
                hm(r.startAt),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                hm(r.endAt),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
      title: Text(
        r.customerLabel.isEmpty ? r.code : r.customerLabel,
        style: TextStyle(
          decoration: r.holdsSlot ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Text(
        r.items.map((i) => i.name).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              reservationStatusLabel(r.status, l10n),
              style: TextStyle(fontSize: 11, color: colors.fg),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            money.format(r.value),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Hour lines, fainter quarter lines, and closed time shaded.
class _ColumnPainter extends CustomPainter {
  final double hourHeight;
  final Color line;
  final Color closed;

  /// Open windows as (top, bottom) in px; null = do not shade.
  final List<(double, double)>? open;

  _ColumnPainter({
    required this.hourHeight,
    required this.line,
    required this.closed,
    required this.open,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (open != null) {
      final shade = Paint()..color = closed;
      var y = 0.0;
      final windows = [...open!]..sort((a, b) => a.$1.compareTo(b.$1));
      for (final (top, bottom) in windows) {
        if (top > y) {
          canvas.drawRect(Rect.fromLTRB(0, y, size.width, top), shade);
        }
        y = math.max(y, bottom);
      }
      if (y < size.height) {
        canvas.drawRect(Rect.fromLTRB(0, y, size.width, size.height), shade);
      }
    }
    final hour = Paint()
      ..color = line
      ..strokeWidth = 0.8;
    final quarter = Paint()
      ..color = line.withValues(alpha: line.a * 0.35)
      ..strokeWidth = 0.5;
    for (var y = 0.0; y <= size.height; y += hourHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hour);
      for (var q = 1; q < 4; q++) {
        final qy = y + hourHeight * q / 4;
        if (qy < size.height) {
          canvas.drawLine(Offset(0, qy), Offset(size.width, qy), quarter);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ColumnPainter old) =>
      old.open != open || old.line != line || old.closed != closed;
}

/// Find a reservation by code, name or phone: online search, else the cache.
class _SearchDialog extends ConsumerStatefulWidget {
  const _SearchDialog();

  @override
  ConsumerState<_SearchDialog> createState() => _SearchDialogState();
}

class _SearchDialogState extends ConsumerState<_SearchDialog> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Reservation>? _results;
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      if (text.trim().length < 2) {
        setState(() => _results = null);
        return;
      }
      setState(() => _loading = true);
      final found = await ref.read(reservationServiceProvider).search(text);
      if (!mounted || _q.text != text) return;
      setState(() {
        _results = found;
        _loading = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.translate('search')),
      content: SizedBox(
        width: 520,
        height: 420,
        child: Column(
          children: [
            TextField(
              controller: _q,
              autofocus: true,
              onChanged: _changed,
              decoration: InputDecoration(
                hintText: l10n.translate('res_search_hint'),
                prefixIcon: const Icon(Icons.search_rounded),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _results == null
                  ? const SizedBox.shrink()
                  : _results!.isEmpty
                  ? Center(child: Text(l10n.translate('res_no_results')))
                  : ListView.builder(
                      itemCount: _results!.length,
                      itemBuilder: (_, i) => ReservationTile(
                        reservation: _results![i],
                        showDate: true,
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.translate('close')),
        ),
      ],
    );
  }
}

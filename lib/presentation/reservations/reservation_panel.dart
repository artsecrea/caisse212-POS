import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../data/database/app_database.dart';
import '../../domain/models/reservation_models.dart';
import '../../providers/catalogue_repository.dart';
import '../../providers/database_providers.dart';
import '../../providers/reservation_providers.dart';
import '../../providers/resource_providers.dart';
import '../../services/reservation_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/currency_formatter.dart';
import '../../utils/customer_display.dart';
import 'reservation_actions.dart';
import 'side_panel.dart';

/// Category names for grouping the services list.
final serviceCategoryNamesProvider = FutureProvider<Map<int, String>>((
  ref,
) {
  return ref.watch(catalogueRepositoryProvider).categoryNamesById();
});

/// One line of the reservation being built: a timed service on a person or
/// room, or a retail product that only rides along to the till.
class BasketLine {
  int? itemId;
  final int productId;
  final int? variantId;
  final String name;
  double quantity;

  /// Agreed price when it is not the catalogue's (a cart override, a booking
  /// made at an older price); null = the catalogue's.
  double? unitPrice;
  final double catalogPrice;

  /// Null for a retail product.
  final int? durationMinutes;
  DateTime? start;
  DateTime? end;

  /// Null = let the server pick one.
  int? resourceId;

  /// Staff set this line's time by hand; it no longer follows the one before.
  bool pinned;

  BasketLine({
    this.itemId,
    required this.productId,
    this.variantId,
    required this.name,
    this.quantity = 1,
    this.unitPrice,
    required this.catalogPrice,
    this.durationMinutes,
    this.start,
    this.end,
    this.resourceId,
    this.pinned = false,
  });

  bool get timed => (durationMinutes ?? 0) > 0;
  double get price => (unitPrice ?? catalogPrice) * quantity;
  Duration get length => end != null && start != null
      ? end!.difference(start!)
      : Duration(minutes: durationMinutes ?? 0);

  factory BasketLine.service(Product p, {int? resourceId}) => BasketLine(
    productId: p.id,
    name: p.name,
    catalogPrice: p.finalPrice,
    durationMinutes: p.planDurationMinutes,
    resourceId: resourceId,
  );

  factory BasketLine.retail(Product p) =>
      BasketLine(productId: p.id, name: p.name, catalogPrice: p.finalPrice);
}

/// What the panel is about to book, for the agenda to outline: one piece per
/// service, in its own column. A null [resourceId] = not chosen yet.
typedef PreviewSegment = ({int? resourceId, DateTime start, DateTime end});

/// A customer handed in by the caller (the cart's, a reservation's).
class PanelCustomer {
  final int? localId;
  final String? name;
  final String? phone;
  const PanelCustomer({this.localId, this.name, this.phone});
}

enum _Mode { appointment, block }

/// Opens the reservation panel beside the agenda. Returns the saved
/// reservation, `true` for a saved block, or null when dismissed.
Future<Object?> showReservationPanel(
  BuildContext context, {
  Reservation? existing,
  required DateTime start,
  DateTime? end,
  int? resourceId,
  List<BasketLine> lines = const [],
  PanelCustomer? customer,
  int stepMinutes = 15,
  void Function(List<PreviewSegment> segments)? onRangeChanged,
}) {
  return showSidePanel<Object>(
    context,
    ReservationPanel(
      existing: existing,
      start: start,
      end: end,
      resourceId: resourceId,
      initialLines: lines,
      customer: customer,
      stepMinutes: stepMinutes,
      onRangeChanged: onRangeChanged,
    ),
    width: 480,
  );
}

/// Create or edit a reservation the way salon agendas do it: beside the day,
/// with the time and the person already set by where staff tapped.
///
///   * every service has its own time and person (a colour by Leila while
///     Sarah does the cut); untouched services follow one another;
///   * retail products can be added, but at least one service is required;
///   * an overlap with another booking is shown before saving, and such a
///     booking goes in unconfirmed, to be sorted out on the agenda;
///   * "next free times" searches the week for the whole basket.
class ReservationPanel extends ConsumerStatefulWidget {
  final Reservation? existing;
  final DateTime start;
  final DateTime? end;
  final int? resourceId;
  final List<BasketLine> initialLines;
  final PanelCustomer? customer;
  final int stepMinutes;
  final void Function(List<PreviewSegment> segments)? onRangeChanged;

  const ReservationPanel({
    super.key,
    this.existing,
    required this.start,
    this.end,
    this.resourceId,
    this.initialLines = const [],
    this.customer,
    this.stepMinutes = 15,
    this.onRangeChanged,
  });

  @override
  ConsumerState<ReservationPanel> createState() => _ReservationPanelState();
}

class _ReservationPanelState extends ConsumerState<ReservationPanel> {
  _Mode _mode = _Mode.appointment;
  late DateTime _start = widget.start;
  late DateTime _blockEnd =
      widget.end ?? widget.start.add(Duration(minutes: widget.stepMinutes * 2));
  late int? _resourceId = widget.resourceId;
  late final List<BasketLine> _lines = [...widget.initialLines];

  // Customer
  final _customerQuery = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  List<Customer> _matches = const [];
  int? _localCustomerId;
  bool _customerChosen = false;
  Timer? _searchDebounce;

  // Catalogue
  bool _showRetail = false;
  final _catalogQuery = TextEditingController();

  // Server checks
  Timer? _checkDebounce;
  bool _checking = false;
  AvailabilitySlot? _slot;
  List<AvailabilitySlot> _nearby = const [];
  bool _searchingNext = false;
  List<AvailabilitySlot>? _next;

  // Block
  String _blockKind = 'BREAK';
  final _blockTitle = TextEditingController();

  final _note = TextEditingController();
  bool _confirmed = false;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _start = e.startAt;
      _note.text = e.note ?? '';
      _confirmed = e.status != ReservationStatus.booked;
      _setCustomer(name: e.customer?.name, phone: e.customer?.phone);
      for (final it in e.items) {
        _lines.add(
          BasketLine(
            itemId: it.id,
            productId: it.productId,
            variantId: it.variantId,
            name: it.name,
            quantity: it.quantity,
            unitPrice: it.unitPrice,
            catalogPrice: it.unitPrice,
            durationMinutes: it.timed ? it.durationMinutes : null,
            start: it.timed ? it.startAt : null,
            end: it.timed ? it.endAt : null,
            resourceId: it.resourceIds.firstOrNull,
            pinned: true,
          ),
        );
      }
    } else if (widget.customer != null) {
      final c = widget.customer!;
      _localCustomerId = c.localId;
      _setCustomer(name: c.name, phone: c.phone);
    }
    for (final l in _lines) {
      if (l.timed && l.resourceId == null && !_isEdit) {
        l.resourceId = _resourceId;
      }
    }
    _relayout();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleCheck());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _checkDebounce?.cancel();
    for (final c in [
      _customerQuery,
      _name,
      _phone,
      _catalogQuery,
      _blockTitle,
      _note,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Timing ──────────────────────────────────────────────────────────────

  List<BasketLine> get _timed => _lines.where((l) => l.timed).toList();
  List<BasketLine> get _retail => _lines.where((l) => !l.timed).toList();

  /// Unpinned services follow one another from [_start]; pinned ones stay.
  void _relayout() {
    var t = _start;
    for (final l in _timed) {
      if (!l.pinned || l.start == null) {
        l.start = t;
        l.end = t.add(Duration(minutes: l.durationMinutes!));
      }
      t = l.end!;
    }
  }

  DateTime get _rangeStart => _timed.isEmpty
      ? _start
      : _timed.map((l) => l.start!).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get _rangeEnd => _timed.isEmpty
      ? (widget.end ?? _start.add(Duration(minutes: widget.stepMinutes * 2)))
      : _timed.map((l) => l.end!).reduce((a, b) => a.isAfter(b) ? a : b);

  /// Shifts everything (pinned services too) so the booking starts at [t].
  void _moveAllTo(DateTime t, {List<SlotItem>? fromSlot}) {
    final delta = t.difference(_rangeStart);
    setState(() {
      _blockEnd = _blockEnd.add(t.difference(_start));
      _start = t;
      for (final l in _timed) {
        l.start = l.start!.add(delta);
        l.end = l.end!.add(delta);
      }
      if (fromSlot != null) {
        final timed = _timed;
        for (var i = 0; i < timed.length && i < fromSlot.length; i++) {
          timed[i]
            ..start = fromSlot[i].startAt
            ..end = fromSlot[i].endAt
            ..resourceId =
                fromSlot[i].resourceIds.firstOrNull ?? timed[i].resourceId;
        }
      }
      _next = null;
    });
    _changed(recheck: fromSlot == null);
  }

  void _changed({bool recheck = true}) {
    setState(() {
      if (recheck) {
        _slot = null;
        _nearby = const [];
      }
    });
    if (recheck) _scheduleCheck();
  }

  /// The basket is a plain chain on one person: the server can say whether
  /// it fits exactly here. Hand-placed services are checked on save.
  bool get _simpleChain {
    final t = _timed;
    if (t.isEmpty || t.any((l) => l.pinned)) return false;
    return t.map((l) => l.resourceId).toSet().length == 1;
  }

  void _scheduleCheck() {
    _checkDebounce?.cancel();
    if (!_simpleChain || !ref.read(canReserveProvider)) return;
    _checkDebounce = Timer(const Duration(milliseconds: 300), _check);
  }

  Future<void> _check() async {
    final t = _timed;
    final rid = t.first.resourceId;
    final start = _rangeStart;
    setState(() => _checking = true);
    try {
      final slots = await ref
          .read(reservationServiceProvider)
          .availability(
            productIds: [for (final l in t) l.productId],
            date: dayStartOf(start),
            resourceIds: rid == null ? null : [rid],
            step: widget.stepMinutes,
            excludeReservationId: widget.existing?.id,
          );
      if (!mounted || start != _rangeStart) return;
      final exact = slots.where((s) => s.startAt == start).firstOrNull;
      final now = DateTime.now();
      setState(() {
        _slot = exact;
        _nearby = exact != null
            ? const []
            : (slots.where((s) => s.startAt.isAfter(now)).toList()..sort(
                    (a, b) => a.startAt
                        .difference(start)
                        .inMinutes
                        .abs()
                        .compareTo(b.startAt.difference(start).inMinutes.abs()),
                  ))
                  .take(6)
                  .toList();
        // Auto-assigned services take the person availability promised.
        if (exact != null) {
          for (var i = 0; i < t.length && i < exact.items.length; i++) {
            t[i].resourceId ??= exact.items[i].resourceIds.firstOrNull;
          }
        }
      });
    } catch (_) {
      // Not knowing is not a refusal: the save still decides.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _findNext() async {
    final t = _timed;
    if (t.isEmpty) return;
    final rids = t.map((l) => l.resourceId).whereType<int>().toSet();
    setState(() => _searchingNext = true);
    try {
      final slots = await ref
          .read(reservationServiceProvider)
          .availability(
            productIds: [for (final l in t) l.productId],
            date: dayStartOf(_rangeStart),
            days: 7,
            resourceIds: rids.length == 1 ? rids.toList() : null,
            step: widget.stepMinutes,
            excludeReservationId: widget.existing?.id,
          );
      final now = DateTime.now();
      if (mounted) {
        setState(
          () => _next = slots.where((s) => s.startAt.isAfter(now)).toList(),
        );
      }
    } catch (e) {
      if (mounted) reservationToast('$e', isError: true);
    } finally {
      if (mounted) setState(() => _searchingNext = false);
    }
  }

  // ── Customer ────────────────────────────────────────────────────────────

  void _setCustomer({String? name, String? phone}) {
    if ((name ?? '').isEmpty && (phone ?? '').isEmpty) return;
    _name.text = name ?? '';
    _phone.text = phone ?? '';
    _customerChosen = true;
  }

  void _searchCustomers(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 200), () async {
      final text = q.trim().toLowerCase();
      if (text.length < 2) {
        if (mounted) setState(() => _matches = const []);
        return;
      }
      final rows = await ref
          .read(customerRepositoryProvider)
          .searchByNameOrPhone(text);
      if (mounted && _customerQuery.text == q) setState(() => _matches = rows);
    });
  }

  bool get _hasCustomer =>
      _customerChosen &&
      (_name.text.trim().isNotEmpty || _phone.text.trim().isNotEmpty);

  // ── Overlaps (from the cached day) ──────────────────────────────────────

  /// Other bookings sharing a person or room with this basket, beyond what
  /// that resource can hold at once.
  List<({BasketLine line, Reservation other, ReservationItem item})> _overlaps(
    AgendaDay day,
    Map<int, AgendaResource> resources,
  ) {
    final out =
        <({BasketLine line, Reservation other, ReservationItem item})>[];
    for (final l in _timed) {
      final rid = l.resourceId;
      if (rid == null) continue;
      final hits = [
        for (final r in day.reservations)
          if (r.holdsSlot && r.id != widget.existing?.id)
            for (final it in r.items)
              if (it.timed &&
                  it.resourceIds.contains(rid) &&
                  it.startAt.isBefore(l.end!) &&
                  it.endAt.isAfter(l.start!))
                (line: l, other: r, item: it),
      ];
      final capacity = resources[rid]?.capacity ?? 1;
      if (hits.length >= capacity) out.addAll(hits);
    }
    return out;
  }

  // ── Save ────────────────────────────────────────────────────────────────

  Future<void> _save(bool overlapping) async {
    setState(() => _saving = true);
    final service = ref.read(reservationServiceProvider);
    Object? result;
    if (_mode == _Mode.block) {
      final ok = await runReservationWrite(ref, context, () async {
        await service.addBlock(
          resourceId: _resourceId!,
          kind: _blockKind,
          title: _blockTitle.text,
          startAt: _start,
          endAt: _blockEnd,
        );
        return true;
      }, successKey: 'res_saved');
      if (ok == true && mounted) {
        final visible = ref.read(agendaVisibleDateProvider);
        if (visible != null) await pullAgendaWeekFromWidget(ref, visible);
      }
      result = ok;
    } else {
      // Unconfirmed bookings may stack; confirmed ones may not.
      final tentative = _isEdit
          ? widget.existing!.status == ReservationStatus.booked
          : !_confirmed || overlapping;
      final draft = await _draft(allowOverlap: tentative && overlapping);
      final forced = await _draft(overbook: true);
      final stacked = await _draft(allowOverlap: true, tentative: true);
      if (!mounted) return;
      Future<Reservation> send(ReservationDraft d) =>
          _isEdit ? service.update(widget.existing!.id, d) : service.create(d);
      result = await runReservationWrite(
        ref,
        context,
        () => send(draft),
        successKey: 'res_saved',
        overbook: () => send(forced),
        allowOverlap: tentative || !_isEdit ? () => send(stacked) : null,
      );
      if (result == null && mounted) _changed();
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (result != null) Navigator.of(context).pop(result);
  }

  Future<ReservationDraft> _draft({
    bool overbook = false,
    bool allowOverlap = false,
    bool tentative = false,
  }) async {
    // A customer row the server knows can go by id when there is no phone;
    // otherwise name + phone, which the server matches or creates.
    int? customerId;
    if (_phone.text.trim().isEmpty && _localCustomerId != null) {
      final row = await ref
          .read(customerRepositoryProvider)
          .getById(_localCustomerId!);
      if (row != null && row.isSynced) customerId = row.id;
    }
    return ReservationDraft(
      startAt: _rangeStart,
      customerId: customerId,
      customerName: _name.text,
      customerPhone: _phone.text,
      note: _note.text,
      status: _isEdit
          ? null
          : (_confirmed && !allowOverlap && !tentative
                ? ReservationStatus.confirmed
                : ReservationStatus.booked),
      overbook: overbook,
      allowOverlap: allowOverlap,
      items: [
        for (final l in [..._timed, ..._retail])
          ReservationDraftItem(
            id: l.itemId,
            productId: l.productId,
            variantId: l.variantId,
            quantity: l.quantity,
            unitPrice: l.unitPrice,
            timed: l.timed,
            startAt: l.start,
            endAt: l.end,
            // Only a person who can do the service; else the server picks.
            resourceIds:
                l.resourceId != null &&
                    _allowedFor(l).any((r) => r.id == l.resourceId)
                ? [l.resourceId!]
                : const [],
          ),
      ],
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  String? _lastReported;

  void _reportRange() {
    final List<PreviewSegment> segments = _mode == _Mode.block || _timed.isEmpty
        ? [
            (
              resourceId: _resourceId,
              start: _start,
              end: _mode == _Mode.block ? _blockEnd : _rangeEnd,
            ),
          ]
        : [
            for (final l in _timed)
              (resourceId: l.resourceId, start: l.start!, end: l.end!),
          ];
    final key = segments.join('|');
    if (key == _lastReported) return;
    _lastReported = key;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.onRangeChanged?.call(segments),
    );
  }

  Map<int, AgendaResource> _shownResources = const {};

  /// Who may take [l]: its pool's staff (or its pool, when the pool is only
  /// rooms), or any staff when the service has no pool. The server rule: a
  /// service needs one resource of each type in its pool; the rest it fills.
  List<AgendaResource> _allowedFor(BasketLine l) {
    final pool = ref.read(servicePoolsProvider).valueOrNull?[l.productId];
    final all = _shownResources.values;
    if (pool == null || pool.isEmpty) {
      return all.where((r) => r.isStaff).toList();
    }
    final inPool = all.where((r) => pool.contains(r.id)).toList();
    final staff = inPool.where((r) => r.isStaff).toList();
    return staff.isNotEmpty ? staff : inPool;
  }

  Map<int, AgendaResource> _resources(AgendaDay? day) {
    final list = (day?.resources.isNotEmpty ?? false)
        ? day!.resources
        : [
            for (final r
                in ref.watch(resourcesProvider).valueOrNull ??
                    const <Resource>[])
              AgendaResource(
                id: r.id,
                name: r.name,
                type: r.type,
                color: r.color,
                sortOrder: r.sortOrder,
                capacity: r.capacity,
              ),
          ];
    return {for (final r in list) r.id: r};
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final online = ref.watch(canReserveProvider);
    final day = ref
        .watch(agendaDayProvider(dayStartOf(_rangeStart)))
        .valueOrNull;
    final resources = _resources(day);
    _shownResources = resources;
    ref.watch(servicePoolsProvider);
    final overlaps = day == null
        ? const <({BasketLine line, Reservation other, ReservationItem item})>[]
        : _overlaps(day, resources);
    final overlapping = overlaps.isNotEmpty;
    _reportRange();

    final locale = Localizations.localeOf(context).toLanguageTag();
    final dayLabel = DateFormat('EEEE d MMMM', locale).format(_rangeStart);
    final canSave =
        online &&
        !_saving &&
        (_mode == _Mode.block
            ? _resourceId != null && _blockEnd.isAfter(_start)
            : (_timed.isNotEmpty && _hasCustomer));

    final title = _isEdit
        ? 'edit_reservation'
        : (_mode == _Mode.block ? 'res_add_block' : 'new_reservation');
    return Column(
      children: [
        SidePanelHeader(
          title: l10n.translate(title),
          subtitle: dayLabel.isEmpty
              ? dayLabel
              : dayLabel[0].toUpperCase() + dayLabel.substring(1),
        ),
        if (!_isEdit && _lines.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: SegmentedButton<_Mode>(
              segments: [
                ButtonSegment(
                  value: _Mode.appointment,
                  icon: const Icon(Icons.event_available_rounded, size: 18),
                  label: Text(l10n.translate('res_appointment')),
                ),
                ButtonSegment(
                  value: _Mode.block,
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: Text(l10n.translate('res_add_block')),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: _mode == _Mode.block
                ? _blockFields(theme, l10n, resources)
                : [
                    _label(theme, l10n.translate('customer')),
                    _customerField(theme, l10n),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _label(theme, l10n.translate('res_services')),
                        ),
                        _startChip(cs),
                      ],
                    ),
                    for (final l in _timed)
                      _serviceRow(theme, l10n, l, resources),
                    if (_timed.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l10n.translate('res_need_service'),
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                    if (_retail.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _label(theme, l10n.translate('res_products')),
                      for (final l in _retail) _retailRow(theme, l),
                    ],
                    _totals(theme, l10n),
                    const SizedBox(height: 6),
                    if (overlapping)
                      _overlapBox(theme, l10n, overlaps, resources)
                    else
                      _availabilityLine(theme, l10n),
                    _nextFree(theme, l10n),
                    const SizedBox(height: 12),
                    _catalog(theme, l10n),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _note,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: l10n.translate('res_note'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    if (!_isEdit)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _confirmed && !overlapping,
                        title: Text(l10n.translate('res_confirmed_now')),
                        subtitle: overlapping
                            ? Text(l10n.translate('res_overlap_unconfirmed'))
                            : null,

                        onChanged: overlapping
                            ? null
                            : (v) => setState(() => _confirmed = v),
                      ),
                  ],
          ),
        ),
        if (!online)
          Container(
            width: double.infinity,
            color: cs.errorContainer,
            padding: const EdgeInsets.all(10),
            child: Text(
              l10n.translate('reconnect_to_book'),
              style: TextStyle(color: cs.onErrorContainer),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: overlapping
                  ? FilledButton.styleFrom(
                      backgroundColor: cs.tertiary,
                      foregroundColor: cs.onTertiary,
                    )
                  : null,
              onPressed: canSave ? () => _save(overlapping) : null,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _mode == _Mode.block
                          ? l10n.translate('res_add_block')
                          : '${l10n.translate(_isEdit ? 'save' : (overlapping ? 'res_create_pending' : 'res_create'))}'
                                ' · ${hmRange(_rangeStart, _rangeEnd)}',
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        letterSpacing: 0.8,
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Widget _startChip(ColorScheme cs) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: ActionChip(
      avatar: Icon(
        Icons.schedule_rounded,
        size: 18,
        color: cs.onPrimaryContainer,
      ),
      backgroundColor: cs.primaryContainer,
      side: BorderSide.none,
      label: Text(
        hmRange(_rangeStart, _rangeEnd),
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: cs.onPrimaryContainer,
        ),
      ),
      onPressed: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(_rangeStart),
        );
        if (t == null) return;
        final s = _rangeStart;
        _moveAllTo(DateTime(s.year, s.month, s.day, t.hour, t.minute));
      },
    ),
  );

  Widget _serviceRow(
    ThemeData theme,
    AppLocalizations l10n,
    BasketLine l,
    Map<int, AgendaResource> resources,
  ) {
    final cs = theme.colorScheme;
    final money = ref.watch(currencyFormatterProvider);
    final res = l.resourceId == null ? null : resources[l.resourceId];
    final color = res == null
        ? cs.outline
        : resourceColor(res.color, res.id, cs);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
      decoration: BoxDecoration(
        color: res == null ? cs.surfaceContainerHighest : resourceTint(res, cs),
        borderRadius: BorderRadius.circular(10),
        border: BorderDirectional(start: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(l.start!),
              );
              if (t == null) return;
              final s = l.start!;
              final ns = DateTime(s.year, s.month, s.day, t.hour, t.minute);
              final len = l.length;
              setState(() {
                l
                  ..start = ns
                  ..end = ns.add(len)
                  ..pinned = true;
                _relayout();
              });
              _changed();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                hmRange(l.start!, l.end!),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                // Who does it: each service can go to its own person or room.
                DropdownButtonHideUnderline(
                  child: DropdownButton<int?>(
                    isDense: true,
                    isExpanded: true,
                    value: _allowedFor(l).any((r) => r.id == l.resourceId)
                        ? l.resourceId
                        : null,
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          l10n.translate('res_staff_any'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      for (final r in _allowedFor(l))
                        DropdownMenuItem<int?>(
                          value: r.id,
                          child: Row(
                            children: [
                              ResourceAvatar(resource: r, radius: 9),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  r.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                    onChanged: (id) {
                      setState(() => l.resourceId = id);
                      _changed();
                    },
                  ),
                ),
              ],
            ),
          ),
          Text(money.format(l.price)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () {
              setState(() {
                _lines.remove(l);
                _relayout();
              });
              _changed();
            },
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _retailRow(ThemeData theme, BasketLine l) {
    final money = ref.watch(currencyFormatterProvider);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 2, 2, 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.shopping_bag_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(l.name, overflow: TextOverflow.ellipsis)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: l.quantity > 1
                ? () => setState(() => l.quantity -= 1)
                : null,
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          Text(l.quantity.toStringAsFixed(0)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => l.quantity += 1),
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
          SizedBox(
            width: 76,
            child: Text(money.format(l.price), textAlign: TextAlign.end),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _lines.remove(l)),
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _totals(ThemeData theme, AppLocalizations l10n) {
    if (_lines.isEmpty) {
      return Text(
        l10n.translate('res_pick_services'),
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      );
    }
    final money = ref.watch(currencyFormatterProvider);
    final minutes = _rangeEnd.difference(_rangeStart).inMinutes;
    final total = _lines.fold<double>(0, (s, l) => s + l.price);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Text(
        '$minutes min · ${money.format(total)}',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _overlapBox(
    ThemeData theme,
    AppLocalizations l10n,
    List<({BasketLine line, Reservation other, ReservationItem item})> overlaps,
    Map<int, AgendaResource> resources,
  ) {
    final cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.layers_rounded,
                size: 18,
                color: cs.onTertiaryContainer,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.translate('res_overlap_title'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final o in overlaps.take(4))
            Text(
              '${hmRange(o.item.startAt, o.item.endAt)} · '
              '${o.other.customerLabel.isEmpty ? o.other.code : o.other.customerLabel}'
              ' · ${resources[o.line.resourceId]?.name ?? ''}'
              ' (${reservationStatusLabel(o.other.status, l10n)})',
              style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
            ),
          const SizedBox(height: 4),
          Text(
            l10n.translate('res_overlap_hint'),
            style: TextStyle(fontSize: 12, color: cs.onTertiaryContainer),
          ),
        ],
      ),
    );
  }

  Widget _availabilityLine(ThemeData theme, AppLocalizations l10n) {
    final cs = theme.colorScheme;
    if (!_simpleChain || !ref.watch(canReserveProvider)) {
      return const SizedBox.shrink();
    }
    if (_checking) return const LinearProgressIndicator(minHeight: 2);
    if (_slot != null) {
      return Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            l10n.translate('res_slot_free'),
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
          ),
        ],
      );
    }
    if (_nearby.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n
              .translate('res_slot_not_free')
              .replaceAll('{time}', hm(_rangeStart)),
          style: TextStyle(color: cs.error),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in _nearby)
              ActionChip(
                label: Text(hm(s.startAt)),
                onPressed: () => _moveAllTo(s.startAt, fromSlot: s.items),
              ),
          ],
        ),
      ],
    );
  }

  Widget _nextFree(ThemeData theme, AppLocalizations l10n) {
    if (_timed.isEmpty || !ref.watch(canReserveProvider)) {
      return const SizedBox.shrink();
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    final byDay = <DateTime, List<AvailabilitySlot>>{};
    for (final s in _next ?? const <AvailabilitySlot>[]) {
      byDay.putIfAbsent(dayStartOf(s.startAt), () => []).add(s);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: _searchingNext ? null : _findNext,
          icon: _searchingNext
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.event_repeat_rounded, size: 18),
          label: Text(l10n.translate('res_next_free')),
        ),
        if (_next != null && _next!.isEmpty)
          Text(
            l10n.translate('res_no_slots'),
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        for (final e in byDay.entries.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 74,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      DateFormat('EEE d', locale).format(e.key),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in e.value.take(8))
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(hm(s.startAt)),
                          onPressed: () =>
                              _moveAllTo(s.startAt, fromSlot: s.items),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _customerField(ThemeData theme, AppLocalizations l10n) {
    final cs = theme.colorScheme;
    if (_customerChosen) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 10),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: l10n.translate('res_customer_name'),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _customerChosen = false;
                    _localCustomerId = null;
                    _customerQuery.clear();
                    _name.clear();
                    _phone.clear();
                  }),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 48),
              child: TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: l10n.translate('phone'),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _customerQuery,
          onChanged: (q) {
            setState(() {});
            _searchCustomers(q);
          },
          decoration: InputDecoration(
            hintText: l10n.translate('res_customer_search'),
            prefixIcon: const Icon(Icons.person_search_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        for (final c in _matches)
          ListTile(
            dense: true,
            leading: CircleAvatar(radius: 16, child: Text(c.displayInitial)),
            title: Text(c.displayLabel),
            subtitle: c.phone == null ? null : Text(c.phone!),
            onTap: () => setState(() {
              _localCustomerId = c.id;
              _matches = const [];
              _setCustomer(name: c.displayLabel, phone: c.phone);
            }),
          ),
        if (_customerQuery.text.trim().isNotEmpty)
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: cs.primaryContainer,
              child: Icon(
                Icons.person_add_alt_1_rounded,
                size: 18,
                color: cs.onPrimaryContainer,
              ),
            ),
            title: Text(
              l10n
                  .translate('res_new_customer')
                  .replaceAll('{name}', _customerQuery.text.trim()),
            ),
            onTap: () {
              final q = _customerQuery.text.trim();
              final phone = RegExp(r'^[+\d][\d\s.-]{4,}$').hasMatch(q);
              setState(() {
                _matches = const [];
                _name.text = phone ? '' : q;
                _phone.text = phone ? q : '';
                _customerChosen = true;
              });
            },
          ),
      ],
    );
  }

  /// Services (and retail products) to add, Planity-style: a searchable list.
  Widget _catalog(ThemeData theme, AppLocalizations l10n) {
    final cs = theme.colorScheme;
    final money = ref.watch(currencyFormatterProvider);
    final q = _catalogQuery.text.trim().toLowerCase();
    final List<Widget> rows;
    if (_showRetail) {
      final found = q.length < 2
          ? const <Product>[]
          : (ref.watch(retailProductSearchProvider(q)).valueOrNull ??
                const <Product>[]);
      rows = [
        if (q.length < 2)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              l10n.translate('res_search_products'),
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        for (final p in found)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.shopping_bag_outlined),
            title: Text(p.name),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(money.format(p.finalPrice)),
                const SizedBox(width: 8),
                Icon(Icons.add_circle_rounded, color: cs.primary),
              ],
            ),
            onTap: () => setState(() => _lines.add(BasketLine.retail(p))),
          ),
      ];
    } else {
      final services =
          ref.watch(bookableServicesProvider).valueOrNull ?? const <Product>[];
      final categoryNames =
          ref.watch(serviceCategoryNamesProvider).valueOrNull ?? const {};
      final groups = <String, List<Product>>{};
      for (final s in services) {
        if (q.isNotEmpty && !s.name.toLowerCase().contains(q)) continue;
        groups.putIfAbsent(categoryNames[s.categoryId] ?? '', () => []).add(s);
      }
      rows = [
        if (services.isEmpty)
          Text(
            l10n.translate('no_bookable_services'),
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
        for (final g in groups.entries) ...[
          if (g.key.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(
                g.key,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          for (final s in g.value)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(s.name),
              subtitle: Text('${s.planDurationMinutes} min'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(money.format(s.finalPrice)),
                  const SizedBox(width: 8),
                  Icon(Icons.add_circle_rounded, color: cs.primary),
                ],
              ),
              onTap: () {
                // A new service goes to the person of the one before it.
                final rid = _timed.lastOrNull?.resourceId ?? _resourceId;
                setState(() {
                  _lines.add(BasketLine.service(s, resourceId: rid));
                  _relayout();
                });
                _changed();
              },
            ),
        ],
      ];
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.content_cut_rounded, size: 16),
                    label: Text(l10n.translate('res_services')),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.shopping_bag_outlined, size: 16),
                    label: Text(l10n.translate('res_products')),
                  ),
                ],
                selected: {_showRetail},
                onSelectionChanged: (s) =>
                    setState(() => _showRetail = s.first),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _catalogQuery,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            hintText: l10n.translate('search'),
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        ...rows,
      ],
    );
  }

  List<Widget> _blockFields(
    ThemeData theme,
    AppLocalizations l10n,
    Map<int, AgendaResource> resources,
  ) {
    final step = Duration(minutes: widget.stepMinutes);
    return [
      Row(
        children: [
          Chip(label: Text(hmRange(_start, _blockEnd))),
          IconButton(
            onPressed: _blockEnd.subtract(step).isAfter(_start)
                ? () => setState(() => _blockEnd = _blockEnd.subtract(step))
                : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            onPressed: () => setState(() => _blockEnd = _blockEnd.add(step)),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
      DropdownButton<int>(
        isExpanded: true,
        value: resources.containsKey(_resourceId) ? _resourceId : null,
        items: [
          for (final r in resources.values)
            DropdownMenuItem(value: r.id, child: Text(r.name)),
        ],
        onChanged: (id) => setState(() => _resourceId = id),
      ),
      const SizedBox(height: 12),
      _label(theme, l10n.translate('res_block_kind')),
      Wrap(
        spacing: 8,
        children: [
          for (final k in const ['BREAK', 'ABSENCE', 'BLOCK'])
            ChoiceChip(
              selected: _blockKind == k,
              label: Text(l10n.translate('res_block_${k.toLowerCase()}')),
              onSelected: (_) => setState(() => _blockKind = k),
            ),
        ],
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _blockTitle,
        decoration: InputDecoration(
          labelText: l10n.translate('res_block_title'),
          border: const OutlineInputBorder(),
        ),
      ),
    ];
  }
}

/// Initials on the resource's colour: the face of a column.
class ResourceAvatar extends StatelessWidget {
  final AgendaResource resource;
  final double radius;
  const ResourceAvatar({super.key, required this.resource, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = resourceColor(resource.color, resource.id, cs);
    final onColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final parts = resource.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    final initials = parts.isEmpty
        ? '?'
        : (parts.length == 1
                  ? parts.first.substring(0, math.min(2, parts.first.length))
                  : '${parts[0][0]}${parts[1][0]}')
              .toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: color,
      child: resource.isStaff
          ? Text(
              initials,
              style: TextStyle(
                color: onColor,
                fontSize: radius * 0.75,
                fontWeight: FontWeight.w700,
              ),
            )
          : Icon(Icons.meeting_room_outlined, size: radius, color: onColor),
    );
  }
}

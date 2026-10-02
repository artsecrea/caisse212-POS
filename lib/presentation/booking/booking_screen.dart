import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../../data/database/app_database.dart';
import '../../domain/models/booking_models.dart';
import '../../domain/models/order_models.dart';
import '../../providers/booking_providers.dart';
import '../../providers/database_providers.dart';
import '../../providers/order_provider.dart';
import '../../providers/resource_providers.dart';
import '../../providers/settings_provider.dart';
import '../../services/booking_service.dart';
import '../../utils/app_localizations.dart';
import '../../utils/error_text.dart';
import '../../utils/currency_formatter.dart';
import '../widgets/customer_selection_dialog.dart';
import '../../utils/snackbar_helper.dart';

/// Every bookable service in the catalogue: a product marked plannable that
/// actually carries a duration.
///
/// A plannable product with no duration cannot be booked at all — the
/// availability endpoint has nothing to size a slot with and answers 400 — so
/// it is filtered out here rather than offered and then refused.
final bookableServicesProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.products)
        ..where((p) =>
            p.isPlannable.equals(true) &
            p.planDurationMinutes.isNotNull() &
            p.planDurationMinutes.isBiggerThanValue(0))
        ..orderBy([(p) => OrderingTerm(expression: p.name)]))
      .watch();
});

/// Pick a service, a day, and a free slot with a provider; then create the
/// order and claim the slot.
///
/// The whole screen is online-only by design (see [OfflineBookingException]):
/// the order has to reach the backend before its line can be addressed by
/// `PATCH /order-products/{id}/schedule`, so there is no useful half of this
/// flow that works offline. Walk-ins are the offline path and live on the main
/// POS screen.
class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key});

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  final _logger = Logger.instance;

  Product? _service;
  late DateTime _date;
  int? _providerFilter;

  /// Chosen slot: the candidate's staff id and the exact start.
  int? _slotWaiterId;
  DateTime? _slotStart;
  int? _resourceId;

  int? _customerId;
  String? _customerName;

  bool _submitting = false;

  /// The order created by a previous attempt that failed at the slot claim.
  ///
  /// Kept so a 409 — the expected, ordinary outcome of two tills racing for the
  /// same chair — costs a retry, not a second order. Without this, every
  /// conflict would leave a stray unscheduled sale behind.
  int? _pendingOrderId;
  int? _pendingLineId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  AvailabilityKey? get _availabilityKey => _service == null
      ? null
      : (
          productId: _service!.id,
          date: _date,
          waiterId: _providerFilter,
          resourceId: _resourceId,
        );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final canBook = ref.watch(canBookProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('book_appointment')),
        actions: [
          if (_service != null && canBook)
            IconButton(
              tooltip: l10n.translate('refresh'),
              onPressed: () => ref.invalidate(availabilityProvider),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!canBook) _offlineBanner(theme, l10n),
          Expanded(
            child: AbsorbPointer(
              absorbing: !canBook,
              child: Opacity(
                opacity: canBook ? 1 : 0.4,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionTitle(theme, '1', l10n.translate('choose_service')),
                    _buildServicePicker(theme, l10n),
                    const SizedBox(height: 20),
                    _sectionTitle(theme, '2', l10n.translate('choose_date')),
                    _buildDateStrip(theme),
                    const SizedBox(height: 20),
                    _sectionTitle(theme, '3', l10n.translate('choose_slot')),
                    _buildAvailability(theme, l10n),
                    const SizedBox(height: 20),
                    _sectionTitle(theme, '4', l10n.translate('customer')),
                    _buildCustomerRow(theme, l10n),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildConfirmBar(theme, l10n, canBook),
    );
  }

  Widget _offlineBanner(ThemeData theme, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.translate('reconnect_to_book'),
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(ThemeData theme, String step, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(step,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer)),
          ),
          const SizedBox(width: 10),
          Text(label,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── 1. Service ──────────────────────────────────────────────────────────

  Widget _buildServicePicker(ThemeData theme, AppLocalizations l10n) {
    final servicesAsync = ref.watch(bookableServicesProvider);
    final formatter = ref.watch(currencyFormatterProvider);

    return servicesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text(errorText(e, l10n)),
      data: (services) {
        if (services.isEmpty) {
          return _hint(theme, l10n.translate('no_bookable_services'));
        }
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in services)
              ChoiceChip(
                selected: _service?.id == s.id,
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '${s.planDurationMinutes} min · '
                      '${formatter.format(s.finalPrice)}',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ],
                ),
                onSelected: (_) => setState(() {
                  _service = s;
                  // A slot belongs to the service it was found for.
                  _slotStart = null;
                  _slotWaiterId = null;
                  _resourceId = null;
                  _clearPendingOrder();
                }),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
          ],
        );
      },
    );
  }

  // ── 2. Date ─────────────────────────────────────────────────────────────

  Widget _buildDateStrip(ThemeData theme) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);

    return SizedBox(
      height: 74,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 14,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final d = start.add(Duration(days: i));
                final selected = _sameDay(d, _date);
                return InkWell(
                  onTap: () => setState(() {
                    _date = d;
                    _slotStart = null;
                    _slotWaiterId = null;
                  }),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 62,
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_weekdayLabel(d),
                            style: TextStyle(
                              fontSize: 11,
                              color: selected
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurfaceVariant,
                            )),
                        Text('${d.day}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: selected
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSurface,
                            )),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            onPressed: _pickDate,
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day);
        _slotStart = null;
        _slotWaiterId = null;
      });
    }
  }

  // ── 3. Availability ─────────────────────────────────────────────────────

  Widget _buildAvailability(ThemeData theme, AppLocalizations l10n) {
    final key = _availabilityKey;
    if (key == null) {
      return _hint(theme, l10n.translate('pick_a_service_first'));
    }

    final async = ref.watch(availabilityProvider(key));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => _errorCard(theme, '$e'),
      data: (availability) {
        if (!availability.hasAnyAvailability) {
          return _hint(theme, l10n.translate('no_slots_that_day'));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (availability.requiresResource)
              _buildResourcePicker(theme, l10n, availability),
            for (final c in availability.candidates)
              if (c.hasAvailability)
                _buildCandidateCard(theme, c, availability),
          ],
        );
      },
    );
  }

  Widget _buildResourcePicker(
      ThemeData theme, AppLocalizations l10n, AvailabilityResponse a) {
    final byId = ref.watch(resourcesByIdProvider);
    if (a.eligibleResourceIds.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.translate('resource'),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              // "Any" lets the server resolve one — the usual case, and the
              // only option that stays valid if the picked chair fills up
              // between here and the confirm.
              ChoiceChip(
                selected: _resourceId == null,
                label: Text(l10n.translate('any')),
                onSelected: (_) => setState(() {
                  _resourceId = null;
                  _slotStart = null;
                }),
              ),
              for (final id in a.eligibleResourceIds)
                ChoiceChip(
                  selected: _resourceId == id,
                  label: Text(byId[id]?.name ?? '#$id'),
                  onSelected: (_) => setState(() {
                    _resourceId = id;
                    _slotStart = null;
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCandidateCard(
      ThemeData theme, AvailabilityCandidate c, AvailabilityResponse a) {
    final duration = Duration(minutes: a.serviceDurationMinutes);
    final starts = _startsWithin(c.freeIntervals, duration);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  child: Text(
                    c.waiterName.isEmpty ? '?' : c.waiterName[0].toUpperCase(),
                    style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSecondaryContainer),
                  ),
                ),
                const SizedBox(width: 10),
                Text(c.waiterName,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in starts)
                  ChoiceChip(
                    selected:
                        _slotWaiterId == c.waiterId && _slotStart == s,
                    label: Text(_timeLabel(s)),
                    onSelected: (_) => setState(() {
                      _slotWaiterId = c.waiterId;
                      _slotStart = s;
                    }),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Every start the service fits into, stepped by the shop's agenda grid.
  ///
  /// The server hands back windows already at least a service long, but a
  /// 09:00–13:00 window is one interval, not one slot: staff need the starts
  /// inside it. Stepping by the agenda's own time step keeps the offered times
  /// aligned with how the day is drawn, instead of producing 09:37s.
  List<DateTime> _startsWithin(List<TimeInterval> intervals, Duration service) {
    final stepMinutes = ref.read(settingsProvider).agendaTimeStep;
    final step = Duration(minutes: stepMinutes <= 0 ? 30 : stepMinutes);
    final now = DateTime.now();
    final out = <DateTime>[];

    for (final interval in intervals) {
      var start = _ceilToStep(interval.start, step);
      while (!start.add(service).isAfter(interval.end)) {
        // A slot that has already begun cannot be booked into.
        if (start.isAfter(now)) out.add(start);
        start = start.add(step);
        if (out.length > 200) return out; // pathological window guard
      }
    }
    return out;
  }

  DateTime _ceilToStep(DateTime t, Duration step) {
    final stepMs = step.inMilliseconds;
    final dayStart = DateTime(t.year, t.month, t.day);
    final into = t.difference(dayStart).inMilliseconds;
    final ceil = ((into + stepMs - 1) ~/ stepMs) * stepMs;
    return dayStart.add(Duration(milliseconds: ceil));
  }

  // ── 4. Customer ─────────────────────────────────────────────────────────

  Widget _buildCustomerRow(ThemeData theme, AppLocalizations l10n) {
    return Row(
      children: [
        Expanded(
          child: Text(
            _customerName ?? l10n.translate('walk_in_no_customer'),
            style: TextStyle(
              color: _customerName == null ? Theme.of(context).colorScheme.onSurfaceVariant : null,
              fontWeight: _customerName == null ? null : FontWeight.w600,
            ),
          ),
        ),
        if (_customerId != null)
          IconButton(
            tooltip: l10n.translate('clear'),
            onPressed: () => setState(() {
              _customerId = null;
              _customerName = null;
            }),
            icon: const Icon(Icons.close_rounded),
          ),
        OutlinedButton.icon(
          onPressed: _pickCustomer,
          icon: const Icon(Icons.person_search_rounded, size: 18),
          label: Text(l10n.translate('select_customer')),
        ),
      ],
    );
  }

  Future<void> _pickCustomer() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const CustomerSelectionDialog(),
    );
    if (result == null) return;
    setState(() {
      _customerId = result['id'] as int?;
      _customerName = result['name'] as String?;
    });
  }

  // ── Confirm ─────────────────────────────────────────────────────────────

  Widget _buildConfirmBar(
      ThemeData theme, AppLocalizations l10n, bool canBook) {
    final ready = canBook &&
        _service != null &&
        _slotStart != null &&
        _slotWaiterId != null &&
        !_submitting;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_slotStart != null && _service != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_service!.name} · ${_dateLabel(_slotStart!)} '
                  '${_timeLabel(_slotStart!)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: ready ? _confirm : null,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.event_available_rounded),
                label: Text(l10n.translate('confirm_booking')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _clearPendingOrder() {
    _pendingOrderId = null;
    _pendingLineId = null;
  }

  Future<void> _confirm() async {
    final l10n = AppLocalizations.of(context)!;
    final service = _service!;
    final start = _slotStart!;
    final end = start.add(Duration(minutes: service.planDurationMinutes ?? 0));

    setState(() => _submitting = true);
    try {
      // 1. The order must exist on the server before its line can be booked:
      //    /schedule addresses the server's order-product id. A retry after a
      //    409 reuses the order created by the first attempt.
      final lineId = _pendingLineId ?? await _createAndSyncOrder(service);
      if (lineId == null) {
        _toast(l10n.translate('booking_order_sync_failed'), isError: true);
        return;
      }

      final booking = ref.read(bookingServiceProvider);
      final serverLineId = await booking.resolveServerLineId(lineId);
      if (serverLineId == null) throw const UnsyncedLineException();

      // 2. Claim the slot. This is the authoritative step — availability was
      //    only ever advice.
      await booking.schedule(
        serverOrderProductId: serverLineId,
        localOrderProductId: lineId,
        planStartAt: start,
        planEndAt: end,
        planWaiterId: _slotWaiterId,
        planResourceId: _resourceId,
      );

      _clearPendingOrder();
      if (!mounted) return;
      _toast(l10n.translate('booking_confirmed'));
      Navigator.of(context).pop(true);
    } on ScheduleConflict catch (c) {
      // Someone else took it between the availability read and the claim —
      // the ordinary race, not an error to apologise for. Refresh and let
      // them pick again; the order stays put for the retry.
      final detail =
          c.capacity != null ? ' (${c.current ?? '?'}/${c.capacity})' : '';
      setState(() => _slotStart = null);
      ref.invalidate(availabilityProvider);
      if (mounted) _toast('${c.message}$detail', isError: true);
    } on ScheduleValidationError catch (v) {
      if (mounted) _toast(v.message, isError: true);
    } on OfflineBookingException {
      if (mounted) _toast(l10n.translate('reconnect_to_book'), isError: true);
    } on UnsyncedLineException {
      if (mounted) {
        _toast(l10n.translate('booking_order_sync_failed'), isError: true);
      }
    } catch (e) {
      _logger.error('Booking failed: $e');
      if (mounted) _toast(errorText(e, l10n), isError: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Create a one-line order for the service and push it to the backend.
  ///
  /// Returns the local `order_products.id` of the service line, or null when
  /// the order could not be synced — in which case there is nothing to book
  /// and the caller says so rather than leaving a silent local-only order.
  Future<int?> _createAndSyncOrder(Product service) async {
    final repo = ref.read(orderRepositoryProvider);
    final user = ref.read(currentUserProvider);
    final session = ref.read(currentSessionProvider);
    final settings = ref.read(settingsProvider);
    if (user == null || session == null) return null;

    // A previous attempt already created the order and only failed to push it.
    // Retry the push rather than ringing the service up a second time.
    if (_pendingOrderId != null) {
      return _syncAndFindLine(_pendingOrderId!, service.id);
    }

    final order = CurrentOrder(
      items: [
        OrderItem(
          productId: service.id,
          productName: service.name,
          imageUrl: service.imageUrl,
          finalPrice: service.finalPrice,
          tva: service.tvaAmount,
          unitName: service.unitName,
        ),
      ],
      customerId: _customerId,
      customerName: _customerName,
      type: settings.defaultOrderType,
    );

    final orderId = await repo.saveOrder(
      order,
      user.id,
      status: settings.defaultOrderStatus,
      sessionId: session.id,
    );
    _pendingOrderId = orderId;
    return _syncAndFindLine(orderId, service.id);
  }

  /// Push [orderId] to the backend and hand back the local id of its service
  /// line. Null when the push failed — there is then nothing bookable, and the
  /// caller says so rather than leaving a local-only order looking booked.
  Future<int?> _syncAndFindLine(int orderId, int productId) async {
    // `autoSyncOrder` is deliberately not used: it obeys the auto-sync
    // setting, and booking cannot be optional about reaching the server.
    final synced =
        await ref.read(dataSyncServiceProvider).syncSingleOrder(orderId);
    if (!synced) return null;

    final db = ref.read(databaseProvider);
    final lines = await (db.select(db.orderProducts)
          ..where((t) => t.orderId.equals(orderId)))
        .get();
    final line = lines.where((l) => l.productId == productId).firstOrNull;
    _pendingLineId = line?.id;
    return _pendingLineId;
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  Widget _hint(ThemeData theme, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget _errorCard(ThemeData theme, String message) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(message,
            style: TextStyle(color: theme.colorScheme.onErrorContainer)),
      );

  void _toast(String message, {bool isError = false}) {
    SnackBarHelper.showToast(message, kind: (isError) ? ToastKind.error : ToastKind.info, duration: Duration(seconds: isError ? 4 : 2));
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _two(int v) => v.toString().padLeft(2, '0');

  String _timeLabel(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

  String _dateLabel(DateTime t) => '${_two(t.day)}/${_two(t.month)}';

  String _weekdayLabel(DateTime d) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(d.weekday - 1) % 7];
  }
}

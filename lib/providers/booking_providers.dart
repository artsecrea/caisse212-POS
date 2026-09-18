import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/models/booking_models.dart';
import '../services/api_service.dart';
import '../services/booking_service.dart';
import '../services/data_sync_service.dart';
import 'database_providers.dart';
import 'network_provider.dart';

/// All active bookable staff, reactive to the locally cached Providers table.
///
/// Ordered by name so the booking screen and the agenda columns agree; the
/// agenda's column order changing between refreshes is disorienting when you
/// are looking for one barber's day.
final serviceProvidersProvider = StreamProvider<List<ServiceProvider>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.providers)
        ..where((p) => p.isActive.equals(true))
        ..orderBy([
          (p) => OrderingTerm(expression: p.firstName),
          (p) => OrderingTerm(expression: p.lastName),
        ]))
      .watch();
});

/// Quick id → provider lookup for putting a name on a booking.
final serviceProvidersByIdProvider = Provider<Map<int, ServiceProvider>>((ref) {
  final list = ref.watch(serviceProvidersProvider).valueOrNull ?? const [];
  return {for (final p in list) p.id: p};
});

String providerDisplayName(ServiceProvider p) =>
    [p.firstName, p.lastName].where((s) => s != null && s.isNotEmpty).join(' ');

/// Whether the booking calls — availability, schedule, unschedule — can run
/// right now.
///
/// The contract is deliberately hard: these are the only POS actions that may
/// **never** be queued for offline sync. A slot belongs to the shop's single
/// diary, so a queued booking would be a promise this terminal cannot keep —
/// two tills offline at once would each sell the same 3pm chair. Walk-ins,
/// which claim no slot, keep working offline through the ordinary order path.
final canBookProvider = Provider<bool>((ref) {
  return ref.watch(lastKnownOnlineStatusProvider);
});

/// The one path through which slots are claimed and released.
final bookingServiceProvider = Provider<BookingService>((ref) {
  return BookingService(
    ref.watch(apiServiceProvider),
    ref.watch(databaseProvider),
    ref.watch(dataSyncServiceProvider),
    ref.watch(pendingOperationsServiceProvider),
    // Read, not watch: the guard must reflect the connection at the moment the
    // call is made, not whenever this provider was last rebuilt.
    () => ref.read(lastKnownOnlineStatusProvider),
  );
});

/// The Monday..Sunday week containing [date], as `[start, endInclusive]`.
///
/// The agenda pulls whole weeks rather than single days: staff flick back and
/// forth across a week constantly, and one request for seven days beats seven
/// requests — especially since the next one may arrive after the connection
/// has gone, when a prefetched week is the difference between a full diary and
/// an empty grid.
({DateTime start, DateTime endInclusive}) weekOf(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final monday = day.subtract(Duration(days: day.weekday - DateTime.monday));
  return (start: monday, endInclusive: monday.add(const Duration(days: 6)));
}

/// The cached diary for one day, newest pull.
///
/// Selected by **overlap**, matching the endpoint: an appointment that began
/// at 23:30 yesterday and runs past midnight is part of today, and a
/// start-in-day filter would drop it off the grid it is occupying.
final cachedAgendaProvider =
    StreamProvider.family<List<AgendaBooking>, DateTime>((ref, date) {
  final db = ref.watch(databaseProvider);
  final dayStart = DateTime(date.year, date.month, date.day);
  final dayEnd = dayStart.add(const Duration(days: 1));
  return (db.select(db.agendaBookings)
        ..where((t) =>
            t.planStartAt.isSmallerThanValue(dayEnd) &
            t.planEndAt.isBiggerThanValue(dayStart))
        ..orderBy([(t) => OrderingTerm(expression: t.planStartAt)]))
      .watch();
});

/// The server's summary for the week last pulled, keyed by that week's Monday.
///
/// Held in memory rather than cached: it is a forecast of expected money, and
/// a stale forecast shown next to a live diary invites someone to bank on it.
final agendaWeekSummaryProvider =
    StateProvider<Map<DateTime, AgendaSummary>>((ref) => const {});

/// Ticks so anything showing a [BookingTimeStatus] repaints as the day moves.
///
/// A booking's time status is a function of the clock, so without a tick a
/// screen left open all morning would still show the 9am cut as NOT_YET at
/// noon. One minute is finer than the eye needs on an hour grid and costs one
/// rebuild a minute.
final clockTickProvider = StreamProvider<DateTime>((ref) {
  late final StreamController<DateTime> controller;
  Timer? timer;

  controller = StreamController<DateTime>(
    onListen: () {
      controller.add(DateTime.now());
      timer = Timer.periodic(
          const Duration(minutes: 1), (_) => controller.add(DateTime.now()));
    },
    onCancel: () => timer?.cancel(),
  );
  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });
  return controller.stream;
});

/// Pull the whole week containing [date] and write it to the cache.
///
/// Takes its dependencies explicitly rather than a `Ref`, so both widgets
/// (`WidgetRef`) and providers can call it.
///
/// Returns null when the pull could not run — offline, or an older backend
/// without the endpoint. The caller keeps showing the cache rather than
/// clearing it: a week-old diary is far more useful to a shop than a blank one.
Future<AgendaSummary?> refreshAgendaWeek({
  required ApiService api,
  required DataSyncService sync,
  required bool isOnline,
  required DateTime date,
}) async {
  if (!isOnline) return null;
  final week = weekOf(date);
  // The endpoint's window is [startDate 00:00, endDate+1 00:00), so the cache
  // has to be scoped to the same half-open range or the replace would miss
  // Sunday evening.
  final windowEnd = week.endInclusive.add(const Duration(days: 1));
  try {
    final page = await api.fetchAgenda(
      startDate: week.start,
      endDate: week.endInclusive,
    );
    await sync.cacheAgenda(page.items,
        windowStart: week.start, windowEnd: windowEnd);
    return page.summary;
  } catch (_) {
    return null;
  }
}

/// The backend's payment position for an order: what has been collected and
/// what is still owed.
///
/// Watched rather than computed locally because the server owns the sum. A
/// service order is routinely part-paid — a deposit at booking, the rest after
/// the appointment, sometimes on a different till — and the backend settles
/// delivered value first, treating only the excess as a deposit. Re-deriving
/// that here would drift the first time money moved anywhere else.
final orderPaymentPositionProvider =
    StreamProvider.family<Order?, int>((ref, orderId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.orders)..where((o) => o.id.equals(orderId)))
      .watchSingleOrNull();
});

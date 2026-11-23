import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';

import '../domain/models/reservation_models.dart';
import '../services/reservation_service.dart';
import 'database_providers.dart';
import 'network_provider.dart';

/// Every bookable service: a time-managed, active product with a duration.
/// One without a duration cannot be sized into a slot, so it is not offered.
final bookableServicesProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.products)
        ..where((p) =>
            p.isPlannable.equals(true) &
            p.isActive.equals(true) &
            p.planDurationMinutes.isNotNull() &
            p.planDurationMinutes.isBiggerThanValue(0))
        ..orderBy([(p) => OrderingTerm(expression: p.name)]))
      .watch();
});

/// Ids of [bookableServicesProvider], for "does this cart hold a service".
final bookableProductIdsProvider = Provider<Set<int>>((ref) => {
      for (final p in ref.watch(bookableServicesProvider).valueOrNull ??
          const <Product>[])
        p.id
    });

/// Each service's resource pool (who can do it), from the product sync.
/// No entry = any staff member.
final servicePoolsProvider = StreamProvider<Map<int, Set<int>>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.productResources).watch().map((rows) {
    final out = <int, Set<int>>{};
    for (final r in rows) {
      out.putIfAbsent(r.productId, () => <int>{}).add(r.resourceId);
    }
    return out;
  });
});

/// Retail products (not time-managed) matching a search, to sell alongside
/// a reservation.
final retailProductSearchProvider =
    FutureProvider.family<List<Product>, String>((ref, query) {
  final db = ref.watch(databaseProvider);
  final q = '%${query.trim().toLowerCase()}%';
  return (db.select(db.products)
        ..where((p) =>
            p.isActive.equals(true) &
            p.isPlannable.equals(false) &
            (p.name.lower().like(q) | p.barcode.like(q)))
        ..orderBy([(p) => OrderingTerm(expression: p.name)])
        ..limit(30))
      .get();
});

/// Whether reservation writes can run right now. They are never queued (a
/// slot belongs to the shop's one diary), so offline they are refused and
/// the agenda shows the last pull.
final canReserveProvider = Provider<bool>((ref) {
  return ref.watch(lastKnownOnlineStatusProvider);
});

final reservationServiceProvider = Provider<ReservationService>((ref) {
  return ReservationService(
    ref.watch(apiServiceProvider),
    ref.watch(databaseProvider),
    // Read, not watch: the guard reflects the connection when a call is
    // made, not when this provider was last rebuilt.
    () => ref.read(lastKnownOnlineStatusProvider),
  );
});

/// Orders the server saved while another order already held their
/// reservation — a possible duplicate sale, worth telling the cashier.
final reservationDuplicateProvider = StreamProvider<ReservationLink>((ref) {
  return ref.watch(dataSyncServiceProvider).reservationDuplicates;
});

/// Bumped whenever the diary may have changed (a write here, an SSE
/// `reservation-updated` from any terminal); the agenda re-reads on it.
final agendaRevisionProvider = StateProvider<int>((ref) => 0);

/// The day an open agenda screen is showing; null when none is open. SSE
/// `reservation-updated` pulls this day's week.
final agendaVisibleDateProvider = StateProvider<DateTime?>((ref) => null);

/// One day of the agenda from the local cache.
final agendaDayProvider =
    FutureProvider.family<AgendaDay, DateTime>((ref, date) {
  ref.watch(agendaRevisionProvider);
  return ref.watch(reservationServiceProvider).loadDay(dayStartOf(date));
});

/// The server's summary for the week last pulled, keyed by its Monday.
/// In memory only: a stale forecast of expected money is worse than none.
final agendaWeekSummaryProvider =
    StateProvider<Map<DateTime, AgendaSummary>>((ref) => const {});

/// The Monday..Sunday week containing [date], as `[start, endInclusive]`.
/// The agenda pulls whole weeks: staff flick across a week constantly, and a
/// prefetched week is what still shows if the connection drops.
({DateTime start, DateTime endInclusive}) weekOf(DateTime date) {
  final day = dayStartOf(date);
  final monday = DateTime(day.year, day.month, day.day - (day.weekday - 1));
  return (
    start: monday,
    endInclusive: DateTime(monday.year, monday.month, monday.day + 6),
  );
}

/// Pull the week containing [date] into the cache, record its summary and
/// repaint. Returns false when offline or the pull failed (the cache stays).
Future<bool> pullAgendaWeek(Ref ref, DateTime date) =>
    _pull(ref.read(reservationServiceProvider), date,
        (m, s) => ref.read(agendaWeekSummaryProvider.notifier).update(
            (old) => {...old, m: s}),
        () => ref.read(agendaRevisionProvider.notifier).state++);

/// [pullAgendaWeek] for widgets.
Future<bool> pullAgendaWeekFromWidget(WidgetRef ref, DateTime date) =>
    _pull(ref.read(reservationServiceProvider), date,
        (m, s) => ref.read(agendaWeekSummaryProvider.notifier).update(
            (old) => {...old, m: s}),
        () => ref.read(agendaRevisionProvider.notifier).state++);

Future<bool> _pull(
  ReservationService service,
  DateTime date,
  void Function(DateTime monday, AgendaSummary summary) onSummary,
  void Function() bump,
) async {
  final week = weekOf(date);
  final summary = await service.pullAgenda(week.start, week.endInclusive);
  if (summary == null) return false;
  onSummary(week.start, summary);
  bump();
  return true;
}

/// Ticks once a minute so anything showing a [BookingTimeStatus] repaints as
/// the day moves.
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

import 'package:drift/drift.dart';

/// Last pulled copy of the shop's reservations, from
/// `GET /pos/reservations/agenda`.
///
/// A read-only cache, never a source of truth: every reservation write is
/// online-only and the server holds the diary. It exists so that, during an
/// outage, the agenda still shows who is coming and a reservation already
/// held here can still be rung up as an order.
///
/// [payload] is the reservation exactly as the server sent it (items, customer,
/// timestamps), so a newer field never needs a schema change to survive the
/// cache. The other columns are copies of it for querying.
class CachedReservations extends Table {
  IntColumn get id => integer()();
  TextColumn get code => text()();
  TextColumn get status => text()();
  DateTimeColumn get startAt => dateTime()();
  DateTimeColumn get endAt => dateTime()();
  TextColumn get customerName => text().nullable()();
  TextColumn get customerPhone => text().nullable()();
  TextColumn get orderCode => text().nullable()();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

/// The frame of one agenda day as last pulled: zone, opening hours, the
/// resource columns with their availability, blocks and busy-elsewhere slots.
/// Stored as the server's JSON, one row per shop-zone day (`yyyy-MM-dd`).
class AgendaDaySnapshots extends Table {
  TextColumn get day => text()();
  TextColumn get payload => text()();
  DateTimeColumn get fetchedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {day};
}

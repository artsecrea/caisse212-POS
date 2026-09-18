import 'package:drift/drift.dart';

/// Bookable staff for time-managed services — the barber, stylist or therapist
/// an appointment is booked *with*. Synced from `GET /pos/providers`.
///
/// Deliberately its own table rather than a flag on [Waiters]. The two answer
/// different questions: a waiter carries tables and settles cash, a provider
/// occupies a slot in the agenda. A shop can run both, one, or neither, and
/// the same person may be in both lists with different ids.
///
/// The credential columns mirror the offline-login shape the KDS profiles use
/// (`/kds-profiles`), so a provider can be authenticated on-device against the
/// last sync while the connection is down.
/// The row class is named `ServiceProvider`, not the default `Provider`:
/// Riverpod exports a `Provider` of its own and almost every file in this app
/// imports both.
@DataClassName('ServiceProvider')
class Providers extends Table {
  IntColumn get id => integer()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get username => text().nullable()();
  TextColumn get passwordHash => text().nullable()();
  TextColumn get pin => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

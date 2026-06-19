import 'package:drift/drift.dart';

/// Waiters table - stores waiter/server information.
///
/// `pin` is the sole credential the waiter types into the waiter app to
/// authenticate against the local POS HTTP server (see `_waiterLogin` in
/// `server_service.dart`). It's synced down from the backend with the rest
/// of the waiter record, and uniqueness is enforced by a **partial unique
/// index** (NULL pins are allowed to coexist during the rollout — the
/// backend may not have populated pins for every waiter yet — but two
/// non-null pins must differ). See the migration block in `app_database.dart`.
///
/// `username` and `passwordHash` are legacy fields kept for backward
/// compatibility with older sync payloads; they're no longer consulted by
/// the login path.
class Waiters extends Table {
  IntColumn get id => integer()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get pin => text().nullable()();
  TextColumn get username => text().nullable()();
  TextColumn get passwordHash => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// WaiterAreas join table - many-to-many relationship between waiters and areas
class WaiterAreas extends Table {
  IntColumn get waiterId => integer()();
  IntColumn get areaId => integer()();

  @override
  Set<Column> get primaryKey => {waiterId, areaId};
}


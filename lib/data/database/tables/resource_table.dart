import 'package:drift/drift.dart';

/// A bookable resource for time-managed services — a room, chair, or piece of
/// equipment a scheduled service occupies. Synced from the server. A resource
/// has a [capacity] (how many overlapping bookings it can hold at once — a
/// shared room may be > 1); the server is authoritative on conflicts, returning
/// a capacity-aware 409 (`current/capacity`) on `PATCH /schedule`.
class Resources extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};

  /// ROOM | CHAIR | EQUIPMENT | OTHER — display grouping only.
  TextColumn get type => text().withDefault(const Constant('OTHER'))();
  IntColumn get capacity => integer().withDefault(const Constant(1))();
  IntColumn get businessId => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

import 'package:drift/drift.dart';

/// A bookable resource — an agenda column. Staff are resources of type STAFF;
/// rooms, chairs and equipment are the others. Synced from `/pos/resources`.
/// [capacity] is how many overlapping reservations it holds at once; the
/// server is authoritative on conflicts (409 SLOT_TAKEN / NO_RESOURCE_FREE).
class Resources extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};

  /// STAFF | ROOM | CHAIR | EQUIPMENT | OTHER.
  TextColumn get type => text().withDefault(const Constant('OTHER'))();
  IntColumn get capacity => integer().withDefault(const Constant(1))();
  IntColumn get businessId => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// `#RRGGBB` set in the back office; null = pick one from the id.
  TextColumn get color => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

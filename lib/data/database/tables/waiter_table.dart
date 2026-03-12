import 'package:drift/drift.dart';

/// Waiters table - stores waiter/server information
class Waiters extends Table {
  IntColumn get id => integer()();
  TextColumn get firstName => text()();
  TextColumn get lastName => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
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


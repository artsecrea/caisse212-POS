import 'package:drift/drift.dart';

class KDSs extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get description => text().nullable()();
  TextColumn get ip => text().nullable()();
  IntColumn get port => integer().nullable()();
  TextColumn get location => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


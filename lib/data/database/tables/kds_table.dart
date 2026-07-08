import 'package:drift/drift.dart';

class KDSs extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get description => text().nullable()();

  IntColumn get stationId => integer().nullable()();
  TextColumn get ip => text().nullable()();
  IntColumn get port => integer().nullable()();
  TextColumn get location => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

// run build_runner to generate the code
// flutter pub run build_runner build --delete-conflicting-outputs
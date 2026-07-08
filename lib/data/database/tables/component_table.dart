import 'package:drift/drift.dart';

class Components extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get description => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  RealColumn get price => real().withDefault(const Constant(0.0))();
  IntColumn get componentGroupId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}


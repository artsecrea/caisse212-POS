import 'package:drift/drift.dart';

class Commercials extends Table {
  IntColumn get id => integer()();
  TextColumn get cin => text().unique()();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}


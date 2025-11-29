import 'package:drift/drift.dart';

class Commercials extends Table {
  IntColumn get id => integer()();
  TextColumn get cin => text().unique()();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get firstName => text()();
  TextColumn get lastName => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


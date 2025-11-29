import 'package:drift/drift.dart';

class Customers extends Table {
  IntColumn get id => integer()();
  TextColumn get firstName => text()();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get lastName => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  DateTimeColumn get joinedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


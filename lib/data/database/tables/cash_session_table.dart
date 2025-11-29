import 'package:drift/drift.dart';

class CashSessions extends Table {
  IntColumn get id => integer()();
  IntColumn get cashierId => integer()();

  @override
  Set<Column> get primaryKey => {id};
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endedAt => dateTime().nullable()();
  RealColumn get moneyAtStart => real()();
  RealColumn get moneyAtEnd => real().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


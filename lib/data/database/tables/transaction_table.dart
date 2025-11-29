import 'package:drift/drift.dart';

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paymentId => integer()();
  TextColumn get referenceId => text().nullable()();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get type => text()(); // CARD, CASH, etc.
  TextColumn get metaData => text().nullable()(); // JSON metadata
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


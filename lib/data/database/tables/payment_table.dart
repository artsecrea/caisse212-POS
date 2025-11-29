import 'package:drift/drift.dart';

class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  TextColumn get code => text().unique()();
  RealColumn get amount => real()();
  TextColumn get metaData => text().nullable()(); // JSON metadata
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


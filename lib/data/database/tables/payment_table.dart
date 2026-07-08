import 'package:drift/drift.dart';

class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get date => dateTime().clientDefault(() => DateTime.now())();
  TextColumn get code => text().unique()();
  RealColumn get amount => real()();
  TextColumn get metaData => text().nullable()(); // JSON metadata
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}


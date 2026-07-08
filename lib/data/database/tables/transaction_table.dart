import 'package:drift/drift.dart';

class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get paymentId => integer()();
  TextColumn get referenceId => text().nullable()();
  RealColumn get amount => real()();
  DateTimeColumn get date => dateTime().clientDefault(() => DateTime.now())();
  TextColumn get type => text()(); // CARD, CASH, etc.
  TextColumn get metaData => text().nullable()(); // JSON metadata
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}


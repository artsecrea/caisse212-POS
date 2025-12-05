import 'package:drift/drift.dart';

class Tickets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get num => text()(); // Format: 0001, 0002, etc.
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  IntColumn get orderId => integer()();
  IntColumn get printCount => integer().withDefault(const Constant(0))();
  TextColumn get paymentMethod => text()(); // TransactionType enum value
  RealColumn get amount => real()();
  BoolColumn get isPaid => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

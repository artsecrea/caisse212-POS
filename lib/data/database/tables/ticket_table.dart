import 'package:drift/drift.dart';
import 'package:posecrea/data/database/app_database.dart';

class Tickets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get num => text()(); // Format: 0001, 0002, etc.
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  IntColumn get orderId => integer().references(Order, #id,onDelete: KeyAction.cascade)();
  IntColumn get sessionId => integer().nullable()(); // Link to cash session
  IntColumn get printCount => integer().withDefault(const Constant(0))();
  TextColumn get paymentMethod => text()(); // TransactionType enum value
  RealColumn get amount => real()();
  BoolColumn get isPaid => boolean().withDefault(const Constant(false))();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))(); // Track if synced to server
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

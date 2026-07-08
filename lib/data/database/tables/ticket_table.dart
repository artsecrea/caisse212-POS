import 'package:drift/drift.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/data/database/tables/order_table.dart';

class Tickets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get num => text()(); // Format: 0001, 0002, etc.
  DateTimeColumn get date => dateTime().clientDefault(() => DateTime.now())();
  IntColumn get orderId => integer().references(Orders, #id,onDelete: KeyAction.cascade)();
  IntColumn get sessionId => integer().nullable()(); // Link to cash session
  DateTimeColumn get zDay => dateTime().nullable()(); // Calendar day the session opened
  IntColumn get printCount => integer().withDefault(const Constant(0))();
  TextColumn get paymentMethod => text()(); // TransactionType enum value
  RealColumn get amount => real()();
  BoolColumn get isPaid => boolean().withDefault(const Constant(false))();
  BoolColumn get isCancelled => boolean().withDefault(const Constant(false))(); // Whether ticket belongs to a cancelled order
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))(); // Track if synced to server
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

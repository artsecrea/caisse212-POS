import 'package:drift/drift.dart';

class OrderProducts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer()();
  IntColumn get productId => integer()();
  IntColumn get ticketId => integer().nullable()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  RealColumn get unitaryPrice => real()();
  RealColumn get unitaryDiscount => real().withDefault(const Constant(0.0))();
  RealColumn get unitaryTva => real().withDefault(const Constant(0.0))();
  RealColumn get manualDiscount => real().withDefault(const Constant(0.0))();
  TextColumn get manualDiscountReason => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('PENDING'))(); // PENDING, PREPARING, COMPLETED, CANCELED
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

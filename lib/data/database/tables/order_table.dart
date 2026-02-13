import 'package:drift/drift.dart';

class Orders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().unique()();
  TextColumn get status => text().withDefault(const Constant('ONHOLD'))(); // ONHOLD, PENDING, PREPARING, READY, DELIVERED
  TextColumn get type => text().withDefault(const Constant('DINE_IN'))(); // DINE_IN, TAKE_AWAY, DELIVERY
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get coupon => text().nullable()();
  IntColumn get persons => integer().withDefault(const Constant(1))();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  IntColumn get paymentId => integer().nullable()();
  IntColumn get tableId => integer().nullable()();
  TextColumn get source => text().nullable()(); // Source of the order (table, kiosk, etc.)
  IntColumn get sourceId => integer().nullable()();
  RealColumn get discountPercentage => real().withDefault(const Constant(0.0))(); // Manual discount percentage (0-100)
  IntColumn get createdBy => integer().nullable()(); // User who created the order
  IntColumn get takenBy => integer().nullable()(); // User who took the order
  IntColumn get clientId => integer().nullable()();
  IntColumn get commercialId => integer().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


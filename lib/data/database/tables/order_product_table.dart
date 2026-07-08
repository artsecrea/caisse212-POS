import 'package:drift/drift.dart';

class OrderProducts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer()();
  IntColumn get productId => integer()();
  IntColumn get variantId => integer().nullable()();
  IntColumn get ticketId => integer().nullable()();
  RealColumn get quantity => real().withDefault(const Constant(1.0))();
  RealColumn get unitaryPrice => real()();
  RealColumn get unitaryDiscount => real().withDefault(const Constant(0.0))();
  RealColumn get unitaryTva => real().withDefault(const Constant(0.0))();
  RealColumn get manualDiscount => real().withDefault(const Constant(0.0))();
  TextColumn get note => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('PENDING'))(); // PENDING, PREPARING, COMPLETED, CANCELED (KDS) | PAID (cashier)
  DateTimeColumn get planStartAt => dateTime().nullable()(); // Planned start time
  DateTimeColumn get planEndAt => dateTime().nullable()(); // Planned end time
  IntColumn get planWaiterId => integer().nullable()(); // Assigned waiter for this booking
  DateTimeColumn get kdsPrintedAt => dateTime().nullable()(); // When item was sent to kitchen (KDS ticket printed)
  RealColumn get kdsPrintedQuantity => real().withDefault(const Constant(0.0))(); // Quantity already sent to kitchen — enables modifications-only delta printing when qty increases
  DateTimeColumn get zDay => dateTime().nullable()(); // Calendar day the session opened (inherited from parent order)
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

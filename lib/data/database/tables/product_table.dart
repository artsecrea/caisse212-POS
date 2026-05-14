import 'package:drift/drift.dart';

class Products extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get barcode => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get description => text().nullable()();
  RealColumn get price => real()();
  TextColumn get uom => text().withDefault(const Constant('unit'))();
  IntColumn get categoryId => integer().nullable()();
  IntColumn get stationId => integer().nullable()();
  RealColumn get tvaAmount => real().withDefault(const Constant(0.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get finalPrice => real()();
  TextColumn get color => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get isVariant => boolean().withDefault(const Constant(false))();
  BoolColumn get isPlannable => boolean().withDefault(const Constant(false))();
  IntColumn get planDurationMinutes => integer().nullable()(); // Default plan duration in minutes
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


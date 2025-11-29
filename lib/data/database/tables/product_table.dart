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
  TextColumn get uom => text().withDefault(const Constant('unit'))(); // Unit of measurement
  IntColumn get categoryId => integer().nullable()();
  IntColumn get stationId => integer().nullable()();
  RealColumn get tvaAmount => real().withDefault(const Constant(0.0))();
  RealColumn get discountAmount => real().withDefault(const Constant(0.0))();
  RealColumn get finalPrice => real()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


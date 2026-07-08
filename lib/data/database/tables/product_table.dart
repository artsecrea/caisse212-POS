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
  /// MBW / PLU code used for scale-barcode lookup (nullable — only set for weighed products).
  TextColumn get mbwCode => text().nullable()();
  /// Price per kg stored in centimes (nullable — only set for weighed products).
  IntColumn get pricePerKg => integer().nullable()();
  /// Unit label from the server (e.g. "kg", "pcs", "box") — nullable.
  TextColumn get unitName => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}


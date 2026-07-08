import 'package:drift/drift.dart';

/// Product variants table - stores variant combinations for products
class ProductVariants extends Table {
  IntColumn get id => integer()();
  IntColumn get productId => integer()();
  TextColumn get name => text()();
  TextColumn get barcode => text().nullable()();
  TextColumn get sku => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get color => text().nullable()();
  TextColumn get tags => text().nullable()();
  RealColumn get price => real()();
  RealColumn get cost => real().nullable()();
  RealColumn get tvaAmount => real().withDefault(const Constant(0.0))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

/// Variant attribute values - stores the attribute-value pairs for each variant
class VariantAttributeValues extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get variantId => integer()();
  IntColumn get attributeId => integer()();
  TextColumn get attributeName => text().nullable()();
  IntColumn get valueId => integer()();
  TextColumn get value => text().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();

  @override
  List<String> get customConstraints => [
    'UNIQUE(variant_id, attribute_id)',
  ];
}


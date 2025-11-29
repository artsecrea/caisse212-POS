import 'package:drift/drift.dart';

/// Many-to-many relationship between Products and Components
/// Defines which components are available for which products
class ProductComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer()();
  IntColumn get componentId => integer()();
  RealColumn get defaultPrice => real().withDefault(const Constant(0.0))(); // Default price for this component on this product
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))(); // If component is required for this product
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


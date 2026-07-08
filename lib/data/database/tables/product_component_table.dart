import 'package:drift/drift.dart';

/// Many-to-many relationship between Products and Components
/// Defines which components are available for which products
class ProductComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer()();
  IntColumn get componentId => integer()();
  RealColumn get defaultPrice => real().withDefault(const Constant(0.0))(); // Default price for this component on this product
  IntColumn get defaultQuantity => integer().withDefault(const Constant(0))(); // Default quantity for this component on this product
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))(); // If component is required for this product
  IntColumn get minQuantity => integer().withDefault(const Constant(0))(); // Minimum quantity required
  IntColumn get maxQuantity => integer().withDefault(const Constant(10))(); // Maximum quantity allowed
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

// run flutter pub run build_runner build --delete-conflicting-outputs to generate the code for this table
import 'package:drift/drift.dart';

/// Many-to-many relationship between Products and Components
/// Defines which components are available for which products
class ProductComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer()();
  IntColumn get componentId => integer()();
  /// Per-product price override. NULL means "no override" — fall back to the
  /// component's own catalogue price — which is a different statement from an
  /// override of 0.0, a deliberately free option. Collapsing the two priced
  /// every un-overridden option at nothing.
  RealColumn get defaultPrice => real().nullable()();
  IntColumn get defaultQuantity => integer().withDefault(const Constant(0))(); // Default quantity for this component on this product
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))(); // If component is required for this product
  IntColumn get minQuantity => integer().withDefault(const Constant(0))(); // Minimum quantity required
  IntColumn get maxQuantity => integer().withDefault(const Constant(10))(); // Maximum quantity allowed
  /// Removing this default does NOT lower the price — "no cheese" costs what
  /// cheese costs. Set per link in the back office; false everywhere else, so
  /// nothing changes for a catalogue that has never used it.
  BoolColumn get chargeOnRemoval => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

// run flutter pub run build_runner build --delete-conflicting-outputs to generate the code for this table
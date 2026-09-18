import 'package:drift/drift.dart';

class ComponentGroups extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();
  TextColumn get description => text().nullable()();

  /// Swatch shown behind the group header, e.g. '#ff0000'.
  TextColumn get color => text().nullable()();

  /// How the group is picked from: 'SINGLE' (radio), 'MULTIPLE' (checkbox,
  /// one each) or 'QUANTITY' (steppers). QUANTITY is the default because it
  /// is the permissive behaviour every existing group already had.
  TextColumn get selectionType =>
      text().withDefault(const Constant('QUANTITY'))();

  /// Minimum selected units across the group. 0 = optional; the group is
  /// required when this is > 0 — there is no separate flag.
  IntColumn get minSelection => integer().withDefault(const Constant(0))();

  /// Maximum selected units. NULL = unlimited.
  IntColumn get maxSelection => integer().nullable()();

  /// How many selected units are included in the product price. The most
  /// expensive ones are the free ones.
  IntColumn get freeQuantity => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}


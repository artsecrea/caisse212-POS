import 'package:drift/drift.dart';

class Components extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
  TextColumn get description => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  RealColumn get price => real().withDefault(const Constant(0.0))();
  IntColumn get componentGroupId => integer().nullable()();

  /// The "86 it" switch. False means the kitchen is out of it: keep the row
  /// (history and old tickets still reference it) but never offer it.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get displayOrder => integer().withDefault(const Constant(0))();

  /// The catalogue product this option *is*, when it is one — a Coca served
  /// as part of a menu is the same Coca that sits on the shelf. The backend
  /// uses it to deduct stock; the POS uses it to route the option to that
  /// product's own station, so the bar prints the drink even though the
  /// kitchen owns the parent line.
  IntColumn get linkedProductId => integer().nullable()();
  IntColumn get linkedVariantId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}


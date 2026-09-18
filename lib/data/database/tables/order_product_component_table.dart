import 'package:drift/drift.dart';

class OrderProductComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get componentId => integer()();
  IntColumn get orderProductId => integer()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  RealColumn get price => real().withDefault(const Constant(0.0))(); // Price at order time
  BoolColumn get isSpecial => boolean().withDefault(const Constant(false))();
  // Name captured at order time. Protects a historical ticket from a later
  // rename or a deleted (86'd) component — the live components table can no
  // longer answer what this modifier was called when it was sold.
  TextColumn get name => text().nullable()();
  /// A money row, not a prep row: the customer took a paid-for default off and
  /// is still charged. It must never reach the kitchen as something to make,
  /// and must never be sent to the server as a plain option (which would
  /// deduct stock for something nobody served).
  BoolColumn get removalCharge => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}


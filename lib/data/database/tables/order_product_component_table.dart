import 'package:drift/drift.dart';

class OrderProductComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get componentId => integer()();
  IntColumn get orderProductId => integer()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  RealColumn get price => real().withDefault(const Constant(0.0))(); // Price at order time
  BoolColumn get isSpecial => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}


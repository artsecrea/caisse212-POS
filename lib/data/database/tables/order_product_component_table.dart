import 'package:drift/drift.dart';

class OrderProductComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get componentId => integer()();
  IntColumn get orderProductId => integer()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  BoolColumn get isSpecial => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


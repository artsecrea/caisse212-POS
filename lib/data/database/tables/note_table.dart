import 'package:drift/drift.dart';
import 'order_table.dart';

class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get content => text().withDefault(const Constant(''))();
  TextColumn get color => text().withDefault(const Constant('#FFFF88'))(); // Hex color like #FFFF88
  RealColumn get posX => real().withDefault(const Constant(20.0))();
  RealColumn get posY => real().withDefault(const Constant(20.0))();
  RealColumn get width => real().withDefault(const Constant(200.0))();
  RealColumn get height => real().withDefault(const Constant(180.0))();
  IntColumn get orderId => integer().nullable().references(Orders, #id, onDelete: KeyAction.setNull)();
  TextColumn get orderCode => text().nullable()(); // Denormalized for display without join
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}


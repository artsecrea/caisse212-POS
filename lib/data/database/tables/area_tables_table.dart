import 'package:drift/drift.dart';

class AreaTables extends Table {
  IntColumn get id => integer()();
  TextColumn get name => text()();
  
  @override
  Set<Column> get primaryKey => {id};
  TextColumn get tableState => text().withDefault(const Constant('AVAILABLE'))(); // AVAILABLE, OCCUPIED, RESERVED

  TextColumn get description => text().nullable()();
  IntColumn get capacity => integer().withDefault(const Constant(4))();
  IntColumn get areaId => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

  IntColumn get orderId => integer().nullable()();
}

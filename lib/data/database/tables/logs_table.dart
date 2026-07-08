
import 'package:drift/drift.dart';

import 'order_table.dart';

class OrderLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(Orders, #id)();
  TextColumn get action => text()(); //  'UPDATED', 'DELETED'
  TextColumn get description => text().nullable()(); // eg 'added product';
  DateTimeColumn get timestamp => dateTime().clientDefault(() => DateTime.now())();
}
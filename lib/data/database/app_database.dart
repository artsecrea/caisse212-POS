import 'dart:io';
import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/category_table.dart';
import 'tables/product_table.dart';
import 'tables/user_table.dart';
import 'tables/component_table.dart';
import 'tables/component_group_table.dart';
import 'tables/product_component_table.dart';
import 'tables/area_table.dart';
import 'tables/area_tables_table.dart';
import 'tables/station_table.dart';
import 'tables/kiosk_table.dart';
import 'tables/kds_table.dart';
import 'tables/commercial_table.dart';
import 'tables/customer_table.dart';
import 'tables/order_table.dart';
import 'tables/order_product_table.dart';
import 'tables/order_product_component_table.dart';
import 'tables/payment_table.dart';
import 'tables/transaction_table.dart';
import 'tables/cash_session_table.dart';
import 'tables/ticket_table.dart';
import 'tables/pending_sync_operation_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Categories,
  Products,
  Users,
  Components,
  ComponentGroups,
  ProductComponents,
  Areas,
  AreaTables,
  Stations,
  Kiosks,
  KDSs,
  Commercials,
  Customers,
  Orders,
  OrderProducts,
  OrderProductComponents,
  Payments,
  Transactions,
  CashSessions,
  Tickets,
  PendingSyncOperations,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  //never change the db version , just delete the db file to reset
  int get schemaVersion => 1;

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'caisse212.db'));
      return NativeDatabase(file);
    });
  }
}


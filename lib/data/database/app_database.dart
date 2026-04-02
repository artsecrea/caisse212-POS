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
import 'tables/logs_table.dart';
import 'tables/product_variant_table.dart';
import 'tables/waiter_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  Categories,
  Products,
  ProductVariants,
  VariantAttributeValues,
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
  OrderLogs,
  Waiters,
  WaiterAreas,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  static String dbName = 'sqd.db';

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          // Rename manual_discount_reason → note in order_products
          // SQLite doesn't support RENAME COLUMN directly before 3.25.0,
          // so we add the new column and migrate data.
          try {
            await customStatement(
              'ALTER TABLE order_products ADD COLUMN note TEXT;',
            );
            await customStatement(
              'UPDATE order_products SET note = manual_discount_reason WHERE manual_discount_reason IS NOT NULL;',
            );
          } catch (e) {
            // Column may already exist if fresh install
          }
        }
        if (from < 3) {
          // Add color column to products and categories
          try {
            await customStatement(
              'ALTER TABLE products ADD COLUMN color TEXT;',
            );
          } catch (e) {
            // Column may already exist
          }
          try {
            await customStatement(
              'ALTER TABLE categories ADD COLUMN color TEXT;',
            );
          } catch (e) {
            // Column may already exist
          }
        }
      },
    );
  }

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      try {
        final dbFolder = await getApplicationDocumentsDirectory();
        final file = File(p.join(dbFolder.path, dbName));

        // Ensure directory exists
        if (!await dbFolder.exists()) {
          await dbFolder.create(recursive: true);
        }
        print(">>>>>>>>"+dbFolder.path);

        return NativeDatabase.createInBackground(file);
      } catch (e) {
        // Fallback: try using executable directory on Windows
        if (Platform.isWindows) {
          try {
            final exePath = Platform.resolvedExecutable;
            final exeDir = File(exePath).parent.path;
            final dataDir = Directory(p.join(exeDir, 'data'));
            if (!await dataDir.exists()) {
              await dataDir.create(recursive: true);
            }
            final file = File(p.join(dataDir.path, dbName));
            return NativeDatabase.createInBackground(file);
          } catch (e2) {
            rethrow;
          }
        }
        rethrow;
      }
    });
  }
}


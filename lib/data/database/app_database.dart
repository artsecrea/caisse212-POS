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
import 'tables/note_table.dart';

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
  Notes,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  static String dbName = 'sqd.db';

  @override
  int get schemaVersion => 8;

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
        if (from < 4) {
          // Add cancellationReason to orders
          try {
            await customStatement(
              'ALTER TABLE orders ADD COLUMN cancellation_reason TEXT;',
            );
          } catch (e) {
            // Column may already exist
          }
          // Add isCancelled to tickets
          try {
            await customStatement(
              'ALTER TABLE tickets ADD COLUMN is_cancelled INTEGER NOT NULL DEFAULT 0;',
            );
          } catch (e) {
            // Column may already exist
          }
        }
        if (from < 5) {
          // Add planning fields to products
          try {
            await customStatement(
              'ALTER TABLE products ADD COLUMN is_plannable INTEGER NOT NULL DEFAULT 0;',
            );
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
              'ALTER TABLE products ADD COLUMN plan_duration_minutes INTEGER;',
            );
          } catch (e) {/* may already exist */}
          // Add planning fields to order_products
          try {
            await customStatement(
              'ALTER TABLE order_products ADD COLUMN plan_start_at INTEGER;',
            );
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
              'ALTER TABLE order_products ADD COLUMN plan_end_at INTEGER;',
            );
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
              'ALTER TABLE order_products ADD COLUMN plan_waiter_id INTEGER;',
            );
          } catch (e) {/* may already exist */}
        }
        if (from < 6) {
          // Add session_id to orders for Z-report locking
          try {
            await customStatement(
              'ALTER TABLE orders ADD COLUMN session_id INTEGER;',
            );
          } catch (e) {/* may already exist */}

          // Backfill pass 1: from ticket session_id (most accurate — ticket was paid in that session)
          try {
            await customStatement('''
              UPDATE orders
              SET session_id = (
                SELECT t.session_id FROM tickets t
                WHERE t.order_id = orders.id AND t.session_id IS NOT NULL
                LIMIT 1
              )
              WHERE orders.session_id IS NULL
                AND EXISTS (
                  SELECT 1 FROM tickets t
                  WHERE t.order_id = orders.id AND t.session_id IS NOT NULL
                );
            ''');
          } catch (e) {/* non-fatal */}

          // Backfill pass 2: match cashier session by time window (started_at <= order.created_at <= ended_at)
          try {
            await customStatement('''
              UPDATE orders
              SET session_id = (
                SELECT cs.id FROM cash_sessions cs
                WHERE cs.cashier_id = orders.taken_by
                  AND cs.started_at <= orders.created_at
                  AND (cs.ended_at IS NULL OR cs.ended_at >= orders.created_at)
                ORDER BY cs.started_at DESC
                LIMIT 1
              )
              WHERE orders.session_id IS NULL
                AND orders.taken_by IS NOT NULL;
            ''');
          } catch (e) {/* non-fatal */}

          // Backfill pass 3: last resort — most recent session for that cashier
          try {
            await customStatement('''
              UPDATE orders
              SET session_id = (
                SELECT cs.id FROM cash_sessions cs
                WHERE cs.cashier_id = orders.taken_by
                ORDER BY cs.started_at DESC
                LIMIT 1
              )
              WHERE orders.session_id IS NULL
                AND orders.taken_by IS NOT NULL;
            ''');
          } catch (e) {/* non-fatal */}
        }
        if (from < 7) {
          // Add notes table
          await m.createTable(notes);
        }
        if (from < 8) {
          // Add MBW code and price-per-kg columns for scale/weighed products.
          try {
            await customStatement('ALTER TABLE products ADD COLUMN mbw_code TEXT;');
          } catch (e) {/* may already exist */}
          try {
            await customStatement('ALTER TABLE products ADD COLUMN price_per_kg INTEGER;');
          } catch (e) {/* may already exist */}
          // Index for fast PLU lookups during scale barcode scanning.
          try {
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_products_mbw_code ON products(mbw_code);',
            );
          } catch (e) {/* non-fatal */}
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

// flutter build runner build --delete-conflicting-outputs
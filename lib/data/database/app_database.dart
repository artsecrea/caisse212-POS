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
import 'tables/activity_log_table.dart';
import 'tables/product_station_table.dart';

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
  ActivityLogs,
  ProductStations,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  static String dbName = 'sqd.db';

  @override
  int get schemaVersion => 24;

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
        if (from < 9) {
          // Add kds_printed_at column to order_products for KDS printing tracking.
          try {
            await customStatement('ALTER TABLE order_products ADD COLUMN kds_printed_at INTEGER;');
          } catch (e) {/* may already exist */}
        }
        if (from < 10) {
          // Add display_name to users for custom display name.
          try {
            await customStatement('ALTER TABLE users ADD COLUMN display_name TEXT;');
          } catch (e) {/* may already exist */}
        }
        if (from < 11) {
          // Add activity (audit) log table.
          await m.createTable(activityLogs);
        }
        if (from < 12) {
          // Add product↔station join table for multi-station products.
          await m.createTable(productStations);
        }
        if (from < 13) {
          // Add delivery address to orders.
          try {
            await customStatement('ALTER TABLE orders ADD COLUMN address TEXT;');
          } catch (e) {/* may already exist */}
        }
        if (from < 14) {
          // Z-report / cash-count columns on cash_sessions.
          try {
            await customStatement(
                'ALTER TABLE cash_sessions ADD COLUMN counted_cash REAL;');
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
                'ALTER TABLE cash_sessions ADD COLUMN variance REAL;');
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
                'ALTER TABLE cash_sessions ADD COLUMN counted_at DATETIME;');
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
                'ALTER TABLE cash_sessions ADD COLUMN count_notes TEXT;');
          } catch (e) {/* may already exist */}
        }
        if (from < 15) {
          // Explicit indexes for fast user lookups (admin-credential dialog
          // and any type-filtered fetch). username already has an implicit
          // unique index; we restate it for clarity + speedup on type.
          try {
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);',
            );
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_users_type ON users(type);',
            );
          } catch (e) {/* may already exist */}
        }
        if (from < 16) {
          // Customer identity rework: phone becomes the dedup key.
          //  • Add phone_normalized column (canonical form for sync upsert).
          //  • Backfill it for every existing row that has a non-empty phone.
          //  • Create a partial UNIQUE index so local duplicates surface
          //    immediately instead of waiting for the server bulk POST.
          try {
            await customStatement(
              'ALTER TABLE customers ADD COLUMN phone_normalized TEXT;',
            );
          } catch (e) {/* may already exist */}
          try {
            // Best-effort backfill: strip non-digits, peel a leading 0,
            // prefix the default country code (212 — Morocco). Existing
            // rows missing a phone stay null and will be re-synced as
            // "anonymous" customers if/when they're touched again.
            await customStatement(
              "UPDATE customers SET phone_normalized = "
              "CASE WHEN phone IS NULL OR TRIM(phone) = '' THEN NULL "
              "ELSE '212' || "
              "  CASE WHEN substr(REPLACE(REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', ''), ')', ''), 1, 1) = '0' "
              "       THEN substr(REPLACE(REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', ''), ')', ''), 2) "
              "       ELSE REPLACE(REPLACE(REPLACE(REPLACE(phone, ' ', ''), '-', ''), '(', ''), ')', '') "
              "  END "
              "END "
              "WHERE phone_normalized IS NULL;",
            );
          } catch (e) {/* keep migration moving — UI will renormalize on next edit */}
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS '
              'idx_customers_phone_normalized ON customers(phone_normalized) '
              'WHERE phone_normalized IS NOT NULL;',
            );
          } catch (e) {/* duplicates exist — log + skip; admin must dedup */}
        }
        if (from < 17) {
          // Tip column on orders. Nullable so existing rows stay valid;
          // backend treats null + 0 differently (null = no tip recorded,
          // 0 explicitly cleared) — we mirror that semantic locally.
          try {
            await customStatement(
              'ALTER TABLE orders ADD COLUMN tip REAL;',
            );
          } catch (e) {/* may already exist */}
        }
        if (from < 18) {
          // PIN-based waiter auth. Pin is nullable to keep existing rows
          // valid while the backend rolls out pin assignment; the partial
          // unique index allows multiple NULLs to coexist but enforces
          // uniqueness on every non-null pin (same pattern used for
          // customers.phone_normalized at v16).
          try {
            await customStatement(
              'ALTER TABLE waiters ADD COLUMN pin TEXT;',
            );
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS '
              'idx_waiters_pin ON waiters(pin) '
              'WHERE pin IS NOT NULL;',
            );
          } catch (e) {/* duplicates exist — log + skip; admin must dedup */}
        }
        if (from < 19) {
          // SQLite cannot change column type with ALTER TABLE, so we recreate
          // order_products with quantity as REAL (was INTEGER).
          // Explicit column list avoids positional mismatch caused by older
          // installs that had columns appended via ALTER TABLE in different order.
          await customStatement('''
            CREATE TABLE order_products_new (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              order_id INTEGER NOT NULL,
              product_id INTEGER NOT NULL,
              variant_id INTEGER,
              ticket_id INTEGER,
              quantity REAL NOT NULL DEFAULT 1.0,
              unitary_price REAL NOT NULL,
              unitary_discount REAL NOT NULL DEFAULT 0.0,
              unitary_tva REAL NOT NULL DEFAULT 0.0,
              manual_discount REAL NOT NULL DEFAULT 0.0,
              note TEXT,
              state TEXT NOT NULL DEFAULT \'PENDING\',
              plan_start_at TEXT,
              plan_end_at TEXT,
              plan_waiter_id INTEGER,
              kds_printed_at TEXT,
              updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
          await customStatement('''
            INSERT INTO order_products_new (
              id, order_id, product_id, variant_id, ticket_id,
              quantity, unitary_price, unitary_discount, unitary_tva, manual_discount,
              note, state, plan_start_at, plan_end_at, plan_waiter_id,
              kds_printed_at, updated_at
            )
            SELECT
              id, order_id, product_id, variant_id, ticket_id,
              CAST(quantity AS REAL), unitary_price, unitary_discount, unitary_tva, manual_discount,
              note, state, plan_start_at, plan_end_at, plan_waiter_id,
              kds_printed_at, updated_at
            FROM order_products
          ''');
          await customStatement('DROP TABLE order_products');
          await customStatement(
            'ALTER TABLE order_products_new RENAME TO order_products',
          );
        }
        if (from < 20) {
          try {
            await customStatement(
              'ALTER TABLE products ADD COLUMN unit_name TEXT;',
            );
          } catch (e) {/* may already exist */}
        }
        if (from < 21) {
          // z_day: the calendar day the cash session opened.
          // Derived at insert time from the active session so it never changes
          // even when an order is created after midnight inside the same session.
          // Backfill: use session.started_at when available, else fall back to
          // the row's own creation timestamp.
          try {
            await customStatement('ALTER TABLE orders ADD COLUMN z_day TEXT;');
          } catch (e) {/* may already exist */}
          try {
            await customStatement('''
              UPDATE orders SET z_day =
                COALESCE(
                  (SELECT date(cs.started_at) || 'T00:00:00.000'
                     FROM cash_sessions cs WHERE cs.id = orders.session_id),
                  date(orders.created_at) || 'T00:00:00.000'
                )
              WHERE z_day IS NULL;
            ''');
          } catch (e) {/* non-fatal */}

          try {
            await customStatement('ALTER TABLE tickets ADD COLUMN z_day TEXT;');
          } catch (e) {/* may already exist */}
          try {
            await customStatement('''
              UPDATE tickets SET z_day =
                COALESCE(
                  (SELECT date(cs.started_at) || 'T00:00:00.000'
                     FROM cash_sessions cs WHERE cs.id = tickets.session_id),
                  date(tickets.date) || 'T00:00:00.000'
                )
              WHERE z_day IS NULL;
            ''');
          } catch (e) {/* non-fatal */}

          try {
            await customStatement('ALTER TABLE order_products ADD COLUMN z_day TEXT;');
          } catch (e) {/* may already exist */}
          try {
            // Inherit z_day from the parent order (orders already backfilled above).
            await customStatement('''
              UPDATE order_products SET z_day =
                (SELECT o.z_day FROM orders o WHERE o.id = order_products.order_id)
              WHERE z_day IS NULL;
            ''');
          } catch (e) {/* non-fatal */}
        }
        if (from < 22) {
          // kds_printed_quantity: how many units of a line have already been
          // sent to the kitchen. Enables modifications-only delta printing so
          // increasing an already-printed line's quantity fires a ticket for
          // just the added units.
          try {
            await customStatement(
              'ALTER TABLE order_products ADD COLUMN kds_printed_quantity REAL NOT NULL DEFAULT 0;',
            );
          } catch (e) {/* may already exist */}
          try {
            // Backfill: any line already sent to the kitchen counts its full
            // current quantity as printed, so it does NOT re-fire as a
            // modification on the next KDS print.
            await customStatement(
              'UPDATE order_products SET kds_printed_quantity = quantity WHERE kds_printed_at IS NOT NULL;',
            );
          } catch (e) {/* non-fatal */}
        }
        if (from < 23) {
          // Normalise legacy datetime text.
          //
          // With store_date_time_values_as_text, the old `currentDateAndTime`
          // column default emitted SQLite's CURRENT_TIMESTAMP — UTC, space
          // separator, no fraction ('2026-07-06 13:38:33') — while every Dart
          // insert wrote drift's local ISO form ('2026-07-06T15:09:42.000000
          // +01:00'). Two incompatible encodings in one TEXT column break the
          // string comparisons drift uses for date-range filters and retention
          // cutoffs (space 0x20 < 'T' 0x54), which silently hid rows on the
          // start day of any range. The column defaults are now clientDefault
          // (local, 'T') so NEW rows are consistent; this backfill fixes the
          // OLD space-format rows.
          //
          // We ONLY swap the space separator for 'T' — we do NOT rebase the
          // instant to local time. Rebasing (datetime(col,'localtime')) would
          // shift near-midnight historical rows onto a different calendar day
          // and depends on the migrating machine's TZ/DST history — unsafe for
          // past financial records. A pure separator swap makes the value
          // string-comparable and re-parseable without changing what instant
          // it represents. Only rows whose 11th char is a space (the legacy
          // form) are touched; already-'T' rows are left alone.
          Future<void> fixCol(String table, String col) async {
            try {
              await customStatement(
                "UPDATE $table SET $col = "
                "substr($col, 1, 10) || 'T' || substr($col, 12) "
                "WHERE $col IS NOT NULL AND substr($col, 11, 1) = ' ';",
              );
            } catch (e) {/* non-fatal — leave the row as-is */}
          }

          // Transactional + reporting columns that get compared or synced.
          await fixCol('tickets', 'date');
          await fixCol('tickets', 'updated_at');
          await fixCol('orders', 'date');
          await fixCol('orders', 'created_at');
          await fixCol('orders', 'updated_at');
          await fixCol('order_products', 'updated_at');
          await fixCol('payments', 'date');
          await fixCol('payments', 'created_at');
          await fixCol('payments', 'updated_at');
          await fixCol('transactions', 'date');
          await fixCol('transactions', 'created_at');
          await fixCol('transactions', 'updated_at');
          await fixCol('cash_sessions', 'started_at');
          await fixCol('cash_sessions', 'ended_at');
          await fixCol('cash_sessions', 'updated_at');
        }
        if (from < 24) {
          // Session-close totals: full takings + per-method breakdown snapshot.
          // `moneyAtEnd` stays the physical cash-drawer figure; these are added
          // alongside it so the Z-report/close covers every payment method.
          try {
            await customStatement(
                'ALTER TABLE cash_sessions ADD COLUMN total_paid REAL;');
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
                'ALTER TABLE cash_sessions ADD COLUMN details TEXT;');
          } catch (e) {/* may already exist */}
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
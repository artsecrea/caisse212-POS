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
import 'tables/product_component_group_table.dart';
import 'tables/serial_conflict_table.dart';
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
import 'tables/resource_table.dart';
import 'tables/product_resource_table.dart';
import 'tables/z_table.dart';
import 'tables/refund_table.dart';
import 'tables/product_unit_table.dart';
import 'tables/cash_movement_table.dart';
import 'tables/removed_order_item_table.dart';
import 'tables/serial_table.dart';
import 'tables/integration_mapping_table.dart';
import 'tables/provider_table.dart';
import 'tables/agenda_booking_table.dart';
import 'tables/ticket_draft_split_table.dart';
import 'tables/pending_notification_table.dart';
import 'tables/order_number_counter_table.dart';
import '../../utils/pos_log.dart';

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
  ProductComponentGroups,
  SerialConflicts,
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
  Resources,
  ProductResources,
  Zs,
  Refunds,
  RefundLines,
  ProductUnits,
  CashMovements,
  RemovedOrderItems,
  Serials,
  IntegrationMappings,
  Providers,
  AgendaBookings,
  TicketDraftSplits,
  PendingNotifications,
  OrderNumberCounters,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Injects a caller-supplied executor — used by tests to run against an
  /// in-memory database instead of the on-disk one. Production code always uses
  /// the default constructor.
  AppDatabase.forTesting(super.executor);

  static String dbName = 'sqd.db';

  @override
  int get schemaVersion => 57;

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
        if (from < 25) {
          // Z (shift) tracking: a Z owns one or more cash sessions.
          try {
            await m.createTable(zs);
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
                'ALTER TABLE cash_sessions ADD COLUMN z_id INTEGER;');
          } catch (e) {/* may already exist */}
        }
        if (from < 26) {
          // Product reference / SKU — searchable, nullable.
          try {
            await customStatement(
                'ALTER TABLE products ADD COLUMN reference TEXT;');
          } catch (e) {/* may already exist */}
        }
        if (from < 27) {
          // KDS stage timestamps on order_products — for local kitchen stats.
          // TEXT because build.yaml sets store_date_time_values_as_text: true.
          for (final col in const ['preparing_at', 'ready_at', 'served_at']) {
            try {
              await customStatement(
                  'ALTER TABLE order_products ADD COLUMN $col TEXT;');
            } catch (e) {/* may already exist */}
          }
        }
        if (from < 43) {
          // Reserved value and resource type on the cached diary.
          for (final col in const [
            'value REAL NULL',
            'plan_resource_type TEXT NULL',
          ]) {
            try {
              await customStatement(
                  'ALTER TABLE agenda_bookings ADD COLUMN $col;');
            } catch (e) {/* may already exist */}
          }
        }
        if (from < 57) {
          // Counters behind the per-session order number, one per scope.
          try {
            await m.createTable(orderNumberCounters);
          } catch (e) {/* may already exist */}
        }
        if (from < 56) {
          // Per-session order number.
          try {
            await customStatement(
                'ALTER TABLE orders ADD COLUMN session_order_no INTEGER NULL;');
          } catch (e) {/* may already exist */}
        }
        if (from < 55) {
          // Notification outbox: kept until the server accepts each one.
          try {
            await m.createTable(pendingNotifications);
          } catch (e) {/* may already exist */}
        }
        if (from < 54) {
          // Z v3 audit flags: system-closed sessions and time-limit overrides.
          for (final stmt in const [
            'ALTER TABLE cash_sessions ADD COLUMN auto_closed '
                'INTEGER NOT NULL DEFAULT 0 CHECK (auto_closed IN (0, 1));',
            'ALTER TABLE cash_sessions ADD COLUMN z_override '
                'INTEGER NOT NULL DEFAULT 0 CHECK (z_override IN (0, 1));',
            'ALTER TABLE zs ADD COLUMN open_override '
                'INTEGER NOT NULL DEFAULT 0 CHECK (open_override IN (0, 1));',
          ]) {
            try {
              await customStatement(stmt);
            } catch (e) {/* may already exist */}
          }
        }
        if (from < 53) {
          // Z contract v3: a Z is a (zDay, zSeq) label carried on sessions.
          for (final stmt in const [
            'ALTER TABLE zs ADD COLUMN z_day TEXT NULL;',
            'ALTER TABLE zs ADD COLUMN z_seq INTEGER NOT NULL DEFAULT 1;',
            'ALTER TABLE zs ADD COLUMN open_mode TEXT NULL;',
            'ALTER TABLE zs ADD COLUMN close_mode TEXT NULL;',
            'ALTER TABLE cash_sessions ADD COLUMN money_entered REAL NULL;',
            'ALTER TABLE cash_sessions ADD COLUMN money_carried_over REAL NULL;',
            'ALTER TABLE cash_sessions ADD COLUMN z_open_mode TEXT NULL;',
            'ALTER TABLE cash_sessions ADD COLUMN is_closing_session '
                'INTEGER NOT NULL DEFAULT 0 CHECK (is_closing_session IN (0, 1));',
            'ALTER TABLE cash_movements ADD COLUMN code TEXT NULL;',
            'ALTER TABLE cash_movements ADD COLUMN is_synced '
                'INTEGER NOT NULL DEFAULT 0 CHECK (is_synced IN (0, 1));',
          ]) {
            try {
              await customStatement(stmt);
            } catch (e) {/* may already exist */}
          }
          // Existing Zs take their opening calendar day — the only day they
          // were ever stamped with. Text datetimes start with yyyy-MM-dd.
          await customStatement(
              "UPDATE zs SET z_day = substr(started_at, 1, 10) WHERE z_day IS NULL;");
          await customStatement(
              "UPDATE cash_movements SET code = 'CM-L' || id WHERE code IS NULL;");
        }
        if (from < 52) {
          // Annulment tombstones: removing a line deletes its order_products
          // row, so without this the Z had nothing left to count.
          try {
            await m.createTable(removedOrderItems);
          } catch (e) {/* may already exist */}
        }
        if (from < 51) {
          // Courses (entrée / plat / dessert). Null on every existing row,
          // which is exactly right: nobody chose one, so nothing about how
          // their tickets print changes.
          try {
            await customStatement(
                'ALTER TABLE order_products ADD COLUMN course_no INTEGER;');
          } catch (e) {/* may already exist */}
        }

        if (from < 50) {
          // Delta printing for the CUSTOMER order ticket. Existing rows start
          // at 0, which reads as "nothing has been put on a slip yet" — so the
          // first additions-only print after upgrading behaves like a full
          // one, then settles into deltas. That is the honest default: we
          // genuinely do not know what was already handed to the customer.
          try {
            await customStatement('ALTER TABLE order_products ADD COLUMN '
                'order_ticket_printed_quantity REAL NOT NULL DEFAULT 0.0;');
          } catch (e) {/* may already exist */}
        }
        if (from < 49) {
          // Draft ticket-split arrangement — local only, see the table's own
          // doc comment. New, so a straight create; nothing to migrate.
          try {
            await m.createTable(ticketDraftSplits);
          } catch (e) {/* may already exist */}
        }
        if (from < 48) {
          // Units another till sold out from under us.
          try {
            await m.createTable(serialConflicts);
          } catch (e) {/* may already exist */}
        }
        if (from < 47) {
          // default_price becomes nullable so "no override" and "free" stop
          // being the same value. SQLite cannot drop NOT NULL in place, and
          // the column was written with a 0.0 default: rows that were never
          // overridden are indistinguishable from free ones now, so the
          // honest repair is to let the next sync restate them.
          try {
            await customStatement(
                'UPDATE product_components SET default_price = NULL '
                'WHERE default_price = 0;');
          } catch (e) {/* column already nullable, or table absent */}
        }
        if (from < 46) {
          // Charge-on-removal: the catalogue flag, and the local marker for a
          // billed removal so the signal survives a restart and a re-sync.
          try {
            await customStatement('ALTER TABLE product_components ADD COLUMN '
                'charge_on_removal INTEGER NOT NULL DEFAULT 0;');
          } catch (e) {/* may already exist */}
          try {
            await customStatement('ALTER TABLE order_product_components ADD '
                'COLUMN removal_charge INTEGER NOT NULL DEFAULT 0;');
          } catch (e) {/* may already exist */}
        }
        if (from < 45) {
          // The product an option stands for, so it can be routed to that
          // product's station.
          for (final col in const [
            'linked_product_id INTEGER NULL',
            'linked_variant_id INTEGER NULL',
          ]) {
            try {
              await customStatement('ALTER TABLE components ADD COLUMN $col;');
            } catch (e) {/* may already exist */}
          }
        }
        if (from < 44) {
          // Component group selection rules. The server has had these since
          // V138; the POS was rendering every group as free-for-all steppers
          // because it never stored them.
          for (final col in const [
            'color TEXT NULL',
            "selection_type TEXT NOT NULL DEFAULT 'QUANTITY'",
            'min_selection INTEGER NOT NULL DEFAULT 0',
            'max_selection INTEGER NULL',
            'free_quantity INTEGER NOT NULL DEFAULT 0',
          ]) {
            try {
              await customStatement(
                  'ALTER TABLE component_groups ADD COLUMN $col;');
            } catch (e) {/* may already exist */}
          }
          for (final col in const [
            'is_active INTEGER NOT NULL DEFAULT 1',
            'display_order INTEGER NOT NULL DEFAULT 0',
          ]) {
            try {
              await customStatement('ALTER TABLE components ADD COLUMN $col;');
            } catch (e) {/* may already exist */}
          }
          try {
            await m.createTable(productComponentGroups);
          } catch (e) {/* may already exist */}
        }
        if (from < 28) {
          // Booking resources: assigned resource on a scheduled line + the
          // Resources catalog and the per-product eligible pool.
          try {
            await customStatement(
                'ALTER TABLE order_products ADD COLUMN plan_resource_id INTEGER;');
          } catch (e) {/* may already exist */}
          try {
            await m.createTable(resources);
          } catch (e) {/* may already exist */}
          try {
            await m.createTable(productResources);
          } catch (e) {/* may already exist */}
        }
        if (from < 29) {
          // POS↔backend contract catch-up. All additive and nullable, so a
          // device that upgrades mid-shift keeps every existing row valid and
          // the old sync payloads keep working unchanged.

          // Delivery-platform routing + the ready-signal marker.
          for (final col in const [
            'external_order_id TEXT',
            'delivery_status TEXT',
            'courier_name TEXT',
            'courier_phone TEXT',
            'ready_signal_at TEXT', // TEXT: store_date_time_values_as_text
          ]) {
            try {
              await customStatement('ALTER TABLE orders ADD COLUMN $col;');
            } catch (e) {/* may already exist */}
          }

          // Line-level: the server's own line id (refunds reference it), the
          // sold UOM, and the discount reason.
          for (final col in const [
            'server_id INTEGER',
            'sale_uom_id INTEGER',
            'manual_discount_reason TEXT',
          ]) {
            try {
              await customStatement(
                  'ALTER TABLE order_products ADD COLUMN $col;');
            } catch (e) {/* may already exist */}
          }

          // Component name snapshot, so a rename or an 86 can't rewrite an
          // already-printed ticket.
          try {
            await customStatement(
                'ALTER TABLE order_product_components ADD COLUMN name TEXT;');
          } catch (e) {/* may already exist */}

          try {
            await m.createTable(refunds);
          } catch (e) {/* may already exist */}
          try {
            await m.createTable(refundLines);
          } catch (e) {/* may already exist */}
          try {
            await m.createTable(productUnits);
          } catch (e) {/* may already exist */}
        }
        if (from < 30) {
          // Split the discount reason out of `orders.note`. Applying a manual
          // discount used to write its reason into `note`, which is the field
          // the KDS and the kitchen ticket read — so discounting an order
          // silently replaced the kitchen instruction. Existing rows keep
          // whatever `note` holds; only new discounts write here.
          try {
            await customStatement(
                'ALTER TABLE orders ADD COLUMN discount_reason TEXT;');
          } catch (e) {/* may already exist */}
        }
        if (from < 31) {
          // Non-sale cash in/out of the drawer, so a petty-cash withdrawal
          // stops surfacing as unexplained Z-report variance.
          try {
            await m.createTable(cashMovements);
          } catch (e) {/* may already exist */}
        }
        if (from < 32) {
          // Local "86" flag. Defaults to 1 so every existing product stays
          // sellable; only an explicit kitchen action clears it.
          try {
            await customStatement(
                'ALTER TABLE products ADD COLUMN is_available INTEGER NOT NULL DEFAULT 1;');
          } catch (e) {/* may already exist */}
        }
        if (from < 33) {
          // Product cost, so order lines can carry a cost to the server for
          // margin reporting. Nullable — an unknown cost must not read as 0.
          try {
            await customStatement(
                'ALTER TABLE products ADD COLUMN cost REAL NULL;');
          } catch (e) {/* may already exist */}
        }
        if (from < 34) {
          // Per-line cost snapshot. Existing rows stay NULL; the sync falls back
          // to the catalogue cost for those, so historical orders still report.
          try {
            await customStatement(
                'ALTER TABLE order_products ADD COLUMN cost REAL NULL;');
          } catch (e) {/* may already exist */}
        }
        if (from < 35) {
          // Serial-managed products: the unit-level stock cache, the two
          // tracking flags, and the unit sold on a line.
          try {
            await m.createTable(serials);
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
                'ALTER TABLE products ADD COLUMN is_serial_tracked '
                'INTEGER NOT NULL DEFAULT 0;');
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
                'ALTER TABLE product_variants ADD COLUMN is_serial_tracked '
                'INTEGER NOT NULL DEFAULT 0;');
          } catch (e) {/* may already exist */}
          try {
            await customStatement(
                'ALTER TABLE order_products ADD COLUMN serial_id INTEGER NULL;');
          } catch (e) {/* may already exist */}
        }
        if (from < 36) {
          // Parked-refund marker — see Refunds.syncError.
          try {
            await customStatement(
                'ALTER TABLE refunds ADD COLUMN sync_error TEXT NULL;');
          } catch (e) {/* may already exist */}
        }
        if (from < 37) {
          // Distinguishes a typed amount from a derived one — see
          // RefundLines.amountOverridden. Existing rows are all derived.
          try {
            await customStatement(
                'ALTER TABLE refund_lines ADD COLUMN amount_overridden '
                'INTEGER NOT NULL DEFAULT 0;');
          } catch (e) {/* may already exist */}
        }
        if (from < 38) {
          // Platform item id -> our product/component, cached for offline
          // resolution of incoming marketplace orders.
          try {
            await m.createTable(integrationMappings);
          } catch (e) {/* may already exist */}
        }
        if (from < 39) {
          // Courier-facing platform code, kept on the order so reprints survive
          // the queue's 7-day purge.
          try {
            await customStatement(
                'ALTER TABLE orders ADD COLUMN external_order_code TEXT NULL;');
          } catch (e) {/* may already exist */}
        }
        if (from < 40) {
          // Delivery charge, tracked beside the products total like `tip`.
          // Left NULL on every existing row: "no fee recorded" is the honest
          // reading of history, and defaulting to 0 would claim every past
          // order shipped free.
          try {
            await customStatement(
                'ALTER TABLE orders ADD COLUMN delivery_fee REAL NULL;');
          } catch (e) {/* may already exist */}
        }
        if (from < 41) {
          // Bookable staff, and the last pulled diary they appear in. Both are
          // caches of server state, so a failed create is safe to swallow —
          // the next master sync refills them.
          try {
            await m.createTable(providers);
          } catch (e) {/* may already exist */}
          try {
            await m.createTable(agendaBookings);
          } catch (e) {/* may already exist */}
        }
        if (from < 42) {
          // Backend-tracked payment position, for service orders settled in
          // instalments. NULL on history: we were never told, which is not
          // the same as nothing having been paid.
          for (final col in const [
            'amount_paid REAL NULL',
            'balance_due REAL NULL',
            'payment_status TEXT NULL',
          ]) {
            try {
              await customStatement('ALTER TABLE orders ADD COLUMN $col;');
            } catch (e) {/* may already exist */}
          }
        }
      },
    );
  }

  /// The counter row an order in [session] draws from under [mode]
  /// (`session` | `z` | `manual`). A session with no Z falls back to its own
  /// scope rather than sharing one with every other Z-less session.
  static String orderNumberScope(String mode, CashSession session) {
    switch (mode) {
      case 'manual':
        return 'manual';
      case 'z':
        if (session.zId != null) return 'z:${session.zId}';
        return 'session:${session.id}';
      default:
        return 'session:${session.id}';
    }
  }

  /// Hands out the next order number for an order in [sessionId], or null
  /// when there is no such session (the order simply goes unnumbered).
  ///
  /// [mode] decides when the numbers restart: every cash session, every Z,
  /// or only when an admin resets them ([resetOrderNumber]). Increment and
  /// read run in one transaction so two orders arriving at once (cashier +
  /// waiter app) can never share a number.
  Future<int?> nextSessionOrderNo(int? sessionId,
      {String mode = 'session'}) async {
    if (sessionId == null) return null;
    return transaction(() async {
      final session = await (select(cashSessions)
            ..where((s) => s.id.equals(sessionId)))
          .getSingleOrNull();
      if (session == null) return null;
      final scope = orderNumberScope(mode, session);
      await customStatement(
        'INSERT INTO order_number_counters (scope, seq) VALUES (?, 1) '
        'ON CONFLICT(scope) DO UPDATE SET seq = seq + 1',
        [scope],
      );
      final row = await (select(orderNumberCounters)
            ..where((c) => c.scope.equals(scope)))
          .getSingle();
      return row.seq;
    });
  }

  /// Restarts the numbering the next order in [sessionId] would draw from,
  /// so it gets #1. Numbers already printed are left as they are. In
  /// `manual` mode [sessionId] is not needed.
  Future<void> resetOrderNumber(int? sessionId,
      {String mode = 'session'}) async {
    String? scope;
    if (mode == 'manual') {
      scope = 'manual';
    } else if (sessionId != null) {
      final session = await (select(cashSessions)
            ..where((s) => s.id.equals(sessionId)))
          .getSingleOrNull();
      if (session != null) scope = orderNumberScope(mode, session);
    }
    if (scope == null) return;
    await into(orderNumberCounters).insertOnConflictUpdate(
        OrderNumberCountersCompanion.insert(scope: scope, seq: const Value(0)));
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
        posLog(">>>>>>>>"+dbFolder.path);

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
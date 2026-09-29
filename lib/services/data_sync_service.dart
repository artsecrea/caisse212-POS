import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:drift/drift.dart';
import '../domain/models/serial_conflict.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/booking_models.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/pending_operations_service.dart';
import 'package:caisse212/services/product_cost_resolver.dart';
import 'package:caisse212/services/z_service.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../domain/models/business_day_config.dart';
import '../domain/models/session_rules.dart';
import 'notification_outbox.dart';
import 'z_day_resolver.dart';

/// Data Sync Service for fetching data from API and storing in local database
class DataSyncService {
  final AppDatabase _database;
  final ApiService _apiService;
  final SharedPreferences? _prefs;
  late final PendingOperationsService _pendingOpsService;
  final _logger = Logger.instance;

  /// Product `state` values the cloud legitimately owns, so a pull is allowed to
  /// overwrite the local line with them. Everything else (the kitchen micro-
  /// states PENDING/PREPARING/READY/COMPLETED) is LAN-local and driven by the
  /// KDS without syncing up, so the backend's copy is stale and must never
  /// clobber local progress on pull. See [pullOrderDelta].
  static const Set<String> serverOwnedProductStates = {'CANCELED', 'PAID'};

  final _syncedOrderController = StreamController<int>.broadcast();

  /// Emits the local DB id of any order that was just updated by a sync delta.
  Stream<int> get syncedOrderUpdatedStream => _syncedOrderController.stream;

  static const _kOrdersCursor        = 'sync_orders_cursor';
  static const _kPaymentsCursor      = 'sync_payments_cursor';
  static const _kOrdersLastSyncAt    = 'sync_orders_last_at';
  static const _kPaymentsLastSyncAt  = 'sync_payments_last_at';
  static const _kLastDeltaError      = 'sync_last_delta_error';

  DataSyncService(this._database, this._apiService, [this._prefs]) {
    _pendingOpsService = PendingOperationsService(_database);
  }

  /// Callback for progress updates
  Function(String message, double progress)? onProgress;

  /// Delete the local rows of [tableName] whose id is **not** in [serverIds].
  ///
  /// This is the non-destructive replacement for wiping a table before a sync:
  /// rows the server still knows about are updated in place (see the upserting
  /// `_persist*` helpers), and only the genuine leftovers — rows the admin
  /// deleted on the backend — are removed.
  ///
  /// Ids are read out and diffed in Dart rather than expressed as a giant
  /// `NOT IN (…)`: SQLite caps bound variables at ~999, and a catalog of a few
  /// thousand products would blow straight through it. The deletes then go out
  /// in chunks, the same pattern [clearOldSyncedData] uses.
  ///
  /// [protectWhere] is raw SQL naming rows that must never be reconciled away
  /// (e.g. a table currently holding an order). [extraKeepWhere] additionally
  /// spares rows that the sync does not own at all.
  ///
  /// Returns the number of rows deleted. Callers must not pass an empty
  /// [serverIds] for a table they cannot prove is genuinely empty server-side —
  /// that would be the old wipe by another name.
  Future<int> _reconcileDeletes(
    String tableName,
    Set<int> serverIds, {
    String idColumn = 'id',
    String? protectWhere,
  }) async {
    final rows = await _database
        .customSelect('SELECT $idColumn AS _rid FROM $tableName'
            '${protectWhere == null ? '' : ' WHERE NOT ($protectWhere)'}')
        .get();

    final stale = <int>[];
    for (final r in rows) {
      final id = r.data['_rid'];
      if (id is int && !serverIds.contains(id)) stale.add(id);
    }
    if (stale.isEmpty) return 0;

    const chunkSize = 500;
    for (var i = 0; i < stale.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, stale.length);
      final chunk = stale.sublist(i, end);
      // Values are ints read straight back out of SQLite — safe to inline.
      await _database.customStatement(
          'DELETE FROM $tableName WHERE $idColumn IN (${chunk.join(',')})');
    }
    return stale.length;
  }

  /// Move a UNIQUE value out of the way before upserting the row that now owns
  /// it.
  ///
  /// Four master tables carry a unique constraint *besides* the primary key:
  /// `users.username`, `commercials.cin`, and the partial indexes on
  /// `waiters.pin` and `customers.phone_normalized`. A real upsert conflicts on
  /// the primary key only, so if the admin reassigns a PIN from one waiter to
  /// another the insert would hit the secondary index and abort the entire sync
  /// transaction. (`INSERT OR REPLACE` never hit this because it resolved any
  /// unique conflict by deleting the other row — quietly losing it.)
  ///
  /// So we clear the value off whichever *other* local row is holding it.
  /// Nullable columns go to NULL; NOT NULL ones are parked on a sentinel that
  /// is always resolved before the transaction ends — the parked row is either
  /// updated by its own entry later in the same payload, or removed by the
  /// reconcile pass because the server no longer lists it.
  Future<void> _releaseUniqueValue(
    String tableName,
    String column,
    Object? value,
    int ownerId, {
    required bool nullable,
  }) async {
    if (value == null) return;
    final v = value.toString();
    if (v.isEmpty) return;
    await _database.customStatement(
      nullable
          ? 'UPDATE $tableName SET $column = NULL '
              'WHERE $column = ? AND id <> ?'
          : "UPDATE $tableName SET $column = '__sync_parked_' || id "
              'WHERE $column = ? AND id <> ?',
      [v, ownerId],
    );
  }

  /// Collect the `id` values out of a raw server payload.
  Set<int> _idsOf(List<Map<String, dynamic>> rows) {
    final ids = <int>{};
    for (final r in rows) {
      final id = r['id'];
      if (id is int) {
        ids.add(id);
      } else if (id is num) {
        ids.add(id.toInt());
      }
    }
    return ids;
  }

  /// Clear only master data (not transactional data like orders, tickets, sessions).
  ///
  /// **No longer used by [syncAllData]** — that path now upserts and reconciles
  /// (see [_reconcileDeletes]) instead of wiping. This remains the full-reset
  /// path used by [clearAllData] on tenant logout, where emptying the tables is
  /// exactly the intent.
  Future<void> clearMasterData() async {
    // Delete in reverse order of dependencies to avoid foreign key issues.
    await _database.delete(_database.kDSs).go();
    await _database.delete(_database.kiosks).go();
    // waiterAreas references waiters AND areas — drop before either.
    await _database.delete(_database.waiterAreas).go();
    await _database.delete(_database.areaTables).go();
    await _database.delete(_database.areas).go();
    await _database.delete(_database.productComponents).go();
    await _database.delete(_database.productUnits).go();
    await _database.delete(_database.variantAttributeValues).go();
    await _database.delete(_database.productVariants).go();
    await _database.delete(_database.products).go();
    await _database.delete(_database.components).go();
    await _database.delete(_database.componentGroups).go();
    await _database.delete(_database.stations).go();
    // Bookable resources catalog (product_resources is repopulated per-product
    // by _persistProducts, so it doesn't need a separate clear here).
    await _database.delete(_database.resources).go();
    await _database.delete(_database.categories).go();
    // Waiters + commercials are purely server-authoritative — wipe them so
    // backend deletes propagate to the device on the next sync.
    await _database.delete(_database.commercials).go();
    await _database.delete(_database.waiters).go();
    await _database.delete(_database.providers).go();
    await _database.delete(_database.agendaBookings).go();
    await _database.delete(_database.users).go();
  }

  /// Clear old synced data based on retention period.
  ///
  /// Scope is **orders and the rows that belong to them** — not customers,
  /// not cash sessions, not any other top-level entity. The previous version
  /// of this method had four flaws we've now fixed:
  ///
  ///  1. **It deleted customers** (by `createdAt`) — but customers are NOT
  ///     order data. A customer created 30 days ago is often still being
  ///     referenced by a recent order; deleting them left the order with a
  ///     dangling `clientId`. Customers are now left alone.
  ///  2. **It deleted cash sessions** — sessions are top-level financial
  ///     records (Z-reports, totals) and aren't strictly order data. Left
  ///     alone too; admins can purge them via the sessions screen if needed.
  ///  3. **It deleted tickets by their own `date`** instead of by their
  ///     order's eligibility — could orphan a ticket whose parent order had
  ///     been edited recently. Tickets are now deleted only when their
  ///     order is being deleted.
  ///  4. **Child rows were never cleaned up.** SQLite's `foreign_keys`
  ///     pragma is OFF in this app, so the `onDelete: cascade` declared in
  ///     `Tickets` and `Notes` does NOT fire — orderProducts,
  ///     orderProductComponents, orderLogs, payments, and transactions all
  ///     piled up forever as orphans. This method now manually cascades:
  ///     children first (OPCs → OPs → tickets/notes/logs/payments/
  ///     transactions), then the parent order itself. We also clear stale
  ///     `area_tables.orderId` pointers so a freed table doesn't keep
  ///     showing as busy.
  ///
  /// Wrapped in a single transaction so a partial failure rolls everything
  /// back rather than leaving the DB half-purged.
  /// Returns the number of orders deleted.
  Future<int> clearOldSyncedData(int retentionDays) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));
    var deletedOrders = 0;

    await _database.transaction(() async {
      // 1. Find the set of orders eligible for deletion.
      //
      // Eligibility = synced AND paid AND older than the cutoff.
      // - `isSynced=true` protects orders that haven't reached the server yet
      //   (deleting them would lose data permanently).
      // - `paymentId IS NOT NULL` protects unpaid orders — an order with no
      //   linked payment is still "open business" (held tab, abandoned cart,
      //   layby, etc.) and must never be auto-purged regardless of age.
      // - `updatedAt < cutoff` is the retention window.
      final eligible = await (_database.select(_database.orders)
            ..where((o) =>
                o.isSynced.equals(true) &
                o.paymentId.isNotNull() &
                o.updatedAt.isSmallerThanValue(cutoffDate)))
          .get();
      if (eligible.isEmpty) return;
      deletedOrders = eligible.length;
      final orderIds = eligible.map((o) => o.id).toList();
      final paymentIds = eligible
          .where((o) => o.paymentId != null)
          .map((o) => o.paymentId!)
          .toSet()
          .toList();

      // 2. Cascade — chunk by 500 to stay clear of SQLite's
      //    SQLITE_MAX_VARIABLE_NUMBER (typically 999) on large purges.
      Future<void> deleteInChunks<T>(
        List<int> ids,
        Future<void> Function(List<int> chunk) deleter,
      ) async {
        const chunkSize = 500;
        for (var i = 0; i < ids.length; i += chunkSize) {
          final end = (i + chunkSize).clamp(0, ids.length);
          await deleter(ids.sublist(i, end));
        }
      }

      // 2a. order_product_components — referenced by orderProductId
      //     (we need the OP ids first).
      final orderProducts = <int>[];
      await deleteInChunks(orderIds, (chunk) async {
        final ops = await (_database.select(_database.orderProducts)
              ..where((p) => p.orderId.isIn(chunk)))
            .get();
        orderProducts.addAll(ops.map((p) => p.id));
      });
      if (orderProducts.isNotEmpty) {
        await deleteInChunks(orderProducts, (chunk) async {
          await (_database.delete(_database.orderProductComponents)
                ..where((c) => c.orderProductId.isIn(chunk)))
              .go();
        });
      }

      // 2b. order_products
      await deleteInChunks(orderIds, (chunk) async {
        await (_database.delete(_database.orderProducts)
              ..where((p) => p.orderId.isIn(chunk)))
            .go();
      });

      // 2c. tickets
      await deleteInChunks(orderIds, (chunk) async {
        await (_database.delete(_database.tickets)
              ..where((t) => t.orderId.isIn(chunk)))
            .go();
      });

      // 2d. notes
      await deleteInChunks(orderIds, (chunk) async {
        await (_database.delete(_database.notes)
              ..where((n) => n.orderId.isIn(chunk)))
            .go();
      });

      // 2e. order_logs
      await deleteInChunks(orderIds, (chunk) async {
        await (_database.delete(_database.orderLogs)
              ..where((l) => l.orderId.isIn(chunk)))
            .go();
      });

      // 2e2. ticket_draft_splits — local-only, never synced (see the table's
      // own doc comment), but keyed by orderId like the rows above, so a
      // purged order's draft split would otherwise sit orphaned forever:
      // nothing ever queries it again once the order itself is gone.
      await deleteInChunks(orderIds, (chunk) async {
        await (_database.delete(_database.ticketDraftSplits)
              ..where((t) => t.orderId.isIn(chunk)))
            .go();
      });

      // 2f. transactions + payments (linked via orders.paymentId →
      //     payments.id, then transactions.paymentId).
      if (paymentIds.isNotEmpty) {
        await deleteInChunks(paymentIds, (chunk) async {
          await (_database.delete(_database.transactions)
                ..where((t) => t.paymentId.isIn(chunk)))
              .go();
        });
        await deleteInChunks(paymentIds, (chunk) async {
          await (_database.delete(_database.payments)
                ..where((p) => p.id.isIn(chunk)))
              .go();
        });
      }

      // 2g. Clear stale area_tables.orderId pointers so freed tables don't
      //     keep showing as "busy" with a deleted order.
      await deleteInChunks(orderIds, (chunk) async {
        await (_database.update(_database.areaTables)
              ..where((t) => t.orderId.isIn(chunk)))
            .write(const AreaTablesCompanion(orderId: Value(null)));
      });

      // 3. Finally delete the orders themselves.
      await deleteInChunks(orderIds, (chunk) async {
        await (_database.delete(_database.orders)
              ..where((o) => o.id.isIn(chunk)))
            .go();
      });
    });

    return deletedOrders;
  }

  /// Dump/backup the database file before clearing.
  /// Copies the current DB to a timestamped backup in a 'backups' subdirectory.
  /// Returns the path to the backup file, or null if backup failed.
  Future<String?> dumpDatabaseBeforeClear() async {
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dbFolder.path, AppDatabase.dbName));

      if (!await dbFile.exists()) {
        _logger.warning('Database file does not exist, nothing to dump');
        return null;
      }

      // Create backups directory
      final backupDir = Directory(p.join(dbFolder.path, 'backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Create timestamped backup filename
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final backupPath = p.join(backupDir.path, 'backup_$timestamp.db');
      await dbFile.copy(backupPath);

      _logger.info('Database backed up to: $backupPath');

      // Clean up old backups - keep only the last 5
      final backups = backupDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

      for (var i = 5; i < backups.length; i++) {
        try {
          await backups[i].delete();
        } catch (_) {}
      }

      return backupPath;
    } catch (e) {
      _logger.error('Failed to dump database: $e');
      return null;
    }
  }

  /// Clear all data from the database (full tenant logout / reset).
  /// Order respects FK constraints — children before parents.
  Future<void> clearAllData() async {
    // Refund lines reference refunds, which reference orders — both must go
    // before the orders below.
    await _database.delete(_database.refundLines).go();
    await _database.delete(_database.refunds).go();
    await _database.delete(_database.tickets).go();
    await _database.delete(_database.orderProductComponents).go();
    await _database.delete(_database.orderProducts).go();
    // Local-only draft ticket splits — never synced, but keyed by orderId
    // like the rows above.
    await _database.delete(_database.ticketDraftSplits).go();
    // orderLogs and notes reference orders — must go before orders
    await _database.delete(_database.orderLogs).go();
    await _database.delete(_database.notes).go();
    await _database.delete(_database.orders).go();
    await _database.delete(_database.transactions).go();
    await _database.delete(_database.payments).go();
    await _database.delete(_database.cashSessions).go();
    // Z (shift) rows own the cash sessions above — wipe them too on a full
    // logout / tenant switch, otherwise a stale open Z would be adopted by the
    // next login and hand new orders the wrong z_day.
    await _database.delete(_database.zs).go();
    await _database.delete(_database.customers).go();
    await _database.delete(_database.commercials).go();
    await _database.delete(_database.pendingSyncOperations).go();
    // waiterAreas references areas (cleared in clearMasterData) — must go first
    await _database.delete(_database.waiterAreas).go();
    await _database.delete(_database.waiters).go();
    await _database.delete(_database.providers).go();
    await _database.delete(_database.agendaBookings).go();
    await clearMasterData();
  }

  /// Sync all data from the server.
  ///
  /// **Fetch-then-swap** topology — the local DB is held byte-identical
  /// to its current contents until every network call has finished
  /// successfully:
  ///
  ///   Phase 1 (no DB writes): fetch every entity over the network into
  ///     in-memory lists. Any failure here aborts the sync with the
  ///     local tables completely untouched — the cashier keeps using the
  ///     pre-sync data they were just looking at, instead of seeing an
  ///     empty UI mid-purge.
  ///
  ///   Phase 2 (single transaction): run the retention purge, **upsert**
  ///     every fetched row (update-or-insert, keyed on the server id),
  ///     then reconcile — delete only the local ids the payload did not
  ///     mention. Wrapped in one transaction, so a throw anywhere rolls
  ///     back to the pre-sync catalog.
  ///
  /// Nothing is ever wiped-then-refilled. Two consequences worth knowing:
  ///
  ///   * Locally-owned columns survive without special handling, because
  ///     they are simply not part of the update set — `area_tables.orderId`
  ///     / `tableState`, and `users.lastLogin` / `displayName`. The old
  ///     `INSERT OR REPLACE` deleted and recreated each row, resetting
  ///     those to defaults, which is what the snapshot/restore helpers
  ///     used to paper over.
  ///   * `kds` and `kiosks` are no longer touched at all. syncAllData never
  ///     fetched them, yet the old wipe deleted them every run and nothing
  ///     put them back — device registrations silently disappeared.
  Future<void> syncAllData({int? dataRetentionDays}) async {
    try {
      // ── Phase 1: network fetches ────────────────────────────────────
      onProgress?.call('Fetching users...', 0.05);
      final users = await _apiService.fetchUsers();

      onProgress?.call('Fetching categories...', 0.12);
      final categories = await _apiService.fetchCategories();

      onProgress?.call('Fetching stations...', 0.18);
      final stations = await _apiService.fetchStations();

      onProgress?.call('Fetching products...', 0.25);
      final products = await _apiService.fetchProducts();

      onProgress?.call('Fetching product variants...', 0.34);
      final variants = await _apiService.fetchVariants();

      // Serial (unit-level) stock. Tolerated as empty: a tenant that sells
      // nothing serialised has no rows, and an older server has no endpoint at
      // all — neither is a reason to fail the whole catalogue sync.
      List<Map<String, dynamic>> serials = const [];
      try {
        serials = await _apiService.fetchSerials();
      } catch (e) {
        _logger.warning('Serial sync skipped: $e');
      }

      onProgress?.call('Fetching component groups...', 0.42);
      final componentGroups = await _apiService.fetchComponentGroups();

      onProgress?.call('Fetching components...', 0.5);
      final components = await _apiService.fetchComponents();

      onProgress?.call('Fetching product components...', 0.58);
      final productComponents = await _apiService.fetchProductComponents();

      // Per-product rule overrides. Newer than most servers in the field, and
      // the client tolerates its absence, so it must not take a sync down.
      List<Map<String, dynamic>> productComponentGroups = const [];
      try {
        productComponentGroups =
            await _apiService.fetchProductComponentGroups();
      } catch (e) {
        _logger.warning('Product component group rules skipped: $e');
      }

      onProgress?.call('Fetching areas...', 0.66);
      final areas = await _apiService.fetchAreas();

      onProgress?.call('Fetching tables...', 0.72);
      final tables = await _apiService.fetchTables();

      onProgress?.call('Fetching commercials...', 0.78);
      final commercials = await _apiService.fetchCommercials();

      onProgress?.call('Fetching customers...', 0.84);
      final customers = await _apiService.fetchCustomers();

      onProgress?.call('Fetching waiters...', 0.9);
      final waiters = await _apiService.fetchWaiters();

      // Bookable resources and staff — best-effort (optional endpoints, older
      // backends 404); [] if absent, which must not fail the master sync.
      final resources = await _apiService.fetchResources();
      final serviceProviders = await _apiService.fetchProviders();

      // ── Guard: refuse a destructive wipe on a suspicious EMPTY payload ──
      // The swap below DELETES the local catalog (tables, products, …) and
      // repopulates it from the fetches above. A backend that returns an empty
      // 200 — e.g. when a proxy strips the X-Business-Id header (see the
      // pos-api-headers note) or a transient tenant-resolution glitch — would
      // otherwise silently delete every table (dropping their order links) and
      // every product mid-service. That is the "tables just got deleted"
      // symptom. Never clear a populated device on the strength of an empty
      // response: abort and let the next (correct) sync repopulate. A genuine
      // "admin removed everything" is rare and recoverable; a mid-service wipe
      // is not.
      final localTables = await _database.select(_database.areaTables).get();
      final localProducts = await _database.select(_database.products).get();
      if (tables.isEmpty && localTables.isNotEmpty) {
        throw Exception(
            'Sync aborted: server returned 0 tables but the device has '
            '${localTables.length}. Refusing to wipe tables (likely a transient/'
            'backend issue — check X-Business-Id). Local data kept.');
      }
      if (products.isEmpty && localProducts.isNotEmpty) {
        throw Exception(
            'Sync aborted: server returned 0 products but the device has '
            '${localProducts.length}. Refusing to wipe the catalog (likely a '
            'transient/backend issue — check X-Business-Id). Local data kept.');
      }

      // ── Phase 2: upsert, then reconcile ─────────────────────────────
      //
      // The local catalog is never emptied. Every row the server sent is
      // updated in place (or inserted when new), and only afterwards are the
      // leftovers — ids the server no longer knows about — deleted. Two things
      // this buys us over the old clear-then-refill:
      //
      //   * There is no instant, even inside the transaction, where the device
      //     has no products/tables. A crash or a throw mid-way leaves the old
      //     catalog intact rather than an empty one.
      //   * Locally-owned columns survive on their own. `area_tables.orderId` /
      //     `tableState` (set by the cashier's Hold/Pay flow) and
      //     `users.lastLogin` / `displayName` are simply not part of the update
      //     set, so they are no longer destroyed and restored from a snapshot.
      onProgress?.call('Updating local data...', 0.95);
      await _database.transaction(() async {
        if (dataRetentionDays != null && dataRetentionDays > 0) {
          await clearOldSyncedData(dataRetentionDays);
        }

        // Persist in FK-respecting order. Each helper is a pure DB
        // writer: it doesn't touch the network and can be re-run safely
        // on a partial failure (drift rolls back the transaction on any
        // throw).
        await _persistUsers(users);
        await _persistCategories(categories);
        await _persistStations(stations);
        await _persistResources(resources);
        await _persistProducts(products);
        await _persistVariants(variants);
        await _persistSerials(serials);
        await _persistComponentGroups(componentGroups);
        await _persistComponents(components);
        await _persistProductComponents(productComponents);
        await _persistProductComponentGroups(productComponentGroups);
        await _persistAreas(areas);
        await _persistTables(tables);
        await _persistCommercials(commercials);
        await _persistCustomers(customers);
        await _persistWaiters(waiters);
        await _persistProviders(serviceProviders);

        // ── Reconcile: propagate backend deletes ──────────────────────
        // Children before parents, mirroring the old clear order. Each call
        // removes ONLY ids absent from this sync's payload.
        //
        // `kds` and `kiosks` are deliberately absent: syncAllData never
        // fetches them, so they have no payload to reconcile against. The old
        // clearMasterData() wiped both on every full sync and nothing ever put
        // them back — device registrations silently vanished. Not reconciling
        // them is the fix.
        await _reconcileDeletes(
            _database.productVariants.actualTableName, _idsOf(variants));
        // Only reconcile serials when the fetch actually returned something.
        // An empty list here is ambiguous — endpoint missing, or a genuinely
        // empty tenant — and wiping the local cache on the ambiguous case would
        // block every serial-tracked sale until the next successful pull.
        if (serials.isNotEmpty) {
          await _reconcileDeletes(
              _database.serials.actualTableName, _idsOf(serials));
        }
        await _reconcileDeletes(
            _database.products.actualTableName, _idsOf(products));
        await _reconcileDeletes(
            _database.components.actualTableName, _idsOf(components));
        await _reconcileDeletes(
            _database.componentGroups.actualTableName, _idsOf(componentGroups));
        await _reconcileDeletes(
            _database.stations.actualTableName, _idsOf(stations));
        await _reconcileDeletes(
            _database.resources.actualTableName, _idsOf(resources));
        await _reconcileDeletes(
            _database.categories.actualTableName, _idsOf(categories));
        // A table still holding an order is never reconciled away: dropping it
        // would strand that order with no floor position mid-service. It
        // disappears on a later sync once the order is closed and the link
        // cleared.
        await _reconcileDeletes(
          _database.areaTables.actualTableName,
          _idsOf(tables),
          protectWhere: 'order_id IS NOT NULL',
        );
        await _reconcileDeletes(
            _database.areas.actualTableName, _idsOf(areas));
        await _reconcileDeletes(
            _database.commercials.actualTableName, _idsOf(commercials));
        await _reconcileDeletes(
            _database.waiters.actualTableName, _idsOf(waiters));
        // Only when the endpoint actually answered: an older backend returns
        // [] for providers, and reconciling on that would delete the whole
        // bookable-staff list off a working shop.
        if (serviceProviders.isNotEmpty) {
          await _reconcileDeletes(
              _database.providers.actualTableName, _idsOf(serviceProviders));
        }
        await _reconcileDeletes(
            _database.users.actualTableName, _idsOf(users));
        // Customers are NOT reconciled — the device creates them locally and
        // uploads later, so a customer missing from the payload is very often
        // one this POS just rang up, not one the admin deleted.
      });

      onProgress?.call('Sync complete!', 1.0);
    } catch (e) {
      _logger.error('Sync failed: $e');
      throw Exception('Sync failed: $e');
    }
  }

  /// Writes the previously-fetched users into the local DB.
  ///
  /// Upsert, not replace: `lastLogin` and `displayName` are tracked locally and
  /// never sent by the server, so they are simply left out of the statement
  /// when absent from the payload — SQLite keeps whatever the row already had.
  /// The old `INSERT OR REPLACE` destroyed and recreated the row, which is why
  /// this used to need a pre-wipe snapshot to put those two columns back.
  Future<void> _persistUsers(List<Map<String, dynamic>> users) async {
    for (final user in users) {
      final createdAt = _parseDateTime(user['createdAt'] ?? user['created_at']);
      final updatedAt = _parseDateTime(user['updatedAt'] ?? user['updated_at']);
      final lastLogin =
          _parseDateTime(user['lastLogin'] ?? user['last_login']);

      final serverDisplayName =
          user['displayName'] ?? user['display_name'];
      final hasDisplayName =
          serverDisplayName is String && serverDisplayName.isNotEmpty;

      final userId = (user['id'] as num?)?.toInt();
      if (userId != null) {
        await _releaseUniqueValue(
            _database.users.actualTableName, 'username', user['username'],
            userId, nullable: false);
      }

      await _database.into(_database.users).insertOnConflictUpdate(
            UsersCompanion.insert(
              id: Value(user['id']),
              username: user['username'],
              password: user['password'] ?? '',
              firstName: user['firstName'] ?? '',
              lastName: user['lastName'] ?? '',
              type: user['type'] ?? 'cashier',
              imageUrl: Value(user['imageUrl']),
              permissions: Value(_normalizePermissions(user['permissions'])),
              // Absent → column keeps its current local value on update.
              displayName: hasDisplayName
                  ? Value(serverDisplayName)
                  : const Value.absent(),
              createdAt:
                  createdAt != null ? Value(createdAt) : const Value.absent(),
              updatedAt:
                  updatedAt != null ? Value(updatedAt) : const Value.absent(),
              lastLogin:
                  lastLogin != null ? Value(lastLogin) : const Value.absent(),
            ),
          );
    }
  }

  /// Parse a date that may arrive as an ISO-8601 string, epoch millis, or null.
  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      if (value.trim().isEmpty) return null;
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }

  /// Normalise permissions to a comma-separated string regardless of whether the
  /// server sends a List, a JSON-array string, or an already comma-separated string.
  String? _normalizePermissions(dynamic value) {
    if (value == null) return null;
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(',');
    }
    if (value is String) {
      final raw = value.trim();
      if (raw.isEmpty) return '';
      if (raw.startsWith('[')) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is List) {
            return decoded.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).join(',');
          }
        } catch (_) {
          // fall through to comma handling
        }
      }
      // Already comma-separated (or a single token)
      return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).join(',');
    }
    return value.toString();
  }

  Future<void> _persistCategories(
      List<Map<String, dynamic>> categories) async {
    for (final category in categories) {
      await _database.into(_database.categories).insertOnConflictUpdate(
        CategoriesCompanion.insert(
          id: Value(category['id']),
          name: category['name'],
          imageUrl: Value(category['imageUrl']),
          description: Value(category['description']),
          displayOrder: Value(category['displayOrder'] ?? 0),
          isActive: Value(category['isActive'] ?? true),
          color: Value(category['color']),
        ),
      );
    }
  }

  Future<void> _persistStations(
      List<Map<String, dynamic>> stations) async {
    for (final station in stations) {
      await _database.into(_database.stations).insertOnConflictUpdate(
        StationsCompanion.insert(
          id: Value(station['id']),
          name: station['name'],
          description: Value(station['description']),
        ),
      );
    }
  }

  /// Persist a product the SERVER just created, through the exact code path a
  /// catalogue sync uses.
  ///
  /// The quick-create endpoint returns the product in the same shape as
  /// `GET /pos/products`, so reusing `_persistProducts` is not a convenience —
  /// it is the only way the row ends up byte-identical to what the next full
  /// sync would write. A bespoke insert here would drift the moment a column is
  /// added to the sync mapping, and the product would silently change under the
  /// cashier at the next refresh.
  Future<void> persistServerProduct(Map<String, dynamic> product) =>
      _persistProducts([product]);

  /// Same reasoning for the category that may have been created alongside it.
  Future<void> persistServerCategory(Map<String, dynamic> category) =>
      _persistCategories([category]);

  /// Platform item -> local product mapping cache.
  ///
  /// Pulled with the catalogue so an incoming Glovo/Kooul order can be resolved
  /// at the counter without a round trip — including on a terminal that has been
  /// offline since the last sync.
  Future<void> _persistIntegrationMappings(
      List<Map<String, dynamic>> items) async {
    for (final m in items) {
      final id = (m['id'] as num?)?.toInt();
      if (id == null) continue;
      await _database.into(_database.integrationMappings).insertOnConflictUpdate(
            IntegrationMappingsCompanion.insert(
              id: Value(id),
              provider: (m['provider'] ?? '').toString().toUpperCase(),
              externalId: (m['externalId'] ?? '').toString(),
              kind: Value((m['kind'] ?? 'PRODUCT').toString().toUpperCase()),
              productId: Value((m['productId'] as num?)?.toInt()),
              variantId: Value((m['variantId'] as num?)?.toInt()),
              componentId: Value((m['componentId'] as num?)?.toInt()),
              mapped: Value(m['mapped'] as bool? ?? false),
              externalName: Value(m['externalName'] as String?),
              updatedAt: Value(DateTime.now()),
            ),
          );
    }
  }

  /// Refresh just the mapping cache. Called from the catalogue sync and worth
  /// calling again when a line fails to resolve — the back office may have
  /// linked it since the last pull.
  Future<int> syncIntegrationMappings() async {
    try {
      final payload = await _apiService.fetchIntegrationMappings();
      final items = (payload['items'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const <Map<String, dynamic>>[];
      if (items.isEmpty) return 0;
      await _persistIntegrationMappings(items);
      await _reconcileDeletes(
          _database.integrationMappings.actualTableName, _idsOf(items));
      _logger.info('Integration mappings refreshed (${items.length})');
      return items.length;
    } catch (e) {
      // A tenant with no delivery integration has no endpoint/rows; never let
      // that fail a catalogue sync.
      _logger.warning('Integration mapping sync skipped: $e');
      return 0;
    }
  }

  /// Serial (unit-level) stock cache.
  ///
  /// Upserts every row the server sent, INCLUDING sold ones — a sold serial is
  /// what a refund or a reprint has to name, and its `isAvailable: false` is
  /// also what stops the picker offering a unit another terminal just sold.
  ///
  /// The server is authoritative for `isAvailable`, which is exactly what makes
  /// this the recovery path for a local reservation orphaned by a crash.
  Future<void> _persistSerials(List<Map<String, dynamic>> serials) async {
    for (final serial in serials) {
      final id = (serial['id'] as num?)?.toInt();
      if (id == null) continue;
      await _database.into(_database.serials).insertOnConflictUpdate(
            SerialsCompanion.insert(
              id: Value(id),
              serialNumber: (serial['serialNumber'] ?? '').toString(),
              code: Value(serial['code'] as String?),
              productId: (serial['productId'] as num?)?.toInt() ?? 0,
              batchId: Value((serial['batchId'] as num?)?.toInt()),
              isAvailable: Value(serial['isAvailable'] ?? true),
              productName: Value(serial['productName'] as String?),
              batchCode: Value(serial['batchCode'] as String?),
              uomId: Value((serial['uomId'] as num?)?.toInt()),
              uomAbbreviation: Value(serial['uomAbbreviation'] as String?),
              updatedAt: Value(DateTime.now()),
            ),
          );
    }
  }

  Future<void> _persistProducts(
      List<Map<String, dynamic>> products) async {
    for (final product in products) {
      // `price` and `finalPrice` used to be cast unconditionally. The catalogue
      // sync always sends both, but the quick-create envelope
      // (`POST /pos/products`) is a different serializer and need not — and a
      // missing one threw a cast error AFTER the server had already created the
      // product, so the till reported failure for a product that now existed.
      // Each falls back to the other, then to 0.
      final rawPrice = (product['price'] as num?)?.toDouble();
      final rawFinalPrice = (product['finalPrice'] as num?)?.toDouble();
      final price = rawPrice ?? rawFinalPrice ?? 0.0;
      final finalPrice = rawFinalPrice ?? rawPrice ?? 0.0;

      await _database.into(_database.products).insertOnConflictUpdate(
        ProductsCompanion.insert(
          id: Value(product['id']),
          name: (product['name'] ?? '').toString(),
          barcode: Value(product['barcode']),
          reference: Value(product['reference'] as String?),
          imageUrl: Value(product['imageUrl']),
          description: Value(product['description']),
          price: price,
          // Kept so order lines can carry a cost to the server for margin
          // reporting. Absent in the payload stays null, not 0.0.
          cost: Value((product['cost'] as num?)?.toDouble()),
          uom: Value(product['uom'] ?? 'unit'),
          categoryId: Value(product['categoryId']),
          stationId: Value(product['stationId']),
          tvaAmount: Value((product['tvaAmount'] as num?)?.toDouble() ?? 0.0),
          discountAmount: Value((product['discountAmount'] as num?)?.toDouble() ?? 0.0),
          finalPrice: finalPrice,
          isActive: Value(product['isActive'] ?? true),
          isVariant: Value(product['isVariant'] ?? false),
          // Serial tracking: a unit-level product cannot be sold without
          // naming the exact unit. Absent on older servers → false, i.e.
          // the existing untracked behaviour.
          isSerialTracked: Value(product['isSerialTracked'] ?? false),
          // New backend structure renamed these to isTimeManaged /
          // serviceDurationMinutes; map at the boundary onto the stable local
          // columns, falling back to the old names for older servers.
          isPlannable: Value(
              product['isTimeManaged'] ?? product['isPlannable'] ?? false),
          planDurationMinutes: Value(
              (product['serviceDurationMinutes'] ?? product['planDurationMinutes'])
                  as int?),
          color: Value(product['color']),
          // Scale / weighed-product fields — null when absent in API response.
          mbwCode: Value(product['mbwCode'] as String?),
          pricePerKg: Value(product['pricePerKg'] as int?),
          unitName: Value(product['unitName'] as String?),
        ),
      );

      // Sync extra stations (multi-station products). The primary `stationId`
      // above keeps single-station behavior; these are additional stations.
      final productId = (product['id'] as num?)?.toInt();
      if (productId == null) continue;
      await (_database.delete(_database.productStations)
            ..where((t) => t.productId.equals(productId)))
          .go();
      final stationIds = (product['stationIds'] as List?)
              ?.map((e) => e is int ? e : int.tryParse(e.toString()))
              .whereType<int>()
              .toList() ??
          const [];
      for (final sid in stationIds) {
        await _database.into(_database.productStations).insert(
              ProductStationsCompanion.insert(productId: productId, stationId: sid),
              mode: InsertMode.insertOrIgnore,
            );
      }

      // Sellable units beyond the base unit (`units[]`). Rebuilt per product,
      // like the two joins above. Absent on older backends → the product keeps
      // base-unit-only selling, exactly as before.
      final units = (product['units'] as List?) ?? const [];
      final keepUomIds = <int>[];
      for (final u in units) {
        if (u is! Map) continue;
        final uomId = (u['uomId'] as num?)?.toInt();
        if (uomId == null) continue;
        keepUomIds.add(uomId);
        await _database.into(_database.productUnits).insertOnConflictUpdate(
              ProductUnitsCompanion.insert(
                productId: productId,
                uomId: uomId,
                unitName: (u['unitName'] ?? '').toString(),
                factor: Value((u['factor'] as num?)?.toDouble() ?? 1.0),
                price: Value((u['price'] as num?)?.toDouble() ?? 0.0),
              ),
            );
      }
      await (_database.delete(_database.productUnits)
            ..where((t) =>
                t.productId.equals(productId) & t.uomId.isNotIn(keepUomIds)))
          .go();

      // Eligible resource pool for a bookable service (mirrors stations above).
      await (_database.delete(_database.productResources)
            ..where((t) => t.productId.equals(productId)))
          .go();
      final resourceIds = (product['resourceIds'] as List?)
              ?.map((e) => e is int ? e : int.tryParse(e.toString()))
              .whereType<int>()
              .toList() ??
          const [];
      for (final rid in resourceIds) {
        await _database.into(_database.productResources).insert(
              ProductResourcesCompanion.insert(
                  productId: productId, resourceId: rid),
              mode: InsertMode.insertOrIgnore,
            );
      }
    }
  }

  Future<void> _persistResources(
      List<Map<String, dynamic>> resources) async {
    for (final r in resources) {
      final id = (r['id'] as num?)?.toInt();
      if (id == null) continue;
      await _database.into(_database.resources).insertOnConflictUpdate(
            ResourcesCompanion.insert(
              id: Value(id),
              name: (r['name'] ?? 'Resource $id').toString(),
              type: Value((r['type'] ?? 'OTHER').toString().toUpperCase()),
              capacity: Value((r['capacity'] as num?)?.toInt() ?? 1),
              businessId: Value((r['businessId'] as num?)?.toInt()),
              isActive: Value(r['isActive'] as bool? ?? true),
            ),
          );
    }
  }

  Future<void> _persistVariants(
      List<Map<String, dynamic>> variants) async {
    for (final variant in variants) {
      // Insert variant
      await _database.into(_database.productVariants).insertOnConflictUpdate(
        ProductVariantsCompanion.insert(
          id: Value(variant['id']),
          productId: variant['productId'],
          name: variant['name'],
          barcode: Value(variant['barcode']),
          sku: Value(variant['sku']),
          description: Value(variant['description']),
          imageUrl: Value(variant['imageUrl']),
          color: Value(variant['color']),
          tags: Value(variant['tags']),
          price: (variant['price'] as num).toDouble(),
          cost: Value((variant['cost'] as num?)?.toDouble()),
          tvaAmount: Value((variant['tvaAmount'] as num?)?.toDouble() ?? 0.0),
          isActive: Value(variant['isActive'] ?? true),
          isSerialTracked: Value(variant['isSerialTracked'] ?? false),
        ),
      );

      // Attribute values for this variant. The row's PK is an autoIncrement
      // `id` the server never sends, so `insertOnConflictUpdate` would have
      // nothing to match on — `insertOrReplace` is kept here deliberately
      // because it resolves against the UNIQUE(variant_id, attribute_id)
      // index instead. Attributes the server dropped are reconciled away
      // first, since without the old table-wide wipe they would linger.
      final variantId = variant['id'] as int;
      final attributeValues = variant['attributeValues'] as List<dynamic>? ?? [];
      final keepAttributeIds = attributeValues
          .map((av) => (av['attributeId'] as num?)?.toInt())
          .whereType<int>()
          .toList();
      await (_database.delete(_database.variantAttributeValues)
            ..where((t) =>
                t.variantId.equals(variantId) &
                t.attributeId.isNotIn(keepAttributeIds)))
          .go();

      for (final av in attributeValues) {
        await _database.into(_database.variantAttributeValues).insert(
          VariantAttributeValuesCompanion.insert(
            variantId: variantId,
            attributeId: av['attributeId'],
            attributeName: Value(av['attributeName']),
            valueId: av['valueId'],
            value: Value(av['value']),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    }
  }

  Future<void> _persistComponentGroups(
      List<Map<String, dynamic>> groups) async {
    for (final group in groups) {
      await _database.into(_database.componentGroups).insertOnConflictUpdate(
        ComponentGroupsCompanion.insert(
          id: Value(group['id']),
          name: group['name'],
          description: Value(group['description']),
          displayOrder: Value(group['displayOrder'] ?? 0),
          color: Value(group['color'] as String?),
          // A server that predates the rules sends none of these. Defaulting
          // to the permissive QUANTITY/0/unlimited keeps such a group behaving
          // exactly as it did before the POS knew rules existed.
          selectionType:
              Value((group['selectionType'] as String?) ?? 'QUANTITY'),
          minSelection: Value((group['minSelection'] as num?)?.toInt() ?? 0),
          maxSelection: Value((group['maxSelection'] as num?)?.toInt()),
          freeQuantity: Value((group['freeQuantity'] as num?)?.toInt() ?? 0),
        ),
      );
    }
  }

  Future<void> _persistComponents(
      List<Map<String, dynamic>> components) async {
    for (final component in components) {
      await _database.into(_database.components).insertOnConflictUpdate(
        ComponentsCompanion.insert(
          id: Value(component['id']),
          name: component['name'],
          price: Value((component['price'] as num?)?.toDouble() ?? 0.0),
          componentGroupId: Value(component['componentGroupId']),
          // Absent on older servers, where nothing was ever 86'd.
          isActive: Value(component['isActive'] as bool? ?? true),
          displayOrder: Value((component['displayOrder'] as num?)?.toInt() ?? 0),
          // Absent until the backend exposes the stock link on the POS
          // payload; null simply means "not a product in its own right".
          linkedProductId: Value((component['linkedProductId'] as num?)?.toInt()),
          linkedVariantId: Value((component['linkedVariantId'] as num?)?.toInt()),
        ),
      );
    }
  }

  /// Replace the per-product group rule overrides.
  ///
  /// The payload is the complete set of overrides, so anything the server no
  /// longer lists has been removed and that product must fall back to its
  /// group defaults. A wipe-and-fill is honest here in a way it is not for the
  /// product↔component join: this table holds no local state and no
  /// server-assigned id worth preserving.
  ///
  /// An empty payload is left alone rather than treated as "everything was
  /// deleted": the endpoint is new, and on a server that does not have it the
  /// fetch returns empty. Wiping real overrides because an older backend
  /// answered 404 would quietly turn every required group optional.
  Future<void> _persistProductComponentGroups(
      List<Map<String, dynamic>> rules) async {
    if (rules.isEmpty) return;

    await _database.delete(_database.productComponentGroups).go();
    for (final rule in rules) {
      final productId = (rule['productId'] as num?)?.toInt();
      final groupId = (rule['groupId'] as num?)?.toInt();
      if (productId == null || groupId == null) continue;

      await _database
          .into(_database.productComponentGroups)
          .insertOnConflictUpdate(
            ProductComponentGroupsCompanion.insert(
              productId: productId,
              groupId: groupId,
              selectionType: Value(rule['selectionType'] as String?),
              minSelection: Value((rule['minSelection'] as num?)?.toInt()),
              maxSelection: Value((rule['maxSelection'] as num?)?.toInt()),
              freeQuantity: Value((rule['freeQuantity'] as num?)?.toInt()),
              isRequired: Value(rule['isRequired'] as bool?),
              displayOrder:
                  Value((rule['displayOrder'] as num?)?.toInt() ?? 0),
            ),
          );
    }
  }

  /// Reconciling upsert for the product↔component join.
  ///
  /// This table's PK is an autoIncrement `id` the server never sends, and it
  /// carries no unique constraint on `(product_id, component_id)`. A plain
  /// insert therefore appends a brand-new row on every sync — harmless only
  /// while something wiped the table first, which is exactly what the old
  /// `clearMasterData()` did. With the wipe gone we match on the pair
  /// ourselves: update the rows that already exist, insert the genuinely new
  /// ones, and delete the pairs the server dropped.
  Future<void> _persistProductComponents(
      List<Map<String, dynamic>> productComponents) async {
    String keyOf(int productId, int componentId) => '$productId:$componentId';

    final existing = await _database.select(_database.productComponents).get();
    final idByPair = <String, int>{};
    for (final row in existing) {
      // Keep the first id per pair; any historic duplicates fall through to
      // the stale sweep below and get cleaned up on this pass.
      idByPair.putIfAbsent(keyOf(row.productId, row.componentId), () => row.id);
    }

    final seen = <String>{};
    for (final pc in productComponents) {
      final productId = (pc['productId'] as num?)?.toInt();
      final componentId = (pc['componentId'] as num?)?.toInt();
      if (productId == null || componentId == null) continue;
      final key = keyOf(productId, componentId);
      seen.add(key);

      final companion = ProductComponentsCompanion(
        productId: Value(productId),
        componentId: Value(componentId),
        // Null stays null: it means "this link sets no price", and the
        // component's catalogue price answers instead. Storing 0.0 for it
        // made every un-overridden option free.
        defaultPrice: Value((pc['defaultPrice'] as num?)?.toDouble()),
        defaultQuantity: Value(pc['defaultQuantity'] ?? 0),
        isRequired: Value(pc['isRequired'] ?? false),
        minQuantity: Value(pc['minQuantity'] ?? 0),
        // 0 from the server means *no ceiling*, not "none allowed" — it
        // coerces a null max to 0. Stored as-is and read through
        // effectiveMaxQuantity, which treats it as unlimited; the old
        // fallback of 10 was a guess at a bound the server never set.
        maxQuantity: Value((pc['maxQuantity'] as num?)?.toInt() ?? 0),
        // Absent on servers without the feature, and on every link the back
        // office has not flagged.
        chargeOnRemoval: Value(pc['chargeOnRemoval'] as bool? ?? false),
        updatedAt: Value(DateTime.now()),
      );

      final existingId = idByPair[key];
      if (existingId != null) {
        await (_database.update(_database.productComponents)
              ..where((t) => t.id.equals(existingId)))
            .write(companion);
      } else {
        await _database.into(_database.productComponents).insert(companion);
      }
    }

    // Pairs the server no longer sends (plus any legacy duplicate rows).
    final stale = <int>[];
    for (final row in existing) {
      final key = keyOf(row.productId, row.componentId);
      if (!seen.contains(key) || idByPair[key] != row.id) stale.add(row.id);
    }
    if (stale.isNotEmpty) {
      const chunkSize = 500;
      for (var i = 0; i < stale.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, stale.length);
        final chunk = stale.sublist(i, end);
        await (_database.delete(_database.productComponents)
              ..where((t) => t.id.isIn(chunk)))
            .go();
      }
    }
  }

  Future<void> _persistAreas(
      List<Map<String, dynamic>> areas) async {
    for (final area in areas) {
      await _database.into(_database.areas).insertOnConflictUpdate(
        AreasCompanion.insert(
          id: Value(area['id']),
          name: area['name'],
          description: Value(area['description']),
        ),
      );
    }
  }

  /// Upserts the server's static table data (name, capacity, area).
  ///
  /// `orderId` and `tableState` are runtime, cashier-owned columns and are
  /// deliberately absent from the statement, so an update never touches them.
  /// Under the old `INSERT OR REPLACE` the row was destroyed and recreated,
  /// which reset both to their defaults — hence the snapshot/restore pair this
  /// replaces, and hence occupied tables appearing free after a sync.
  Future<void> _persistTables(
      List<Map<String, dynamic>> tables) async {
    for (final table in tables) {
      await _database.into(_database.areaTables).insertOnConflictUpdate(
            AreaTablesCompanion.insert(
              id: Value(table['id']),
              name: table['name'],
              capacity: Value(table['capacity'] ?? 4),
              areaId: Value(table['areaId']),
            ),
          );
    }
  }

  Future<void> _persistCommercials(
      List<Map<String, dynamic>> commercials) async {
    for (final commercial in commercials) {
      final commercialId = (commercial['id'] as num?)?.toInt();
      if (commercialId != null) {
        await _releaseUniqueValue(_database.commercials.actualTableName, 'cin',
            commercial['cin'], commercialId,
            nullable: false);
      }
      await _database.into(_database.commercials).insertOnConflictUpdate(
        CommercialsCompanion.insert(
          id: Value(commercial['id']),
          firstName: commercial['firstName'],
          lastName: commercial['lastName'],
          cin: commercial['cin'],
        ),
      );
    }
  }

  Future<void> _persistCustomers(
      List<Map<String, dynamic>> customers) async {
    for (final customer in customers) {
      // Accept either `phoneNormalized` or snake_case `phone_normalized` from
      // the server. If neither is present, fall back to a local normalisation
      // of the raw `phone` so the dedup key is still populated.
      final phone = customer['phone'] as String?;
      final serverNorm =
          customer['phoneNormalized'] ?? customer['phone_normalized'];
      final normalised = (serverNorm is String && serverNorm.isNotEmpty)
          ? serverNorm
          : (phone == null || phone.isEmpty
              ? null
              : _normalizePhoneFallback(phone));
      // updatedAt comes back from the server now (new bulk response field).
      // Use it when present so the local row reflects the canonical
      // last-touched timestamp; fall back to existing default otherwise.
      final updatedAt = _parseDateTime(customer['updatedAt']);
      final customerId = (customer['id'] as num?)?.toInt();
      if (customerId != null) {
        await _releaseUniqueValue(_database.customers.actualTableName,
            'phone_normalized', normalised, customerId,
            nullable: true);
      }
      await _database.into(_database.customers).insertOnConflictUpdate(
        CustomersCompanion.insert(
          id: Value(customer['id']),
          firstName: Value(customer['firstName'] ?? ''),
          lastName: Value(customer['lastName'] ?? ''),
          phone: Value(phone),
          phoneNormalized: Value(normalised),
          email: Value(customer['email']),
          isSynced: const Value(true), // Data from server is already synced
          updatedAt: updatedAt != null ? Value(updatedAt) : const Value.absent(),
        ),
      );
    }
  }

  /// Tiny inline normaliser — same logic as `utils/phone_normalizer.dart` but
  /// kept here to avoid a cross-package import inside the sync service.
  String _normalizePhoneFallback(String raw, {String cc = '212'}) {
    var d = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (d.isEmpty) return '';
    if (d.startsWith('00$cc')) d = d.substring(2 + cc.length);
    else if (d.startsWith(cc)) d = d.substring(cc.length);
    if (d.startsWith('0')) d = d.substring(1);
    return '$cc$d';
  }

  Future<void> _persistProviders(
      List<Map<String, dynamic>> serviceProviders) async {
    for (final row in serviceProviders) {
      final id = (row['id'] as num?)?.toInt();
      if (id == null) continue;
      await _database.into(_database.providers).insertOnConflictUpdate(
            ProvidersCompanion.insert(
              id: Value(id),
              firstName: (row['firstName'] ?? '').toString(),
              lastName: Value(row['lastName']?.toString()),
              imageUrl: Value(row['imageUrl']?.toString()),
              username: Value(row['username']?.toString()),
              passwordHash: Value(row['passwordHash']?.toString()),
              pin: Value(row['pin']?.toString()),
              isActive: Value(row['isActive'] as bool? ?? true),
              updatedAt: Value(DateTime.now()),
            ),
          );
    }
  }

  /// Replace the cached diary for the pulled window.
  ///
  /// Scoped to the window rather than wiping the table: pulling one week must
  /// not blank the weeks the terminal already has, and a booking that vanished
  /// from the window genuinely was unscheduled, canceled, or moved out of it.
  ///
  /// Matched by **overlap**, exactly like the endpoint: a booking that starts
  /// at 23:30 on the last day of the window is part of that window, and a
  /// start-only match would leave a stale copy behind after it moved.
  ///
  /// One transaction, so the agenda never paints a half-empty week.
  Future<void> cacheAgenda(
    List<AgendaBookingDto> bookings, {
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    await _database.transaction(() async {
      await (_database.delete(_database.agendaBookings)
            ..where((t) =>
                t.planStartAt.isSmallerThanValue(windowEnd) &
                t.planEndAt.isBiggerThanValue(windowStart)))
          .go();

      for (final b in bookings) {
        if (!b.hasWindow) continue;
        await _database.into(_database.agendaBookings).insertOnConflictUpdate(
              AgendaBookingsCompanion.insert(
                orderProductId: Value(b.orderProductId),
                orderId: Value(b.orderId),
                orderCode: Value(b.orderCode),
                productId: Value(b.productId),
                productName: Value(b.productName),
                customerName: Value(b.customerName),
                customerPhone: Value(b.customerPhone),
                note: Value(b.note),
                planStartAt: b.planStartAt,
                planEndAt: b.planEndAt,
                planWaiterId: Value(b.planWaiterId),
                planWaiterName: Value(b.planWaiterName),
                planResourceId: Value(b.planResourceId),
                planResourceName: Value(b.planResourceName),
                planResourceType: Value(b.planResourceType),
                value: Value(b.value),
                state: Value(b.lineState ?? 'PENDING'),
                fetchedAt: Value(DateTime.now()),
              ),
            );
      }
    });
  }

  /// Drop a booking from the cache the moment it is unscheduled, so the agenda
  /// does not keep showing a slot the server has already freed.
  Future<void> removeCachedBooking(int orderProductId) async {
    await (_database.delete(_database.agendaBookings)
          ..where((t) => t.orderProductId.equals(orderProductId)))
        .go();
  }

  Future<void> _persistWaiters(
      List<Map<String, dynamic>> waiters) async {
    for (final waiter in waiters) {
      // `pin` is the credential the waiter app uses to authenticate against
      // the local POS — see `_waiterLogin` in server_service.dart. Stored
      // as-is (plaintext) since the LAN-only server has no separate hashing
      // requirement; uniqueness is enforced by the partial index added at
      // schemaVersion 18.
      final wId = (waiter['id'] as num?)?.toInt();
      if (wId != null) {
        await _releaseUniqueValue(
            _database.waiters.actualTableName, 'pin', waiter['pin'], wId,
            nullable: true);
      }
      await _database.into(_database.waiters).insertOnConflictUpdate(
        WaitersCompanion.insert(
          id: Value(waiter['id']),
          firstName: waiter['firstName'] ?? '',
          lastName: Value(waiter['lastName']),
          imageUrl: Value(waiter['imageUrl']),
          pin: Value(waiter['pin']),
          username: Value(waiter['username']),
          passwordHash: Value(waiter['passwordHash']),
          isActive: const Value(true),
        ),
      );

      // Waiter→area assignments. Reconciled per waiter: without the old
      // table-wide wipe, an area the admin unassigned would otherwise stay
      // attached forever and keep routing that waiter's tables.
      final waiterId = waiter['id'] as int;
      final areaIds = (waiter['areaIds'] as List<dynamic>? ?? [])
          .map((e) => e is int ? e : int.tryParse(e.toString()))
          .whereType<int>()
          .toList();
      await (_database.delete(_database.waiterAreas)
            ..where((t) =>
                t.waiterId.equals(waiterId) & t.areaId.isNotIn(areaIds)))
          .go();
      for (final areaId in areaIds) {
        await _database.into(_database.waiterAreas).insert(
          WaiterAreasCompanion.insert(waiterId: waiterId, areaId: areaId),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  }

  // ============ UPLOAD LOCAL DATA TO SERVER ============

  /// Fields shared by both order-sync payload builders (`getOrdersForSync` for
  /// the bulk path and `syncSingleOrder` for the immediate one), kept in one
  /// place so the two can't drift apart again.
  ///
  /// Every entry is conditional: an order that has none of these produces an
  /// empty map and therefore exactly the payload the POS sent before these
  /// columns existed. `deliveryStatus` in particular must be *absent* rather
  /// than null — the contract reads absent as "don't change" and an unknown
  /// value as NONE, so sending null on a non-delivery order would clear it.
  Map<String, dynamic> _orderContractFields(Order order) => {
        // Delivery charge, top-level next to `tip` in PosOrderRequest. Sent on
        // create and on every re-sync, but ONLY when we actually hold a value:
        // the contract reads a missing/null `deliveryFee` as "don't change",
        // so sending null on an order that never had one would be a no-op at
        // best and, on a server that reads null as "clear", would wipe a fee
        // the platform set. An explicit 0 ("free delivery") IS sent, because
        // the test below is on null, not on `> 0`.
        if (order.deliveryFee != null) 'deliveryFee': order.deliveryFee,
        if (order.externalOrderId != null)
          'externalOrderId': order.externalOrderId,
        // The courier-facing platform code, sent alongside the machine id so
        // the server persists it and echoes it back on every order response.
        // That echo is what lets a reprint work on a terminal that never saw
        // the original queue row.
        if (order.externalOrderCode != null)
          'externalOrderCode': order.externalOrderCode,
        if (order.deliveryStatus != null)
          'deliveryStatus': order.deliveryStatus,
        if (order.courierName != null) 'courierName': order.courierName,
        if (order.courierPhone != null) 'courierPhone': order.courierPhone,
      };

  /// Build products list for sync, merging order-level discount percentage
  /// into each product's manualDiscount proportionally.
  ///
  /// Example: Product costs $10, existing manualDiscount $5, order discount 50%.
  /// Effective price after existing discounts = $10 - $5 = $5.
  /// Order discount on that = $5 * 50% = $2.50.
  /// Final manualDiscount sent to server = $5 + $2.50 = $7.50.
  /// Exposed for tests: the per-line cost resolution below (variant cost
  /// beats product cost, unknown stays absent) is worth pinning, and the
  /// method only reads the DB, so a test can call it directly.
  @visibleForTesting
  Future<List<Map<String, dynamic>>> buildProductsListForSync(
    List<OrderProduct> orderProducts,
    double discountPercentage,
  ) async {
    if (orderProducts.isEmpty) return [];

    // Batch-load all components for all products in one query
    final productIds = orderProducts.map((p) => p.id).toList();
    final allComponents = await (_database.select(_database.orderProductComponents)
      ..where((opc) => opc.orderProductId.isIn(productIds)))
      .get();
    final componentsByProductId = <int, List<OrderProductComponent>>{};
    for (final comp in allComponents) {
      componentsByProductId.putIfAbsent(comp.orderProductId, () => []).add(comp);
    }

    // Per-line cost for server-side margin reporting. Batch-loaded in two
    // queries rather than per line — a Z-close sync can push hundreds of lines.
    //
    // A variant's own cost wins when the line sold a variant, because a large
    // size can cost more to make than the base product. Falls back to the
    // product cost, and stays null when the catalogue never supplied one:
    // sending 0.0 for "unknown" would read as a 100% margin on the server.
    final catalogueIds = orderProducts.map((p) => p.productId).toSet().toList();
    final variantIds =
        orderProducts.map((p) => p.variantId).whereType<int>().toSet().toList();
    final costByProductId = <int, double?>{};
    if (catalogueIds.isNotEmpty) {
      final rows = await (_database.select(_database.products)
            ..where((t) => t.id.isIn(catalogueIds)))
          .get();
      for (final r in rows) {
        costByProductId[r.id] = r.cost;
      }
    }
    final costByVariantId = <int, double?>{};
    if (variantIds.isNotEmpty) {
      final rows = await (_database.select(_database.productVariants)
            ..where((t) => t.id.isIn(variantIds)))
          .get();
      for (final r in rows) {
        costByVariantId[r.id] = r.cost;
      }
    }

    final productDataList = <Map<String, dynamic>>[];
    final effectivePrices = <double>[];

    for (final product in orderProducts) {
      final productComponents = componentsByProductId[product.id] ?? [];

      // Removal charges are the server's to work out, from the explicit
      // quantity we send for the component itself. Echoing our own copy back
      // as an option would have it deduct stock for something nobody served,
      // and the server drops rows it did not materialise anyway.
      final componentsList = productComponents
          .where((comp) => !comp.removalCharge)
          .map((comp) => {
        'componentId': comp.componentId,
        'quantity': comp.quantity,
        'price': comp.price,
        'isSpecial': comp.isSpecial,
        // Name captured at order time. Omitted (not null) on legacy rows so
        // the server falls back to the component's current name exactly as
        // it did before this field existed.
        if (comp.name != null && comp.name!.isNotEmpty) 'name': comp.name,
      }).toList();

      double componentTotal = 0.0;
      for (final comp in productComponents) {
        componentTotal += comp.price * comp.quantity;
      }

      final effectivePerItem = product.unitaryPrice + componentTotal - product.unitaryDiscount - product.manualDiscount;
      final effectiveTotal = effectivePerItem * product.quantity;
      effectivePrices.add(effectiveTotal > 0 ? effectiveTotal : 0.0);

      // The snapshot taken when the line was rung up wins. The catalogue
      // lookup is only a fallback for rows created before `order_products.cost`
      // existed — without it, every order already in the queue at upgrade time
      // would sync with no cost at all.
      final lineCost = product.cost ??
          (product.variantId != null
                  ? costByVariantId[product.variantId]
                  : null) ??
          costByProductId[product.productId];

      productDataList.add({
        'productId': product.productId,
        'variantId': product.variantId,
        'quantity': product.quantity,
        'unitaryPrice': product.unitaryPrice,
        // Per-unit cost at sync time. Omitted rather than null when unknown, so
        // a server that stores this can tell "no cost on file" from "zero cost".
        if (lineCost != null) 'cost': lineCost,
        'unitaryDiscount': product.unitaryDiscount,
        'unitaryTva': product.unitaryTva,
        'manualDiscount': product.manualDiscount,
        if (product.manualDiscountReason != null)
          'manualDiscountReason': product.manualDiscountReason,
        // UOM the quantity is expressed in. Omitted for base-unit lines, which
        // is what every pre-existing line is — the server treats absent as 1:1.
        if (product.saleUomId != null) 'saleUomId': product.saleUomId,
        // The individual unit sold. Only ever present on a serial-tracked line —
        // the server 400s a serialId on a normal product, and 400s a tracked
        // line without one.
        if (product.serialId != null) 'serialId': product.serialId,
        'note': product.note,
        'state': product.state,
        'zDay': product.zDay?.toIso8601String(),
        // Booking fields — send times as explicit UTC (server stores UTC).
        'planStartAt': product.planStartAt?.toUtc().toIso8601String(),
        'planEndAt': product.planEndAt?.toUtc().toIso8601String(),
        'planWaiterId': product.planWaiterId,
        'planResourceId': product.planResourceId,
        'components': componentsList,
      });
    }

    if (discountPercentage > 0) {
      final totalEffective = effectivePrices.fold(0.0, (sum, v) => sum + v);
      if (totalEffective > 0) {
        final orderDiscountAmount = totalEffective * (discountPercentage / 100.0);
        for (int i = 0; i < productDataList.length; i++) {
          final proportion = effectivePrices[i] / totalEffective;
          final productShareOfDiscount = orderDiscountAmount * proportion;
          final qty = (productDataList[i]['quantity'] as num).toDouble();
          final perUnitShare = qty > 0 ? productShareOfDiscount / qty : 0.0;
          final existingManualDiscount = productDataList[i]['manualDiscount'] as double;
          productDataList[i]['manualDiscount'] = existingManualDiscount + perUnitShare;
        }
      }
    }

    return productDataList;
  }

  /// Get all orders that need to be synced (not yet synced, excluding ONHOLD)
  Future<List<Map<String, dynamic>>> getOrdersForSync() async {
    final orders = await (_database.select(_database.orders)
      ..where((o) => o.isSynced.equals(false) & o.status.isNotValue('ONHOLD')))
      .get();

    // Pre-load `phone_normalized` for every customer referenced by this
    // batch so we don't run N queries inside the loop. The new backend
    // contract keys orders to customers by phone, not by id.
    final clientIds = orders
        .where((o) => o.clientId != null)
        .map((o) => o.clientId!)
        .toSet();
    final phoneByClientId = <int, String?>{};
    if (clientIds.isNotEmpty) {
      final rows = await (_database.select(_database.customers)
            ..where((c) => c.id.isIn(clientIds)))
          .get();
      for (final c in rows) {
        phoneByClientId[c.id] = c.phoneNormalized;
      }
    }

    // Pre-load `code` for every session referenced by this batch so the
    // payload can carry both `sessionId` (local) and `sessionCode` (the
    // backend's stable key) — same pattern the ticket sync at line 990
    // uses. Without this the backend can't reconcile orders to a Z-report.
    final sessionIds = orders
        .where((o) => o.sessionId != null)
        .map((o) => o.sessionId!)
        .toSet();
    final sessionCodeById = <int, String?>{};
    if (sessionIds.isNotEmpty) {
      final rows = await (_database.select(_database.cashSessions)
            ..where((s) => s.id.isIn(sessionIds)))
          .get();
      for (final s in rows) {
        sessionCodeById[s.id] = s.code;
      }
    }

    // Build order list with products
    final ordersList = <Map<String, dynamic>>[];

    for (final order in orders) {
      // Get all products for this order
      final orderProducts = await (_database.select(_database.orderProducts)
        ..where((op) => op.orderId.equals(order.id)))
        .get();

      // Build products list, merging order-level discount into manualDiscount
      final productsList = await buildProductsListForSync(orderProducts, order.discountPercentage);

      // Build order map with products - discountPercentage is set to 0
      // because it has been merged into each product's manualDiscount
      ordersList.add({
        'id': order.id,
        'code': order.code,
        'status': order.status,
        'type': order.type,
        'priority': order.priority,
        'coupon': order.coupon,
        'persons': order.persons,
        'tableId': order.tableId,
        // Origin of the order ('POS' / 'WAITER' / 'KIOSK' / 'EXTERNAL').
        // Lets the backend filter / report by source. Null on legacy rows
        // that predate the column — backend should treat null as 'POS'.
        'source': order.source,
        // Kept for backward compat with older backends — the new server
        // ignores clientId and routes by customerPhoneNormalized instead.
        'clientId': order.clientId,
        'customerPhoneNormalized':
            order.clientId == null ? null : phoneByClientId[order.clientId!],
        'commercialId': order.commercialId,
        'discountPercentage': 0.0,
        // `tip` is sent regardless of value (including null) so the server
        // can distinguish "no tip" from "clear the tip" — the bulk endpoint
        // accepts a nullable `tip` field per the contract.
        'tip': order.tip,
        'note': order.note,
        'address': order.address,
        'cancellationReason': order.cancellationReason,
        'createdBy': order.createdBy,
        'takenBy': order.takenBy,
        'servedBy': order.waiterId,
        // Bind the order to its cash session. Mirrors the shape ticket
        // sync already uses — `sessionId` is the POS-local int, `sessionCode`
        // is the backend's stable key.
        'sessionId': order.sessionId,
        'sessionCode': order.sessionId == null
            ? null
            : sessionCodeById[order.sessionId!],
        'zDay': order.zDay?.toIso8601String(),
        ..._orderContractFields(order),
        'products': productsList,
        'createdAt': order.createdAt.toIso8601String(),
        'updatedAt': order.updatedAt.toIso8601String(),
      });
    }

    return ordersList;
  }

  /// Get all tickets for synced orders that haven't been synced yet
  Future<List<Map<String, dynamic>>> getTicketsForSync() async {
    // Get synced order IDs and codes
    final syncedOrders = await (_database.select(_database.orders)
      ..where((o) => o.isSynced.equals(true)))
      .get();
    final syncedOrderMap = {for (var o in syncedOrders) o.id: o.code};

    // Get synced sessions IDs and codes
    final sessions = await (_database.select(_database.cashSessions)).get();
    final sessionCodeById = {for (final s in sessions) s.id: s.code};

    // Get tickets that belong to synced orders but aren't synced yet
    final tickets = await (_database.select(_database.tickets)
      ..where((t) => t.isSynced.equals(false)))
      .get();

    // Filter tickets for synced orders only and build ticket list
    final ticketsList = <Map<String, dynamic>>[];
    for (final t in tickets) {
      if (!syncedOrderMap.containsKey(t.orderId)) continue;

      final String? sessionCode = t.sessionId != null ? sessionCodeById[t.sessionId] : null;

      ticketsList.add({
        'id': t.id,
        'num': t.num,
        'orderCode': syncedOrderMap[t.orderId], // Use order code for backend
        'orderId': t.orderId, // Keep for local tracking
        'sessionId': t.sessionId,
        'sessionCode': sessionCode, // Use session code for backend
        'paymentMethod': t.paymentMethod,
        'amount': t.amount,
        'isPaid': t.isPaid,
        'isCancelled': t.isCancelled,
        'printCount': t.printCount,
        'zDay': t.zDay?.toIso8601String(),
        'date': t.date.toIso8601String(),
        'createdAt': t.date.toIso8601String(),
      });
    }

    return ticketsList;
  }

  /// Every ended session not yet on the server, as push payloads.
  Future<List<Map<String, dynamic>>> getSessionsForSync() async =>
      (await _sessionsForSync()).map((e) => e.payload).toList();

  Future<List<({Map<String, dynamic> payload, DateTime updatedAt})>>
      _sessionsForSync() async {
    final sessions = await (_database.select(_database.cashSessions)
          ..where((s) => s.status.equals('ended') & s.isSynced.equals(false)))
        .get();
    final zById = await _zsFor(sessions);
    return [
      for (final s in sessions)
        (payload: sessionSyncPayload(s, zById[s.zId]), updatedAt: s.updatedAt),
    ];
  }

  /// Money rounded to the cent: floating sums (expected cash, totals) carry
  /// noise past two decimals, and the server columns are NUMERIC(12,2).
  static double? _money(double? v) =>
      v == null ? null : (v * 100).roundToDouble() / 100;

  Future<Map<int, Z>> _zsFor(List<CashSession> sessions) async {
    final zIds = sessions.map((s) => s.zId).whereType<int>().toSet().toList();
    if (zIds.isEmpty) return const {};
    final rows = await (_database.select(_database.zs)
          ..where((z) => z.id.isIn(zIds)))
        .get();
    return {for (final z in rows) z.id: z};
  }

  /// A session as the server receives it (Z contract v3).
  ///
  /// The Z travels on the session: `zDay` / `zSeq` label it, the session that
  /// opened the Z adds `zOpenMode`, and the one that closed it adds
  /// `isClosingSession` with the close mode, who and when. The server fills
  /// those once, even on a session it already holds closed — which is how a Z
  /// gets closed after its last session was synced.
  static Map<String, dynamic> sessionSyncPayload(CashSession s, Z? z) {
    final label = z == null ? null : ZService.labelOf(z);
    final closing = s.isClosingSession && z != null && z.status == 'closed';
    return {
      'id': s.id,
      'code': s.code,
      'cashierId': s.cashierId,
      'moneyAtStart': _money(s.moneyAtStart),
      'moneyAtEnd': _money(s.moneyAtEnd),
      if (s.moneyEntered != null) 'moneyEntered': _money(s.moneyEntered),
      if (s.moneyCarriedOver != null)
        'moneyCarriedOver': _money(s.moneyCarriedOver),
      if (s.countedCash != null) 'countedCash': _money(s.countedCash),
      'totalPaid': _money(s.totalPaid),
      if (s.autoClosed) 'autoClosed': true,
      if (s.zOverride) 'zOverride': true,
      'details': s.details == null ? null : jsonDecode(s.details!),
      'status': s.status,
      'startedAt': s.startedAt.toIso8601String(),
      'endedAt': s.endedAt?.toIso8601String(),
      'pausedAt': s.pausedAt?.toIso8601String(),
      if (label != null) 'zDay': label.zDay,
      if (label != null) 'zSeq': label.zSeq,
      if (s.zOpenMode != null) 'zOpenMode': s.zOpenMode,
      if (closing) ...{
        'isClosingSession': true,
        'zCloseMode': z.closeMode ?? ZService.closeManual,
        if (z.endedBy != null) 'zClosedBy': z.endedBy,
        if (z.endedAt != null) 'zClosedAt': z.endedAt!.toIso8601String(),
      },
    };
  }

  /// How many consecutive network failures end a batch early.
  ///
  /// Not a retry limit — the orders are untouched and go again next cycle.
  /// It only stops the till spending its entire life in connect timeouts: the
  /// per-order fallbacks below walk a batch of up to 50, and against an
  /// unreachable endpoint each one burns the full connect timeout before
  /// failing identically. That is ~17 minutes of a 5-minute cycle doing
  /// nothing, and it is what filled the field logs with thousands of
  /// "Error syncing single order" lines.
  static const int _networkFailureStreakLimit = 3;

  /// Set by [syncSingleOrder] when its failure was the network giving up
  /// rather than the backend refusing the payload. The batch fallbacks read it
  /// to tell "this endpoint is down" from "this one order is bad" — a serial
  /// rejection must not stop the queue, an unreachable host should.
  bool _lastFailureWasNetwork = false;

  /// Whether [error] is the connection failing rather than the server
  /// answering. Public so the classification can be tested directly: it
  /// decides whether a batch keeps going, and getting it wrong in either
  /// direction is expensive.
  static bool isNetworkFailure(Object error) {
    if (error is DioException) {
      return error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.sendTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.connectionError;
    }
    // syncSingleOrder rewraps Dio's error in a plain Exception, so by the time
    // a batch loop sees it the type is gone and only the message survives.
    final m = error.toString().toLowerCase();
    return m.contains('took longer than') ||
        m.contains('socketexception') ||
        m.contains('connection refused') ||
        m.contains('connection closed') ||
        m.contains('network is unreachable') ||
        m.contains('failed host lookup');
  }

  /// Push unsynced refunds. POST /pos/refunds/bulk.
  ///
  /// A refund line must reference the SERVER's `order_products.id`, which the
  /// POS does not assign. So before sending we make sure the parent order is
  /// synced and then learn its line ids from `GET /pos/orders/{code}`, caching
  /// them onto `order_products.serverId`. A refund whose ids still can't be
  /// resolved is left unsynced and retried on the next cycle rather than sent
  /// with wrong ids.
  /// One refund as the bulk endpoint wants it.
  ///
  /// Extracted so a test can assert what actually goes on the wire — the
  /// `zDay` below especially, which is the difference between a refund landing
  /// in the shift that gave the money back and landing in whatever day its
  /// timestamp happens to fall in.
  @visibleForTesting
  Future<Map<String, dynamic>> buildRefundPayload(
    Refund refund,
    List<Map<String, dynamic>> lineMaps,
    ZDayResolver zDayResolver,
  ) async {
    // The shift the money went back out on. Without it the server has only
    // `refundedAt` to derive a day from, so a refund given at 00:30 during a
    // shift that opened at 20:00 was booked to the next day — the same fault
    // the orders carried, and worse here, because a refund reported on a day
    // its own sale is not makes both days wrong.
    //
    // Resolved through the session when the column itself is null (rows
    // written before it existed), so what goes up is the shift's day either
    // way. Omitted, never null, when even that comes up empty: a missing field
    // leaves the server deriving its own, which is exactly the old behaviour
    // and better than asserting a guess.
    final refundZDay =
        refund.zDay ?? await zDayResolver.forSession(refund.sessionId);

    return {
      'code': refund.code,
      'orderCode': refund.orderCode,
      'method': refund.method,
      if (refund.reason != null) 'reason': refund.reason,
      'refundedBy': refund.refundedBy,
      'refundedAt': refund.refundedAt.toUtc().toIso8601String(),
      // Same shape the order and ticket pushes use for this field, so the
      // backend parses one `zDay` format across every entity.
      if (refundZDay != null) 'zDay': refundZDay.toIso8601String(),
      'lines': lineMaps,
    };
  }

  Future<int> syncRefundsBulk({int batchSize = 50}) async {
    try {
      // Previously-refused refunds are included, deliberately.
      //
      // They used to be excluded on the reasoning that they had already failed
      // on their own merits and would roll back the batch around them. Both
      // halves of that turned out to be wrong: the server runs each refund in
      // its own transaction, so one failure poisons nothing, and its failure
      // map mixes permanent rejections (over-refund, unknown order) with
      // transient database errors that carry no distinguishing message.
      // Excluding them meant a refund that failed once for a moment's reason
      // was never sent again — money given back that never reached the books.
      //
      // Re-sending cannot double-refund: the endpoint is idempotent on `code`,
      // so one the server already accepted comes back as skipped. A genuinely
      // invalid refund simply keeps failing, and keeps saying why on the
      // pending-sync screen, which is where it belongs until a human fixes it.
      final pending = await refundsAwaitingSync(batchSize);
      if (pending.isEmpty) return 0;

      final payload = <Map<String, dynamic>>[];
      final sentIds = <int>[];
      final zDayResolver = ZDayResolver(_database);

      for (final refund in pending) {
        final order = await (_database.select(_database.orders)
              ..where((o) => o.id.equals(refund.orderId)))
            .getSingleOrNull();
        if (order == null) continue;

        // The refund can't exist server-side before its order does.
        if (!order.isSynced) {
          final ok = await syncSingleOrder(order.id);
          if (!ok) continue;
        }

        await _ensureServerLineIds(order.code, order.id);

        final lines = await (_database.select(_database.refundLines)
              ..where((l) => l.refundId.equals(refund.id)))
            .get();
        if (lines.isEmpty) continue;

        final opIds = lines.map((l) => l.orderProductId).toList();
        final ops = await (_database.select(_database.orderProducts)
              ..where((op) => op.id.isIn(opIds)))
            .get();
        final serverIdByLocal = {
          for (final op in ops)
            if (op.serverId != null) op.id: op.serverId!
        };

        final lineMaps = <Map<String, dynamic>>[];
        var resolvable = true;
        for (final l in lines) {
          final serverId = l.orderProductServerId ?? serverIdByLocal[l.orderProductId];
          if (serverId == null) {
            resolvable = false;
            break;
          }
          lineMaps.add({
            'orderProductId': serverId,
            'quantity': l.quantity,
            // Only a deliberately-typed amount goes on the wire. A derived one
            // is stored locally for the slip but omitted here so the server
            // derives its own — our per-unit arithmetic does not account for an
            // order-level discount the way the server's line total does, and
            // sending it would 400 on the amount ceiling.
            if (l.amountOverridden && l.amount != null) 'amount': l.amount,
            'restock': l.restock,
            if (l.reason != null) 'reason': l.reason,
          });
        }
        if (!resolvable) {
          _logger.warning(
              'Refund ${refund.code}: server line ids unresolved — will retry.');
          continue;
        }

        payload.add(await buildRefundPayload(refund, lineMaps, zDayResolver));
        sentIds.add(refund.id);
      }

      if (payload.isEmpty) return 0;

      final RefundSyncResult result;
      try {
        result = await _apiService.syncRefunds(payload);
      } catch (e) {
        // Transport failure (401/500/timeout), NOT a record rejection: the
        // batch never got a verdict, so nothing is marked either way and the
        // whole thing is retried later. Safe because the endpoint is idempotent
        // on `code`.
        //
        // Older servers instead fail the entire batch on one bad record, with
        // no per-record response to tell us which. Isolating one at a time is
        // the only way to salvage the good ones there, and is harmless against
        // a server that reports properly (it will simply accept them all).
        if (payload.length == 1) rethrow;
        _logger.warning(
            'Refund batch of ${payload.length} failed as a whole — retrying '
            'one at a time to isolate the bad record: $e');
        return await _syncRefundsIndividually(payload, sentIds);
      }

      // Apply the verdict per record, matched by CODE. Position matching would
      // mis-assign every outcome the moment the server reorders or omits one.
      final codeByLocalId = <int, String>{};
      for (var i = 0; i < payload.length; i++) {
        codeByLocalId[sentIds[i]] = (payload[i]['code'] ?? '').toString();
      }

      var syncedCount = 0;
      for (final entry in codeByLocalId.entries) {
        final localId = entry.key;
        final code = entry.value;

        if (result.accepted.contains(code)) {
          // `created` and `skipped` are both success: skipped means the server
          // already had it, which is the idempotent re-send working as intended.
          await (_database.update(_database.refunds)
                ..where((r) => r.id.equals(localId)))
              .write(RefundsCompanion(
            isSynced: const Value(true),
            syncError: const Value(null),
            updatedAt: Value(DateTime.now()),
          ));
          syncedCount++;
          continue;
        }

        final error = result.failed[code];
        if (error != null) {
          // Recorded, not abandoned. The message is shown on the pending-sync
          // screen and replaced on each attempt, so what is displayed is why
          // it failed THIS time rather than the first time.
          _logger.error('Refund $code refused by the server: $error');
          await (_database.update(_database.refunds)
                ..where((r) => r.id.equals(localId)))
              .write(RefundsCompanion(
            syncError: Value(
                error.length > 300 ? '${error.substring(0, 300)}…' : error),
            updatedAt: Value(DateTime.now()),
          ));
        }
        // Neither accepted nor explicitly failed: the server said nothing about
        // this code. Left untouched so the next cycle asks again — assuming
        // success here is how a refund goes missing.
      }

      return syncedCount;
    } catch (e) {
      _logger.error('Error syncing refunds: $e');
      return 0;
    }
  }

  /// Re-send a rejected batch one refund at a time.
  ///
  /// Safe because the endpoint is idempotent on `code`: a refund the server
  /// already accepted in the rolled-back attempt is a no-op, not a duplicate.
  /// Anything that fails alone is the poison record — parked with its error so
  /// the queue keeps moving and someone can see why.
  Future<int> _syncRefundsIndividually(
      List<Map<String, dynamic>> payload, List<int> localIds) async {
    var synced = 0;
    for (var i = 0; i < payload.length; i++) {
      final localId = localIds[i];
      try {
        final one = await _apiService.syncRefunds([payload[i]]);
        final code = (payload[i]['code'] ?? '').toString();
        if (!one.accepted.contains(code)) {
          // Reported as failed rather than thrown — park it with the server's
          // own words instead of counting it as synced.
          final why = one.failed[code] ?? 'Rejected by server';
          throw Exception(why);
        }
        await (_database.update(_database.refunds)
              ..where((r) => r.id.equals(localId)))
            .write(RefundsCompanion(
          isSynced: const Value(true),
          syncError: const Value(null),
          updatedAt: Value(DateTime.now()),
        ));
        synced++;
      } catch (e) {
        final message = e.toString();
        _logger.error(
            'Refund ${payload[i]['code']} refused, will retry: $message');
        await (_database.update(_database.refunds)
              ..where((r) => r.id.equals(localId)))
            .write(RefundsCompanion(
          // Truncated: this is displayed in the pending-sync screen, and a Dio
          // error can carry an entire HTML error page.
          syncError: Value(message.length > 300
              ? '${message.substring(0, 300)}…'
              : message),
          updatedAt: Value(DateTime.now()),
        ));
      }
    }
    _logger.info('Refund isolation pass: $synced of ${payload.length} accepted');
    return synced;
  }

  /// Every refund still owed to the server, oldest batch first.
  ///
  /// Exposed as its own method so the one predicate that decides whether a
  /// refund is ever sent again can be tested without a network. A refund that
  /// failed last time is still in here — see the reasoning at the call site.
  Future<List<Refund>> refundsAwaitingSync([int batchSize = 50]) =>
      (_database.select(_database.refunds)
            ..where((r) => r.isSynced.equals(false))
            ..limit(batchSize))
          .get();

  /// Refunds the server refused on their last attempt, for the pending-sync
  /// screen. They are still queued and still retried; this is the list of what
  /// is currently unhappy, not a list of what has been given up on.
  Future<List<Refund>> parkedRefunds() => (_database.select(_database.refunds)
        ..where((r) => r.syncError.isNotNull() & r.isSynced.equals(false))
        ..orderBy([(r) => OrderingTerm.desc(r.refundedAt)]))
      .get();

  /// Clear the last error message on a refund.
  ///
  /// Retrying no longer depends on this — every unsynced refund is retried on
  /// every cycle — so this only tidies a stale message away after the cause
  /// was fixed elsewhere. Kept because the screen offers it.
  Future<void> unparkRefund(int refundId) async {
    await (_database.update(_database.refunds)
          ..where((r) => r.id.equals(refundId)))
        .write(const RefundsCompanion(syncError: Value(null)));
  }

  /// Public entry point to [_ensureServerLineIds] — booking needs it before it
  /// can address a line, because `PATCH /order-products/{id}/schedule` speaks
  /// the server's line ids, not this device's.
  Future<void> ensureServerLineIds(String orderCode, int orderId) =>
      _ensureServerLineIds(orderCode, orderId);

  /// Fill in `order_products.serverId` for [orderCode] from the server's own
  /// copy of the order. Lines are matched the same way the delta pull matches
  /// them — oldest unmatched row per (productId, variantId) — because that is
  /// the only key both sides share.
  Future<void> _ensureServerLineIds(String orderCode, int orderId) async {
    try {
      final local = await (_database.select(_database.orderProducts)
            ..where((op) => op.orderId.equals(orderId)))
          .get();
      if (local.every((op) => op.serverId != null)) return;

      final remote = await _apiService.fetchOrderByCode(orderCode);
      final products = ((remote['products'] ?? remote['orderProducts']) as List?)
              ?.cast<Map<String, dynamic>>() ??
          const [];
      if (products.isEmpty) return;

      final byKey = <(int, int?), List<OrderProduct>>{};
      for (final op in local) {
        byKey.putIfAbsent((op.productId, op.variantId), () => []).add(op);
      }

      for (final p in products) {
        final serverId = (p['id'] as num?)?.toInt();
        final productId = ((p['productId'] ?? p['product_id']) as num?)?.toInt();
        if (serverId == null || productId == null) continue;
        final variantId = ((p['variantId'] ?? p['variant_id']) as num?)?.toInt();
        final queue = byKey[(productId, variantId)];
        if (queue == null || queue.isEmpty) continue;
        final row = queue.removeAt(0);
        if (row.serverId == serverId) continue;
        await (_database.update(_database.orderProducts)
              ..where((op) => op.id.equals(row.id)))
            .write(OrderProductsCompanion(serverId: Value(serverId)));
      }
    } catch (e) {
      _logger.warning('Could not resolve server line ids for $orderCode: $e');
    }
  }

  /// Get all new customers that need to be synced
  Future<List<Map<String, dynamic>>> getCustomersForSync() async {
    final customers = await (_database.select(_database.customers)
      ..where((c) => c.isSynced.equals(false)))
      .get();
    return customers.map((c) => {
      'id': c.id,
      'firstName': c.firstName,
      'lastName': c.lastName,
      'phone': c.phone,
      'phoneNormalized': c.phoneNormalized,
      'email': c.email,
      'createdAt': c.createdAt.toIso8601String(),
    }).toList();
  }

  /// Mark orders as synced
  Future<void> markOrdersAsSynced(List<int> orderIds) async {
    if (orderIds.isEmpty) return;
    await (_database.update(_database.orders)
      ..where((o) => o.id.isIn(orderIds)))
      .write(const OrdersCompanion(isSynced: Value(true)));
  }

  /// Mark orders synced ONLY if they have not been written to since the
  /// snapshot that was actually pushed.
  ///
  /// Every push reads a snapshot at T0 and is confirmed at T2. A write in
  /// between — the waiter app appending a line over the LAN, a cashier edit —
  /// sets `isSynced = false` to request a re-push, and an unconditional mark
  /// here erases that request: the new line is never sent, and the backend's
  /// snapshot stays short by one line for good. That is the "item printed but
  /// vanished" path, since the pull then treats the extra local line as a
  /// remote removal.
  ///
  /// Compared as instants (`isAtSameMomentAs`) rather than by serialized text:
  /// datetimes are stored as TEXT in this schema and have been seen in mixed
  /// UTC/local encodings, which a string or SQL equality would read as
  /// "changed" on every row.
  ///
  /// Asymmetric on purpose. A false negative costs one redundant re-push on the
  /// next cycle; a false positive silently loses a line.
  Future<void> markOrdersAsSyncedIfUnchanged(
      Map<int, DateTime> pushedUpdatedAt) async {
    if (pushedUpdatedAt.isEmpty) return;
    final rows = await (_database.select(_database.orders)
          ..where((o) => o.id.isIn(pushedUpdatedAt.keys.toList())))
        .get();

    final stillClean = <int>[];
    for (final row in rows) {
      final pushed = pushedUpdatedAt[row.id];
      if (pushed == null) continue;
      if (row.updatedAt.isAtSameMomentAs(pushed)) {
        stillClean.add(row.id);
      } else {
        _logger.info(
            'markOrdersAsSynced: order #${row.id} changed mid-push '
            '(pushed=$pushed now=${row.updatedAt}) — left unsynced so the '
            'next cycle pushes the newer lines');
      }
    }
    await markOrdersAsSynced(stillClean);
  }

  /// `id → updatedAt` for the order maps that were just pushed, so
  /// [markOrdersAsSyncedIfUnchanged] can tell a confirmed snapshot from a
  /// superseded one. Orders missing either field are skipped rather than
  /// marked blind.
  Map<int, DateTime> _pushedUpdatedAtById(List<Map<String, dynamic>> orders) {
    final out = <int, DateTime>{};
    for (final o in orders) {
      final id = o['id'];
      final raw = o['updatedAt'];
      if (id is! int || raw is! String) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) out[id] = parsed;
    }
    return out;
  }

  /// Mark tickets as synced
  Future<void> markTicketsAsSynced(List<int> ticketIds) async {
    if (ticketIds.isEmpty) return;
    await (_database.update(_database.tickets)
      ..where((t) => t.id.isIn(ticketIds)))
      .write(const TicketsCompanion(isSynced: Value(true)));
  }

  /// Mark sessions synced only if nothing touched them since they were read.
  /// A Z close flags its last session while a push may be in flight; marking
  /// that row synced would drop the close fields for good.
  Future<void> _markSessionsSyncedIfUnchanged(Map<int, DateTime> pushed) async {
    for (final e in pushed.entries) {
      await (_database.update(_database.cashSessions)
            ..where((s) => s.id.equals(e.key) & s.updatedAt.equals(e.value)))
          .write(const CashSessionsCompanion(isSynced: Value(true)));
    }
  }

  /// Mark sessions as synced
  Future<void> markSessionsAsSynced(List<int> sessionIds) async {
    if (sessionIds.isEmpty) return;
    await (_database.update(_database.cashSessions)
      ..where((s) => s.id.isIn(sessionIds)))
      .write(const CashSessionsCompanion(isSynced: Value(true)));
  }

  /// Mark customers as synced
  Future<void> markCustomersAsSynced(List<int> customerIds) async {
    if (customerIds.isEmpty) return;
    await (_database.update(_database.customers)
      ..where((c) => c.id.isIn(customerIds)))
      .write(const CustomersCompanion(isSynced: Value(true)));
  }

  /// Renumber local customer rows whose canonical server id differs from
  /// the local autoincrement value. Cascades the renumber to every order
  /// row that referenced the old id, in one transaction so the FK is never
  /// dangling. No-op when the backend returns no mappings (= old backend
  /// or no divergence).
  Future<void> _reconcileCustomerIds(
      List<Map<String, dynamic>> mappings) async {
    if (mappings.isEmpty) return;
    await _database.transaction(() async {
      for (final m in mappings) {
        final localId = m['localId'];
        final serverId = m['serverId'];
        if (localId is! int || serverId is! int) continue;
        if (localId == serverId) continue;
        // Update orders' FK FIRST so we never leave a dangling reference.
        await _database.customStatement(
          'UPDATE orders SET client_id = ? WHERE client_id = ?;',
          [serverId, localId],
        );
        // Then the customer row itself.
        await _database.customStatement(
          'UPDATE customers SET id = ? WHERE id = ?;',
          [serverId, localId],
        );
        _logger.info(
            'Reconciled customer local id $localId -> server id $serverId');
      }
    });
  }

  // ── Targeted pull-sync helpers (no full master-data wipe) ─────────────────

  /// Pull + persist categories, products, variants and components without
  /// touching orders, sessions, or any other unrelated table.
  Future<void> syncMenu() async {
    final categories = await _apiService.fetchCategories();
    final products = await _apiService.fetchProducts();
    final variants = await _apiService.fetchVariants();
    List<Map<String, dynamic>> serials = const [];
    try {
      serials = await _apiService.fetchSerials();
    } catch (e) {
      _logger.warning('Serial sync skipped: $e');
    }
    final componentGroups = await _apiService.fetchComponentGroups();
    final components = await _apiService.fetchComponents();
    final productComponents = await _apiService.fetchProductComponents();
    final stations = await _apiService.fetchStations();

    // Same reasoning as syncAllData: an empty 200 is far more likely to be a
    // stripped header or a tenant-resolution blip than a genuinely emptied
    // catalog, so never let one drive deletes on a populated device.
    final localProducts = await _database.select(_database.products).get();
    if (products.isEmpty && localProducts.isNotEmpty) {
      throw Exception(
          'Menu sync aborted: server returned 0 products but the device has '
          '${localProducts.length}. Local data kept.');
    }

    await _database.transaction(() async {
      await _persistCategories(categories);
      await _persistStations(stations);
      await _persistProducts(products);
      await _persistVariants(variants);
      await _persistSerials(serials);
      await _persistComponentGroups(componentGroups);
      await _persistComponents(components);
      await _persistProductComponents(productComponents);

      await _reconcileDeletes(
          _database.productVariants.actualTableName, _idsOf(variants));
      if (serials.isNotEmpty) {
        await _reconcileDeletes(
            _database.serials.actualTableName, _idsOf(serials));
      }
      await _reconcileDeletes(
          _database.products.actualTableName, _idsOf(products));
      await _reconcileDeletes(
          _database.components.actualTableName, _idsOf(components));
      await _reconcileDeletes(
          _database.componentGroups.actualTableName, _idsOf(componentGroups));
      await _reconcileDeletes(
          _database.stations.actualTableName, _idsOf(stations));
      await _reconcileDeletes(
          _database.categories.actualTableName, _idsOf(categories));
    });

    // Outside the transaction: it does its own network call and swallows its
    // own failures, and a tenant with no delivery integration must not fail a
    // menu sync over it.
    await syncIntegrationMappings();
  }

  /// Pull + persist users only. `lastLogin` / `displayName` survive on their
  /// own now that this upserts instead of replacing.
  Future<void> syncUsersOnly() async {
    final users = await _apiService.fetchUsers();
    await _persistUsers(users);
  }

  /// Pull + persist areas and tables only. No snapshot/restore dance: the
  /// upsert leaves `orderId` and `tableState` untouched.
  Future<void> syncAreasOnly() async {
    final areas = await _apiService.fetchAreas();
    final tables = await _apiService.fetchTables();

    final localTables = await _database.select(_database.areaTables).get();
    if (tables.isEmpty && localTables.isNotEmpty) {
      throw Exception(
          'Table sync aborted: server returned 0 tables but the device has '
          '${localTables.length}. Local data kept.');
    }

    await _database.transaction(() async {
      await _persistAreas(areas);
      await _persistTables(tables);
      // An occupied table is never reconciled away mid-service.
      await _reconcileDeletes(
        _database.areaTables.actualTableName,
        _idsOf(tables),
        protectWhere: 'order_id IS NOT NULL',
      );
      await _reconcileDeletes(_database.areas.actualTableName, _idsOf(areas));
    });
  }

  /// Upload all unsynced local data to the server (sessions, orders, tickets,
  /// customers, pending ops). Does not pull anything from the server.
  Future<void> syncUpload({int batchSize = 50}) async {
    await syncPendingOperations();
    await syncSessionsBulk(batchSize: batchSize);
    await syncCashMovementsBulk(batchSize: batchSize);
    await syncPendingNotifications();
    await syncOrdersBulk(batchSize: batchSize);
    await syncTicketsBulk(batchSize: batchSize * 2);
    await syncCustomersBulk(batchSize: batchSize);
    // Refunds last: each one needs its order to exist server-side first, and
    // needs the server's line ids, which only become resolvable afterwards.
    await syncRefundsBulk(batchSize: batchSize);
  }

  // ── Upload flow ────────────────────────────────────────────────────────────

  /// Sync all local data to server
  /// Each entity type is synced independently so a failure in one does not
  /// block the others.  Mark-as-synced only runs when the API call succeeds.
  Future<void> uploadLocalData() async {
    // Sync customers first (may be referenced by orders)
    try {
      final customers = await getCustomersForSync();
      if (customers.isNotEmpty) {
        final mappings = await _apiService.syncCustomers(customers);
        // Renumber local rows whose canonical server id differs (no-op
        // when the server returns no mappings — old backends, no changes).
        await _reconcileCustomerIds(mappings);
        // Only mark after a confirmed successful API response.
        await markCustomersAsSynced(
            customers.map((c) => c['id'] as int).toList());
      }
    } catch (e) {
      _logger.error(
          'uploadLocalData: customers sync failed – will retry later: $e');
    }

    // Sync completed orders
    try {
      final orders = await getOrdersForSync();
      if (orders.isNotEmpty) {
        final pushedAt = _pushedUpdatedAtById(orders);
        await _applySerialConflicts(await _apiService.syncOrders(orders));
        await markOrdersAsSyncedIfUnchanged(pushedAt);
      }
    } catch (e) {
      _logger.error('uploadLocalData: orders sync failed – will retry later: $e');
    }

    // Sync tickets for synced orders
    try {
      final tickets = await getTicketsForSync();
      if (tickets.isNotEmpty) {
        _logger.debug("Syncing ${tickets.length} tickets");
        await _apiService.syncTickets(tickets);
        await markTicketsAsSynced(tickets.map((t) => t['id'] as int).toList());
      }
    } catch (e) {
      _logger.error('uploadLocalData: tickets sync failed – will retry later: $e');
    }
  }

  /// Sync a single session immediately (for online auto-sync)
  Future<bool> syncSingleSession(int sessionId) async {
    try {
      final session = await (_database.select(_database.cashSessions)
        ..where((s) => s.id.equals(sessionId)))
        .getSingleOrNull();

      if (session == null) {
        _logger.warning('Session #$sessionId not found for sync');
        return false;
      }

      if (session.isSynced) {
        _logger.info('Session #$sessionId already synced');
        return true;
      }

      final z = session.zId == null
          ? null
          : await (_database.select(_database.zs)
                ..where((t) => t.id.equals(session.zId!)))
              .getSingleOrNull();
      final sessionData = sessionSyncPayload(session, z)..remove('id');

      // Sync to server using single session endpoint (PUT to create/update)
      await _apiService.syncSingleSession(session.code, sessionData);

      await _markSessionsSyncedIfUnchanged({sessionId: session.updatedAt});

      _logger.info('Successfully synced session code=${session.code}');
      return true;
    } catch (e) {
      _logger.error('Error syncing single session: $e');
      return false;
    }
  }

  /// Fetches session rules from the server and persists them to SharedPrefs.
  /// Returns the parsed rules, or null if the server returned 404 / error
  /// (in which case the cached rules are left untouched).
  Future<SessionRules?> syncSessionRules() async {
    try {
      final raw = await _apiService.fetchSessionRules();
      if (raw == null) return null;
      final rules = SessionRules.fromJson(raw);
      final prefs = _prefs ?? await SharedPreferences.getInstance();
      await prefs.setString('session_rules_json', jsonEncode(rules.toJson()));
      return rules;
    } catch (e) {
      _logger.warning('syncSessionRules: $e');
      return null;
    }
  }

  /// Deliver notifications queued while the network was down.
  Future<int> syncPendingNotifications() async {
    try {
      return await NotificationOutbox(_database, _apiService).flush();
    } catch (e) {
      _logger.warning('Notification outbox flush failed: $e');
      return 0;
    }
  }

  /// The tenant's business-day definition from `GET /pos/identity`
  /// (`timezone`, `businessDayStartHour`). Null on any failure, so the cached
  /// copy stands.
  Future<BusinessDayConfig?> syncBusinessDayConfig() async {
    try {
      final identity = await _apiService.fetchPosIdentity();
      if (identity == null || !identity.containsKey('businessDayStartHour')) {
        return null;
      }
      return BusinessDayConfig.fromJson(identity);
    } catch (e) {
      _logger.warning('syncBusinessDayConfig: $e');
      return null;
    }
  }

  // ── Cash movements (drawer pay-in / pay-out) ──────────────────────────────

  /// Unsynced movements as push payloads. Attached to their session by
  /// `sessionCode`; the server links them to the Z itself.
  Future<List<({int id, String code, Map<String, dynamic> payload})>>
      getCashMovementsForSync() async {
    final rows = await (_database.select(_database.cashMovements)
          ..where((m) => m.isSynced.equals(false)))
        .get();
    if (rows.isEmpty) return const [];
    final sessionIds = rows.map((m) => m.sessionId).whereType<int>().toSet();
    final sessions = sessionIds.isEmpty
        ? const <CashSession>[]
        : await (_database.select(_database.cashSessions)
              ..where((s) => s.id.isIn(sessionIds)))
            .get();
    final codeBySession = {for (final s in sessions) s.id: s.code};
    return [
      for (final m in rows)
        if (m.code != null)
          (
            id: m.id,
            code: m.code!,
            payload: cashMovementSyncPayload(
                m, m.sessionId == null ? null : codeBySession[m.sessionId]),
          ),
    ];
  }

  static Map<String, dynamic> cashMovementSyncPayload(
      CashMovement m, String? sessionCode) {
    final zDay = m.zDay;
    return {
      'code': m.code,
      'type': m.direction == 'IN' ? 'PAY_IN' : 'PAY_OUT',
      'amount': m.amount.abs(),
      'reason': m.reason,
      if (m.reference != null) 'reference': m.reference,
      'sessionCode': sessionCode,
      'userId': m.createdBy,
      'occurredAt': m.createdAt.toIso8601String(),
      if (zDay != null)
        'zDay': '${zDay.year.toString().padLeft(4, '0')}-'
            '${zDay.month.toString().padLeft(2, '0')}-'
            '${zDay.day.toString().padLeft(2, '0')}',
    };
  }

  /// Push unsynced cash movements (bulk first, one by one on failure).
  Future<int> syncCashMovementsBulk({int batchSize = 50}) async {
    try {
      final pending = await getCashMovementsForSync();
      if (pending.isEmpty) return 0;
      final batch = pending.take(batchSize).toList();
      Future<void> mark(List<int> ids) =>
          (_database.update(_database.cashMovements)
                ..where((m) => m.id.isIn(ids)))
              .write(const CashMovementsCompanion(isSynced: Value(true)));
      try {
        await _apiService
            .syncCashMovements(batch.map((m) => m.payload).toList());
        await mark(batch.map((m) => m.id).toList());
        return batch.length;
      } catch (bulkError) {
        _logger.warning('Bulk cash movement sync failed: $bulkError');
        var ok = 0;
        for (final m in batch) {
          try {
            await _apiService.syncSingleCashMovement(m.code, m.payload);
            await mark([m.id]);
            ok++;
          } catch (e) {
            _logger.error('Cash movement ${m.code} sync failed: $e');
            if (isNetworkFailure(e)) break;
          }
        }
        return ok;
      }
    } catch (e) {
      _logger.error('Error syncing cash movements: $e');
      return 0;
    }
  }

  /// Sync a single order immediately (for online auto-sync)
  /// [deadline] bounds the network push only (not the local reads/writes
  /// around it). Passed by the detached "prompt push" the cashier's tap kicks
  /// off, so a hanging server hands over to the pending-ops fallback and the
  /// periodic sweep in seconds instead of sitting on Dio's 10s connect + 30s
  /// receive. Null (bulk sync, manual sync) keeps the Dio defaults.
  Future<bool> syncSingleOrder(int orderId, {Duration? deadline}) async {
    try {
      // Get the specific order with products
      final order = await (_database.select(_database.orders)
        ..where((o) => o.id.equals(orderId)))
        .getSingleOrNull();

      if (order == null) {
        _logger.warning('Order #$orderId not found for sync');
        return false;
      }

      if (order.isSynced) {
        _logger.info('Order #$orderId already synced');
        return true;
      }

      // Get all products for this order
      final orderProducts = await (_database.select(_database.orderProducts)
        ..where((op) => op.orderId.equals(order.id)))
        .get();

      // Build products list, merging order-level discount into manualDiscount
      final productsList = await buildProductsListForSync(orderProducts, order.discountPercentage);

      // Resolve customer phone for the new phone-keyed contract.
      String? customerPhoneNormalized;
      if (order.clientId != null) {
        final c = await (_database.select(_database.customers)
              ..where((t) => t.id.equals(order.clientId!)))
            .getSingleOrNull();
        customerPhoneNormalized = c?.phoneNormalized;
      }

      // Resolve the parent session's code for the backend's session-keyed
      // contract. See the matching block in getOrdersForSync.
      String? sessionCode;
      if (order.sessionId != null) {
        final s = await (_database.select(_database.cashSessions)
              ..where((t) => t.id.equals(order.sessionId!)))
            .getSingleOrNull();
        sessionCode = s?.code;
      }

      // Build order map - use code as identifier for backend
      // discountPercentage is set to 0 because it's been merged into each product's manualDiscount
      final orderData = {
        'code': order.code,
        'status': order.status,
        'type': order.type,
        'priority': order.priority,
        'coupon': order.coupon,
        'persons': order.persons,
        'tableId': order.tableId,
        // Origin of the order — see getOrdersForSync for the contract.
        'source': order.source,
        // Kept for backward compat with older backends.
        'clientId': order.clientId,
        'customerPhoneNormalized': customerPhoneNormalized,
        'commercialId': order.commercialId,
        'discountPercentage': 0.0,
        // Sent regardless of value — see comment in getOrdersForSync.
        'tip': order.tip,
        'createdBy': order.createdBy,
        'takenBy': order.takenBy,
        'servedBy': order.waiterId,
        'sessionId': order.sessionId,
        'sessionCode': sessionCode,
        'zDay': order.zDay?.toIso8601String(),
        'note': order.note,
        'address': order.address,
        'cancellationReason': order.cancellationReason,
        // See getOrdersForSync — without `date` the server stamps "now".
        'date': order.date.toIso8601String(),
        ..._orderContractFields(order),
        'products': productsList,
        'createdAt': order.createdAt.toIso8601String(),
        'updatedAt': order.updatedAt.toIso8601String(),
      };

      // Sync to server using single order endpoint (PUT to create/update)
      final push = _apiService.syncSingleOrder(order.code, orderData);
      await _applySerialConflicts(
          await (deadline == null ? push : push.timeout(deadline)));

      // Mark as synced — but only if nothing was appended to the order while
      // this push was in flight. The waiter routes write over the LAN while
      // this runs unawaited, so an unconditional mark here strands their line.
      await markOrdersAsSyncedIfUnchanged({orderId: order.updatedAt});

      _logger.info('Successfully synced order code=${order.code}');
      _lastFailureWasNetwork = false;
      return true;
    } catch (e) {
      _lastFailureWasNetwork = isNetworkFailure(e);
      _logger.error('Error syncing single order: $e');
      // Stale unit cache: refresh it so the next attempt (or the cashier's next
      // pick) is made against server truth rather than repeating the failure.
      if (isSerialRejection(e)) {
        _logger.warning('Serial rejection — refreshing the serial cache');
        await refreshSerials();
      }
      return false;
    }
  }

  /// Serial rejections mean the local unit cache disagrees with the server —
  /// the unit was sold on another terminal, or its reception was never
  /// validated. Retrying the same payload can only fail again, so re-pull the
  /// serials and let the cashier pick a unit that actually exists.
  ///
  /// Matched on the message because the backend returns all six serial failures
  /// as a plain 400; there is no error code to switch on.
  static bool isSerialRejection(Object error) {
    final m = error.toString().toLowerCase();
    if (!m.contains('serial')) return false;
    return m.contains('not available') ||
        m.contains('serial-tracked') ||
        m.contains('must have quantity') ||
        m.contains('belongs to product') ||
        m.contains('more than one line') ||
        m.contains('remove serialid');
  }

  /// Re-pull just the serial cache. Safe to call from an error path: it swallows
  /// its own failures, because it is already running because something failed.
  Future<bool> refreshSerials() async {
    try {
      final serials = await _apiService.fetchSerials();
      await _persistSerials(serials);
      if (serials.isNotEmpty) {
        await _reconcileDeletes(
            _database.serials.actualTableName, _idsOf(serials));
      }
      _logger.info('Serial cache refreshed (${serials.length} rows)');
      return true;
    } catch (e) {
      _logger.error('Serial refresh failed: $e');
      return false;
    }
  }

  /// Sync tickets for a single order (used by auto-sync when online)
  /// [deadline] bounds the network push only — see [syncSingleOrder].
  Future<bool> syncTicketsForOrder(int orderId, {Duration? deadline}) async {
    try {
      final order = await (_database.select(_database.orders)
        ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();

      if (order == null) {
        _logger.warning('Order #$orderId not found when syncing tickets');
        return false;
      }

      final tickets = await (_database.select(_database.tickets)
        ..where((t) => t.orderId.equals(orderId) & t.isSynced.equals(false)))
          .get();

      if (tickets.isEmpty) {
        _logger.info('No tickets to sync for order code=${order.code}');
        return true;
      }

      final sessions = await (_database.select(_database.cashSessions)).get();
      final sessionCodeById = {for (final s in sessions) s.id: s.code};

      final payload = <Map<String, dynamic>>[];
      for (final t in tickets) {
        payload.add({
          'id': t.id,
          'num': t.num,
          'orderCode': order.code,
          'orderId': t.orderId,
          'sessionId': t.sessionId,
          'sessionCode': t.sessionId != null ? sessionCodeById[t.sessionId] : null,
          'paymentMethod': t.paymentMethod,
          'amount': t.amount,
          'isPaid': t.isPaid,
          'isCancelled': t.isCancelled,
          'printCount': t.printCount,
          'date': t.date.toIso8601String(),
          'createdAt': t.date.toIso8601String(),
        });
      }

      final push = _apiService.syncTickets(payload);
      await (deadline == null ? push : push.timeout(deadline));
      await markTicketsAsSynced(tickets.map((t) => t.id).toList());

      _logger.info('Synced ${tickets.length} tickets for order code=${order.code}');
      return true;
    } catch (e) {
      _logger.error('Error syncing tickets for order #$orderId: $e');
      return false;
    }
  }

  /// Sync orders in bulk with limited batch size
  /// Only sends bulk request if more than one order, otherwise uses single sync.
  /// If the bulk request fails, falls back to individual syncs so only
  /// confirmed-successful orders are marked as synced.
  /// Give up the units another terminal sold first.
  ///
  /// Two tills go offline, both sell the same boxed unit, both come back. The
  /// server awards it to whoever got there first and drops the serial links
  /// from the losing order — the order itself still saves and still counts.
  /// This is the losing terminal reconciling with that.
  ///
  /// Note what is NOT done here: the serial stays unavailable locally, because
  /// it genuinely is — somebody sold it. And nothing is undone on the order.
  /// The customer left with a box and a receipt naming that serial; erasing
  /// every trace would make the records tidy and the shop floor unexplainable.
  ///
  /// Never throws. It runs after a sync the server has already accepted, and
  /// turning that into a failure would re-queue the batch forever — the exact
  /// behaviour this feature was built to remove.
  Future<void> _applySerialConflicts(List<SerialConflictReport> conflicts) async {
    if (conflicts.isEmpty) return;
    for (final conflict in conflicts) {
      try {
        final order = await (_database.select(_database.orders)
              ..where((o) => o.code.equals(conflict.orderCode)))
            .getSingleOrNull();
        if (order != null) {
          final lines = await (_database.select(_database.orderProducts)
                ..where((p) => p.orderId.equals(order.id))
                ..where((p) => p.serialId.equals(conflict.serialId)))
              .get();
          for (final line in lines) {
            // The number stays in the note: once the link is gone this is the
            // only place the terminal still says which box went out the door.
            final note = [
              if (line.note != null && line.note!.trim().isNotEmpty) line.note!,
              conflict.historyNote,
            ].join(' · ');
            await (_database.update(_database.orderProducts)
                  ..where((p) => p.id.equals(line.id)))
                .write(OrderProductsCompanion(
              serialId: const Value(null),
              note: Value(note),
              updatedAt: Value(DateTime.now()),
            ));
          }
        }

        // One row per (order, serial). Re-syncing the same order must not pile
        // up duplicates of a conflict somebody has already seen.
        final existing = await (_database.select(_database.serialConflicts)
              ..where((c) => c.orderCode.equals(conflict.orderCode))
              ..where((c) => c.serialId.equals(conflict.serialId)))
            .getSingleOrNull();
        if (existing == null) {
          await _database.into(_database.serialConflicts).insert(
                SerialConflictsCompanion.insert(
                  orderCode: conflict.orderCode,
                  productId: conflict.productId,
                  serialId: conflict.serialId,
                  serialNumber: Value(conflict.serialNumber),
                  winningOrderCode: Value(conflict.winningOrderCode),
                  reason: Value(conflict.reason),
                ),
              );
        }
        _logger.warning('Serial conflict on ${conflict.orderCode}: '
            '${conflict.historyNote}');
      } catch (e) {
        _logger.warning('Could not apply serial conflict $conflict: $e');
      }
    }
  }

  Future<int> syncOrdersBulk({int batchSize = 50}) async {
    try {
      // Get unsynced orders
      final orders = await getOrdersForSync();

      if (orders.isEmpty) {
        return 0;
      }

      // Take only the specified batch size
      final batch = orders.take(batchSize).toList();

      // If only one order, use single sync instead of bulk
      if (batch.length == 1) {
        final orderId = batch.first['id'] as int;
        final success = await syncSingleOrder(orderId);
        return success ? 1 : 0;
      }

      // Try bulk sync first
      try {
        final pushedAt = _pushedUpdatedAtById(batch);
        await _applySerialConflicts(await _apiService.syncOrders(batch));
        // Bulk succeeded – mark as synced, minus any order written to while
        // the batch was in flight (that one re-pushes on the next cycle).
        await markOrdersAsSyncedIfUnchanged(pushedAt);
        return batch.length;
      } catch (bulkError) {
        // Bulk failed – fall back to individual sync so only confirmed
        // orders get marked as synced (prevents phantom synced orders)
        _logger.warning('Bulk order sync failed, falling back to individual sync: $bulkError');
        int successCount = 0;
        var networkFailures = 0;
        for (final orderMap in batch) {
          try {
            final orderId = orderMap['id'] as int;
            final success = await syncSingleOrder(orderId);
            if (success) {
              successCount++;
              networkFailures = 0;
            } else if (_lastFailureWasNetwork) {
              networkFailures++;
            } else {
              // The server answered and refused this particular order. That
              // says nothing about the next one, so keep going.
              networkFailures = 0;
            }
          } catch (e) {
            _logger.error('Individual order sync failed for order #${orderMap['id']}: $e');
            if (isNetworkFailure(e)) {
              networkFailures++;
            } else {
              networkFailures = 0;
            }
          }
          if (networkFailures >= _networkFailureStreakLimit) {
            _logger.warning(
              'Order sync: $networkFailures consecutive network failures — '
              'abandoning the remaining ${batch.length - batch.indexOf(orderMap) - 1} '
              'order(s) this cycle. Nothing is lost; they stay unsynced and go '
              'again next cycle.',
            );
            break;
          }
        }
        return successCount;
      }
    } catch (e) {
      _logger.error('Error syncing orders bulk: $e');
      return 0;
    }
  }

  /// Sync tickets in bulk for synced orders
  /// If the bulk call fails, falls back to per-order ticket sync.
  Future<int> syncTicketsBulk({int batchSize = 100}) async {
    try {
      // Get tickets for sync (only for synced orders)
      final tickets = await getTicketsForSync();

      if (tickets.isEmpty) {
        return 0;
      }

      // Take only the specified batch size
      final batch = tickets.take(batchSize).toList();

      try {
        // Sync the batch
        await _apiService.syncTickets(batch);

        // Mark as synced only after confirmed success
        final syncedIds = batch.map((t) => t['id'] as int).toList();
        await markTicketsAsSynced(syncedIds);

        return batch.length;
      } catch (bulkError) {
        // Bulk failed – fall back to per-order ticket sync
        _logger.warning('Bulk ticket sync failed, falling back to per-order sync: $bulkError');

        // Group tickets by orderId and sync per order
        final ticketsByOrder = <int, List<Map<String, dynamic>>>{};
        for (final t in batch) {
          final orderId = t['orderId'] as int;
          ticketsByOrder.putIfAbsent(orderId, () => []).add(t);
        }

        int successCount = 0;
        for (final entry in ticketsByOrder.entries) {
          try {
            final success = await syncTicketsForOrder(entry.key);
            if (success) successCount += entry.value.length;
          } catch (e) {
            _logger.error('Per-order ticket sync failed for order #${entry.key}: $e');
          }
        }
        return successCount;
      }
    } catch (e) {
      _logger.error('Error syncing tickets bulk: $e');
      return 0;
    }
  }

  /// Sync customers in bulk
  /// If the bulk call fails, falls back to individual customer sync.
  Future<int> syncCustomersBulk({int batchSize = 100}) async {
    try {
      // Get customers for sync
      final customers = await getCustomersForSync();

      if (customers.isEmpty) {
        return 0;
      }

      // Take only the specified batch size
      final batch = customers.take(batchSize).toList();

      try {
        // Sync the batch
        await _apiService.syncCustomers(batch);

        // Mark as synced only after confirmed success
        final syncedIds = batch.map((c) => c['id'] as int).toList();
        await markCustomersAsSynced(syncedIds);

        return batch.length;
      } catch (bulkError) {
        _logger.warning('Bulk customer sync failed, falling back to individual sync: $bulkError');
        int successCount = 0;
        for (final customer in batch) {
          try {
            await _apiService.syncCustomers([customer]);
            await markCustomersAsSynced([customer['id'] as int]);
            successCount++;
          } catch (e) {
            _logger.error('Individual customer sync failed for #${customer['id']}: $e');
          }
        }
        return successCount;
      }
    } catch (e) {
      _logger.error('Error syncing customers bulk: $e');
      return 0;
    }
  }

  /// Sync ended sessions in bulk
  /// If the bulk call fails, falls back to individual session sync.
  Future<int> syncSessionsBulk({int batchSize = 50}) async {
    try {
      final sessions = await _sessionsForSync();
      if (sessions.isEmpty) {
        return 0;
      }

      final batch = sessions.take(batchSize).toList();

      try {
        await _apiService.syncSessions(batch.map((e) => e.payload).toList());
        await _markSessionsSyncedIfUnchanged({
          for (final e in batch) e.payload['id'] as int: e.updatedAt,
        });
        return batch.length;
      } catch (bulkError) {
        _logger.warning('Bulk session sync failed, falling back to individual sync: $bulkError');
        int successCount = 0;
        for (final e in batch) {
          final session = e.payload;
          try {
            final sessionCode = session['code'] as String;
            await _apiService.syncSingleSession(sessionCode, session);
            await _markSessionsSyncedIfUnchanged(
                {session['id'] as int: e.updatedAt});
            successCount++;
          } catch (e) {
            _logger.error('Individual session sync failed for #${session['id']}: $e');
          }
        }
        return successCount;
      }
    } catch (e) {
      _logger.error('Error syncing sessions bulk: $e');
      return 0;
    }
  }

  /// Get sync status summary
  Future<Map<String, int>> getSyncStatus() async {
    // Use SQL COUNT — NOT `.get().length`, which would fetch and deserialize
    // every unsynced row across these tables just to count them (a real stall
    // on the exit path when there's a backlog or a big customers table).
    final ordersCnt = countAll(filter: _database.orders.isSynced.equals(false));
    final ticketsCnt =
        countAll(filter: _database.tickets.isSynced.equals(false));
    final sessionsCnt = countAll(
        filter: _database.cashSessions.status.equals('ended') &
            _database.cashSessions.isSynced.equals(false));
    final customersCnt =
        countAll(filter: _database.customers.isSynced.equals(false));

    final ordersN = (await (_database.selectOnly(_database.orders)
              ..addColumns([ordersCnt]))
            .getSingle())
        .read(ordersCnt) ??
        0;
    final ticketsN = (await (_database.selectOnly(_database.tickets)
              ..addColumns([ticketsCnt]))
            .getSingle())
        .read(ticketsCnt) ??
        0;
    final sessionsN = (await (_database.selectOnly(_database.cashSessions)
              ..addColumns([sessionsCnt]))
            .getSingle())
        .read(sessionsCnt) ??
        0;
    final customersN = (await (_database.selectOnly(_database.customers)
              ..addColumns([customersCnt]))
            .getSingle())
        .read(customersCnt) ??
        0;

    return {
      'orders': ordersN,
      'tickets': ticketsN,
      'sessions': sessionsN,
      'customers': customersN,
    };
  }

  /// Count of Z shifts still waiting to be pushed. Not part of [getSyncStatus]
  /// (which mirrors the status UI) — used by the exit flow to decide whether a
  /// pre-exit flush is needed at all.
  Future<int> countUnsyncedZs() async {
    final cnt = countAll(filter: _database.zs.isSynced.equals(false));
    return (await (_database.selectOnly(_database.zs)..addColumns([cnt]))
                .getSingle())
            .read(cnt) ??
        0;
  }

  /// Sync all pending operations (deletes and updates)
  Future<void> syncPendingOperations() async {
    try {
      _logger.info('Starting sync of pending operations...');
      final operations = await _pendingOpsService.getPendingOperations();

      if (operations.isEmpty) {
        _logger.info('No pending operations to sync');
        return;
      }

      _logger.info('Found ${operations.length} pending operations');
      int successCount = 0;
      int failureCount = 0;

      for (final operation in operations) {
        try {
          if (operation.operationType == 'DELETE') {
            await _processPendingDelete(operation);
          } else if (operation.operationType == 'UPDATE') {
            await _processPendingUpdate(operation);
          }

          // Mark as completed
          await _pendingOpsService.markCompleted(operation.id);
          successCount++;
        } catch (e) {
          _logger.error('Failed to sync operation #${operation.id}: $e');
          await _pendingOpsService.recordFailure(operation.id, e.toString());
          failureCount++;
        }
      }

      _logger.info('Pending operations sync complete: $successCount succeeded, $failureCount failed');
    } catch (e) {
      _logger.error('Error syncing pending operations: $e');
    }
  }

  /// Process a pending delete operation
  Future<void> _processPendingDelete(PendingSyncOperation operation) async {
    _logger.info('Processing DELETE for ${operation.entityType} #${operation.entityId}');

    switch (operation.entityType) {
      case 'ORDER':
        // Temporarily get orderCode from updateData JSON until database is regenerated
        String? orderCode;
        if (operation.updateData != null) {
          try {
            final data = jsonDecode(operation.updateData!) as Map<String, dynamic>;
            orderCode = data['_orderCode'] as String?;
          } catch (e) {
            _logger.error('Failed to parse orderCode from updateData: $e');
          }
        }

        if (orderCode == null) {
          _logger.warning('Skipping DELETE - no order code for ORDER #${operation.entityId}');
          return;
        }
        await _apiService.deleteOrder(orderCode);
        _logger.info('Deleted order code=$orderCode from server');
        break;

      case 'TICKET':
        // Temporarily get orderCode and ticketNum from updateData JSON
        String? orderCode;
        String? ticketNum;
        if (operation.updateData != null) {
          try {
            final data = jsonDecode(operation.updateData!) as Map<String, dynamic>;
            orderCode = data['_orderCode'] as String?;
            ticketNum = data['_ticketNum'] as String?;
          } catch (e) {
            _logger.error('Failed to parse ticket data from updateData: $e');
          }
        }

        if (orderCode == null || ticketNum == null) {
          _logger.warning('Skipping DELETE - missing orderCode or ticketNum for TICKET #${operation.entityId}');
          return;
        }
        await _apiService.deleteTicket(orderCode, ticketNum);
        _logger.info('Deleted ticket orderCode=$orderCode, ticketNum=$ticketNum from server');
        break;

      case 'ORDER_PRODUCT':
        if (operation.serverId == null) {
          _logger.warning('Skipping DELETE - no server ID for ORDER_PRODUCT #${operation.entityId}');
          return;
        }
        await _apiService.deleteOrderProduct(operation.serverId!);
        _logger.info('Deleted order product #${operation.serverId} from server');
        break;

      case 'SCHEDULE':
        // Freeing a slot is the one booking call that may be replayed: it only
        // ever gives capacity back, so arriving late can wrong nobody.
        if (operation.serverId == null) {
          _logger.warning(
              'Skipping unschedule - no server ID for line #${operation.entityId}');
          return;
        }
        await _apiService.deleteSchedule(operation.serverId!);
        _logger.info('Unscheduled line #${operation.serverId} on server');
        break;

      case 'SESSION':
        // Get sessionCode from updateData
        String? sessionCode;
        if (operation.updateData != null) {
          try {
            final data = jsonDecode(operation.updateData!) as Map<String, dynamic>;
            sessionCode = data['_sessionCode'] as String?;
          } catch (e) {
            _logger.error('Failed to parse sessionCode from updateData: $e');
          }
        }

        if (sessionCode == null) {
          _logger.warning('Skipping DELETE - no session code for SESSION #${operation.entityId}');
          return;
        }
        await _apiService.deleteSession(sessionCode);
        _logger.info('Deleted session code=$sessionCode from server');
        break;

      default:
        _logger.warning('Unknown entity type for delete: ${operation.entityType}');
    }
  }

  /// Process a pending update operation
  Future<void> _processPendingUpdate(PendingSyncOperation operation) async {
    _logger.info('Processing UPDATE for ${operation.entityType} #${operation.entityId}');

    if (operation.updateData == null) {
      _logger.warning('Skipping UPDATE - no update data for ${operation.entityType} #${operation.entityId}');
      return;
    }

    final rawData = jsonDecode(operation.updateData!) as Map<String, dynamic>;

    switch (operation.entityType) {
      case 'ORDER':
        // Extract orderCode and actual update data
      _logger.debug("Raw data for update: $rawData");
        final orderCode = rawData['_orderCode'] as String?;
        if (orderCode == null) {
          _logger.warning('Skipping UPDATE - no order code for ORDER #${operation.entityId}');
          return;
        }

        // Remove metadata fields
        final updateData = Map<String, dynamic>.from(rawData);
        updateData.remove('_orderCode');
        updateData.remove('_ticketNum');

        await _apiService.updateOrder(orderCode, updateData);
        _logger.info('Updated order code=$orderCode on server');
        break;

      case 'TICKET':
        // Extract orderCode, ticketNum and actual update data
        final orderCode = rawData['_orderCode'] as String?;
        final ticketNum = rawData['_ticketNum'] as String?;
        if (orderCode == null || ticketNum == null) {
          _logger.warning('Skipping UPDATE - missing orderCode or ticketNum for TICKET #${operation.entityId}');
          return;
        }

        // Remove metadata fields
        final updateData = Map<String, dynamic>.from(rawData);
        _logger.debug(updateData.toString());
        await _apiService.updateTicket(orderCode, ticketNum, updateData);
        _logger.info('Updated ticket orderCode=$orderCode, ticketNum=$ticketNum on server');
        break;

      case 'SESSION':
        // Extract sessionCode and actual update data
        final sessionCode = rawData['_sessionCode'] as String?;
        if (sessionCode == null) {
          _logger.warning('Skipping UPDATE - no session code for SESSION #${operation.entityId}');
          return;
        }

        // Remove metadata fields
        final updateData = Map<String, dynamic>.from(rawData);
        updateData.remove('_sessionCode');

        await _apiService.updateSession(sessionCode, updateData);
        _logger.info('Updated session code=$sessionCode on server');
        break;

      case 'ORDER_PRODUCT':
        // Order product updates are handled by resending the full order
        // Backend deletes all products and recreates them with same order code
        _logger.info('ORDER_PRODUCT update skipped - handled via order sync');
        break;

      default:
        _logger.warning('Unknown entity type for update: ${operation.entityType}');
    }
  }

  /// Queue a delete operation (for offline support)
  Future<void> queueDelete(String entityType, int entityId, {int? serverId, String? orderCode, String? ticketNum}) async {
    await _pendingOpsService.queueDelete(
      entityType: entityType,
      entityId: entityId,
      serverId: serverId,
      orderCode: orderCode,
      ticketNum: ticketNum,
    );
  }

  /// Queue an update operation (for offline support)
  Future<void> queueUpdate(String entityType, int entityId, Map<String, dynamic> updateData, {int? serverId, String? orderCode, String? ticketNum}) async {
    await _pendingOpsService.queueUpdate(
      entityType: entityType,
      entityId: entityId,
      serverId: serverId,
      orderCode: orderCode,
      ticketNum: ticketNum,
      updateData: updateData,
    );
  }

  /// Execute delete immediately if online, queue if offline
  Future<void> deleteOrderEntity({
    required int entityId,
    required String orderCode,
    required bool isOnline,
  }) async {
    if (isOnline) {
      try {
        await _apiService.deleteOrder(orderCode);
        _logger.info('Deleted order code=$orderCode from server immediately');
      } catch (e) {
        _logger.error('Failed to delete order immediately, queuing: $e');
        await _pendingOpsService.queueOrderDelete(entityId: entityId, orderCode: orderCode);
      }
    } else {
      await _pendingOpsService.queueOrderDelete(entityId: entityId, orderCode: orderCode);
    }
  }

  /// Execute ticket delete immediately if online, queue if offline
  Future<void> deleteTicketEntity({
    required int entityId,
    required String orderCode,
    required String ticketNum,
    required bool isOnline,
  }) async {
    if (isOnline) {
      try {
        await _apiService.deleteTicket(orderCode, ticketNum);
        _logger.info('Deleted ticket orderCode=$orderCode, ticketNum=$ticketNum from server immediately');
      } catch (e) {
        _logger.error('Failed to delete ticket immediately, queuing: $e');
        await _pendingOpsService.queueTicketDelete(entityId: entityId, orderCode: orderCode, ticketNum: ticketNum);
      }
    } else {
      await _pendingOpsService.queueTicketDelete(entityId: entityId, orderCode: orderCode, ticketNum: ticketNum);
    }
  }

  /// Execute order update immediately if online, queue if offline
  Future<void> updateOrderEntity({
    required int entityId,
    required String orderCode,
    required Map<String, dynamic> updateData,
    required bool isOnline,
  }) async {
    if (isOnline) {
      try {
        await _apiService.updateOrder(orderCode, updateData);
        _logger.info('Updated order code=$orderCode on server immediately');
      } catch (e) {
        _logger.error('Failed to update order immediately, queuing: $e');
        await _pendingOpsService.queueOrderUpdate(entityId: entityId, orderCode: orderCode, updateData: updateData);
      }
    } else {
      await _pendingOpsService.queueOrderUpdate(entityId: entityId, orderCode: orderCode, updateData: updateData);
    }
  }

  /// Execute ticket update immediately if online, queue if offline
  Future<void> updateTicketEntity({
    required int entityId,
    required String orderCode,
    required String ticketNum,
    required Map<String, dynamic> updateData,
    required bool isOnline,
  }) async {
    if (isOnline) {
      try {
        await _apiService.updateTicket(orderCode, ticketNum, updateData);
        _logger.info('Updated ticket orderCode=$orderCode, ticketNum=$ticketNum on server immediately');
      } catch (e) {
        _logger.error('Failed to update ticket immediately, queuing: $e');
        await _pendingOpsService.queueTicketUpdate(entityId: entityId, orderCode: orderCode, ticketNum: ticketNum, updateData: updateData);
      }
    } else {
      await _pendingOpsService.queueTicketUpdate(entityId: entityId, orderCode: orderCode, ticketNum: ticketNum, updateData: updateData);
    }
  }

  /// Execute session delete immediately if online, queue if offline
  Future<void> deleteSessionEntity({
    required int entityId,
    required String sessionCode,
    required bool isOnline,
  }) async {
    if (isOnline) {
      try {
        await _apiService.deleteSession(sessionCode);
        _logger.info('Deleted session code=$sessionCode from server immediately');
      } catch (e) {
        _logger.error('Failed to delete session immediately, queuing: $e');
        await _pendingOpsService.queueSessionDelete(entityId: entityId, sessionCode: sessionCode);
      }
    } else {
      await _pendingOpsService.queueSessionDelete(entityId: entityId, sessionCode: sessionCode);
    }
  }

  /// Execute session update immediately if online, queue if offline
  Future<void> updateSessionEntity({
    required int entityId,
    required String sessionCode,
    required Map<String, dynamic> updateData,
    required bool isOnline,
  }) async {
    if (isOnline) {
      try {
        await _apiService.updateSession(sessionCode, updateData);
        _logger.info('Updated session code=$sessionCode on server immediately');
      } catch (e) {
        _logger.error('Failed to update session immediately, queuing: $e');
        await _pendingOpsService.queueSessionUpdate(entityId: entityId, sessionCode: sessionCode, updateData: updateData);
      }
    } else {
      await _pendingOpsService.queueSessionUpdate(entityId: entityId, sessionCode: sessionCode, updateData: updateData);
    }
  }

  // ── Delta pull (server → POS) ─────────────────────────────────────────────

  /// Pull order deltas from the server, looping through all pages until
  /// `hasMore = false`. Applies each item as an upsert or tombstone delete.
  /// Persists the cursor to [prefs] after each page so partial progress
  /// survives a crash. On exception, stores the error string and returns the
  /// counts accumulated so far.
  Future<({int applied, int deleted, int pages})> pullOrderDeltas(
      SharedPreferences prefs) async {
    var cursor = prefs.getString(_kOrdersCursor);
    var applied = 0, deleted = 0, pages = 0;

    try {
      bool hasMore = true;
      while (hasMore) {
        final result = await _apiService.fetchOrderDeltas(cursor: cursor);
        final changes =
            ((result['changes'] as List?) ?? []).cast<Map<String, dynamic>>();
        final nextCursor = result['nextCursor'] as String?;
        hasMore = (result['hasMore'] as bool?) ?? false;

        for (final item in changes) {
          try {
            if (item['deletedAt'] != null) {
              await _applyOrderTombstone(item['code'] as String);
              deleted++;
            } else {
              await _applyOrderDelta(item);
              applied++;
            }
          } catch (e) {
            _logger.error('pullOrderDeltas: item ${item['code']}: $e');
          }
        }

        if (nextCursor != null && nextCursor.isNotEmpty) {
          cursor = nextCursor;
          await prefs.setString(_kOrdersCursor, nextCursor);
        }
        pages++;
        if (!hasMore) break;
      }

      await prefs.setString(
          _kOrdersLastSyncAt, DateTime.now().toIso8601String());
      _logger.info(
          'pullOrderDeltas: applied=$applied deleted=$deleted pages=$pages');
    } catch (e) {
      await prefs.setString(
          _kLastDeltaError, '${DateTime.now().toIso8601String()}  $e');
      _logger.error('pullOrderDeltas failed: $e');
    }

    return (applied: applied, deleted: deleted, pages: pages);
  }

  /// Pull payment (ticket) deltas from the server, same pagination logic as
  /// [pullOrderDeltas]. Skips items whose order doesn't exist locally yet.
  Future<({int applied, int deleted, int pages})> pullPaymentDeltas(
      SharedPreferences prefs) async {
    var cursor = prefs.getString(_kPaymentsCursor);
    var applied = 0, deleted = 0, pages = 0;

    try {
      bool hasMore = true;
      while (hasMore) {
        final result = await _apiService.fetchPaymentDeltas(cursor: cursor);
        final changes =
            ((result['changes'] as List?) ?? []).cast<Map<String, dynamic>>();
        final nextCursor = result['nextCursor'] as String?;
        hasMore = (result['hasMore'] as bool?) ?? false;

        for (final item in changes) {
          try {
            final orderCode =
                (item['orderCode'] ?? item['order_code']) as String?;
            if (orderCode == null) continue;

            final order = await (_database.select(_database.orders)
                  ..where((o) => o.code.equals(orderCode)))
                .getSingleOrNull();
            if (order == null) {
              _logger.warning(
                  'pullPaymentDeltas: order $orderCode not local, skipping');
              continue;
            }

            final ticketNum = (item['num'] as String?) ?? '';
            if (item['deletedAt'] != null) {
              await (_database.delete(_database.tickets)
                    ..where((t) =>
                        t.orderId.equals(order.id) & t.num.equals(ticketNum)))
                  .go();
              deleted++;
            } else {
              await _applyPaymentDelta(item, order.id);
              applied++;
            }
          } catch (e) {
            _logger.error('pullPaymentDeltas: item ${item['num']}: $e');
          }
        }

        if (nextCursor != null && nextCursor.isNotEmpty) {
          cursor = nextCursor;
          await prefs.setString(_kPaymentsCursor, nextCursor);
        }
        pages++;
        if (!hasMore) break;
      }

      await prefs.setString(
          _kPaymentsLastSyncAt, DateTime.now().toIso8601String());
      _logger.info(
          'pullPaymentDeltas: applied=$applied deleted=$deleted pages=$pages');
    } catch (e) {
      await prefs.setString(
          _kLastDeltaError, '${DateTime.now().toIso8601String()}  $e');
      _logger.error('pullPaymentDeltas failed: $e');
    }

    return (applied: applied, deleted: deleted, pages: pages);
  }

  /// Run both delta streams in sequence: orders first (so payments can
  /// resolve their `orderCode` FK), then payments.
  Future<void> pullAllDeltas(SharedPreferences prefs) async {
    await pullOrderDeltas(prefs);
    await pullPaymentDeltas(prefs);
  }

  /// Test seam for the delta reconciler — specifically which local lines a
  /// server snapshot is allowed to remove. Pure database work, no network.
  @visibleForTesting
  Future<void> applyOrderDeltaForTesting(Map<String, dynamic> item) =>
      _applyOrderDelta(item);

  Future<void> _applyOrderDelta(Map<String, dynamic> item) async {
    final code = item['code'] as String;

    // Log the raw incoming order so we can inspect server-sent prices.
    _logger.info('pullOrderDelta incoming order=$code '
        'products_count=${((item['products'] as List?) ?? []).length} '
        'raw_products=${item['products']}');

    final existing = await (_database.select(_database.orders)
          ..where((o) => o.code.equals(code)))
        .getSingleOrNull();

    // Resolved out here because the companion builder is synchronous. Used
    // only when neither the server nor the local row supplies a z_day — see
    // [_orderCompanionFromDelta].
    //
    // Deliberately an EXACT session lookup, with no fall-through to whatever
    // session is open now: a delta carries orders from other terminals and,
    // after a cursor reset, orders from months ago. Stamping those with this
    // terminal's current shift would drop a backfill straight into today's Z.
    final sessionZDay = await ZDayResolver(_database).forSession(
        existing?.sessionId ??
            ((item['sessionId'] ?? item['session_id']) as num?)?.toInt());

    // Header upsert, product snapshot, and delete/re-insert all commit together.
    // Previously the header was written outside the products transaction, so a
    // crash between them left the header updated with stale or missing products.
    late int orderId;
    await _database.transaction(() async {
    if (existing != null) {
      await (_database.update(_database.orders)
            ..where((o) => o.id.equals(existing.id)))
          .write(_orderCompanionFromDelta(item, existing, sessionZDay));
      orderId = existing.id;
    } else {
      orderId = await _database
          .into(_database.orders)
          .insert(_orderCompanionFromDelta(item, null, sessionZDay));
    }

    // Load existing lines and index them by (productId, variantId) so each
    // server line can be matched to a local row and UPDATED IN PLACE rather
    // than delete+reinsert. Update-in-place keeps line IDs stable and preserves
    // EVERY client-only column automatically (ticketId, zDay, KDS print +
    // stage timestamps) — the server only owns price/qty/discount/state/plan/
    // components. Duplicate product/variant lines are matched in insertion
    // order; whatever local rows go unmatched were removed remotely.
    final existingProductsList = await (_database.select(_database.orderProducts)
          ..where((op) => op.orderId.equals(orderId)))
        .get();
    final existingByKey = <(int, int?), List<OrderProduct>>{};
    final existingByServerId = <int, OrderProduct>{};
    for (final op in existingProductsList) {
      existingByKey.putIfAbsent((op.productId, op.variantId), () => []).add(op);
      if (op.serverId != null) existingByServerId[op.serverId!] = op;
    }
    // Rows a server line has already taken. Tracked instead of draining the
    // queues so an unclaimed row stays visible to the leftover pass below.
    final claimedRowIds = <int>{};

    // A delta that carries no `products` key at all is a HEADER-only change
    // (status, table move, tip). Treating its absent list as "zero lines" would
    // reconcile every local line away — the same guard the components block
    // below already applies. Only an explicitly sent list reconciles lines.
    final rawProducts = item['products'];
    final hasProductsPayload = rawProducts is List;
    final products = hasProductsPayload
        ? rawProducts.cast<Map<String, dynamic>>()
        : const <Map<String, dynamic>>[];

    // Every server line id this snapshot mentions. A local row whose serverId
    // is NOT in here has been orphaned: the backend no longer has the line
    // that id names, so the row was re-keyed rather than duplicated, and it is
    // free to be re-matched. Without this the re-keyed line could not bind to
    // anything, so it was INSERTED — and an inserted line starts with empty
    // client-only fields, i.e. kdsPrintedQuantity 0. The panel then showed the
    // same food twice: the original under "already sent", the phantom above it
    // as though the kitchen still owed it.
    final snapshotServerIds = <int>{
      for (final p in products)
        if ((p['id'] as num?) != null) (p['id'] as num).toInt(),
    };
    for (final p in products) {
      final productId = ((p['productId'] ?? p['product_id']) as num).toInt();
      final variantId = ((p['variantId'] ?? p['variant_id']) as num?)?.toInt();
      final key = (productId, variantId);

      // The server's own line id, read up here because matching needs it.
      final lineServerId = (p['id'] as num?)?.toInt();

      // Identity first, product key second.
      //
      // This used to match purely by position within (productId, variantId),
      // which quietly went wrong whenever an order held two lines of the same
      // product — routine, since the waiter app's add-product route never
      // merges into an existing line. The server line would bind to whichever
      // row happened to be first, stamp ITS server id onto that row, and leave
      // the row the id actually belonged to unmatched — i.e. a leftover, to be
      // deleted. A line that was rung up and sent to the kitchen vanished, and
      // nothing said so.
      OrderProduct? existingRow;
      if (lineServerId != null) {
        final byServerId = existingByServerId[lineServerId];
        if (byServerId != null && !claimedRowIds.contains(byServerId.id)) {
          existingRow = byServerId;
        }
      }
      if (existingRow == null) {
        for (final candidate in existingByKey[key] ?? const <OrderProduct>[]) {
          if (claimedRowIds.contains(candidate.id)) continue;
          // A row is free unless THIS snapshot still names its server line —
          // in which case that line will come along and claim it, and taking
          // it now would be theft. A row whose id the snapshot never mentions
          // is orphaned and re-keyable (see [snapshotServerIds]).
          if (candidate.serverId != null &&
              candidate.serverId != lineServerId &&
              snapshotServerIds.contains(candidate.serverId)) {
            continue;
          }
          existingRow = candidate;
          break;
        }
      }
      if (existingRow != null) claimedRowIds.add(existingRow.id);

      // ── Resolve server-owned fields, falling back to the matched local row
      //    when the server omits/zeros a value (same rules as before). ──
      final serverPrice =
          ((p['unitaryPrice'] ?? p['unitary_price'] ?? p['price']) as num?)?.toDouble();
      if (serverPrice == null || serverPrice == 0.0) {
        _logger.warning(
          'pullOrderDelta[$code] productId=$productId variantId=$variantId '
          'serverPrice=$serverPrice existingLocalPrice=${existingRow?.unitaryPrice} '
          '→ raw payload keys=${p.keys.toList()} '
          'unitaryPrice_raw=${p['unitaryPrice']} unitary_price_raw=${p['unitary_price']} '
          'full_product=$p',
        );
      }
      // Preserve local price when server omits or zeros it.
      final unitaryPrice = (serverPrice != null && serverPrice > 0)
          ? serverPrice
          : existingRow?.unitaryPrice ?? 0.0;
      if (unitaryPrice == 0.0) {
        _logger.warning(
          'pullOrderDelta[$code] productId=$productId → RESOLVED TO 0.0 '
          '(serverPrice=$serverPrice existingLocalPrice=${existingRow?.unitaryPrice})',
        );
      }

      final serverUnitaryDiscount =
          ((p['unitaryDiscount'] ?? p['unitary_discount'] ?? p['discountAmount'] ?? p['discount_amount']) as num?)?.toDouble();
      final serverManualDiscount =
          ((p['manualDiscount'] ?? p['manual_discount'] ?? p['manualDiscountAmount'] ?? p['manual_discount_amount']) as num?)?.toDouble();
      final unitaryDiscount =
          serverUnitaryDiscount ?? existingRow?.unitaryDiscount ?? 0.0;
      final manualDiscount =
          serverManualDiscount ?? existingRow?.manualDiscount ?? 0.0;
      final unitaryTva =
          ((p['unitaryTva'] ?? p['unitary_tva'] ?? p['totalTva'] ?? p['total_tva']) as num?)
                  ?.toDouble() ??
              0.0;

      // Preserve local quantity when server sends 0 — protects weighed/MBw
      // items whose decimal quantity may be truncated to 0 by the backend.
      final serverQty = (p['quantity'] as num?)?.toDouble();
      final qty = (serverQty != null && serverQty > 0)
          ? serverQty
          : existingRow?.quantity ?? 1.0;

      final note = p['note'] as String?;
      // Product KITCHEN state (PENDING→PREPARING→READY→COMPLETED) is LAN-LOCAL:
      // the KDS advances it without ever syncing it up, so the backend's copy is
      // authoritatively STALE. A pull must NOT let that stale state clobber the
      // local KDS progress — that's exactly what reset tickets after a sync
      // (delete/reinsert-from-backend wiped the kitchen state).
      //
      // The cloud only owns two product-state facts: a CANCELED decision (which
      // can originate backend-side) and a PAID line (financial). For a brand-new
      // local line we trust the server. Everything else keeps the local state.
      final serverState = p['state'] as String? ?? 'PENDING';
      final localState = existingRow?.state;
      final String state;
      if (localState == null) {
        state = serverState;
      } else if (serverOwnedProductStates.contains(serverState)) {
        state = serverState;
      } else {
        state = localState;
      }
      final planStartAt = _parseDateTime(p['planStartAt'] ?? p['plan_start_at']);
      final planEndAt = _parseDateTime(p['planEndAt'] ?? p['plan_end_at']);
      final planWaiterId =
          ((p['planWaiterId'] ?? p['plan_waiter_id']) as num?)?.toInt();
      final planResourceId =
          ((p['planResourceId'] ?? p['plan_resource_id']) as num?)?.toInt();
      // (`lineServerId` is parsed at the top of this loop — refunds reference
      // it, and this delta is one of only two places we ever learn it, the
      // other being an explicit GET /pos/orders/{code}.)
      final saleUomId =
          ((p['saleUomId'] ?? p['sale_uom_id']) as num?)?.toInt();

      // An EXPLICIT removal, which is the only kind there is. The server
      // stamps `deletedAt` on the line itself — it has always been in the
      // payload (`..., options: [...], deletedAt: null`) and was never read.
      // Nothing to do when the line was never here; never insert one that
      // arrives already deleted.
      if ((p['deletedAt'] ?? p['deleted_at']) != null) {
        if (existingRow != null) {
          if (existingRow.ticketId != null) {
            _logger.warning(
              'pullOrderDelta[$code] server deleted line serverId=$lineServerId '
              '(id=${existingRow.id} productId=$productId) but it is PAID on '
              'ticket ${existingRow.ticketId} — keeping it; a reported Z must '
              'not be rewritten by a pull',
            );
          } else {
            _logger.info(
              'pullOrderDelta[$code] server deleted line serverId=$lineServerId '
              '(id=${existingRow.id} productId=$productId '
              'kdsPrinted=${existingRow.kdsPrintedQuantity})',
            );
            await (_database.delete(_database.orderProductComponents)
                  ..where((c) => c.orderProductId.equals(existingRow!.id)))
                .go();
            await (_database.delete(_database.orderProducts)
                  ..where((op) => op.id.equals(existingRow!.id)))
                .go();
          }
        }
        continue;
      }

      final int opId;
      if (existingRow != null) {
        // UPDATE in place — write ONLY server-owned columns. Every client-only
        // column (ticketId, zDay, kdsPrintedAt/Quantity, preparing/ready/
        // servedAt, createdAt) is left untouched by omission. kdsPrintedQuantity
        // is clamped down ONLY when the server shrank the line below what was
        // already sent to the kitchen, so a remote qty drop can't strand it.
        opId = existingRow.id;
        await (_database.update(_database.orderProducts)
              ..where((t) => t.id.equals(opId)))
            .write(OrderProductsCompanion(
          quantity: Value(qty),
          unitaryPrice: Value(unitaryPrice),
          unitaryDiscount: Value(unitaryDiscount),
          unitaryTva: Value(unitaryTva),
          manualDiscount: Value(manualDiscount),
          note: Value(note),
          state: Value(state),
          planStartAt: Value(planStartAt),
          planEndAt: Value(planEndAt),
          planWaiterId: Value(planWaiterId),
          planResourceId: Value(planResourceId),
          serverId: lineServerId != null
              ? Value(lineServerId)
              : const Value.absent(),
          saleUomId:
              saleUomId != null ? Value(saleUomId) : const Value.absent(),
          kdsPrintedQuantity: existingRow.kdsPrintedQuantity > qty
              ? Value(qty)
              : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ));
      } else {
        // No local match → a line added on the server. Client-only fields start
        // empty (never printed, no ticket).
        //
        // If the order already holds this product and the kitchen has been told
        // about it, say so: the insert is about to put a second, unprinted copy
        // of the same food on the panel, which reads as "the kitchen still owes
        // this" when it does not. That is a real state — the backend can hold
        // genuine duplicates, e.g. from a push that timed out client-side after
        // the server had already applied it — but it is worth seeing rather
        // than discovering on a ticket.
        final printedTwin = (existingByKey[key] ?? const <OrderProduct>[])
            .where((r) => r.kdsPrintedQuantity > 0);
        if (printedTwin.isNotEmpty) {
          _logger.warning(
            'pullOrderDelta[$code] inserting server line $lineServerId '
            '(productId=$productId) while ${printedTwin.length} already-sent '
            'local line(s) of the same product exist — the panel will show it '
            'twice. Check the backend for duplicate lines on this order.',
          );
        }
        opId = await _database.into(_database.orderProducts).insert(
              OrderProductsCompanion(
                orderId: Value(orderId),
                productId: Value(productId),
                variantId: Value(variantId),
                quantity: Value(qty),
                unitaryPrice: Value(unitaryPrice),
                unitaryDiscount: Value(unitaryDiscount),
                unitaryTva: Value(unitaryTva),
                manualDiscount: Value(manualDiscount),
                note: Value(note),
                state: Value(state),
                planStartAt: Value(planStartAt),
                planEndAt: Value(planEndAt),
                planWaiterId: Value(planWaiterId),
                planResourceId: Value(planResourceId),
                serverId: Value(lineServerId),
                saleUomId: Value(saleUomId),
                // Line added on the server (a web edit): stamp the cost from
                // the local catalogue so it is not the one line in the order
                // with an unknown margin. The server does not send a cost.
                cost: await ProductCostResolver(_database)
                    .resolveValue(productId: productId, variantId: variantId),
                updatedAt: Value(DateTime.now()),
              ),
            );
      }

      // Components: only touch them when the server actually sent some. If it
      // omitted them, whatever is already attached to the line stays.
      final serverComponents =
          ((p['components'] ?? p['options'] as List?) ?? []).cast<Map<String, dynamic>>();
      if (serverComponents.isNotEmpty) {
        await (_database.delete(_database.orderProductComponents)
              ..where((c) => c.orderProductId.equals(opId)))
            .go();
        for (final c in serverComponents) {
          await _database.into(_database.orderProductComponents).insert(
                OrderProductComponentsCompanion(
                  orderProductId: Value(opId),
                  componentId: Value(
                      ((c['componentId'] ?? c['component_id']) as num).toInt()),
                  quantity: Value((c['quantity'] as num?)?.toInt() ?? 1),
                  price: Value((c['price'] as num?)?.toDouble() ?? 0.0),
                  isSpecial: Value(
                      (c['isSpecial'] ?? c['is_special']) as bool? ?? false),
                  name: Value(c['name'] as String?),
                  // A charge for a default the customer removed. Without this
                  // an imported order would bring it back as a plain option,
                  // and the next edit would send it as one — an ingredient
                  // nobody served, deducted from stock.
                  removalCharge: Value(
                      (c['removalCharge'] ?? c['removal_charge']) as bool? ??
                          false),
                  createdAt: Value(DateTime.now()),
                  updatedAt: Value(DateTime.now()),
                ),
                mode: InsertMode.insertOrReplace,
              );
        }
      }
    }

    // Any local lines the server no longer lists were removed remotely — drop
    // them and their components. Server order snapshots are complete, so an
    // unmatched local line means a genuine remote removal.
    //
    // Two things are NOT a remote removal, and deleting them loses food a
    // customer already ordered (and that the kitchen has already printed):
    //
    //   * a header-only delta ([hasProductsPayload] false) — the server sent
    //     no line list at all, so it cannot be asserting an empty one;
    //   * a line with `serverId == null` — the backend has never seen it, so
    //     it cannot have deleted it. That is every line added locally since
    //     the last successful push: the waiter app's add-product route, an
    //     offline POS edit, anything queued. Those must wait for their push,
    //     not be reconciled away by the pull that overtakes it.
    final unmatchedRows = !hasProductsPayload
        ? const <OrderProduct>[]
        : [
            for (final op in existingProductsList)
              if (!claimedRowIds.contains(op.id) && op.serverId != null) op,
          ];

    // Absence from a snapshot is NOT a removal, and a pull never subtracts on
    // its own inference.
    //
    // Orders are validated on this till and the backend receives them; it is
    // not an authority that can take away a line the POS may not even have
    // managed to send up yet. Deletion is something the server states
    // explicitly — `deletedAt` on the line (handled in the loop above) or on
    // the order ([_applyOrderTombstone]) — and that flag has been in the
    // payload all along. Inferring it from "missing from the list" instead is
    // what made a till whose push had timed out delete food the kitchen was
    // already cooking, silently, on the very next pull.
    //
    // So these rows are reported and kept. On a healthy till the list is empty;
    // anything here means the backend is behind this POS, which is a sync
    // problem to go and look at, not a licence to drop a line.
    if (unmatchedRows.isNotEmpty) {
      _logger.info(
        'pullOrderDelta[$code] keeping ${unmatchedRows.length} local line(s) '
        'the server did not list (absence is not a deletion): '
        '${[for (final op in unmatchedRows) '(id=${op.id} serverId=${op.serverId} '
            'productId=${op.productId} variantId=${op.variantId} '
            'qty=${op.quantity} kdsPrinted=${op.kdsPrintedQuantity} '
            'ticketId=${op.ticketId})'].join(', ')} '
        '— server sent ${products.length} line(s)',
      );
    }
    }); // end transaction

    _syncedOrderController.add(orderId);
  }

  /// Returns the status to persist, preventing a stale server response from
  /// regressing a locally-completed order back to an in-progress status.
  /// "Base" statuses are the standard OrderStatus enum values — any other value
  /// (e.g. 'COMPLETED', 'DONE', 'PAID') is treated as a terminal/custom status
  /// that must not be overwritten by a stale server in-flow status.
  String _resolveOrderStatus(String? serverStatus, String? localStatus) {
    const baseStatuses = {'ONHOLD', 'PENDING', 'PREPARING', 'READY', 'DELIVERED'};
    final server = serverStatus ?? localStatus ?? 'ONHOLD';
    if (localStatus != null &&
        !baseStatuses.contains(localStatus) &&
        baseStatuses.contains(server)) {
      return localStatus;
    }
    return server;
  }

  OrdersCompanion _orderCompanionFromDelta(
      Map<String, dynamic> item, Order? existing, DateTime? sessionZDay) {
    final now = DateTime.now();
    return OrdersCompanion(
      code: Value(item['code'] as String),
      status: Value(
          _resolveOrderStatus(item['status'] as String?, existing?.status)),
      type: Value(
          item['type'] as String? ?? existing?.type ?? 'DINE_IN'),
      priority: Value(
          (item['priority'] as num?)?.toInt() ??
              existing?.priority ??
              0),
      coupon: Value(item['coupon'] as String?),
      persons: Value(
          (item['persons'] as num?)?.toInt() ?? existing?.persons ?? 1),
      date: Value(
          _parseDateTime(item['date'] ?? item['createdAt']) ??
              existing?.date ??
              now),
      tableId: Value(
          ((item['tableId'] ?? item['table_id']) as num?)?.toInt()
          ?? existing?.tableId),
      source: Value(item['source'] as String?),
      // The courier code the server echoes back. Falls back to what we already
      // hold rather than nulling it: an older server that does not return the
      // field must not wipe a code we captured from the queue, or the reprint
      // loses it.
      externalOrderCode: Value(
          (item['externalOrderCode'] ?? item['external_order_code'])
                  as String? ??
              existing?.externalOrderCode),
      sourceId: Value(
          ((item['sourceId'] ?? item['source_id']) as num?)?.toInt()),
      discountPercentage: Value(
          ((item['discountPercentage'] ?? item['discount_percentage'])
                      as num?)
                  ?.toDouble() ??
              existing?.discountPercentage ??
              0.0),
      tip: Value((item['tip'] as num?)?.toDouble()),
      // Delivery fee from PosOrderResponse, preserved across re-syncs the same
      // way externalOrderCode is: fall back to what we already hold instead of
      // nulling it, so an older server that doesn't return the field can't
      // erase a fee this terminal recorded (or one that came off the queue).
      // A server-sent 0 still wins — it's a real value, not an absence.
      deliveryFee: Value(
          ((item['deliveryFee'] ?? item['delivery_fee']) as num?)?.toDouble() ??
              existing?.deliveryFee),
      // Payment position, straight from the server — it owns the arithmetic.
      // Falls back to what we hold so an older backend that omits the fields
      // cannot blank a balance the cashier is looking at.
      amountPaid: Value(
          ((item['amountPaid'] ?? item['amount_paid']) as num?)?.toDouble() ??
              existing?.amountPaid),
      balanceDue: Value(
          ((item['balanceDue'] ?? item['balance_due']) as num?)?.toDouble() ??
              existing?.balanceDue),
      paymentStatus: Value(
          (item['paymentStatus'] ?? item['payment_status']) as String? ??
              existing?.paymentStatus),
      createdBy: Value(
          ((item['createdBy'] ?? item['created_by']) as num?)?.toInt()
          ?? existing?.createdBy),
      takenBy: Value(
          ((item['takenBy'] ?? item['taken_by']) as num?)?.toInt()
          ?? existing?.takenBy),
      waiterId: Value(
          ((item['servedBy'] ?? item['waiterId'] ?? item['waiter_id'])
                  as num?)
              ?.toInt()),
      clientId: Value(
          ((item['clientId'] ?? item['client_id']) as num?)?.toInt()),
      commercialId: Value(
          ((item['commercialId'] ?? item['commercial_id']) as num?)
              ?.toInt()),
      note: Value(item['note'] as String?),
      address: Value(item['address'] as String?),
      cancellationReason: Value(
          (item['cancellationReason'] ?? item['cancellation_reason'])
              as String?),
      sessionId: Value(
          ((item['sessionId'] ?? item['session_id']) as num?)?.toInt()
          ?? existing?.sessionId),
      zDay: Value(() {
        // Precedence:
        //  1. the server's zDay, when it echoes one;
        //  2. the z_day already on the local row;
        //  3. the order's own SESSION;
        //  4. the order's date, as a last resort for a remote order that
        //     names no session we know.
        //
        // (2) is the one that matters and the one that was missing. Every
        // neighbouring field here falls back to `existing` — this did not, so
        // on a server that does not echo zDay (it is in no response contract
        // we publish) the branch below ran on every delta and overwrote a
        // correct z_day with the CALENDAR day of the order's date. An order
        // rung up at 00:30 inside a 20:00 shift was stamped correctly at
        // save, pushed correctly once, then silently moved to the next day by
        // the first pull that touched it — and re-pushed there, which is how
        // an order ends up reported on the day after its own shift.
        //
        // The order's date is no longer reachable for anything we already
        // hold — it is the moment the order was typed, which is precisely
        // what a z_day must not be.
        final raw = item['zDay'] ?? item['z_day'];
        if (raw != null) return _parseDateTime(raw);
        final known = existing?.zDay ?? sessionZDay;
        if (known != null) return known;
        final orderDate = _parseDateTime(item['date'] ?? item['createdAt']) ??
            existing?.date ??
            now;
        return ZDayResolver.dayOf(orderDate);
      }()),
      createdAt: Value(
          _parseDateTime(item['createdAt'] ?? item['created_at']) ??
              existing?.createdAt ??
              now),
      updatedAt: Value(
          _parseDateTime(item['updatedAt'] ?? item['updated_at']) ?? now),
      isSynced: const Value(true),
    );
  }

  Future<void> _applyOrderTombstone(String code) async {
    final existing = await (_database.select(_database.orders)
          ..where((o) => o.code.equals(code)))
        .getSingleOrNull();
    if (existing == null) return;

    final orderId = existing.id;
    // Cascade delete atomically — a crash mid-cascade would otherwise leave an
    // orphaned order (e.g. tickets gone but the order row still present).
    await _database.transaction(() async {
      await (_database.delete(_database.tickets)
            ..where((t) => t.orderId.equals(orderId)))
          .go();
      final opIds = await (_database.select(_database.orderProducts)
            ..where((op) => op.orderId.equals(orderId)))
          .map((op) => op.id)
          .get();
      if (opIds.isNotEmpty) {
        await (_database.delete(_database.orderProductComponents)
              ..where((c) => c.orderProductId.isIn(opIds)))
            .go();
      }
      await (_database.delete(_database.orderProducts)
            ..where((op) => op.orderId.equals(orderId)))
          .go();
      await (_database.delete(_database.orders)
            ..where((o) => o.id.equals(orderId)))
          .go();
    });

    _logger.info('pullOrderDeltas: tombstone order code=$code');
  }

  Future<void> _applyPaymentDelta(
      Map<String, dynamic> item, int orderId) async {
    final ticketNum = (item['num'] as String?) ?? '';
    final existing = await (_database.select(_database.tickets)
          ..where((t) => t.orderId.equals(orderId) & t.num.equals(ticketNum)))
        .getSingleOrNull();

    final sessionId =
        ((item['sessionId'] ?? item['session_id']) as num?)?.toInt();

    // z_day precedence:
    //  1. server-sent zDay (authoritative),
    //  2. the session's Z opening day (all sessions in a Z share one z_day),
    //     falling back to the session's own opening day,
    //  3. the ticket date (last resort, when no session row is available).
    DateTime? zDay;
    final rawZ = item['zDay'] ?? item['z_day'];
    if (rawZ != null) {
      zDay = _parseDateTime(rawZ);
    } else if (sessionId != null) {
      final s = await (_database.select(_database.cashSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingleOrNull();
      if (s != null) {
        DateTime? d;
        if (s.zId != null) {
          final z = await (_database.select(_database.zs)
                ..where((t) => t.id.equals(s.zId!)))
              .getSingleOrNull();
          if (z != null) {
            d = DateTime(z.startedAt.year, z.startedAt.month, z.startedAt.day);
          }
        }
        zDay = d ??
            DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day);
      }
    }
    if (zDay == null) {
      final ticketDate =
          _parseDateTime(item['date'] ?? item['createdAt']) ?? DateTime.now();
      zDay = DateTime(ticketDate.year, ticketDate.month, ticketDate.day);
    }

    final companion = TicketsCompanion(
      num: Value(ticketNum),
      date: Value(_parseDateTime(item['date'] ?? item['createdAt']) ??
          DateTime.now()),
      orderId: Value(orderId),
      sessionId: Value(sessionId),
      paymentMethod: Value(
          (item['paymentMethod'] ?? item['payment_method']) as String? ??
              'CASH'),
      // Preserve existing non-zero amount when server sends 0 or null — the
      // ticket may have been created locally before the server received it.
      amount: Value(() {
        final serverAmount = (item['amount'] as num?)?.toDouble() ?? 0.0;
        return serverAmount > 0 ? serverAmount : (existing?.amount ?? 0.0);
      }()),
      isPaid:
          Value((item['isPaid'] ?? item['is_paid']) as bool? ?? true),
      isCancelled: Value(
          (item['isCancelled'] ?? item['is_cancelled']) as bool? ?? false),
      zDay: Value(zDay),
      isSynced: const Value(true),
    );

    if (existing != null) {
      await (_database.update(_database.tickets)
            ..where((t) => t.id.equals(existing.id)))
          .write(companion);
    } else {
      await _database
          .into(_database.tickets)
          .insert(companion, mode: InsertMode.insertOrIgnore);
    }
  }

  // ── Sync-inspector helpers (read-only, no DB side effects) ───────────────

  /// Returns the current cursor / last-sync-at / last-error strings for the
  /// inspector dialog. All values may be null when no sync has run yet.
  Future<Map<String, String?>> getDeltaSyncMeta(SharedPreferences prefs) async {
    return {
      'ordersCursor':    prefs.getString(_kOrdersCursor),
      'paymentsCursor':  prefs.getString(_kPaymentsCursor),
      'ordersLastSync':  prefs.getString(_kOrdersLastSyncAt),
      'paymentsLastSync': prefs.getString(_kPaymentsLastSyncAt),
      'lastError':       prefs.getString(_kLastDeltaError),
    };
  }

  Future<void> resetOrdersCursor(SharedPreferences prefs) async {
    await prefs.remove(_kOrdersCursor);
    _logger.info('pullOrderDeltas: cursor reset');
  }

  Future<void> resetPaymentsCursor(SharedPreferences prefs) async {
    await prefs.remove(_kPaymentsCursor);
    _logger.info('pullPaymentDeltas: cursor reset');
  }
}


import 'package:drift/drift.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/pending_operations_service.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:convert';
import 'dart:io';

/// Data Sync Service for fetching data from API and storing in local database
class DataSyncService {
  final AppDatabase _database;
  final ApiService _apiService;
  late final PendingOperationsService _pendingOpsService;
  final _logger = Logger.instance;

  DataSyncService(this._database, this._apiService) {
    _pendingOpsService = PendingOperationsService(_database);
  }

  /// Callback for progress updates
  Function(String message, double progress)? onProgress;

  /// Clear only master data (not transactional data like orders, tickets, sessions).
  ///
  /// Server-authoritative tables (users, products, categories, waiters,
  /// commercials, etc.) are wiped here and repopulated by the subsequent
  /// fetch calls — that way **rows the admin deleted on the backend
  /// actually disappear from the device**. Tables that have a local-create
  /// flow (customers, with isSynced=false rows that haven't been uploaded
  /// yet) are deliberately NOT wiped here; their upload path runs first.
  Future<void> clearMasterData() async {
    // Delete in reverse order of dependencies to avoid foreign key issues.
    await _database.delete(_database.kDSs).go();
    await _database.delete(_database.kiosks).go();
    // waiterAreas references waiters AND areas — drop before either.
    await _database.delete(_database.waiterAreas).go();
    await _database.delete(_database.areaTables).go();
    await _database.delete(_database.areas).go();
    await _database.delete(_database.productComponents).go();
    await _database.delete(_database.variantAttributeValues).go();
    await _database.delete(_database.productVariants).go();
    await _database.delete(_database.products).go();
    await _database.delete(_database.components).go();
    await _database.delete(_database.componentGroups).go();
    await _database.delete(_database.stations).go();
    await _database.delete(_database.categories).go();
    // Waiters + commercials are purely server-authoritative — wipe them so
    // backend deletes propagate to the device on the next sync.
    await _database.delete(_database.commercials).go();
    await _database.delete(_database.waiters).go();
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
    await _database.delete(_database.tickets).go();
    await _database.delete(_database.orderProductComponents).go();
    await _database.delete(_database.orderProducts).go();
    // orderLogs and notes reference orders — must go before orders
    await _database.delete(_database.orderLogs).go();
    await _database.delete(_database.notes).go();
    await _database.delete(_database.orders).go();
    await _database.delete(_database.transactions).go();
    await _database.delete(_database.payments).go();
    await _database.delete(_database.cashSessions).go();
    await _database.delete(_database.customers).go();
    await _database.delete(_database.commercials).go();
    await _database.delete(_database.pendingSyncOperations).go();
    // waiterAreas references areas (cleared in clearMasterData) — must go first
    await _database.delete(_database.waiterAreas).go();
    await _database.delete(_database.waiters).go();
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
  ///   Phase 2 (single transaction): snapshot locally-tracked user
  ///     fields (`lastLogin`, `displayName`) that the server doesn't
  ///     send, run `clearMasterData()` + retention purge, then persist
  ///     all the cached lists. Wrapped in one transaction so the swap
  ///     is atomic — if anything in phase 2 throws, drift rolls back
  ///     and the old data is still there.
  ///
  /// This replaces the old pattern that cleared and re-fetched inside
  /// one long transaction — which held DB locks for the whole network
  /// round-trip and showed an empty UI during the brief window between
  /// clear and refetch.
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

      onProgress?.call('Fetching component groups...', 0.42);
      final componentGroups = await _apiService.fetchComponentGroups();

      onProgress?.call('Fetching components...', 0.5);
      final components = await _apiService.fetchComponents();

      onProgress?.call('Fetching product components...', 0.58);
      final productComponents = await _apiService.fetchProductComponents();

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

      // ── Phase 2: atomic swap (snapshot → clear → persist) ───────────
      onProgress?.call('Updating local data...', 0.95);
      await _database.transaction(() async {
        // Snapshot 1: locally-tracked user fields. Server doesn't send
        // lastLogin / displayName, so we'd lose them otherwise.
        final existingUsers = await _database.select(_database.users).get();
        final existingUsersById = {for (final u in existingUsers) u.id: u};

        // Snapshot 2: which table is currently holding which order. The
        // API only sends static table data (name, capacity, area); the
        // runtime `area_tables.orderId` mapping is set locally by the
        // cashier (Hold / Pay flows) and would otherwise be wiped when
        // `clearMasterData` deletes the table rows. Lives in memory until
        // we've reinserted the new table set and can re-apply it.
        final tableOrderSnapshot = await _snapshotTableOrders();

        await clearMasterData();

        if (dataRetentionDays != null && dataRetentionDays > 0) {
          await clearOldSyncedData(dataRetentionDays);
        }

        // Persist in FK-respecting order. Each helper is a pure DB
        // writer: it doesn't touch the network and can be re-run safely
        // on a partial failure (drift rolls back the transaction on any
        // throw).
        await _persistUsers(users, existingUsersById);
        await _persistCategories(categories);
        await _persistStations(stations);
        await _persistProducts(products);
        await _persistVariants(variants);
        await _persistComponentGroups(componentGroups);
        await _persistComponents(components);
        await _persistProductComponents(productComponents);
        await _persistAreas(areas);
        await _persistTables(tables);
        // Restore the table → order assignments now that the new table
        // rows exist. Done AFTER `_persistTables` so the update has
        // something to write to. Skips entries whose order was purged by
        // the retention pass above, or whose table id no longer exists
        // in the server's response.
        await _restoreTableOrders(tableOrderSnapshot);
        await _persistCommercials(commercials);
        await _persistCustomers(customers);
        await _persistWaiters(waiters);
      });

      onProgress?.call('Sync complete!', 1.0);
    } catch (e) {
      _logger.error('Sync failed: $e');
      throw Exception('Sync failed: $e');
    }
  }

  /// Writes the previously-fetched users into the local DB. Uses the
  /// snapshot the caller took **before clearMasterData ran** so locally-
  /// tracked fields (`lastLogin`, `displayName`) survive the swap.
  Future<void> _persistUsers(
    List<Map<String, dynamic>> users,
    Map<int, User> existingById,
  ) async {
    for (final user in users) {
      final int? id = user['id'];
      final prior = id != null ? existingById[id] : null;

      final createdAt = _parseDateTime(user['createdAt'] ?? user['created_at']);
      final updatedAt = _parseDateTime(user['updatedAt'] ?? user['updated_at']);
      final lastLogin =
          _parseDateTime(user['lastLogin'] ?? user['last_login']) ?? prior?.lastLogin;

      // Preserve a locally-set displayName when the server doesn't send one
      // (typical case: the cashier edits their nickname in Profile, and the
      // backend has no concept of display names yet). Same pattern as
      // `lastLogin` above.
      final serverDisplayName =
          user['displayName'] ?? user['display_name'];
      final displayName = (serverDisplayName is String &&
              serverDisplayName.isNotEmpty)
          ? serverDisplayName
          : prior?.displayName;

      await _database.into(_database.users).insert(
        UsersCompanion.insert(
          id: Value(user['id']),
          username: user['username'],
          password: user['password'] ?? '',
          firstName: user['firstName'] ?? '',
          lastName: user['lastName'] ?? '',
          type: user['type'] ?? 'cashier',
          imageUrl: Value(user['imageUrl']),
          permissions: Value(_normalizePermissions(user['permissions'])),
          displayName: Value(displayName),
          // Only override the column defaults when the server actually sends a value
          createdAt: createdAt != null ? Value(createdAt) : const Value.absent(),
          updatedAt: updatedAt != null ? Value(updatedAt) : const Value.absent(),
          lastLogin: Value(lastLogin),
        ),
        mode: InsertMode.insertOrReplace,
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
      await _database.into(_database.categories).insert(
        CategoriesCompanion.insert(
          id: Value(category['id']),
          name: category['name'],
          imageUrl: Value(category['imageUrl']),
          description: Value(category['description']),
          displayOrder: Value(category['displayOrder'] ?? 0),
          isActive: Value(category['isActive'] ?? true),
          color: Value(category['color']),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _persistStations(
      List<Map<String, dynamic>> stations) async {
    for (final station in stations) {
      await _database.into(_database.stations).insert(
        StationsCompanion.insert(
          id: Value(station['id']),
          name: station['name'],
          description: Value(station['description']),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _persistProducts(
      List<Map<String, dynamic>> products) async {
    for (final product in products) {
      await _database.into(_database.products).insert(
        ProductsCompanion.insert(
          id: Value(product['id']),
          name: product['name'],
          barcode: Value(product['barcode']),
          imageUrl: Value(product['imageUrl']),
          description: Value(product['description']),
          price: (product['price'] as num).toDouble(),
          uom: Value(product['uom'] ?? 'unit'),
          categoryId: Value(product['categoryId']),
          stationId: Value(product['stationId']),
          tvaAmount: Value((product['tvaAmount'] as num?)?.toDouble() ?? 0.0),
          discountAmount: Value((product['discountAmount'] as num?)?.toDouble() ?? 0.0),
          finalPrice: (product['finalPrice'] as num).toDouble(),
          isActive: Value(product['isActive'] ?? true),
          isVariant: Value(product['isVariant'] ?? false),
          isPlannable: Value(product['isPlannable'] ?? false),
          planDurationMinutes: Value(product['planDurationMinutes'] as int?),
          color: Value(product['color']),
          // Scale / weighed-product fields — null when absent in API response.
          mbwCode: Value(product['mbwCode'] as String?),
          pricePerKg: Value(product['pricePerKg'] as int?),
        ),
        mode: InsertMode.insertOrReplace,
      );

      // Sync extra stations (multi-station products). The primary `stationId`
      // above keeps single-station behavior; these are additional stations.
      final productId = product['id'] as int;
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
    }
  }

  Future<void> _persistVariants(
      List<Map<String, dynamic>> variants) async {
    for (final variant in variants) {
      // Insert variant
      await _database.into(_database.productVariants).insert(
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
        ),
        mode: InsertMode.insertOrReplace,
      );

      // Insert attribute values for this variant
      final attributeValues = variant['attributeValues'] as List<dynamic>? ?? [];
      for (final av in attributeValues) {
        await _database.into(_database.variantAttributeValues).insert(
          VariantAttributeValuesCompanion.insert(
            variantId: variant['id'],
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
      await _database.into(_database.componentGroups).insert(
        ComponentGroupsCompanion.insert(
          id: Value(group['id']),
          name: group['name'],
          description: Value(group['description']),
          displayOrder: Value(group['displayOrder'] ?? 0),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _persistComponents(
      List<Map<String, dynamic>> components) async {
    for (final component in components) {
      await _database.into(_database.components).insert(
        ComponentsCompanion.insert(
          id: Value(component['id']),
          name: component['name'],
          price: Value((component['price'] as num?)?.toDouble() ?? 0.0),
          componentGroupId: Value(component['componentGroupId']),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _persistProductComponents(
      List<Map<String, dynamic>> productComponents) async {
    for (final pc in productComponents) {
      await _database.into(_database.productComponents).insert(
        ProductComponentsCompanion.insert(
          productId: pc['productId'],
          componentId: pc['componentId'],
          defaultPrice: Value((pc['defaultPrice'] as num?)?.toDouble() ?? 0.0),
          defaultQuantity: Value(pc['defaultQuantity'] ?? 0),

          isRequired: Value(pc['isRequired'] ?? false),
          minQuantity: Value(pc['minQuantity'] ?? 0),
          maxQuantity: Value(pc['maxQuantity'] ?? 10),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _persistAreas(
      List<Map<String, dynamic>> areas) async {
    for (final area in areas) {
      await _database.into(_database.areas).insert(
        AreasCompanion.insert(
          id: Value(area['id']),
          name: area['name'],
          description: Value(area['description']),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  /// Read the current `tableId → orderId` mapping into memory. Only rows
  /// with an active order are captured — empty tables don't need to be
  /// "restored" since the new table set starts empty anyway.
  Future<Map<int, int>> _snapshotTableOrders() async {
    final rows = await (_database.select(_database.areaTables)
          ..where((t) => t.orderId.isNotNull()))
        .get();
    return {for (final r in rows) r.id: r.orderId!};
  }

  /// Re-apply a `tableId → orderId` mapping captured by
  /// [_snapshotTableOrders] before the table rows were wiped.
  ///
  /// Two guards:
  ///   - If the new (server-returned) table set doesn't include a snapshot
  ///     id, the `UPDATE ... WHERE id = ?` simply matches zero rows and
  ///     the entry is silently dropped — the table doesn't exist anymore.
  ///   - If the referenced order was purged by the retention pass that
  ///     ran earlier in the same transaction, skip the restore so we
  ///     don't reattach a dangling FK.
  Future<void> _restoreTableOrders(Map<int, int> mapping) async {
    if (mapping.isEmpty) return;
    final orderIds = mapping.values.toSet().toList();
    final survivors = await (_database.select(_database.orders)
          ..where((o) => o.id.isIn(orderIds)))
        .get();
    final survivingIds = survivors.map((o) => o.id).toSet();

    for (final entry in mapping.entries) {
      if (!survivingIds.contains(entry.value)) continue;
      await (_database.update(_database.areaTables)
            ..where((t) => t.id.equals(entry.key)))
          .write(AreaTablesCompanion(orderId: Value(entry.value)));
    }
  }

  Future<void> _persistTables(
      List<Map<String, dynamic>> tables) async {
    for (final table in tables) {
      await _database.into(_database.areaTables).insert(
        AreaTablesCompanion.insert(
          id: Value(table['id']),
          name: table['name'],
          capacity: Value(table['capacity'] ?? 4),
          areaId: Value(table['areaId']),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _persistCommercials(
      List<Map<String, dynamic>> commercials) async {
    for (final commercial in commercials) {
      await _database.into(_database.commercials).insert(
        CommercialsCompanion.insert(
          id: Value(commercial['id']),
          firstName: commercial['firstName'],
          lastName: commercial['lastName'],
          cin: commercial['cin'],
        ),
        mode: InsertMode.insertOrReplace,
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
      await _database.into(_database.customers).insert(
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
        mode: InsertMode.insertOrReplace,
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

  Future<void> _persistWaiters(
      List<Map<String, dynamic>> waiters) async {
    // No per-waiter clear of `waiter_areas` needed — clearMasterData
    // already wiped that table at the start of the transaction.
    for (final waiter in waiters) {
      // `pin` is the credential the waiter app uses to authenticate against
      // the local POS — see `_waiterLogin` in server_service.dart. Stored
      // as-is (plaintext) since the LAN-only server has no separate hashing
      // requirement; uniqueness is enforced by the partial index added at
      // schemaVersion 18.
      await _database.into(_database.waiters).insert(
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
        mode: InsertMode.insertOrReplace,
      );

      // Insert waiter-area assignments
      final areaIds = waiter['areaIds'] as List<dynamic>? ?? [];
      for (final areaId in areaIds) {
        await _database.into(_database.waiterAreas).insert(
          WaiterAreasCompanion.insert(
            waiterId: waiter['id'],
            areaId: areaId as int,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }
    }
  }

  // ============ UPLOAD LOCAL DATA TO SERVER ============

  /// Build products list for sync, merging order-level discount percentage
  /// into each product's manualDiscount proportionally.
  ///
  /// Example: Product costs $10, existing manualDiscount $5, order discount 50%.
  /// Effective price after existing discounts = $10 - $5 = $5.
  /// Order discount on that = $5 * 50% = $2.50.
  /// Final manualDiscount sent to server = $5 + $2.50 = $7.50.
  Future<List<Map<String, dynamic>>> _buildProductsListForSync(
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

    final productDataList = <Map<String, dynamic>>[];
    final effectivePrices = <double>[];

    for (final product in orderProducts) {
      final productComponents = componentsByProductId[product.id] ?? [];

      final componentsList = productComponents.map((comp) => {
        'componentId': comp.componentId,
        'quantity': comp.quantity,
        'price': comp.price,
        'isSpecial': comp.isSpecial,
      }).toList();

      double componentTotal = 0.0;
      for (final comp in productComponents) {
        componentTotal += comp.price * comp.quantity;
      }

      final effectivePerItem = product.unitaryPrice + componentTotal - product.unitaryDiscount - product.manualDiscount;
      final effectiveTotal = effectivePerItem * product.quantity;
      effectivePrices.add(effectiveTotal > 0 ? effectiveTotal : 0.0);

      productDataList.add({
        'productId': product.productId,
        'variantId': product.variantId,
        'quantity': product.quantity,
        'unitaryPrice': product.unitaryPrice,
        'unitaryDiscount': product.unitaryDiscount,
        'unitaryTva': product.unitaryTva,
        'manualDiscount': product.manualDiscount,
        'note': product.note,
        'state': product.state,
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
          final qty = productDataList[i]['quantity'] as int;
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
      final productsList = await _buildProductsListForSync(orderProducts, order.discountPercentage);

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
        'date': t.date.toIso8601String(),
        'createdAt': t.date.toIso8601String(),
      });
    }

    return ticketsList;
  }

  /// Get all ended sessions that need to be synced
  Future<List<Map<String, dynamic>>> getSessionsForSync() async {
    final sessions = await (_database.select(_database.cashSessions)
      ..where((s) => s.status.equals('ended') & s.isSynced.equals(false)))
      .get();
    return sessions.map((s) => {
      'id': s.id,
      'code': s.code,
      'cashierId': s.cashierId,
      'moneyAtStart': s.moneyAtStart,
      'moneyAtEnd': s.moneyAtEnd,
      'status': s.status,
      'startedAt': s.startedAt.toIso8601String(),
      'endedAt': s.endedAt?.toIso8601String(),
      'pausedAt': s.pausedAt?.toIso8601String(),
    }).toList();
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

  /// Mark tickets as synced
  Future<void> markTicketsAsSynced(List<int> ticketIds) async {
    if (ticketIds.isEmpty) return;
    await (_database.update(_database.tickets)
      ..where((t) => t.id.isIn(ticketIds)))
      .write(const TicketsCompanion(isSynced: Value(true)));
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
        await _apiService.syncOrders(orders);
        await markOrdersAsSynced(orders.map((o) => o['id'] as int).toList());
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

      // Build session data
      final sessionData = {
        'code': session.code,
        'cashierId': session.cashierId,
        'moneyAtStart': session.moneyAtStart,
        'moneyAtEnd': session.moneyAtEnd,
        'status': session.status,
        'startedAt': session.startedAt.toIso8601String(),
        'endedAt': session.endedAt?.toIso8601String(),
        'pausedAt': session.pausedAt?.toIso8601String(),
      };

      // Sync to server using single session endpoint (PUT to create/update)
      await _apiService.syncSingleSession(session.code, sessionData);

      // Mark as synced
      await markSessionsAsSynced([sessionId]);

      _logger.info('Successfully synced session code=${session.code}');
      return true;
    } catch (e) {
      _logger.error('Error syncing single session: $e');
      return false;
    }
  }

  /// Sync a single order immediately (for online auto-sync)
  Future<bool> syncSingleOrder(int orderId) async {
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
      final productsList = await _buildProductsListForSync(orderProducts, order.discountPercentage);

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
        'note': order.note,
        'address': order.address,
        'cancellationReason': order.cancellationReason,
        'products': productsList,
        'createdAt': order.createdAt.toIso8601String(),
        'updatedAt': order.updatedAt.toIso8601String(),
      };

      // Sync to server using single order endpoint (PUT to create/update)
      await _apiService.syncSingleOrder(order.code, orderData);

      // Mark as synced
      await markOrdersAsSynced([orderId]);

      _logger.info('Successfully synced order code=${order.code}');
      return true;
    } catch (e) {
      _logger.error('Error syncing single order: $e');
      return false;
    }
  }

  /// Sync tickets for a single order (used by auto-sync when online)
  Future<bool> syncTicketsForOrder(int orderId) async {
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

      await _apiService.syncTickets(payload);
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
        await _apiService.syncOrders(batch);
        // Bulk succeeded – mark all as synced
        final syncedIds = batch.map((o) => o['id'] as int).toList();
        await markOrdersAsSynced(syncedIds);
        return batch.length;
      } catch (bulkError) {
        // Bulk failed – fall back to individual sync so only confirmed
        // orders get marked as synced (prevents phantom synced orders)
        _logger.warning('Bulk order sync failed, falling back to individual sync: $bulkError');
        int successCount = 0;
        for (final orderMap in batch) {
          try {
            final orderId = orderMap['id'] as int;
            final success = await syncSingleOrder(orderId);
            if (success) successCount++;
          } catch (e) {
            _logger.error('Individual order sync failed for order #${orderMap['id']}: $e');
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
      // Get sessions for sync
      final sessions = await getSessionsForSync();

      if (sessions.isEmpty) {
        return 0;
      }

      // Take only the specified batch size
      final batch = sessions.take(batchSize).toList();

      try {
        // Sync the batch
        await _apiService.syncSessions(batch);

        // Mark as synced only after confirmed success
        final syncedIds = batch.map((s) => s['id'] as int).toList();
        await markSessionsAsSynced(syncedIds);

        return batch.length;
      } catch (bulkError) {
        _logger.warning('Bulk session sync failed, falling back to individual sync: $bulkError');
        int successCount = 0;
        for (final session in batch) {
          try {
            final sessionCode = session['code'] as String;
            await _apiService.syncSingleSession(sessionCode, session);
            await markSessionsAsSynced([session['id'] as int]);
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
    final unsyncedOrders = await (_database.select(_database.orders)
      ..where((o) => o.isSynced.equals(false)))
      .get();

    final unsyncedTickets = await (_database.select(_database.tickets)
      ..where((t) => t.isSynced.equals(false)))
      .get();

    final unsyncedSessions = await (_database.select(_database.cashSessions)
      ..where((s) => s.status.equals('ended') & s.isSynced.equals(false)))
      .get();

    final unsyncedCustomers = await (_database.select(_database.customers)
      ..where((c) => c.isSynced.equals(false)))
      .get();

    return {
      'orders': unsyncedOrders.length,
      'tickets': unsyncedTickets.length,
      'sessions': unsyncedSessions.length,
      'customers': unsyncedCustomers.length,
    };
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
}


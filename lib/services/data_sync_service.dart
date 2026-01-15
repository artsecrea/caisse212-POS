import 'package:drift/drift.dart';
import 'package:posecrea/data/database/app_database.dart';
import 'package:posecrea/services/api_service.dart';

/// Data Sync Service for fetching data from API and storing in local database
class DataSyncService {
  final AppDatabase _database;
  final ApiService _apiService;

  DataSyncService(this._database, this._apiService);

  /// Callback for progress updates
  Function(String message, double progress)? onProgress;

  /// Clear all data from the database
  Future<void> clearAllData() async {
    // Delete in order to respect foreign key constraints
    await _database.delete(_database.tickets).go();
    await _database.delete(_database.orderProductComponents).go();
    await _database.delete(_database.orderProducts).go();
    await _database.delete(_database.orders).go();
    await _database.delete(_database.transactions).go();
    await _database.delete(_database.payments).go();
    await _database.delete(_database.cashSessions).go();
    await _database.delete(_database.customers).go();
    await _database.delete(_database.commercials).go();
    await _database.delete(_database.kDSs).go();
    await _database.delete(_database.kiosks).go();
    await _database.delete(_database.productComponents).go();
    await _database.delete(_database.componentGroups).go();
    await _database.delete(_database.components).go();
    await _database.delete(_database.areaTables).go();
    await _database.delete(_database.areas).go();
    await _database.delete(_database.stations).go();
    await _database.delete(_database.products).go();
    await _database.delete(_database.categories).go();
    await _database.delete(_database.users).go();
  }

  /// Sync all data from the server
  Future<void> syncAllData() async {
    try {
      // Clear existing data first
      onProgress?.call('Clearing existing data...', 0.0);
      await clearAllData();

      // Sync in order to respect foreign key constraints
      onProgress?.call('Fetching users...', 0.1);
      await _syncUsers();

      onProgress?.call('Fetching categories...', 0.2);
      await _syncCategories();

      onProgress?.call('Fetching stations...', 0.25);
      await _syncStations();

      onProgress?.call('Fetching products...', 0.3);
      await _syncProducts();

      onProgress?.call('Fetching component groups...', 0.4);
      await _syncComponentGroups();

      onProgress?.call('Fetching components...', 0.5);
      await _syncComponents();

      onProgress?.call('Fetching product components...', 0.6);
      await _syncProductComponents();

      onProgress?.call('Fetching areas...', 0.7);
      await _syncAreas();

      onProgress?.call('Fetching tables...', 0.75);
      await _syncTables();

      onProgress?.call('Fetching commercials...', 0.8);
      await _syncCommercials();

      onProgress?.call('Fetching customers...', 0.9);
      await _syncCustomers();

      onProgress?.call('Sync complete!', 1.0);
    } catch (e) {
      throw Exception('Sync failed: $e');
    }
  }

  Future<void> _syncUsers() async {
    final users = await _apiService.fetchUsers();
    for (final user in users) {
      await _database.into(_database.users).insert(
        UsersCompanion.insert(
          id: Value(user['id']),
          username: user['username'],
          password: user['password'] ?? '',
          firstName: user['firstName'] ?? '',
          lastName: user['lastName'] ?? '',
          type: user['type'] ?? 'cashier',
          imageUrl: Value(user['imageUrl']),
          permissions: Value(user['permissions']),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _syncCategories() async {
    final categories = await _apiService.fetchCategories();
    for (final category in categories) {
      await _database.into(_database.categories).insert(
        CategoriesCompanion.insert(
          id: Value(category['id']),
          name: category['name'],
          imageUrl: Value(category['imageUrl']),
          description: Value(category['description']),
          displayOrder: Value(category['displayOrder'] ?? 0),
          isActive: Value(category['isActive'] ?? true),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _syncStations() async {
    final stations = await _apiService.fetchStations();
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

  Future<void> _syncProducts() async {
    final products = await _apiService.fetchProducts();
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
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _syncComponentGroups() async {
    final groups = await _apiService.fetchComponentGroups();
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

  Future<void> _syncComponents() async {
    final components = await _apiService.fetchComponents();
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

  Future<void> _syncProductComponents() async {
    final productComponents = await _apiService.fetchProductComponents();
    for (final pc in productComponents) {
      await _database.into(_database.productComponents).insert(
        ProductComponentsCompanion.insert(
          productId: pc['productId'],
          componentId: pc['componentId'],
          defaultPrice: Value((pc['defaultPrice'] as num?)?.toDouble() ?? 0.0),
          isRequired: Value(pc['isRequired'] ?? false),
          minQuantity: Value(pc['minQuantity'] ?? 0),
          maxQuantity: Value(pc['maxQuantity'] ?? 10),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _syncAreas() async {
    final areas = await _apiService.fetchAreas();
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

  Future<void> _syncTables() async {
    final tables = await _apiService.fetchTables();
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

  Future<void> _syncCommercials() async {
    final commercials = await _apiService.fetchCommercials();
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

  Future<void> _syncCustomers() async {
    final customers = await _apiService.fetchCustomers();
    for (final customer in customers) {
      await _database.into(_database.customers).insert(
        CustomersCompanion.insert(
          id: Value(customer['id']),
          firstName: customer['firstName'],
          lastName: customer['lastName'],
          phone: Value(customer['phone']),
          email: Value(customer['email']),
          isSynced: const Value(true), // Data from server is already synced
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  // ============ UPLOAD LOCAL DATA TO SERVER ============

  /// Get all completed orders that need to be synced (not yet synced)
  Future<List<Map<String, dynamic>>> getOrdersForSync() async {
    final orders = await (_database.select(_database.orders)
      ..where((o) => o.status.equals('COMPLETED') & o.isSynced.equals(false)))
      .get();
    return orders.map((o) => {
      'id': o.id,
      'code': o.code,
      'status': o.status,
      'type': o.type,
      'priority': o.priority,
      'coupon': o.coupon,
      'persons': o.persons,
      'tableId': o.tableId,
      'clientId': o.clientId,
      'commercialId': o.commercialId,
      'discountPercentage': o.discountPercentage,
      'note': o.note,
      'createdAt': o.createdAt.toIso8601String(),
      'updatedAt': o.updatedAt.toIso8601String(),
    }).toList();
  }

  /// Get all tickets for completed, synced orders that haven't been synced yet
  Future<List<Map<String, dynamic>>> getTicketsForSync() async {
    // Get synced order IDs
    final syncedOrders = await (_database.select(_database.orders)
      ..where((o) => o.isSynced.equals(true)))
      .get();
    final syncedOrderIds = syncedOrders.map((o) => o.id).toSet();

    // Get tickets that belong to synced orders but aren't synced yet
    final tickets = await (_database.select(_database.tickets)
      ..where((t) => t.isSynced.equals(false)))
      .get();

    // Filter tickets for synced orders only
    final ticketsToSync = tickets.where((t) => syncedOrderIds.contains(t.orderId)).toList();

    return ticketsToSync.map((t) => {
      'id': t.id,
      'num': t.num,
      'orderId': t.orderId,
      'sessionId': t.sessionId,
      'paymentMethod': t.paymentMethod,
      'amount': t.amount,
      'isPaid': t.isPaid,
      'printCount': t.printCount,
      'date': t.date.toIso8601String(),
      'createdAt': t.createdAt.toIso8601String(),
    }).toList();
  }

  /// Get all ended sessions that need to be synced
  Future<List<Map<String, dynamic>>> getSessionsForSync() async {
    final sessions = await (_database.select(_database.cashSessions)
      ..where((s) => s.status.equals('ended') & s.isSynced.equals(false)))
      .get();
    return sessions.map((s) => {
      'id': s.id,
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
      'email': c.email,
      'createdAt': c.createdAt.toIso8601String(),
    }).toList();
  }

  /// Mark orders as synced
  Future<void> markOrdersAsSynced(List<int> orderIds) async {
    for (final id in orderIds) {
      await (_database.update(_database.orders)
        ..where((o) => o.id.equals(id)))
        .write(const OrdersCompanion(isSynced: Value(true)));
    }
  }

  /// Mark tickets as synced
  Future<void> markTicketsAsSynced(List<int> ticketIds) async {
    for (final id in ticketIds) {
      await (_database.update(_database.tickets)
        ..where((t) => t.id.equals(id)))
        .write(const TicketsCompanion(isSynced: Value(true)));
    }
  }

  /// Mark sessions as synced
  Future<void> markSessionsAsSynced(List<int> sessionIds) async {
    for (final id in sessionIds) {
      await (_database.update(_database.cashSessions)
        ..where((s) => s.id.equals(id)))
        .write(const CashSessionsCompanion(isSynced: Value(true)));
    }
  }

  /// Mark customers as synced
  Future<void> markCustomersAsSynced(List<int> customerIds) async {
    for (final id in customerIds) {
      await (_database.update(_database.customers)
        ..where((c) => c.id.equals(id)))
        .write(const CustomersCompanion(isSynced: Value(true)));
    }
  }

  /// Sync all local data to server
  Future<void> uploadLocalData() async {
    // Sync customers first (may be referenced by orders)
    final customers = await getCustomersForSync();
    if (customers.isNotEmpty) {
      await _apiService.syncCustomers(customers);
      await markCustomersAsSynced(customers.map((c) => c['id'] as int).toList());
    }

    // Sync completed orders
    final orders = await getOrdersForSync();
    if (orders.isNotEmpty) {
      await _apiService.syncOrders(orders);
      await markOrdersAsSynced(orders.map((o) => o['id'] as int).toList());
    }

    // Sync tickets for synced orders
    final tickets = await getTicketsForSync();
    if (tickets.isNotEmpty) {
      await _apiService.syncTickets(tickets);
      await markTicketsAsSynced(tickets.map((t) => t['id'] as int).toList());
    }

    // Sync ended sessions
    final sessions = await getSessionsForSync();
    if (sessions.isNotEmpty) {
      await _apiService.syncSessions(sessions);
      await markSessionsAsSynced(sessions.map((s) => s['id'] as int).toList());
    }
  }

  /// Get sync status summary
  Future<Map<String, int>> getSyncStatus() async {
    final unsyncedOrders = await (_database.select(_database.orders)
      ..where((o) => o.status.equals('COMPLETED') & o.isSynced.equals(false)))
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
}


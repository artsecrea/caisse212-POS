import 'package:drift/drift.dart';
import 'package:posecrea/data/database/app_database.dart';
import 'package:posecrea/data/database/tables/pending_sync_operation_table.dart';
import 'package:posecrea/services/api_service.dart';
import 'package:posecrea/services/pending_operations_service.dart';
import 'package:loggecrea/loggecrea.dart';
import 'dart:convert';

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

  /// Clear only master data (not transactional data like orders, tickets, sessions)
  Future<void> clearMasterData() async {
    // Only clear reference/master data, preserve transactional data
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

  /// Clear old synced data based on retention period
  Future<void> clearOldSyncedData(int retentionDays) async {
    final cutoffDate = DateTime.now().subtract(Duration(days: retentionDays));

    // Delete old synced orders
    await (_database.delete(_database.orders)
      ..where((o) => o.isSynced.equals(true) & o.updatedAt.isSmallerThanValue(cutoffDate)))
      .go();

    // Delete old synced tickets
    await (_database.delete(_database.tickets)
      ..where((t) => t.isSynced.equals(true) & t.date.isSmallerThanValue(cutoffDate)))
      .go();

    // Delete old synced sessions
    await (_database.delete(_database.cashSessions)
      ..where((s) => s.isSynced.equals(true) & s.endedAt.isSmallerThanValue(cutoffDate)))
      .go();

    // Delete old synced customers
    await (_database.delete(_database.customers)
      ..where((c) => c.isSynced.equals(true) & c.createdAt.isSmallerThanValue(cutoffDate)))
      .go();
  }

  /// Clear all data from the database (for demo mode or full reset)
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
    await clearMasterData();
  }

  /// Sync all data from the server
  Future<void> syncAllData({int? dataRetentionDays}) async {
    try {
      // Clear only master data (keep transactional data like orders, tickets)
      onProgress?.call('Clearing master data...', 0.0);
      await clearMasterData();

      // Optionally clear old synced data based on retention period
      if (dataRetentionDays != null && dataRetentionDays > 0) {
        onProgress?.call('Clearing old synced data...', 0.05);
        await clearOldSyncedData(dataRetentionDays);
      }

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

    // Build order list with products
    final ordersList = <Map<String, dynamic>>[];

    for (final order in orders) {
      // Get all products for this order
      final orderProducts = await (_database.select(_database.orderProducts)
        ..where((op) => op.orderId.equals(order.id)))
        .get();

      // Build products list
      final productsList = <Map<String, dynamic>>[];

      for (final product in orderProducts) {
        // Get components for this product
        final productComponents = await (_database.select(_database.orderProductComponents)
          ..where((opc) => opc.orderProductId.equals(product.id)))
          .get();

        // Build components list
        final componentsList = productComponents.map((comp) => {
          'componentId': comp.componentId,
          'quantity': comp.quantity,
          'isSpecial': comp.isSpecial,
        }).toList();

        // Build product map
        productsList.add({
          'productId': product.productId,
          'quantity': product.quantity,
          'unitaryPrice': product.unitaryPrice,
          'unitaryDiscount': product.unitaryDiscount,
          'unitaryTva': product.unitaryTva,
          'manualDiscount': product.manualDiscount,
          'manualDiscountReason': product.manualDiscountReason,
          'state': product.state,
          'components': componentsList,
        });
      }

      // Build order map with products
      ordersList.add({
        'id': order.id,
        'code': order.code,
        'status': order.status,
        'type': order.type,
        'priority': order.priority,
        'coupon': order.coupon,
        'persons': order.persons,
        'tableId': order.tableId,
        'clientId': order.clientId,
        'commercialId': order.commercialId,
        'discountPercentage': order.discountPercentage,
        'note': order.note,
        'products': productsList,
        'createdAt': order.createdAt.toIso8601String(),
        'updatedAt': order.updatedAt.toIso8601String(),
      });
    }

    return ordersList;
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
      'createdAt': t.date.toIso8601String(),
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

  /// Sync a single order immediately (for online auto-sync)
  Future<bool> syncSingleOrder(int orderId) async {
    try {
      // Get the specific order with products
      final order = await (_database.select(_database.orders)
        ..where((o) => o.id.equals(orderId)))
        .getSingleOrNull();

      if (order == null || order.isSynced) {
        return false; // Order doesn't exist or already synced
      }

      // Get all products for this order
      final orderProducts = await (_database.select(_database.orderProducts)
        ..where((op) => op.orderId.equals(order.id)))
        .get();

      // Build products list with components
      final productsList = <Map<String, dynamic>>[];

      for (final product in orderProducts) {
        final productComponents = await (_database.select(_database.orderProductComponents)
          ..where((opc) => opc.orderProductId.equals(product.id)))
          .get();

        final componentsList = productComponents.map((comp) => {
          'componentId': comp.componentId,
          'quantity': comp.quantity,
          'isSpecial': comp.isSpecial,
        }).toList();

        productsList.add({
          'productId': product.productId,
          'quantity': product.quantity,
          'unitaryPrice': product.unitaryPrice,
          'unitaryDiscount': product.unitaryDiscount,
          'unitaryTva': product.unitaryTva,
          'manualDiscount': product.manualDiscount,
          'manualDiscountReason': product.manualDiscountReason,
          'state': product.state,
          'components': componentsList,
        });
      }

      // Build order map
      final orderData = {
        'id': order.id,
        'code': order.code,
        'status': order.status,
        'type': order.type,
        'priority': order.priority,
        'coupon': order.coupon,
        'persons': order.persons,
        'tableId': order.tableId,
        'clientId': order.clientId,
        'commercialId': order.commercialId,
        'discountPercentage': order.discountPercentage,
        'note': order.note,
        'products': productsList,
        'createdAt': order.createdAt.toIso8601String(),
        'updatedAt': order.updatedAt.toIso8601String(),
      };

      // Sync to server
      await _apiService.syncOrders([orderData]);

      // Mark as synced
      await markOrdersAsSynced([orderId]);

      return true;
    } catch (e) {
      print('Error syncing single order: $e');
      return false;
    }
  }

  /// Sync orders in bulk with limited batch size
  Future<int> syncOrdersBulk({int batchSize = 50}) async {
    try {
      // Get unsynced orders
      final orders = await getOrdersForSync();

      if (orders.isEmpty) {
        return 0;
      }

      // Take only the specified batch size
      final batch = orders.take(batchSize).toList();

      // Sync the batch
      await _apiService.syncOrders(batch);

      // Mark as synced
      final syncedIds = batch.map((o) => o['id'] as int).toList();
      await markOrdersAsSynced(syncedIds);

      return batch.length;
    } catch (e) {
      print('Error syncing orders bulk: $e');
      return 0;
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

    // Only process if we have a server ID (can't delete if not synced to server)
    if (operation.serverId == null) {
      _logger.warning('Skipping DELETE - no server ID for ${operation.entityType} #${operation.entityId}');
      return;
    }

    switch (operation.entityType) {
      case 'ORDER':
        await _apiService.deleteOrder(operation.serverId!);
        _logger.info('Deleted order #${operation.serverId} from server');
        break;

      case 'TICKET':
        await _apiService.deleteTicket(operation.serverId!);
        _logger.info('Deleted ticket #${operation.serverId} from server');
        break;

      case 'ORDER_PRODUCT':
        await _apiService.deleteOrderProduct(operation.serverId!);
        _logger.info('Deleted order product #${operation.serverId} from server');
        break;

      default:
        _logger.warning('Unknown entity type for delete: ${operation.entityType}');
    }
  }

  /// Process a pending update operation
  Future<void> _processPendingUpdate(PendingSyncOperation operation) async {
    _logger.info('Processing UPDATE for ${operation.entityType} #${operation.entityId}');

    if (operation.serverId == null) {
      _logger.warning('Skipping UPDATE - no server ID for ${operation.entityType} #${operation.entityId}');
      return;
    }

    if (operation.updateData == null) {
      _logger.warning('Skipping UPDATE - no update data for ${operation.entityType} #${operation.entityId}');
      return;
    }

    final updateData = operation.updateData!;

    switch (operation.entityType) {
      case 'ORDER':
        await _apiService.updateOrder(operation.serverId!, updateData);
        _logger.info('Updated order #${operation.serverId} on server');
        break;

      case 'TICKET':
        await _apiService.updateTicket(operation.serverId!, updateData);
        _logger.info('Updated ticket #${operation.serverId} on server');
        break;

      case 'ORDER_PRODUCT':
        await _apiService.updateOrderProduct(operation.serverId!, updateData);
        _logger.info('Updated order product #${operation.serverId} on server');
        break;

      default:
        _logger.warning('Unknown entity type for update: ${operation.entityType}');
    }
  }

  /// Queue a delete operation (for offline support)
  Future<void> queueDelete(String entityType, int entityId, {int? serverId}) async {
    await _pendingOpsService.queueDelete(
      entityType: entityType,
      entityId: entityId,
      serverId: serverId,
    );
  }

  /// Queue an update operation (for offline support)
  Future<void> queueUpdate(String entityType, int entityId, Map<String, dynamic> updateData, {int? serverId}) async {
    await _pendingOpsService.queueUpdate(
      entityType: entityType,
      entityId: entityId,
      serverId: serverId,
      updateData: updateData,
    );
  }

  /// Execute delete immediately if online, queue if offline
  Future<void> deleteEntity({
    required String entityType,
    required int entityId,
    int? serverId,
    required bool isOnline,
  }) async {
    if (isOnline && serverId != null) {
      // Execute immediately
      try {
        switch (entityType) {
          case 'ORDER':
            await _apiService.deleteOrder(serverId);
            break;
          case 'TICKET':
            await _apiService.deleteTicket(serverId);
            break;
          case 'ORDER_PRODUCT':
            await _apiService.deleteOrderProduct(serverId);
            break;
        }
        _logger.info('Deleted $entityType #$serverId from server immediately');
      } catch (e) {
        _logger.error('Failed to delete $entityType immediately, queuing: $e');
        await queueDelete(entityType, entityId, serverId: serverId);
      }
    } else {
      // Queue for later
      await queueDelete(entityType, entityId, serverId: serverId);
    }
  }

  /// Execute update immediately if online, queue if offline
  Future<void> updateEntity({
    required String entityType,
    required int entityId,
    required Map<String, dynamic> updateData,
    int? serverId,
    required bool isOnline,
  }) async {
    if (isOnline && serverId != null) {
      // Execute immediately
      try {
        final updateDataJson = jsonEncode(updateData);
        switch (entityType) {
          case 'ORDER':
            await _apiService.updateOrder(serverId, updateDataJson);
            break;
          case 'TICKET':
            await _apiService.updateTicket(serverId, updateDataJson);
            break;
          case 'ORDER_PRODUCT':
            await _apiService.updateOrderProduct(serverId, updateDataJson);
            break;
        }
        _logger.info('Updated $entityType #$serverId on server immediately');
      } catch (e) {
        _logger.error('Failed to update $entityType immediately, queuing: $e');
        await queueUpdate(entityType, entityId, updateData, serverId: serverId);
      }
    } else {
      // Queue for later
      await queueUpdate(entityType, entityId, updateData, serverId: serverId);
    }
  }
}


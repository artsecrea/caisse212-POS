import 'package:drift/drift.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/pending_operations_service.dart';
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
    // Delete in reverse order of dependencies to avoid foreign key issues
    await _database.delete(_database.kDSs).go();
    await _database.delete(_database.kiosks).go();
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
      // Wrap entire sync in a transaction so it's atomic - all or nothing
      await _database.transaction(() async {
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

        onProgress?.call('Fetching product variants...', 0.35);
        await _syncVariants();

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

        onProgress?.call('Fetching customers...', 0.85);
        await _syncCustomers();

        onProgress?.call('Fetching waiters...', 0.95);
        await _syncWaiters();
      });

      onProgress?.call('Sync complete!', 1.0);
    } catch (e) {
      _logger.error('Sync failed: $e');
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
          isVariant: Value(product['isVariant'] ?? false),
        ),
        mode: InsertMode.insertOrReplace,
      );
    }
  }

  Future<void> _syncVariants() async {
    final variants = await _apiService.fetchVariants();
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
          defaultQuantity: Value(pc['defaultQuantity'] ?? 0),

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

  Future<void> _syncWaiters() async {
    final waiters = await _apiService.fetchWaiters();

    // Clear existing waiter-area assignments
    await _database.delete(_database.waiterAreas).go();

    for (final waiter in waiters) {
      // Insert or update waiter (username and passwordHash may be null)
      await _database.into(_database.waiters).insert(
        WaitersCompanion.insert(
          id: Value(waiter['id']),
          firstName: waiter['firstName'] ?? '',
          lastName: Value(waiter['lastName']),
          imageUrl: Value(waiter['imageUrl']),
          username: Value(waiter['username']), // Can be null - for future authentication
          passwordHash: Value(waiter['passwordHash']), // Can be null - for future authentication
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
    // First pass: build product data with component totals to calculate effective prices
    final productDataList = <Map<String, dynamic>>[];
    final effectivePrices = <double>[]; // effective price per product (before order discount)

    for (final product in orderProducts) {
      // Get components for this product
      final productComponents = await (_database.select(_database.orderProductComponents)
        ..where((opc) => opc.orderProductId.equals(product.id)))
        .get();

      // Build components list
      final componentsList = productComponents.map((comp) => {
        'componentId': comp.componentId,
        'quantity': comp.quantity,
        'price': comp.price,
        'isSpecial': comp.isSpecial,
      }).toList();

      // Calculate component total
      double componentTotal = 0.0;
      for (final comp in productComponents) {
        componentTotal += comp.price * comp.quantity;
      }

      // Effective price per item = (unitaryPrice + componentTotal - unitaryDiscount - manualDiscount)
      // Then multiply by quantity for total effective price
      final effectivePerItem = (product.unitaryPrice + componentTotal - product.unitaryDiscount - product.manualDiscount);
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

    // Second pass: if discountPercentage > 0, distribute order-level discount
    // proportionally into each product's manualDiscount
    if (discountPercentage > 0) {
      final totalEffective = effectivePrices.fold(0.0, (sum, v) => sum + v);

      if (totalEffective > 0) {
        final orderDiscountAmount = totalEffective * (discountPercentage / 100.0);

        for (int i = 0; i < productDataList.length; i++) {
          final proportion = effectivePrices[i] / totalEffective;
          final productShareOfDiscount = orderDiscountAmount * proportion;
          // Distribute per-unit: divide by quantity
          final qty = productDataList[i]['quantity'] as int;
          final perUnitShare = qty > 0 ? productShareOfDiscount / qty : 0.0;
          // Merge into existing manualDiscount
          final existingManualDiscount = productDataList[i]['manualDiscount'] as double;
          productDataList[i]['manualDiscount'] = existingManualDiscount + perUnitShare;
        }
      }
    }

    return productDataList;
  }

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
        'clientId': order.clientId,
        'commercialId': order.commercialId,
        'discountPercentage': 0.0,
        'note': order.note,
        'createdBy': order.createdBy,
        'servedBy': order.waiterId,
        'products': productsList,
        'createdAt': order.createdAt.toIso8601String(),
        'updatedAt': order.updatedAt.toIso8601String(),
      });
    }

    return ordersList;
  }

  /// Get all tickets for completed, synced orders that haven't been synced yet
  Future<List<Map<String, dynamic>>> getTicketsForSync() async {
    // Get synced order IDs and codes
    final syncedOrders = await (_database.select(_database.orders)
      ..where((o) => o.isSynced.equals(true)))
      .get();
    final syncedOrderMap = {for (var o in syncedOrders) o.id: o.code};

    // Get synced sessions IDs and codes
    final sessions = await (_database.select(_database.cashSessions)
      .get());

    // Get tickets that belong to synced orders but aren't synced yet
    final tickets = await (_database.select(_database.tickets)
      ..where((t) => t.isSynced.equals(false)))
      .get();

    // Filter tickets for synced orders only and build ticket list
    final ticketsList = <Map<String, dynamic>>[];
    for (final t in tickets) {
      if (!syncedOrderMap.containsKey(t.orderId)) continue;

      // Get session code if ticket has a session
      String? sessionCode = sessions.firstWhere((s) => s.id == t.sessionId).code;


      print(">>>>>>>>>>>>>>>>>>> $sessionCode");

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
  /// Each entity type is synced independently so a failure in one does not
  /// block the others.  Mark-as-synced only runs when the API call succeeds.
  Future<void> uploadLocalData() async {
    // Sync customers first (may be referenced by orders)
    try {
      final customers = await getCustomersForSync();
      if (customers.isNotEmpty) {
        await _apiService.syncCustomers(customers);
        // Only mark after a confirmed successful API response
        await markCustomersAsSynced(customers.map((c) => c['id'] as int).toList());
      }
    } catch (e) {
      _logger.error('uploadLocalData: customers sync failed – will retry later: $e');
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
        'clientId': order.clientId,
        'commercialId': order.commercialId,
        'discountPercentage': 0.0,
        'createdBy': order.createdBy,
        'servedBy': order.waiterId,
        'note': order.note,
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
        await _pendingOpsService.queueSessionDelete(entityId: entityId, sessionId: entityId);
      }
    } else {
      await _pendingOpsService.queueSessionDelete(entityId: entityId, sessionId: entityId);
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
        await _pendingOpsService.queueSessionUpdate(entityId: entityId, sessionId: entityId, updateData: updateData);
      }
    } else {
      await _pendingOpsService.queueSessionUpdate(entityId: entityId, sessionId: entityId, updateData: updateData);
    }
  }
}


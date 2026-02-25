import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import '../domain/models/order_models.dart';
import '../data/database/app_database.dart';
import '../domain/models/order_events.dart';
import '../services/pending_operations_service.dart';
import '../services/data_sync_service.dart';
import '../services/order_log_service.dart';
import 'package:uuid/uuid.dart';
import 'database_providers.dart';
import 'network_provider.dart';

// Current Order State Provider
class OrderNotifier extends StateNotifier<CurrentOrder> {
  OrderNotifier() : super(CurrentOrder());

  void addItem(OrderItem item) {
    // Check if trying to add an item that belongs to a paid ticket
    if (item.ticketId != null) {
      throw Exception('Cannot add items from paid tickets');
    }

    // Check for duplicate items (same product, note, and components)
    final existingItemIndex = _findDuplicateItemIndex(item);

    if (existingItemIndex != -1) {
      // Merge with existing item by adding quantities
      final items = List<OrderItem>.from(state.items);
      final existingItem = items[existingItemIndex];
      items[existingItemIndex] = existingItem.copyWith(
        quantity: existingItem.quantity + item.quantity,
      );
      state = state.copyWith(items: items);
    } else {
      // Add as new item
      state = state.copyWith(
        items: [...state.items, item],
      );
    }
  }

  /// Find the index of a duplicate item in the current order
  /// Returns -1 if no duplicate is found
  /// Items are duplicates if they have:
  /// - Same productId
  /// - Same note (null or matching string)
  /// - Same components (same componentId and quantity for each)
  /// - Not already paid (ticketId is null)
  int _findDuplicateItemIndex(OrderItem newItem) {
    for (int i = 0; i < state.items.length; i++) {
      final existingItem = state.items[i];

      // Skip items that are already paid
      if (existingItem.ticketId != null) {
        continue;
      }

      // Check if product IDs match
      if (existingItem.productId != newItem.productId) {
        continue;
      }

      // Check if notes match (both null or same string)
      final notesMatch = (existingItem.note == null && newItem.note == null) ||
                         (existingItem.note != null && newItem.note != null &&
                          existingItem.note == newItem.note);

      if (!notesMatch) {
        continue;
      }

      // Check if components match
      if (!_componentsMatch(existingItem.components, newItem.components)) {
        continue;
      }

      // Found a duplicate
      return i;
    }

    return -1;
  }

  /// Check if two component lists are identical
  /// They match if they have the same components with the same quantities
  bool _componentsMatch(List<OrderItemComponent> list1, List<OrderItemComponent> list2) {
    // Different number of components
    if (list1.length != list2.length) {
      return false;
    }

    // Both empty
    if (list1.isEmpty) {
      return true;
    }

    // Sort both lists by componentId for comparison
    final sorted1 = List<OrderItemComponent>.from(list1)
      ..sort((a, b) => a.componentId.compareTo(b.componentId));
    final sorted2 = List<OrderItemComponent>.from(list2)
      ..sort((a, b) => a.componentId.compareTo(b.componentId));

    // Compare each component
    for (int i = 0; i < sorted1.length; i++) {
      if (sorted1[i].componentId != sorted2[i].componentId ||
          sorted1[i].quantity != sorted2[i].quantity) {
        return false;
      }
    }

    return true;
  }

  void removeItem(int index) {
    final items = List<OrderItem>.from(state.items);

    // Don't allow removing items from paid tickets
    if (items[index].ticketId != null) {
      throw Exception('Cannot remove items from paid tickets');
    }

    items.removeAt(index);
    state = state.copyWith(items: items);
  }

  void updateItemQuantity(int index, int quantity) {
    if (quantity <= 0) {
      removeItem(index);
      return;
    }

    final items = List<OrderItem>.from(state.items);
    items[index] = items[index].copyWith(quantity: quantity);
    state = state.copyWith(items: items);
  }

  void updateItem(int index, OrderItem item) {
    final items = List<OrderItem>.from(state.items);

    // Don't allow updating items from paid tickets
    if (items[index].ticketId != null) {
      throw Exception('Cannot update items from paid tickets');
    }

    items[index] = item;
    state = state.copyWith(items: items);
  }

  void setTable(int? tableId, String? tableName) {
    clearOrder();
    state = state.copyWith(tableId: tableId, tableName: tableName);
  }

  void clearTable() {
    state = state.copyWith(
      tableId: null,
      tableName: null,
    );
  }

  void setCustomer(int? customerId, String? customerName) {
    state = state.copyWith(customerId: customerId, customerName: customerName);
  }

  void clearCustomer() {
    state = CurrentOrder(
      orderId: state.orderId,
      orderCode: state.orderCode,
      items: state.items,
      tableId: state.tableId,
      tableName: state.tableName,
      customerId: null,
      customerName: null,
      commercialId: state.commercialId,
      commercialName: state.commercialName,
      coupon: state.coupon,
      discountPercentage: state.discountPercentage,
      note: state.note,
      type: state.type,
      numberOfPersons: state.numberOfPersons,
    );
  }

  void setCommercial(int? commercialId, String? commercialName) {
    state = state.copyWith(commercialId: commercialId, commercialName: commercialName);
  }

  void clearCommercial() {
    state = CurrentOrder(
      orderId: state.orderId,
      orderCode: state.orderCode,
      items: state.items,
      tableId: state.tableId,
      tableName: state.tableName,
      customerId: state.customerId,
      customerName: state.customerName,
      commercialId: null,
      commercialName: null,
      coupon: state.coupon,
      discountPercentage: state.discountPercentage,
      note: state.note,
      type: state.type,
      numberOfPersons: state.numberOfPersons,
    );
  }

  void setDiscountPercentage(double percentage) {
    state = state.copyWith(discountPercentage: percentage);
  }

  void setNote(String? note) {
    state = state.copyWith(note: note);
  }

  void setOrderType(String type) {
    state = state.copyWith(type: type);
  }

  void setNumberOfPersons(int count) {
    state = state.copyWith(numberOfPersons: count);
  }

  void clearOrder() {
    state = CurrentOrder();
  }

  void loadOrder(CurrentOrder order) {
    state = order;
  }

  void mergeItems(List<OrderItem> newItems) {
    state = state.copyWith(
      items: [...state.items, ...newItems],
    );
  }


  void holdOrder() {
    // Save to held orders - will be implemented in repository
  }
}

final orderProvider = StateNotifierProvider<OrderNotifier, CurrentOrder>((ref) {
  return OrderNotifier();
});

// Order Repository
class OrderRepository {
  final AppDatabase _database;
  final _logger = Logger.instance;
  late final OrderLogService _logService;

  // Optional sync service and network status callback for auto-sync
  DataSyncService? _syncService;
  bool Function()? _isOnlineCallback;

  OrderRepository(this._database) {
    _logService = OrderLogService(_database);
  }

  /// Set sync service for auto-syncing completed orders
  void setSyncService(DataSyncService syncService, bool Function() isOnlineCallback) {
    _syncService = syncService;
    _isOnlineCallback = isOnlineCallback;
  }

  // Event stream for socket service integration
  final StreamController<OrderEvent> _eventController = StreamController<OrderEvent>.broadcast();

  /// Stream of order events (insert, update, delete, status changes, etc.)
  Stream<OrderEvent> get events => _eventController.stream;

  /// Dispose the repository and close streams
  void dispose() {
    _eventController.close();
  }

  /// Emit an event to listeners
  void _emitEvent(OrderEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  Future<int> saveOrder(CurrentOrder order, int userId, {String status = 'PENDING'}) async {

    if (order.orderId != null) {
      throw Exception("Order already has an order code, use updateOrder instead.");
    }
    print(order.items.first.toJson());
    // Generate order code
    final uuid = const Uuid();
    final orderCode = order.orderCode != null ? order.orderCode! : uuid.v4().substring(0, 8).toUpperCase();

    // check if the order with that code exists
    final existingOrder = await (_database.select(_database.orders)..where((tbl) => tbl.code.equals(orderCode))).getSingleOrNull();
      if (existingOrder != null) {
        throw Exception("Order with code $orderCode already exists.");
      }
    // Insert order
    final orderId = await _database.into(_database.orders).insert(
      OrdersCompanion.insert(
        code: orderCode,
        status: Value(status),
        type: Value(order.type),
        priority: Value(0),
        note: Value(order.note),
        tableId: Value(order.tableId),
        source: Value('POS'),
        sourceId: Value(null),
        discountPercentage: Value(order.discountPercentage),
        createdBy: Value(userId),
        takenBy: Value(userId),
        persons: Value(order.numberOfPersons),

        clientId: Value(order.customerId),
        commercialId: Value(order.commercialId),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
// flutter pub run build_runner build --delete-conflicting-outputs
    // Insert order products - set state based on order status
    final itemState = status == 'ONHOLD' ? 'ONHOLD' : 'PENDING';
    for (final item in order.items) {
      final orderProductId = await _database.into(_database.orderProducts).insert(
        OrderProductsCompanion.insert(
          orderId: orderId,
          productId: item.productId,
          quantity: Value(item.quantity),
          unitaryPrice: item.finalPrice,
          unitaryDiscount: Value(item.discount),
          manualDiscount: Value(item.manualDiscount),
          unitaryTva: Value(item.tva),
          state: Value(itemState),
        ),
      );

      // Insert order product components
      for (final component in item.components) {
        await _database.into(_database.orderProductComponents).insert(
          OrderProductComponentsCompanion.insert(
            componentId: component.componentId,
            orderProductId: orderProductId,
            quantity: Value(component.quantity),
            price: Value(component.price),
            isSpecial: Value(component.isSpecial),
          ),
        );
      }
    }

    // Emit event
    _emitEvent(OrderInsertedEvent(
      orderId: orderId,
      orderCode: orderCode,
      status: status,
    ));

    // Log order creation
    await _logService.logOrderCreated(orderId, 'Order created with code $orderCode, status $status');

    // Auto-sync if order is COMPLETED and network is available
    print("-----------------------------------------------");
    if (status == 'COMPLETED' && _syncService != null && _isOnlineCallback != null) {
      print("-----------------------------------------------2");
      final isOnline = _isOnlineCallback!();
      if (isOnline) {
        try {
          await _syncService!.syncSingleOrder(orderId);
          print("-----------------------------------------------3");

          _logger.info('Auto-synced new COMPLETED order code=$orderCode');
        } catch (e) {
          _logger.error('Failed to auto-sync new order: $e');
          // Order is saved locally, will be synced later
        }
      }
    }

    return orderId;
  }

  Future<int> holdOrder(CurrentOrder order, int userId) async {
    // Check if order is already saved (has orderId)
    if (order.isSaved()) {
      // Check if there are new items added (items without IDs are new)
      final hasNewItems = order.items.any((item) => item.id == null);

      if (hasNewItems) {
        // Cannot hold an order that has new unsaved items
        // User must press "Proceed" first to save those items
        throw Exception('Cannot hold order with new items. Press Proceed first to save them.');
      }

      // No new items, just update status to ONHOLD
      final orderId = order.orderId!;
      await updateOrderStatus(orderId, "ONHOLD");

      // Update all unpaid items to ONHOLD state
      for (final item in order.items) {
        if (item.id != null && item.ticketId == null) {
          await (_database.update(_database.orderProducts)
            ..where((tbl) => tbl.id.equals(item.id!)))
            .write(OrderProductsCompanion(
              state: const Value('ONHOLD'),
              updatedAt: Value(DateTime.now()),
            ));
        }
      }

      final savedOrder = await (_database.select(_database.orders)
        ..where((tbl) => tbl.id.equals(orderId)))
          .getSingle();

      // Emit hold event
      _emitEvent(OrderHeldEvent(
        orderId: orderId,
        orderCode: savedOrder.code,
      ));
      return order.orderId!;
    }

    // Save new order as ONHOLD
    final orderId = await saveOrder(order, userId, status: 'ONHOLD');
    final savedOrder = await (_database.select(_database.orders)
      ..where((tbl) => tbl.id.equals(orderId)))
        .getSingle();

    // Emit hold event
    _emitEvent(OrderHeldEvent(
      orderId: orderId,
      orderCode: savedOrder.code,
    ));

    return orderId;
  }

  Future<void> updateOrder(CurrentOrder order, {bool queueSyncOperation = true}) async {
    int orderId = order.orderId!;

    // Check if order was synced and queue update operation
    final existingOrder = await (_database.select(_database.orders)
      ..where((tbl) => tbl.id.equals(orderId)))
      .getSingleOrNull();

    final wasAlreadySynced = existingOrder?.isSynced ?? false;
    final orderCode = existingOrder?.code ?? order.orderCode ?? '';

    // Update order details
    await (_database.update(_database.orders)..where((tbl) => tbl.id.equals(orderId))).write(OrdersCompanion(
      tableId: Value(order.tableId),
      clientId: Value(order.customerId),
      commercialId: Value(order.commercialId),
      discountPercentage: Value(order.discountPercentage),
      persons: Value(order.numberOfPersons),

      note: Value(order.note),
      updatedAt: Value(DateTime.now()),

      // Mark as not synced if changes were made to a previously synced order
      isSynced: Value(wasAlreadySynced ? false : existingOrder?.isSynced ?? false),
    ));

    // Delete existing unpaid order products (keep paid ones)
    await (_database.delete(_database.orderProducts)..where((tbl) => tbl.orderId.equals(orderId))..where((tbl) => tbl.ticketId.isNull())).go();

    // Insert new order products
    for (final item in order.items) {
      if (item.ticketId != null) {
        // Skip items that are already ticketed
        _logger.debug("Skipping ticketed item");
        continue;
      }
      final orderProductId = await _database.into(_database.orderProducts).insert(
        OrderProductsCompanion.insert(
          orderId: orderId,
          productId: item.productId,
          quantity: Value(item.quantity),
          unitaryPrice: item.finalPrice,
          unitaryDiscount: Value(item.discount),
          manualDiscount: Value(item.manualDiscount),
          unitaryTva: Value(item.tva),
          state: Value('PENDING'),
        ),
      );

      // Insert order product components
      for (final component in item.components) {
        await _database.into(_database.orderProductComponents).insert(
          OrderProductComponentsCompanion.insert(
            componentId: component.componentId,
            orderProductId: orderProductId,
            quantity: Value(component.quantity),
            price: Value(component.price),
            isSpecial: Value(component.isSpecial),
          ),
        );
      }
    }

    // If order was previously synced, we need to sync the update
    if (wasAlreadySynced && queueSyncOperation && orderCode.isNotEmpty) {
      // Try to sync immediately if online, otherwise queue
      if (_syncService != null && _isOnlineCallback != null) {
        final isOnline = _isOnlineCallback!();
        if (isOnline) {
          try {
            // Re-sync the entire order with updated products
            await _syncService!.syncSingleOrder(orderId);
            _logger.info('Re-synced updated order code=$orderCode');
          } catch (e) {
            _logger.error('Failed to re-sync updated order, queuing update: $e');
            // Queue update operation as fallback
            await _queueOrderUpdate(orderId, orderCode, order);
          }
        } else {
          // Offline - queue the update
          await _queueOrderUpdate(orderId, orderCode, order);
        }
      } else {
        // No sync service - queue the update
        await _queueOrderUpdate(orderId, orderCode, order);
      }
    }

    // Emit event
    _emitEvent(OrderUpdatedEvent(orderId: orderId));
    _emitEvent(OrderItemsChangedEvent(
      orderId: orderId,
      itemCount: order.items.length,
    ));

    // Log order update
    await _logService.logOrderUpdated(orderId, 'Order updated: code=$orderCode');
  }

  /// Helper to queue order update operation
  Future<void> _queueOrderUpdate(int orderId, String orderCode, CurrentOrder order) async {
    try {
      final pendingOpsService = PendingOperationsService(_database);
      await pendingOpsService.queueOrderUpdate(
        entityId: orderId,
        orderCode: orderCode,
        updateData: {
          'tableId': order.tableId,
          'clientId': order.customerId,
          'commercialId': order.commercialId,
          'discountPercentage': order.discountPercentage,
          'note': order.note,
        },
      );
      _logger.info('Queued update operation for order code=$orderCode');
    } catch (e) {
      _logger.error('Failed to queue update operation: $e');
    }
  }

  Future<CurrentOrder?> getOrderByTable(int tableId) async {
    // Get the most recent ONHOLD order for this table
    final table = await (_database.select(_database.areaTables)..where((tbl) => tbl.id.equals(tableId))).getSingleOrNull();

    if (table == null || table.orderId == null) return null;

    final order = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(table.orderId!))).getSingleOrNull();

    if (order == null) return null;

    return await loadOrderDetails(order);
  }

  Future<void> updateOrderProductState(int orderId, int productId, String newState) async {
    await (_database.update(_database.orderProducts)
          ..where((tbl) => tbl.orderId.equals(orderId) & tbl.id.equals(productId)))
        .write(OrderProductsCompanion(
      state: Value(newState),
      updatedAt: Value(DateTime.now()),
    ));

  }

  Future<CurrentOrder?> getOrderById(int orderId) async {
    final order = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();

    if (order == null) return null;

    return await loadOrderDetails(order);
  }

  Future<CurrentOrder?> getOrderByCode(String orderCode) async {
    final order = await (_database.select(_database.orders)..where((tbl) => tbl.code.equals(orderCode))).getSingleOrNull();

    if (order == null) return null;

    return await loadOrderDetails(order);
  }

  Future<CurrentOrder> loadOrderDetails(Order order) async {
    // Get order products
    final orderProducts = await (_database.select(_database.orderProducts)..where((tbl) => tbl.orderId.equals(order.id))).get();

    final items = <OrderItem>[];
    for (final orderProduct in orderProducts) {
      // Get product details
      final product = await (_database.select(_database.products)..where((tbl) => tbl.id.equals(orderProduct.productId))).getSingleOrNull();

      if (product == null) continue;

      // Get order product components
      final orderComponents = await (_database.select(_database.orderProductComponents)..where((tbl) => tbl.orderProductId.equals(orderProduct.id))).get();

      final components = <OrderItemComponent>[];
      for (final orderComp in orderComponents) {
        final component = await (_database.select(_database.components)..where((tbl) => tbl.id.equals(orderComp.componentId))).getSingleOrNull();

        if (component != null) {
          components.add(OrderItemComponent(
            componentId: component.id,
            name: component.name,
            quantity: orderComp.quantity,
            price: orderComp.price, // Use stored price from order time
            isSpecial: orderComp.isSpecial,
          ));
        }
      }

      items.add(OrderItem(
        id: orderProduct.id,
        productId: product.id,
        productName: product.name,
        imageUrl: product.imageUrl,
        finalPrice: orderProduct.unitaryPrice,
        quantity: orderProduct.quantity,
        components: components,
        discount: orderProduct.unitaryDiscount,
        manualDiscount: orderProduct.manualDiscount,
        tva: orderProduct.unitaryTva,
        ticketId: orderProduct.ticketId,
        state: orderProduct.state,
      ));
    }

    // Get table name
    String? tableName;
    if (order.tableId != null) {
      final table = await (_database.select(_database.areaTables)..where((tbl) => tbl.id.equals(order.tableId!))).getSingleOrNull();
      tableName = table?.name;
    }

    // Get customer name
    String? customerName;
    if (order.clientId != null) {
      final customer = await (_database.select(_database.customers)..where((tbl) => tbl.id.equals(order.clientId!))).getSingleOrNull();
      customerName = customer != null ? '${customer.firstName} ${customer.lastName}' : null;
    }

    // Get commercial name
    String? commercialName;
    if (order.commercialId != null) {
      final commercial = await (_database.select(_database.commercials)..where((tbl) => tbl.id.equals(order.commercialId!))).getSingleOrNull();
      commercialName = commercial != null ? '${commercial.firstName} ${commercial.lastName}' : null;
    }

    int numberOfPersons = order.persons ?? 1;

    return CurrentOrder(
      orderId: order.id,
      orderCode: order.code,
      items: items,
      numberOfPersons: numberOfPersons,


      tableId: order.tableId,
      tableName: tableName,
      customerId: order.clientId,
      customerName: customerName,
      commercialId: order.commercialId,
      commercialName: commercialName,
      discountPercentage: order.discountPercentage,
      note: order.note,
      type: order.type,
    );
  }

  // Get all tables with their active orders
  Future<List<TableWithOrder>> getTablesWithOrders() async {
    final tables = await _database.select(_database.areaTables).get();
    final result = <TableWithOrder>[];

    for (final table in tables) {
      if (table.orderId == null) continue;

      final order = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(table.orderId!))).getSingleOrNull();

      if (order == null) continue;

      // Calculate total
      final orderProducts = await (_database.select(_database.orderProducts)..where((tbl) => tbl.orderId.equals(order.id))).get();

      double total = 0.0;
      for (final product in orderProducts) {
        final subtotal = product.unitaryPrice * product.quantity;
        final discount = product.unitaryDiscount * product.quantity;
        final tva = product.unitaryTva * product.quantity;
        total += subtotal - discount + tva;
      }

      result.add(TableWithOrder(
        table: table,
        orderCount: 1,
        total: total,
        lastUpdated: order.updatedAt,
      ));
    }

    return result;
  }

  Stream<List<Order>> getOrdersByTable(int tableId) {
    return (_database.select(_database.orders)..where((tbl) => tbl.tableId.equals(tableId))).watch();
  }

  Stream<List<Order>> getPendingOrders() {
    return (_database.select(_database.orders)..where((tbl) => tbl.status.isNotIn(['DELIVERED', 'CANCELED']))).watch();
  }

  // Get all held orders (ONHOLD status)
  Future<List<Order>> getHeldOrders() async {
    return await (_database.select(_database.orders)
          ..where((tbl) => tbl.status.equals('ONHOLD'))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]))
        .get();
  }

  // Get all orders with full details
  Future<List<OrderWithDetails>> getAllOrdersWithDetails() async {
    final orders = await (_database.select(_database.orders)..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)])).get();

    final result = <OrderWithDetails>[];
    for (final order in orders) {
      // Get order products count
      final orderProducts = await (_database.select(_database.orderProducts)..where((tbl) => tbl.orderId.equals(order.id))).get();

      // Calculate total
      double total = 0.0;
      for (final product in orderProducts) {
        final subtotal = product.unitaryPrice * product.quantity;
        final discount = product.unitaryDiscount * product.quantity;
        final tva = product.unitaryTva * product.quantity;
        total += subtotal - discount + tva;
      }

      // Get table name
      String? tableName;
      if (order.tableId != null) {
        final table = await (_database.select(_database.areaTables)..where((tbl) => tbl.id.equals(order.tableId!))).getSingleOrNull();
        tableName = table?.name;
      }

      result.add(OrderWithDetails(
        order: order,
        tableName: tableName,
        itemCount: orderProducts.length,
        total: total,
      ));
    }

    return result;
  }

  Future<void> updateOrderStatus(int orderId, String status, {bool queueSyncOperation = true}) async {
    // Get current status before updating
    final currentOrder = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();
    final oldStatus = currentOrder?.status ?? '';
    final wasAlreadySynced = currentOrder?.isSynced ?? false;
    final orderCode = currentOrder?.code ?? '';

    await (_database.update(_database.orders)..where((tbl) => tbl.id.equals(orderId))).write(OrdersCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
      // Mark as not synced when status changes
      isSynced: const Value(false),
    ));

    // Handle sync based on status change
    if (queueSyncOperation && orderCode.isNotEmpty) {
      // If order becomes COMPLETED, try to sync it
      if (status == 'COMPLETED' && _syncService != null && _isOnlineCallback != null) {
        final isOnline = _isOnlineCallback!();
        if (isOnline) {
          try {
            await _syncService!.syncSingleOrder(orderId);
            _logger.info('Synced COMPLETED order code=$orderCode');
          } catch (e) {
            _logger.error('Failed to sync COMPLETED order: $e');
            // Will be synced later by periodic sync
          }
        }
      } else if (wasAlreadySynced) {
        // Order was synced before, queue status update
        try {
          final pendingOpsService = PendingOperationsService(_database);
          await pendingOpsService.queueOrderUpdate(
            entityId: orderId,
            orderCode: orderCode,
            updateData: {'status': status},
          );
          _logger.info('Queued status update operation for order code=$orderCode');
        } catch (e) {
          _logger.error('Failed to queue status update operation: $e');
        }
      }
    }

    // Emit event
    _emitEvent(OrderStatusChangedEvent(
      orderId: orderId,
      oldStatus: oldStatus,
      newStatus: status,
    ));

    // Log order status update
    await _logService.logOrderUpdated(orderId, 'Order status changed from $oldStatus to $status');
  }





  Future<void> setTableOrderId(int tableId, int? orderId) async {
    await (_database.update(_database.areaTables)..where((tbl) => tbl.id.equals(tableId))).write(AreaTablesCompanion(orderId: Value(orderId)));
  }

  // Clear table order assignment (set orderId to null)
  Future<void> clearTableOrder(int tableId) async {
    await setTableOrderId(tableId, null);
  }

  // Get all orders with full details including user, products, discounts, TVA, and paid amounts
  Future<List<OrderFullDetails>> getAllOrdersWithFullDetails() async {
    final orders = await (_database.select(_database.orders)..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)])).get();

    final result = <OrderFullDetails>[];
    for (final order in orders) {
      final fullDetails = await _buildOrderFullDetails(order);
      result.add(fullDetails);
    }

    return result;
  }

  // Get paginated orders with full details - real database-level pagination
  Future<PaginatedOrders> getPaginatedOrdersWithFullDetails({
    required int page,
    required int pageSize,
    String? statusFilter,
    String? searchQuery,
    int? customerId,
    DateTime? startDate,
    DateTime? endDate,
    String sortColumn = 'createdAt',
    bool sortAscending = false,
  }) async {
    // Build the base query with filters
    var countQuery = _database.select(_database.orders);
    var totalCount = 0;
    // Get total count with filters
    {
      var query = _database.select(_database.orders);

      if (statusFilter != null && statusFilter != 'ALL') {
        query = query..where((tbl) => tbl.status.equals(statusFilter));
      }

      if (customerId != null) {
        query = query..where((tbl) => tbl.clientId.equals(customerId));
      }

      if (startDate != null) {
        query = query..where((tbl) => tbl.date.isBiggerOrEqualValue(startDate));
      }

      if (endDate != null) {
        final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
        query = query..where((tbl) => tbl.date.isSmallerOrEqualValue(endOfDay));
      }

      final allOrders = await query.get();

      // Filter by search query in memory (code and userName need joins)
      if (searchQuery != null && searchQuery.isNotEmpty) {
        final searchLower = searchQuery.toLowerCase();
        final filteredOrders = <Order>[];
        for (final order in allOrders) {
          if (order.code.toLowerCase().contains(searchLower)) {
            filteredOrders.add(order);
            continue;
          }
          // Check user name
          if (order.takenBy != null) {
            final user = await (_database.select(_database.users)..where((tbl) => tbl.id.equals(order.takenBy!))).getSingleOrNull();
            if (user?.username.toLowerCase().contains(searchLower) == true) {
              filteredOrders.add(order);
              continue;
            }
          }
          // Check customer name
          if (order.clientId != null) {
            final customer = await (_database.select(_database.customers)..where((tbl) => tbl.id.equals(order.clientId!))).getSingleOrNull();
            if (customer != null) {
              final fullName = '${customer.firstName} ${customer.lastName}'.toLowerCase();
              if (fullName.contains(searchLower)) {
                filteredOrders.add(order);
              }
            }
          }
        }
        totalCount = filteredOrders.length;
      } else {
        totalCount = allOrders.length;
      }
    }

    final totalPages = (totalCount / pageSize).ceil();
    if (totalPages == 0) {
      return PaginatedOrders(
        orders: [],
        totalCount: 0,
        page: page,
        pageSize: pageSize,
        totalPages: 0,
      );
    }

    // Build the paginated query
    var query = _database.select(_database.orders);

    // Apply filters
    if (statusFilter != null && statusFilter != 'ALL') {
      query = query..where((tbl) => tbl.status.equals(statusFilter));
    }

    if (customerId != null) {
      query = query..where((tbl) => tbl.clientId.equals(customerId));
    }

    if (startDate != null) {
      query = query..where((tbl) => tbl.date.isBiggerOrEqualValue(startDate));
    }

    if (endDate != null) {
      final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      query = query..where((tbl) => tbl.date.isSmallerOrEqualValue(endOfDay));
    }

    // Apply sorting
    query = query..orderBy([(tbl) {
      switch (sortColumn) {
        case 'id':
          return sortAscending ? OrderingTerm.asc(tbl.id) : OrderingTerm.desc(tbl.id);
        case 'code':
          return sortAscending ? OrderingTerm.asc(tbl.code) : OrderingTerm.desc(tbl.code);
        case 'status':
          return sortAscending ? OrderingTerm.asc(tbl.status) : OrderingTerm.desc(tbl.status);
        case 'date':
        case 'createdAt':
        default:
          return sortAscending ? OrderingTerm.asc(tbl.createdAt) : OrderingTerm.desc(tbl.createdAt);
      }
    }]);

    // Get all filtered orders (we need to filter by search in memory)
    final allFilteredOrders = await query.get();

    // Apply search filter in memory
    List<Order> ordersToProcess;
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final searchLower = searchQuery.toLowerCase();
      ordersToProcess = [];
      for (final order in allFilteredOrders) {
        if (order.code.toLowerCase().contains(searchLower)) {
          ordersToProcess.add(order);
          continue;
        }
        // Check user name
        if (order.takenBy != null) {
          final user = await (_database.select(_database.users)..where((tbl) => tbl.id.equals(order.takenBy!))).getSingleOrNull();
          if (user?.username.toLowerCase().contains(searchLower) == true) {
            ordersToProcess.add(order);
            continue;
          }
        }
        // Check customer name
        if (order.clientId != null) {
          final customer = await (_database.select(_database.customers)..where((tbl) => tbl.id.equals(order.clientId!))).getSingleOrNull();
          if (customer != null) {
            final fullName = '${customer.firstName} ${customer.lastName}'.toLowerCase();
            if (fullName.contains(searchLower)) {
              ordersToProcess.add(order);
            }
          }
        }
      }
    } else {
      ordersToProcess = allFilteredOrders;
    }

    // Apply pagination in memory after search
    final start = page * pageSize;
    final end = (start + pageSize).clamp(0, ordersToProcess.length);
    final paginatedOrders = start < ordersToProcess.length
        ? ordersToProcess.sublist(start, end)
        : <Order>[];

    // Build full details for each order
    final result = <OrderFullDetails>[];
    for (final order in paginatedOrders) {
      final fullDetails = await _buildOrderFullDetails(order);
      result.add(fullDetails);
    }

    return PaginatedOrders(
      orders: result,
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
      totalPages: totalPages,
    );
  }

  // Helper method to build OrderFullDetails from an Order
  Future<OrderFullDetails> _buildOrderFullDetails(Order order) async {
    // Get order products
    final orderProducts = await (_database.select(_database.orderProducts)..where((tbl) => tbl.orderId.equals(order.id))).get();

    // Get user name
    String? userName;
    if (order.takenBy != null) {
      final user = await (_database.select(_database.users)..where((tbl) => tbl.id.equals(order.takenBy!))).getSingleOrNull();
      userName = user?.username;
    }

    // Get table name
    String? tableName;
    if (order.tableId != null) {
      final table = await (_database.select(_database.areaTables)..where((tbl) => tbl.id.equals(order.tableId!))).getSingleOrNull();
      tableName = table?.name;
    }

    // Get customer name
    String? customerName;
    int? customerId;
    if (order.clientId != null) {
      final customer = await (_database.select(_database.customers)..where((tbl) => tbl.id.equals(order.clientId!))).getSingleOrNull();
      if (customer != null) {
        customerName = '${customer.firstName} ${customer.lastName}';
        customerId = customer.id;
      }
    }

    // Calculate totals
    double subtotal = 0.0;
    double itemDiscount = 0.0;
    double totalTva = 0.0;
    double totalPaid = 0.0;
    int? ticketId;

    final itemDetails = <OrderItemDetails>[];
    for (final product in orderProducts) {
      final productDetail = await (_database.select(_database.products)
        ..where((tbl) => tbl.id.equals(product.productId)))
          .getSingleOrNull();

      // Get components
      final orderComponents = await (_database.select(_database.orderProductComponents)..where((tbl) => tbl.orderProductId.equals(product.id))).get();

      // Calculate component total using stored prices
      double componentTotal = 0.0;
      final components = <ComponentDetails>[];
      for (final orderComp in orderComponents) {
        componentTotal += orderComp.price * orderComp.quantity;

        final component = await (_database.select(_database.components)..where((tbl) => tbl.id.equals(orderComp.componentId))).getSingleOrNull();
        if (component != null) {
          components.add(ComponentDetails(
            name: component.name,
            quantity: orderComp.quantity,
            price: orderComp.price
          ));
        }
      }

      final productDiscount = ((product.manualDiscount + product.unitaryDiscount) * product.quantity);
      print(componentTotal);
      final itemSubtotal = ((product.unitaryPrice - product.unitaryTva + product.unitaryDiscount)+ componentTotal ) * product.quantity ;
      final itemTva = product.unitaryTva * product.quantity;

      subtotal += itemSubtotal;
      itemDiscount += productDiscount;
      totalTva += itemTva;

      // Check if item is paid (has a ticket)
      bool isPaid = product.ticketId != null;
      String? ticketNum;
      if (isPaid) {
        final ticket = await (_database.select(_database.tickets)..where((tbl) => tbl.id.equals(product.ticketId!))).getSingleOrNull();
        ticketNum = ticket?.num;
        if (ticketId == null || ticketId != ticket?.id) {
          totalPaid += ticket?.amount ?? 0.0;
          ticketId = ticket?.id;
        }
      }

      itemDetails.add(OrderItemDetails(
        productName: productDetail?.name ?? 'Unknown Product',
        quantity: product.quantity,
        totalPrice: itemSubtotal - productDiscount,
        isPaid: isPaid,
        ticketNum: ticketNum,
        components: components,
      ));
    }

    // Calculate manual discount from percentage
    final discountPercentage = order.discountPercentage;
    final manualDiscountAmount = (subtotal + totalTva - itemDiscount) * (discountPercentage / 100);
    final totalDiscount = itemDiscount + manualDiscountAmount;

    // Calculate final total
    final total = subtotal + totalTva - totalDiscount;

    return OrderFullDetails(
      order: order,
      userName: userName,
      tableName: tableName,
      customerName: customerName,
      customerId: customerId,
      productCount: orderProducts.length,
      subtotal: subtotal,
      itemDiscount: itemDiscount,
      discountPercentage: discountPercentage,
      manualDiscountAmount: manualDiscountAmount,
      totalDiscount: totalDiscount,
      totalTva: totalTva,
      total: total,
      totalPaid: totalPaid,
      items: itemDetails,
    );
  }

  // Get full details for a specific order
  Future<OrderFullDetails> getOrderFullDetails(int orderId) async {
    final order = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(orderId))).getSingle();
    return _buildOrderFullDetails(order);
  }

  // Delete an order
  Future<void> deleteOrder(int orderId, {bool queueSyncOperation = true}) async {
    // Check if order was synced to server
    final order = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();

    if (order != null && order.isSynced && queueSyncOperation) {
      // Try to delete from server if online, otherwise queue
      if (_syncService != null && _isOnlineCallback != null) {
        final isOnline = _isOnlineCallback!();
        if (isOnline) {
          try {
            await _syncService!.deleteOrderEntity(
              entityId: orderId,
              orderCode: order.code,
              isOnline: true,
            );
            _logger.info('Deleted order code=${order.code} from server');
          } catch (e) {
            _logger.error('Failed to delete order from server: $e');
            // Queue for later if immediate delete failed
            await _queueOrderDelete(orderId, order.code);
          }
        } else {
          // Offline - queue the delete
          await _queueOrderDelete(orderId, order.code);
        }
      } else {
        // No sync service available - just queue
        await _queueOrderDelete(orderId, order.code);
      }
    } else if (order != null && !order.isSynced) {
      _logger.info('Deleting local-only order #$orderId (not synced, no queue needed)');
    }

    // CASCADE DELETE: Delete all tickets associated with this order
    final tickets = await (_database.select(_database.tickets)..where((tbl) => tbl.orderId.equals(orderId))).get();
    for (final ticket in tickets) {

      // Delete the ticket
      await (_database.delete(_database.tickets)..where((tbl) => tbl.id.equals(ticket.id))).go();
      _logger.info('Deleted ticket #${ticket.id} (num=${ticket.num}) for order #$orderId');
    }

    // Delete order product components first
    final orderProducts = await (_database.select(_database.orderProducts)..where((tbl) => tbl.orderId.equals(orderId))).get();
    for (final product in orderProducts) {
      await (_database.delete(_database.orderProductComponents)..where((tbl) => tbl.orderProductId.equals(product.id))).go();
    }

    // Delete order products
    await (_database.delete(_database.orderProducts)..where((tbl) => tbl.orderId.equals(orderId))).go();

    // Log order deletion BEFORE deleting the order
    if (order != null) {
      await _logService.logOrderDeleted(orderId, 'Order deleted: code=${order.code}');
    }

    // Delete the order
    await (_database.delete(_database.orders)..where((tbl) => tbl.id.equals(orderId))).go();

    // Emit event
    _emitEvent(OrderDeletedEvent(orderId: orderId));
  }

  /// Helper to queue order delete operation
  Future<void> _queueOrderDelete(int orderId, String orderCode) async {
    try {
      final pendingOpsService = PendingOperationsService(_database);
      await pendingOpsService.queueOrderDelete(
        entityId: orderId,
        orderCode: orderCode,
      );
      _logger.info('Queued delete operation for synced order code=$orderCode');
    } catch (e) {
      _logger.error('Failed to queue delete operation: $e');
    }
  }
}

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final database = ref.watch(databaseProvider);
  final repository = OrderRepository(database);

  // Set up sync service and network status callback
  final syncService = ref.watch(dataSyncServiceProvider);
  final isOnline = ref.watch(lastKnownOnlineStatusProvider);
  repository.setSyncService(syncService, () => isOnline);

  return repository;
});




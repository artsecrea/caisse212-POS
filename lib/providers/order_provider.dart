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
import '../services/activity_log_service.dart';
import '../utils/customer_display.dart';
import '../utils/order_code.dart';
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

  /// Adds a weighed (scale) item — always as a distinct line.
  /// quantity=weightKg, unitPrice=pricePerKg for both barcode types.
  void addWeighedItem({
    required int productId,
    required String productName,
    String? imageUrl,
    required double quantity,
    required double unitPrice,
    double weightKg = 0.0,
    double? pricePerKgDisplay,
    String? unitName,
  }) {
    final item = OrderItem(
      productId: productId,
      productName: productName,
      imageUrl: imageUrl,
      finalPrice: unitPrice,
      quantity: quantity,
      isWeighedItem: true,
      weightKg: weightKg,
      pricePerKgDisplay: pricePerKgDisplay,
      unitName: unitName,
    );
    state = state.copyWith(items: [...state.items, item]);
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

  void updateItemQuantity(int index, double quantity) {
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

  // Update table for existing order (used for transfer)
  void updateTable(int? tableId, String? tableName) {
    state = state.copyWith(tableId: tableId, tableName: tableName);
  }

  void clearTable() {
    state = state.copyWith(
      tableId: null,
      tableName: null,
    );
  }

  void setCustomer(int? customerId, String? customerName, {String? customerPhone}) {
    state = state.copyWith(
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
    );
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
      customerPhone: null,
      commercialId: state.commercialId,
      commercialName: state.commercialName,
      waiterId: state.waiterId,
      waiterName: state.waiterName,
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
      waiterId: state.waiterId,
      waiterName: state.waiterName,
      coupon: state.coupon,
      discountPercentage: state.discountPercentage,
      note: state.note,
      type: state.type,
      numberOfPersons: state.numberOfPersons,
    );
  }

  void setWaiter(int? waiterId, String? waiterName) {
    state = state.copyWith(waiterId: waiterId, waiterName: waiterName);
  }

  void clearWaiter() {
    state = CurrentOrder(
      orderId: state.orderId,
      orderCode: state.orderCode,
      items: state.items,
      tableId: state.tableId,
      tableName: state.tableName,
      customerId: state.customerId,
      customerName: state.customerName,
      commercialId: state.commercialId,
      commercialName: state.commercialName,
      waiterId: null,
      waiterName: null,
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

  void setDeliveryAddress(String? address) {
    state = state.copyWith(deliveryAddress: address);
  }

  void setNumberOfPersons(int count) {
    state = state.copyWith(numberOfPersons: count);
  }

  /// Stamps the tip value returned by `PATCH /orders/{id}/tip` onto the
  /// in-memory order. The server is the source of truth; this just keeps
  /// the UI in sync so the tip button label and the payment screen totals
  /// reflect what's saved.
  void setTip(double value) {
    state = state.copyWith(tip: value);
  }

  /// Replace the in-memory order outright with [order]. Used after a save
  /// + reload pass when the caller wants the DB-loaded copy (with
  /// auto-generated ids, etc.) to become the working order.
  void setOrder(CurrentOrder order) {
    state = order;
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
  final Ref? _ref;
  final _logger = Logger.instance;
  late final OrderLogService _logService;

  // Optional sync service and network status callback for auto-sync
  DataSyncService? _syncService;
  bool Function()? _isOnlineCallback;

  OrderRepository(this._database, [this._ref]) {
    _logService = OrderLogService(_database);
  }

  /// Records a user-action audit entry for the current actor (if available).
  void _audit(void Function(ActivityLogService log, int? userId, String? username) action) {
    final ref = _ref;
    if (ref == null) return;
    try {
      final actor = ref.read(currentUserProvider);
      action(ref.read(activityLogServiceProvider), actor?.id, actor?.effectiveDisplayName);
    } catch (e) {
      _logger.error('Activity log failed: $e');
    }
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

  // Returns z_day from the active session (O(1) state read — no DB hit).
  DateTime _currentZDay() {
    final ref = _ref;
    if (ref != null) return ref.read(currentZDayProvider);
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<int> saveOrder(CurrentOrder order, int userId, {String status = 'PENDING', int? sessionId}) async {

    if (order.orderId != null) {
      throw Exception("Order already has an order code, use updateOrder instead.");
    }

    // Check if order has items
    if (order.items.isEmpty) {
      throw Exception("Cannot save order with no items");
    }

    _logger.debug('saveOrder: ${order.items.length} items, first item: ${order.items.first.toJson()}');
    // Generate order code — short uppercase alphanumeric (e.g. RGH7IE3H3LR),
    // consistent with the waiter-app path. Uniqueness is checked just below.
    final orderCode = order.orderCode ?? generateOrderCode();

    // check if the order with that code exists
    final existingOrder = await (_database.select(_database.orders)..where((tbl) => tbl.code.equals(orderCode))).getSingleOrNull();
      if (existingOrder != null) {
        throw Exception("Order with code $orderCode already exists.");
      }

    final zDay = _currentZDay();

    // Insert order
    final orderId = await _database.into(_database.orders).insert(
      OrdersCompanion.insert(
        code: orderCode,
        status: Value(status),
        type: Value(order.type),
        priority: Value(0),
        note: Value(order.note),
        address: Value(order.deliveryAddress),
        tableId: Value(order.tableId),
        source: Value('POS'),
        sourceId: Value(null),
        discountPercentage: Value(order.discountPercentage),
        // Only persist a tip when the cashier actually entered one — keeps
        // the column null for the "no tip recorded" case, matching the
        // backend's `tip: null` semantic.
        tip: order.tip > 0 ? Value(order.tip) : const Value.absent(),
        createdBy: Value(userId),
        takenBy: Value(userId),
        waiterId: Value(order.waiterId),
        persons: Value(order.numberOfPersons),
        clientId: Value(order.customerId),
        commercialId: Value(order.commercialId),
        sessionId: Value(sessionId),
        zDay: Value(zDay),
        date: Value(DateTime.now()),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // Insert order products - set state based on order status
    final itemState = status == 'ONHOLD' ? 'ONHOLD' : 'PENDING';
    for (final item in order.items) {
      final orderProductId = await _database.into(_database.orderProducts).insert(
        OrderProductsCompanion.insert(
          orderId: orderId,
          productId: item.productId,
          variantId: Value(item.variantId),
          quantity: Value(item.quantity),
          unitaryPrice: item.finalPrice,
          unitaryDiscount: Value(item.discount),
          manualDiscount: Value(item.manualDiscount),
          note: Value(item.note),
          unitaryTva: Value(item.tva),
          state: Value(itemState),
          zDay: Value(zDay),
          planStartAt: Value(item.planStartAt),
          planEndAt: Value(item.planEndAt),
          planWaiterId: Value(item.planWaiterId),
          kdsPrintedAt: Value(item.kdsPrintedAt),
          kdsPrintedQuantity: Value(item.kdsPrintedQuantity),
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
    _audit((log, uid, uname) => log.logOrderCreated(orderCode, userId: uid, username: uname));

    // Auto-sync if network is available
    if (_syncService != null && _isOnlineCallback != null) {
      final isOnline = _isOnlineCallback!();
      _logger.debug('Auto-sync on create: online=$isOnline orderCode=$orderCode');
      if (isOnline) {
        try {
          final orderSynced = await _syncService!.syncSingleOrder(orderId);
          if (orderSynced) {
            await _syncService!.syncTicketsForOrder(orderId);
          }
          _logger.info('Auto-synced new $status order code=$orderCode');
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

    final existingOrder = await (_database.select(_database.orders)
      ..where((tbl) => tbl.id.equals(orderId)))
      .getSingleOrNull();

    // Z-report guard: refuse item modifications on orders from a closed session
    if (existingOrder?.sessionId != null) {
      final session = await (_database.select(_database.cashSessions)
            ..where((tbl) => tbl.id.equals(existingOrder!.sessionId!)))
          .getSingleOrNull();
      if (session?.status == 'ended') {
        throw Exception('Cannot modify order from a closed (Z-report) session');
      }
    }

    final wasAlreadySynced = existingOrder?.isSynced ?? false;
    final orderCode = existingOrder?.code ?? order.orderCode ?? '';
    // Preserve the original z_day — re-inserted products must stay on the
    // same Z-day as the order even if the update happens after midnight.
    final orderZDay = existingOrder?.zDay ?? _currentZDay();

    // Count unpaid items to be updated
    final unpaidItems = order.items.where((item) => item.ticketId == null).toList();
    _logger.debug('updateOrder: total items=${order.items.length}, unpaid items=${unpaidItems.length}');
    
    // If there are no unpaid items and no items at all, something is wrong
    if (order.items.isEmpty && unpaidItems.isEmpty) {
      _logger.warning('updateOrder called with zero items - this should not happen');
    }

    // Update order details
    await (_database.update(_database.orders)..where((tbl) => tbl.id.equals(orderId))).write(OrdersCompanion(
      tableId: Value(order.tableId),
      clientId: Value(order.customerId),
      commercialId: Value(order.commercialId),
      waiterId: Value(order.waiterId),
      discountPercentage: Value(order.discountPercentage),
      // Tip — passes `null` when cleared (cashier picked "No tip" on the
      // dialog), so the server's clear-semantic round-trips correctly via
      // the normal order update path.
      tip: Value(order.tip > 0 ? order.tip : null),
      persons: Value(order.numberOfPersons),
      type: Value(order.type),
      note: Value(order.note),
      address: Value(order.deliveryAddress),
      updatedAt: Value(DateTime.now()),

      // Mark as not synced if changes were made to a previously synced order
      isSynced: Value(wasAlreadySynced ? false : existingOrder?.isSynced ?? false),
    ));

    // Snapshot the existing UNPAID lines BEFORE we wipe them, so that after
    // the re-insert below we can diff old vs new and surface which items the
    // cashier dropped (or reduced) in this save. Paid items are filtered out
    // because they're not touched by the update.
    //
    // Key = (productId, variantId ?? -1). Two lines with the same product +
    // variant collapse into one entry whose value is the summed quantity, so
    // a partial reduction (e.g. removing one of two Pizzas) still surfaces.
    final removedSnapshot = <String, double>{};
    final existingUnpaidRows = await (_database.select(_database.orderProducts)
          ..where((t) => t.orderId.equals(orderId) & t.ticketId.isNull()))
        .get();
    for (final row in existingUnpaidRows) {
      final key = '${row.productId}:${row.variantId ?? -1}';
      removedSnapshot[key] = (removedSnapshot[key] ?? 0) + row.quantity;
    }

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
          variantId: Value(item.variantId),
          quantity: Value(item.quantity),
          unitaryPrice: item.finalPrice,
          unitaryDiscount: Value(item.discount),
          manualDiscount: Value(item.manualDiscount),
          note: Value(item.note),
          unitaryTva: Value(item.tva),
          state: Value('PENDING'),
          zDay: Value(orderZDay),
          planStartAt: Value(item.planStartAt),
          planEndAt: Value(item.planEndAt),
          planWaiterId: Value(item.planWaiterId),
          kdsPrintedAt: Value(item.kdsPrintedAt),
          kdsPrintedQuantity: Value(item.kdsPrintedQuantity),
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
          _logger.debug('Auto-sync on update: online=$isOnline orderCode=$orderCode');
          try {
            // Re-sync the entire order with updated products
            final orderSynced = await _syncService!.syncSingleOrder(orderId);
            if (orderSynced) {
              await _syncService!.syncTicketsForOrder(orderId);
            }
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
    _audit((log, uid, uname) => log.logOrderUpdated(orderCode, userId: uid, username: uname));

    // Subtract the new state from the snapshot — anything left is what got
    // removed (whole line dropped OR quantity reduced). We do this AFTER the
    // re-insert so the snapshot map is still untouched by intermediate state.
    for (final item in order.items) {
      if (item.ticketId != null) continue; // paid lines aren't in the snapshot
      final key = '${item.productId}:${item.variantId ?? -1}';
      final remaining = (removedSnapshot[key] ?? 0) - item.quantity;
      if (remaining <= 0) {
        removedSnapshot.remove(key);
      } else {
        removedSnapshot[key] = remaining;
      }
    }
    if (removedSnapshot.isNotEmpty) {
      await _logRemovedItems(orderId, orderCode, removedSnapshot);
    }
  }

  /// Resolves product/variant names for the leftover snapshot entries and
  /// writes both the technical (`OrderLogs`) and audit (`ActivityLogs`) lines.
  /// Wrapped in try/catch — a logging failure must never abort an order save.
  Future<void> _logRemovedItems(
      int orderId, String orderCode, Map<String, double> removed) async {
    try {
      final productIds = <int>{};
      final variantIds = <int>{};
      for (final key in removed.keys) {
        final parts = key.split(':');
        productIds.add(int.parse(parts[0]));
        final vid = int.parse(parts[1]);
        if (vid != -1) variantIds.add(vid);
      }

      final productsById = <int, Product>{};
      if (productIds.isNotEmpty) {
        final rows = await (_database.select(_database.products)
              ..where((t) => t.id.isIn(productIds)))
            .get();
        for (final p in rows) {
          productsById[p.id] = p;
        }
      }
      final variantsById = <int, ProductVariant>{};
      if (variantIds.isNotEmpty) {
        final rows = await (_database.select(_database.productVariants)
              ..where((t) => t.id.isIn(variantIds)))
            .get();
        for (final v in rows) {
          variantsById[v.id] = v;
        }
      }

      final parts = <String>[];
      removed.forEach((key, qty) {
        final split = key.split(':');
        final pid = int.parse(split[0]);
        final vid = int.parse(split[1]);
        final productName = productsById[pid]?.name ?? 'item #$pid';
        final variantName = vid != -1 ? variantsById[vid]?.name : null;
        final label =
            variantName != null ? '$productName ($variantName)' : productName;
        parts.add('$qty× $label');
      });
      final summary = parts.join(', ');

      await _logService.logOrderUpdated(orderId, 'Items removed: $summary');
      _audit((log, uid, uname) =>
          log.logOrderItemsRemoved(orderCode, summary, userId: uid, username: uname));
    } catch (e) {
      _logger.error('Failed to log removed items for order $orderCode: $e');
    }
  }

  /// Helper to queue order update operation.
  ///
  /// CRITICAL: every field the server should see on a queued replay MUST
  /// be in this map. The pending-operations queue does a plain `PUT
  /// /pos/orders/{code}` with this body and nothing else — anything missing
  /// here is silently dropped server-side. Past omissions:
  ///   - `tip` was forgotten and never reached the backend when the cashier
  ///     was offline or the auto-sync hit a transient error and fell back
  ///     to the queue. Adding it here closes that gap.
  ///   - `customerPhoneNormalized` replaces the old `customerId` lookup per
  ///     the latest backend contract — server dedups customers by phone,
  ///     ignores ids on the order payload.
  Future<void> _queueOrderUpdate(int orderId, String orderCode, CurrentOrder order) async {
    try {
      final phoneNormalized = await _lookupCustomerPhoneNormalized(order.customerId);
      final pendingOpsService = PendingOperationsService(_database);
      await pendingOpsService.queueOrderUpdate(
        entityId: orderId,
        orderCode: orderCode,
        updateData: {
          'tableId': order.tableId,
          // Kept for backward compat — server ignores it now, but old
          // server builds still read it. No harm sending both.
          'clientId': order.customerId,
          'customerPhoneNormalized': phoneNormalized,
          'commercialId': order.commercialId,
          'discountPercentage': order.discountPercentage,
          'tip': order.tip,
          'note': order.note,
          'type': order.type,
          'address': order.deliveryAddress,
        },
      );
      _logger.info('Queued update operation for order code=$orderCode');
    } catch (e) {
      _logger.error('Failed to queue update operation: $e');
    }
  }

  /// Resolve the canonical `phone_normalized` for [customerId], or `null`
  /// if there's no customer or the customer has no phone on record. Used
  /// to build order payloads that key customers by phone instead of by id.
  Future<String?> _lookupCustomerPhoneNormalized(int? customerId) async {
    if (customerId == null) return null;
    final row = await (_database.select(_database.customers)
          ..where((c) => c.id.equals(customerId)))
        .getSingleOrNull();
    return row?.phoneNormalized;
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

  /// Find an active product by its MBW / PLU code (string comparison only).
  Future<Product?> findByMbwCode(String plu) async {
    return (_database.select(_database.products)
          ..where((t) => t.mbwCode.equals(plu))
          ..where((t) => t.isActive.equals(true)))
        .getSingleOrNull();
  }

  Future<CurrentOrder?> getOrderByCode(String orderCode) async {
    final order = await (_database.select(_database.orders)..where((tbl) => tbl.code.equals(orderCode))).getSingleOrNull();

    if (order == null) return null;

    return await loadOrderDetails(order);
  }

  Future<CurrentOrder> loadOrderDetails(Order order) async {
    // Batched-fetch rewrite: collapses the previous N+1 pattern
    // (one query per item × product / variant / OPCs / per-component) into
    // ~5 IN(...) queries regardless of order size. Saves the
    // "Continue with table's order" lag on big orders.
    final orderProducts = await (_database.select(_database.orderProducts)
          ..where((tbl) => tbl.orderId.equals(order.id)))
        .get();

    final items = <OrderItem>[];
    if (orderProducts.isNotEmpty) {
      final productIds = orderProducts.map((p) => p.productId).toSet();
      final variantIds = orderProducts
          .where((p) => p.variantId != null)
          .map((p) => p.variantId!)
          .toSet();
      final orderProductIds = orderProducts.map((p) => p.id).toSet();

      // 1) All products in one IN(...) query
      final products = productIds.isEmpty
          ? const <Product>[]
          : await (_database.select(_database.products)
                ..where((t) => t.id.isIn(productIds)))
              .get();
      final productById = {for (final p in products) p.id: p};

      // 2) All variants in one IN(...) query
      final productVariantById = <int, ProductVariant>{};
      if (variantIds.isNotEmpty) {
        final variants = await (_database.select(_database.productVariants)
              ..where((t) => t.id.isIn(variantIds)))
            .get();
        for (final v in variants) {
          productVariantById[v.id] = v;
        }
      }

      // 3) All order_product_components for these order products, grouped
      //    by orderProductId in memory.
      final allOpcs = orderProductIds.isEmpty
          ? const <OrderProductComponent>[]
          : await (_database.select(_database.orderProductComponents)
                ..where((t) => t.orderProductId.isIn(orderProductIds)))
              .get();
      final opcsByOp = <int, List<OrderProductComponent>>{};
      for (final c in allOpcs) {
        opcsByOp.putIfAbsent(c.orderProductId, () => []).add(c);
      }

      // 4) All distinct components those reference, in one query.
      //    The map is left untyped to avoid the name clash between drift's
      //    framework `Component` class and the project's `Component` table
      //    row class — both are visible through the imports above.
      final componentIds = allOpcs.map((c) => c.componentId).toSet();
      final componentById = {
        if (componentIds.isNotEmpty)
          for (final c in await (_database.select(_database.components)
                ..where((t) => t.id.isIn(componentIds)))
              .get())
            c.id: c,
      };

      // 5) Assemble OrderItems from the in-memory lookups — no awaits.
      for (final orderProduct in orderProducts) {
        final product = productById[orderProduct.productId];
        if (product == null) continue; // tolerate orphan rows like before

        String? variantName;
        String? variantImageUrl;
        if (orderProduct.variantId != null) {
          final v = productVariantById[orderProduct.variantId!];
          variantName = v?.name;
          variantImageUrl = v?.imageUrl;
        }

        final components = <OrderItemComponent>[];
        for (final orderComp in opcsByOp[orderProduct.id] ?? const []) {
          final component = componentById[orderComp.componentId];
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
          variantId: orderProduct.variantId,
          variantName: variantName,
          imageUrl: variantImageUrl ?? product.imageUrl,
          finalPrice: orderProduct.unitaryPrice,
          quantity: orderProduct.quantity,
          // Baseline for the decrement floor — cashier can take back only
          // what they added on top of this in the current session.
          savedQuantity: orderProduct.quantity,
          components: components,
          note: orderProduct.note,
          discount: orderProduct.unitaryDiscount,
          manualDiscount: orderProduct.manualDiscount,
          tva: orderProduct.unitaryTva,
          ticketId: orderProduct.ticketId,
          state: orderProduct.state,
          planStartAt: orderProduct.planStartAt,
          planEndAt: orderProduct.planEndAt,
          planWaiterId: orderProduct.planWaiterId,
          kdsPrintedAt: orderProduct.kdsPrintedAt,
          kdsPrintedQuantity: orderProduct.kdsPrintedQuantity,
        ));
      }
    }

    // Get table name
    String? tableName;
    if (order.tableId != null) {
      final table = await (_database.select(_database.areaTables)..where((tbl) => tbl.id.equals(order.tableId!))).getSingleOrNull();
      tableName = table?.name;
    }

    // Get customer name and phone
    String? customerName;
    String? customerPhone;
    if (order.clientId != null) {
      final customer = await (_database.select(_database.customers)..where((tbl) => tbl.id.equals(order.clientId!))).getSingleOrNull();
      if (customer != null) {
        customerName = customer.displayLabel;
        customerPhone = customer.phone;
      }
    }

    // Get commercial name
    String? commercialName;
    if (order.commercialId != null) {
      final commercial = await (_database.select(_database.commercials)..where((tbl) => tbl.id.equals(order.commercialId!))).getSingleOrNull();
      commercialName = commercial != null ? '${commercial.firstName} ${commercial.lastName}' : null;
    }

    // Get waiter name
    String? waiterName;
    if (order.waiterId != null) {
      final waiter = await (_database.select(_database.waiters)..where((tbl) => tbl.id.equals(order.waiterId!))).getSingleOrNull();
      waiterName = waiter != null ? '${waiter.firstName} ${waiter.lastName ?? ''}'.trim() : null;
    }

    int numberOfPersons = order.persons;

    return CurrentOrder(
      orderId: order.id,
      orderCode: order.code,
      items: items,
      numberOfPersons: numberOfPersons,


      tableId: order.tableId,
      tableName: tableName,
      customerId: order.clientId,
      customerName: customerName,
      customerPhone: customerPhone,
      commercialId: order.commercialId,
      commercialName: commercialName,
      waiterId: order.waiterId,
      waiterName: waiterName,
      discountPercentage: order.discountPercentage,
      note: order.note,
      type: order.type,
      deliveryAddress: order.address,
      tip: order.tip ?? 0.0,
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

  Future<void> updateOrderStatus(int orderId, String status, {bool queueSyncOperation = true, String? cancellationReason, int? sessionId, int? userId, int? waiterId}) async {
    // Get current status before updating
    final currentOrder = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();
    final oldStatus = currentOrder?.status ?? '';
    final wasAlreadySynced = currentOrder?.isSynced ?? false;
    final orderCode = currentOrder?.code ?? '';

    // Z-report guard: only COMPLETED (payment finalization) allowed on Z-locked orders
    if (currentOrder?.sessionId != null && status != 'COMPLETED') {
      final session = await (_database.select(_database.cashSessions)
            ..where((tbl) => tbl.id.equals(currentOrder!.sessionId!)))
          .getSingleOrNull();
      if (session?.status == 'ended') {
        throw Exception('Cannot change status of order from a closed (Z-report) session');
      }
    }

    // Stamp sessionId if order has none and caller is providing one (confirmation flow)
    final sessionIdToStamp = (currentOrder?.sessionId == null && sessionId != null)
        ? Value(sessionId)
        : const Value<int?>.absent();

    // On confirmation (ONHOLD → anything else), stamp the confirming user + optional waiter
    final isConfirming = oldStatus == 'ONHOLD' && status != 'ONHOLD';

    // Build the update companion including cancellationReason
    final updateCompanion = OrdersCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
      // Mark as not synced when status changes (except ONHOLD which doesn't sync)
      isSynced: Value(status == 'ONHOLD'),
      // Set cancellation reason when cancelled, clear it otherwise
      cancellationReason: Value(status == 'CANCELED' ? cancellationReason : null),
      sessionId: sessionIdToStamp,
      createdBy: isConfirming && userId != null
          ? Value(userId)
          : const Value<int?>.absent(),
      takenBy: isConfirming && userId != null
          ? Value(userId)
          : const Value<int?>.absent(),
      waiterId: isConfirming && waiterId != null
          ? Value(waiterId)
          : const Value<int?>.absent(),
    );

    await (_database.update(_database.orders)..where((tbl) => tbl.id.equals(orderId))).write(updateCompanion);

    // Handle sync based on status change (skip ONHOLD)
    if (queueSyncOperation && orderCode.isNotEmpty && status != 'ONHOLD') {
      bool syncedSuccessfully = false;

      // Try to sync if online
      if (_syncService != null && _isOnlineCallback != null) {
        final isOnline = _isOnlineCallback!();
        if (isOnline) {
          _logger.debug('Auto-sync on status change: online=$isOnline orderCode=$orderCode newStatus=$status');
          try {
            final orderSynced = await _syncService!.syncSingleOrder(orderId);
            if (orderSynced) {
              await _syncService!.syncTicketsForOrder(orderId);
              syncedSuccessfully = true;
            }
            _logger.info('Synced $status order code=$orderCode');
          } catch (e) {
            _logger.error('Failed to sync $status order: $e');
            // Will queue operation below
          }
        }
      }

      // If order was previously synced and we didn't sync successfully now, queue the update
      if (wasAlreadySynced && !syncedSuccessfully) {
        try {
          final pendingOpsService = PendingOperationsService(_database);
          await pendingOpsService.queueOrderUpdate(
            entityId: orderId,
            orderCode: orderCode,
            updateData: {
              'status': status,
              if (cancellationReason != null) 'cancellationReason': cancellationReason,
            },
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
    _audit((log, uid, uname) {
      if (status == 'CANCELED') {
        log.logOrderCancelled(orderCode,
            userId: uid, username: uname, reason: cancellationReason);
      } else if (isConfirming) {
        log.logOrderConfirmed(orderCode, userId: uid, username: uname);
      } else {
        log.logOrderStatusChanged(orderCode, oldStatus, status,
            userId: uid, username: uname);
      }
    });
  }





  Future<void> setTableOrderId(int tableId, int? orderId) async {
    await (_database.update(_database.areaTables)..where((tbl) => tbl.id.equals(tableId))).write(AreaTablesCompanion(orderId: Value(orderId)));
  }

  // Clear table order assignment (set orderId to null)
  Future<void> clearTableOrder(int tableId) async {
    await setTableOrderId(tableId, null);
  }

  // Transfer order from one table to another
  Future<void> transferOrderToTable(int orderId, int oldTableId, int newTableId) async {
    // Clear old table's orderId
    await clearTableOrder(oldTableId);

    // Set new table's orderId
    await setTableOrderId(newTableId, orderId);

    // Update order's tableId
    await (_database.update(_database.orders)..where((tbl) => tbl.id.equals(orderId))).write(OrdersCompanion(
      tableId: Value(newTableId),
      updatedAt: Value(DateTime.now()),
    ));

    // Log the transfer
    await _logService.logOrderUpdated(orderId, 'Order transferred from table $oldTableId to table $newTableId');
    final transferred = await (_database.select(_database.orders)
          ..where((tbl) => tbl.id.equals(orderId)))
        .getSingleOrNull();
    final transferCode = transferred?.code ?? '#$orderId';
    _audit((log, uid, uname) => log.logOrderTransferred(
        transferCode, '$oldTableId', '$newTableId', userId: uid, username: uname));
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

  /// Local calendar day as 'YYYY-MM-DD' — the stable prefix shared by every
  /// datetime text encoding (legacy UTC/space and current local/'T'). Used to
  /// range-filter on the day rather than the full timestamp, which sorts
  /// inconsistently across encodings.
  static String _dayStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Expression<bool> _dateOnOrAfterDay(
          GeneratedColumn<DateTime> col, DateTime day) =>
      CustomExpression<bool>("substr(${col.name}, 1, 10) >= '${_dayStr(day)}'");

  Expression<bool> _dateOnOrBeforeDay(
          GeneratedColumn<DateTime> col, DateTime day) =>
      CustomExpression<bool>("substr(${col.name}, 1, 10) <= '${_dayStr(day)}'");

  // Get paginated orders with full details - real database-level pagination
  Future<PaginatedOrders> getPaginatedOrdersWithFullDetails({
    required int page,
    required int pageSize,
    String? statusFilter,
    String? typeFilter,
    bool unpaidOnly = false,
    String? searchQuery,
    int? customerId,
    int? cashierId,
    int? tableId,
    int? waiterId,
    int? sessionId,
    DateTime? startDate,
    DateTime? endDate,
    String sortColumn = 'createdAt',
    bool sortAscending = false,
  }) async {
    // Build the base query with filters
    var totalCount = 0;
    // Get total count with filters
    {
      var query = _database.select(_database.orders);

      if (statusFilter != null && statusFilter != 'ALL') {
        query = query..where((tbl) => tbl.status.equals(statusFilter));
      }

      if (typeFilter != null && typeFilter != 'ALL') {
        query = query..where((tbl) => tbl.type.equals(typeFilter));
      }

      if (customerId != null) {
        query = query..where((tbl) => tbl.clientId.equals(customerId));
      }

      if (cashierId != null) {
        query = query..where((tbl) => tbl.takenBy.equals(cashierId));
      }

      if (tableId != null) {
        query = query..where((tbl) => tbl.tableId.equals(tableId));
      }

      if (waiterId != null) {
        query = query..where((tbl) => tbl.waiterId.equals(waiterId));
      }

      if (sessionId != null) {
        query = query..where((tbl) => tbl.sessionId.equals(sessionId));
      }

      // Day-prefix comparison — dates are stored as TEXT and legacy rows may
      // use the UTC/space encoding that sorts before 'T', which would drop
      // same-day orders on the range's start day. See _dayStr / ticket filter.
      if (startDate != null) {
        query = query..where((tbl) => _dateOnOrAfterDay(tbl.date, startDate));
      }

      if (endDate != null) {
        query = query..where((tbl) => _dateOnOrBeforeDay(tbl.date, endDate));
      }

      final allOrders = await query.get();

      // Filter by search query in memory (code and userName need joins)
      List<Order> postSqlOrders = allOrders;
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
              final fullName = customer.displayLabel.toLowerCase();
              if (fullName.contains(searchLower)) {
                filteredOrders.add(order);
              }
            }
          }
        }
        postSqlOrders = filteredOrders;
      }

      // Unpaid-only filter — applied in memory because it compares
      // computed sums (ticket payments vs order line-item totals). Done
      // here in the count phase so totalCount + pagination math match
      // what the data phase will produce.
      if (unpaidOnly) {
        final unpaidOrders = <Order>[];
        for (final order in postSqlOrders) {
          if (await _isOrderUnpaid(order)) {
            unpaidOrders.add(order);
          }
        }
        totalCount = unpaidOrders.length;
      } else {
        totalCount = postSqlOrders.length;
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

    if (typeFilter != null && typeFilter != 'ALL') {
      query = query..where((tbl) => tbl.type.equals(typeFilter));
    }

    if (customerId != null) {
      query = query..where((tbl) => tbl.clientId.equals(customerId));
    }

    if (cashierId != null) {
      query = query..where((tbl) => tbl.takenBy.equals(cashierId));
    }

    if (tableId != null) {
      query = query..where((tbl) => tbl.tableId.equals(tableId));
    }

    if (waiterId != null) {
      query = query..where((tbl) => tbl.waiterId.equals(waiterId));
    }

    if (sessionId != null) {
      query = query..where((tbl) => tbl.sessionId.equals(sessionId));
    }

    if (startDate != null) {
      query = query..where((tbl) => _dateOnOrAfterDay(tbl.date, startDate));
    }

    if (endDate != null) {
      query = query..where((tbl) => _dateOnOrBeforeDay(tbl.date, endDate));
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
            final fullName = customer.displayLabel.toLowerCase();
            if (fullName.contains(searchLower)) {
              ordersToProcess.add(order);
            }
          }
        }
      }
    } else {
      ordersToProcess = allFilteredOrders;
    }

    // Apply unpaid-only filter (in memory — same reasoning as the count
    // phase). Done BEFORE pagination so the page slicing is over the
    // already-filtered set.
    if (unpaidOnly) {
      final unpaidOrders = <Order>[];
      for (final order in ordersToProcess) {
        if (await _isOrderUnpaid(order)) {
          unpaidOrders.add(order);
        }
      }
      ordersToProcess = unpaidOrders;
    }

    // Apply pagination in memory after search
    final start = page * pageSize;
    final end = (start + pageSize).clamp(0, ordersToProcess.length);
    final paginatedOrders = start < ordersToProcess.length
        ? ordersToProcess.sublist(start, end)
        : <Order>[];

    // Batch Z-lock: one query for all session IDs on this page (like tickets' _enrichTickets)
    final sessionIds = paginatedOrders
        .where((o) => o.sessionId != null)
        .map((o) => o.sessionId!)
        .toSet();
    final endedSessionIds = <int>{};
    if (sessionIds.isNotEmpty) {
      final sessions = await (_database.select(_database.cashSessions)
            ..where((s) => s.id.isIn(sessionIds.toList())))
          .get();
      for (final s in sessions) {
        if (s.status == 'ended') endedSessionIds.add(s.id);
      }
    }

    // Build full details for each order
    final result = <OrderFullDetails>[];
    for (final order in paginatedOrders) {
      final fullDetails = await _buildOrderFullDetails(order, endedSessionIds: endedSessionIds);
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

  /// Fetches the small ranked list of orders that the cashier can
  /// "resume" from the empty cart panel.
  ///
  /// Inclusion rule = "the cashier might want to pick this back up":
  ///   * status NOT IN (`COMPLETED`, `CANCELED`)
  ///   * AND ([_isOrderUnpaid] returns true) — i.e. line items haven't
  ///     been fully covered by paid tickets yet. `ONHOLD` orders pass
  ///     this naturally since they have no tickets.
  ///
  /// Filters are pushed into SQL where they're cheap (`type`, `tableId`)
  /// and applied in memory where they need joins (customer-name match).
  /// [customerQuery] does a case-insensitive substring match on the
  /// concatenated first + last name; an empty / null value means "no
  /// customer filter".
  ///
  /// Cap defaults to 50 — the dialog this feeds is meant for "pick the
  /// one you were just working on", not for browsing a long history.
  /// The orders-management screen handles the deep-browse case.
  Future<List<Order>> getUnpaidOrdersForResume({
    String? typeFilter,
    int? tableId,
    String? customerQuery,
    int? cashierId,
    int limit = 50,
  }) async {
    var query = _database.select(_database.orders)
      ..where((tbl) => tbl.status.isNotIn(const ['COMPLETED', 'CANCELED']))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);

    if (typeFilter != null && typeFilter != 'ALL') {
      query = query..where((tbl) => tbl.type.equals(typeFilter));
    }
    if (tableId != null) {
      query = query..where((tbl) => tbl.tableId.equals(tableId));
    }
    if (cashierId != null) {
      query = query..where((tbl) => tbl.takenBy.equals(cashierId));
    }

    final candidates = await query.get();

    final needle = (customerQuery ?? '').trim().toLowerCase();
    final result = <Order>[];
    for (final order in candidates) {
      // Customer-name filter — needs a customers join we can't do in the
      // base select without restructuring, so it runs in memory. Cheap
      // because the SQL where clauses above have already pruned the
      // candidate set.
      if (needle.isNotEmpty) {
        if (order.clientId == null) continue;
        final customer = await (_database.select(_database.customers)
              ..where((c) => c.id.equals(order.clientId!)))
            .getSingleOrNull();
        if (customer == null) continue;
        final fullName =
            '${customer.firstName} ${customer.lastName}'.toLowerCase();
        if (!fullName.contains(needle)) continue;
      }
      if (await _isOrderUnpaid(order)) {
        result.add(order);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  /// Returns the correctly-computed total for each requested order.
  ///
  /// Formula matches [OrderItem.totalPrice] + [CurrentOrder.total]:
  ///   componentTotal = Σ (component.price × component.quantity)
  ///   itemTotal      = (unitaryPrice + componentTotal − manualDiscount) × quantity
  ///   beforeDiscount = Σ itemTotal
  ///   total          = beforeDiscount − (beforeDiscount × discountPct / 100)
  ///
  /// Batched: three queries total (orders, orderProducts,
  /// orderProductComponents) no matter how many ids are passed in.
  /// Empty input or empty order returns 0 for that id.
  ///
  /// Previous version (`_isOrderUnpaid` baseline) summed only
  /// `unitaryPrice × quantity` — dropped every component price, every
  /// manual discount, and the entire order-level discount %, so totals
  /// looked wildly off for any order with paid add-ons (Cheese,
  /// Mushrooms, etc.) or a discount applied.
  Future<Map<int, double>> getOrderTotals(List<int> orderIds) async {
    if (orderIds.isEmpty) return const {};

    final orders = await (_database.select(_database.orders)
          ..where((o) => o.id.isIn(orderIds)))
        .get();
    final discountPctById = {
      for (final o in orders) o.id: o.discountPercentage,
    };

    final products = await (_database.select(_database.orderProducts)
          ..where((p) => p.orderId.isIn(orderIds)))
        .get();
    if (products.isEmpty) {
      return {for (final id in orderIds) id: 0.0};
    }

    final productIds = products.map((p) => p.id).toList();
    final allComps = await (_database.select(_database.orderProductComponents)
          ..where((c) => c.orderProductId.isIn(productIds)))
        .get();
    final compsByProductId = <int, List<OrderProductComponent>>{};
    for (final c in allComps) {
      compsByProductId.putIfAbsent(c.orderProductId, () => []).add(c);
    }

    final beforeDiscount = <int, double>{};
    for (final p in products) {
      final comps = compsByProductId[p.id] ?? const <OrderProductComponent>[];
      final componentTotal = comps.fold<double>(
        0.0,
        (sum, c) => sum + (c.price * c.quantity),
      );
      final itemTotal =
          ((p.unitaryPrice + componentTotal) - p.manualDiscount) * p.quantity;
      beforeDiscount[p.orderId] =
          (beforeDiscount[p.orderId] ?? 0) + itemTotal;
    }

    final result = <int, double>{};
    for (final id in orderIds) {
      final before = beforeDiscount[id] ?? 0;
      final pct = discountPctById[id] ?? 0;
      result[id] = before - (before * pct / 100);
    }
    return result;
  }

  /// "Is this order unpaid?" — the canonical check used by the orders-
  /// management unpaid-filter chip and by the resume-order picker.
  ///
  /// Cancelled orders report as paid (so the filter doesn't surface
  /// them as "needs payment" — they're done). Uses [getOrderTotals]
  /// internally so the math matches what the payment screen, the cart,
  /// and the printed receipt all see.
  Future<bool> _isOrderUnpaid(Order order) async {
    if (order.status == 'CANCELED') return false;
    final totals = await getOrderTotals([order.id]);
    final total = totals[order.id] ?? 0.0;
    if (total <= 0) return false; // empty order isn't "unpaid"
    final tickets = await (_database.select(_database.tickets)
          ..where((t) =>
              t.orderId.equals(order.id) &
              t.isPaid.equals(true) &
              t.isCancelled.equals(false)))
        .get();
    final totalPaid =
        tickets.fold<double>(0.0, (sum, t) => sum + t.amount);
    // Tiny epsilon so floating-point rounding doesn't classify a fully-
    // paid order as unpaid by a penny.
    return totalPaid + 0.005 < total;
  }

  // Helper method to build OrderFullDetails from an Order
  Future<OrderFullDetails> _buildOrderFullDetails(Order order, {Set<int>? endedSessionIds}) async {
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

    // Get customer name and phone
    String? customerName;
    String? customerPhone;
    int? customerId;
    if (order.clientId != null) {
      final customer = await (_database.select(_database.customers)..where((tbl) => tbl.id.equals(order.clientId!))).getSingleOrNull();
      if (customer != null) {
        customerName = customer.displayLabel;
        customerPhone = customer.phone;
        customerId = customer.id;
      }
    }

    // Calculate totals
    double subtotal = 0.0;
    double itemDiscount = 0.0;
    double totalTva = 0.0;
    double totalPaid = 0.0;
    final seenTicketIds = <int>{};

    final itemDetails = <OrderItemDetails>[];
    for (final product in orderProducts) {
      final productDetail = await (_database.select(_database.products)
        ..where((tbl) => tbl.id.equals(product.productId)))
          .getSingleOrNull();

      // Get variant details if variantId exists
      String? variantName;
      if (product.variantId != null) {
        final variant = await (_database.select(_database.productVariants)..where((tbl) => tbl.id.equals(product.variantId!))).getSingleOrNull();
        variantName = variant?.name;
      }

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

      // unitaryPrice = basePrice + tva - preDiscount (all baked in).
      // Subtract unitaryTva so subtotal is tax-exclusive (HT); totalTva is added
      // back later in the final total formula to avoid double-counting.
      // productDiscount covers both the pre-discount and any manual discount.
      // totalPrice = itemSubtotal + totalTva - productDiscount
      //            = (unitaryPrice - unitaryTva + unitaryDiscount + componentTotal) * qty + tva*qty - (unitaryDiscount + manualDiscount) * qty
      //            = (unitaryPrice + componentTotal - manualDiscount) * qty  ✓
      final productDiscount = (product.unitaryDiscount + product.manualDiscount) * product.quantity;
      final itemSubtotal = (product.unitaryPrice - product.unitaryTva + product.unitaryDiscount + componentTotal) * product.quantity;
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
        if (ticket != null && !seenTicketIds.contains(ticket.id)) {
          seenTicketIds.add(ticket.id);
          totalPaid += ticket.amount;
        }
      }

      itemDetails.add(OrderItemDetails(
        productName: productDetail?.name ?? 'Unknown Product',
        variantId: product.variantId,
        variantName: variantName,
        quantity: product.quantity,
        totalPrice: itemSubtotal + itemTva - productDiscount,
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

    bool isZLocked = false;
    if (order.sessionId != null) {
      if (endedSessionIds != null) {
        isZLocked = endedSessionIds.contains(order.sessionId!);
      } else {
        final session = await (_database.select(_database.cashSessions)
              ..where((tbl) => tbl.id.equals(order.sessionId!)))
            .getSingleOrNull();
        isZLocked = session?.status == 'ended';
      }
    }

    return OrderFullDetails(
      order: order,
      userName: userName,
      tableName: tableName,
      customerName: customerName,
      customerPhone: customerPhone,
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
      isZLocked: isZLocked,
    );
  }

  // Get full details for a specific order
  Future<OrderFullDetails> getOrderFullDetails(int orderId) async {
    final order = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(orderId))).getSingle();
    return _buildOrderFullDetails(order);
  }

  // Delete an order
  Future<void> deleteOrder(int orderId, {bool queueSyncOperation = true}) async {
    final order = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();

    // Z-report guard: refuse deletes on orders from a closed session
    if (order?.sessionId != null) {
      final session = await (_database.select(_database.cashSessions)
            ..where((tbl) => tbl.id.equals(order!.sessionId!)))
          .getSingleOrNull();
      if (session?.status == 'ended') {
        throw Exception('Cannot delete order from a closed (Z-report) session');
      }
    }


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
  final repository = OrderRepository(database, ref);

  // Set up sync service and network status callback.
  // Use ref.read inside the callback so it always returns the CURRENT online state,
  // rather than capturing a stale value at provider creation time.
  final syncService = ref.watch(dataSyncServiceProvider);
  repository.setSyncService(syncService, () => ref.read(lastKnownOnlineStatusProvider));

  return repository;
});








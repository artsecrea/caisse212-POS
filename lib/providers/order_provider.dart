import 'dart:async';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import '../domain/models/order_models.dart';
import '../data/database/app_database.dart';
import '../domain/models/order_events.dart';
import 'package:uuid/uuid.dart';
import 'database_providers.dart';

// Current Order State Provider
class OrderNotifier extends StateNotifier<CurrentOrder> {
  OrderNotifier() : super(CurrentOrder());

  void addItem(OrderItem item) {
    state = state.copyWith(
      items: [...state.items, item],
    );
  }

  void removeItem(int index) {
    final items = List<OrderItem>.from(state.items);
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
    items[index] = item;
    state = state.copyWith(items: items);
  }

  void setTable(int? tableId, String? tableName) {
    clearOrder();
    state = state.copyWith(tableId: tableId, tableName: tableName);
  }

  void setCustomer(int? customerId, String? customerName) {
    state = state.copyWith(customerId: customerId, customerName: customerName);
  }

  void setCommercial(int? commercialId, String? commercialName) {
    state = state.copyWith(commercialId: commercialId, commercialName: commercialName);
  }

  void setCoupon(String? coupon) {
    state = state.copyWith(coupon: coupon);
  }

  void setNote(String? note) {
    state = state.copyWith(note: note);
  }

  void setOrderType(String type) {
    state = state.copyWith(type: type);
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

  OrderRepository(this._database);

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
    // Generate order code
    final uuid = const Uuid();
    final orderCode = uuid.v4().substring(0, 8).toUpperCase();

    // Insert order
    final orderId = await _database.into(_database.orders).insert(
      OrdersCompanion.insert(
        code: orderCode,
        status: Value(status),
        type: Value(order.type),
        priority: Value(0),
        coupon: Value(order.coupon),
        note: Value(order.note),
        tableId: Value(order.tableId),
        source: Value('POS'),
        sourceId: Value(null),
        createdBy: Value(userId),
        takenBy: Value(userId),
        clientId: Value(order.customerId),
        commercialId: Value(order.commercialId),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // Insert order products
    for (final item in order.items) {
      final orderProductId = await _database.into(_database.orderProducts).insert(
        OrderProductsCompanion.insert(
          orderId: orderId,
          productId: item.productId,
          quantity: Value(item.quantity),
          unitaryPrice: item.unitPrice,
          unitaryDiscount: Value(item.discount),
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

    return orderId;
  }

  Future<int> holdOrder(CurrentOrder order, int userId) async {
    final orderId = await saveOrder(order, userId, status: 'ONHOLD');

    // Get order code
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

  Future<void> updateOrder( CurrentOrder order) async {

    int orderId = order.orderId!;
    // Update order details
    await (_database.update(_database.orders)..where((tbl) => tbl.id.equals(orderId))).write(OrdersCompanion(
      tableId: Value(order.tableId),
      clientId: Value(order.customerId),
      commercialId: Value(order.commercialId),
      coupon: Value(order.coupon),
      note: Value(order.note),
      updatedAt: Value(DateTime.now()),
    ));

    // Delete existing order products
    await (_database.delete(_database.orderProducts)..where((tbl) => tbl.orderId.equals(orderId))..where((tbl) => tbl.ticketId.isNull())).go();

    // Insert new order products
    for (final item in order.items) {
      if (item.ticketId != null) {
        // Skip items that are already ticketed
        _logger.debug("continue");
        continue;
      }
      final orderProductId = await _database.into(_database.orderProducts).insert(
        OrderProductsCompanion.insert(
          orderId: orderId,
          productId: item.productId,
          quantity: Value(item.quantity),
          unitaryPrice: item.unitPrice,
          unitaryDiscount: Value(item.discount),
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
            isSpecial: Value(component.isSpecial),
          ),
        );
      }
    }

    // Emit event
    _emitEvent(OrderUpdatedEvent(orderId: orderId));
    _emitEvent(OrderItemsChangedEvent(
      orderId: orderId,
      itemCount: order.items.length,
    ));
  }

  Future<CurrentOrder?> getOrderByTable(int tableId) async {
    // Get the most recent ONHOLD order for this table
    final table = await (_database.select(_database.areaTables)..where((tbl) => tbl.id.equals(tableId))).getSingleOrNull();

    if (table == null || table.orderId == null) return null;

    final order = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(table.orderId!))).getSingleOrNull();

    if (order == null) return null;

    return await loadOrderDetails(order);
  }

  Future<CurrentOrder?> getOrderById(int orderId) async {
    final order = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();

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
            price: component.price,
            isSpecial: orderComp.isSpecial,
          ));
        }
      }

      items.add(OrderItem(
        id: orderProduct.id,
        productId: product.id,
        productName: product.name,
        imageUrl: product.imageUrl,
        unitPrice: orderProduct.unitaryPrice,
        quantity: orderProduct.quantity,
        components: components,
        discount: orderProduct.unitaryDiscount,
        tva: orderProduct.unitaryTva,
        ticketId: orderProduct.ticketId,
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

    return CurrentOrder(
      orderId: order.id,
      items: items,
      tableId: order.tableId,
      tableName: tableName,
      customerId: order.clientId,
      customerName: customerName,
      commercialId: order.commercialId,
      commercialName: commercialName,
      coupon: order.coupon,
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

  Future<void> updateOrderStatus(int orderId, String status) async {
    // Get current status before updating
    final currentOrder = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();
    final oldStatus = currentOrder?.status ?? '';

    await (_database.update(_database.orders)..where((tbl) => tbl.id.equals(orderId))).write(OrdersCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
    ));

    // Emit event
    _emitEvent(OrderStatusChangedEvent(
      orderId: orderId,
      oldStatus: oldStatus,
      newStatus: status,
    ));
  }





  Future<void> setTableOrderId(int tableId, int? orderId) async {
    await (_database.update(_database.areaTables)..where((tbl) => tbl.id.equals(tableId))).write(AreaTablesCompanion(orderId: Value(orderId)));
  }

  // Get all orders with full details including user, products, discounts, TVA, and paid amounts
  Future<List<OrderFullDetails>> getAllOrdersWithFullDetails() async {
    final orders = await (_database.select(_database.orders)..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)])).get();

    final result = <OrderFullDetails>[];
    for (final order in orders) {
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

      // Calculate totals
      double subtotal = 0.0;
      double totalDiscount = 0.0;
      double totalTva = 0.0;
      double totalPaid = 0.0;

      final itemDetails = <OrderItemDetails>[];
      for (final product in orderProducts) {
        final productDetail = await (_database.select(_database.products)..where((tbl) => tbl.id.equals(product.productId))).getSingleOrNull();

        final itemSubtotal = product.unitaryPrice - product.unitaryTva * product.quantity ;
        final itemDiscount = product.unitaryDiscount * product.quantity;
        final itemTva = product.unitaryTva * product.quantity;

        subtotal += itemSubtotal;
        totalDiscount += itemDiscount;
        totalTva += itemTva;

        // Check if item is paid (has a ticket)
        bool isPaid = product.ticketId != null;
        String? ticketNum;
        if (isPaid) {
          final ticket = await (_database.select(_database.tickets)..where((tbl) => tbl.id.equals(product.ticketId!))).getSingleOrNull();
          ticketNum = ticket?.num;
          totalPaid += itemSubtotal - itemDiscount + itemTva;
        }

        // Get components
        final orderComponents = await (_database.select(_database.orderProductComponents)..where((tbl) => tbl.orderProductId.equals(product.id))).get();
        final components = <ComponentDetails>[];
        for (final orderComp in orderComponents) {
          final component = await (_database.select(_database.components)..where((tbl) => tbl.id.equals(orderComp.componentId))).getSingleOrNull();
          if (component != null) {
            components.add(ComponentDetails(
              name: component.name,
              quantity: orderComp.quantity,
            ));
          }
        }

        itemDetails.add(OrderItemDetails(
          productName: productDetail?.name ?? 'Unknown Product',
          quantity: product.quantity,
          totalPrice: itemSubtotal - itemDiscount,
          isPaid: isPaid,
          ticketNum: ticketNum,
          components: components,
        ));
      }

      final total = subtotal  + totalTva;

      result.add(OrderFullDetails(
        order: order,
        userName: userName,
        tableName: tableName,
        productCount: orderProducts.length,
        subtotal: subtotal,
        totalDiscount: totalDiscount,
        totalTva: totalTva,
        total: total,
        totalPaid: totalPaid,
        items: itemDetails,
      ));
    }

    return result;
  }

  // Get full details for a specific order
  Future<OrderFullDetails> getOrderFullDetails(int orderId) async {
    final order = await (_database.select(_database.orders)..where((tbl) => tbl.id.equals(orderId))).getSingle();

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

    // Calculate totals
    double subtotal = 0.0;
    double totalDiscount = 0.0;
    double totalTva = 0.0;
    double totalPaid = 0.0;

    final itemDetails = <OrderItemDetails>[];
    for (final product in orderProducts) {
      final productDetail = await (_database.select(_database.products)..where((tbl) => tbl.id.equals(product.productId))).getSingleOrNull();

      final itemSubtotal = product.unitaryPrice * product.quantity;
      final itemDiscount = product.unitaryDiscount * product.quantity;
      final itemTva = product.unitaryTva * product.quantity;

      subtotal += itemSubtotal;
      totalDiscount += itemDiscount;
      totalTva += itemTva;

      // Check if item is paid (has a ticket)
      bool isPaid = product.ticketId != null;
      String? ticketNum;
      if (isPaid) {
        final ticket = await (_database.select(_database.tickets)..where((tbl) => tbl.id.equals(product.ticketId!))).getSingleOrNull();
        ticketNum = ticket?.num;
        totalPaid += itemSubtotal - itemDiscount + itemTva;
      }

      // Get components
      final orderComponents = await (_database.select(_database.orderProductComponents)..where((tbl) => tbl.orderProductId.equals(product.id))).get();
      final components = <ComponentDetails>[];
      for (final orderComp in orderComponents) {
        final component = await (_database.select(_database.components)..where((tbl) => tbl.id.equals(orderComp.componentId))).getSingleOrNull();
        if (component != null) {
          components.add(ComponentDetails(
            name: component.name,
            quantity: orderComp.quantity,
          ));
        }
      }

      itemDetails.add(OrderItemDetails(
        productName: productDetail?.name ?? 'Unknown Product',
        quantity: product.quantity,
        totalPrice: itemSubtotal - itemDiscount + itemTva,
        isPaid: isPaid,
        ticketNum: ticketNum,
        components: components,
      ));
    }

    final total = subtotal - totalDiscount + totalTva;

    return OrderFullDetails(
      order: order,
      userName: userName,
      tableName: tableName,
      productCount: orderProducts.length,
      subtotal: subtotal,
      totalDiscount: totalDiscount,
      totalTva: totalTva,
      total: total,
      totalPaid: totalPaid,
      items: itemDetails,
    );
  }

  // Delete an order
  Future<void> deleteOrder(int orderId) async {
    // Delete order product components first
    final orderProducts = await (_database.select(_database.orderProducts)..where((tbl) => tbl.orderId.equals(orderId))).get();
    for (final product in orderProducts) {
      await (_database.delete(_database.orderProductComponents)..where((tbl) => tbl.orderProductId.equals(product.id))).go();
    }

    // Delete order products
    await (_database.delete(_database.orderProducts)..where((tbl) => tbl.orderId.equals(orderId))).go();

    // Delete the order
    await (_database.delete(_database.orders)..where((tbl) => tbl.id.equals(orderId))).go();

    // Emit event
    _emitEvent(OrderDeletedEvent(orderId: orderId));
  }
}

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return OrderRepository(database);
});


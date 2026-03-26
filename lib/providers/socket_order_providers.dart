import 'package:drift/drift.dart' hide Column;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import '../domain/models/socket_models.dart';
import 'database_providers.dart';

// Stream all orders
final allOrdersStreamProvider = StreamProvider<List<Order>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.orders)
    ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)])
    ..watch())
      .watch();
});

// Stream orders by status
final ordersByStatusProvider = StreamProvider.family<List<Order>, String>((ref, status) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.orders)
    ..where((tbl) => tbl.status.equals(status))
    ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)])
    ..watch()).watch();
});

// Stream pending orders (not delivered)
final pendingOrdersStreamProvider = StreamProvider<List<Order>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.orders)
    ..where((tbl) => tbl.status.isNotIn(['DELIVERED']))
    ..orderBy([
      (tbl) => OrderingTerm.desc(tbl.priority),
      (tbl) => OrderingTerm.asc(tbl.createdAt)
    ])
    ..watch()).watch();
});

// Stream single order
final orderStreamProvider = StreamProvider.family<Order?, int>((ref, orderId) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.orders)
    ..where((tbl) => tbl.id.equals(orderId))
    ..watch()).watchSingleOrNull();
});

// Stream order products for an order
final orderProductsStreamProvider = StreamProvider.family<List<OrderProduct>, int>((ref, orderId) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.orderProducts)
    ..where((tbl) => tbl.orderId.equals(orderId))
    ..watch()).watch();
});

// Order Repository for socket model conversion
class SocketOrderRepository {
  final AppDatabase _database;

  SocketOrderRepository(this._database);

  Future<SocketOrderModel?> getOrderWithDetails(int orderId) async {
    // Get order
    final order = await (_database.select(_database.orders)
      ..where((tbl) => tbl.id.equals(orderId)))
        .getSingleOrNull();

    if (order == null) return null;

    // Get table name if exists
    String? tableName;
    if (order.tableId != null) {
      final table = await (_database.select(_database.areaTables)
        ..where((tbl) => tbl.id.equals(order.tableId!)))
          .getSingleOrNull();
      tableName = table?.name;
    }

    // Get client name if exists
    String? clientName;
    if (order.clientId != null) {
      final client = await (_database.select(_database.customers)
        ..where((tbl) => tbl.id.equals(order.clientId!)))
          .getSingleOrNull();
      clientName = client != null ? '${client.firstName} ${client.lastName}' : null;
    }

    // Get order products
    final orderProducts = await (_database.select(_database.orderProducts)
      ..where((tbl) => tbl.orderId.equals(orderId)))
        .get();

    final socketProducts = <SocketOrderProductModel>[];
    for (final orderProduct in orderProducts) {
      // Get product details
      final product = await (_database.select(_database.products)
        ..where((tbl) => tbl.id.equals(orderProduct.productId)))
          .getSingleOrNull();

      if (product == null) continue;

      // Get station info if exists
      String? stationName;
      if (product.stationId != null) {
        final station = await (_database.select(_database.stations)
          ..where((tbl) => tbl.id.equals(product.stationId!)))
            .getSingleOrNull();
        stationName = station?.name;
      }

      // Get components
      final orderComponents = await (_database.select(_database.orderProductComponents)
        ..where((tbl) => tbl.orderProductId.equals(orderProduct.id)))
          .get();

      final socketComponents = <SocketOrderProductComponentModel>[];
      for (final orderComp in orderComponents) {
        final component = await (_database.select(_database.components)
          ..where((tbl) => tbl.id.equals(orderComp.componentId)))
            .getSingleOrNull();

        if (component != null) {
          socketComponents.add(SocketOrderProductComponentModel(
            componentId: component.id,
            componentName: component.name,
            quantity: orderComp.quantity,
            isSpecial: orderComp.isSpecial,
          ));
        }
      }

      socketProducts.add(SocketOrderProductModel(
        id: orderProduct.id,
        productId: product.id,
        variantId: orderProduct.variantId,
        productName: product.name,
        imageUrl: product.imageUrl,
        quantity: orderProduct.quantity,
        unitaryPrice: orderProduct.unitaryPrice,
        state: orderProduct.state,
        stationId: product.stationId,
        stationName: stationName,
        components: socketComponents,
        note: orderProduct.note,
      ));
    }

    return SocketOrderModel(
      id: order.id,
      code: order.code,
      status: order.status,
      type: order.type,

      priority: order.priority,
      date: order.date,
      tableId: order.tableId,
      tableName: tableName,
      clientId: order.clientId,
      clientName: clientName,
      products: socketProducts,
      note: order.note,
    );
  }

  Stream<List<SocketOrderModel>> watchOrdersWithDetails() async* {
    await for (final orders in (_database.select(_database.orders)
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)])
      ..watch()).watch()) {

      final socketOrders = <SocketOrderModel>[];
      for (final order in orders) {
        final socketOrder = await getOrderWithDetails(order.id);
        if (socketOrder != null) {
          socketOrders.add(socketOrder);
        }
      }
      yield socketOrders;
    }
  }

  Stream<List<SocketOrderModel>> watchPendingOrdersWithDetails() async* {
    await for (final orders in (_database.select(_database.orders)
      ..where((tbl) => tbl.status.isNotIn(['DELIVERED']))
      ..orderBy([
        (tbl) => OrderingTerm.desc(tbl.priority),
        (tbl) => OrderingTerm.asc(tbl.createdAt)
      ])
      ..watch()).watch()) {

      final socketOrders = <SocketOrderModel>[];
      for (final order in orders) {
        final socketOrder = await getOrderWithDetails(order.id);
        if (socketOrder != null) {
          socketOrders.add(socketOrder);
        }
      }
      yield socketOrders;
    }
  }

  Stream<SocketOrderModel?> watchOrderWithDetails(int orderId) async* {
    await for (final order in (_database.select(_database.orders)
      ..where((tbl) => tbl.id.equals(orderId))
      ..watch()).watchSingleOrNull()) {

      if (order == null) {
        yield null;
        continue;
      }

      yield await getOrderWithDetails(order.id);
    }
  }

  // Get orders by station
  Future<List<SocketOrderModel>> getOrdersByStation(int stationId) async {
    final orders = await (_database.select(_database.orders)
      ..where((tbl) => tbl.status.isNotIn(['DELIVERED']))
      ..orderBy([
        (tbl) => OrderingTerm.desc(tbl.priority),
        (tbl) => OrderingTerm.asc(tbl.createdAt)
      ]))
        .get();

    final stationOrders = <SocketOrderModel>[];
    for (final order in orders) {
      final orderProducts = await (_database.select(_database.orderProducts)
        ..where((tbl) => tbl.orderId.equals(order.id)))
          .get();

      // Check if any product belongs to this station
      bool hasStationProduct = false;
      for (final orderProduct in orderProducts) {
        final product = await (_database.select(_database.products)
          ..where((tbl) => tbl.id.equals(orderProduct.productId)))
            .getSingleOrNull();

        if (product?.stationId == stationId) {
          hasStationProduct = true;
          break;
        }
      }

      if (hasStationProduct) {
        final socketOrder = await getOrderWithDetails(order.id);
        if (socketOrder != null) {
          // Filter products to only include those for this station
          final filteredProducts = <SocketOrderProductModel>[];
          for (final product in socketOrder.products) {
            if (product.stationId == stationId) {
              filteredProducts.add(product);
            }
          }

          if (filteredProducts.isNotEmpty) {
            stationOrders.add(
                SocketOrderModel(
              id: socketOrder.id,
              code: socketOrder.code,
              status: socketOrder.status,
              type: socketOrder.type,
              priority: socketOrder.priority,
              date: socketOrder.date,
              tableId: socketOrder.tableId,
              tableName: socketOrder.tableName,
              clientId: socketOrder.clientId,
              clientName: socketOrder.clientName,
              products: filteredProducts,
              note: socketOrder.note,
            ));
          }
        }
      }
    }

    return stationOrders;
  }

  Stream<List<SocketOrderModel>> watchOrdersByStation(int stationId) async* {
    await for (final _ in (_database.select(_database.orders)
      ..where((tbl) => tbl.status.isNotIn(['DELIVERED']))
      ..orderBy([
        (tbl) => OrderingTerm.desc(tbl.priority),
        (tbl) => OrderingTerm.asc(tbl.createdAt)
      ])
      ..watch()).watch()) {

      yield await getOrdersByStation(stationId);
    }
  }

  // Update order product state
  Future<void> updateOrderProductState(int orderProductId, String state) async {
    await (_database.update(_database.orderProducts)
      ..where((tbl) => tbl.id.equals(orderProductId)))
        .write(OrderProductsCompanion(
          state: Value(state),
          updatedAt: Value(DateTime.now()),
        ));
  }

  // Update order status
  Future<void> updateOrderStatus(int orderId, String status) async {
    await (_database.update(_database.orders)
      ..where((tbl) => tbl.id.equals(orderId)))
        .write(OrdersCompanion(
          status: Value(status),
          updatedAt: Value(DateTime.now()),
        ));
  }
}

final socketOrderRepositoryProvider = Provider<SocketOrderRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return SocketOrderRepository(database);
});

// Stream providers for socket order models
final allSocketOrdersStreamProvider = StreamProvider<List<SocketOrderModel>>((ref) {
  final repository = ref.watch(socketOrderRepositoryProvider);
  return repository.watchOrdersWithDetails();
});

final pendingSocketOrdersStreamProvider = StreamProvider<List<SocketOrderModel>>((ref) {
  final repository = ref.watch(socketOrderRepositoryProvider);
  return repository.watchPendingOrdersWithDetails();
});

final socketOrderStreamProvider = StreamProvider.family<SocketOrderModel?, int>((ref, orderId) {
  final repository = ref.watch(socketOrderRepositoryProvider);
  return repository.watchOrderWithDetails(orderId);
});

final socketOrdersByStationProvider = StreamProvider.family<List<SocketOrderModel>, int>((ref, stationId) {
  final repository = ref.watch(socketOrderRepositoryProvider);
  return repository.watchOrdersByStation(stationId);
});


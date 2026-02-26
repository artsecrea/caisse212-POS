/**
 * HTTP Server service using Shelf and Shelf Router
 * Handles incoming HTTP requests for order management and KDS communication
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database/app_database.dart';
import '../domain/models/socket_models.dart';
import '../providers/database_providers.dart';
import '../providers/settings_provider.dart';
import 'order_log_service.dart';
import 'package:drift/drift.dart' as drift;

class ServerService {
  final Ref _ref;
  HttpServer? _server;
  int _port;
  String? _serverPassword;
  bool _isRunning = false;

  ServerService(this._ref, {int port = 8080}) : _port = port;

  /// Start the HTTP server
  Future<void> start({int? port, String? password}) async {
    if (_isRunning) {
      print('⚠️ Server already running on port $_port');
      return;
    }

    if (port != null) _port = port;
    _serverPassword = password;

    final router = _buildRouter();
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_corsMiddleware())
        .addMiddleware(_authMiddleware())
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
      _isRunning = true;
      print('✅ Server started on http://${_server!.address.host}:${_server!.port}');
    } catch (e) {
      print('❌ Failed to start server: $e');
      rethrow;
    }
  }

  /// Stop the HTTP server
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      _isRunning = false;
      print('🛑 Server stopped');
    }
  }

  /// Build the router with all endpoints
  Router _buildRouter() {
    final router = Router();

    // Health check
    router.get('/health', _healthCheck);

    // router.post('/login', _login)

    // Order endpoints
    router.get('/orders', _getOrders);
    router.post('/orders', _createOrder);
    router.put('/orders/<orderId>', _updateOrder);
    router.put('/orders/products/<id>', _updateOrderProduct);
    router.get('/stations', _getStations);

    // Catch-all for 404
    router.all('/<ignored|.*>', _notFound);

    return router;
  }

  /// CORS Middleware
  Middleware _corsMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }

        final response = await innerHandler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  /// Authentication Middleware
  Middleware _authMiddleware() {
    return (Handler innerHandler) {
      return (Request request) async {
        // Skip auth for health check
        if (request.url.path == 'health') {
          return innerHandler(request);
        }

        // Check password if configured
        if (_serverPassword != null && _serverPassword!.isNotEmpty) {
          final authHeader = request.headers['x-server-password'];
          if (authHeader != _serverPassword) {
            return Response.forbidden(
              jsonEncode({'error': 'Invalid or missing server password'}),
              headers: {'Content-Type': 'application/json'},
            );
          }
        }

        return innerHandler(request);
      };
    };
  }

  Map<String, String> get _corsHeaders => {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, X-Server-Password',
      };

  // ==================== ENDPOINT HANDLERS ====================

  /// Health check endpoint
  Future<Response> _healthCheck(Request request) async {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'timestamp': DateTime.now().toIso8601String(),
        'port': _port,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }



  /// GET /orders/?since=date&updated_after_log_id=int&station=string
  /// Returns: orders (new orders), orders_updated (full updated orders), orders_deleted (deleted order IDs)
  Future<Response> _getOrders(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final queryParams = request.url.queryParameters;

      // Parse query parameters
      final sinceStr = queryParams['since'];
      final afterIdStr = queryParams['after_id'];
      final updatedAfterLogIdStr = queryParams['updated_after_log_id'];
      final stationName = queryParams['station'];
      final statusStr = queryParams['status'];

      DateTime? since;
      int? updatedAfterLogId;
      final afterId = int.tryParse(afterIdStr ?? '');
      List<String> status = statusStr != null ? statusStr.split(',').map((s) => s.trim().toUpperCase()).toList() : [];

      // Parse since date
      if (sinceStr != null) {
        try {
          since = DateTime.parse(sinceStr);
        } catch (e) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Invalid date format for "since" parameter'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }


      // Parse updated_after_log_id
      if (updatedAfterLogIdStr != null) {
        updatedAfterLogId = int.tryParse(updatedAfterLogIdStr);
        if (updatedAfterLogId == null) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Invalid integer for "updated_after_log_id" parameter'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // Default to today if no parameters provided
      if (since == null && updatedAfterLogId == null) {
        final now = DateTime.now();
        since = DateTime(now.year, now.month, now.day);
      }

      // Get new orders (created today or since specific date)
      var ordersQuery = database.select(database.orders).join([]);
      if (since != null) {
        ordersQuery = ordersQuery..where(database.orders.createdAt.isBiggerOrEqualValue(since));
      }
      if (status.isNotEmpty) {
        ordersQuery = ordersQuery..where(database.orders.status.isIn(status));
      }
      if(afterId != null) {
        ordersQuery = ordersQuery..where(database.orders.id.isBiggerThanValue(afterId));
      }

      final ordersData = await ordersQuery.get();
      final newOrders = ordersData.map((row) => row.readTable(database.orders)).toList();

      // Get updated order IDs from logs
      // Get updated order IDs from logs
      List<int> updatedOrderIds= [];

      if (updatedAfterLogId != null) {
        updatedOrderIds = await logService.getUpdatedOrdersSinceLogId(updatedAfterLogId);
      } else {
        updatedOrderIds = await logService.getUpdatedOrdersToday();
      }

      // Fetch full updated orders
      final updatedOrders = <Order>[];
      for (final orderId in updatedOrderIds) {
        final order = await (database.select(database.orders)
              ..where((tbl) => tbl.id.equals(orderId)))
            .getSingleOrNull();
        if (order != null) {
          updatedOrders.add(order);
        }
      }

      // Get deleted order IDs from logs
      List<int> deletedOrderIds;
      if (updatedAfterLogId != null) {
        deletedOrderIds = await logService.getDeletedOrdersSinceLogId(updatedAfterLogId);
      } else {
        deletedOrderIds = await logService.getDeletedOrdersToday();
      }

      // Convert to SocketOrderModel
      final socketNewOrders = (await Future.wait(
        newOrders.map(
              (order) => _buildSocketOrder(order, stationName),
        ),
      ))
        .whereType<SocketOrderModel>()
        .toList();

      final socketUpdatedOrders = (await Future.wait(
        updatedOrders.map(
              (order) => _buildSocketOrder(order, stationName),
        ),
      ))
          .whereType<SocketOrderModel>()
          .toList();

      // Get the last log ID for the client to use in next request
      final lastLogId = await logService.getLastUpdateLogId();

      return Response.ok(
        jsonEncode({
          'orders': socketNewOrders.map((o) => o.toJson()).toList(),
          'orders_updated': socketUpdatedOrders.map((o) => o.toJson()).toList(),
          'orders_deleted': deletedOrderIds,
          'last_log_id': lastLogId,
          'count': socketNewOrders.length,
          'updated_count': socketUpdatedOrders.length,
          'deleted_count': deletedOrderIds.length,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _getOrders: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Internal server error', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /orders/ - Create new order
  Future<Response> _createOrder(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final socketOrder = SocketOrderModel.fromJson(json);

      // Convert to database order
      final orderId = await database.into(database.orders).insert(
        OrdersCompanion.insert(
          code: socketOrder.code,
          status: drift.Value(socketOrder.status),
          type: drift.Value(socketOrder.type),
          priority: drift.Value(socketOrder.priority),
          persons: drift.Value(socketOrder.persons),
          tableId: drift.Value(socketOrder.tableId),
          clientId: drift.Value(socketOrder.clientId),
          note: drift.Value(socketOrder.note),
          createdAt: drift.Value(socketOrder.date),
          //todo add the neccessery fields like source and sourceId to know where the order come from
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      // Insert products
      for (final product in socketOrder.products) {
        final productId = await database.into(database.orderProducts).insert(
          OrderProductsCompanion.insert(
            orderId: orderId,
            productId: product.productId,
            quantity: drift.Value(product.quantity),
            unitaryPrice: product.unitaryPrice,
            unitaryDiscount: drift.Value(product.discountAmount ?? 0.0),
            unitaryTva: drift.Value(product.tvaAmount ?? 0.0),
            state: drift.Value(product.state),
          ),
        );

        // Insert components
        for (final component in product.components) {
          await database.into(database.orderProductComponents).insert(
            OrderProductComponentsCompanion.insert(
              orderProductId: productId,
              componentId: component.componentId,
              quantity: drift.Value(component.quantity),
              price: drift.Value(component.extraPrice ?? 0.0),
              isSpecial: drift.Value(component.isSpecial),
            ),
          );
        }
      }

      // Log order creation
      await logService.logOrderCreated(orderId, 'Order created via API: code=${socketOrder.code}');

      return Response(
        201,
        body: jsonEncode({'id': orderId, 'code': socketOrder.code}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _createOrder: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create order', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /orders/<code> - Update order
  /// PUT /orders/<code>?status=newstatus - Fast update order status
  Future<Response> _updateOrder(Request request, String orderId) async {
    final id = int.tryParse(orderId)!;

    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final queryParams = request.url.queryParameters;
      final statusParam = queryParams['status'];

      // Fast status update
      if (statusParam != null) {
        final updated = await (database.update(database.orders)
              ..where((tbl) => tbl.id.equals(id)))
            .write(
          OrdersCompanion(
            status: drift.Value(statusParam.toUpperCase()),
            updatedAt: drift.Value(DateTime.now()),
          ),
        );

        if (updated == 0) {
          return Response.notFound(
            jsonEncode({'error': 'Order not found'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        return Response.ok(
          jsonEncode({'message': 'Order status updated', 'id': id}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Full update with body
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final socketOrder = SocketOrderModel.fromJson(json);

      // Update order
      final updated = await (database.update(database.orders)
            ..where((tbl) => tbl.id.equals(id)))
          .write(
        OrdersCompanion(
          status: drift.Value(socketOrder.status),
          type: drift.Value(socketOrder.type),
          priority: drift.Value(socketOrder.priority),
          persons: drift.Value(socketOrder.persons),
          tableId: drift.Value(socketOrder.tableId),
          clientId: drift.Value(socketOrder.clientId),
          note: drift.Value(socketOrder.note),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
      logService.logOrderUpdated(id, "Order updated via API with new data");
      if (updated == 0) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Log full order update
      await logService.logOrderUpdated(id, 'Order fully updated via API');

      return Response.ok(
        jsonEncode({'message': 'Order updated', 'code': id}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _updateOrder: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update order', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /orders/products/<id>?status=newstatus - Update product status
  Future<Response> _updateOrderProduct(Request request, String id) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final queryParams = request.url.queryParameters;
      final statusParam = queryParams['status'];

      if (statusParam == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing "status" query parameter'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final productId = int.tryParse(id);
      if (productId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid product ID'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final updated = await (database.update(database.orderProducts)
            ..where((tbl) => tbl.id.equals(productId)))
          .write(
        OrderProductsCompanion(
          state: drift.Value(statusParam.toUpperCase()),
        ),
      );
      // todo make the
      // check all the products of the order and update the order status if all products are in the same status
      final orderProduct = await (database.select(database.orderProducts)..where((tbl) => tbl.id.equals(productId))).getSingleOrNull();
      if (orderProduct != null) {
        final orderId = orderProduct.orderId;
        final allProducts = await (database.select(database.orderProducts)..where((tbl) => tbl.orderId.equals(orderId))).get();
        final allSameStatus = allProducts.every((p) => p.state == statusParam.toUpperCase());
        if (allSameStatus) {
          await (database.update(database.orders)..where((tbl) => tbl.id.equals(orderId))).write(
            OrdersCompanion(
              status: drift.Value(statusParam.toUpperCase()),
              updatedAt: drift.Value(DateTime.now()),
            ),
          );
        }
      }

      await logService.logOrderUpdated(orderProduct?.orderId ?? 0, "Product status updated via API to $statusParam");


      if (updated == 0) {
        return Response.notFound(
          jsonEncode({'error': 'Order product not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'message': 'Product status updated', 'id': productId}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _updateOrderProduct: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update product', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /stations/ - Get all stations (for KDS station selection)
  Future<Response> _getStations(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final stations = await database.select(database.stations).get();
      final stationList = stations
          .map((s) => {'id': s.id, 'name': s.name, "description": s.description})
          .toList();

      return Response.ok(
        jsonEncode({'stations': stationList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _getStations: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch stations', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// 404 handler
  Future<Response> _notFound(Request request) async {
    return Response.notFound(
      jsonEncode({'error': 'Endpoint not found'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // ==================== HELPER METHODS ====================

  /// Build SocketOrderModel from database order
  Future<SocketOrderModel?> _buildSocketOrder(Order order, String? stationFilter) async {
    final database = _ref.read(databaseProvider);

    // Get order products first - if none, return null
    final orderProducts = await (database.select(database.orderProducts)
      ..where((tbl) => tbl.orderId.equals(order.id)))
        .get();

    if (orderProducts.isEmpty) {
      print('⚠️ Order ${order.code} has no products, skipping...');
      return null;
    }

    // Batch load all needed data in parallel
    final [
    table,
    client,
    products,
    allComponents,
    allStations,
    ] = await Future.wait([
      // Get table
      order.tableId != null
          ? (database.select(database.areaTables)
        ..where((tbl) => tbl.id.equals(order.tableId!))).getSingleOrNull()
          : Future.value(null),

      // Get client
      order.clientId != null
          ? (database.select(database.customers)
        ..where((tbl) => tbl.id.equals(order.clientId!))).getSingleOrNull()
          : Future.value(null),

      // Get all products for this order in one query
      (database.select(database.products)
        ..where((tbl) => tbl.id.isIn(orderProducts.map((p) => p.productId).toList())))
          .get(),

      // Get all components for all order products
      (database.select(database.orderProductComponents)
        ..where((tbl) => tbl.orderProductId.isIn(orderProducts.map((p) => p.id).toList())))
          .get(),

      // Get all stations (for filtering)
      database.select(database.stations).get(),
    ]);

    // Create maps for quick lookup
    final productsMap = {for (var p in products as List<dynamic>) p.id: p};
    final stationsMap = {for (var s in allStations as List<dynamic>) s.id: s};
    final componentsByOrderProduct = <int, List>{};

    // Group components by order product ID
    for (var comp in allComponents as List<dynamic>) {
      componentsByOrderProduct.putIfAbsent(comp.orderProductId, () => []).add(comp);
    }

    final tableName = table != null ? (table as dynamic).name : null;
    final clientName = client != null
        ? '${(client as dynamic).firstName} ${(client as dynamic).lastName}'.trim()
        : null;

    // Process products
    final socketProducts = <SocketOrderProductModel>[];

    for (final orderProduct in orderProducts) {
      final product = productsMap[orderProduct.productId];
      if (product == null) continue;

      // Get station name
      String? stationName;
      if (product.stationId != null) {
        final station = stationsMap[product.stationId];
        stationName = station?.name;
      }

      // Filter by station if specified
      if (stationFilter != null && stationName?.toLowerCase() != stationFilter.toLowerCase()) {
        continue;
      }

      // Get components for this order product
      final productComponents = componentsByOrderProduct[orderProduct.id] ?? [];

      final socketComponents = <SocketOrderProductComponentModel>[];
      for (final comp in productComponents) {
        // Get component details (would need another batch query for components)
        // For simplicity, keeping component query as is or you can batch load components too
        final component = await (database.select(database.components)
          ..where((tbl) => tbl.id.equals(comp.componentId)))
            .getSingleOrNull();

        if (component != null) {
          socketComponents.add(SocketOrderProductComponentModel(
            componentId: comp.componentId,
            componentName: component.name,
            quantity: comp.quantity,
            isSpecial: comp.isSpecial,
            extraPrice: comp.price,
          ));
        }
      }

      socketProducts.add(SocketOrderProductModel(
        id: orderProduct.id,
        productId: orderProduct.productId,
        productName: product.name,
        imageUrl: product.imageUrl,
        quantity: orderProduct.quantity,
        unitaryPrice: orderProduct.unitaryPrice,
        state: orderProduct.state,
        stationId: product.stationId,
        stationName: stationName,
        components: socketComponents,
        note: null,
        tvaAmount: orderProduct.unitaryTva,
        discountAmount: orderProduct.unitaryDiscount,
      ));
    }

    // If no products after filtering, return null
    if (socketProducts.isEmpty) {
      print('⚠️ Order ${order.code} has no products after station filter, skipping...');
      return null;
    }

    return SocketOrderModel(
      id: order.id,
      code: order.code,
      status: order.status,
      type: order.type,
      priority: order.priority,
      persons: order.persons,
      date: order.createdAt,
      tableId: order.tableId,
      tableName: tableName,
      clientId: order.clientId,
      clientName: clientName,
      products: socketProducts,
      note: order.note,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    );
  }

  // ==================== GETTERS ====================

  bool get isRunning => _isRunning;
  int get port => _port;
  String? get serverPassword => _serverPassword;
}


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
    router.get('/orders/', _getOrders);
    router.post('/orders/', _createOrder);
    router.put('/orders/<code>', _updateOrder);
    router.put('/orders/products/<id>', _updateOrderProduct);

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



  /// GET /orders/?since=date&after_id=int&station=string
  Future<Response> _getOrders(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final queryParams = request.url.queryParameters;

      // Parse query parameters
      final sinceStr = queryParams['since'];
      final afterIdStr = queryParams['after_id'];
      final stationName = queryParams['station'];
      final statusStr = queryParams['status'];


      DateTime? since;
      int? afterId;
      List<String> status = statusStr != null ? statusStr.split(',').map((s) => s.trim().toUpperCase()).toList() : [];

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

      if (afterIdStr != null) {
        afterId = int.tryParse(afterIdStr);
        if (afterId == null) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Invalid integer for "after_id" parameter'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // Build query
      var query = database.select(database.orders).join([]);

      if (since != null) {
        query = query..where(database.orders.createdAt.isBiggerOrEqualValue(since));
      }

      if (afterId != null) {
        query = query..where(database.orders.id.isBiggerThanValue(afterId));
      }

      if (status.isNotEmpty) {
        query = query..where(database.orders.status.isIn(status));
      }

      // Execute query
      final ordersData = await query.get();
      final orders = ordersData.map((row) => row.readTable(database.orders)).toList();

      // Convert to SocketOrderModel
      final socketOrders = await Future.wait(
        orders.map((order) => _buildSocketOrder(order, stationName)),
      );

      return Response.ok(
        jsonEncode({
          'orders': socketOrders.map((o) => o.toJson()).toList(),
          'count': socketOrders.length,
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
  Future<Response> _updateOrder(Request request, String code) async {
    try {
      final database = _ref.read(databaseProvider);
      final queryParams = request.url.queryParameters;
      final statusParam = queryParams['status'];

      // Fast status update
      if (statusParam != null) {
        final updated = await (database.update(database.orders)
              ..where((tbl) => tbl.code.equals(code)))
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
          jsonEncode({'message': 'Order status updated', 'code': code}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Full update with body
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final socketOrder = SocketOrderModel.fromJson(json);

      // Update order
      final updated = await (database.update(database.orders)
            ..where((tbl) => tbl.code.equals(code)))
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

      if (updated == 0) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      return Response.ok(
        jsonEncode({'message': 'Order updated', 'code': code}),
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

  /// 404 handler
  Future<Response> _notFound(Request request) async {
    return Response.notFound(
      jsonEncode({'error': 'Endpoint not found'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // ==================== HELPER METHODS ====================

  /// Build SocketOrderModel from database order
  Future<SocketOrderModel> _buildSocketOrder(Order order, String? stationFilter) async {
    final database = _ref.read(databaseProvider);

    // Get table name
    String? tableName;
    if (order.tableId != null) {
      final table = await (database.select(database.areaTables)
            ..where((tbl) => tbl.id.equals(order.tableId!)))
          .getSingleOrNull();
      tableName = table?.name;
    }

    // Get client name
    String? clientName;
    if (order.clientId != null) {
      final client = await (database.select(database.customers)
            ..where((tbl) => tbl.id.equals(order.clientId!)))
          .getSingleOrNull();
      if (client != null) {
        clientName = '${client.firstName} ${client.lastName}';
      }
    }

    // Get order products
    final orderProducts = await (database.select(database.orderProducts)
          ..where((tbl) => tbl.orderId.equals(order.id)))
        .get();

    final socketProducts = <SocketOrderProductModel>[];

    for (final orderProduct in orderProducts) {
      // Get product details
      final product = await (database.select(database.products)
            ..where((tbl) => tbl.id.equals(orderProduct.productId)))
          .getSingleOrNull();

      if (product == null) continue;

      // Get station name
      String? stationName;
      if (product.stationId != null) {
        final station = await (database.select(database.stations)
              ..where((tbl) => tbl.id.equals(product.stationId!)))
            .getSingleOrNull();
        stationName = station?.name;
      }

      // Filter by station if specified
      if (stationFilter != null && stationName?.toLowerCase() != stationFilter.toLowerCase()) {
        continue;
      }

      // Get components
      final components = await (database.select(database.orderProductComponents)
            ..where((tbl) => tbl.orderProductId.equals(orderProduct.id)))
          .get();

      final socketComponents = <SocketOrderProductComponentModel>[];
      for (final comp in components) {
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
        note: null, // OrderProduct doesn't have note field
        tvaAmount: orderProduct.unitaryTva,
        discountAmount: orderProduct.unitaryDiscount,
      ));
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


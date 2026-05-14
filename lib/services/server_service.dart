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

    // Order endpoints
    router.get('/orders', _getOrders);
    router.post('/orders', _createOrder);
    router.put('/orders/<orderId>', _updateOrder);
    router.put('/orders/products/<id>', _updateOrderProduct);
    router.get('/stations', _getStations);

    // Waiter-specific endpoints
    router.post('/waiters/login', _waiterLogin);
    router.get('/waiters/dashboard', _waiterDashboard);
    router.get('/waiters/products', _waiterProducts);
    router.get('/waiters/categories', _waiterCategories);
    router.get('/waiters/components', _waiterComponents);
    router.get('/waiters/component-groups', _waiterComponentGroups);
    router.get('/waiters/product-components', _waiterProductComponents);
    router.get('/waiters/product-variants', _waiterProductVariants);
    router.get('/waiters/tables', _waiterTables);
    router.get('/waiters/orders', _waiterOrders);
    router.post('/waiters/orders', _waiterCreateOrder);
    router.put('/waiters/orders/<code>/add-product', _waiterAddProductToOrder);

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



  /// GET /orders/?since=date&from_date=date&to_date=date&updated_after_log_id=int
  ///                &station=string&status=csv&after_id=int
  ///
  /// Date params (any combination accepted; `from_date` is an alias for `since`):
  ///   - `since` / `from_date` — lower bound (inclusive).  Default: start of today.
  ///   - `to_date`             — upper bound (inclusive).  Default: no upper bound.
  ///
  /// Filter priority:
  ///   1. Date window (`since`/`from_date`/`to_date`) — the primary scope.
  ///   2. `updated_after_log_id` — incremental cursor; constrained by date window.
  ///   3. `station` — pre-filtered at DB level (no noisy post-fetch skips).
  ///
  /// Returns: orders (new), orders_updated (updated), orders_deleted (IDs),
  ///          last_log_id (opaque cursor for next poll).
  Future<Response> _getOrders(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final queryParams = request.url.queryParameters;

      // ── Parse query parameters ──────────────────────────────────────────
      // Accept both `since` and `from_date` as the lower-bound date param
      final sinceStr = queryParams['since'] ?? queryParams['from_date'];
      final toDateStr = queryParams['to_date'];
      final afterIdStr = queryParams['after_id'];
      final updatedAfterLogIdStr = queryParams['updated_after_log_id'];
      final stationName = queryParams['station'];
      final statusStr = queryParams['status'];

      DateTime? since;
      DateTime? toDate;
      int? updatedAfterLogId;
      final afterId = int.tryParse(afterIdStr ?? '');
      final List<String> status = statusStr != null
          ? statusStr.split(',').map((s) => s.trim().toUpperCase()).toList()
          : [];

      // 1. Parse lower-bound date
      if (sinceStr != null) {
        try {
          since = DateTime.parse(sinceStr);
        } catch (_) {
          return Response.badRequest(
            body: jsonEncode(
                {'error': 'Invalid date format for "since"/"from_date" parameter'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // 2. Parse upper-bound date
      if (toDateStr != null) {
        try {
          toDate = DateTime.parse(toDateStr);
        } catch (_) {
          return Response.badRequest(
            body: jsonEncode(
                {'error': 'Invalid date format for "to_date" parameter'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // 3. Parse updated_after_log_id
      if (updatedAfterLogIdStr != null) {
        updatedAfterLogId = int.tryParse(updatedAfterLogIdStr);
        if (updatedAfterLogId == null) {
          return Response.badRequest(
            body: jsonEncode(
                {'error': 'Invalid integer for "updated_after_log_id" parameter'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // 4. Default to today when neither date nor log-cursor provided
      if (since == null && updatedAfterLogId == null) {
        final now = DateTime.now();
        since = DateTime(now.year, now.month, now.day);
      }

      // ── Pre-resolve station ID so we can filter orders at DB level ───────
      // This avoids fetching orders that have no products for the station,
      // eliminating the "no products after station filter, skipping" noise.
      int? stationId;
      if (stationName != null) {
        final station = await (database.select(database.stations)
              ..where((tbl) => tbl.name.lower().equals(stationName.toLowerCase())))
            .getSingleOrNull();
        if (station == null) {
          // Unknown station — return empty result immediately
          final lastLogId = await logService.getLastUpdateLogId();
          return Response.ok(
            jsonEncode({
              'orders': [],
              'orders_updated': [],
              'orders_deleted': [],
              'last_log_id': lastLogId,
              'count': 0,
              'updated_count': 0,
              'deleted_count': 0,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
        stationId = station.id;
      }

      // Build the set of order IDs that contain at least one product from
      // the requested station (empty set means no station filter).
      Set<int>? orderIdsForStation;
      if (stationId != null) {
        final rows = await (database.select(database.orderProducts).join([
          drift.innerJoin(
            database.products,
            database.products.id
                .equalsExp(database.orderProducts.productId),
          ),
        ])
              ..where(database.products.stationId.equals(stationId)))
            .get();
        orderIdsForStation = rows
            .map((r) => r.readTable(database.orderProducts).orderId)
            .toSet();
        if (orderIdsForStation.isEmpty) {
          // Station exists but no products are assigned to it yet
          final lastLogId = await logService.getLastUpdateLogId();
          return Response.ok(
            jsonEncode({
              'orders': [],
              'orders_updated': [],
              'orders_deleted': [],
              'last_log_id': lastLogId,
              'count': 0,
              'updated_count': 0,
              'deleted_count': 0,
            }),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }

      // ── New orders (created within the date window) ──────────────────────
      var ordersQuery = database.select(database.orders).join([]);
      if (since != null) {
        ordersQuery = ordersQuery
          ..where(database.orders.createdAt.isBiggerOrEqualValue(since));
      }
      if (toDate != null) {
        ordersQuery = ordersQuery
          ..where(database.orders.createdAt.isSmallerOrEqualValue(toDate));
      }
      if (status.isNotEmpty) {
        ordersQuery = ordersQuery
          ..where(database.orders.status.isIn(status));
      }
      if (afterId != null) {
        ordersQuery = ordersQuery
          ..where(database.orders.id.isBiggerThanValue(afterId));
      }
      if (orderIdsForStation != null) {
        ordersQuery = ordersQuery
          ..where(database.orders.id.isIn(orderIdsForStation.toList()));
      }

      final ordersData = await ordersQuery.get();
      final newOrders =
          ordersData.map((row) => row.readTable(database.orders)).toList();

      // ── Updated order IDs from logs (date-first, then log cursor) ───────
      List<int> updatedOrderIds;
      if (updatedAfterLogId != null && since != null) {
        updatedOrderIds = await logService
            .getUpdatedOrdersSinceLogIdAndDate(updatedAfterLogId, since);
      } else if (updatedAfterLogId != null) {
        updatedOrderIds =
            await logService.getUpdatedOrdersSinceLogId(updatedAfterLogId);
      } else if (since != null) {
        updatedOrderIds = await logService.getUpdatedOrdersSinceDate(since);
      } else {
        updatedOrderIds = await logService.getUpdatedOrdersToday();
      }

      // Fetch full updated orders, re-applying date + station filters
      final updatedOrders = <Order>[];
      final sinceDate = since;
      for (final orderId in updatedOrderIds) {
        // Skip if we already know this order doesn't belong to the station
        if (orderIdsForStation != null &&
            !orderIdsForStation.contains(orderId)) {
          continue;
        }
        final orderQuery = database.select(database.orders)
          ..where((tbl) => tbl.id.equals(orderId));
        if (sinceDate != null) {
          orderQuery
            ..where((tbl) => tbl.createdAt.isBiggerOrEqualValue(sinceDate));
        }
        if (toDate != null) {
          final td = toDate;
          orderQuery
            ..where((tbl) => tbl.createdAt.isSmallerOrEqualValue(td));
        }
        final order = await orderQuery.getSingleOrNull();
        if (order != null) {
          updatedOrders.add(order);
        }
      }

      // ── Deleted order IDs from logs ───────────────────────────────────────
      List<int> deletedOrderIds;
      if (updatedAfterLogId != null && since != null) {
        deletedOrderIds = await logService
            .getDeletedOrdersSinceLogIdAndDate(updatedAfterLogId, since);
      } else if (updatedAfterLogId != null) {
        deletedOrderIds =
            await logService.getDeletedOrdersSinceLogId(updatedAfterLogId);
      } else if (since != null) {
        deletedOrderIds = await logService.getDeletedOrdersSinceDate(since);
      } else {
        deletedOrderIds = await logService.getDeletedOrdersToday();
      }

      // ── Convert to SocketOrderModel ──────────────────────────────────────
      final socketNewOrders = (await Future.wait(
        newOrders.map((order) => _buildSocketOrder(order, stationName)),
      ))
          .whereType<SocketOrderModel>()
          .toList();

      final socketUpdatedOrders = (await Future.wait(
        updatedOrders.map((order) => _buildSocketOrder(order, stationName)),
      ))
          .whereType<SocketOrderModel>()
          .toList();

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
        body: jsonEncode(
            {'error': 'Internal server error', 'details': e.toString()}),
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

      print('📥 _createOrder: $json');

      // Read extra fields not in SocketOrderModel
      final waiterId = json['waiterId'] as int?;

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
          waiterId: drift.Value(waiterId),
          note: drift.Value(socketOrder.note),
          createdAt: drift.Value(socketOrder.date),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );

      // If DINE_IN with a table, link the order to the table
      if (socketOrder.tableId != null) {
        await (database.update(database.areaTables)
          ..where((t) => t.id.equals(socketOrder.tableId!)))
          .write(AreaTablesCompanion(orderId: drift.Value(orderId)));
      }

      // Insert products
      for (final product in socketOrder.products) {
        // Resolve authoritative price from DB for the variant (prevents price manipulation)
        double unitPrice = product.unitaryPrice;
        double unitTva = product.tvaAmount ?? 0.0;
        double unitDiscount = product.discountAmount ?? 0.0;

        if (product.variantId != null) {
          final variant = await (database.select(database.productVariants)
            ..where((v) => v.id.equals(product.variantId!)))
            .getSingleOrNull();
          if (variant != null) {
            unitPrice = variant.price;
            unitTva = variant.tvaAmount;
          }
        } else {
          final dbProduct = await (database.select(database.products)
            ..where((p) => p.id.equals(product.productId)))
            .getSingleOrNull();
          if (dbProduct != null) {
            unitPrice = dbProduct.finalPrice;
            unitTva = dbProduct.tvaAmount;
            unitDiscount = dbProduct.discountAmount;
          }
        }

        final orderProductId = await database.into(database.orderProducts).insert(
          OrderProductsCompanion.insert(
            orderId: orderId,
            productId: product.productId,
            variantId: drift.Value(product.variantId),
            quantity: drift.Value(product.quantity),
            unitaryPrice: unitPrice,
            unitaryDiscount: drift.Value(unitDiscount),
            unitaryTva: drift.Value(unitTva),
            note: drift.Value(product.note),
            state: drift.Value(product.state),
          ),
        );

        // Insert components
        for (final component in product.components) {
          await database.into(database.orderProductComponents).insert(
            OrderProductComponentsCompanion.insert(
              orderProductId: orderProductId,
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

      print('✅ _createOrder: inserted order #$orderId code=${socketOrder.code}');

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

  // ==================== WAITER ENDPOINTS ====================

  /// POST /waiters/login - Waiter authentication
  /// Body: { "waiterId": 1, "password": "optional" }
  Future<Response> _waiterLogin(Request request) async {

    //get the username and password from the request body
    final body = jsonDecode(await request.readAsString()) as Map<String ,dynamic>;



    final username = body['username'];
    final password = body['password'];


    final db = _ref.read(databaseProvider);
    final query = db.select(db.waiters)..where((w) => w.username.equals(username!!));

    final result = await query.getSingleOrNull();
    if (result == null) {
      return Response.forbidden(
        jsonEncode({'error': 'Invalid username or password'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    return Response.ok(
      jsonEncode({
        'waiter': {
          'id': result.id,
          'firstName': result.firstName,
          'lastName': result.lastName,
        },
      }),
      headers: {'Content-Type': 'application/json'},
    );






    try {
      final database = _ref.read(databaseProvider);
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final waiterId = json['waiterId'] as int?;
      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get waiter
      final waiter = await (database.select(database.waiters)
        ..where((w) => w.id.equals(waiterId)))
        .getSingleOrNull();

      if (waiter == null || !waiter.isActive) {
        return Response(
          401,
          body: jsonEncode({'error': 'Invalid waiter or inactive'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get waiter areas
      final waiterAreas = await (database.select(database.waiterAreas)
        ..where((wa) => wa.waiterId.equals(waiterId)))
        .get();
      final areaIds = waiterAreas.map((wa) => wa.areaId).toList();

      // Return waiter info
      return Response.ok(
        jsonEncode({
          'waiter': {
            'id': waiter.id,
            'firstName': waiter.firstName,
            'lastName': waiter.lastName,
            'imageUrl': waiter.imageUrl,
            'areaIds': areaIds,
          },
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterLogin: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Login failed', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/dashboard?waiterId=1
  /// Returns: total orders, active orders, expected cash, total cash
  Future<Response> _waiterDashboard(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final queryParams = request.url.queryParameters;
      final waiterIdStr = queryParams['waiterId'];

      if (waiterIdStr == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final waiterId = int.tryParse(waiterIdStr);
      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid waiterId'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get today's date range
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      // Get all orders for this waiter today (excluding cancelled orders)
      final allWaiterOrders = await (database.select(database.orders)
        ..where((o) => o.waiterId.equals(waiterId) & o.createdAt.isBiggerOrEqualValue(startOfDay)))
        .get();

      // Filter out cancelled orders for calculations
      final waiterOrders = allWaiterOrders.where((o) => o.status != 'CANCELED').toList();

      final totalOrders = waiterOrders.length;
      final activeOrders = waiterOrders.where((o) => o.status != 'COMPLETED').length;
      final cancelledOrders = allWaiterOrders.where((o) => o.status == 'CANCELED').length;

      // Calculate totals (excluding cancelled orders)
      double expectedCash = 0.0;
      double totalCash = 0.0;
      double cancelledAmount = 0.0;

      // Calculate cancelled amount separately
      for (final order in allWaiterOrders.where((o) => o.status == 'CANCELED')) {
        final orderProducts = await (database.select(database.orderProducts)
          ..where((op) => op.orderId.equals(order.id)))
          .get();

        for (final product in orderProducts) {
          double itemTotal = product.unitaryPrice * product.quantity;
          final components = await (database.select(database.orderProductComponents)
            ..where((c) => c.orderProductId.equals(product.id)))
            .get();
          for (final component in components) {
            itemTotal += component.price * component.quantity;
          }
          itemTotal -= (product.unitaryDiscount * product.quantity);
          itemTotal -= (product.manualDiscount * product.quantity);
          cancelledAmount += itemTotal;
        }
      }

      for (final order in waiterOrders) {
        final orderProducts = await (database.select(database.orderProducts)
          ..where((op) => op.orderId.equals(order.id)))
          .get();

        for (final product in orderProducts) {
          // Base product price (already includes TVA)
          double itemTotal = product.unitaryPrice * product.quantity;

          // Add component prices
          final components = await (database.select(database.orderProductComponents)
            ..where((c) => c.orderProductId.equals(product.id)))
            .get();

          for (final component in components) {
            itemTotal += component.price * component.quantity;
          }

          // Subtract discounts (item-level discount + manual discount)
          itemTotal -= (product.unitaryDiscount * product.quantity);
          itemTotal -= (product.manualDiscount * product.quantity);

          expectedCash += itemTotal;

          // Check if product is paid (and ticket is not cancelled)
          if (product.ticketId != null) {
            // Check if the ticket is cancelled
            final ticket = await (database.select(database.tickets)
              ..where((t) => t.id.equals(product.ticketId!)))
              .getSingleOrNull();

            if (ticket != null && !ticket.isCancelled) {
              totalCash += itemTotal;
            }
          }
        }
      }

      return Response.ok(
        jsonEncode({
          'totalOrders': totalOrders,
          'activeOrders': activeOrders,
          'cancelledOrders': cancelledOrders,
          'expectedCash': expectedCash,
          'totalCash': totalCash,
          'cancelledAmount': cancelledAmount,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterDashboard: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to get dashboard', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/products
  Future<Response> _waiterProducts(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final products = await (database.select(database.products)
        ..where((p) => p.isActive.equals(true)))
        .get();

      final productList = products.map((p) => {
        'id': p.id,
        'name': p.name,
        'barcode': p.barcode,
        'imageUrl': p.imageUrl,
        'description': p.description,
        'price': p.price,
        'finalPrice': p.finalPrice,
        'categoryId': p.categoryId,
        'stationId': p.stationId,
        'isVariant': p.isVariant,
        'color': p.color,
        'isPlannable': p.isPlannable,
        'planDurationMinutes': p.planDurationMinutes,
      }).toList();

      return Response.ok(
        jsonEncode({'products': productList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterProducts: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch products', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/categories
  Future<Response> _waiterCategories(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final categories = await (database.select(database.categories)
        ..where((c) => c.isActive.equals(true))
        ..orderBy([(c) => drift.OrderingTerm(expression: c.displayOrder)]))
        .get();

      final categoryList = categories.map((c) => {
        'id': c.id,
        'name': c.name,
        'imageUrl': c.imageUrl,
        'description': c.description,
        'displayOrder': c.displayOrder,
        'color': c.color,
      }).toList();

      return Response.ok(
        jsonEncode({'categories': categoryList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterCategories: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch categories', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/components
  Future<Response> _waiterComponents(Request request) async {


    try {
      final database = _ref.read(databaseProvider);
      final components = await database.select(database.components).get();

      final componentList = components.map((c) => {
        'id': c.id,
        'name': c.name,
        'price': c.price,
        'componentGroupId': c.componentGroupId,
      }).toList();

      print(componentList);
      return Response.ok(
        jsonEncode({'components': componentList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterComponents: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch components', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/component-groups
  Future<Response> _waiterComponentGroups(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final groups = await (database.select(database.componentGroups)
        ..orderBy([(g) => drift.OrderingTerm(expression: g.displayOrder)]))
        .get();

      final groupList = groups.map((g) => {
        'id': g.id,
        'name': g.name,
        'description': g.description,
        'displayOrder': g.displayOrder,
      }).toList();

      return Response.ok(
        jsonEncode({'componentGroups': groupList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterComponentGroups: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch component groups', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/product-components
  Future<Response> _waiterProductComponents(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final productComponents = await database.select(database.productComponents).get();

      final pcList = productComponents.map((pc) => {
        'productId': pc.productId,
        'componentId': pc.componentId,
        'defaultPrice': pc.defaultPrice,
        'defaultQuantity': pc.defaultQuantity, // ✅ Added: Default quantity from ProductComponents relation table
        'isRequired': pc.isRequired,
        'minQuantity': pc.minQuantity,
        'maxQuantity': pc.maxQuantity,
      }).toList();

      return Response.ok(
        jsonEncode({'productComponents': pcList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterProductComponents: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch product components', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/product-variants?productId=123
  /// Returns all variant groups and their variants with attributes for proper selection
  Future<Response> _waiterProductVariants(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final queryParams = request.url.queryParameters;
      final productIdStr = queryParams['productId'];

      if (productIdStr == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'productId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final productId = int.tryParse(productIdStr);
      if (productId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid productId'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Check if product exists
      final product = await (database.select(database.products)
        ..where((p) => p.id.equals(productId)))
        .getSingleOrNull();

      if (product == null) {
        return Response(
          404,
          body: jsonEncode({
            'error': 'Product not found',
            'message': 'Product with ID $productId does not exist'
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get all variants for this product
      final variants = await (database.select(database.productVariants)
        ..where((v) => v.productId.equals(productId))
        ..where((v) => v.isActive.equals(true)))
        .get();

      if (variants.isEmpty) {
        return Response.ok(
          jsonEncode({
            'hasVariants': false,
            'variants': [],
            'attributeGroups': []
          }),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get all variant attribute values for these variants
      final variantIds = variants.map((v) => v.id).toList();
      final attributeValues = await (database.select(database.variantAttributeValues)
        ..where((av) => av.variantId.isIn(variantIds)))
        .get();

      // Build variants list with their attributes
      final variantsList = variants.map((variant) {
        final variantAttrs = attributeValues
            .where((av) => av.variantId == variant.id)
            .toList();

        return {
          'id': variant.id,
          'productId': variant.productId,
          'name': variant.name,
          'barcode': variant.barcode,
          'sku': variant.sku,
          'description': variant.description,
          'imageUrl': variant.imageUrl,
          'color': variant.color,
          'price': variant.price,
          'additionalPrice': variant.price - product.price,
          'finalPrice': variant.price,
          'tvaAmount': variant.tvaAmount,
          'isActive': variant.isActive,
          'attributes': variantAttrs.map((attr) => {
            'attributeId': attr.attributeId,
            'attributeName': attr.attributeName,
            'valueId': attr.valueId,
            'value': attr.value,
          }).toList(),
        };
      }).toList();

      // Build attribute groups for UI selection
      final Map<String, Map<String, dynamic>> attributeGroupsMap = {};

      for (final attrValue in attributeValues) {
        final attrName = attrValue.attributeName ?? 'Options';
        final attrId = attrValue.attributeId;

        if (!attributeGroupsMap.containsKey(attrName)) {
          attributeGroupsMap[attrName] = {
            'id': attrId,
            'name': attrName,
            'values': <Map<String, dynamic>>[],
          };
        }

        // Add unique values only
        final values = attributeGroupsMap[attrName]!['values'] as List;
        final existingValue = values.any((v) => v['id'] == attrValue.valueId);

        if (!existingValue) {
          values.add({
            'id': attrValue.valueId,
            'value': attrValue.value,
            'attributeId': attrId,
          });
        }
      }

      // Convert to list and sort
      final attributeGroups = attributeGroupsMap.values.toList();

      return Response.ok(
        jsonEncode({
          'hasVariants': true,
          'baseProduct': {
            'id': product.id,
            'name': product.name,
            'price': product.price,
            'imageUrl': product.imageUrl,
          },
          'variants': variantsList,
          'attributeGroups': attributeGroups,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterProductVariants: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({
          'error': 'Failed to fetch product variants',
          'details': e.toString()
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/tables?waiterId=1
  /// Returns tables for the waiter's assigned areas
  Future<Response> _waiterTables(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final queryParams = request.url.queryParameters;
      final waiterIdStr = queryParams['waiterId'];

      if (waiterIdStr == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final waiterId = int.tryParse(waiterIdStr);
      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid waiterId'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get waiter areas
      final waiterAreas = await (database.select(database.waiterAreas)
        ..where((wa) => wa.waiterId.equals(waiterId)))
        .get();
      final areaIds = waiterAreas.map((wa) => wa.areaId).toList();

      if (areaIds.isEmpty) {
        final tables = await (database.select(database.areaTables))
            .get();

        final tableList = <Map<String, dynamic>>[];
        for (final table in tables) {
          // Get area name
          final area = await (database.select(database.areas)
            ..where((a) => a.id.equals(table.areaId!)))
              .getSingleOrNull();

          // Get order for this table if exists
          final order = await (database.select(database.orders)
            ..where((o) => o.id.equals(table.orderId ?? 0)))
              .getSingleOrNull();

          double totalAmount = 0.0;
          if (order != null) {
            final orderProducts = await (database.select(database.orderProducts)
              ..where((op) => op.orderId.equals(order.id)))
                .get();

            for (final product in orderProducts) {
              // Check if not paid
              if (product.ticketId == null) {
                // Base product price (already includes TVA)
                double itemTotal = product.unitaryPrice * product.quantity;

                // Add component prices
                final components = await (database.select(database.orderProductComponents)
                  ..where((c) => c.orderProductId.equals(product.id)))
                  .get();

                for (final component in components) {
                  itemTotal += component.price * component.quantity;
                }

                // Subtract discounts
                itemTotal -= (product.unitaryDiscount * product.quantity);
                itemTotal -= (product.manualDiscount * product.quantity);

                totalAmount += itemTotal;
              }
            }
          }

          tableList.add({
            'id': table.id,
            'name': table.name,
            'capacity': table.capacity,
            'areaId': table.areaId,
            'areaName': area?.name,
            'orderId': order?.id,
            'orderCode': order?.code,
            'totalAmount': totalAmount,
          });
        }
        return Response.ok(
          jsonEncode({'tables': tableList}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get tables for those areas
      final tables = await (database.select(database.areaTables)
        ..where((t) => t.areaId.isIn(areaIds)))
        .get();

      final tableList = <Map<String, dynamic>>[];
      for (final table in tables) {
        // Get area name
        final area = await (database.select(database.areas)
          ..where((a) => a.id.equals(table.areaId!)))
          .getSingleOrNull();

        // Get active order for this table if exists (only non-completed orders)
        final order = await (database.select(database.orders)
          ..where((o) => o.id.equals(table.orderId ?? 0) & o.status.isNotIn(['completed', 'cancelled']))
          ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)])
          ..limit(1))
          .getSingleOrNull();

        double totalAmount = 0.0;
        if (order != null) {
          final orderProducts = await (database.select(database.orderProducts)
            ..where((op) => op.orderId.equals(order.id)))
            .get();

          for (final product in orderProducts) {
            // Check if not paid
            if (product.ticketId == null) {
              // Base product price (already includes TVA)
              double itemTotal = product.unitaryPrice * product.quantity;

              // Add component prices
              final components = await (database.select(database.orderProductComponents)
                ..where((c) => c.orderProductId.equals(product.id)))
                .get();

              for (final component in components) {
                itemTotal += component.price * component.quantity;
              }

              // Subtract discounts
              itemTotal -= (product.unitaryDiscount * product.quantity);
              itemTotal -= (product.manualDiscount * product.quantity);

              totalAmount += itemTotal;
            }
          }
        }

        tableList.add({
          'id': table.id,
          'name': table.name,
          'capacity': table.capacity,
          'areaId': table.areaId,
          'areaName': area?.name,
          'orderId': order?.id,
          'orderCode': order?.code,
          'totalAmount': totalAmount,
        });
      }

      return Response.ok(
        jsonEncode({'tables': tableList}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterTables: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch tables', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// GET /waiters/orders?waiterId=1&status=PENDING,ONHOLD&page=0&limit=20
  Future<Response> _waiterOrders(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final queryParams = request.url.queryParameters;
      final waiterIdStr = queryParams['waiterId'];
      final statusStr = queryParams['status'];
      final pageStr = queryParams['page'] ?? '0';
      final limitStr = queryParams['limit'] ?? '20';

      if (waiterIdStr == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final waiterId = int.tryParse(waiterIdStr);
      final page = int.tryParse(pageStr) ?? 0;
      final limit = int.tryParse(limitStr) ?? 20;

      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid waiterId'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Build query
      var query = database.select(database.orders)..where((o) => o.waiterId.equals(waiterId));

      // Filter by status if provided
      if (statusStr != null && statusStr.isNotEmpty) {
        final statuses = statusStr.split(',').map((s) => s.trim().toUpperCase()).toList();
        query = query..where((o) => o.status.isIn(statuses));
      }

      // Order by creation date descending
      query = query..orderBy([(o) => drift.OrderingTerm(expression: o.createdAt, mode: drift.OrderingMode.desc)]);

      // Pagination
      query = query..limit(limit, offset: page * limit);

      final orders = await query.get();

      // Build response with full order details
      final orderList = <Map<String, dynamic>>[];
      for (final order in orders) {
        // Get table name
        String? tableName;
        if (order.tableId != null) {
          final table = await (database.select(database.areaTables)
            ..where((t) => t.id.equals(order.tableId!)))
            .getSingleOrNull();
          tableName = table?.name;
        }

        // Get products
        final orderProducts = await (database.select(database.orderProducts)
          ..where((op) => op.orderId.equals(order.id)))
          .get();

        double totalAmount = 0.0;
        bool allPaid = true;
        for (final product in orderProducts) {
          // Base product price (already includes TVA)
          double itemTotal = product.unitaryPrice * product.quantity;

          // Add component prices
          final components = await (database.select(database.orderProductComponents)
            ..where((c) => c.orderProductId.equals(product.id)))
            .get();

          for (final component in components) {
            itemTotal += component.price * component.quantity;
          }

          // Subtract discounts (item-level discount + manual discount)
          itemTotal -= (product.unitaryDiscount * product.quantity);
          itemTotal -= (product.manualDiscount * product.quantity);

          totalAmount += itemTotal;

          if (product.ticketId == null) {
            allPaid = false;
          }
        }

        orderList.add({
          'id': order.id,
          'code': order.code,
          'status': order.status,
          'type': order.type,
          'persons': order.persons,
          'tableId': order.tableId,
          'tableName': tableName,
          'totalAmount': totalAmount,
          'allPaid': allPaid,
          'productCount': orderProducts.length,
          'createdAt': order.createdAt.toIso8601String(),
          'updatedAt': order.updatedAt.toIso8601String(),
        });
      }

      return Response.ok(
        jsonEncode({
          'orders': orderList,
          'page': page,
          'limit': limit,
          'count': orderList.length,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterOrders: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch orders', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /waiters/orders - Create new order
  /// Body: { "waiterId": 1, "tableId": 5, "type": "DINE_IN", "persons": 2, "products": [...] }
  Future<Response> _waiterCreateOrder(Request request) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      print(json);

      final waiterId = json['waiterId'] as int?;
      final tableId = json['tableId'] as int?;
      final type = json['type'] as String? ?? 'DINE_IN';
      final persons = json['persons'] as int? ?? 1;
      final products = json['products'] as List<dynamic>? ?? [];

      if (waiterId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId is required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Validate table for DINE_IN
      if (type == 'DINE_IN' && tableId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'tableId is required for DINE_IN orders'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Generate order code
      final now = DateTime.now();
      final orderCode = 'W${waiterId}_${now.millisecondsSinceEpoch}';

      // Create order
      final orderId = await database.into(database.orders).insert(
        OrdersCompanion.insert(
          code: orderCode,
          status: const drift.Value('PENDING'),
          type: drift.Value(type),
          persons: drift.Value(persons),
          tableId: drift.Value(tableId),
          waiterId: drift.Value(waiterId),
          createdAt: drift.Value(now),
          updatedAt: drift.Value(now),
        ),
      );

      // Insert products
      for (final productJson in products) {
        final productId = productJson['productId'] as int;
        final variantId = productJson['variantId'] as int?;
        final quantity = productJson['quantity'] as int? ?? 1;
        final productNote = productJson['note'] as String?;
        final components = productJson['components'] as List<dynamic>? ?? [];

        // Get product details
        final product = await (database.select(database.products)
          ..where((p) => p.id.equals(productId)))
          .getSingleOrNull();

        if (product == null) continue;

        // Use variant price/TVA if a variantId is provided
        double unitPrice = product.finalPrice;
        double unitTva = product.tvaAmount;
        double unitDiscount = product.discountAmount;

        if (variantId != null) {
          final variant = await (database.select(database.productVariants)
            ..where((v) => v.id.equals(variantId)))
            .getSingleOrNull();
          if (variant != null) {
            unitPrice = variant.price;
            unitTva = variant.tvaAmount;
            unitDiscount = 0.0; // Variants typically have no pre-discount
          }
        }

        final orderProductId = await database.into(database.orderProducts).insert(
          OrderProductsCompanion.insert(
            orderId: orderId,
            productId: productId,
            variantId: drift.Value(variantId),
            quantity: drift.Value(quantity),
            unitaryPrice: unitPrice,
            unitaryDiscount: drift.Value(unitDiscount),
            unitaryTva: drift.Value(unitTva),
            note: drift.Value(productNote),
            state: const drift.Value('PENDING'),
          ),
        );

        // Insert components
        for (final compJson in components) {
          final componentId = compJson['componentId'] as int;
          final compQuantity = compJson['quantity'] as int? ?? 1;
          final price = (compJson['price'] as num?)?.toDouble() ?? 0.0;

          await database.into(database.orderProductComponents).insert(
            OrderProductComponentsCompanion.insert(
              orderProductId: orderProductId,
              componentId: componentId,
              quantity: drift.Value(compQuantity),
              price: drift.Value(price),
              isSpecial: const drift.Value(false),
            ),
          );
        }
      }


      // update the tabele order_id

      if (tableId != null) {
        await (database.update(database.areaTables)..where((t) => t.id.equals(tableId)))
          .write(AreaTablesCompanion(orderId: drift.Value(orderId)));
      }

      // Log order creation
      await logService.logOrderCreated(orderId, 'Order created by waiter #$waiterId');

      return Response(
        201,
        body: jsonEncode({
          'id': orderId,
          'code': orderCode,
          'message': 'Order created successfully',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterCreateOrder: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create order', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// PUT /waiters/orders/<code>/add-product - Add product to existing order
  /// Body: { "waiterId": 1, "productId": 5, "quantity": 2, "components": [...] }
  Future<Response> _waiterAddProductToOrder(Request request, String code) async {
    try {
      final database = _ref.read(databaseProvider);
      final logService = OrderLogService(database);
      final body = await request.readAsString();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final waiterId = json['waiterId'] as int?;
      final productId = json['productId'] as int?;
      final variantId = json['variantId'] as int?;
      final quantity = json['quantity'] as int? ?? 1;
      final productNote = json['note'] as String?;
      final components = json['components'] as List<dynamic>? ?? [];

      if (waiterId == null || productId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'waiterId and productId are required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get order
      final order = await (database.select(database.orders)
        ..where((o) => o.code.equals(code)))
        .getSingleOrNull();

      if (order == null) {
        return Response.notFound(
          jsonEncode({'error': 'Order not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Verify waiter owns this order
      if (order.waiterId != waiterId) {
        return Response(
          403,
          body: jsonEncode({'error': 'Not authorized to modify this order'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Get product details
      final product = await (database.select(database.products)
        ..where((p) => p.id.equals(productId)))
        .getSingleOrNull();

      if (product == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Product not found'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Use variant price/TVA if a variantId is provided
      double unitPrice = product.finalPrice;
      double unitTva = product.tvaAmount;
      double unitDiscount = product.discountAmount;

      if (variantId != null) {
        final variant = await (database.select(database.productVariants)
          ..where((v) => v.id.equals(variantId)))
          .getSingleOrNull();
        if (variant != null) {
          unitPrice = variant.price;
          unitTva = variant.tvaAmount;
          unitDiscount = 0.0;
        }
      }

      // Insert product
      final orderProductId = await database.into(database.orderProducts).insert(
        OrderProductsCompanion.insert(
          orderId: order.id,
          productId: productId,
          variantId: drift.Value(variantId),
          quantity: drift.Value(quantity),
          unitaryPrice: unitPrice,
          unitaryDiscount: drift.Value(unitDiscount),
          unitaryTva: drift.Value(unitTva),
          note: drift.Value(productNote),
          state: const drift.Value('PENDING'),
        ),
      );

      // Insert components
      for (final compJson in components) {
        final componentId = compJson['componentId'] as int;
        final compQuantity = compJson['quantity'] as int? ?? 1;
        final price = (compJson['price'] as num?)?.toDouble() ?? 0.0;

        await database.into(database.orderProductComponents).insert(
          OrderProductComponentsCompanion.insert(
            orderProductId: orderProductId,
            componentId: componentId,
            quantity: drift.Value(compQuantity),
            price: drift.Value(price),
            isSpecial: const drift.Value(false),
          ),
        );
      }

      // Update order timestamp
      await (database.update(database.orders)..where((o) => o.id.equals(order.id)))
        .write(OrdersCompanion(updatedAt: drift.Value(DateTime.now())));

      // Log update
      await logService.logOrderUpdated(order.id, 'Product added by waiter #$waiterId');

      return Response.ok(
        jsonEncode({'message': 'Product added to order successfully'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e, stackTrace) {
      print('❌ Error in _waiterAddProductToOrder: $e');
      print(stackTrace);
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to add product', 'details': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
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
      cancellationReason: order.cancellationReason,
      createdAt: order.createdAt,
      updatedAt: order.updatedAt,
    );
  }

  // ==================== GETTERS ====================

  bool get isRunning => _isRunning;
  int get port => _port;
  String? get serverPassword => _serverPassword;
}


import 'dart:async';

import 'package:cmdecrea/cmdecrea.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posecrea/data/database/app_database.dart';
import 'package:uuid/uuid.dart';
import '../domain/models/socket_models.dart';
import '../domain/models/order_events.dart';
import '../providers/database_providers.dart';
import '../providers/socket_order_providers.dart';
import '../providers/device_providers.dart';
import '../providers/order_provider.dart';

final cmdecreaClientProvider = Provider<CmdecreaClient>((ref) {
  final client = CmdecreaClient();
  ref.onDispose(() => client.dispose());
  return client;
});

final connectionStateProvider = StreamProvider<ConnectionEvent>((ref) {
  final client = ref.watch(cmdecreaClientProvider);
  return client.connectionStream;
});

// socket service provider
final socketServiceProvider = Provider<SocketService>((ref) {
  final client = ref.watch(cmdecreaClientProvider);
  final service = SocketService(client, ref);
  ref.onDispose(() => service.close());
  return service;
});

// Provider for discovered devices
final discoveredDevicesProvider = StateNotifierProvider<DiscoveredDevicesNotifier, List<DeviceInfo>>((ref) {
  return DiscoveredDevicesNotifier(ref.watch(cmdecreaClientProvider));
});

class DiscoveredDevicesNotifier extends StateNotifier<List<DeviceInfo>> {
  final CmdecreaClient client;
  StreamSubscription? _subscription;

  DiscoveredDevicesNotifier(this.client) : super([]) {
    _subscription = client.deviceDiscoveryStream.listen((device) {
      state = [...state, device];
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

enum CommandTypes {


  newOrder ('NEW_ORDER'),
  orderUpdate ('ORDER_UPDATE'),
  orderStatusChanged ('ORDER_STATUS_CHANGED'),
  orderProductStateChanged ('ORDER_PRODUCT_STATE_CHANGED');
  final String value;
  const CommandTypes(this.value);
}




class SocketService {
  final CmdecreaClient _client;
  final Ref _ref;
  final List<StreamSubscription> _subscriptions = [];
  final _uuid = const Uuid();


  SocketService(this._client, this._ref);

  Future<void> start({
    required String deviceId,
    required String deviceName,
    required DeviceRole role,
    int? port,
  }) async
  {
    // Initialize socket client
    await _client.initialize(
      deviceId: deviceId,
      deviceName: deviceName,
      role: role,
      port: port,
    );

    // Start discovery
    await _client.startDiscovery();

    // Start listening to orders and forward to connected devices
    _listenToOrders();

    // Listen to incoming commands
    _listenToCommands();
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _client.stopDiscovery();
    await _client.dispose();
  }

  // Scan network for available devices
  Future<List<DeviceInfo>> scanNetwork() async {
    return await CmdecreaClient.scanNetwork(timeout: Duration(seconds: 5));
  }

  void _listenToOrders() {
    // Listen to repository events instead of database directly
    final repository = _ref.read(orderRepositoryProvider);

    final subscription = repository.events.listen((event) async {
      await _handleOrderEvent(event);
    });

    _subscriptions.add(subscription);
  }

  /// Handle different order events from the repository
  Future<void> _handleOrderEvent(OrderEvent event) async {
    if (event is OrderInsertedEvent) {
      await _onOrderInserted(event);
    } else if (event is OrderUpdatedEvent) {
      await _onOrderUpdated(event);
    } else if (event is OrderStatusChangedEvent) {
      await _onOrderStatusChanged(event);
    } else if (event is OrderProductStateChangedEvent) {
      await _onOrderProductStateChanged(event);
    } else if (event is OrderHeldEvent) {
      await _onOrderHeld(event);
    } else if (event is OrderItemsChangedEvent) {
      await _onOrderItemsChanged(event);
    }
  }

  /// Called when a new order is inserted
  Future<void> _onOrderInserted(OrderInsertedEvent event) async {

    // Get full order details
    final repository = _ref.read(socketOrderRepositoryProvider);
    final socketOrder = await repository.getOrderWithDetails(event.orderId);
    if (socketOrder == null) {
      print('⚠️ Could not load order details for order ${event.orderId}');
      return;
    }


    if (event.status == 'PENDING') {
      final stationIds = socketOrder.products
          .where((p) => p.stationId != null)
          .map((p) => p.stationId!)
          .toSet();

      if (stationIds.isEmpty) {
        print('⚠️ Order ${event.orderCode} has no products assigned to stations');
        return;
      }


      for (final stationId in stationIds) {
        try {
          await sendOrderToStation(socketOrder, stationId);
          print('✅ Sent order ${event.orderCode} to station $stationId');
        } catch (e) {
          print('❌ Failed to send to station $stationId: $e');
        }
      }
    }

  }

  /// Called when an order is updated
  Future<void> _onOrderUpdated(OrderUpdatedEvent event) async {
    print('🔄 Order updated: ID ${event.orderId}');

    // Get full order details
    final repository = _ref.read(socketOrderRepositoryProvider);
    final socketOrder = await repository.getOrderWithDetails(event.orderId);
    if (socketOrder == null) return;

    // ===== IMPLEMENT YOUR LOGIC HERE =====

    // Example: Broadcast update to all devices
    // await broadcastOrder(socketOrder);

    // ===== END OF YOUR LOGIC =====
  }

  /// Called when order status changes
  Future<void> _onOrderStatusChanged(OrderStatusChangedEvent event) async {
    print('📊 Order ${event.orderId} status: ${event.oldStatus} → ${event.newStatus}');

    // ===== IMPLEMENT YOUR LOGIC HERE =====

    // Example: Notify devices of status change
    final command = Command(
      id: _uuid.v4(),
      type: 'ORDER_STATUS_CHANGED',
      payload: {
        'orderId': event.orderId,
        'oldStatus': event.oldStatus,
        'newStatus': event.newStatus,
      },
      timestamp: DateTime.now(),
      senderId: _client.localDevice.id,
      targetId: null,
    );
    await _client.sendToAll(command);

    // ===== END OF YOUR LOGIC =====
  }

  /// Called when order product state changes
  Future<void> _onOrderProductStateChanged(OrderProductStateChangedEvent event) async {
    print('🍳 Product ${event.orderProductId} state: ${event.oldState} → ${event.newState}');

    // ===== IMPLEMENT YOUR LOGIC HERE =====

    // Example: Notify devices
    final command = Command(
      id: _uuid.v4(),
      type: 'ORDER_PRODUCT_STATE_CHANGED',
      payload: {
        'orderProductId': event.orderProductId,
        'orderId': event.orderId,
        'oldState': event.oldState,
        'newState': event.newState,
      },
      timestamp: DateTime.now(),
      senderId: _client.localDevice.id,
      targetId: null,
    );
    await _client.sendToAll(command);

    // ===== END OF YOUR LOGIC =====
  }

  /// Called when order is held
  Future<void> _onOrderHeld(OrderHeldEvent event) async {
    print('⏸️ Order held: ${event.orderCode} (ID: ${event.orderId})');

    // ===== IMPLEMENT YOUR LOGIC HERE =====
    // Maybe don't send held orders to kitchen
    // ===== END OF YOUR LOGIC =====
  }

  /// Called when order items are changed
  Future<void> _onOrderItemsChanged(OrderItemsChangedEvent event) async {
    print('📦 Order ${event.orderId} items changed (${event.itemCount} items)');

    // ===== IMPLEMENT YOUR LOGIC HERE =====
    // Maybe re-send to kitchen if items changed
    // ===== END OF YOUR LOGIC =====
  }


  void _listenToCommands() {
    final repository = _ref.read(orderRepositoryProvider);
    final currentUser = _ref.read(currentUserProvider);

    _client.listenForCommand('UPDATE_ORDER', (command) {
      print("new order update");

      // Handle order updates from other devices
      final orderId =  int.parse(command.payload['id']);
      final status = command.payload['status'] as String;
      repository.updateOrderStatus(orderId, status.toUpperCase());
    });

    _client.listenForCommand('UPDATE_ORDER_PRODUCT', (command) async {
      print("new product update");

      // Handle order product updates from other devices
      final orderId =  int.parse(command.payload['orderId']);
      final productId = command.payload['productId'] as int;
      final status = command.payload['status'] as String;
      repository
          .updateOrderProductState(orderId, productId,
          status.toUpperCase());
    });

    _client.listenForCommand('ORDER_STATE_CHANGED', (command) {
      // Handle order state changes from KDS
      print('Order state changed: ${command.payload}');
    });

    _client.listenForCommand('new_order', (command) async {
      // Handle order state changes from KDS


      repository.saveOrder(
          SocketOrderModel.fromJson(command.payload).toCurrentOrder(),
          currentUser!.id);
      print("aha");
    });


    _client.listenForAllCommands((cmd){
        print(cmd.type);

    });
  }


  // Business functions

  /// Send order to specific KDS
  Future<void> sendOrderToKDS(SocketOrderModel order, int kdsId) async {
    try {
      // Get KDS device info from database
      final kds = await _ref.read(kdsProvider(kdsId).future).timeout(
        Duration(seconds: 5),
        onTimeout: () => null,
      );

      if (kds == null) {
        print('❌ KDS $kdsId not found');
        return;
      }

      if (!kds.isActive) {
        print('❌ KDS $kdsId is inactive');
        return;
      }

      final targetDeviceId = kds.name;

      // Check if device is connected
      // if (!_client.connectedDeviceIds.contains(targetDeviceId)) {
      //   print('⚠️ KDS ${kds.name} (ID: $targetDeviceId) is NOT connected');
      //   print('   Connected devices: ${_client.connectedDeviceIds}');
      //   return;
      // }

      // Verify connection is healthy before sending
      final isHealthy = await _client.testConnection();
      if (!isHealthy) {
        print('⚠️ Connection test failed for KDS ${kds.name}');
        return;
      }


      final command = Command(
        id: _uuid.v4(),
        type: 'NEW_ORDER',
        payload: order.toKdsOrder().toJson(),
        timestamp: DateTime.now(),
        senderId: _client.localDevice.id,
        targetId: targetDeviceId,
      );

      // await _client.sendToDevice(targetDeviceId, command);
      await _client.sendToDevice(targetDeviceId, command);
      print('✅ Order sent successfully to KDS ${kds.name}');

    } catch (e, stackTrace) {
      print('❌ Error sending order to KDS $kdsId: $e');
      print('   Stack trace: $stackTrace');
      // Don't rethrow - log and continue
    }
  }

  /// Send order to specific Kiosk
  Future<void> sendOrderToKiosk(SocketOrderModel order, int kioskId) async {
    final kioskAsync = _ref.read(kioskProvider(kioskId).future);
    final kiosk = await kioskAsync;

    if (kiosk == null || !kiosk.isActive) {
      throw Exception('Kiosk not found or inactive');
    }

    final command = Command(
      id: _uuid.v4(),
      type: 'NEW_ORDER',
      payload: order.toJson(),
      timestamp: DateTime.now(),
      senderId: _client.localDevice.id,
      targetId: kiosk.id.toString(),
    );

    await _client.sendToDevice(kiosk.id.toString(), command);
  }

  /// Broadcast order to all active devices
  Future<void> broadcastOrder(SocketOrderModel order) async {
    await _broadcastOrder(order);
  }

  Future<void> _broadcastOrder(SocketOrderModel order) async {
    final command = Command(
      id: _uuid.v4(),
      type: 'NEW_ORDER',
      payload: order.toJson(),
      timestamp: DateTime.now(),
      senderId: _client.localDevice.id,
      targetId: null, // Broadcast to all
    );

    await _client.sendToAll(command);
  }

  /// Send order to station's KDS devices
  Future<void> sendOrderToStation(SocketOrderModel order, int stationId) async {
    // Get all KDS devices for this station
    final kdsListAsync = _ref.read(kdsListByStationProvider(stationId).future);
    final kdsList = await kdsListAsync;

    if (kdsList.isEmpty) {
      print('⚠️ No KDS devices found for station $stationId');
      return;
    }

    // Filter order to only include products for this station
    final filteredProducts = order.products
        .where((p) => p.stationId == stationId)
        .toList();

    if (filteredProducts.isEmpty) {
      return; // No products for this station
    }

    final filteredOrder = SocketOrderModel(
      id: order.id,
      code: order.code,
      status: order.status,
      type: order.type,
      priority: order.priority,
      date: order.date,
      tableId: order.tableId,
      tableName: order.tableName,
      clientId: order.clientId,
      clientName: order.clientName,
      products: filteredProducts,
      note: order.note,
    );

    // Send to all active KDS devices for this station
    for (final kds in kdsList) {
      if (kds.isActive) {
        await sendOrderToKDS(filteredOrder, kds.id);
      }
    }
  }

  /// Update order product state and notify devices
  Future<void> updateOrderProductState(int orderProductId, String state) async {
    final repository = _ref.read(orderRepositoryProvider);
    await repository.updateOrderStatus(orderProductId, state);
    // Event will be emitted by repository and handled by _onOrderProductStateChanged
  }

  /// Update order status and notify devices
  Future<void> updateOrderStatus(int orderId, String status) async {
    final repository = _ref.read(orderRepositoryProvider);
    await repository.updateOrderStatus(orderId, status);
    // Event will be emitted by repository and handled by _onOrderStatusChanged
  }

  /// Get all active devices
  Future<List<SocketDeviceModel>> getActiveDevices() async {
    final devicesAsync = _ref.read(allSocketDevicesProvider.future);
    final devices = await devicesAsync;
    return devices.where((d) => d.isActive).toList();
  }

  /// Send custom command to device
  Future<void> sendCommandToDevice(Command command, String deviceId) async {
    await _client.sendToDevice(deviceId, command);
  }

  /// Send custom command to all devices
  Future<void> broadcastCommand(Command command) async {
    await _client.sendToAll(command);
  }

  /// Listen to specific command type
  void listenForCommand(String commandType, void Function(Command) callback) {
    _client.listenForCommand(commandType, callback);
  }

  /// Listen to all commands
  void listenForAllCommands(void Function(Command) callback) {
    _client.listenForAllCommands(callback);
  }

  /// Remove command listener
  void removeCommandListener(String commandType, void Function(Command) callback) {
    _client.removeCommandListener(commandType, callback);
  }

  /// Get local device info
  DeviceInfo get localDevice => _client.localDevice;

  /// Get discovered devices
  List<DeviceInfo> get discoveredDevices => _client.discoveredDevices;

  /// Get discovered hosts
  List<DeviceInfo> get discoveredHosts => _client.discoveredHosts;

  /// Check if connected
  bool get isConnected => _client.isConnected;

  /// Listen to connection events
  Stream<ConnectionEvent> get connectionStream => _client.connectionStream;

  /// Listen to device discovery
  Stream<DeviceInfo> get deviceDiscoveryStream => _client.deviceDiscoveryStream;

  /// Connect to host (for devices)
  Future<void> connectToHost(DeviceInfo hostInfo) async {
    await _client.connectToHost(hostInfo);
  }

  /// Test connection
  Future<bool> testConnection() async {
    return await _client.testConnection();
  }

}

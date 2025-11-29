// Order Events for Socket Service Integration

/// Base class for all order events
abstract class OrderEvent {
  final DateTime timestamp;

  OrderEvent() : timestamp = DateTime.now();
}

/// Event fired when a new order is inserted
class OrderInsertedEvent extends OrderEvent {
  final int orderId;
  final String orderCode;
  final String status;

  OrderInsertedEvent({
    required this.orderId,
    required this.orderCode,
    required this.status,
  });
}

/// Event fired when an order is updated
class OrderUpdatedEvent extends OrderEvent {
  final int orderId;
  final String? oldStatus;
  final String? newStatus;

  OrderUpdatedEvent({
    required this.orderId,
    this.oldStatus,
    this.newStatus,
  });
}

/// Event fired when an order status changes
class OrderStatusChangedEvent extends OrderEvent {
  final int orderId;
  final String oldStatus;
  final String newStatus;

  OrderStatusChangedEvent({
    required this.orderId,
    required this.oldStatus,
    required this.newStatus,
  });
}

/// Event fired when an order product state changes
class OrderProductStateChangedEvent extends OrderEvent {
  final int orderProductId;
  final int orderId;
  final String oldState;
  final String newState;

  OrderProductStateChangedEvent({
    required this.orderProductId,
    required this.orderId,
    required this.oldState,
    required this.newState,
  });
}

/// Event fired when an order is deleted
class OrderDeletedEvent extends OrderEvent {
  final int orderId;

  OrderDeletedEvent({required this.orderId});
}

/// Event fired when order is held
class OrderHeldEvent extends OrderEvent {
  final int orderId;
  final String orderCode;

  OrderHeldEvent({
    required this.orderId,
    required this.orderCode,
  });
}

/// Event fired when order items are added/modified
class OrderItemsChangedEvent extends OrderEvent {
  final int orderId;
  final int itemCount;

  OrderItemsChangedEvent({
    required this.orderId,
    required this.itemCount,
  });
}


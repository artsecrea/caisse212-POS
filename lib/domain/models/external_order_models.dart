/// Models for the external order queue (DealUp / WhatsApp / future sources).

class ExternalQueueComponent {
  final int componentId;
  final int quantity;

  const ExternalQueueComponent({
    required this.componentId,
    required this.quantity,
  });

  factory ExternalQueueComponent.fromJson(Map<String, dynamic> j) =>
      ExternalQueueComponent(
        componentId: j['componentId'] as int,
        quantity: j['quantity'] as int? ?? 1,
      );
}

class ExternalQueueOrderItem {
  final int productId;
  final int? variantId;
  final int quantity;
  final String? note;
  final List<ExternalQueueComponent> components;

  const ExternalQueueOrderItem({
    required this.productId,
    this.variantId,
    required this.quantity,
    this.note,
    required this.components,
  });

  factory ExternalQueueOrderItem.fromJson(Map<String, dynamic> j) =>
      ExternalQueueOrderItem(
        productId: j['productId'] as int,
        variantId: j['variantId'] as int?,
        quantity: j['quantity'] as int? ?? 1,
        note: j['note'] as String?,
        components: (j['components'] as List<dynamic>? ?? [])
            .map((c) => ExternalQueueComponent.fromJson(
                c as Map<String, dynamic>))
            .toList(),
      );
}

class ExternalQueueOrder {
  final String type; // DELIVERY, TAKE_AWAY, DINE_IN
  final String? customerName;
  final String? customerPhone;
  final String? note;
  final List<ExternalQueueOrderItem> items;

  const ExternalQueueOrder({
    required this.type,
    this.customerName,
    this.customerPhone,
    this.note,
    required this.items,
  });

  factory ExternalQueueOrder.fromJson(Map<String, dynamic> j) =>
      ExternalQueueOrder(
        type: j['type'] as String? ?? 'TAKE_AWAY',
        customerName: j['customerName'] as String?,
        customerPhone: j['customerPhone'] as String?,
        note: j['note'] as String?,
        items: (j['items'] as List<dynamic>? ?? [])
            .map((i) => ExternalQueueOrderItem.fromJson(
                i as Map<String, dynamic>))
            .toList(),
      );
}

class ExternalQueueItem {
  final int id;
  final String orderCode;
  final String source; // 'DEALUP', 'WHATSAPP', etc.
  final String status; // 'PENDING', 'ACKNOWLEDGED'
  final int? customerId;
  final ExternalQueueOrder order;
  final DateTime createdAt;

  const ExternalQueueItem({
    required this.id,
    required this.orderCode,
    required this.source,
    required this.status,
    this.customerId,
    required this.order,
    required this.createdAt,
  });

  factory ExternalQueueItem.fromJson(Map<String, dynamic> j) =>
      ExternalQueueItem(
        id: j['id'] as int,
        orderCode: j['orderCode'] as String,
        source: j['source'] as String? ?? 'EXTERNAL',
        status: j['status'] as String? ?? 'PENDING',
        customerId: j['customerId'] as int?,
        order: ExternalQueueOrder.fromJson(
            j['order'] as Map<String, dynamic>),
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  String get sourceLabel {
    switch (source.toUpperCase()) {
      case 'DEALUP':
        return 'DealUp';
      case 'WHATSAPP':
        return 'WhatsApp';
      default:
        return source;
    }
  }
}

class AcknowledgeResult {
  final int queueItemId;
  final String orderCode;
  final int orderId;
  final String status;

  const AcknowledgeResult({
    required this.queueItemId,
    required this.orderCode,
    required this.orderId,
    required this.status,
  });

  factory AcknowledgeResult.fromJson(Map<String, dynamic> j) =>
      AcknowledgeResult(
        queueItemId: j['queueItemId'] as int,
        orderCode: j['orderCode'] as String,
        orderId: j['orderId'] as int,
        status: j['status'] as String? ?? 'ACKNOWLEDGED',
      );
}

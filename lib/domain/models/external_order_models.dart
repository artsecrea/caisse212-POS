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

/// Server response shape for both confirm and cancel queue endpoints.
///
/// Backend no longer carries an `orderId` — the POS owns the order rows
/// (they live in the local `orders` table and sync up via the normal
/// order endpoints). The server only tracks queue state (`CONFIRMED`,
/// `CANCELLED`) and forwards it to DealUp.
///
/// Class name kept for now to minimise churn at call sites; the field
/// shape reflects the new contract.
class QueueStateResult {
  final int queueItemId;
  final String? orderCode;
  final String status; // CONFIRMED | CANCELLED

  const QueueStateResult({
    required this.queueItemId,
    required this.orderCode,
    required this.status,
  });

  factory QueueStateResult.fromJson(Map<String, dynamic> j) =>
      QueueStateResult(
        queueItemId: j['queueItemId'] as int,
        orderCode: j['orderCode'] as String?,
        status: j['status'] as String? ?? 'CONFIRMED',
      );
}

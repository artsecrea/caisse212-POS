/// Models for the external order queue (DealUp / WhatsApp / future sources).

class ExternalQueueComponent {
  /// 0 when the platform's addon has no local component yet — the POS resolves
  /// it from [externalComponentId] instead.
  final int componentId;
  final int quantity;

  /// The platform's own id for this addon. The key everything is matched on.
  final String? externalComponentId;

  /// The platform's label, for showing what could not be resolved.
  final String? name;

  /// The server's verdict. False means it arrived with no local component.
  final bool mapped;

  /// What this option was actually charged at, per parent unit, as validated
  /// with the customer — after any free allowance the platform applied. Null
  /// on payloads that predate the money moving onto the components, where the
  /// local catalogue price is the only figure available.
  final double? price;

  const ExternalQueueComponent({
    required this.componentId,
    required this.quantity,
    this.externalComponentId,
    this.name,
    this.mapped = true,
    this.price,
  });

  factory ExternalQueueComponent.fromJson(Map<String, dynamic> j) =>
      ExternalQueueComponent(
        // Tolerant of null AND of a non-int: an unmapped addon arrives as 0 or
        // absent, and `as int` on that threw, taking the whole ticket down.
        componentId: (j['componentId'] as num?)?.toInt() ?? 0,
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        externalComponentId: (j['externalComponentId'] ??
                j['externalProductId'] ??
                j['externalId'])
            ?.toString(),
        name: j['name'] as String?,
        mapped: j['mapped'] as bool? ?? ((j['componentId'] as num?) ?? 0) > 0,
        // 0.00 is a real price here — the free half of a split selection —
        // so absent and zero must stay distinguishable.
        price: (j['price'] as num?)?.toDouble(),
      );

  ExternalQueueComponent copyWith({int? componentId, bool? mapped}) =>
      ExternalQueueComponent(
        componentId: componentId ?? this.componentId,
        quantity: quantity,
        externalComponentId: externalComponentId,
        name: name,
        mapped: mapped ?? this.mapped,
        price: price,
      );
}

class ExternalQueueOrderItem {
  /// 0 when the server could not resolve the line. The POS then resolves it
  /// itself from [externalProductId] — see `ExternalItemResolver`.
  final int productId;
  final int? variantId;
  final int quantity;
  final String? note;
  final List<ExternalQueueComponent> components;

  /// The platform's item id. **This is the key the whole match runs on** —
  /// a Glovo item id, or a Kooul SKU that equals our `products.reference`.
  final String? externalProductId;

  /// The platform's own label. All there is to show for a line that cannot be
  /// resolved, so it is worth keeping even when the match succeeds.
  final String? name;

  /// The platform's quoted unit price. Reference only — the POS re-prices from
  /// its own catalogue when it builds the order.
  final double? unitPrice;

  /// The server's verdict at enqueue time. The POS may still resolve a line the
  /// server could not, because the payload is frozen when it is queued while the
  /// POS matches against a catalogue that has moved on since.
  final bool mapped;

  const ExternalQueueOrderItem({
    required this.productId,
    this.variantId,
    required this.quantity,
    this.note,
    required this.components,
    this.externalProductId,
    this.name,
    this.unitPrice,
    this.mapped = true,
  });

  factory ExternalQueueOrderItem.fromJson(Map<String, dynamic> j) =>
      ExternalQueueOrderItem(
        productId: (j['productId'] as num?)?.toInt() ?? 0,
        variantId: (j['variantId'] as num?)?.toInt(),
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        note: j['note'] as String?,
        components: (j['components'] as List<dynamic>? ?? [])
            .map((c) => ExternalQueueComponent.fromJson(
                c as Map<String, dynamic>))
            .toList(),
        externalProductId:
            (j['externalProductId'] ?? j['externalId'])?.toString(),
        name: j['name'] as String?,
        unitPrice: (j['unitPrice'] as num?)?.toDouble(),
        mapped: j['mapped'] as bool? ?? ((j['productId'] as num?) ?? 0) > 0,
      );

  ExternalQueueOrderItem copyWith({
    int? productId,
    int? variantId,
    bool? mapped,
    List<ExternalQueueComponent>? components,
  }) =>
      ExternalQueueOrderItem(
        productId: productId ?? this.productId,
        variantId: variantId ?? this.variantId,
        quantity: quantity,
        note: note,
        components: components ?? this.components,
        externalProductId: externalProductId,
        name: name,
        unitPrice: unitPrice,
        mapped: mapped ?? this.mapped,
      );
}

class ExternalQueueOrder {
  final String type; // DELIVERY, TAKE_AWAY, DINE_IN
  final String? customerName;
  final String? customerPhone;
  final String? note;
  final String? address;
  final List<ExternalQueueOrderItem> items;

  /// Server's verdict on whether every line resolves to a local product.
  /// **Confirm must be blocked while this is true** — accepting an order the
  /// kitchen cannot build is worse than making the cashier wait for the back
  /// office to map it.
  final bool hasUnmappedItems;

  /// Courier details, DELIVERY orders on a platform only.
  final String? courierName;
  final String? courierPhone;

  /// Platform-reported total. Display only — the POS re-prices from its own
  /// catalogue when it builds the local order, so this is for sanity-checking
  /// against what the customer was charged, not for taking money.
  final double? total;

  // ── Marketplace extras. All null for DealUp/Web, which are our own. ───────

  /// The code the COURIER says out loud. Ours means nothing to them, so this is
  /// what belongs in big type on the ticket.
  final String? externalOrderCode;

  /// Handover code, where the platform uses one.
  final String? pickUpCode;

  /// `CASH` = the money is collected here, at handover. `DELAYED` = the
  /// platform already charged the customer and nothing is owed at the counter.
  /// Getting this wrong means either handing food over unpaid or charging
  /// someone twice.
  final String? paymentMethod;
  final String? currency;

  /// Customer allergy text. Safety-critical and therefore never merged into the
  /// general note — it has to be renderable on its own, loudly.
  final String? allergyInfo;
  final String? specialRequirements;
  final bool? cutleryRequested;

  final DateTime? estimatedPickupTime;
  final double? deliveryFee;
  final double? estimatedTotalPrice;

  /// What the customer pays in total on the platform's side.
  final double? totalCustomerToPay;

  /// Customer collects in person rather than a courier coming.
  final bool? isPickedUpByCustomer;

  bool get isCashOnHandover =>
      (paymentMethod ?? '').toUpperCase() == 'CASH';

  bool get hasAllergyInfo => (allergyInfo ?? '').trim().isNotEmpty;

  const ExternalQueueOrder({
    required this.type,
    this.customerName,
    this.customerPhone,
    this.note,
    this.address,
    required this.items,
    this.hasUnmappedItems = false,
    this.courierName,
    this.courierPhone,
    this.total,
    this.externalOrderCode,
    this.pickUpCode,
    this.paymentMethod,
    this.currency,
    this.allergyInfo,
    this.specialRequirements,
    this.cutleryRequested,
    this.estimatedPickupTime,
    this.deliveryFee,
    this.estimatedTotalPrice,
    this.totalCustomerToPay,
    this.isPickedUpByCustomer,
  });

  /// Only the two fields local resolution rewrites. Everything else on a queue
  /// preview is the platform's word and is carried through untouched.
  ExternalQueueOrder copyWith({
    List<ExternalQueueOrderItem>? items,
    bool? hasUnmappedItems,
  }) =>
      ExternalQueueOrder(
        type: type,
        customerName: customerName,
        customerPhone: customerPhone,
        note: note,
        address: address,
        items: items ?? this.items,
        hasUnmappedItems: hasUnmappedItems ?? this.hasUnmappedItems,
        courierName: courierName,
        courierPhone: courierPhone,
        total: total,
        externalOrderCode: externalOrderCode,
        pickUpCode: pickUpCode,
        paymentMethod: paymentMethod,
        currency: currency,
        allergyInfo: allergyInfo,
        specialRequirements: specialRequirements,
        cutleryRequested: cutleryRequested,
        estimatedPickupTime: estimatedPickupTime,
        deliveryFee: deliveryFee,
        estimatedTotalPrice: estimatedTotalPrice,
        totalCustomerToPay: totalCustomerToPay,
        isPickedUpByCustomer: isPickedUpByCustomer,
      );

  factory ExternalQueueOrder.fromJson(Map<String, dynamic> j) =>
      ExternalQueueOrder(
        type: j['type'] as String? ?? 'TAKE_AWAY',
        customerName: j['customerName'] as String?,
        customerPhone: j['customerPhone'] as String?,
        note: j['note'] as String?,
        address: j['address'] as String?,
        items: (j['items'] as List<dynamic>? ?? [])
            .map((i) => ExternalQueueOrderItem.fromJson(
                i as Map<String, dynamic>))
            .toList(),
        // Absent → false. A server that predates the flag must not make every
        // order look unconfirmable.
        hasUnmappedItems: j['hasUnmappedItems'] as bool? ?? false,
        courierName: j['courierName'] as String?,
        courierPhone: j['courierPhone'] as String?,
        total: (j['total'] as num?)?.toDouble(),
        externalOrderCode: j['externalOrderCode'] as String?,
        pickUpCode: j['pickUpCode'] as String?,
        paymentMethod: j['paymentMethod'] as String?,
        currency: j['currency'] as String?,
        allergyInfo: j['allergyInfo'] as String?,
        specialRequirements: j['specialRequirements'] as String?,
        cutleryRequested: j['cutleryRequested'] as bool?,
        estimatedPickupTime: j['estimatedPickupTime'] == null
            ? null
            : DateTime.tryParse(j['estimatedPickupTime'].toString()),
        deliveryFee: (j['deliveryFee'] as num?)?.toDouble(),
        estimatedTotalPrice: (j['estimatedTotalPrice'] as num?)?.toDouble(),
        totalCustomerToPay: (j['totalCustomerToPay'] as num?)?.toDouble(),
        isPickedUpByCustomer: j['isPickedUpByCustomer'] as bool?,
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

  /// The platform's own order id. Echoed back on every re-sync of this order so
  /// the server can close the reconciliation loop; without it the server has to
  /// backfill from the queue by code.
  final String? externalOrderId;

  /// Which platform store fed this order (a business can have several).
  final String? externalStoreId;

  /// Set once the confirmed order has been synced back — that sync is what
  /// flips the item to ACKNOWLEDGED.
  final int? acknowledgedOrderId;
  final DateTime? acknowledgedAt;

  const ExternalQueueItem({
    required this.id,
    required this.orderCode,
    required this.source,
    required this.status,
    this.customerId,
    required this.order,
    required this.createdAt,
    this.externalOrderId,
    this.externalStoreId,
    this.acknowledgedOrderId,
    this.acknowledgedAt,
  });

  factory ExternalQueueItem.fromJson(Map<String, dynamic> j) =>
      ExternalQueueItem(
        // Defensive: an id arriving as a double (JSON number) must not crash the
        // whole list — see the station null-description incident.
        id: (j['id'] as num).toInt(),
        orderCode: j['orderCode']?.toString() ?? '',
        source: j['source'] as String? ?? 'EXTERNAL',
        status: j['status'] as String? ?? 'PENDING',
        customerId: (j['customerId'] as num?)?.toInt(),
        order: ExternalQueueOrder.fromJson(
            Map<String, dynamic>.from((j['order'] as Map?) ?? const {})),
        createdAt:
            DateTime.tryParse('${j['createdAt'] ?? ''}') ?? DateTime.now(),
        externalOrderId: j['externalOrderId']?.toString(),
        externalStoreId: j['externalStoreId']?.toString(),
        acknowledgedOrderId: (j['acknowledgedOrderId'] as num?)?.toInt(),
        acknowledgedAt: DateTime.tryParse('${j['acknowledgedAt'] ?? ''}'),
      );

  bool get isPending => status.toUpperCase() == 'PENDING';
  bool get isConfirmed => status.toUpperCase() == 'CONFIRMED';
  bool get isCancelled => status.toUpperCase() == 'CANCELLED';
  bool get isAcknowledged => status.toUpperCase() == 'ACKNOWLEDGED';

  /// Only a PENDING item with every line mapped may be confirmed.
  bool get canConfirm => isPending && !order.hasUnmappedItems;

  /// Only the preview is ever rewritten — by local resolution. Queue identity
  /// (id, code, status) is the server's and is carried through untouched.
  ExternalQueueItem copyWith({ExternalQueueOrder? order}) => ExternalQueueItem(
        id: id,
        orderCode: orderCode,
        source: source,
        status: status,
        customerId: customerId,
        order: order ?? this.order,
        createdAt: createdAt,
        externalOrderId: externalOrderId,
        externalStoreId: externalStoreId,
        acknowledgedOrderId: acknowledgedOrderId,
        acknowledgedAt: acknowledgedAt,
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

/// Standard page envelope returned by `GET /pos/queue`.
///
/// Carries the server's own totals rather than inferring them from the item
/// count, so the pager can show "page 2 of 4 · 64 orders" honestly even on a
/// partially-filled last page.
class QueuePage {
  final List<ExternalQueueItem> content;
  final int page;
  final int size;
  final int totalElements;
  final int totalPages;
  final bool first;
  final bool last;

  /// Swap the rows, keep the server's paging facts.
  QueuePage copyWith({List<ExternalQueueItem>? content}) => QueuePage(
        content: content ?? this.content,
        page: page,
        size: size,
        totalElements: totalElements,
        totalPages: totalPages,
        first: first,
        last: last,
      );

  const QueuePage({
    this.content = const [],
    this.page = 0,
    this.size = 20,
    this.totalElements = 0,
    this.totalPages = 0,
    this.first = true,
    this.last = true,
  });

  bool get isEmpty => content.isEmpty;

  factory QueuePage.fromJson(Map<String, dynamic> j) {
    final raw = (j['content'] as List<dynamic>? ?? const []);
    final items = <ExternalQueueItem>[];
    for (final r in raw) {
      // One malformed row must not blank the whole page.
      try {
        items.add(ExternalQueueItem.fromJson(Map<String, dynamic>.from(r as Map)));
      } catch (_) {/* skip */}
    }
    final size = (j['size'] as num?)?.toInt() ?? 20;
    final total = (j['totalElements'] as num?)?.toInt() ?? items.length;
    return QueuePage(
      content: items,
      page: (j['page'] as num?)?.toInt() ?? 0,
      size: size,
      totalElements: total,
      // Derive rather than trust a missing field, so the pager still works
      // against a server that omits it.
      totalPages: (j['totalPages'] as num?)?.toInt() ??
          (size > 0 ? ((total + size - 1) ~/ size) : 1),
      first: j['first'] as bool? ?? true,
      last: j['last'] as bool? ?? true,
    );
  }
}

/// `GET /pos/queue/counts` — the numbers behind the filter chips.
class QueueCounts {
  final int total;

  /// Always contains all four source keys, zero-filled, and they are exactly
  /// the values the `source` filter accepts — so the chips are rendered from
  /// this map rather than a hardcoded list that could drift from the server.
  final Map<String, int> bySource;

  const QueueCounts({this.total = 0, this.bySource = const {}});

  /// The canonical order the chips are shown in.
  static const List<String> sourceKeys = ['WEB', 'GLOVO', 'KOOUL', 'OTHER'];

  int countFor(String source) => bySource[source] ?? 0;

  factory QueueCounts.fromJson(Map<String, dynamic> j) {
    final raw = (j['bySource'] as Map?) ?? const {};
    final map = <String, int>{};
    for (final k in sourceKeys) {
      map[k] = (raw[k] as num?)?.toInt() ?? 0;
    }
    // Keep any source the server adds later that we don't know about yet.
    raw.forEach((k, v) {
      final key = k.toString();
      if (!map.containsKey(key)) map[key] = (v as num?)?.toInt() ?? 0;
    });
    return QueueCounts(
      total: (j['total'] as num?)?.toInt() ?? 0,
      bySource: map,
    );
  }
}

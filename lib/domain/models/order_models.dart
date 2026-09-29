// Model for current order item in cart

import '../../data/database/app_database.dart';

class OrderItem {
  final int? id;
  final int productId;
  final String productName;
  final int? variantId;
  final String? variantName;
  final String? imageUrl;
  final double finalPrice; // final price per unit without components
  final double quantity;
  /// Quantity that was persisted to the DB at load time. `null` for items
  /// freshly added to the cart in this session. Used as the **decrement floor**:
  /// cashiers can take back only the quantity they added this session — going
  /// below this value requires `pos:orders:item:modify`.
  final double? savedQuantity;
  final List<OrderItemComponent> components;
  final String? note;
  /// Which course this line belongs to: 1 entrée, 2 plat, 3 dessert.
  ///
  /// Null is the normal state — see `OrderProducts.courseNo`. The kitchen
  /// ticket only splits into sections when the lines on it actually carry
  /// more than one course.
  final int? courseNo;

  final int? ticketId; // null = not paid, number = ticket ID (paid)
  final double discount; // discount amount per item
  final double manualDiscount; // manual discount amount per item
  final double tva; // TVA amount per item
  final String state; // PENDING, ONHOLD, PREPARING, READY, SERVED, etc.
  final DateTime? planStartAt; // Planning start time
  final DateTime? planEndAt; // Planning end time
  final int? planWaiterId; // Assigned waiter for this booking
  final int? planResourceId; // Assigned resource (room/chair/equipment) for this booking
  final DateTime? kdsPrintedAt; // When item was sent to kitchen (KDS ticket printed)
  /// Quantity that has already been sent to the kitchen. Persisted. Lets
  /// `KdsPrintMode.modificationsOnly` fire a ticket for the *added* units when
  /// an already-printed line's quantity increases (delta = quantity - this).
  final double kdsPrintedQuantity;
  /// Transient (never persisted) override for the quantity to render on the
  /// *current* KDS ticket — the modifications-only delta. Null → use [quantity].
  final double? kdsPrintQuantity;
  /// Quantity already put on a printed CUSTOMER order ticket. Persisted, and
  /// the exact counterpart of [kdsPrintedQuantity] for the receipt printer —
  /// see `OrderProducts.orderTicketPrintedQuantity` for why the two are
  /// tracked separately rather than shared.
  final double orderTicketPrintedQuantity;
  /// Transient (never persisted) override for the quantity to render on the
  /// *current* order ticket — the additions-only delta. Null → use [quantity].
  final double? orderTicketPrintQuantity;
  // Scale / weighed-item fields
  final bool isWeighedItem;
  final double? weightKg;
  final double? pricePerKgDisplay;
  /// Unit label from the server (e.g. "kg", "pcs", "box") — nullable.
  final String? unitName;

  /// The individual unit sold, for serial-tracked products.
  ///
  /// Non-null means this line is exactly one physical unit: quantity is forced
  /// to 1 and the line never merges with another of the same product, because
  /// two units are two different serials. [serialNumber] is carried alongside
  /// purely so the basket, receipt and KDS can show it without a lookup.
  final int? serialId;
  final String? serialNumber;

  /// Backend `order_products.id` for this line, when the server has seen it.
  ///
  /// Carried on the model only so [OrderRepository.updateOrder] can put it
  /// back: that save deletes and re-inserts every unpaid row, and a line that
  /// came back without its server id looks to the next push like a brand new
  /// one — the backend grows a duplicate, and refunds (which reference the
  /// server's line id, not ours) point at a row nobody sold.
  final int? serverId;

  OrderItem({
    this.id,
    required this.productId,
    required this.productName,
    this.variantId,
    this.variantName,
    this.imageUrl,
    required this.finalPrice, // final price per unit without components
    this.quantity = 1.0,
    this.savedQuantity,
    this.components = const [],
    this.note,
    this.courseNo,
    this.ticketId,
    this.discount = 0.0,
    this.manualDiscount = 0.0,
    this.tva = 0.0,
    this.state = 'PENDING',
    this.planStartAt,
    this.planEndAt,
    this.planWaiterId,
    this.planResourceId,
    this.kdsPrintedAt,
    this.kdsPrintedQuantity = 0.0,
    this.kdsPrintQuantity,
    this.orderTicketPrintedQuantity = 0.0,
    this.orderTicketPrintQuantity,
    this.isWeighedItem = false,
    this.weightKg,
    this.pricePerKgDisplay,
    this.unitName,
    this.serialId,
    this.serialNumber,
    this.serverId,
  });

  /// Returns the display name - variant name if available, otherwise product name
  String get displayName => variantName ?? productName;

  double get componentTotal {
    return components.fold(0.0, (sum, comp) => sum + (comp.price * comp.quantity));
  }

  // Base price per item without tax or any discount (but with components)
  // finalPrice = basePrice + tva - prediscount, so: basePrice = finalPrice - tva + prediscount
  double get subtotalPerItem {
    return ((finalPrice - tva) + discount) + componentTotal;
  }

  // Price per item with all discounts applied (including manual discount)
  // finalPrice already has tva and prediscount applied, add components, then subtract manual discount
  double get totalPrice {
    return ((finalPrice + componentTotal) - manualDiscount) * quantity;
  }

  // Total discount per all quantities (pre-discount + manual discount)
  double get totalDiscount {
    return (discount + manualDiscount) * quantity;
  }

  // Total TVA for all quantities
  double get totalTva {
    return tva * quantity;
  }

  /// True when this line names a specific physical unit.
  bool get isSerialLine => serialId != null;

  OrderItem copyWith({
    int? id,
    int? productId,
    String? productName,
    int? variantId,
    String? variantName,
    String? imageUrl,
    double? unitPrice,
    double? quantity,
    double? savedQuantity,
    List<OrderItemComponent>? components,
    String? note,
    int? courseNo,
    bool clearCourse = false,
    int? ticketId,
    double? discount,
    double? manualDiscount,
    double? tva,
    String? state,
    DateTime? planStartAt,
    DateTime? planEndAt,
    int? planWaiterId,
    int? planResourceId,
    DateTime? kdsPrintedAt,
    double? kdsPrintedQuantity,
    double? kdsPrintQuantity,
    double? orderTicketPrintedQuantity,
    double? orderTicketPrintQuantity,
    bool? isWeighedItem,
    double? weightKg,
    double? pricePerKgDisplay,
    String? unitName,
    int? serialId,
    String? serialNumber,
    int? serverId,
  }) {
    return OrderItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      variantId: variantId ?? this.variantId,
      variantName: variantName ?? this.variantName,
      imageUrl: imageUrl ?? this.imageUrl,
      finalPrice: unitPrice ?? this.finalPrice,
      quantity: quantity ?? this.quantity,
      savedQuantity: savedQuantity ?? this.savedQuantity,
      components: components ?? this.components,
      note: note ?? this.note,
      // `clearCourse` because null is a meaningful value here: "no course"
      // has to be reachable from "plat", and `courseNo ?? this.courseNo`
      // could never express it.
      courseNo: clearCourse ? null : (courseNo ?? this.courseNo),
      ticketId: ticketId ?? this.ticketId,
      discount: discount ?? this.discount,
      manualDiscount: manualDiscount ?? this.manualDiscount,
      tva: tva ?? this.tva,
      state: state ?? this.state,
      planStartAt: planStartAt ?? this.planStartAt,
      planResourceId: planResourceId ?? this.planResourceId,
      planEndAt: planEndAt ?? this.planEndAt,
      planWaiterId: planWaiterId ?? this.planWaiterId,
      kdsPrintedAt: kdsPrintedAt ?? this.kdsPrintedAt,
      kdsPrintedQuantity: kdsPrintedQuantity ?? this.kdsPrintedQuantity,
      kdsPrintQuantity: kdsPrintQuantity ?? this.kdsPrintQuantity,
      orderTicketPrintedQuantity:
          orderTicketPrintedQuantity ?? this.orderTicketPrintedQuantity,
      orderTicketPrintQuantity:
          orderTicketPrintQuantity ?? this.orderTicketPrintQuantity,
      isWeighedItem: isWeighedItem ?? this.isWeighedItem,
      weightKg: weightKg ?? this.weightKg,
      pricePerKgDisplay: pricePerKgDisplay ?? this.pricePerKgDisplay,
      unitName: unitName ?? this.unitName,
      serialId: serialId ?? this.serialId,
      serialNumber: serialNumber ?? this.serialNumber,
      serverId: serverId ?? this.serverId,
    );
  }

  // to Json
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'productName': productName,
      'variantId': variantId,
      'variantName': variantName,
      'imageUrl': imageUrl,
      'unitPrice': finalPrice,
      'quantity': quantity,
      'components': components.map((c) => {
        'componentId': c.componentId,
        'name': c.name,
        'quantity': c.quantity,
        'price': c.price,
        'isSpecial': c.isSpecial,
        'removalCharge': c.removalCharge,
      }).toList(),
      'note': note,
      'courseNo': courseNo,
      'ticketId': ticketId,
      'discount': discount,
      'tva': tva,
      'state': state,
      'planStartAt': planStartAt?.toIso8601String(),
      'planResourceId': planResourceId,
      'planEndAt': planEndAt?.toIso8601String(),
      'planWaiterId': planWaiterId,
      'kdsPrintedAt': kdsPrintedAt?.toIso8601String(),
      'kdsPrintedQuantity': kdsPrintedQuantity,
      'isWeighedItem': isWeighedItem,
      'weightKg': weightKg,
      'pricePerKgDisplay': pricePerKgDisplay,
      'unitName': unitName,
      'serialId': serialId,
      'serialNumber': serialNumber,
    };
  }


}

// Model for component modification
class OrderItemComponent {
  final int componentId;
  final String name;
  final int quantity;
  final double price;
  final bool isSpecial;

  /// This row is money for a default the customer removed, not something to
  /// make. It is never sent to the server as an option — the server works the
  /// charge out for itself from the explicit quantity we send — and the
  /// kitchen must never see it as an ingredient.
  final bool removalCharge;

  OrderItemComponent({
    required this.componentId,
    required this.name,
    required this.quantity,
    required this.price,
    this.isSpecial = false,
    this.removalCharge = false,
  });

  OrderItemComponent copyWith({
    int? componentId,
    String? name,
    int? quantity,
    double? price,
    bool? isSpecial,
    bool? removalCharge,
  }) {
    return OrderItemComponent(
      componentId: componentId ?? this.componentId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      isSpecial: isSpecial ?? this.isSpecial,
      removalCharge: removalCharge ?? this.removalCharge,
    );
  }
}

// Model for current active order in the POS
/// How much of a line the kitchen was told to make and no longer has to.
///
/// [sent] is what has been put on a kitchen ticket ([OrderItem.
/// kdsPrintedQuantity]); [remaining] is what the line is worth now — 0 for a
/// line deleted outright. The difference is food somebody is cooking for an
/// order that no longer wants it, and is exactly what a cancellation ticket
/// has to carry.
///
/// Returns 0 when nothing was ever sent, which is the case that matters most:
/// pulling a line the kitchen never saw needs no ticket, and printing one
/// would train the pass to ignore the paper.
///
/// Pure, so the arithmetic that decides whether a printer fires can be tested
/// without one.
double cancelledQuantity({required double sent, required double remaining}) {
  final gone = sent - remaining;
  // Same epsilon as everywhere else quantities are compared: weighed goods
  // make exact equality a lie.
  return gone > 0.0001 ? gone : 0.0;
}

class CurrentOrder {
  final int? orderId;
  final String? orderCode;

  /// Per-session order number (`Orders.sessionOrderNo`). Null until saved.
  final int? sessionOrderNo;
  final List<OrderItem> items;
  final int? tableId;
  final String? tableName;
  final int? customerId;
  final String? customerName;
  final String? customerPhone;
  final int? commercialId;
  final String? commercialName;
  final int? waiterId;
  final String? waiterName;
  final String? coupon;
  final double discountPercentage; // Manual discount percentage (0-100)

  /// Order-level note for the kitchen. Printed on the kitchen ticket and shown
  /// on the KDS board, so it is an instruction, not bookkeeping.
  final String? note;

  /// Why the manual discount was given. Kept apart from [note] — it used to
  /// share it, so discounting an order wiped the kitchen instruction.
  final String? discountReason;

  final String type;
  final String? deliveryAddress; // Delivery address (when type == DELIVERY)
  final int numberOfPersons; // Number of persons for the order

  /// Tip stored on the server via `PATCH /api/orders/{id}/tip`. NOT included
  /// in [total] — the cashier collects `total + tip` from the customer.
  /// Carries through to PaymentScreen so the receipt and total-due lines
  /// show the right number.
  final double tip;

  /// Delivery charge for this order. Like [tip], it is deliberately NOT part
  /// of [total] — the products total stays a products total, and the cashier
  /// collects [amountDue].
  ///
  /// `null` and `0` are different states and must stay that way:
  ///   * `null` — no delivery fee recorded (nothing to show, nothing to send)
  ///   * `0`    — delivery is explicitly free (a real, printable fact)
  /// Use [hasDeliveryFee] rather than a `> 0` test when deciding whether the
  /// fee is a recorded value.
  final double? deliveryFee;

  /// Where the order came from — the `Orders.source` column: `POS`, `WAITER`,
  /// `KIOSK`, `EXTERNAL` (see `kAllOrderSources`). Null on a cart that has
  /// not been saved yet, and on orders written before the column was
  /// populated.
  ///
  /// Deliberately distinct from [waiterId]: a cashier can attach a waiter to
  /// an order they raised themselves, so a non-null [waiterId] does NOT mean
  /// the waiter app created it. Only this field answers that, which is what
  /// the waiter-order edit guard needs — see `isWaiterRaisedOrder` in
  /// `utils/order_permissions.dart`.
  final String? source;

  /// When this cart was read out of the database, or null for a cart that was
  /// never loaded from one (a fresh sale).
  ///
  /// The watermark that lets [OrderRepository.updateOrder] tell a line the
  /// cashier DELETED from one that somebody else ADDED while this screen sat
  /// open — both look identical by id alone (absent from [items]), and the
  /// save used to treat them the same and wipe the second kind. The waiter
  /// app writes straight into `order_products` over the LAN, so "somebody
  /// else" is an every-shift occurrence on a table the cashier has open.
  final DateTime? loadedAt;

  CurrentOrder({
    this.orderId,
    this.orderCode,
    this.sessionOrderNo,
    this.items = const [],
    this.tableId,
    this.tableName,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.commercialId,
    this.commercialName,
    this.waiterId,
    this.waiterName,
    this.coupon,
    this.discountPercentage = 0.0,
    this.note,
    this.discountReason,
    this.type = 'DINE_IN',
    this.deliveryAddress,
    this.numberOfPersons = 1,
    this.tip = 0.0,
    this.deliveryFee,
    this.source,
    this.loadedAt,
  });

  /// True when there is an order note worth surfacing to the cashier.
  bool get hasNote => note != null && note!.trim().isNotEmpty;

  /// Whether a delivery fee has been recorded at all. True for an explicit
  /// zero ("free delivery"), false only when the field was never set.
  bool get hasDeliveryFee => deliveryFee != null;

  /// The delivery fee as money, treating "not recorded" as nothing owed.
  /// Use this for arithmetic; use [hasDeliveryFee] for display decisions.
  double get deliveryFeeAmount => deliveryFee ?? 0.0;

  // Subtotal: sum of all base prices (no tax, no discounts)
  double get subtotal {
    return items.fold(0.0, (sum, item) => sum + (item.subtotalPerItem * item.quantity));
  }

  // Total tax for all items
  double get tax {
    return items.fold(0.0, (sum, item) => sum + item.totalTva);
  }

  // Total before order-level discount (includes item prices with components, tva, pre-discounts, and manual discounts)
  double get totalBeforeDiscount {
    return items.fold(0.0, (sum, item) => sum + item.totalPrice);
  }

  // Order-level discount amount calculated from percentage
  double get discountAmount {
    return totalBeforeDiscount * (discountPercentage / 100);
  }

  // Final total with order-level discount applied
  double get total {
    return totalBeforeDiscount - discountAmount;
  }

  /// What the customer actually hands over: the products [total] plus the
  /// non-product extras. Kept separate from [total] so nothing that reports
  /// on sales, discounts or Z-totals ever picks the fee up by accident —
  /// only the collection points (payment pad, receipt footer) use this.
  double get amountDue => total + deliveryFeeAmount;

  // Get only unpaid items
  List<OrderItem> get unpaidItems {
    return items.where((item) => item.ticketId == null).toList();
  }

  // Get only paid items
  List<OrderItem> get paidItems {
    return items.where((item) => item.ticketId != null).toList();
  }

  // Check if order has any paid items
  bool get hasPaidItems {
    return items.any((item) => item.ticketId != null);
  }

  double get totalDiscount {
    return items.fold(0.0, (sum, item) => sum + item.totalDiscount) + discountAmount;
  }


  CurrentOrder copyWith({
    int? orderId,
    String? orderCode,
    List<OrderItem>? items,
    int? tableId,
    String? tableName,
    int? customerId,
    String? customerName,
    String? customerPhone,
    int? commercialId,
    String? commercialName,
    int? waiterId,
    String? waiterName,
    String? coupon,
    double? discountPercentage,
    String? note,
    String? discountReason,
    String? type,
    String? deliveryAddress,
    int? numberOfPersons,
    double? tip,
    double? deliveryFee,
    String? source,
    DateTime? loadedAt,
    int? sessionOrderNo,
    /// `copyWith` can't express "set this back to null" through a nullable
    /// parameter — `deliveryFee: null` is indistinguishable from "not passed".
    /// This flag is how the cashier's "remove the fee" action round-trips, and
    /// it wins over [deliveryFee] if both are given.
    bool clearDeliveryFee = false,
  }) {
    return CurrentOrder(
      orderId: orderId ?? this.orderId,
      orderCode: orderCode ?? this.orderCode,
      sessionOrderNo: sessionOrderNo ?? this.sessionOrderNo,
      items: items ?? this.items,
      tableId: tableId ?? this.tableId,
      tableName: tableName ?? this.tableName,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      commercialId: commercialId ?? this.commercialId,
      commercialName: commercialName ?? this.commercialName,
      waiterId: waiterId ?? this.waiterId,
      waiterName: waiterName ?? this.waiterName,
      coupon: coupon ?? this.coupon,
      discountPercentage: discountPercentage ?? this.discountPercentage,
      note: note ?? this.note,
      discountReason: discountReason ?? this.discountReason,
      type: type ?? this.type,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      numberOfPersons: numberOfPersons ?? this.numberOfPersons,
      tip: tip ?? this.tip,
      deliveryFee:
          clearDeliveryFee ? null : (deliveryFee ?? this.deliveryFee),
      source: source ?? this.source,
      loadedAt: loadedAt ?? this.loadedAt,
    );
  }

  bool isSaved() {
    return orderId != null || orderCode != null;
  }

  /// Whether walking away from this cart would lose work.
  ///
  /// An order already in the database is NOT unsaved just because it has lines
  /// on it — leaving it for another table leaves it exactly where it is, which
  /// is why picking a second table used to nag about discarding an order that
  /// was never at risk. What would actually be lost is a line that was never
  /// persisted, or a quantity moved since the cart was loaded. A cart with no
  /// order behind it is unsaved the moment anything is on it.
  bool get hasUnsavedChanges {
    if (orderId == null) return items.isNotEmpty;
    return items.any((i) =>
        i.id == null ||
        (i.savedQuantity != null &&
            (i.quantity - i.savedQuantity!).abs() > 0.0001));
  }


}

// Model for table with active order info
class TableWithOrder {
  final dynamic table; // AreaTable from database
  final int orderCount;
  final double total;
  final DateTime lastUpdated;

  TableWithOrder({
    required this.table,
    required this.orderCount,
    required this.total,
    required this.lastUpdated,
  });
}

// Model for order with summary details
class OrderWithDetails {
  final dynamic order; // Order from database
  final String? tableName;
  final int itemCount;
  final double total;

  OrderWithDetails({
    required this.order,
    this.tableName,
    required this.itemCount,
    required this.total,
  });
}

// Model for component details in order item
class ComponentDetails {
  final String name;
  final int quantity;
  final double price;
  final bool isSpecial;

  ComponentDetails({
    required this.name,
    required this.quantity,
    required this.price,
    this.isSpecial = false,
  });
}

// Model for order item with all details for management screen
class OrderItemDetails {
  final String productName;
  final int? variantId;
  final String? variantName;
  final double quantity;
  final double totalPrice;
  final bool isPaid;
  final String? ticketNum;
  final List<ComponentDetails> components;

  OrderItemDetails({
    required this.productName,
    this.variantId,
    this.variantName,
    required this.quantity,
    required this.totalPrice,
    required this.isPaid,
    this.ticketNum,
    this.components = const [],
  });

  /// Returns the display name - variant name if available, otherwise product name
  String get displayName => variantName ?? productName;
}

// Model for order with full details including all calculations
class OrderFullDetails {
  final Order order; // Order from database
  final String? userName;
  final String? tableName;
  final String? customerName; // Customer name if exists
  final String? customerPhone; // Customer phone if exists
  final int? customerId; // Customer ID if exists
  final int productCount;
  final double subtotal;
  final double itemDiscount; // Total item-level discounts
  final double discountPercentage; // Manual discount percentage
  final double manualDiscountAmount; // Calculated from percentage
  final double totalDiscount; // itemDiscount + manualDiscountAmount
  final double totalTva;
  final double total;
  final double totalPaid;

  /// Delivery charge on this order, or 0.
  ///
  /// Kept OUT of [total] deliberately: `totalPaid` sums ticket amounts, which
  /// are products-only, so folding the fee into the total would make every
  /// settled delivery read as still owing. Use [grandTotal] to show a human
  /// what the customer actually pays, and [total] to decide whether the order
  /// is paid.
  final double deliveryFee;

  final List<OrderItemDetails> items;
  final bool isZLocked; // True when linked session is ended (Z-report closed)

  /// What the customer hands over: products plus delivery.
  double get grandTotal => total + deliveryFee;

  OrderFullDetails({
    required this.order,
    this.userName,
    this.tableName,
    this.customerName,
    this.customerPhone,
    this.customerId,
    required this.productCount,
    required this.subtotal,
    this.itemDiscount = 0.0,
    this.discountPercentage = 0.0,
    this.manualDiscountAmount = 0.0,
    required this.totalDiscount,
    required this.totalTva,
    required this.total,
    required this.totalPaid,
    this.deliveryFee = 0.0,
    this.items = const [],
    this.isZLocked = false,
  });
}

// Model for paginated order results
class PaginatedOrders {
  final List<OrderFullDetails> orders;
  final int totalCount;
  final int page;
  final int pageSize;
  final int totalPages;

  PaginatedOrders({
    required this.orders,
    required this.totalCount,
    required this.page,
    required this.pageSize,
    required this.totalPages,
  });
}


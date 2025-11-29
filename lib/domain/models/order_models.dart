// Model for current order item in cart
class OrderItem {
  final int? id;
  final int productId;
  final String productName;
  final String? imageUrl;
  final double unitPrice;
  final int quantity;
  final List<OrderItemComponent> components;
  final String? note;
  final int? ticketId; // null = not paid, number = ticket ID (paid)
  final double discount; // discount amount per item
  final double tva; // TVA amount per item

  OrderItem({
    this.id,
    required this.productId,
    required this.productName,
    this.imageUrl,
    required this.unitPrice,
    this.quantity = 1,
    this.components = const [],
    this.note,
    this.ticketId,
    this.discount = 0.0,
    this.tva = 0.0,
  });

  double get componentTotal {
    return components.fold(0.0, (sum, comp) => sum + (comp.price * comp.quantity));
  }

  double get subtotalPerItem {
    return unitPrice + componentTotal;
  }

  double get totalPrice {
    return (subtotalPerItem - discount + tva) * quantity;
  }

  double get totalDiscount {
    return discount * quantity;
  }

  double get totalTva {
    return tva * quantity;
  }

  OrderItem copyWith({
    int? id,
    int? productId,
    String? productName,
    String? imageUrl,
    double? unitPrice,
    int? quantity,
    List<OrderItemComponent>? components,
    String? note,
    int? ticketId,
    double? discount,
    double? tva,
  }) {
    return OrderItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      unitPrice: unitPrice ?? this.unitPrice,
      quantity: quantity ?? this.quantity,
      components: components ?? this.components,
      note: note ?? this.note,
      ticketId: ticketId ?? this.ticketId,
      discount: discount ?? this.discount,
      tva: tva ?? this.tva,
    );
  }
}

// Model for component modification
class OrderItemComponent {
  final int componentId;
  final String name;
  final int quantity;
  final double price;
  final bool isSpecial;

  OrderItemComponent({
    required this.componentId,
    required this.name,
    required this.quantity,
    required this.price,
    this.isSpecial = false,
  });

  OrderItemComponent copyWith({
    int? componentId,
    String? name,
    int? quantity,
    double? price,
    bool? isSpecial,
  }) {
    return OrderItemComponent(
      componentId: componentId ?? this.componentId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      price: price ?? this.price,
      isSpecial: isSpecial ?? this.isSpecial,
    );
  }
}

// Model for current active order in the POS
class CurrentOrder {
  final int? orderId;
  final String? orderCode;
  final List<OrderItem> items;
  final int? tableId;
  final String? tableName;
  final int? customerId;
  final String? customerName;
  final int? commercialId;
  final String? commercialName;
  final String? coupon;
  final double? couponDiscountAmount;
  final String? note;
  final String type;

  CurrentOrder({
    this.orderId,
    this.orderCode,
    this.items = const [],
    this.tableId,
    this.tableName,
    this.customerId,
    this.customerName,
    this.commercialId,
    this.commercialName,
    this.coupon,
    this.couponDiscountAmount,
    this.note,
    this.type = 'DINE_IN',
  });

  double get subtotal {
    return items.fold(0.0,
            (sum, item) => sum + item.totalPrice);
  }

  double get tax {

    print("Calculating tax for order with ${items.length} items.");

    final tax = items.fold(0.0,
            (sum, item) {
            print(item.totalTva);
            print(item.tva);
              return sum + item.totalTva;
            });

    return tax;
  }

  double get total {
    return subtotal + tax;
  }

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

  CurrentOrder copyWith({
    int? orderId,
    List<OrderItem>? items,
    int? tableId,
    String? tableName,
    int? customerId,
    String? customerName,
    int? commercialId,
    String? commercialName,
    String? coupon,
    String? note,
    String? type,
  }) {
    return CurrentOrder(
      orderId: orderId ?? this.orderId,
      items: items ?? this.items,
      tableId: tableId ?? this.tableId,
      tableName: tableName ?? this.tableName,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      commercialId: commercialId ?? this.commercialId,
      commercialName: commercialName ?? this.commercialName,
      coupon: coupon ?? this.coupon,
      note: note ?? this.note,
      type: type ?? this.type,
    );
  }

  bool isSaved() {
    return orderId != null || orderCode != null;
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




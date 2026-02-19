// Model for current order item in cart

import '../../data/database/app_database.dart';

class OrderItem {
  final int? id;
  final int productId;
  final String productName;
  final String? imageUrl;
  final double finalPrice; // final price per unit without components
  final int quantity;
  final List<OrderItemComponent> components;
  final String? note;
  final int? ticketId; // null = not paid, number = ticket ID (paid)
  final double discount; // discount amount per item
  final double manualDiscount; // manual discount amount per item
  final double tva; // TVA amount per item
  final String state; // PENDING, ONHOLD, PREPARING, READY, SERVED, etc.

  OrderItem({
    this.id,
    required this.productId,
    required this.productName,
    this.imageUrl,
    required this.finalPrice, // final price per unit without components
    this.quantity = 1,
    this.components = const [],
    this.note,
    this.ticketId,
    this.discount = 0.0,
    this.manualDiscount = 0.0,
    this.tva = 0.0,
    this.state = 'PENDING',
  });

  double get componentTotal {
    return components.fold(0.0, (sum, comp) => sum + (comp.price * comp.quantity));
  }

  // Base price per item without tax or any discount (but with components)
  // finalPrice = basePrice + tva - prediscount, so: basePrice = finalPrice - tva + prediscount
  double get subtotalPerItem {
    print('finalPrice: $finalPrice, tva: $tva, discount: $discount, componentTotal: $componentTotal');
    return ((finalPrice - tva) + discount) + componentTotal;
  }

  // Price per item with all discounts applied (including manual discount)
  // finalPrice already has tva and prediscount applied, add components, then subtract manual discount
  double get totalPrice {
    print('finalPrice: $finalPrice, componentTotal: $componentTotal, manualDiscount: $manualDiscount, quantity: $quantity');
    return ((finalPrice + componentTotal) - manualDiscount) * quantity;
  }

  // Total discount per all quantities (pre-discount + manual discount)
  double get totalDiscount {
    print('discount: $discount, manualDiscount: $manualDiscount, quantity: $quantity');
    return (discount + manualDiscount) * quantity;
  }

  // Total TVA for all quantities
  double get totalTva {
    print('tva: $tva, quantity: $quantity');
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
    double? manualDiscount,
    double? tva,
    String? state,
  }) {
    return OrderItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      imageUrl: imageUrl ?? this.imageUrl,
      finalPrice: unitPrice ?? this.finalPrice,
      quantity: quantity ?? this.quantity,
      components: components ?? this.components,
      note: note ?? this.note,
      ticketId: ticketId ?? this.ticketId,
      discount: discount ?? this.discount,
      manualDiscount: manualDiscount ?? this.manualDiscount,
      tva: tva ?? this.tva,
      state: state ?? this.state,
    );
  }

  // to Json
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'productName': productName,
      'imageUrl': imageUrl,
      'unitPrice': finalPrice,
      'quantity': quantity,
      'components': components.map((c) => {
        'componentId': c.componentId,
        'name': c.name,
        'quantity': c.quantity,
        'price': c.price,
        'isSpecial': c.isSpecial,
      }).toList(),
      'note': note,
      'ticketId': ticketId,
      'discount': discount,
      'tva': tva,
      'state': state,
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
  final double discountPercentage; // Manual discount percentage (0-100)
  final String? note;
  final String type;
  final int numberOfPersons; // Number of persons for the order


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
    this.discountPercentage = 0.0,
    this.note,
    this.type = 'DINE_IN',
    this.numberOfPersons = 1,
  });

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
    List<OrderItem>? items,
    int? tableId,
    String? tableName,
    int? customerId,
    String? customerName,
    int? commercialId,
    String? commercialName,
    String? coupon,
    double? discountPercentage,
    String? note,
    String? type,
    int? numberOfPersons,
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
      discountPercentage: discountPercentage ?? this.discountPercentage,
      note: note ?? this.note,
      type: type ?? this.type,
      numberOfPersons: numberOfPersons ?? this.numberOfPersons,
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
  final int quantity;
  final double totalPrice;
  final bool isPaid;
  final String? ticketNum;
  final List<ComponentDetails> components;

  OrderItemDetails({
    required this.productName,
    required this.quantity,
    required this.totalPrice,
    required this.isPaid,
    this.ticketNum,
    this.components = const [],
  });
}

// Model for order with full details including all calculations
class OrderFullDetails {
  final Order order; // Order from database
  final String? userName;
  final String? tableName;
  final String? customerName; // Customer name if exists
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
  final List<OrderItemDetails> items;

  OrderFullDetails({
    required this.order,
    this.userName,
    this.tableName,
    this.customerName,
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
    this.items = const [],
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


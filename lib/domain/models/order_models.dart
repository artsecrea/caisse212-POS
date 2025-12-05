// Model for current order item in cart
import 'package:posecrea/data/database/app_database.dart';

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
  });

  double get componentTotal {
    return components.fold(0.0, (sum, comp) => sum + (comp.price * comp.quantity));
  }

  double get subtotalPerItem {
    return (finalPrice - manualDiscount )+ componentTotal;
  }

  double get totalPrice {
    return subtotalPerItem  * quantity;
  }

  double get totalDiscount {
    return (discount + manualDiscount) * quantity;
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
    double? manualDiscount,
    double? tva,
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
    return total - tax;
  }

  double get tax {
    final tax = items.fold(0.0,
            (sum, item) {
              return sum + item.tva * item.quantity;
            });

    return tax;
  }

  double get total {
    return      items.fold(0.0,
            (sum, item) => sum + item.totalPrice);
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

// Model for component details in order item
class ComponentDetails {
  final String name;
  final int quantity;

  ComponentDetails({
    required this.name,
    required this.quantity,
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
  final dynamic order; // Order from database
  final String? userName;
  final String? tableName;
  final int productCount;
  final double subtotal;
  final double totalDiscount;
  final double totalTva;
  final double total;
  final double totalPaid;
  final List<OrderItemDetails> items;

  OrderFullDetails({
    required this.order,
    this.userName,
    this.tableName,
    required this.productCount,
    required this.subtotal,
    required this.totalDiscount,
    required this.totalTva,
    required this.total,
    required this.totalPaid,
    this.items = const [],
  });
}

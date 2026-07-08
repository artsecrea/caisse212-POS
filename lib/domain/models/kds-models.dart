
enum KdsOrderType {
  dineIn,
  takeAway,
  delivery;

  String toDisplayString() {
    switch (this) {
      case KdsOrderType.dineIn:
        return 'Dine-in';
      case KdsOrderType.takeAway:
        return 'Takeaway';
      case KdsOrderType.delivery:
        return 'Delivery';
    }
  }
}


enum KdsOrderStatus {
  pending,
  preparing,
  complete,
  canceled;

  String toDisplayString() {
    switch (this) {
      case KdsOrderStatus.pending:
        return 'PENDING';
      case KdsOrderStatus.preparing:
        return 'PREPARING';
      case KdsOrderStatus.complete:
        return 'COMPLETE';
      case KdsOrderStatus.canceled:
        return 'CANCELED';
    }
  }
}


class KdsOrder {
  final String id;
  final String orderCode;
  final String? tableName;
  final KdsOrderType orderType;
  final int? numberOfPersons;
  final String? clientName;
  final List<KdsProduct> products;
  final KdsOrderStatus status;
  final DateTime createdAt;
  final DateTime? updatedAt;

  KdsOrder({
    required this.id,
    required this.orderCode,
    this.tableName,
    required this.orderType,
    this.numberOfPersons,
    this.clientName,
    required this.products,
    required this.status,
    required this.createdAt,
    this.updatedAt,
  });

  KdsOrder copyWith({
    String? id,
    String? orderCode,
    String? tableName,
    KdsOrderType? orderType,
    int? numberOfPersons,
    String? clientName,
    List<KdsProduct>? products,
    KdsOrderStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KdsOrder(
      id: id ?? this.id,
      orderCode: orderCode ?? this.orderCode,
      tableName: tableName ?? this.tableName,
      orderType: orderType ?? this.orderType,
      numberOfPersons: numberOfPersons ?? this.numberOfPersons,
      clientName: clientName ?? this.clientName,
      products: products ?? this.products,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderCode': orderCode,
      'tableName': tableName,
      'orderType': orderType.name,
      'numberOfPersons': numberOfPersons,
      'clientName': clientName,
      'products': products.map((p) => p.toJson()).toList(),
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory KdsOrder.fromJson(Map<String, dynamic> json) {
    return KdsOrder(
      id: json['id'] as String,
      orderCode: json['orderCode'] as String,
      tableName: json['tableName'] as String?,
      orderType: KdsOrderType.values.firstWhere(
            (e) => e.name == json['orderType'],
        orElse: () => KdsOrderType.dineIn,
      ),
      numberOfPersons: json['numberOfPersons'] as int?,
      clientName: json['clientName'] as String?,
      products: (json['products'] as List<dynamic>)
          .map((p) => KdsProduct.fromJson(p as Map<String, dynamic>))
          .toList(),
      status: KdsOrderStatus.values.firstWhere(
            (e) => e.name == json['status'],
        orElse: () => KdsOrderStatus.pending,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }
}


class KdsProduct {
  final int id;
  final String name;
  final double quantity;
  final List<String> options;

  KdsProduct({
    required this.id,
    required this.name,
    required this.quantity,
    this.options = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'quantity': quantity,
      'options': options.toList(),
    };
  }

  factory KdsProduct.fromJson(Map<String, dynamic> json) {
    return KdsProduct(
      id : json['id'] as int,
      name: json['name'] as String,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      options: (json['options'] as List<String>?) ??
          [],
    );
  }
}


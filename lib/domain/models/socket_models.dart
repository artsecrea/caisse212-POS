// Models for socket communication

import '../../core/enums.dart';
import '../../data/database/app_database.dart';
import 'kds-models.dart';
import 'order_course.dart';
import 'order_models.dart';



class SocketOrderModel {
  final int id;
  final String code;
  final String status;
  final String type;
  final int priority;
  final int persons;
  final DateTime date;
  final int? tableId;
  final String? tableName;
  final int? clientId;
  final String? clientName;
  final List<SocketOrderProductModel> products;
  final String? note;
  final String? cancellationReason;

  /// Take-away / delivery reference typed by the cashier.
  final String? reference;
  /// Per-session order number; only set when the KDS setting is on.
  final int? orderNumber;

  /// Every course-tagged line of the order, whatever its station — so a
  /// dessert screen can tell when the entrée cooked elsewhere is done. Empty
  /// when courses are off or nothing is tagged (and then left off the wire).
  final List<KdsCourseLine> courseLines;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  SocketOrderModel({
    required this.id,
    required this.code,
    required this.status,
    required this.type,
    required this.priority,
    this.persons = 1,
    required this.date,
    this.tableId,
    this.tableName,
    this.clientId,
    this.clientName,
    required this.products,
    this.note,
    this.cancellationReason,
    this.reference,
    this.orderNumber,
    this.courseLines = const [],
    this.createdAt,
    this.updatedAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      if (orderNumber != null) 'orderNumber': orderNumber,
      'status': status,
      'type': type,
      'priority': priority,
      'persons': persons,
      'date': date.toIso8601String(),
      'tableId': tableId,
      'tableName': tableName,
      'clientId': clientId,
      'clientName': clientName,
      'products': products.map((p) => p.toJson()).toList(),
      'note': note,
      'cancellationReason': cancellationReason,
      if ((reference ?? '').isNotEmpty) 'reference': reference,
      if (courseLines.isNotEmpty)
        'courseLines': courseLines.map((l) => l.toJson()).toList(),
    };
  }

  factory SocketOrderModel.fromJson(Map<String, dynamic> json) {
    // Normalize type: "takeAway" → "TAKE_AWAY", "dineIn" → "DINE_IN", etc.
    String normalizeType(String raw) {
      switch (raw.toLowerCase().replaceAll('_', '').replaceAll(' ', '')) {
        case 'takeaway': return 'TAKE_AWAY';
        case 'dinein':   return 'DINE_IN';
        case 'delivery': return 'DELIVERY';
        default:         return raw.toUpperCase();
      }
    }

    // Normalize status: always uppercase
    String normalizeStatus(String raw) => raw.toUpperCase();

    return SocketOrderModel(
      id: json['id'] as int? ?? 0,
      code: json['code'] as String,
      status: normalizeStatus(json['status'] as String? ?? 'ONHOLD'),
      type: normalizeType(json['type'] as String? ?? 'DINE_IN'),
      priority: json['priority'] as int? ?? 0,
      persons: json['persons'] as int? ?? 1,
      date: json['date'] != null ? DateTime.parse(json['date'] as String) : DateTime.now(),
      tableId: json['tableId'] as int?,
      tableName: json['tableName'] as String?,
      clientId: json['clientId'] as int?,
      clientName: json['clientName'] as String?,
      products: (json['products'] as List? ?? [])
          .map((p) => SocketOrderProductModel.fromJson(p as Map<String, dynamic>))
          .toList(),
      note: json['note'] as String?,
      cancellationReason: json['cancellationReason'] as String?,
    );
  }

}

class SocketOrderProductModel {
  final int id;
  final int productId;
  final int? variantId;
  final String productName;
  final String? imageUrl;
  final double quantity;
  final double unitaryPrice;
  final String state;
  final int? stationId;
  final String? stationName;
  final List<SocketOrderProductComponentModel> components;
  final String? note;
  final double? tvaAmount;
  final double? discountAmount;

  /// 1 entrée / 2 plat / 3 dessert (see `OrderCourse`). Omitted from the JSON
  /// when null, so a KDS reads "no course" rather than a placeholder.
  final int? courseNo;

  /// Set on a linked line (an option shown on its own product's station): the
  /// real order line it came from. Such a line has a negative [id] and is
  /// read-only on the KDS - its state is the parent's.
  final int? parentLineId;

  /// The cashier has taken money for the line. Separate from [state], which
  /// stays the kitchen stage: a line paid up front is still food to cook.
  final bool paid;

  /// When the line reached the kitchen — the KDS "waiting" clock.
  final DateTime? kitchenAt;

  /// When the kitchen started it — the KDS "cooking" clock.
  final DateTime? preparingAt;

  /// When the kitchen finished it (ready, else served); null while it is
  /// still to make. Starts the next course's clock on the KDS.
  final DateTime? doneAt;

  /// The product's preparation time from the back-office, in minutes. Null =
  /// not configured.
  final int? prepMinutes;

  SocketOrderProductModel({
    required this.id,
    required this.productId,
    this.variantId,
    required this.productName,
    this.imageUrl,
    required this.quantity,
    required this.unitaryPrice,
    required this.state,
    this.stationId,
    this.stationName,
    required this.components,
    this.note,
    this.tvaAmount,
    this.discountAmount,
    this.courseNo,
    this.parentLineId,
    this.paid = false,
    this.kitchenAt,
    this.preparingAt,
    this.doneAt,
    this.prepMinutes,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productId': productId,
      'variantId': variantId,
      'productName': productName,
      'imageUrl': imageUrl,
      'quantity': quantity,
      "tvaAmount": tvaAmount,
      "discountAmount": discountAmount,
      'unitaryPrice': unitaryPrice,
      'state': state,
      'stationId': stationId,
      'stationName': stationName,
      'components': components.map((c) => c.toJson()).toList(),
      'note': note,
      if (courseNo != null) 'courseNo': courseNo,
      if (parentLineId != null) 'parentLineId': parentLineId,
      'paid': paid,
      // Local ISO, like the order's `date`.
      if (kitchenAt != null) 'kitchenAt': kitchenAt!.toIso8601String(),
      if (preparingAt != null) 'preparingAt': preparingAt!.toIso8601String(),
      if (doneAt != null) 'doneAt': doneAt!.toIso8601String(),
      if (prepMinutes != null) 'prepMinutes': prepMinutes,
    };
  }

  factory SocketOrderProductModel.fromJson(Map<String, dynamic> json) {
    return SocketOrderProductModel(
      id: json['id'] as int? ?? 0,
      productId: json['productId'] as int,
      variantId: json['variantId'] as int?,
      productName: json['productName'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1.0,
      tvaAmount: (json['tvaAmount'] as num?)?.toDouble(),
      discountAmount: (json['discountAmount'] as num?)?.toDouble(),
      unitaryPrice: (json['unitaryPrice'] as num? ?? json['unitPrice'] as num? ?? 0).toDouble(),
      state: (json['state'] as String? ?? 'PENDING').toUpperCase(),
      stationId: json['stationId'] as int?,
      stationName: json['stationName'] as String?,
      components: (json['components'] as List? ?? [])
          .map((c) => SocketOrderProductComponentModel
          .fromJson(c as Map<String, dynamic>))
          .toList(),
      note: json['note'] as String?,
      courseNo: normalizeCourseNo(json['courseNo']),
      parentLineId: (json['parentLineId'] as num?)?.toInt(),
      paid: json['paid'] as bool? ?? false,
      kitchenAt: DateTime.tryParse(json['kitchenAt'] as String? ?? ''),
      preparingAt: DateTime.tryParse(json['preparingAt'] as String? ?? ''),
      doneAt: DateTime.tryParse(json['doneAt'] as String? ?? ''),
      prepMinutes: (json['prepMinutes'] as num?)?.toInt(),
    );
  }
}

/// One course-tagged line of an order as the KDS needs it to sequence
/// courses: its course, kitchen state, and when it reached / left the kitchen.
class KdsCourseLine {
  final int id;
  final int courseNo;
  final String state;
  final DateTime kitchenAt;
  final DateTime? doneAt;

  const KdsCourseLine({
    required this.id,
    required this.courseNo,
    required this.state,
    required this.kitchenAt,
    this.doneAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'courseNo': courseNo,
        'state': state,
        'kitchenAt': kitchenAt.toIso8601String(),
        if (doneAt != null) 'doneAt': doneAt!.toIso8601String(),
      };
}

class SocketOrderProductComponentModel {
  final int componentId;
  final String componentName;
  final int quantity;
  final bool isSpecial;
  final double? extraPrice;

  SocketOrderProductComponentModel({
    required this.componentId,
    required this.componentName,
    required this.quantity,
    required this.isSpecial,
    this.extraPrice,
  });

  Map<String, dynamic> toJson() {
    return {
      'componentId': componentId,
      'componentName': componentName,
      'quantity': quantity,
      'isSpecial': isSpecial,
      'extraPrice': extraPrice,
    };
  }

  factory SocketOrderProductComponentModel.fromJson(Map<String, dynamic> json) {
    return SocketOrderProductComponentModel(
      componentId: json['componentId'] as int,
      componentName: json['componentName'] as String,
      quantity: json['quantity'] as int,
      isSpecial: json['isSpecial'] as bool,
      extraPrice: (json['extraPrice'] as num?)?.toDouble(),
    );
  }

  @override
  String toString() {
    return '$componentName x$quantity${isSpecial ? ' (Special)' : ''}';
  }

}

class SocketDeviceModel {
  final int id;
  final String name;
  final String? description;
  final String? ip;
  final int? port;
  final String? location;
  final bool isActive;
  final String type; // 'KDS' or 'KIOSK'

  SocketDeviceModel({
    required this.id,
    required this.name,
    this.description,
    this.ip,
    this.port,
    this.location,
    required this.isActive,
    required this.type,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'ip': ip,
      'port': port,
      'location': location,
      'isActive': isActive,
      'type': type,
    };
  }

  factory SocketDeviceModel.fromJson(Map<String, dynamic> json) {
    return SocketDeviceModel(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      ip: json['ip'] as String?,
      port: json['port'] as int?,
      location: json['location'] as String?,
      isActive: json['isActive'] as bool,
      type: json['type'] as String,
    );
  }
}

class SocketStationModel {
  final int id;
  final String name;
  final String? description;
  final int? kdsId;
  final String? kdsName;

  SocketStationModel({
    required this.id,
    required this.name,
    this.description,
    this.kdsId,
    this.kdsName,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'kdsId': kdsId,
      'kdsName': kdsName,
    };
  }

  factory SocketStationModel.fromJson(Map<String, dynamic> json) {
    return SocketStationModel(
      id: json['id'] as int,
      name: json['name'] as String,
      description: json['description'] as String?,
      kdsId: json['kdsId'] as int?,
      kdsName: json['kdsName'] as String?,
    );
  }
}

extension SocketOrderToKds on SocketOrderModel {
  KdsOrder toKdsOrder() {
    return KdsOrder(
      id: id.toString(),
      orderCode: code,
      tableName: tableName,
      orderType: _mapOrderType(type),
      numberOfPersons: persons,
      clientName: clientName,
      products: products.map((item) => item.toKdsProduct()).toList(),
      status: _mapOrderStatus(status),
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  KdsOrderType _mapOrderType(String? type) {
    if (type == null) return KdsOrderType.dineIn;

    switch (type.toLowerCase()) {
      case 'dinein':
      case 'dine-in':
      case 'dine_in':
        return KdsOrderType.dineIn;
      case 'takeaway':
      case 'take-away':
      case 'take_away':
        return KdsOrderType.takeAway;
      case 'delivery':
        return KdsOrderType.delivery;
      default:
        return KdsOrderType.dineIn;
    }
  }

  KdsOrderStatus _mapOrderStatus(String? status) {
    if (status == null) return KdsOrderStatus.pending;

    switch (status.toLowerCase()) {
      case 'pending':
      case 'new':
        return KdsOrderStatus.pending;
      case 'preparing':
      case 'in_progress':
      case 'cooking':
        return KdsOrderStatus.preparing;
      case 'complete':
      case 'completed':
      case 'ready':
        return KdsOrderStatus.complete;
      case 'canceled':
      case 'cancelled':
        return KdsOrderStatus.canceled;
      default:
        return KdsOrderStatus.pending;
    }
  }
}

extension SocketOrderItemToKdsProduct on SocketOrderProductModel {
  KdsProduct toKdsProduct() {
    return KdsProduct(
      id :id,
      name: productName,
      quantity: quantity,
      options: components.map((item){
        return item.toString();
      }).toList(),
    );
  }
}

// extension functions from order to socket models
//#region from kds models to socket ones if needed in the future

extension SocketModelsToCurrentOrder on SocketOrderModel {
  CurrentOrder toCurrentOrder() {
    return CurrentOrder(
      orderCode: code,
      tableId: tableId,
      tableName: tableName,
      type: type,
      customerId: clientId,
      items: products.map((item) => item.toCurrentOrderItem()).toList(),
      note: note,
    );
  }


}

extension SocketOrderProductToCurrentOrderItem on SocketOrderProductModel {
  OrderItem toCurrentOrderItem() {
    return OrderItem(
      productId: productId,
      productName: productName,
      variantId: variantId,
      imageUrl: imageUrl,
      finalPrice: unitaryPrice,
      quantity: quantity.toDouble(),
      note: note,
      tva: tvaAmount ?? 0,
      discount: discountAmount ?? 0,
      components: components.map((comp) {
        return OrderItemComponent(
          componentId: comp.componentId,
          name: comp.componentName,
          price: comp.extraPrice ?? 0.0,
          quantity: comp.quantity,
          isSpecial: comp.isSpecial,
        );
      }).toList(),
    );
  }
}

//#endregion
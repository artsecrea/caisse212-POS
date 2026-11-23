import 'order_models.dart';

/// Lossless JSON form of an in-memory cart, used to carry the cart and the
/// held orders across the restart an update forces. Unlike
/// [OrderItem.toJson] (the API payload) it keeps every field the cart needs
/// to come back exactly as it was: saved quantities, print counters, server
/// ids and the load watermark. The transient per-ticket overrides
/// (`kdsPrintQuantity`, `orderTicketPrintQuantity`) are deliberately dropped.
Map<String, dynamic> orderToSnapshot(CurrentOrder o) => {
      'orderId': o.orderId,
      'orderCode': o.orderCode,
      'sessionOrderNo': o.sessionOrderNo,
      'items': o.items.map(_itemToSnapshot).toList(),
      'tableId': o.tableId,
      'tableName': o.tableName,
      'customerId': o.customerId,
      'customerName': o.customerName,
      'customerPhone': o.customerPhone,
      'commercialId': o.commercialId,
      'commercialName': o.commercialName,
      'waiterId': o.waiterId,
      'waiterName': o.waiterName,
      'coupon': o.coupon,
      'discountPercentage': o.discountPercentage,
      'note': o.note,
      'discountReason': o.discountReason,
      'type': o.type,
      'deliveryAddress': o.deliveryAddress,
      'reference': o.reference,
      'reservationCode': o.reservationCode,
      'numberOfPersons': o.numberOfPersons,
      'tip': o.tip,
      'deliveryFee': o.deliveryFee,
      'source': o.source,
      'loadedAt': o.loadedAt?.toIso8601String(),
      'loadedLineIds': o.loadedLineIds?.toList(),
      'tagIds': o.tagIds,
    };

CurrentOrder orderFromSnapshot(Map<String, dynamic> j) => CurrentOrder(
      orderId: _int(j['orderId']),
      orderCode: j['orderCode'] as String?,
      sessionOrderNo: _int(j['sessionOrderNo']),
      items: ((j['items'] as List?) ?? const [])
          .map((e) => _itemFromSnapshot(Map<String, dynamic>.from(e as Map)))
          .toList(),
      tableId: _int(j['tableId']),
      tableName: j['tableName'] as String?,
      customerId: _int(j['customerId']),
      customerName: j['customerName'] as String?,
      customerPhone: j['customerPhone'] as String?,
      commercialId: _int(j['commercialId']),
      commercialName: j['commercialName'] as String?,
      waiterId: _int(j['waiterId']),
      waiterName: j['waiterName'] as String?,
      coupon: j['coupon'] as String?,
      discountPercentage: _dbl(j['discountPercentage']) ?? 0.0,
      note: j['note'] as String?,
      discountReason: j['discountReason'] as String?,
      type: j['type'] as String? ?? 'DINE_IN',
      deliveryAddress: j['deliveryAddress'] as String?,
      reference: j['reference'] as String?,
      reservationCode: j['reservationCode'] as String?,
      numberOfPersons: _int(j['numberOfPersons']) ?? 1,
      tip: _dbl(j['tip']) ?? 0.0,
      deliveryFee: _dbl(j['deliveryFee']),
      source: j['source'] as String?,
      loadedAt: _date(j['loadedAt']),
      loadedLineIds: (j['loadedLineIds'] as List?)
          ?.map((e) => (e as num).toInt())
          .toSet(),
      tagIds: ((j['tagIds'] as List?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
    );

Map<String, dynamic> _itemToSnapshot(OrderItem i) => {
      'id': i.id,
      'productId': i.productId,
      'productName': i.productName,
      'variantId': i.variantId,
      'variantName': i.variantName,
      'imageUrl': i.imageUrl,
      'finalPrice': i.finalPrice,
      'quantity': i.quantity,
      'savedQuantity': i.savedQuantity,
      'components': i.components
          .map((c) => {
                'componentId': c.componentId,
                'name': c.name,
                'quantity': c.quantity,
                'price': c.price,
                'isSpecial': c.isSpecial,
                'removalCharge': c.removalCharge,
              })
          .toList(),
      'note': i.note,
      'courseNo': i.courseNo,
      'ticketId': i.ticketId,
      'discount': i.discount,
      'manualDiscount': i.manualDiscount,
      'tva': i.tva,
      'state': i.state,
      'kdsPrintedAt': i.kdsPrintedAt?.toIso8601String(),
      'kdsPrintedQuantity': i.kdsPrintedQuantity,
      'orderTicketPrintedQuantity': i.orderTicketPrintedQuantity,
      'isWeighedItem': i.isWeighedItem,
      'weightKg': i.weightKg,
      'pricePerKgDisplay': i.pricePerKgDisplay,
      'unitName': i.unitName,
      'serialId': i.serialId,
      'serialNumber': i.serialNumber,
      'serverId': i.serverId,
    };

OrderItem _itemFromSnapshot(Map<String, dynamic> j) => OrderItem(
      id: _int(j['id']),
      productId: _int(j['productId'])!,
      productName: j['productName'] as String? ?? '',
      variantId: _int(j['variantId']),
      variantName: j['variantName'] as String?,
      imageUrl: j['imageUrl'] as String?,
      finalPrice: _dbl(j['finalPrice']) ?? 0.0,
      quantity: _dbl(j['quantity']) ?? 1.0,
      savedQuantity: _dbl(j['savedQuantity']),
      components: ((j['components'] as List?) ?? const []).map((e) {
        final c = Map<String, dynamic>.from(e as Map);
        return OrderItemComponent(
          componentId: _int(c['componentId'])!,
          name: c['name'] as String? ?? '',
          quantity: _int(c['quantity']) ?? 1,
          price: _dbl(c['price']) ?? 0.0,
          isSpecial: c['isSpecial'] as bool? ?? false,
          removalCharge: c['removalCharge'] as bool? ?? false,
        );
      }).toList(),
      note: j['note'] as String?,
      courseNo: _int(j['courseNo']),
      ticketId: _int(j['ticketId']),
      discount: _dbl(j['discount']) ?? 0.0,
      manualDiscount: _dbl(j['manualDiscount']) ?? 0.0,
      tva: _dbl(j['tva']) ?? 0.0,
      state: j['state'] as String? ?? 'PENDING',
      kdsPrintedAt: _date(j['kdsPrintedAt']),
      kdsPrintedQuantity: _dbl(j['kdsPrintedQuantity']) ?? 0.0,
      orderTicketPrintedQuantity: _dbl(j['orderTicketPrintedQuantity']) ?? 0.0,
      isWeighedItem: j['isWeighedItem'] as bool? ?? false,
      weightKg: _dbl(j['weightKg']),
      pricePerKgDisplay: _dbl(j['pricePerKgDisplay']),
      unitName: j['unitName'] as String?,
      serialId: _int(j['serialId']),
      serialNumber: j['serialNumber'] as String?,
      serverId: _int(j['serverId']),
    );

int? _int(Object? v) => (v as num?)?.toInt();
double? _dbl(Object? v) => (v as num?)?.toDouble();
DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;

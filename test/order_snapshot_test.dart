import 'dart:convert';

import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/domain/models/order_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a cart survives the update restart field for field', () {
    final printed = DateTime(2026, 10, 21, 12, 30);
    final loaded = DateTime(2026, 10, 21, 12, 0);
    final order = CurrentOrder(
      orderId: 7,
      orderCode: 'A-7',
      sessionOrderNo: 12,
      tableId: 3,
      tableName: 'T3',
      customerId: 9,
      customerName: 'Client',
      customerPhone: '0600',
      commercialId: 2,
      commercialName: 'Com',
      waiterId: 4,
      waiterName: 'Waiter',
      coupon: 'X10',
      discountPercentage: 10,
      note: 'no salt',
      discountReason: 'regular',
      type: 'DELIVERY',
      deliveryAddress: 'Rue 1',
      reference: 'REF',
      reservationCode: 'R-1',
      numberOfPersons: 4,
      tip: 5,
      deliveryFee: 0,
      source: 'POS',
      loadedAt: loaded,
      loadedLineIds: {1, 2},
      tagIds: [5, 6],
      items: [
        OrderItem(
          id: 1,
          productId: 100,
          productName: 'Burger',
          variantId: 3,
          variantName: 'XL',
          imageUrl: 'img',
          finalPrice: 45.5,
          quantity: 2,
          savedQuantity: 1,
          components: [
            OrderItemComponent(
                componentId: 8, name: 'Cheese', quantity: 2, price: 3,
                isSpecial: true),
            OrderItemComponent(
                componentId: 9, name: 'No onion', quantity: 1, price: 1,
                removalCharge: true),
          ],
          note: 'well done',
          courseNo: 2,
          ticketId: 44,
          discount: 1,
          manualDiscount: 2,
          tva: 4.5,
          state: 'PREPARING',
          kdsPrintedAt: printed,
          kdsPrintedQuantity: 1,
          kdsPrintQuantity: 1,
          orderTicketPrintedQuantity: 1,
          isWeighedItem: true,
          weightKg: 0.25,
          pricePerKgDisplay: 180,
          unitName: 'kg',
          serialId: 55,
          serialNumber: 'SN1',
          serverId: 900,
        ),
        OrderItem(productId: 101, productName: 'Cola', finalPrice: 10),
      ],
    );

    // Through a real JSON string, as SharedPreferences stores it.
    final back = orderFromSnapshot(
        jsonDecode(jsonEncode(orderToSnapshot(order))) as Map<String, dynamic>);

    expect(jsonEncode(orderToSnapshot(back)),
        jsonEncode(orderToSnapshot(order)));
    expect(back.total, order.total);
    expect(back.deliveryFee, 0, reason: 'explicit free delivery is kept');
    expect(back.items.first.kdsPrintQuantity, isNull,
        reason: 'transient print override is not carried');
    expect(back.items[1].id, isNull);
    expect(back.items[1].savedQuantity, isNull);
    expect(back.hasUnsavedChanges, order.hasUnsavedChanges);
  });

  test('an empty cart round-trips to an empty cart', () {
    final back = orderFromSnapshot(
        jsonDecode(jsonEncode(orderToSnapshot(CurrentOrder())))
            as Map<String, dynamic>);
    expect(back.items, isEmpty);
    expect(back.orderId, isNull);
    expect(back.deliveryFee, isNull);
    expect(back.type, 'DINE_IN');
  });
}

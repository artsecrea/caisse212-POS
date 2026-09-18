import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/presentation/paymen_screen/payment_screen.dart';
import 'package:caisse212/services/printing_service.dart';

/// The delivery fee's whole design rests on two rules that are easy to break
/// by accident and expensive to break in production:
///
///   1. `null` and `0` mean different things — "no fee recorded" vs "delivery
///      is free" — all the way from the cashier's keyboard to the server.
///   2. The fee is never part of the products total, only of what is collected.
///
/// A regression in either shows up as money that quietly moves between the
/// sales column and the delivery column on a Z report, so pin them here.

OrderItem _item({
  double price = 100,
  double quantity = 1,
  int? ticketId,
}) =>
    OrderItem(
      productId: 1,
      productName: 'Pizza',
      finalPrice: price,
      quantity: quantity,
      ticketId: ticketId,
    );

CurrentOrder _order({
  double? deliveryFee,
  List<OrderItem>? items,
}) =>
    CurrentOrder(
      items: items ?? [_item()],
      type: 'DELIVERY',
      deliveryFee: deliveryFee,
    );

void main() {
  group('CurrentOrder.deliveryFee', () {
    test('an unset fee is null, not zero', () {
      final order = _order();
      expect(order.deliveryFee, isNull);
      expect(order.hasDeliveryFee, isFalse);
      expect(order.deliveryFeeAmount, 0.0);
    });

    test('an explicit zero is a recorded value, not an absence', () {
      final order = _order(deliveryFee: 0);
      expect(order.hasDeliveryFee, isTrue);
      expect(order.deliveryFeeAmount, 0.0);
    });

    test('the fee stays out of the products total', () {
      final products = _order().total;
      final withFee = _order(deliveryFee: 15);

      expect(withFee.total, products);
      expect(withFee.amountDue, products + 15);
    });

    test('amountDue equals total when no fee is recorded', () {
      final order = _order();
      expect(order.amountDue, order.total);
    });
  });

  group('CurrentOrder.copyWith', () {
    test('carries an existing fee through an unrelated change', () {
      final order = _order(deliveryFee: 12).copyWith(numberOfPersons: 4);
      expect(order.deliveryFee, 12);
    });

    test('a null argument cannot clear the fee — that is what the flag is for',
        () {
      final order = _order(deliveryFee: 12).copyWith(deliveryFee: null);
      expect(order.deliveryFee, 12);
    });

    test('clearDeliveryFee returns it to "not recorded"', () {
      final order = _order(deliveryFee: 12).copyWith(clearDeliveryFee: true);
      expect(order.deliveryFee, isNull);
      expect(order.hasDeliveryFee, isFalse);
    });

    test('clearDeliveryFee wins over a value passed at the same time', () {
      final order = _order(deliveryFee: 12)
          .copyWith(deliveryFee: 30, clearDeliveryFee: true);
      expect(order.deliveryFee, isNull);
    });
  });

  group('deliveryFeeToCollect', () {
    // The fee rides the first ticket cut. Divide a delivered order three ways
    // and the other two tickets must not each add it again.
    TicketData ticket({bool isPaid = false}) =>
        TicketData(items: const [], isPaid: isPaid);

    test('is collected while nothing on the order has been paid', () {
      expect(deliveryFeeToCollect(15, [ticket()]), 15);
    });

    test('drops to nothing once any ticket has settled', () {
      expect(
        deliveryFeeToCollect(15, [ticket(isPaid: true), ticket()]),
        0,
      );
    });

    test('a free delivery collects nothing either way', () {
      expect(deliveryFeeToCollect(0, [ticket()]), 0);
    });
  });

  group('PrintingService.feeForThisTicket', () {
    // The same rule as deliveryFeeToCollect above, for the three payment
    // paths that know "has anything been collected?" as prior tickets or as
    // an amount already paid rather than as the payment screen's ticket list.
    test('rides the first cut of the order', () {
      expect(
        PrintingService.feeForThisTicket(15, anythingAlreadyPaid: false),
        15,
      );
    });

    test('never rides a second cut', () {
      // Divide a delivered order and the fee is already on ticket one;
      // adding it again here charges the customer twice for one delivery.
      expect(
        PrintingService.feeForThisTicket(15, anythingAlreadyPaid: true),
        isNull,
      );
    });

    test('an order with no fee recorded puts no row on the ticket', () {
      expect(
        PrintingService.feeForThisTicket(null, anythingAlreadyPaid: false),
        isNull,
      );
    });

    test('a free delivery puts no row on the ticket either', () {
      // Distinct from `null` on the order (see the copyWith group), but the
      // same on paper: a "Delivery fee: 0.00" line is noise.
      expect(
        PrintingService.feeForThisTicket(0, anythingAlreadyPaid: false),
        isNull,
      );
    });
  });
}

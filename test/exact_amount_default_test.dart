import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/presentation/paymen_screen/payment_screen.dart';

/// The calculator pre-fills with the exact amount owed, so a plain cash sale
/// needs no typing — tap straight through to a tender button. This pins
/// exactly when that pre-fill applies and when it correctly stays blank.

TicketData _ticket({
  bool isPaid = false,
  List<TicketLine> items = const [],
}) =>
    TicketData(items: items, isPaid: isPaid);

TicketLine _line(double price, {double quantity = 1}) => TicketLine.whole(
      OrderItem(
        productId: 1,
        productName: 'Item',
        finalPrice: price,
        quantity: quantity,
      ),
    );

void main() {
  group('the plain case', () {
    test('pre-fills the ticket total', () {
      final ticket = _ticket(items: [_line(40)]);
      expect(
        exactAmountDueFor(ticket, [ticket], orderDeliveryFee: 0),
        40.0,
      );
    });

    test('folds in the order-level delivery fee, same as the receipt does',
        () {
      final ticket = _ticket(items: [_line(40)]);
      expect(
        exactAmountDueFor(ticket, [ticket], orderDeliveryFee: 15),
        55.0,
      );
    });
  });

  group('nothing to pre-fill — stays blank, not zero-as-a-value', () {
    test('no ticket selected', () {
      expect(exactAmountDueFor(null, const [], orderDeliveryFee: 0), isNull);
    });

    test('the ticket is already paid — nothing left to tender', () {
      final ticket = _ticket(isPaid: true, items: [_line(40)]);
      expect(
        exactAmountDueFor(ticket, [ticket], orderDeliveryFee: 0),
        isNull,
      );
    });

    test('the ticket has no items yet', () {
      final ticket = _ticket();
      expect(
        exactAmountDueFor(ticket, [ticket], orderDeliveryFee: 0),
        isNull,
      );
    });

    test('a payable amount of exactly zero stays blank', () {
      final ticket = _ticket(items: [_line(0)]);
      expect(
        exactAmountDueFor(ticket, [ticket], orderDeliveryFee: 0),
        isNull,
      );
    });
  });

  group('the delivery-fee-rides-the-first-ticket rule carries through', () {
    test('a second, still-unpaid ticket on a delivered order pre-fills its '
        'own total only — the fee already rode the first', () {
      final paid = _ticket(isPaid: true, items: [_line(20)]);
      final second = _ticket(items: [_line(30)]);
      expect(
        exactAmountDueFor(second, [paid, second], orderDeliveryFee: 15),
        30.0,
        reason: 'deliveryFeeToCollect returns 0 once any ticket is paid — '
            'the same rule the receipt and the totals bar already follow',
      );
    });
  });
}

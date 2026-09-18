import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/services/printing_service.dart';

/// An open table gets a slip on every Continue. Before the delta existed the
/// slip was the WHOLE bill each time, so a table on its third round got three
/// full bills instead of one slip per round. These pin the selection that
/// fixed it — what lands on the slip, and what the totals block therefore
/// prices.

OrderItem _item({
  int? id,
  String name = 'Item',
  double price = 10,
  double quantity = 1,
  double printed = 0,
  int? ticketId,
}) =>
    OrderItem(
      id: id,
      productId: 1,
      productName: name,
      finalPrice: price,
      quantity: quantity,
      orderTicketPrintedQuantity: printed,
      ticketId: ticketId,
    );

List<OrderItem> _lines(List<OrderItem> items, OrderTicketPrintMode mode) =>
    PrintingService().orderTicketLinesForTesting(
      CurrentOrder(items: items),
      mode,
    );

void main() {
  group('full mode — unchanged behaviour for a bill', () {
    test('takes every line, however much was already slipped', () {
      final items = [
        _item(name: 'A', printed: 1),
        _item(name: 'B', quantity: 3, printed: 3),
      ];
      final out = _lines(items, OrderTicketPrintMode.full);
      expect(out, same(items), reason: 'a bill must not be narrowed');
    });

    test('keeps paid lines too — the bill is the whole table', () {
      final out = _lines(
        [_item(ticketId: 7)],
        OrderTicketPrintMode.full,
      );
      expect(out, hasLength(1));
    });
  });

  group('additions-only — what a running table wants', () {
    test('a brand-new line prints in full', () {
      final out = _lines([_item(quantity: 2)], OrderTicketPrintMode.additionsOnly);
      expect(out, hasLength(1));
      expect(out.single.quantity, 2);
    });

    test('an already-slipped line is dropped entirely', () {
      final out = _lines(
        [_item(quantity: 2, printed: 2)],
        OrderTicketPrintMode.additionsOnly,
      );
      expect(out, isEmpty, reason: 'this is the reprint bug');
    });

    test('a bumped line prints only the bump', () {
      // 2 already went out on the first round, the table asked for 3 more.
      final out = _lines(
        [_item(quantity: 5, printed: 2)],
        OrderTicketPrintMode.additionsOnly,
      );
      expect(out.single.quantity, 3);
      expect(out.single.orderTicketPrintQuantity, 3,
          reason: 'a caller must be able to tell a delta line from a whole one');
    });

    test('the delta carries the line price, so the total prices this round only',
        () {
      final out = _lines(
        [_item(price: 10, quantity: 5, printed: 2)],
        OrderTicketPrintMode.additionsOnly,
      );
      final order = CurrentOrder(items: out);
      expect(order.total, 30.0, reason: '3 new units, not 5');
    });

    test('a paid line never comes back — it is on a payment receipt already',
        () {
      final out = _lines(
        [_item(quantity: 2, ticketId: 9)],
        OrderTicketPrintMode.additionsOnly,
      );
      expect(out, isEmpty);
    });

    test('mixes: only the new lines and the new units survive', () {
      final out = _lines([
        _item(name: 'settled', quantity: 1, printed: 1),
        _item(name: 'bumped', quantity: 4, printed: 1),
        _item(name: 'fresh', quantity: 2),
        _item(name: 'paid', quantity: 1, ticketId: 3),
      ], OrderTicketPrintMode.additionsOnly);

      expect(out.map((i) => i.productName), ['bumped', 'fresh']);
      expect(out.map((i) => i.quantity), [3, 2]);
    });

    test('a float wobble is not a new unit', () {
      // 0.3 + 0.3 + 0.3 != 0.9 in binary — the epsilon exists so a weighed
      // line does not slip a phantom 0.0000001kg on every Continue.
      final out = _lines(
        [_item(quantity: 0.3 + 0.3 + 0.3, printed: 0.9)],
        OrderTicketPrintMode.additionsOnly,
      );
      expect(out, isEmpty);
    });

    test('nothing new at all yields an empty slip, not a blank ticket', () {
      final out = _lines([
        _item(quantity: 1, printed: 1),
        _item(quantity: 2, printed: 2),
      ], OrderTicketPrintMode.additionsOnly);
      expect(out, isEmpty);
    });
  });

  group('the source order is left alone', () {
    test('narrowing does not mutate the stored quantities', () {
      final original = _item(quantity: 5, printed: 2);
      _lines([original], OrderTicketPrintMode.additionsOnly);
      expect(original.quantity, 5,
          reason: 'the true total must survive for the DB write-back');
      expect(original.orderTicketPrintedQuantity, 2);
    });
  });
}

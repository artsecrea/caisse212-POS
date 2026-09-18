import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/presentation/widgets/order_panel.dart';
import 'package:flutter_test/flutter_test.dart';

OrderItem line({
  required int id,
  double quantity = 1,
  double printed = 0,
  int? ticketId,
}) =>
    OrderItem(
      id: id,
      productId: id,
      productName: 'p$id',
      finalPrice: 10,
      quantity: quantity,
      kdsPrintedQuantity: printed,
      ticketId: ticketId,
    );

/// The rows the panel actually renders, as order-line indices with a null where
/// the separator goes — the same walk the itemBuilder does.
List<int?> rows(List<OrderItem> items) {
  final layout = orderPanelRowOrder(items);
  final out = <int?>[];
  final rowCount = items.length + (layout.showSeparator ? 1 : 0);
  for (var index = 0; index < rowCount; index++) {
    if (layout.showSeparator && index == layout.separatorAt) {
      out.add(null);
      continue;
    }
    final pos =
        layout.showSeparator && index > layout.separatorAt ? index - 1 : index;
    out.add(layout.ordered[pos]);
  }
  return out;
}

void main() {
  group('order panel sent/new separator', () {
    test('a brand-new order shows no separator', () {
      final items = [line(id: 0), line(id: 1)];
      expect(orderPanelRowOrder(items).showSeparator, isFalse);
      // Newest first, every line rendered, no separator row.
      expect(rows(items), [1, 0]);
    });

    test('a fully sent order shows no separator', () {
      final items = [
        line(id: 0, printed: 1),
        line(id: 1, printed: 1),
      ];
      expect(orderPanelRowOrder(items).showSeparator, isFalse);
      expect(rows(items), [1, 0]);
    });

    test('new lines sit above the separator, sent ones below', () {
      // Rung first (already sent), then a burger added this round.
      final items = [
        line(id: 0, printed: 1), // pizza, sent
        line(id: 1, printed: 1), // drink, sent
        line(id: 2), // burger, new
      ];
      // Burger, separator, then the sent pair newest-first.
      expect(rows(items), [2, null, 1, 0]);
    });

    test('a line with added units counts as new even though it was sent', () {
      // qty 1 -> 3 on an already-sent line: the kitchen is owed 2 more.
      final items = [
        line(id: 0, quantity: 3, printed: 1),
        line(id: 1, printed: 1),
      ];
      expect(rows(items), [0, null, 1]);
    });

    test('a paid line is never new, whatever its printed quantity', () {
      final items = [
        line(id: 0, quantity: 3, printed: 0, ticketId: 7),
        line(id: 1), // the only genuinely new line
      ];
      expect(rows(items), [1, null, 0]);
    });

    test('indices address the real order lines, never the row numbers', () {
      // The mapping that matters: removeItem/_showItemOptions take these.
      final items = [
        line(id: 0, printed: 1),
        line(id: 1),
        line(id: 2, printed: 1),
        line(id: 3),
      ];
      final rendered = rows(items);
      // Every line appears exactly once, and the separator exactly once.
      expect(rendered.whereType<int>().toSet(), {0, 1, 2, 3});
      expect(rendered.where((r) => r == null).length, 1);
      // New lines (1, 3) precede the separator; sent lines (0, 2) follow it.
      final sep = rendered.indexOf(null);
      expect(rendered.sublist(0, sep), [3, 1]);
      expect(rendered.sublist(sep + 1), [2, 0]);
    });

    test('an empty order produces no rows and no separator', () {
      expect(orderPanelRowOrder(const []).showSeparator, isFalse);
      expect(rows(const []), isEmpty);
    });
  });
}

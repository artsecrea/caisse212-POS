import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/presentation/paymen_screen/payment_screen.dart';

/// Division and merging on the payment screen are provisional: they only
/// rearrange [TicketLine]s, and the database is told what happened when a
/// ticket is paid, from each line's `sources`. That makes `sources` the record
/// of who owes what — if it stops matching the line's quantity, the order gets
/// paid for a quantity it does not contain, so these are money tests.

OrderItem _item({
  int? id = 1,
  double quantity = 1,
  int productId = 10,
  int? variantId,
  double finalPrice = 10.0,
  double discount = 0.0,
  double manualDiscount = 0.0,
  double tva = 0.0,
  String? note,
  List<OrderItemComponent> components = const [],
  int? serialId,
}) =>
    OrderItem(
      id: id,
      productId: productId,
      productName: 'Coffee',
      variantId: variantId,
      finalPrice: finalPrice,
      quantity: quantity,
      discount: discount,
      manualDiscount: manualDiscount,
      tva: tva,
      note: note,
      components: components,
      serialId: serialId,
    );

double _claimed(TicketLine line) =>
    line.sources.fold<double>(0, (sum, s) => sum + s.quantity);

void main() {
  group('TicketLine.split', () {
    test('halves stay backed by exactly the quantity they show', () {
      final line = TicketLine.whole(_item(id: 7, quantity: 3));

      final (kept, taken) = line.split(1);

      expect(kept.item.quantity, 2);
      expect(taken.item.quantity, 1);
      expect(_claimed(kept), 2);
      expect(_claimed(taken), 1);
      expect(kept.sources.single.rowId, 7);
      expect(taken.sources.single.rowId, 7);
    });

    test('a merged line divides its claim across both rows', () {
      final a = TicketLine.whole(_item(id: 1, quantity: 2));
      final b = TicketLine.whole(_item(id: 2, quantity: 1));

      final merged = a.mergedWith(b);
      expect(merged.item.quantity, 3);
      expect(_claimed(merged), 3);

      final (kept, taken) = merged.split(1);

      // Total claimed is conserved, and no row is claimed twice.
      expect(_claimed(kept) + _claimed(taken), 3);
      expect(kept.item.quantity, 2);
      expect(taken.item.quantity, 1);

      final perRow = <int, double>{};
      for (final source in [...kept.sources, ...taken.sources]) {
        perRow[source.rowId] = (perRow[source.rowId] ?? 0) + source.quantity;
      }
      expect(perRow, {1: 2.0, 2: 1.0});
    });

    test('splitting exactly on a source boundary does not fracture it', () {
      final merged = TicketLine.whole(_item(id: 1, quantity: 2))
          .mergedWith(TicketLine.whole(_item(id: 2, quantity: 1)));

      final (kept, taken) = merged.split(2);

      expect(taken.sources.single, (rowId: 1, quantity: 2.0));
      expect(kept.sources.single, (rowId: 2, quantity: 1.0));
    });

    test('repeated division keeps every unit accounted for', () {
      var line = TicketLine.whole(_item(id: 3, quantity: 5));
      final pieces = <TicketLine>[];

      for (var i = 0; i < 4; i++) {
        final (kept, taken) = line.split(1);
        pieces.add(taken);
        line = kept;
      }
      pieces.add(line);

      expect(pieces.fold<double>(0, (s, l) => s + l.item.quantity), 5);
      expect(pieces.fold<double>(0, (s, l) => s + _claimed(l)), 5);
    });
  });

  group('canCombineLines', () {
    test('same product at the same price combines', () {
      expect(canCombineLines(_item(id: 1), _item(id: 2)), isTrue);
    });

    test('a different price never combines', () {
      // The merged line charges one price for every unit, so combining across
      // prices would silently reprice the cheaper — or dearer — half.
      expect(
        canCombineLines(_item(finalPrice: 10), _item(finalPrice: 12)),
        isFalse,
      );
    });

    test('different discounts never combine', () {
      expect(
        canCombineLines(_item(manualDiscount: 0), _item(manualDiscount: 2)),
        isFalse,
      );
    });

    test('different components never combine', () {
      final withExtra = _item(components: [
        OrderItemComponent(
            componentId: 4, name: 'Extra shot', quantity: 1, price: 3),
      ]);
      expect(canCombineLines(withExtra, _item()), isFalse);
      expect(canCombineLines(withExtra, withExtra), isTrue);
    });

    test('different notes never combine', () {
      expect(canCombineLines(_item(note: 'no sugar'), _item()), isFalse);
    });

    test('serial lines never combine — each names one physical unit', () {
      expect(canCombineLines(_item(serialId: 9), _item(serialId: 8)), isFalse);
      expect(canCombineLines(_item(serialId: 9), _item()), isFalse);
    });

    test('different variants never combine', () {
      expect(canCombineLines(_item(variantId: 1), _item(variantId: 2)), isFalse);
    });
  });
}

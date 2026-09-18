import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:flutter_test/flutter_test.dart';

OrderItem pizza({int? id, double quantity = 1, double printed = 0, String? note}) =>
    OrderItem(
      id: id,
      productId: 42,
      productName: 'Pizza',
      finalPrice: 12,
      quantity: quantity,
      kdsPrintedQuantity: printed,
      note: note,
    );

void main() {
  group('addItem merging', () {
    test('two taps before saving collapse into one line', () {
      // The behaviour that makes ringing up fast — unchanged.
      final n = OrderNotifier()
        ..addItem(pizza())
        ..addItem(pizza());

      expect(n.state.items, hasLength(1));
      expect(n.state.items.single.quantity, 2);
    });

    test('a saved line is never merged into — the new units get their own line',
        () {
      // Order was saved and sent; the cashier rings the same product again.
      final n = OrderNotifier()
        ..addItem(pizza(id: 7, printed: 1))
        ..addItem(pizza());

      expect(n.state.items, hasLength(2));
      // Saved line untouched, so the panel still shows it as already sent.
      expect(n.state.items.first.id, 7);
      expect(n.state.items.first.quantity, 1);
      expect(n.state.items.first.kdsPrintedQuantity, 1);
      // New units are their own, unsaved, unsent line.
      expect(n.state.items.last.id, isNull);
      expect(n.state.items.last.quantity, 1);
      expect(n.state.items.last.kdsPrintedQuantity, 0);
    });

    test('the new line goes last, so the panel shows it on top', () {
      // The panel renders newest-first, so "appended last" == "shown first".
      final n = OrderNotifier()
        ..addItem(pizza(id: 7, printed: 1))
        ..addItem(pizza());

      expect(n.state.items.last.id, isNull);
    });

    test('further taps merge into the new line, not the saved one', () {
      final n = OrderNotifier()
        ..addItem(pizza(id: 7, printed: 1))
        ..addItem(pizza())
        ..addItem(pizza());

      expect(n.state.items, hasLength(2));
      expect(n.state.items.first.quantity, 1, reason: 'saved line untouched');
      expect(n.state.items.last.quantity, 2, reason: 'new units pooled');
    });

    test('a saved line is skipped even when nothing was sent to the kitchen',
        () {
      // KDS off / print rules excluded it: kdsPrintedQuantity stays 0, but the
      // line is still persisted, so it must not absorb new units.
      final n = OrderNotifier()
        ..addItem(pizza(id: 7))
        ..addItem(pizza());

      expect(n.state.items, hasLength(2));
    });

    test('unsaved lines still respect the existing merge rules', () {
      // A differing note has always split the line; that is unchanged.
      final n = OrderNotifier()
        ..addItem(pizza(note: 'no olives'))
        ..addItem(pizza());

      expect(n.state.items, hasLength(2));
    });
  });
}

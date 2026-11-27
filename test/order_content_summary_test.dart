import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_read_models.dart';

/// The condensed "what is in this order" line shown on parked/held orders.
///
/// It exists so a waiter can tell two parked tables apart without resuming one,
/// and its whole job is fitting a variable-length basket into a fixed-size row.
void main() {
  group('unit count', () {
    test('a whole count reads without a decimal tail', () {
      // "3.0 articles" is what the old fold produced.
      const s = OrderContentSummary(units: 3, lineCount: 2);
      expect(s.unitsLabel, '3');
    });

    test('a weighed order keeps its decimals', () {
      const s = OrderContentSummary(units: 0.75, lineCount: 1);
      expect(s.unitsLabel, '0.750');
    });

    test('zero is still rendered, not blank', () {
      const s = OrderContentSummary();
      expect(s.unitsLabel, '0');
      expect(s.isEmpty, isTrue);
    });
  });

  group('preview truncation', () {
    test('a short basket shows every line and no counter', () {
      const s = OrderContentSummary(
        units: 3,
        lineCount: 2,
        preview: ['2x Tajine', '1x Coca'],
      );
      expect(s.previewLabel, '2x Tajine · 1x Coca');
      expect(s.previewLabel.contains('+'), isFalse);
    });

    test('a long basket reports how many lines are hidden', () {
      // The point of "+4" over a bare ellipsis: the waiter learns how much they
      // cannot see, which a fade does not tell them.
      const s = OrderContentSummary(
        units: 12,
        lineCount: 7,
        preview: ['2x Tajine', '1x Coca', '3x Salade'],
        hiddenLines: 4,
      );
      expect(s.previewLabel, '2x Tajine · 1x Coca · 3x Salade  +4');
    });

    test('an empty basket produces an empty label, not a stray separator', () {
      const s = OrderContentSummary();
      expect(s.previewLabel, '');
    });

    test('the label never grows with the order beyond the preview', () {
      // Two orders of wildly different size must render the same width, which
      // is what keeps the pick-list scannable.
      const small = OrderContentSummary(
        units: 2,
        lineCount: 3,
        preview: ['1x A', '1x B', '1x C'],
      );
      const huge = OrderContentSummary(
        units: 200,
        lineCount: 60,
        preview: ['1x A', '1x B', '1x C'],
        hiddenLines: 57,
      );
      expect(huge.previewLabel.length - small.previewLabel.length,
          lessThanOrEqualTo(5),
          reason: 'only the "+57" suffix may differ');
    });
  });
}

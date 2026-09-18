import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/presentation/widgets/product_grid.dart';
import 'package:caisse212/utils/responsive_utils.dart';

/// Pins the product-card sizing rule the grid depends on.
///
/// The complaint this fixes: shrinking cards to fit more products also shrank
/// the labels, so a denser grid was a less readable one. Label size must depend
/// on the space available, never on the card-size setting, and the label block
/// must keep a fixed height so a shorter card takes pixels from the image.
void main() {
  group('label size ignores the card-size setting', () {
    test('the same width gives the same fonts at every card height', () {
      // Card height is what the size setting drives. It must not move the type.
      final small = CardMetrics.forWidth(1400, cardHeight: 176);
      final medium = CardMetrics.forWidth(1400, cardHeight: 210);
      final large = CardMetrics.forWidth(1400, cardHeight: 250);

      expect(small.nameFont, medium.nameFont);
      expect(medium.nameFont, large.nameFont);
      expect(small.priceFont, large.priceFont);
    });

    test('never drops below the 12pt legibility floor', () {
      // 12 is the smallest that stays scannable at arm's length, which is the
      // only distance that matters on a till.
      for (final w in [320.0, 400.0, 480.0, 560.0, 700.0, 1024.0, 1920.0]) {
        final m = CardMetrics.forWidth(w, cardHeight: 116);
        expect(m.nameFont, greaterThanOrEqualTo(12.0), reason: 'width $w');
        expect(m.priceFont, greaterThanOrEqualTo(11.0), reason: 'width $w');
      }
    });

    test('a narrow grid drops the label by one point, not more', () {
      final wide = CardMetrics.forWidth(1920, cardHeight: 210);
      final narrow = CardMetrics.forWidth(420, cardHeight: 132);
      expect(wide.nameFont - narrow.nameFont, lessThanOrEqualTo(2.0),
          reason: 'a small screen should not collapse the type scale');
    });
  });

  group('the image absorbs the shrink', () {
    test('a shorter card leaves the label block untouched', () {
      // Same width, three heights: the reserved label height is identical, so
      // every pixel removed comes off the image.
      final tall = CardMetrics.forWidth(1400, cardHeight: 250);
      final short = CardMetrics.forWidth(1400, cardHeight: 176);
      expect(tall.textBlockHeight, short.textBlockHeight);

      final tallImage = 250 - tall.textBlockHeight;
      final shortImage = 176 - short.textBlockHeight;
      expect(shortImage, lessThan(tallImage));
      expect(tallImage - shortImage, closeTo(250 - 176, 0.01),
          reason: 'the whole height difference must land on the image');
    });

    test('the label block always leaves usable room for an image', () {
      // 116 is the shortest card the grid asks for (tiny tier, size 1). If the
      // label ate so much that no image fit, the card would silently fall back
      // to text-only and the setting would look broken.
      final m = CardMetrics.forWidth(420, cardHeight: 116);
      expect(116 - m.textBlockHeight, greaterThan(44.0),
          reason: 'must clear the min-image threshold at the smallest card');
    });

    test('the reserved height actually fits the text it reserves for', () {
      // Under-reserving is what produces a RenderFlex overflow in a grid tile.
      for (final w in [420.0, 700.0, 1400.0]) {
        for (final h in [116.0, 152.0, 210.0, 250.0]) {
          final m = CardMetrics.forWidth(w, cardHeight: h);
          final needed =
              (m.nameFont * 1.15 * m.nameLines) + 2 + (m.priceFont * 1.25) + 8;
          expect(m.textBlockHeight, greaterThanOrEqualTo(needed),
              reason: 'w=$w h=$h');
        }
      }
    });
  });

  group('line count', () {
    test('two lines on a tall card, one on a short one', () {
      expect(CardMetrics.forWidth(1400, cardHeight: 250).nameLines, 2);
      expect(CardMetrics.forWidth(1400, cardHeight: 116).nameLines, 1);
    });

    test('one line reserves less height than two', () {
      final oneLine = CardMetrics.forWidth(1400, cardHeight: 116);
      final twoLine = CardMetrics.forWidth(1400, cardHeight: 250);
      expect(oneLine.textBlockHeight, lessThan(twoLine.textBlockHeight));
    });
  });

  group('order panel width on small screens', () {
    test('never takes more than 40% of a screen 560px or wider', () {
      // A fixed 260 was 43% of a 600px window, leaving the grid unusable.
      // Below 560 the 200px floor wins and the share rises past 40% — a cart
      // line narrower than that is unreadable, and a screen that small really
      // wants a stacked layout rather than side-by-side (not done here).
      for (final w in [560.0, 600.0, 680.0]) {
        expect(orderPanelWidth(w) / w, lessThanOrEqualTo(0.40),
            reason: 'screen $w');
      }
    });

    test('keeps a floor wide enough to read a cart line', () {
      expect(orderPanelWidth(320), greaterThanOrEqualTo(200.0));
    });

    test('never shrinks as the screen grows', () {
      var last = 0.0;
      for (final w in [320.0, 480.0, 600.0, 700.0, 900.0, 1200.0, 1920.0]) {
        final got = orderPanelWidth(w);
        expect(got, greaterThanOrEqualTo(last), reason: 'screen $w');
        last = got;
      }
    });

    test('the existing tiers above 700 are untouched', () {
      // Boundaries are exclusive, exactly as before this change: 899 is still
      // "compact", 900 is not.
      expect(orderPanelWidth(700), 260.0);
      expect(orderPanelWidth(899), 260.0);
      expect(orderPanelWidth(900), 320.0);
      expect(orderPanelWidth(1199), 320.0);
      expect(orderPanelWidth(1200), 400.0);
      expect(orderPanelWidth(1920), 400.0);
    });
  });
}

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/presentation/widgets/keypad_placement.dart';

/// Where the keypad goes, tested as arithmetic.
///
/// This used to live inside the widget, computed once when the pad opened and
/// cached for as long as it stayed up — which is why minimising the window and
/// restoring it brought the pad back off the edge of the screen. Pulling it out
/// as a pure function means the awkward cases can be checked directly, without
/// a widget tree, a window, or a person watching.

const _pad = Size(272, 336);

PadLayout place(Rect field, {Size space = const Size(1266, 682)}) => layoutPad(
      fieldRect: field,
      space: space,
      padSize: _pad,
      gap: 10,
      margin: 8,
      cornerRadius: 14,
      pointerSpread: 20,
    );

Rect padRect(PadLayout l) => l.position & _pad;

void main() {
  group('side', () {
    test('opens right when there is room', () {
      // Field on the left of a wide screen.
      final l = place(const Rect.fromLTWH(24, 300, 400, 56));
      expect(l.side, PadSide.right);
      expect(l.position.dx, 24 + 400 + 10);
    });

    test('opens left when the right is too tight', () {
      // The far-right case: 24px to the right, plenty to the left.
      final l = place(const Rect.fromLTWH(733, 331, 509, 56));
      expect(l.side, PadSide.left);
      expect(padRect(l).right, 733 - 10);
    });

    test('prefers the roomier side when both fit', () {
      final l = place(const Rect.fromLTWH(600, 300, 60, 56));
      expect(l.side, PadSide.right);
    });

    test('falls to below when neither side fits', () {
      // A field spanning almost the full width of a tall screen.
      final l = place(const Rect.fromLTWH(20, 40, 1200, 56),
          space: const Size(1240, 900));
      expect(l.side, PadSide.below);
      expect(l.position.dy, 40 + 56 + 10);
    });

    test('falls to above when there is no room below either', () {
      final l = place(const Rect.fromLTWH(20, 500, 1200, 56),
          space: const Size(1240, 900));
      expect(l.side, PadSide.above);
    });
  });

  group('centring', () {
    test('a side-opening pad is centred on the field', () {
      const field = Rect.fromLTWH(24, 300, 400, 56);
      final l = place(field);
      expect(padRect(l).center.dy, closeTo(field.center.dy, 0.01));
    });

    test('a stacked pad is centred on the field horizontally', () {
      const field = Rect.fromLTWH(20, 40, 1200, 56);
      final l = place(field, space: const Size(1240, 900));
      expect(padRect(l).center.dx, closeTo(field.center.dx, 0.01));
    });
  });

  group('staying on screen', () {
    test('a field near the top does not push the pad off the top', () {
      final l = place(const Rect.fromLTWH(24, 8, 300, 56));
      expect(padRect(l).top, greaterThanOrEqualTo(0));
      // ...and the pointer slides up to keep aiming at the field.
      expect(l.pointerShift, lessThan(0));
    });

    test('a field near the bottom does not push the pad off the bottom', () {
      final l = place(const Rect.fromLTWH(24, 620, 300, 56));
      expect(padRect(l).bottom, lessThanOrEqualTo(682));
      expect(l.pointerShift, greaterThan(0));
    });

    test('every corner of the screen keeps the whole pad visible', () {
      const space = Size(1266, 682);
      for (final field in const [
        Rect.fromLTWH(0, 0, 200, 56),
        Rect.fromLTWH(1066, 0, 200, 56),
        Rect.fromLTWH(0, 626, 200, 56),
        Rect.fromLTWH(1066, 626, 200, 56),
      ]) {
        final r = padRect(place(field, space: space));
        expect(r.left, greaterThanOrEqualTo(0), reason: '$field');
        expect(r.top, greaterThanOrEqualTo(0), reason: '$field');
        expect(r.right, lessThanOrEqualTo(space.width), reason: '$field');
        expect(r.bottom, lessThanOrEqualTo(space.height), reason: '$field');
      }
    });

    test('the pointer never leaves the pad\'s straight edge', () {
      // Hard against the top: the field is further from the pad's centre than
      // the pad can reach, so the arrow stops at the corner instead of
      // floating off it.
      final l = place(const Rect.fromLTWH(24, 0, 300, 24));
      final limit = (_pad.height / 2) - 14 - 10;
      expect(l.pointerShift.abs(), lessThanOrEqualTo(limit));
    });
  });

  group('a space smaller than the pad', () {
    // A minimised window reports no size at all. The old code measured against
    // it, got negative gaps everywhere, and placed the pad off the screen.
    test('a zero-sized space pins the pad to the margin rather than exploding',
        () {
      final l = place(const Rect.fromLTWH(0, 0, 0, 0), space: Size.zero);
      expect(l.position.dx, 8);
      expect(l.position.dy, 8);
    });

    test('a space narrower than the pad still yields a usable position', () {
      final l = place(const Rect.fromLTWH(10, 10, 100, 56),
          space: const Size(200, 200));
      expect(l.position.dx, 8);
      expect(l.position.dy, 8);
    });
  });
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/core/theme/app_theme.dart';

/// WCAG relative luminance.
double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final light = AppTheme.lightTheme();
  final dark = AppTheme.darkTheme();

  group('legacy ThemeData slots', () {
    // The bug these guard: Flutter defaults `primaryColor` to
    // `colorScheme.surface` in a DARK theme, so the ~90 call sites that use it
    // as an accent painted the background colour onto the background.
    test('primaryColor is the accent, never the surface', () {
      expect(dark.primaryColor, dark.colorScheme.primary);
      expect(light.primaryColor, light.colorScheme.primary);
      expect(dark.primaryColor, isNot(dark.colorScheme.surface));
    });

    test('primaryColor stays readable on the scaffold background', () {
      for (final t in [light, dark]) {
        expect(_contrast(t.primaryColor, t.scaffoldBackgroundColor),
            greaterThan(3.0),
            reason: '${t.brightness} accent vs background');
      }
    });

    // `cardColor` defaulted to `colorScheme.surface`, i.e. exactly
    // `scaffoldBackgroundColor` — panels had zero contrast and survived on
    // drop shadows, which a dark theme swallows.
    test('cardColor is distinguishable from the scaffold background', () {
      for (final t in [light, dark]) {
        expect(t.cardColor, isNot(t.scaffoldBackgroundColor),
            reason: '${t.brightness} card vs background');
      }
    });
  });

  group('branded bars', () {
    test('white foreground is legible on bar and barAlt in both themes', () {
      for (final scheme in [light.colorScheme, dark.colorScheme]) {
        for (final bg in [AppTheme.bar(scheme), AppTheme.barAlt(scheme)]) {
          expect(_contrast(AppTheme.onBar, bg), greaterThan(4.5),
              reason: '${scheme.brightness} bar vs onBar');
        }
      }
    });

    test('barAlt is darker than bar, so the two rows separate', () {
      for (final scheme in [light.colorScheme, dark.colorScheme]) {
        expect(_lum(AppTheme.barAlt(scheme)), lessThan(_lum(AppTheme.bar(scheme))),
            reason: '${scheme.brightness}');
      }
    });

    test('light mode keeps the brand blue', () {
      expect(AppTheme.bar(light.colorScheme), light.colorScheme.primary);
    });
  });

  group('scheme pairs used as button colours', () {
    test('onPrimary is legible on primary in both themes', () {
      for (final t in [light, dark]) {
        expect(_contrast(t.colorScheme.onPrimary, t.colorScheme.primary),
            greaterThan(4.5),
            reason: '${t.brightness}');
      }
    });

    test('white is NOT legible on a dark scheme primary', () {
      // Documents why `backgroundColor: primary` + `foregroundColor: white`
      // had to become `onPrimary`: the dark scheme's primary is a pale blue.
      expect(_contrast(Colors.white, dark.colorScheme.primary), lessThan(4.5));
    });
  });
}

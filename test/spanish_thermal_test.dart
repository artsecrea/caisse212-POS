import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/services/printing_service.dart';
import 'package:caisse212/utils/app_localizations.dart';
import 'package:flutter/material.dart' show Locale;

/// Spanish on paper.
///
/// An unencodable character does not merely look wrong on a thermal printer:
/// it can stall the print head mid-stream and hang the ticket (see
/// `_sanitizeForThermal`). So every character Spanish actually needs is
/// checked to survive the sanitiser, and the two that are deliberately
/// rewritten are pinned so nobody "fixes" them back.
void main() {
  String clean(String s) => PrintingService.sanitizeForThermalTest(s);

  group('Spanish characters reach the printer intact', () {
    test('accented vowels survive in both cases', () {
      const vowels = 'áéíóúÁÉÍÓÚ';
      expect(clean(vowels), vowels);
    });

    test('n with tilde survives', () {
      // The one letter whose loss would be unmissable on a Spanish menu.
      expect(clean('Ñoquis con piñones'), 'Ñoquis con piñones');
    });

    test('u with diaeresis survives', () {
      expect(clean('Pingüino, VERGÜENZA'), 'Pingüino, VERGÜENZA');
    });

    test('the inverted marks survive', () {
      // CP1252 0xBF / 0xA1, and present in CP437 too, so both the page we ask
      // for and the page a cheap printer may really be on can render them.
      expect(clean('¿Efectivo? ¡Gracias!'), '¿Efectivo? ¡Gracias!');
    });

    test('angle quotes survive', () {
      expect(clean('«Menú del día»'), '«Menú del día»');
    });

    test('a whole receipt line is untouched', () {
      const line = 'Cantidad: 2 x Jamón ibérico — sin cebolla';
      // Only the em dash is rewritten, and it was already.
      expect(clean(line), 'Cantidad: 2 x Jamón ibérico - sin cebolla');
    });
  });

  group('the two deliberate rewrites', () {
    test('ordinal indicators become plain letters', () {
      // Spanish writes these constantly (Nº, 1.º, 2.ª). CP437 renders 0xBA as
      // a box-drawing glyph, so the abbreviation is the safe form and is what
      // a Spanish reader expects anyway.
      expect(clean('Nº 12, 1.º piso, 2.ª mesa'), 'No 12, 1.o piso, 2.a mesa');
    });

    test('the euro sign becomes EUR', () {
      expect(clean('12,50 €'), '12,50 EUR');
    });
  });

  group('the Spanish bundle', () {
    final es = AppLocalizations(const Locale('es'));
    final en = AppLocalizations(const Locale('en'));

    test('a missing key would print its own id, so none may be missing', () {
      // translate() falls back to the key itself, not to English, and the
      // ticket builder reads this same map. A gap does not degrade to English
      // on a receipt - it prints 'order_code'.
      final missing = <String>[];
      for (final key in AppLocalizations.keysFor('en')) {
        if (es.translate(key) == key && en.translate(key) != key) {
          missing.add(key);
        }
      }
      expect(missing, isEmpty,
          reason: '${missing.length} Spanish keys missing: '
              '${missing.take(15).join(', ')}');
    });

    test('Spanish adds no character English did not already have', () {
      // A handful of UI-only labels carry glyphs a thermal head cannot
      // encode - the favourites star, the warning sign, the bullets in the
      // session dialog. None of those keys is ever printed, and they read
      // the same in every bundle, so the useful invariant is not 'Spanish
      // is clean' but 'Spanish is no worse than English'. That still catches
      // the real risk: a smart quote or an em dash typed into a Spanish
      // label that the English one does not have.
      bool unprintable(String v) {
        final safe = clean(v);
        return safe.contains('?') && !v.contains('?');
      }

      final regressions = <String>[];
      for (final key in AppLocalizations.keysFor('es')) {
        if (unprintable(es.translate(key)) &&
            !unprintable(en.translate(key))) {
          regressions.add(key);
        }
      }
      expect(regressions, isEmpty,
          reason: 'unprintable characters new to Spanish in: '
              '${regressions.take(15).join(', ')}');
    });
  });
}

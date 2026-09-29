import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/utils/elapsed_label.dart';

/// The "how long has the kitchen had this" badge on a sent order line.
///
/// Short forms, because it sits beside a product name on a cramped row, and
/// capped, because past a point the exact figure stops being information: a
/// table nine hours old is one somebody forgot to close, not one running late.

void main() {
  final sentAt = DateTime(2026, 9, 19, 12, 0);
  String at(Duration elapsed, {String locale = 'en'}) =>
      elapsedLabel(sentAt, now: sentAt.add(elapsed), locale: locale);

  group('the short form is what lands on the row', () {
    test('minutes read as a number and a letter, not a sentence', () {
      expect(at(const Duration(minutes: 5)), '5m');
      expect(at(const Duration(minutes: 42)), '42m');
    });

    test('hours too', () {
      expect(at(const Duration(hours: 2)), '2h');
      expect(at(const Duration(hours: 8)), '8h');
    });

    test('a line just sent does not read as an hour or a blank', () {
      final label = at(const Duration(seconds: 3));
      expect(label, isNotEmpty);
      expect(label, isNot(contains('h')));
    });
  });

  group('the cap', () {
    test('exactly at the cap already shows the capped form', () {
      expect(at(const Duration(hours: 9)), '+9h');
    });

    test('and stays there however long it runs', () {
      expect(at(const Duration(hours: 14)), '+9h');
      expect(at(const Duration(days: 3)), '+9h',
          reason: 'a forgotten table must not grow a badge that reflows the '
              'row');
    });

    test('just under the cap is still a real figure', () {
      expect(at(const Duration(hours: 8, minutes: 59)), isNot('+9h'));
    });

    test('the cap is configurable, for callers that want a tighter one', () {
      expect(
        elapsedLabel(sentAt,
            now: sentAt.add(const Duration(hours: 3)),
            cap: const Duration(hours: 2)),
        '+2h',
      );
    });
  });

  group('the awkward inputs', () {
    test('no timestamp is no badge, not a zero', () {
      expect(elapsedLabel(null), '');
    });

    test('a future timestamp reads as fresh, never negative', () {
      // The LAN devices that stamp these have their own clocks.
      final label = elapsedLabel(sentAt,
          now: sentAt.subtract(const Duration(minutes: 3)));
      expect(label, isNotEmpty);
      expect(label, isNot(startsWith('-')));
    });

    test('an unknown locale falls back rather than throwing', () {
      expect(at(const Duration(minutes: 5), locale: 'de'), '5m');
      expect(at(const Duration(minutes: 5), locale: ''), '5m');
    });

    test('a full locale tag still resolves to its language', () {
      expect(at(const Duration(minutes: 5), locale: 'en_US'), '5m');
    });
  });

  group('the app languages all render', () {
    test('each returns something, and the cap is language-independent', () {
      for (final locale in ['en', 'fr', 'ar', 'es']) {
        expect(at(const Duration(minutes: 5), locale: locale), isNotEmpty,
            reason: '$locale produced nothing — its short messages are '
                'probably unregistered, which silently falls back to English '
                'long form');
        expect(at(const Duration(hours: 12), locale: locale), '+9h');
      }
    });
  });
}

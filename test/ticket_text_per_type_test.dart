import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/app_settings.dart';

/// Header and footer used to be one text shared by every document, which is
/// wrong the moment the texts have different jobs: the customer copy wants a
/// thank-you, the store copy wants a signature line, the order ticket wants
/// neither.
///
/// The rule that matters is the fallback — a till that only ever set the
/// shared text must keep printing it on every ticket, or an upgrade silently
/// blanks headers across the shop.

void main() {
  group('reading stored overrides back', () {
    test('a plain string map survives the round trip', () {
      expect(parseTicketTexts({'order': 'KITCHEN', 'customer': 'Merci'}),
          {'order': 'KITCHEN', 'customer': 'Merci'});
    });

    test('blank entries are dropped, so they fall back rather than blanking',
        () {
      expect(parseTicketTexts({'order': '', 'store': 'X'}), {'store': 'X'});
    });

    test('junk reads as no overrides instead of throwing on startup', () {
      expect(parseTicketTexts(null), isEmpty);
      expect(parseTicketTexts('not a map'), isEmpty);
      expect(parseTicketTexts(42), isEmpty);
      expect(parseTicketTexts({'order': 7, 3: 'x'}), isEmpty);
    });
  });

  group('the settings model', () {
    test('defaults to no overrides and to printing the reason', () {
      const s = AppSettings();
      expect(s.ticketHeaders, isEmpty);
      expect(s.ticketFooters, isEmpty);
      expect(s.printDiscountReason, isTrue,
          reason: 'a reduction with no stated reason is the line an auditor '
              'asks about');
    });

    test('survives a JSON round trip', () {
      const before = AppSettings(
        ticketHeader: 'SHARED',
        ticketHeaders: {'customer': 'THANK YOU'},
        ticketFooters: {'store': 'Signature:'},
        printDiscountReason: false,
      );
      final after = AppSettings.fromJson(before.toJson());

      expect(after.ticketHeader, 'SHARED');
      expect(after.ticketHeaders, {'customer': 'THANK YOU'});
      expect(after.ticketFooters, {'store': 'Signature:'});
      expect(after.printDiscountReason, isFalse);
    });

    test('an older stored config reads as shared-text-only', () {
      // Exactly what a build before this feature wrote.
      final old = {'ticketHeader': 'SHARED', 'ticketFooter': 'BYE'};
      final s = AppSettings.fromJson(old);

      expect(s.ticketHeader, 'SHARED');
      expect(s.ticketHeaders, isEmpty,
          reason: 'no overrides means every type inherits the shared text');
      expect(s.printDiscountReason, isTrue);
    });

    test('copyWith carries the maps and the switch', () {
      const s = AppSettings();
      final next = s.copyWith(
        ticketHeaders: {'order': 'K'},
        printDiscountReason: false,
      );
      expect(next.ticketHeaders, {'order': 'K'});
      expect(next.printDiscountReason, isFalse);
      expect(next.ticketFooters, isEmpty, reason: 'untouched stays untouched');
    });
  });
}

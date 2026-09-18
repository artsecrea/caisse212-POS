import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/session_expiry.dart';

/// When the till warns that its sign-in is running out.
///
/// Two thresholds have to stay in step: the notice starts at seven days, and
/// stops at one — because at one day the app blocks on its own and a banner
/// beside a blocking dialog is noise. Getting the boundary wrong either nags
/// for a week with no escalation, or says nothing until the till locks.

final now = DateTime(2026, 9, 1, 12);

DateTime inDays(double d) =>
    now.add(Duration(minutes: (d * 24 * 60).round()));

void main() {
  group('which notice applies', () {
    test('nothing at all when the expiry is unknown', () {
      // Old installs, or a credential with no readable expiry. A warning
      // nobody can act on, shown forever, teaches people to ignore warnings.
      expect(sessionExpiryLevel(null, now), SessionExpiryLevel.none);
    });

    test('silence with more than a week left', () {
      expect(sessionExpiryLevel(inDays(8), now), SessionExpiryLevel.none);
      expect(sessionExpiryLevel(inDays(30), now), SessionExpiryLevel.none);
    });

    test('a notice from seven days out', () {
      expect(sessionExpiryLevel(inDays(7), now), SessionExpiryLevel.notice);
      expect(sessionExpiryLevel(inDays(6.5), now), SessionExpiryLevel.notice);
      expect(sessionExpiryLevel(inDays(1.5), now), SessionExpiryLevel.notice);
    });

    test('the blocking gate takes over inside a day', () {
      expect(sessionExpiryLevel(inDays(1), now), SessionExpiryLevel.blocked);
      expect(sessionExpiryLevel(inDays(0.5), now), SessionExpiryLevel.blocked);
    });

    test('an expiry already past is blocked, not silent', () {
      expect(sessionExpiryLevel(inDays(-3), now), SessionExpiryLevel.blocked);
    });

    test('the two windows meet with no gap', () {
      // Every instant from expiry back to eight days out must be covered by
      // exactly one level — a gap here is a day the till says nothing.
      for (var hours = 0; hours <= 24 * 8; hours++) {
        final level =
            sessionExpiryLevel(now.add(Duration(hours: hours)), now);
        if (hours <= 24) {
          expect(level, SessionExpiryLevel.blocked, reason: '${hours}h');
        } else if (hours <= 24 * 7) {
          expect(level, SessionExpiryLevel.notice, reason: '${hours}h');
        } else {
          expect(level, SessionExpiryLevel.none, reason: '${hours}h');
        }
      }
    });
  });

  group('the number of days quoted', () {
    test('rounds up, so the deadline is never quoted short', () {
      // 6 days and 12 hours is "7 days". Saying "6" would make the app look
      // wrong to anyone who counts to the date themselves.
      expect(sessionDaysLeft(inDays(6.5), now), 7);
      expect(sessionDaysLeft(inDays(6.01), now), 7);
      expect(sessionDaysLeft(inDays(7), now), 7);
    });

    test('an exact number of days stays that number', () {
      expect(sessionDaysLeft(inDays(3), now), 3);
      expect(sessionDaysLeft(inDays(2), now), 2);
    });

    test('never says zero', () {
      // "Stops working in 0 days" reads as broken. By then the blocking gate
      // owns the screen anyway.
      expect(sessionDaysLeft(inDays(0.2), now), 1);
      expect(sessionDaysLeft(inDays(-5), now), 1);
    });

    test('every day in the notice window gets a sensible number', () {
      for (var hours = 25; hours <= 24 * 7; hours++) {
        final days = sessionDaysLeft(now.add(Duration(hours: hours)), now);
        expect(days, inInclusiveRange(1, 7), reason: '${hours}h');
      }
    });
  });
}

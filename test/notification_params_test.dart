import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/services/daily_summary_service.dart';
import 'package:caisse212/services/notification_params.dart';

/// Verifies the POS side of the notification params contract.
///
/// The mobile app renders push content and feed cards **strictly** from these
/// keys, so a missing or mistyped one is a broken card on someone's phone that
/// nothing here would surface. These tests are the only place that failure is
/// visible before a release.

SessionSummaryReport report({
  double startingBalance = 500,
  double cash = 2800,
  double card = 1200,
  double phone = 0,
  double other = 200,
  double? countedCash,
  double? variance,
  String? countNotes,
  double cashPaidIn = 0,
  double cashPaidOut = 0,
  DateTime? startedAt,
}) =>
    SessionSummaryReport(
      sessionId: 9,
      sessionCode: 'CS-20260629-081400-123',
      cashierId: 42,
      cashierName: 'Sara Amrani',
      startedAt: startedAt ?? DateTime(2026, 6, 29, 8, 14),
      endedAt: DateTime(2026, 6, 29, 16, 45),
      status: 'ended',
      startingBalance: startingBalance,
      totalOrders: 47,
      expectedFromOrders: 4200,
      totalTickets: 52,
      expectedFromTickets: 4200,
      unpaidOrders: 1,
      unpaidAmount: 150,
      paidByCash: cash,
      paidByCard: card,
      paidByPhone: phone,
      paidByOther: other,
      cancelledTickets: 1,
      cancelledAmount: 75,
      countedCash: countedCash,
      variance: variance,
      countNotes: countNotes,
      cashPaidIn: cashPaidIn,
      cashPaidOut: cashPaidOut,
    );

void main() {
  group('POS_SESSION_OPENED', () {
    final p = NotificationParams.sessionOpened(
      terminalName: 'Caisse 1',
      cashierName: 'Sara Amrani',
      cashierId: 42,
      openedAt: DateTime(2026, 6, 29, 8, 14),
      startingBalance: 500,
      currency: 'MAD',
    );

    test('carries every required key', () {
      for (final k in [
        'v',
        'terminalName',
        'cashierName',
        'cashierId',
        'openedAt',
        'startingBalance',
        'currency',
      ]) {
        expect(p.containsKey(k), isTrue, reason: '$k missing');
      }
    });

    test('money is 2 decimal places', () {
      expect(p['startingBalance'], '500.00');
    });

    test('openedAt is local ISO with no Z suffix', () {
      // The mobile displays these verbatim without timezone conversion, so a
      // UTC value would render as the wrong wall-clock time.
      expect(p['openedAt'], '2026-06-29T08:14:00.000');
      expect(p['openedAt']!.endsWith('Z'), isFalse);
    });

    test('schema version is a string', () {
      expect(p['v'], '1');
    });
  });

  group('POS_SESSION_CLOSED', () {
    test('carries all 20 always-present keys', () {
      final p = NotificationParams.sessionClosed(
        terminalName: 'Caisse 1',
        report: report(),
        closedAt: DateTime(2026, 6, 29, 16, 45),
        expectedCash: 3300,
        currency: 'MAD',
      );
      for (final k in [
        'v', 'terminalName', 'cashierName', 'cashierId', 'sessionCode',
        'openedAt', 'closedAt', 'durationMinutes', 'currency',
        'totalAmount', 'totalCash', 'totalCard', 'totalPhone', 'totalOther',
        'ordersCount', 'ticketsCount', 'unpaidAmount', 'cancelledAmount',
        'moneyAtStart', 'moneyAtEnd',
      ]) {
        expect(p.containsKey(k), isTrue, reason: '$k missing');
      }
    });

    test('every value is a String', () {
      final p = NotificationParams.sessionClosed(
        terminalName: 'Caisse 1',
        report: report(countedCash: 3295, variance: -5),
        closedAt: DateTime(2026, 6, 29, 16, 45),
        expectedCash: 3300,
        currency: 'MAD',
      );
      // The map is typed Map<String,String>, but assert on content too — a
      // number slipping through as a non-string is the classic contract break.
      for (final e in p.entries) {
        expect(e.value, isA<String>(), reason: '${e.key} is not a String');
      }
    });

    test('durationMinutes is whole minutes', () {
      final p = NotificationParams.sessionClosed(
        terminalName: 'Caisse 1',
        report: report(),
        closedAt: DateTime(2026, 6, 29, 16, 45),
        expectedCash: 3300,
        currency: 'MAD',
      );
      // 08:14 -> 16:45 is 8h31m = 511 minutes, the doc's own example.
      expect(p['durationMinutes'], '511');
    });

    test('durationMinutes never goes negative on a clock change', () {
      final p = NotificationParams.sessionClosed(
        terminalName: 'Caisse 1',
        report: report(startedAt: DateTime(2026, 6, 29, 17, 0)),
        closedAt: DateTime(2026, 6, 29, 16, 45), // clock moved back mid-shift
        expectedCash: 3300,
        currency: 'MAD',
      );
      expect(p['durationMinutes'], '0',
          reason: 'the card must not render "-0h 15m"');
    });

    test('optional drawer keys are OMITTED when the count was skipped', () {
      final p = NotificationParams.sessionClosed(
        terminalName: 'Caisse 1',
        report: report(), // no countedCash
        closedAt: DateTime(2026, 6, 29, 16, 45),
        expectedCash: 3300,
        currency: 'MAD',
      );
      // The mobile hides the whole Drawer section on absence — sending "" would
      // render a blank block instead.
      expect(p.containsKey('countedCash'), isFalse);
      expect(p.containsKey('variance'), isFalse);
      expect(p.containsKey('countNotes'), isFalse);
    });

    test('drawer keys appear when the cashier counted', () {
      final p = NotificationParams.sessionClosed(
        terminalName: 'Caisse 1',
        report: report(
            countedCash: 3295, variance: -5, countNotes: 'Slight shortage'),
        closedAt: DateTime(2026, 6, 29, 16, 45),
        expectedCash: 3300,
        currency: 'MAD',
      );
      expect(p['countedCash'], '3295.00');
      expect(p['variance'], '-5.00');
      expect(p['countNotes'], 'Slight shortage');
    });

    test('a whitespace-only note is omitted, not sent blank', () {
      final p = NotificationParams.sessionClosed(
        terminalName: 'Caisse 1',
        report: report(countedCash: 3300, variance: 0, countNotes: '   '),
        closedAt: DateTime(2026, 6, 29, 16, 45),
        expectedCash: 3300,
        currency: 'MAD',
      );
      expect(p.containsKey('countNotes'), isFalse);
    });

    test('moneyAtEnd AGREES with variance when cash was paid out', () {
      // The regression this guards. Expected cash includes a 60 payout; the
      // cashier counted exactly right, so variance is 0. If moneyAtEnd were the
      // old `float + cash sales` the card would read
      // "Expected 3300, Counted 3240, Variance 0.00" in green — numbers that
      // visibly contradict each other.
      const expected = 500.0 + 2800.0 - 60.0; // 3240
      final p = NotificationParams.sessionClosed(
        terminalName: 'Caisse 1',
        report: report(countedCash: expected, variance: 0, cashPaidOut: 60),
        closedAt: DateTime(2026, 6, 29, 16, 45),
        expectedCash: expected,
        currency: 'MAD',
      );
      final counted = double.parse(p['countedCash']!);
      final atEnd = double.parse(p['moneyAtEnd']!);
      final variance = double.parse(p['variance']!);
      expect(atEnd, 3240.00);
      expect(counted - atEnd, closeTo(variance, 0.001),
          reason: 'countedCash - moneyAtEnd must equal the variance sent');
    });

    test('totalAmount is the sum of the four method totals', () {
      final p = NotificationParams.sessionClosed(
        terminalName: 'Caisse 1',
        report: report(),
        closedAt: DateTime(2026, 6, 29, 16, 45),
        expectedCash: 3300,
        currency: 'MAD',
      );
      final sum = double.parse(p['totalCash']!) +
          double.parse(p['totalCard']!) +
          double.parse(p['totalPhone']!) +
          double.parse(p['totalOther']!);
      expect(double.parse(p['totalAmount']!), closeTo(sum, 0.001));
      expect(p['totalAmount'], '4200.00');
    });

    test('falls back to a cashier label when the name is unknown', () {
      final r = SessionSummaryReport(
        sessionId: 1,
        sessionCode: 'CS-1',
        cashierId: 7,
        cashierName: null,
        startedAt: DateTime(2026, 6, 29, 8),
        status: 'ended',
        startingBalance: 0,
        totalOrders: 0,
        expectedFromOrders: 0,
        totalTickets: 0,
        expectedFromTickets: 0,
        unpaidOrders: 0,
        unpaidAmount: 0,
        paidByCash: 0,
        paidByCard: 0,
        paidByPhone: 0,
        paidByOther: 0,
      );
      final p = NotificationParams.sessionClosed(
        terminalName: 'Caisse 1',
        report: r,
        closedAt: DateTime(2026, 6, 29, 9),
        expectedCash: 0,
        currency: 'MAD',
      );
      // Never an empty string — the push would read "  opened a session".
      expect(p['cashierName'], 'Cashier #7');
    });
  });

  group('GENERAL', () {
    test('title is required and body omitted when blank', () {
      final p = NotificationParams.general(
        terminalName: 'Caisse 1',
        title: 'Register closed early',
        body: '   ',
      );
      expect(p['title'], 'Register closed early');
      expect(p.containsKey('body'), isFalse);
      expect(p['v'], '1');
      expect(p['terminalName'], 'Caisse 1');
    });

    test('body is kept when present', () {
      final p = NotificationParams.general(
        terminalName: 'Caisse 1',
        title: 'Power cut',
        body: 'Power outage at 16:30.',
      );
      expect(p['body'], 'Power outage at 16:30.');
    });

    test('title is capped at 80 chars and body at 255', () {
      final p = NotificationParams.general(
        terminalName: 'Caisse 1',
        title: 'T' * 200,
        body: 'B' * 400,
      );
      expect(p['title']!.length, NotificationParams.generalTitleMax);
      expect(p['body']!.length, NotificationParams.generalBodyMax);
    });

    test('surrounding whitespace is trimmed', () {
      final p = NotificationParams.general(
        terminalName: 'Caisse 1',
        title: '  Padded  ',
      );
      expect(p['title'], 'Padded');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/core/enums.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/session_service.dart';
import 'package:caisse212/services/z_rules.dart';

/// Pure-arithmetic tests. No database, no widgets — these cover the functions
/// that decide how much money the POS thinks it has, which is the part where a
/// silent regression costs a client real cash rather than just looking wrong.

Ticket _ticket({
  required double amount,
  String method = 'CASH',
  bool isPaid = true,
  bool isCancelled = false,
}) =>
    Ticket(
      id: 0,
      num: 'T-1',
      date: DateTime(2026, 8, 17, 12),
      orderId: 1,
      printCount: 0,
      paymentMethod: method,
      amount: amount,
      isPaid: isPaid,
      isCancelled: isCancelled,
      isSynced: false,
      updatedAt: DateTime(2026, 8, 17, 12),
    );

void main() {
  group('PaymentBreakdown.fromTickets', () {
    test('buckets each method separately and totals them', () {
      final b = PaymentBreakdown.fromTickets([
        _ticket(amount: 100, method: 'CASH'),
        _ticket(amount: 50, method: 'CARD'),
        _ticket(amount: 25, method: 'MOBILE'),
        _ticket(amount: 5, method: 'OTHER'),
      ]);

      expect(b.cash, 100);
      expect(b.card, 50);
      expect(b.mobile, 25);
      expect(b.other, 5);
      expect(b.totalPaid, 180);
      expect(b.paidCount, 4);
    });

    test('cancelled tickets are excluded from takings, counted separately', () {
      final b = PaymentBreakdown.fromTickets([
        _ticket(amount: 100, method: 'CASH'),
        _ticket(amount: 40, method: 'CASH', isCancelled: true),
      ]);

      // The cancelled 40 must NOT inflate cash — this is the line that decides
      // whether a voided sale shows up as money the cashier owes.
      expect(b.cash, 100);
      expect(b.cancelled, 40);
      expect(b.cancelledCount, 1);
      expect(b.totalPaid, 100);
    });

    test('unpaid tickets contribute nothing', () {
      final b = PaymentBreakdown.fromTickets([
        _ticket(amount: 100, method: 'CASH', isPaid: false),
      ]);
      expect(b.totalPaid, 0);
      expect(b.paidCount, 0);
    });

    test('a cancelled ticket is cancelled even if also unpaid', () {
      // Order matters in the implementation: the cancelled check comes first.
      // If that ever flips, a voided unpaid ticket would vanish from the report
      // entirely instead of being reported as cancelled.
      final b = PaymentBreakdown.fromTickets([
        _ticket(amount: 30, isPaid: false, isCancelled: true),
      ]);
      expect(b.cancelledCount, 1);
      expect(b.cancelled, 30);
    });

    test('an unknown payment method lands in other, never in cash', () {
      final b = PaymentBreakdown.fromTickets([
        _ticket(amount: 70, method: 'TRANSFER'),
      ]);
      // Two separate invariants, and both matter:
      //  1. the money must not disappear from takings;
      //  2. it must NOT be counted as physical cash — an unrecognised
      //     electronic method claimed as cash inflates expected drawer cash and
      //     invents a shortage the cashier is blamed for.
      expect(b.totalPaid, 70);
      expect(b.other, 70);
      expect(b.cash, 0);
    });

    test('empty input is all zeroes, not an error', () {
      final b = PaymentBreakdown.fromTickets(const []);
      expect(b.totalPaid, 0);
      expect(b.cancelledCount, 0);
    });
  });

  group('TransactionType.fromString', () {
    test('maps the wire values the tickets actually carry', () {
      expect(TransactionType.fromString('CASH'), TransactionType.cash);
      expect(TransactionType.fromString('CARD'), TransactionType.card);
      expect(TransactionType.fromString('MOBILE'), TransactionType.mobile);
      expect(TransactionType.fromString('OTHER'), TransactionType.other);
    });
  });

  group('zDayKeyOf', () {
    test('with startHour 0 the business day is the calendar day', () {
      expect(zDayKeyOf(DateTime(2026, 8, 17, 0, 1), 0), '2026-08-17');
      expect(zDayKeyOf(DateTime(2026, 8, 17, 23, 59), 0), '2026-08-17');
    });

    test('before the start hour still belongs to the PREVIOUS business day', () {
      // The whole point of the setting: a bar closing at 03:00 with a 05:00 day
      // start is still working yesterday's shift, so its Z must not roll over.
      expect(zDayKeyOf(DateTime(2026, 8, 18, 3, 0), 5), '2026-08-17');
    });

    test('at exactly the start hour the new business day begins', () {
      expect(zDayKeyOf(DateTime(2026, 8, 18, 5, 0), 5), '2026-08-18');
    });

    test('one minute before the start hour is still the old day', () {
      expect(zDayKeyOf(DateTime(2026, 8, 18, 4, 59), 5), '2026-08-17');
    });

    test('midnight with a non-zero start hour belongs to the previous day', () {
      expect(zDayKeyOf(DateTime(2026, 8, 18, 0, 0), 5), '2026-08-17');
    });

    test('month and year boundaries roll correctly', () {
      expect(zDayKeyOf(DateTime(2026, 9, 1, 2, 0), 5), '2026-08-31');
      expect(zDayKeyOf(DateTime(2027, 1, 1, 2, 0), 5), '2026-12-31');
    });

    test('the key is always zero-padded so string comparison works', () {
      // Z labels order by these strings (planZ, ZLabel.compareTo), so
      // '2026-1-5' instead of '2026-01-05' would break the ordering.
      final key = zDayKeyOf(DateTime(2026, 1, 5, 12), 0);
      expect(key, '2026-01-05');
      expect(key.length, 10);
    });

    test('parseZDay returns midnight of the key', () {
      final d = parseZDay(zDayKeyOf(DateTime(2026, 8, 17, 14, 33, 12), 0));
      expect(d, DateTime(2026, 8, 17));
    });
  });

  group('SessionSummary.expectedCashAtEnd', () {
    CashSession session({double moneyAtStart = 100}) => CashSession(
          id: 1,
          code: 'CS-1',
          cashierId: 1,
          startedAt: DateTime(2026, 8, 17, 8),
          moneyAtStart: moneyAtStart,
          status: 'active',
          isSynced: false,
          updatedAt: DateTime(2026, 8, 17, 8),
          isClosingSession: false,
          autoClosed: false,
          zOverride: false,
        );

    test('is float + cash takings when there are no movements', () {
      final s = SessionSummary(
        session: session(moneyAtStart: 100),
        breakdown: const PaymentBreakdown(cash: 250, card: 90),
        ticketCount: 2,
      );
      // Card takings must NOT be expected in the drawer.
      expect(s.expectedCashAtEnd, 350);
    });

    test('a payout REDUCES expected cash', () {
      // The bug this feature exists to fix: without the movements term a
      // petty-cash withdrawal showed up as the cashier being short.
      final s = SessionSummary(
        session: session(moneyAtStart: 100),
        breakdown: const PaymentBreakdown(cash: 250),
        ticketCount: 1,
        cashMovementsNet: -60,
        cashPaidOut: 60,
      );
      expect(s.expectedCashAtEnd, 290);
    });

    test('a float top-up INCREASES expected cash', () {
      final s = SessionSummary(
        session: session(moneyAtStart: 100),
        breakdown: const PaymentBreakdown(cash: 250),
        ticketCount: 1,
        cashMovementsNet: 40,
        cashPaidIn: 40,
      );
      expect(s.expectedCashAtEnd, 390);
    });

    test('equal paid-in and paid-out net to zero but stay visible separately',
        () {
      final s = SessionSummary(
        session: session(moneyAtStart: 100),
        breakdown: const PaymentBreakdown(cash: 250),
        ticketCount: 1,
        cashMovementsNet: 0,
        cashPaidIn: 200,
        cashPaidOut: 200,
      );
      expect(s.expectedCashAtEnd, 350);
      // Both facts survive for the Z report — netting them away would hide a
      // £200 movement in each direction.
      expect(s.cashPaidIn, 200);
      expect(s.cashPaidOut, 200);
      expect(s.details['cashPaidIn'], 200);
      expect(s.details['cashPaidOut'], 200);
    });
  });
}

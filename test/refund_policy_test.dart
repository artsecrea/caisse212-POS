import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/refund_policy.dart';

/// The refund policy is enforced only at the till — the server stores whatever
/// arrives and flags it — so this pure check is where it actually holds.
void main() {
  final today = DateTime(2026, 10, 7);

  RefundAttempt attempt({
    DateTime? saleZDay,
    bool saleZClosed = false,
    double total = 50,
    String method = 'CASH',
    Set<String> paid = const {'CASH'},
    bool nonRefundable = false,
    bool full = true,
  }) =>
      RefundAttempt(
        saleZDay: saleZDay ?? today,
        currentZDay: today,
        saleZClosed: saleZClosed,
        total: total,
        method: method,
        paidMethods: paid,
        includesNonRefundable: nonRefundable,
        isFullRefund: full,
      );

  Set<RefundPolicyFlag> flags(RefundPolicy p, RefundAttempt a) =>
      refundPolicyIssues(p, a).map((i) => i.flag).toSet();

  group('parsing', () {
    test('absent fields are today\'s behaviour', () {
      final p = RefundPolicy.fromJson({});
      expect(p.enabled, isTrue);
      expect(p.windowDays, isNull);
      expect(p.approvalAbove, isNull);
      expect(p.allowedMethods, kRefundMethods);
      expect(p.allowPartial, isTrue);
      expect(p.defaultRestock, isTrue);
      expect(p.closedZNeedsPermission, isFalse,
          reason: 'refunding a closed Z is allowed by default');
    });

    test('the BMS shape round-trips', () {
      final p = RefundPolicy.fromJson({
        'enabled': true,
        'windowDays': 30,
        'closedZNeedsPermission': false,
        'approvalAbove': 500.0,
        'requireReason': true,
        'reasons': [
          {'code': 'DEFECTIVE', 'label': 'Produit défectueux'},
          {'code': 'OTHER', 'label': 'Autre'},
        ],
        'allowedMethods': ['CASH', 'CARD'],
        'methodMustMatchPayment': true,
        'allowPartial': false,
        'defaultRestock': false,
      });
      final again = RefundPolicy.fromJson(p.toJson());
      expect(again.windowDays, 30);
      expect(again.approvalAbove, 500);
      expect(again.reasons.map((r) => r.code), ['DEFECTIVE', 'OTHER']);
      expect(again.reasons.last.isOther, isTrue);
      expect(again.allowedMethods, ['CASH', 'CARD']);
      expect(again.closedZNeedsPermission, isFalse);
      expect(again.defaultRestock, isFalse);
    });

    test('malformed values fall back instead of failing the sync', () {
      final p = RefundPolicy.fromJson({
        'windowDays': -3,
        'approvalAbove': 'lots',
        'allowedMethods': ['BITCOIN'],
        'reasons': [
          {'code': '', 'label': 'nameless'},
          'not a map',
          {'code': 'X'},
        ],
        'enabled': 'yes',
      });
      expect(p.windowDays, isNull);
      expect(p.approvalAbove, isNull);
      expect(p.allowedMethods, kRefundMethods,
          reason: 'no usable method must not leave a refund unpayable');
      expect(p.reasons.single.code, 'X');
      expect(p.reasons.single.label, 'X');
      expect(p.enabled, isTrue);
    });
  });

  group('issues', () {
    test('a plain refund under the defaults raises nothing', () {
      expect(refundPolicyIssues(RefundPolicy.defaults, attempt()), isEmpty);
    });

    test('closed Z is free by default; needs closed-z only when turned on',
        () {
      final a = attempt(saleZClosed: true);
      expect(refundPolicyIssues(RefundPolicy.defaults, a), isEmpty);
      expect(
          refundPolicyIssues(
              const RefundPolicy(closedZNeedsPermission: true), a),
          [const RefundPolicyIssue(RefundPolicyFlag.closedZ, kRefundClosedZPermission)]);
    });

    test('window counts business days, inclusive limit', () {
      const p = RefundPolicy(windowDays: 30, closedZNeedsPermission: false);
      expect(flags(p, attempt(saleZDay: today.subtract(const Duration(days: 30)))),
          isEmpty);
      expect(flags(p, attempt(saleZDay: today.subtract(const Duration(days: 31)))),
          {RefundPolicyFlag.window});
    });

    test('an unknown sale day never counts against the window', () {
      const p = RefundPolicy(windowDays: 0);
      final a = RefundAttempt(
        saleZDay: null,
        currentZDay: today,
        saleZClosed: false,
        total: 1,
        method: 'CASH',
        paidMethods: const {},
        includesNonRefundable: false,
        isFullRefund: true,
      );
      expect(refundPolicyIssues(p, a), isEmpty);
    });

    test('amount: strictly above the threshold, with a centime of slack', () {
      const p = RefundPolicy(approvalAbove: 500);
      expect(flags(p, attempt(total: 500)), isEmpty);
      expect(flags(p, attempt(total: 500.004)), isEmpty);
      expect(flags(p, attempt(total: 500.01)), {RefundPolicyFlag.amount});
    });

    test('method outside the list, or not how it was paid', () {
      const listed = RefundPolicy(allowedMethods: ['CASH']);
      expect(flags(listed, attempt(method: 'CARD')), {RefundPolicyFlag.method});

      const match = RefundPolicy(methodMustMatchPayment: true);
      expect(flags(match, attempt(method: 'CASH', paid: {'CARD'})),
          {RefundPolicyFlag.method});
      expect(flags(match, attempt(method: 'CARD', paid: {'CARD'})), isEmpty);
      expect(flags(match, attempt(method: 'CASH', paid: {})), isEmpty,
          reason: 'no payment rows on this till: not blocked on a guess');
    });

    test('non-refundable products and partial refunds', () {
      expect(flags(RefundPolicy.defaults, attempt(nonRefundable: true)),
          {RefundPolicyFlag.nonRefundable});
      const noPartial = RefundPolicy(allowPartial: false);
      expect(flags(noPartial, attempt(full: false)), {RefundPolicyFlag.partial});
      expect(flags(RefundPolicy.defaults, attempt(full: false)), isEmpty);
    });

    test('everything at once, each with its token', () {
      const p = RefundPolicy(
        closedZNeedsPermission: true,
        windowDays: 7,
        approvalAbove: 100,
        allowedMethods: ['CASH'],
        allowPartial: false,
      );
      final issues = refundPolicyIssues(
          p,
          attempt(
            saleZDay: today.subtract(const Duration(days: 20)),
            saleZClosed: true,
            total: 200,
            method: 'TRANSFER',
            nonRefundable: true,
            full: false,
          ));
      expect(issues.map((i) => i.flag.wire).toList(),
          ['CLOSED_Z', 'WINDOW', 'AMOUNT', 'METHOD', 'NON_REFUNDABLE', 'PARTIAL']);
      expect(permissionsNeeded(issues),
          {kRefundClosedZPermission, kRefundOverridePermission});
    });
  });

  group('approval', () {
    final issues = refundPolicyIssues(
        const RefundPolicy(approvalAbove: 10, closedZNeedsPermission: true),
        attempt(saleZClosed: true, total: 99));

    test('a cashier with neither token needs both from the approver', () {
      final open = unapprovedIssues(issues, (_) => false);
      expect(permissionsNeeded(open),
          {kRefundClosedZPermission, kRefundOverridePermission});
    });

    test('a token the cashier holds is not asked of anyone', () {
      final open =
          unapprovedIssues(issues, (p) => p == kRefundClosedZPermission);
      expect(open.map((i) => i.flag), [RefundPolicyFlag.amount]);
    });

    test('a supervisor holding both needs no approval', () {
      expect(unapprovedIssues(issues, (_) => true), isEmpty);
    });
  });

  test('payment methods map onto refund methods', () {
    expect(refundMethodsForPayments(['CASH', 'CARD', 'MOBILE', 'OTHER', null, '']),
        {'CASH', 'CARD'});
    expect(refundMethodsForPayments(['cheque', 'virement']), {'CHECK', 'TRANSFER'});
  });

  test('business days ignore the hour a day was stamped with', () {
    expect(businessDaysBetween(DateTime(2026, 10, 6, 23, 59), DateTime(2026, 10, 7)), 1);
    expect(businessDaysBetween(DateTime(2026, 10, 7, 5), DateTime(2026, 10, 7, 23)), 0);
  });
}

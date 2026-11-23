/// The business's refund policy, as set in BMS (`GET /pos/refund-policy`),
/// and the pure check of one refund against it.
///
/// The till enforces this BEFORE any money moves; the server never rejects a
/// refund on policy grounds (it is already paid out), it only flags it. So the
/// till is the one place the policy actually holds — which is why the decision
/// is a pure function, tested without a database or a screen.
///
/// See docs/REFUND_POLICY_CONTRACT.md.
library;

const kRefundMethods = ['CASH', 'CARD', 'TRANSFER', 'CHECK'];

class RefundReason {
  final String code;
  final String label;
  const RefundReason(this.code, this.label);

  /// `OTHER` opens a free-text field next to the preset.
  bool get isOther => code.toUpperCase() == 'OTHER';

  Map<String, dynamic> toJson() => {'code': code, 'label': label};
}

class RefundPolicy {
  /// false = refunds are off for this business. Nothing bypasses it.
  final bool enabled;

  /// Max business days from the sale's zDay to today's. null = unlimited.
  final int? windowDays;

  /// Refunding an order whose Z is closed needs `pos:refunds:closed-z`.
  /// Off by default: refunding an earlier sale is the whole point of a
  /// refund (user ruling 2026-10-08); a business may still turn it on.
  final bool closedZNeedsPermission;

  /// A refund TOTAL above this needs `pos:refunds:override`. null = never.
  final double? approvalAbove;

  final bool requireReason;
  final List<RefundReason> reasons;

  /// Methods offered without an override. Never empty after parsing.
  final List<String> allowedMethods;

  /// The method must be one the order was paid with.
  final bool methodMustMatchPayment;

  /// false = only a full refund of what is left on the order.
  final bool allowPartial;

  /// Initial position of the per-line "return to stock" switch.
  final bool defaultRestock;

  const RefundPolicy({
    this.enabled = true,
    this.windowDays,
    this.closedZNeedsPermission = false,
    this.approvalAbove,
    this.requireReason = false,
    this.reasons = const [],
    this.allowedMethods = kRefundMethods,
    this.methodMustMatchPayment = false,
    this.allowPartial = true,
    this.defaultRestock = true,
  });

  /// What the till does with no policy from the server: today's behaviour.
  static const RefundPolicy defaults = RefundPolicy();

  /// Lenient: a malformed field falls back to its default rather than failing
  /// the sync that carried it, and an unknown method is dropped rather than
  /// offered (the refund endpoint would refuse it).
  factory RefundPolicy.fromJson(Map<dynamic, dynamic> json) {
    int? asInt(dynamic v) =>
        v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));
    double? asDouble(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
    bool asBool(dynamic v, bool fallback) => v is bool ? v : fallback;

    final reasons = <RefundReason>[];
    final rawReasons = json['reasons'];
    if (rawReasons is List) {
      for (final r in rawReasons) {
        if (r is Map) {
          final code = r['code']?.toString().trim() ?? '';
          final label = r['label']?.toString().trim() ?? '';
          if (code.isEmpty) continue;
          reasons.add(RefundReason(code, label.isEmpty ? code : label));
        }
      }
    }

    var methods = kRefundMethods;
    final rawMethods = json['allowedMethods'];
    if (rawMethods is List) {
      final parsed = rawMethods
          .map((m) => m.toString().trim().toUpperCase())
          .where(kRefundMethods.contains)
          .toSet()
          .toList();
      // An empty list would leave a refund with no way to pay it out; that is
      // what `enabled: false` is for, so read it as "no restriction".
      if (parsed.isNotEmpty) methods = parsed;
    }

    final window = asInt(json['windowDays']);
    final above = asDouble(json['approvalAbove']);

    return RefundPolicy(
      enabled: asBool(json['enabled'], true),
      windowDays: (window != null && window >= 0) ? window : null,
      closedZNeedsPermission: asBool(json['closedZNeedsPermission'], false),
      approvalAbove: (above != null && above >= 0) ? above : null,
      requireReason: asBool(json['requireReason'], false),
      reasons: reasons,
      allowedMethods: methods,
      methodMustMatchPayment: asBool(json['methodMustMatchPayment'], false),
      allowPartial: asBool(json['allowPartial'], true),
      defaultRestock: asBool(json['defaultRestock'], true),
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'windowDays': windowDays,
        'closedZNeedsPermission': closedZNeedsPermission,
        'approvalAbove': approvalAbove,
        'requireReason': requireReason,
        'reasons': [for (final r in reasons) r.toJson()],
        'allowedMethods': allowedMethods,
        'methodMustMatchPayment': methodMustMatchPayment,
        'allowPartial': allowPartial,
        'defaultRestock': defaultRestock,
      };
}

/// A policy limit a refund goes past. The names are the `policyFlags` values
/// sent with the refund, so the back office sees exactly what was approved.
enum RefundPolicyFlag {
  closedZ('CLOSED_Z'),
  window('WINDOW'),
  amount('AMOUNT'),
  method('METHOD'),
  nonRefundable('NON_REFUNDABLE'),
  partial('PARTIAL');

  final String wire;
  const RefundPolicyFlag(this.wire);
}

/// Permission tokens the policy hands out. Mirrors `Permissions` in
/// permission_service.dart (kept here so this file stays pure).
const kRefundClosedZPermission = 'pos:refunds:closed-z';
const kRefundOverridePermission = 'pos:refunds:override';

class RefundPolicyIssue {
  final RefundPolicyFlag flag;

  /// Token that lets someone go past this limit.
  final String permission;

  const RefundPolicyIssue(this.flag, this.permission);

  @override
  bool operator ==(Object other) =>
      other is RefundPolicyIssue &&
      other.flag == flag &&
      other.permission == permission;

  @override
  int get hashCode => Object.hash(flag, permission);

  @override
  String toString() => '${flag.wire}→$permission';
}

/// Everything about the refund being attempted that the policy looks at.
class RefundAttempt {
  /// Business day the order was sold on, and today's. Either may be unknown
  /// (a legacy row, no Z yet); an unknown day never counts against the window.
  final DateTime? saleZDay;
  final DateTime? currentZDay;

  /// The order's Z is closed (it was sold in an earlier Z).
  final bool saleZClosed;

  final double total;
  final String method;

  /// Methods the order was actually paid with, upper-case.
  final Set<String> paidMethods;

  /// Some selected line is a product marked non-refundable.
  final bool includesNonRefundable;

  /// The refund takes everything that is still refundable on the order.
  final bool isFullRefund;

  const RefundAttempt({
    required this.saleZDay,
    required this.currentZDay,
    required this.saleZClosed,
    required this.total,
    required this.method,
    required this.paidMethods,
    required this.includesNonRefundable,
    required this.isFullRefund,
  });
}

/// Calendar days between two business days (dates only, so the hour a zDay
/// was stamped with never shifts the count).
int businessDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// The limits [attempt] goes past, each with the token that allows it.
/// Empty = a plain refund anyone with `pos:refunds:create` may give.
///
/// Does not look at `enabled` — a switched-off policy is not something to
/// approve, and the caller refuses before getting here.
List<RefundPolicyIssue> refundPolicyIssues(
    RefundPolicy policy, RefundAttempt attempt) {
  final issues = <RefundPolicyIssue>[];

  if (attempt.saleZClosed && policy.closedZNeedsPermission) {
    issues.add(const RefundPolicyIssue(
        RefundPolicyFlag.closedZ, kRefundClosedZPermission));
  }

  final window = policy.windowDays;
  if (window != null &&
      attempt.saleZDay != null &&
      attempt.currentZDay != null &&
      businessDaysBetween(attempt.saleZDay!, attempt.currentZDay!) > window) {
    issues.add(const RefundPolicyIssue(
        RefundPolicyFlag.window, kRefundOverridePermission));
  }

  final above = policy.approvalAbove;
  // A centime of tolerance, like the amount ceiling: 500.004 is not "above 500".
  if (above != null && attempt.total > above + 0.005) {
    issues.add(const RefundPolicyIssue(
        RefundPolicyFlag.amount, kRefundOverridePermission));
  }

  final method = attempt.method.toUpperCase();
  final methodOutsidePolicy = !policy.allowedMethods.contains(method);
  // Only checkable when the payments are known; an order with no payment rows
  // on this till (imported, legacy) must not be blocked on a guess.
  final methodMismatch = policy.methodMustMatchPayment &&
      attempt.paidMethods.isNotEmpty &&
      !attempt.paidMethods.contains(method);
  if (methodOutsidePolicy || methodMismatch) {
    issues.add(const RefundPolicyIssue(
        RefundPolicyFlag.method, kRefundOverridePermission));
  }

  if (attempt.includesNonRefundable) {
    issues.add(const RefundPolicyIssue(
        RefundPolicyFlag.nonRefundable, kRefundOverridePermission));
  }

  if (!policy.allowPartial && !attempt.isFullRefund) {
    issues.add(const RefundPolicyIssue(
        RefundPolicyFlag.partial, kRefundOverridePermission));
  }

  return issues;
}

/// The issues [has] does not cover — what still needs a supervisor.
List<RefundPolicyIssue> unapprovedIssues(
        List<RefundPolicyIssue> issues, bool Function(String permission) has) =>
    [for (final i in issues) if (!has(i.permission)) i];

/// Distinct tokens an approver must hold to clear [issues].
Set<String> permissionsNeeded(List<RefundPolicyIssue> issues) =>
    {for (final i in issues) i.permission};

/// Payment-method labels on this till's tickets, normalised to the refund
/// methods. Anything that is not cash/transfer/check is treated as a card
/// (mobile payment, TPE…), which is how it would be refunded.
Set<String> refundMethodsForPayments(Iterable<String?> paymentMethods) {
  final out = <String>{};
  for (final raw in paymentMethods) {
    final m = (raw ?? '').trim().toUpperCase();
    if (m.isEmpty) continue;
    if (m.contains('CASH') || m == 'ESPECES' || m == 'ESPÈCES') {
      out.add('CASH');
    } else if (m.contains('TRANSFER') || m.contains('VIREMENT')) {
      out.add('TRANSFER');
    } else if (m.contains('CHECK') || m.contains('CHEQUE') || m.contains('CHÈQUE')) {
      out.add('CHECK');
    } else {
      out.add('CARD');
    }
  }
  return out;
}

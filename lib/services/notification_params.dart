import 'cash_report_sections.dart';
import 'daily_summary_service.dart';

/// Builders for `POST /api/pos/notify` `params` payloads.
///
/// Extracted from the widgets that fire them so the contract is testable: the
/// mobile app renders push content and feed cards **strictly** from these keys,
/// so a missing or mistyped one is a broken card on someone's phone rather than
/// an error anyone here would see.
///
/// Contract rules encoded below:
///   * every value is a **String** — numbers and datetimes serialised;
///   * every payload carries `v` (schema version, currently "1");
///   * money is 2 decimal places;
///   * `openedAt` / `closedAt` are **local** ISO 8601 with no `Z` suffix, and
///     the mobile displays them without timezone conversion;
///   * optional keys are **omitted**, never sent as null or "".
class NotificationParams {
  NotificationParams._();

  /// Current schema version. Bump only alongside the mobile renderer — a `v`
  /// the app has no renderer for falls back to a generic card, which is a
  /// regression for every notification of that type.
  static const String version = '1';

  static String _money(double v) => v.toStringAsFixed(2);

  /// Local ISO 8601, no `Z`. `toIso8601String()` on a local `DateTime` already
  /// omits the suffix; `.toUtc()` here would be wrong — the mobile shows these
  /// verbatim, so a UTC value would display as the wrong wall-clock time.
  static String _localIso(DateTime d) => d.toLocal().toIso8601String();

  /// `POS_SESSION_OPENED` — fired right after `startSession` succeeds.
  /// Envelope `refId` is the session id.
  static Map<String, String> sessionOpened({
    required String terminalName,
    required String cashierName,
    required int cashierId,
    required DateTime openedAt,
    required double startingBalance,
    required String currency,
  }) =>
      {
        'v': version,
        'terminalName': terminalName,
        'cashierName': cashierName,
        'cashierId': cashierId.toString(),
        'openedAt': _localIso(openedAt),
        'startingBalance': _money(startingBalance),
        'currency': currency,
      };

  /// `POS_SESSION_CLOSED` — the full Z summary, so the mobile can render a rich
  /// card with no second API call.
  ///
  /// [expectedCash] is what should physically be in the drawer and is sent as
  /// `moneyAtEnd`. It is deliberately NOT `moneyAtStart + totalCash`:
  ///
  /// The mobile shows Expected / Counted / Variance together and colours the
  /// variance by sign. `variance` is `countedCash − expectedCash`, and expected
  /// cash now includes non-sale drawer movements (a petty-cash payout, a float
  /// top-up). Sending the simpler `float + cash sales` as `moneyAtEnd` while
  /// `variance` accounted for movements produced a self-contradictory card: a
  /// 60 payout counted perfectly rendered as "Expected 3300, Counted 3240,
  /// Variance 0.00" in green. Keeping the two in step matters more than matching
  /// the older formula, and it agrees with the session email-report contract,
  /// which defines moneyAtEnd as "open + cash sales − refunds − payouts".
  ///
  /// [sections] (the session's banded report) and [zDay] / [zSeq] add the
  /// detail keys; each is omitted when its source is unavailable.
  static Map<String, String> sessionClosed({
    required String terminalName,
    required SessionSummaryReport report,
    required DateTime closedAt,
    required double expectedCash,
    required String currency,
    CashReportSections? sections,
    String? zDay,
    int? zSeq,
    bool autoClosed = false,
  }) {
    final s = report;
    // Whole minutes, never negative — a clock adjustment mid-shift must not
    // render as "-3h 12m" on the card.
    final minutes = closedAt.difference(s.startedAt).inMinutes;
    return {
      'v': version,
      'terminalName': terminalName,
      'cashierName': s.cashierName ?? 'Cashier #${s.cashierId}',
      'cashierId': s.cashierId.toString(),
      'sessionCode': s.sessionCode,
      'openedAt': _localIso(s.startedAt),
      'closedAt': _localIso(closedAt),
      'durationMinutes': (minutes < 0 ? 0 : minutes).toString(),
      'currency': currency,
      'totalAmount': _money(s.totalPaid),
      'totalCash': _money(s.paidByCash),
      'totalCard': _money(s.paidByCard),
      'totalPhone': _money(s.paidByPhone),
      'totalOther': _money(s.paidByOther),
      'ordersCount': s.totalOrders.toString(),
      'ticketsCount': s.totalTickets.toString(),
      'unpaidAmount': _money(s.unpaidAmount),
      'cancelledAmount': _money(s.cancelledAmount),
      'moneyAtStart': _money(s.startingBalance),
      'moneyAtEnd': _money(expectedCash),
      // Omitted, not nulled: the mobile hides the whole Drawer section when
      // countedCash is absent, so an empty string would render a blank block.
      if (s.countedCash != null) 'countedCash': _money(s.countedCash!),
      if (s.variance != null) 'variance': _money(s.variance!),
      if (s.countNotes != null && s.countNotes!.trim().isNotEmpty)
        'countNotes': s.countNotes!.trim(),
      'cancelledCount': s.cancelledTickets.toString(),
      'unpaidOrders': s.unpaidOrders.toString(),
      'refundsTotal': _money(s.refundsTotal),
      'refundsCash': _money(s.refundsCash),
      'cashPaidIn': _money(s.cashPaidIn),
      'cashPaidOut': _money(s.cashPaidOut),
      'deliveryFees': _money(s.deliveryFees),
      if (zDay != null) 'zDay': zDay,
      if (zSeq != null) 'zSeq': zSeq.toString(),
      if (autoClosed) 'autoClosed': 'true',
      ..._sectionKeys(sections),
    };
  }

  /// Detail keys shared by the session and Z close cards, from the banded
  /// report: sales before and after discounts, tax, covers, and what was
  /// struck off saved orders.
  static Map<String, String> _sectionKeys(CashReportSections? sections) {
    if (sections == null) return const {};
    final g = sections.general;
    final i = sections.indicators;
    final removed = sections.removedItems;
    return {
      'grossSales': _money(g.grossSales),
      'discountsTotal': _money(g.discounts),
      'netSales': _money(i.netSales),
      'vatTotal': _money(sections.vatTotalVat),
      'covers': i.covers.toString(),
      'averageTicket': _money(i.averageTicket),
      'voidedLinesCount': removed.lineCount.toString(),
      'voidedLinesAmount': _money(removed.amount),
    };
  }

  /// `POS_Z_CLOSED` — the day close, summed over every session of the Z.
  /// Envelope `refId` is `"<zDay>#<zSeq>"`.
  static Map<String, String> zClosed({
    required String terminalName,
    required String zDay,
    required int zSeq,
    required String closeMode,
    String? closedByName,
    required DateTime openedAt,
    required DateTime closedAt,
    required DailySummaryReport report,
    required String currency,
    int autoClosedSessions = 0,
    bool overridden = false,
  }) {
    final r = report;
    double? counted;
    double? variance;
    var refunds = 0.0, paidIn = 0.0, paidOut = 0.0;
    for (final s in r.sessions) {
      if (s.countedCash != null) counted = (counted ?? 0) + s.countedCash!;
      if (s.variance != null) variance = (variance ?? 0) + s.variance!;
      refunds += s.refundsTotal;
      paidIn += s.cashPaidIn;
      paidOut += s.cashPaidOut;
    }
    final minutes = closedAt.difference(openedAt).inMinutes;
    final total = r.totalPaidByCash +
        r.totalPaidByCard +
        r.totalPaidByPhone +
        r.totalPaidByOther;
    return {
      'v': version,
      'terminalName': terminalName,
      'zDay': zDay,
      'zSeq': zSeq.toString(),
      'closeMode': closeMode,
      if (closedByName != null && closedByName.trim().isNotEmpty)
        'closedByName': closedByName.trim(),
      'openedAt': _localIso(openedAt),
      'closedAt': _localIso(closedAt),
      'durationMinutes': (minutes < 0 ? 0 : minutes).toString(),
      'currency': currency,
      'sessionsCount': r.totalSessions.toString(),
      if (autoClosedSessions > 0)
        'autoClosedSessions': autoClosedSessions.toString(),
      if (overridden) 'overridden': 'true',
      'totalAmount': _money(total),
      'totalCash': _money(r.totalPaidByCash),
      'totalCard': _money(r.totalPaidByCard),
      'totalPhone': _money(r.totalPaidByPhone),
      'totalOther': _money(r.totalPaidByOther),
      'ordersCount': r.totalOrders.toString(),
      'ticketsCount': r.totalTickets.toString(),
      'unpaidOrders': r.totalUnpaidOrders.toString(),
      'unpaidAmount': _money(r.totalUnpaidAmount),
      'cancelledCount': r.totalCancelledTickets.toString(),
      'cancelledAmount': _money(r.totalCancelledAmount),
      'refundsTotal': _money(refunds),
      'cashPaidIn': _money(paidIn),
      'cashPaidOut': _money(paidOut),
      'deliveryFees': _money(r.totalDeliveryFees),
      if (counted != null) 'countedCash': _money(counted),
      if (variance != null) 'variance': _money(variance),
      ..._sectionKeys(r.sections),
    };
  }

  /// `POS_DISCOUNT_APPLIED` — a remise given on a whole order or on one line.
  /// [scope] is `ORDER` or `LINE`; [percent] only for a percentage discount.
  /// Envelope `refId` is the order code.
  static Map<String, String> discountApplied({
    required String terminalName,
    required String scope,
    required String orderCode,
    required double amount,
    double? percent,
    String? productName,
    double? quantity,
    double? totalBefore,
    double? totalAfter,
    String? reason,
    String? cashierName,
    int? cashierId,
    required DateTime at,
    required String currency,
  }) =>
      {
        'v': version,
        'terminalName': terminalName,
        'scope': scope,
        'orderCode': orderCode,
        'amount': _money(amount),
        if (percent != null && percent > 0) 'percent': _money(percent),
        if (productName != null && productName.isNotEmpty)
          'productName': productName,
        if (quantity != null) 'quantity': _qty(quantity),
        if (totalBefore != null) 'totalBefore': _money(totalBefore),
        if (totalAfter != null) 'totalAfter': _money(totalAfter),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (cashierName != null && cashierName.trim().isNotEmpty)
          'cashierName': cashierName.trim(),
        if (cashierId != null) 'cashierId': cashierId.toString(),
        'at': _localIso(at),
        'currency': currency,
      };

  /// `POS_CANCELLATION` — money taken off after the fact. [kind] is `ORDER`
  /// (a whole order voided), `LINE` (a line removed from a saved order) or
  /// `REFUND`. [afterKitchen] marks food the kitchen had already been told to
  /// make. Envelope `refId` is the order code.
  static Map<String, String> cancellation({
    required String terminalName,
    required String kind,
    required String orderCode,
    required double amount,
    String? productName,
    double? quantity,
    bool afterKitchen = false,
    String? reason,
    String? cashierName,
    int? cashierId,
    required DateTime at,
    required String currency,
  }) =>
      {
        'v': version,
        'terminalName': terminalName,
        'kind': kind,
        'orderCode': orderCode,
        'amount': _money(amount),
        if (productName != null && productName.isNotEmpty)
          'productName': productName,
        if (quantity != null) 'quantity': _qty(quantity),
        if (afterKitchen) 'afterKitchen': 'true',
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        if (cashierName != null && cashierName.trim().isNotEmpty)
          'cashierName': cashierName.trim(),
        if (cashierId != null) 'cashierId': cashierId.toString(),
        'at': _localIso(at),
        'currency': currency,
      };

  /// Whole quantities bare, weighed ones to 3 decimals.
  static String _qty(double q) =>
      q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(3);

  /// Max lengths the contract states for `GENERAL`. Enforced client-side so a
  /// long message is truncated into a usable push rather than silently rejected
  /// or overflowing someone's notification shade.
  static const int generalTitleMax = 80;
  static const int generalBodyMax = 255;

  /// `GENERAL` — free-form message from the terminal to the admin devices.
  static Map<String, String> general({
    required String terminalName,
    required String title,
    String? body,
  }) {
    final t = title.trim();
    final b = body?.trim() ?? '';
    return {
      'v': version,
      'terminalName': terminalName,
      'title': t.length > generalTitleMax ? t.substring(0, generalTitleMax) : t,
      if (b.isNotEmpty)
        'body': b.length > generalBodyMax ? b.substring(0, generalBodyMax) : b,
    };
  }
}

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
  static Map<String, String> sessionClosed({
    required String terminalName,
    required SessionSummaryReport report,
    required DateTime closedAt,
    required double expectedCash,
    required String currency,
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
    };
  }

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

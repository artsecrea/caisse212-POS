import '../../data/database/app_database.dart' show CashSession;
import '../../services/daily_summary_service.dart'
    show
        DailySummaryReport,
        OptionsSummaryReport,
        OrdersListReport,
        ProductsSummaryReport,
        ReportScope,
        StaffGrouping,
        StaffSalesReport;

/// The reports the screens print and show: X and Z, a session's report,
/// products sold, the orders list and staff sales. An interface because,
/// linked to a hub, a till reports what the hub holds: standalone, it adds
/// up its own database (`DailySummaryService`).
abstract interface class ReportQueries {
  /// Get summary report for specific sessions
  Future<DailySummaryReport> generateReport({
    required DateTime startDate,
    required DateTime endDate,
    required List<int> sessionIds,
  });

  /// Produce a single-session report — the data shape used for a Z-report.
  /// Reuses [generateReport] verbatim so totals/payments/unpaid math stays in
  /// one place. The returned [DailySummaryReport] has `sessions.length == 1`,
  /// which is what `printDailySummaryReport` checks to decide whether to print
  /// the variance block at the bottom.
  Future<DailySummaryReport> generateSessionReport(int sessionId);

  /// Get sessions within a date range
  Future<List<CashSession>> getSessionsInRange(DateTime startDate, DateTime endDate);

  /// Quantity/revenue per product for the "products summary" ticket.
  /// Cancelled orders are excluded — they never left the kitchen.
  /// The cash sessions whose business day falls in [from]..[to] (whole days,
  /// inclusive). The business day is the session's Z day, or the day it
  /// started when it has no Z — the same rule the Z report's day list uses.
  /// Open sessions count: a period report is read mid-day as often as not.
  Future<List<int>> sessionIdsForPeriod(DateTime from, DateTime to);

  Future<ProductsSummaryReport> generateProductsSummary({
    required List<int> sessionIds,
    required String scopeLabel,
    List<String> sessionCodes = const [],
    String? zCode,
    int? zNumber,
  });

  /// Per-order list for the "orders done" ticket.
  /// [discountedOnly] narrows the list to orders something came off — the
  /// reductions ticket a manager signs at close. The discount is computed the
  /// same way the banded report computes it, so the two always agree.
  Future<OrdersListReport> generateOrdersList({
    required List<int> sessionIds,
    required String scopeLabel,
    List<String> sessionCodes = const [],
    String? zCode,
    int? zNumber,
    bool discountedOnly = false,
  });

  /// A day's trading split per waiter or per cashier.
  ///
  /// [onlyStaffId] narrows to one person — what "print this waiter's ticket"
  /// asks for. Null gives every one of them, biggest seller first.
  ///
  /// Orders with nobody on the grouping field are kept under one "unassigned"
  /// row rather than dropped: leaving them out would make the ticket's total
  /// disagree with the Z, and a cashier chasing the difference would have
  /// nothing to find.
  Future<StaffSalesReport> generateStaffSales({
    required List<int> sessionIds,
    required String scopeLabel,
    required StaffGrouping grouping,
    int? onlyStaffId,
    String unassignedLabel = 'Unassigned',
    List<String> sessionCodes = const [],
    String? zCode,
    int? zNumber,
  });

  /// The trading day [session] belongs to: every session of its Z when it has
  /// one, otherwise every session whose business day is the day it started.
  /// Open sessions count — this is read mid-day, not at close.
  Future<ReportScope> dayScopeFor(CashSession session);

  /// Modifiers sold across [sessionIds]. Cancelled orders are left out, the
  /// same rule as [generateProductsSummary], so the two tickets agree.
  Future<OptionsSummaryReport> generateOptionsSummary({
    required List<int> sessionIds,
    required String scopeLabel,
    List<String> sessionCodes = const [],
    String? zCode,
    int? zNumber,
  });
}


import 'package:drift/drift.dart';

import 'cash_report_sections.dart';
import 'package:uuid/uuid.dart';
import '../core/enums.dart';
import '../data/database/app_database.dart';
import '../domain/models/order_money.dart';
import '../domain/models/order_money_rows.dart';
import '../utils/user_display.dart';
import 'cash_movement_service.dart';
import 'refund_service.dart';
import 'session_service.dart' show PaymentBreakdown;
import 'z_service.dart' show ZService;

/// Per-waiter rollup inside a session or across a full report.
///
/// "Paid" is the amount actually settled (sum of non-cancelled tickets
/// attributed to this waiter's orders). "Owed" is what's still open
/// (`expected - paid`, never negative). `ordersCount` excludes cancelled
/// orders so the dashboard math lines up with the Settle Waiter flow.
class WaiterBreakdown {
  final int waiterId;
  final String waiterName;
  final int ordersCount;
  final double expected;
  final double paid;
  final double owed;
  final double paidByCash;
  final double paidByCard;
  final double paidByPhone;
  final double paidByOther;

  const WaiterBreakdown({
    required this.waiterId,
    required this.waiterName,
    required this.ordersCount,
    required this.expected,
    required this.paid,
    required this.owed,
    required this.paidByCash,
    required this.paidByCard,
    required this.paidByPhone,
    required this.paidByOther,
  });
}

/// One line of the "orders done" ticket.
class OrdersListEntry {
  final int orderId;
  final String code;
  final DateTime createdAt;
  final String type; // DINE_IN / TAKE_AWAY / DELIVERY
  final String status;
  final String? tableName;
  final String? waiterName;
  final double itemCount;
  final double total;
  final double paid;

  /// Everything that came off this order: per-line discounts, manual
  /// discounts, and the order-level percentage. Drives the reductions ticket.
  final double discount;

  final String paymentMethods; // 'CASH', 'CASH+CARD', '' when unpaid

  const OrdersListEntry({
    required this.orderId,
    required this.code,
    required this.createdAt,
    required this.type,
    required this.status,
    this.tableName,
    this.waiterName,
    required this.itemCount,
    required this.total,
    required this.paid,
    this.discount = 0,
    this.paymentMethods = '',
  });

  bool get isCancelled => status == 'CANCELED';
  double get due {
    final d = total - paid;
    return d < 0 ? 0 : d;
  }
}

/// The "orders done" ticket: every order of a session, or of a whole Z.
class OrdersListReport {
  /// Session code, or Z code when the scope is a whole shift.
  final String scopeLabel;
  final DateTime start;
  final DateTime end;
  final List<String> sessionCodes;
  final String? zCode;
  final int? zNumber;

  /// Oldest first. Cancelled orders are included but flagged, and excluded
  /// from every total below.
  final List<OrdersListEntry> orders;

  /// True when the list was narrowed to orders that carry a discount — the
  /// "reductions" ticket. Changes the heading and shows the discount column.
  final bool discountedOnly;

  const OrdersListReport({
    required this.scopeLabel,
    required this.start,
    required this.end,
    this.sessionCodes = const [],
    this.zCode,
    this.zNumber,
    this.orders = const [],
    this.discountedOnly = false,
  });

  Iterable<OrdersListEntry> get _live => orders.where((o) => !o.isCancelled);
  int get count => _live.length;
  double get total => _live.fold(0.0, (s, o) => s + o.total);
  double get paid => _live.fold(0.0, (s, o) => s + o.paid);
  double get unpaid => _live.fold(0.0, (s, o) => s + o.due);
  int get cancelledCount => orders.length - count;
  double get cancelledTotal =>
      orders.where((o) => o.isCancelled).fold(0.0, (s, o) => s + o.total);
}

/// Who a [StaffSalesReport] is broken down by.
enum StaffGrouping {
  /// `orders.waiterId` — the floor staff who served the table.
  waiter,

  /// `orders.takenBy` — the till operator who rang it up. Falls back to
  /// `createdBy` for rows written before `takenBy` was populated.
  cashier,
}

/// One person's trading on the "sales by staff" ticket.
class StaffSalesEntry {
  final int? staffId;
  final String name;
  final int orderCount;
  final double itemCount;

  /// What the orders came to, after every discount — same formula as the
  /// products summary, so the two tickets reconcile.
  final double net;

  /// Collected against those orders (paid, non-cancelled tickets).
  final double paid;

  const StaffSalesEntry({
    required this.staffId,
    required this.name,
    required this.orderCount,
    required this.itemCount,
    required this.net,
    required this.paid,
  });

  /// Still owed — what a handover or a waiter's settlement turns on.
  double get due {
    final d = net - paid;
    return d < 0 ? 0 : d;
  }
}

/// The "sales by staff" ticket: a day's trading split per waiter or per
/// cashier. Cancelled orders are excluded outright rather than flagged — this
/// ticket answers "what did this person sell", and a void is not a sale.
class StaffSalesReport {
  final String scopeLabel;
  final DateTime start;
  final DateTime end;
  final List<String> sessionCodes;
  final String? zCode;
  final int? zNumber;
  final StaffGrouping grouping;

  /// Set when the report was narrowed to one person, for the ticket header.
  final String? onlyStaffName;

  /// Biggest seller first.
  final List<StaffSalesEntry> rows;

  const StaffSalesReport({
    required this.scopeLabel,
    required this.start,
    required this.end,
    required this.grouping,
    this.sessionCodes = const [],
    this.zCode,
    this.zNumber,
    this.onlyStaffName,
    this.rows = const [],
  });

  int get orderCount => rows.fold(0, (s, r) => s + r.orderCount);
  double get totalNet => rows.fold(0.0, (s, r) => s + r.net);
  double get totalPaid => rows.fold(0.0, (s, r) => s + r.paid);
  double get totalDue => rows.fold(0.0, (s, r) => s + r.due);
}

/// One line of the "products summary" ticket.
class ProductSummaryEntry {
  final int productId;
  final String name;
  final String? categoryName;
  final double quantity;
  final double gross; // before discounts, components included
  final double discount; // unitary + manual, per unit × qty
  final double net; // what actually landed on the order line

  const ProductSummaryEntry({
    required this.productId,
    required this.name,
    this.categoryName,
    required this.quantity,
    required this.gross,
    required this.discount,
    required this.net,
  });
}

/// The "products summary" ticket: what was actually sold, busiest first.
/// How a products report is ordered. Also orders the category sections when
/// the report is grouped: by their total quantity, total amount, or name.
enum ProductsSort { quantity, amount, name }

/// [rows] in [sort] order. Ties fall back to name so the paper is stable.
List<ProductSummaryEntry> sortProductRows(
    List<ProductSummaryEntry> rows, ProductsSort sort) {
  int byName(ProductSummaryEntry a, ProductSummaryEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  final out = [...rows];
  switch (sort) {
    case ProductsSort.quantity:
      out.sort((a, b) {
        final c = b.quantity.compareTo(a.quantity);
        return c != 0 ? c : byName(a, b);
      });
    case ProductsSort.amount:
      out.sort((a, b) {
        final c = b.net.compareTo(a.net);
        return c != 0 ? c : byName(a, b);
      });
    case ProductsSort.name:
      out.sort(byName);
  }
  return out;
}

class ProductsSummaryReport {
  final String scopeLabel;
  final DateTime start;
  final DateTime end;
  final List<String> sessionCodes;
  final String? zCode;
  final int? zNumber;

  /// Sorted by quantity descending.
  final List<ProductSummaryEntry> rows;

  const ProductsSummaryReport({
    required this.scopeLabel,
    required this.start,
    required this.end,
    this.sessionCodes = const [],
    this.zCode,
    this.zNumber,
    this.rows = const [],
  });

  int get distinctProducts => rows.length;
  double get totalQuantity => rows.fold(0.0, (s, r) => s + r.quantity);
  double get totalNet => rows.fold(0.0, (s, r) => s + r.net);
  double get totalDiscount => rows.fold(0.0, (s, r) => s + r.discount);
}

/// One line of the "options sold" ticket: a modifier, how many times it was
/// added, and what it brought in.
class OptionSummaryEntry {
  final int componentId;
  final String name;

  /// The customer took a paid-for default off and was still charged. Kept on
  /// its own line so "SANS fromage" never adds to the count of "fromage".
  final bool removal;
  final double quantity;
  final double amount;

  const OptionSummaryEntry({
    required this.componentId,
    required this.name,
    this.removal = false,
    required this.quantity,
    required this.amount,
  });
}

/// The "options sold" ticket: every modifier taken in the scope, busiest
/// first. Counts are units served — a double cheese on two burgers is four.
class OptionsSummaryReport {
  final String scopeLabel;
  final DateTime start;
  final DateTime end;
  final List<String> sessionCodes;
  final String? zCode;
  final int? zNumber;
  final List<OptionSummaryEntry> rows;

  const OptionsSummaryReport({
    required this.scopeLabel,
    required this.start,
    required this.end,
    this.sessionCodes = const [],
    this.zCode,
    this.zNumber,
    this.rows = const [],
  });

  double get totalQuantity => rows.fold(0.0, (s, r) => s + r.quantity);
  double get totalAmount => rows.fold(0.0, (s, r) => s + r.amount);
}

/// The sessions a "whole day" report covers, and how its tickets are headed.
typedef ReportScope = ({
  List<int> sessionIds,
  String label,
  List<String> sessionCodes,
  String? zCode,
  int? zNumber,
});

/// Model for session summary data
class SessionSummaryReport {
  final int sessionId;
  final String sessionCode;
  final int cashierId;
  final String? cashierName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String status;
  final double startingBalance;
  final double? endingBalance;
  final int totalOrders;
  final double expectedFromOrders;
  final int totalTickets;
  final double expectedFromTickets;
  final int unpaidOrders;
  final double unpaidAmount;
  final double paidByCash;
  final double paidByCard;
  final double paidByPhone;
  final double paidByOther;

  /// Exchange credit spent on new orders (see TransactionType.exchange).
  final double paidByExchange;
  final int cancelledTickets;
  final double cancelledAmount;
  // Z-report fields (null when the session was closed without a cash count).
  final double? countedCash;
  final double? variance;
  final DateTime? countedAt;
  final String? countNotes;
  /// Non-sale cash in and out of the drawer during this session. Kept as two
  /// gross figures rather than a net: a float top-up and a payout of the same
  /// size cancel out but are two separate facts on a Z report.
  final double cashPaidIn;
  final double cashPaidOut;

  /// Refunds in this scope. [refundsTotal] is every method (a report line);
  /// [refundsCash] is the part that physically left the drawer.
  final double refundsTotal;
  final double refundsCash;

  /// Delivery charges on this session's orders, summed as their own figure.
  ///
  /// Deliberately NOT folded into [expectedFromOrders], [expectedFromTickets]
  /// or any payment-method bucket: a delivery fee is not a product sale, and
  /// mixing it in would overstate takings and quietly corrupt the Z. Same
  /// treatment tips get. Orders with no fee recorded contribute nothing.
  final double deliveryFees;

  /// Per-waiter rollup inside this session. Empty when no waiter-attributed
  /// orders exist (cashier-only shifts).
  final List<WaiterBreakdown> waiterBreakdown;

  SessionSummaryReport({
    required this.sessionId,
    required this.sessionCode,
    required this.cashierId,
    this.cashierName,
    required this.startedAt,
    this.endedAt,
    required this.status,
    required this.startingBalance,
    this.endingBalance,
    required this.totalOrders,
    required this.expectedFromOrders,
    required this.totalTickets,
    required this.expectedFromTickets,
    required this.unpaidOrders,
    required this.unpaidAmount,
    required this.paidByCash,
    required this.paidByCard,
    required this.paidByPhone,
    required this.paidByOther,
    this.paidByExchange = 0,
    this.cancelledTickets = 0,
    this.cancelledAmount = 0,
    this.countedCash,
    this.variance,
    this.countedAt,
    this.countNotes,
    this.cashPaidIn = 0,
    this.cashPaidOut = 0,
    this.refundsTotal = 0,
    this.refundsCash = 0,
    this.deliveryFees = 0,
    this.waiterBreakdown = const [],
  });

  double get totalPaid =>
      paidByCash + paidByCard + paidByPhone + paidByOther + paidByExchange;

  /// Signed net effect of the cash movements on the drawer.
  double get cashMovementsNet => cashPaidIn - cashPaidOut;

  /// What should physically be in the drawer. Must stay in step with
  /// `SessionSummary.expectedCashAtEnd`, or the printed variance and the
  /// on-screen variance will disagree.
  /// Must stay in step with `SessionSummary.expectedCashAtEnd` — if these two
  /// disagree, the printed variance and the on-screen variance disagree.
  ///
  /// Cash refunds are subtracted for the reason spelled out there: refunds never
  /// reach `transactions`, so [paidByCash] has not seen them, and the drawer
  /// would read short by exactly the refunded cash at every close.
  double get expectedCash =>
      startingBalance + paidByCash + cashMovementsNet - refundsCash;
}

/// Model for the overall daily summary
class DailySummaryReport {
  final DateTime startDate;
  final DateTime endDate;
  final List<SessionSummaryReport> sessions;
  final int totalSessions;
  final int totalOrders;
  final double totalExpectedFromOrders;
  final int totalTickets;
  final double totalExpectedFromTickets;
  final int totalUnpaidOrders;
  final double totalUnpaidAmount;
  final double totalPaidByCash;
  final double totalPaidByCard;
  final double totalPaidByPhone;
  final double totalPaidByOther;
  final double totalPaidByExchange;
  final double totalStartingBalance;
  final double totalEndingBalance;
  final int totalCancelledTickets;
  final double totalCancelledAmount;

  /// Delivery charges across every session in the report — the day's
  /// delivery-fee line. Excluded from every sales total for the reason
  /// spelled out on [SessionSummaryReport.deliveryFees].
  final double totalDeliveryFees;

  /// Aggregated waiter rollup across every session in the report. Same
  /// waiter appearing in multiple sessions gets a single merged row.
  final List<WaiterBreakdown> totalWaiterBreakdown;

  /// The banded X / Z body — the nine sections the printed report is built
  /// from. Everything above stays for the on-screen previews and the other
  /// report types, which read these figures individually.
  final CashReportSections sections;

  DailySummaryReport({
    required this.startDate,
    required this.endDate,
    required this.sessions,
    required this.totalSessions,
    required this.totalOrders,
    required this.totalExpectedFromOrders,
    required this.totalTickets,
    required this.totalExpectedFromTickets,
    required this.totalUnpaidOrders,
    required this.totalUnpaidAmount,
    required this.totalPaidByCash,
    required this.totalPaidByCard,
    required this.totalPaidByPhone,
    required this.totalPaidByOther,
    this.totalPaidByExchange = 0,
    required this.totalStartingBalance,
    required this.totalEndingBalance,
    this.totalCancelledTickets = 0,
    this.totalCancelledAmount = 0,
    this.totalDeliveryFees = 0,
    this.totalWaiterBreakdown = const [],
    this.sections = CashReportSections.empty,
  });

  double get totalPaid =>
      totalPaidByCash +
      totalPaidByCard +
      totalPaidByPhone +
      totalPaidByOther +
      totalPaidByExchange;
}

class DailySummaryService {
  final AppDatabase _db;

  DailySummaryService(this._db);

  /// Get sessions within a date range
  Future<List<CashSession>> getSessionsInRange(DateTime startDate, DateTime endDate) async {
    final start = DateTime(startDate.year, startDate.month, startDate.day, 0, 0, 0);
    final end = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);

    return await (_db.select(_db.cashSessions)
      ..where((s) => s.startedAt.isBiggerOrEqualValue(start) & s.startedAt.isSmallerOrEqualValue(end))
      ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]))
        .get();
  }

  /// Get summary report for specific sessions
  Future<DailySummaryReport> generateReport({
    required DateTime startDate,
    required DateTime endDate,
    required List<int> sessionIds,
  }) async {
    final sessions = <SessionSummaryReport>[];

    for (final sessionId in sessionIds) {
      final sessionReport = await _getSessionSummary(sessionId);
      if (sessionReport != null) {
        sessions.add(sessionReport);
      }
    }

    // Calculate totals
    int totalOrders = 0;
    double totalExpectedFromOrders = 0;
    int totalTickets = 0;
    double totalExpectedFromTickets = 0;
    int totalUnpaidOrders = 0;
    double totalUnpaidAmount = 0;
    double totalPaidByCash = 0;
    double totalPaidByCard = 0;
    double totalPaidByPhone = 0;
    double totalPaidByOther = 0;
    double totalPaidByExchange = 0;
    double totalStartingBalance = 0;
    double totalEndingBalance = 0;
    int totalCancelledTickets = 0;
    double totalCancelledAmount = 0;
    double totalDeliveryFees = 0;

    // Aggregate per-waiter rollup across sessions — same waiter appearing
    // in multiple sessions collapses into one row with summed totals.
    final waiterAcc = <int, _WaiterAcc>{};
    final waiterNameById = <int, String>{};

    for (final session in sessions) {
      totalOrders += session.totalOrders;
      totalExpectedFromOrders += session.expectedFromOrders;
      totalTickets += session.totalTickets;
      totalExpectedFromTickets += session.expectedFromTickets;
      totalUnpaidOrders += session.unpaidOrders;
      totalUnpaidAmount += session.unpaidAmount;
      totalPaidByCash += session.paidByCash;
      totalPaidByCard += session.paidByCard;
      totalPaidByPhone += session.paidByPhone;
      totalPaidByOther += session.paidByOther;
      totalPaidByExchange += session.paidByExchange;
      totalStartingBalance += session.startingBalance;
      totalEndingBalance += session.endingBalance ?? 0;
      totalCancelledTickets += session.cancelledTickets;
      totalCancelledAmount += session.cancelledAmount;
      totalDeliveryFees += session.deliveryFees;

      for (final w in session.waiterBreakdown) {
        final acc = waiterAcc.putIfAbsent(w.waiterId, () => _WaiterAcc());
        acc.ordersCount += w.ordersCount;
        acc.expected += w.expected;
        acc.paid += w.paid;
        acc.paidByCash += w.paidByCash;
        acc.paidByCard += w.paidByCard;
        acc.paidByPhone += w.paidByPhone;
        acc.paidByOther += w.paidByOther;
        waiterNameById[w.waiterId] = w.waiterName;
      }
    }

    final totalWaiterBreakdown = waiterAcc.entries.map((e) {
      final acc = e.value;
      final owed = acc.expected - acc.paid;
      return WaiterBreakdown(
        waiterId: e.key,
        waiterName: waiterNameById[e.key] ?? 'Waiter #${e.key}',
        ordersCount: acc.ordersCount,
        expected: acc.expected,
        paid: acc.paid,
        owed: owed > 0 ? owed : 0,
        paidByCash: acc.paidByCash,
        paidByCard: acc.paidByCard,
        paidByPhone: acc.paidByPhone,
        paidByOther: acc.paidByOther,
      );
    }).toList()
      ..sort((a, b) => b.expected.compareTo(a.expected));

    return DailySummaryReport(
      startDate: startDate,
      endDate: endDate,
      sessions: sessions,
      totalSessions: sessions.length,
      totalOrders: totalOrders,
      totalExpectedFromOrders: totalExpectedFromOrders,
      totalTickets: totalTickets,
      totalExpectedFromTickets: totalExpectedFromTickets,
      totalUnpaidOrders: totalUnpaidOrders,
      totalUnpaidAmount: totalUnpaidAmount,
      totalPaidByCash: totalPaidByCash,
      totalPaidByCard: totalPaidByCard,
      totalPaidByPhone: totalPaidByPhone,
      totalPaidByOther: totalPaidByOther,
      totalPaidByExchange: totalPaidByExchange,
      totalStartingBalance: totalStartingBalance,
      totalEndingBalance: totalEndingBalance,
      totalCancelledTickets: totalCancelledTickets,
      totalCancelledAmount: totalCancelledAmount,
      totalDeliveryFees: totalDeliveryFees,
      totalWaiterBreakdown: totalWaiterBreakdown,
      sections: await CashReportBuilder(_db).build(sessionIds: sessionIds),
    );
  }

  Future<SessionSummaryReport?> _getSessionSummary(int sessionId) async {
    // Get session
    final session = await (_db.select(_db.cashSessions)
      ..where((s) => s.id.equals(sessionId)))
        .getSingleOrNull();

    if (session == null) return null;

    // Get cashier name
    final user = await (_db.select(_db.users)
      ..where((u) => u.id.equals(session.cashierId)))
        .getSingleOrNull();

    // Get tickets for this session (exclude cancelled tickets)
    final allTickets = await (_db.select(_db.tickets)
      ..where((t) => t.sessionId.equals(sessionId)))
        .get();

    // Filter out cancelled tickets for calculations
    final tickets = allTickets.where((t) => !t.isCancelled).toList();
    final cancelledTickets = allTickets.where((t) => t.isCancelled).toList();

    // Non-sale drawer movements for this session, so the printed expected-cash
    // and variance match what the close dialog showed on screen.
    final cashTotals =
        await CashMovementService(_db).totalsForSessions([sessionId]);

    // Refunds, for the same reason: the printed figure must equal the screen.
    final refundSvc = RefundService(_db);
    final refundsTotal = await refundSvc.totalForSession(sessionId);
    final refundsCash = await refundSvc.cashTotalForSession(sessionId);

    // Get unique order IDs from tickets
    final orderIds = tickets.map((t) => t.orderId).toSet().toList();

    // Get orders (excluding cancelled orders)
    List<Order> orders = [];
    for (final orderId in orderIds) {
      final order = await (_db.select(_db.orders)
        ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();
      if (order != null && order.status != 'CANCELED') {
        orders.add(order);
      }
    }

    // Calculate order totals using the same logic as _buildOrderFullDetails
    int totalOrders = orders.length;
    double expectedFromOrders = 0;
    int unpaidOrders = 0;
    double unpaidAmount = 0;
    // Own line, never added to expectedFromOrders — see [deliveryFees].
    double deliveryFees = 0;

    // Per-waiter rollup accumulator. Key = waiterId. An order with no
    // waiterId (cashier rang it up directly) is excluded.
    final waiterAcc = <int, _WaiterAcc>{};

    for (final order in orders) {
      // Get order products to calculate order total
      final orderProducts = await (_db.select(_db.orderProducts)
        ..where((op) => op.orderId.equals(order.id)))
          .get();

      double linesNet = 0.0;

      for (final product in orderProducts) {
        // Get components for this order product
        final orderComponents = await (_db.select(_db.orderProductComponents)
          ..where((tbl) => tbl.orderProductId.equals(product.id)))
            .get();

        linesNet += product
            .amounts(componentsPerUnit: componentsPerUnitOf(orderComponents))
            .net;
      }

      final orderTotal = applyOrderDiscount(linesNet, order.discountPercentage);

      expectedFromOrders += orderTotal;
      deliveryFees += order.deliveryFee ?? 0.0;

      // Check if order is fully paid by checking its tickets
      final orderTickets = tickets.where((t) => t.orderId == order.id).toList();
      final ticketTotal = orderTickets.fold<double>(0, (sum, t) => sum + t.amount);

      if (ticketTotal < orderTotal) {
        unpaidOrders++;
        unpaidAmount += (orderTotal - ticketTotal);
      }

      // Per-waiter rollup. Walk each ticket on this order so the per-method
      // split (cash/card/phone/other) attributes correctly, even when an
      // order has mixed-method partial tickets.
      final wId = order.waiterId;
      if (wId != null) {
        final acc = waiterAcc.putIfAbsent(wId, () => _WaiterAcc());
        acc.ordersCount++;
        acc.expected += orderTotal;
        for (final t in orderTickets) {
          if (!t.isPaid) continue;
          acc.paid += t.amount;
          switch (TransactionType.fromString(t.paymentMethod)) {
            case TransactionType.cash:
              acc.paidByCash += t.amount;
              break;
            case TransactionType.card:
              acc.paidByCard += t.amount;
              break;
            case TransactionType.mobile:
              acc.paidByPhone += t.amount;
              break;
            case TransactionType.other:
            case TransactionType.exchange:
              acc.paidByOther += t.amount;
              break;
          }
        }
      }
    }

    // Calculate ticket totals by payment method (excluding cancelled).
    // Single source of truth with the session-close drawer figure: buckets
    // paid, non-cancelled tickets via the TransactionType enum. `paidByPhone`
    // carries mobile-money takings (the enum's MOBILE method).
    final breakdown = PaymentBreakdown.fromTickets(tickets);
    final double paidByCash = breakdown.cash;
    final double paidByCard = breakdown.card;
    final double paidByPhone = breakdown.mobile;
    final double paidByOther = breakdown.other;
    double expectedFromTickets = 0;
    for (final ticket in tickets) {
      expectedFromTickets += ticket.amount;
    }

    // Calculate cancelled ticket totals
    final cancelledTicketCount = cancelledTickets.length;
    final cancelledAmount = cancelledTickets.fold<double>(0, (sum, t) => sum + t.amount);

    // Resolve waiter names + finalize the breakdown. Sorted by descending
    // expected so the busiest waiters land at the top of the printed
    // section.
    final waiterIds = waiterAcc.keys.toList();
    final waiterRows = await (_db.select(_db.waiters)
          ..where((w) => w.id.isIn(waiterIds)))
        .get();
    final waiterNameById = {
      for (final w in waiterRows)
        w.id: '${w.firstName} ${w.lastName ?? ''}'.trim(),
    };
    final waiterBreakdown = waiterAcc.entries.map((e) {
      final acc = e.value;
      final owed = acc.expected - acc.paid;
      return WaiterBreakdown(
        waiterId: e.key,
        waiterName: waiterNameById[e.key] ?? 'Waiter #${e.key}',
        ordersCount: acc.ordersCount,
        expected: acc.expected,
        paid: acc.paid,
        owed: owed > 0 ? owed : 0,
        paidByCash: acc.paidByCash,
        paidByCard: acc.paidByCard,
        paidByPhone: acc.paidByPhone,
        paidByOther: acc.paidByOther,
      );
    }).toList()
      ..sort((a, b) => b.expected.compareTo(a.expected));

    return SessionSummaryReport(
      sessionId: session.id,
      sessionCode: session.code,
      cashierId: session.cashierId,
      cashierName: user?.displayLabel,
      startedAt: session.startedAt,
      endedAt: session.endedAt,
      status: session.status,
      startingBalance: session.moneyAtStart,
      endingBalance: session.moneyAtEnd,
      totalOrders: totalOrders,
      expectedFromOrders: expectedFromOrders,
      totalTickets: tickets.length,
      expectedFromTickets: expectedFromTickets,
      unpaidOrders: unpaidOrders,
      unpaidAmount: unpaidAmount,
      paidByCash: paidByCash,
      paidByCard: paidByCard,
      paidByPhone: paidByPhone,
      paidByOther: paidByOther,
      paidByExchange: breakdown.exchange,
      cancelledTickets: cancelledTicketCount,
      cancelledAmount: cancelledAmount,
      cashPaidIn: cashTotals.paidIn,
      cashPaidOut: cashTotals.paidOut,
      refundsTotal: refundsTotal,
      refundsCash: refundsCash,
      deliveryFees: deliveryFees,
      countedCash: session.countedCash,
      variance: session.variance,
      countedAt: session.countedAt,
      countNotes: session.countNotes,
      waiterBreakdown: waiterBreakdown,
    );
  }

  /// Produce a single-session report — the data shape used for a Z-report.
  /// Reuses [generateReport] verbatim so totals/payments/unpaid math stays in
  /// one place. The returned [DailySummaryReport] has `sessions.length == 1`,
  /// which is what `printDailySummaryReport` checks to decide whether to print
  /// the variance block at the bottom.
  Future<DailySummaryReport> generateSessionReport(int sessionId) async {
    final session = await (_db.select(_db.cashSessions)
          ..where((s) => s.id.equals(sessionId)))
        .getSingleOrNull();
    if (session == null) {
      throw Exception('Session $sessionId not found');
    }
    final start = session.startedAt;
    final end = session.endedAt ?? DateTime.now();
    return generateReport(
      startDate: start,
      endDate: end,
      sessionIds: [sessionId],
    );
  }

  /// Aggregate every session whose z-day equals [zDay] (midnight of a
  /// session's opening day) into one report — the whole-day rollup used for
  /// the "Z-DAY TOTAL" extension printed on session close when Z tracking is
  /// off. Selection matches `zDayForSession`: a session belongs to the z-day
  /// when its `startedAt` falls on that calendar day. Returns a report whose
  /// [DailySummaryReport.totalSessions] spans the day (may be 1).
  Future<DailySummaryReport> generateZDayReport(DateTime zDay) async {
    final sessions = await getSessionsInRange(zDay, zDay);
    return generateReport(
      startDate: zDay,
      endDate: zDay,
      sessionIds: sessions.map((s) => s.id).toList(),
    );
  }

  // ── Orders list / products summary (extra close-time tickets) ────────────

  /// Session ids belonging to [zId] — same selection as
  /// [ZService.sessionsForZ], inlined so this service stays dependency-free.
  Future<List<int>> _sessionIdsForZ(int zId) async {
    final rows = await (_db.select(_db.cashSessions)
          ..where((s) => s.zId.equals(zId))
          ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
        .get();
    return rows.map((s) => s.id).toList();
  }

  /// Resolves the Z's printed name + sequence for the ticket header.
  Future<({String? code, int? number, List<int> sessionIds})> _zScope(
      int zId) async {
    final z = await (_db.select(_db.zs)..where((t) => t.id.equals(zId)))
        .getSingleOrNull();
    return (
      code: z == null ? null : ZService.displayName(z),
      number: z?.zSeq,
      sessionIds: await _sessionIdsForZ(zId),
    );
  }

  /// Everything both extra reports need, fetched in a fixed number of batched
  /// queries regardless of how many orders the scope holds. A Z spanning a
  /// full trading day can carry thousands of rows; the per-order loop used by
  /// [_getSessionSummary] would stall the close dialog here.
  Future<_ScopeData> _loadScope(List<int> sessionIds) async {
    if (sessionIds.isEmpty) return _ScopeData.empty();

    // Orders: union of the session-stamped rows and the ticket-derived ones,
    // so fully-unpaid orders (which have no ticket) and legacy rows with a
    // null sessionId both make it in.
    final tickets = await (_db.select(_db.tickets)
          ..where((t) => t.sessionId.isIn(sessionIds)))
        .get();
    final bySession = await (_db.select(_db.orders)
          ..where((o) => o.sessionId.isIn(sessionIds)))
        .get();
    final ticketOrderIds = tickets.map((t) => t.orderId).toSet();
    final missing =
        ticketOrderIds.difference(bySession.map((o) => o.id).toSet()).toList();
    final extra = missing.isEmpty
        ? <Order>[]
        : await (_db.select(_db.orders)..where((o) => o.id.isIn(missing))).get();
    final orders = [...bySession, ...extra]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (orders.isEmpty) return _ScopeData.empty();

    final orderIds = orders.map((o) => o.id).toList();
    final orderProducts = await (_db.select(_db.orderProducts)
          ..where((op) => op.orderId.isIn(orderIds)))
        .get();
    final opIds = orderProducts.map((op) => op.id).toList();
    final components = opIds.isEmpty
        ? <OrderProductComponent>[]
        : await (_db.select(_db.orderProductComponents)
              ..where((c) => c.orderProductId.isIn(opIds)))
            .get();

    // Component cost per order-product line.
    final compCostByOpId = <int, double>{};
    for (final c in components) {
      compCostByOpId[c.orderProductId] =
          (compCostByOpId[c.orderProductId] ?? 0.0) + c.price * c.quantity;
    }

    final tableIds = orders.map((o) => o.tableId).whereType<int>().toSet();
    final waiterIds = orders.map((o) => o.waiterId).whereType<int>().toSet();
    final tables = tableIds.isEmpty
        ? <AreaTable>[]
        : await (_db.select(_db.areaTables)
              ..where((t) => t.id.isIn(tableIds.toList())))
            .get();
    final waiters = waiterIds.isEmpty
        ? <Waiter>[]
        : await (_db.select(_db.waiters)
              ..where((w) => w.id.isIn(waiterIds.toList())))
            .get();

    return _ScopeData(
      orders: orders,
      orderProducts: orderProducts,
      tickets: tickets,
      components: components,
      compCostByOpId: compCostByOpId,
      tableNameById: {for (final t in tables) t.id: t.name},
      waiterNameById: {
        for (final w in waiters)
          w.id: '${w.firstName} ${w.lastName ?? ''}'.trim()
      },
    );
  }

  /// Gross line total for one order-product, components included.
  ///
  /// `unitaryDiscount` is already baked into `unitaryPrice`, so only
  /// `manualDiscount` is subtracted here — the same formula the dashboard uses
  /// (`dashboard_screen.dart`), and algebraically identical to the TVA-split
  /// arithmetic in [_getSessionSummary]. Keeping all three in step is what lets
  /// the printed summary reconcile with the Z report and the dashboard.
  static double _opLineTotal(OrderProduct op, double compCost) =>
      op.amounts(componentsPerUnit: compCost).net;

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
  }) async {
    final data = await _loadScope(sessionIds);
    final opsByOrder = <int, List<OrderProduct>>{};
    for (final op in data.orderProducts) {
      opsByOrder.putIfAbsent(op.orderId, () => []).add(op);
    }
    final ticketsByOrder = <int, List<Ticket>>{};
    for (final t in data.tickets) {
      ticketsByOrder.putIfAbsent(t.orderId, () => []).add(t);
    }

    final entries = <OrdersListEntry>[];
    for (final o in data.orders) {
      final ops = opsByOrder[o.id] ?? const <OrderProduct>[];
      var lineTotal = 0.0;
      var itemCount = 0.0;
      var lineDiscount = 0.0;
      for (final op in ops) {
        if (op.state == 'CANCELED') continue;
        lineTotal += _opLineTotal(op, data.compCostByOpId[op.id] ?? 0.0);
        itemCount += op.quantity;
        lineDiscount += (op.unitaryDiscount + op.manualDiscount) * op.quantity;
      }
      final total = applyOrderDiscount(lineTotal, o.discountPercentage);
      final orderLevelDiscount = lineTotal - total;
      final discount = lineDiscount + orderLevelDiscount;
      if (discountedOnly && discount.abs() <= 0.005) continue;

      final ts = ticketsByOrder[o.id] ?? const <Ticket>[];
      final live = ts.where((t) => !t.isCancelled).toList();
      final paid = live
          .where((t) => t.isPaid)
          .fold<double>(0, (s, t) => s + t.amount);
      final methods = live
          .where((t) => t.isPaid)
          .map((t) => t.paymentMethod)
          .toSet()
          .toList()
        ..sort();

      entries.add(OrdersListEntry(
        orderId: o.id,
        code: o.code,
        createdAt: o.createdAt,
        type: o.type,
        status: o.status,
        tableName: o.tableId == null ? null : data.tableNameById[o.tableId],
        waiterName: o.waiterId == null ? null : data.waiterNameById[o.waiterId],
        itemCount: itemCount,
        total: total,
        paid: paid,
        discount: discount,
        paymentMethods: methods.join('+'),
      ));
    }

    final start = data.orders.isEmpty
        ? DateTime.now()
        : data.orders.first.createdAt;
    final end =
        data.orders.isEmpty ? DateTime.now() : data.orders.last.createdAt;

    return OrdersListReport(
      scopeLabel: scopeLabel,
      start: start,
      end: end,
      sessionCodes: sessionCodes,
      zCode: zCode,
      zNumber: zNumber,
      orders: entries,
      discountedOnly: discountedOnly,
    );
  }

  /// Quantity/revenue per product for the "products summary" ticket.
  /// Cancelled orders are excluded — they never left the kitchen.
  /// The cash sessions whose business day falls in [from]..[to] (whole days,
  /// inclusive). The business day is the session's Z day, or the day it
  /// started when it has no Z — the same rule the Z report's day list uses.
  /// Open sessions count: a period report is read mid-day as often as not.
  Future<List<int>> sessionIdsForPeriod(DateTime from, DateTime to) async {
    final first = DateTime(from.year, from.month, from.day);
    final last = DateTime(to.year, to.month, to.day);
    final sessions = await _db.select(_db.cashSessions).get();
    final zs = await _db.select(_db.zs).get();
    final zById = {for (final z in zs) z.id: z};
    return [
      for (final s in sessions)
        if (() {
          final z = s.zId == null ? null : zById[s.zId];
          final d = z != null
              ? ZService.zDayOf(z)
              : DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day);
          return !d.isBefore(first) && !d.isAfter(last);
        }())
          s.id,
    ];
  }

  Future<ProductsSummaryReport> generateProductsSummary({
    required List<int> sessionIds,
    required String scopeLabel,
    List<String> sessionCodes = const [],
    String? zCode,
    int? zNumber,
  }) async {
    final data = await _loadScope(sessionIds);
    final liveOrderIds = data.orders
        .where((o) => o.status != 'CANCELED')
        .map((o) => o.id)
        .toSet();

    final acc = <int, _ProductAcc>{};
    for (final op in data.orderProducts) {
      if (!liveOrderIds.contains(op.orderId)) continue;
      if (op.state == 'CANCELED') continue;
      final compCost = data.compCostByOpId[op.id] ?? 0.0;
      final a = acc.putIfAbsent(op.productId, () => _ProductAcc());
      a.quantity += op.quantity;
      // `unitaryPrice` already has the catalogue discount off; adding it back
      // is what makes gross - discount = net on the printed row.
      final money = op.amounts(componentsPerUnit: compCost);
      a.gross += money.gross;
      a.discount += money.lineDiscount;
      a.net += money.net;
    }

    // Names + categories in two batched lookups.
    final productIds = acc.keys.toList();
    final products = productIds.isEmpty
        ? <Product>[]
        : await (_db.select(_db.products)..where((p) => p.id.isIn(productIds)))
            .get();
    final categoryIds =
        products.map((p) => p.categoryId).whereType<int>().toSet().toList();
    final categories = categoryIds.isEmpty
        ? <Category>[]
        : await (_db.select(_db.categories)..where((c) => c.id.isIn(categoryIds)))
            .get();
    final categoryNameById = {for (final c in categories) c.id: c.name};
    final productById = {for (final p in products) p.id: p};

    final rows = <ProductSummaryEntry>[];
    acc.forEach((productId, a) {
      final p = productById[productId];
      final catId = p?.categoryId;
      rows.add(ProductSummaryEntry(
        productId: productId,
        name: p?.name ?? '#$productId',
        categoryName: catId == null ? null : categoryNameById[catId],
        quantity: a.quantity,
        gross: a.gross,
        discount: a.discount,
        net: a.net,
      ));
    });
    rows.sort((x, y) => y.quantity.compareTo(x.quantity));

    final start = data.orders.isEmpty
        ? DateTime.now()
        : data.orders.first.createdAt;
    final end =
        data.orders.isEmpty ? DateTime.now() : data.orders.last.createdAt;

    return ProductsSummaryReport(
      scopeLabel: scopeLabel,
      start: start,
      end: end,
      sessionCodes: sessionCodes,
      zCode: zCode,
      zNumber: zNumber,
      rows: rows,
    );
  }

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
  }) async {
    final data = await _loadScope(sessionIds);

    final opsByOrder = <int, List<OrderProduct>>{};
    for (final op in data.orderProducts) {
      opsByOrder.putIfAbsent(op.orderId, () => []).add(op);
    }
    final paidByOrder = <int, double>{};
    for (final t in data.tickets) {
      if (!t.isPaid || t.isCancelled) continue;
      paidByOrder[t.orderId] = (paidByOrder[t.orderId] ?? 0.0) + t.amount;
    }

    // Cashier names need a users lookup; waiter names are already resolved by
    // the scope load.
    var nameById = data.waiterNameById;
    if (grouping == StaffGrouping.cashier) {
      final ids = <int>{
        for (final o in data.orders)
          if ((o.takenBy ?? o.createdBy) != null) (o.takenBy ?? o.createdBy)!,
      };
      final users = ids.isEmpty
          ? <User>[]
          : await (_db.select(_db.users)..where((u) => u.id.isIn(ids.toList())))
              .get();
      nameById = {
        for (final u in users)
          u.id: '${u.firstName} ${u.lastName}'.trim().isEmpty
              ? u.username
              : '${u.firstName} ${u.lastName}'.trim()
      };
    }

    final buckets = <int?, StaffSalesEntry>{};
    for (final o in data.orders) {
      if (o.status == 'CANCELED') continue;
      final staffId = grouping == StaffGrouping.waiter
          ? o.waiterId
          : (o.takenBy ?? o.createdBy);
      if (onlyStaffId != null && staffId != onlyStaffId) continue;

      var net = 0.0;
      var units = 0.0;
      for (final op in opsByOrder[o.id] ?? const <OrderProduct>[]) {
        if (op.state == 'CANCELED') continue;
        net += _opLineTotal(op, data.compCostByOpId[op.id] ?? 0.0);
        units += op.quantity;
      }
      net = applyOrderDiscount(net, o.discountPercentage);

      final prev = buckets[staffId];
      buckets[staffId] = StaffSalesEntry(
        staffId: staffId,
        name: staffId == null
            ? unassignedLabel
            : (nameById[staffId] ?? '#$staffId'),
        orderCount: (prev?.orderCount ?? 0) + 1,
        itemCount: (prev?.itemCount ?? 0) + units,
        net: (prev?.net ?? 0) + net,
        paid: (prev?.paid ?? 0) + (paidByOrder[o.id] ?? 0.0),
      );
    }

    final rows = buckets.values.toList()
      ..sort((a, b) => b.net.compareTo(a.net));

    return StaffSalesReport(
      scopeLabel: scopeLabel,
      start: data.orders.isEmpty ? DateTime.now() : data.orders.first.createdAt,
      end: data.orders.isEmpty ? DateTime.now() : data.orders.last.createdAt,
      grouping: grouping,
      sessionCodes: sessionCodes,
      zCode: zCode,
      zNumber: zNumber,
      onlyStaffName: onlyStaffId == null ? null : rows.firstOrNull?.name,
      rows: rows,
    );
  }



  // Scope wrappers — session close prints the session, day close prints the Z.

  Future<OrdersListReport> ordersListForSession(int sessionId) async {
    final s = await (_db.select(_db.cashSessions)
          ..where((t) => t.id.equals(sessionId)))
        .getSingleOrNull();
    return generateOrdersList(
      sessionIds: [sessionId],
      scopeLabel: s?.code ?? '#$sessionId',
      sessionCodes: s == null ? const [] : [s.code],
    );
  }

  Future<OrdersListReport> ordersListForZ(int zId) async {
    final scope = await _zScope(zId);
    final codes = await _sessionCodes(scope.sessionIds);
    return generateOrdersList(
      sessionIds: scope.sessionIds,
      scopeLabel: scope.code ?? '#$zId',
      sessionCodes: codes,
      zCode: scope.code,
      zNumber: scope.number,
    );
  }

  Future<ProductsSummaryReport> productsSummaryForSession(int sessionId) async {
    final s = await (_db.select(_db.cashSessions)
          ..where((t) => t.id.equals(sessionId)))
        .getSingleOrNull();
    return generateProductsSummary(
      sessionIds: [sessionId],
      scopeLabel: s?.code ?? '#$sessionId',
      sessionCodes: s == null ? const [] : [s.code],
    );
  }

  Future<ProductsSummaryReport> productsSummaryForZ(int zId) async {
    final scope = await _zScope(zId);
    final codes = await _sessionCodes(scope.sessionIds);
    return generateProductsSummary(
      sessionIds: scope.sessionIds,
      scopeLabel: scope.code ?? '#$zId',
      sessionCodes: codes,
      zCode: scope.code,
      zNumber: scope.number,
    );
  }

  /// Modifiers sold across [sessionIds]. Cancelled orders are left out, the
  /// same rule as [generateProductsSummary], so the two tickets agree.
  Future<OptionsSummaryReport> generateOptionsSummary({
    required List<int> sessionIds,
    required String scopeLabel,
    List<String> sessionCodes = const [],
    String? zCode,
    int? zNumber,
  }) async {
    final data = await _loadScope(sessionIds);
    final liveOrderIds = data.orders
        .where((o) => o.status != 'CANCELED')
        .map((o) => o.id)
        .toSet();
    final opById = {
      for (final op in data.orderProducts)
        if (liveOrderIds.contains(op.orderId)) op.id: op
    };

    final missingNames = <int>{
      for (final c in data.components)
        if ((c.name ?? '').trim().isEmpty) c.componentId
    };
    final catalogueName = <int, String>{
      if (missingNames.isNotEmpty)
        for (final c in await (_db.select(_db.components)
              ..where((c) => c.id.isIn(missingNames.toList())))
            .get())
          c.id: c.name
    };

    final acc = <(int, bool), ({String name, double qty, double amount})>{};
    for (final c in data.components) {
      final op = opById[c.orderProductId];
      if (op == null) continue;
      final units = c.quantity * op.quantity;
      final key = (c.componentId, c.removalCharge);
      final name = (c.name ?? '').trim().isNotEmpty
          ? c.name!.trim()
          : (catalogueName[c.componentId] ?? '#${c.componentId}');
      final prev = acc[key];
      acc[key] = (
        name: prev?.name ?? name,
        qty: (prev?.qty ?? 0) + units,
        amount: (prev?.amount ?? 0) + c.price * units,
      );
    }

    final rows = [
      for (final e in acc.entries)
        OptionSummaryEntry(
          componentId: e.key.$1,
          removal: e.key.$2,
          name: e.value.name,
          quantity: e.value.qty,
          amount: e.value.amount,
        )
    ]..sort((a, b) {
        final c = b.quantity.compareTo(a.quantity);
        return c != 0 ? c : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return OptionsSummaryReport(
      scopeLabel: scopeLabel,
      start: data.orders.isEmpty ? DateTime.now() : data.orders.first.createdAt,
      end: data.orders.isEmpty ? DateTime.now() : data.orders.last.createdAt,
      sessionCodes: sessionCodes,
      zCode: zCode,
      zNumber: zNumber,
      rows: rows,
    );
  }

  /// The trading day [session] belongs to: every session of its Z when it has
  /// one, otherwise every session whose business day is the day it started.
  /// Open sessions count — this is read mid-day, not at close.
  Future<ReportScope> dayScopeFor(CashSession session) async {
    if (session.zId != null) {
      final z = await _zScope(session.zId!);
      if (z.sessionIds.isNotEmpty) {
        return (
          sessionIds: z.sessionIds,
          label: z.code ?? '#${session.zId}',
          sessionCodes: await _sessionCodes(z.sessionIds),
          zCode: z.code,
          zNumber: z.number,
        );
      }
    }
    final day = DateTime(session.startedAt.year, session.startedAt.month,
        session.startedAt.day);
    final ids = await sessionIdsForPeriod(day, day);
    if (!ids.contains(session.id)) ids.add(session.id);
    return (
      sessionIds: ids,
      label: '${day.year}-${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}',
      sessionCodes: await _sessionCodes(ids),
      zCode: null,
      zNumber: null,
    );
  }

  Future<List<String>> _sessionCodes(List<int> sessionIds) async {
    if (sessionIds.isEmpty) return const [];
    final rows = await (_db.select(_db.cashSessions)
          ..where((s) => s.id.isIn(sessionIds)))
        .get();
    return rows.map((s) => s.code).toList();
  }

  /// Build the JSON payload for `POST /pos/cash-sessions/{code}/email-report`.
  /// Includes session financials and per-product breakdown.
  /// [currency] should come from [AppSettings.currency].
  /// [clientRequestId] is the server's idempotency key together with the
  /// tenant and session code. It MUST be stable across retries and re-closes —
  /// a fresh uuid each attempt makes the server treat the retry as a new
  /// request and send a second email. Callers pass one they have persisted;
  /// the fallback only covers callers that genuinely fire once.
  Future<Map<String, dynamic>> buildEmailReportPayload(
    int sessionId, {
    String currency = 'MAD',
    int? zNumber,
    String? clientRequestId,
  }) async {
    final report = await generateSessionReport(sessionId);
    final session = report.sessions.first;

    // Non-cancelled tickets for this session → order IDs (mirrors _getSessionSummary)
    final allTickets = await (_db.select(_db.tickets)
          ..where((t) => t.sessionId.equals(sessionId)))
        .get();
    final ticketOrderIds = allTickets
        .where((t) => !t.isCancelled)
        .map((t) => t.orderId)
        .toSet()
        .toList();

    // Resolve orders, skip CANCELED — single batch fetch.
    final orders = ticketOrderIds.isNotEmpty
        ? (await (_db.select(_db.orders)
                ..where((o) => o.id.isIn(ticketOrderIds)))
              .get())
            .where((o) => o.status != 'CANCELED')
            .toList()
        : <Order>[];
    final orderIds = orders.map((o) => o.id).toList();

    // Product-level accumulator
    final Map<int, _EmailProductAcc> productAcc = {};
    double discountTotal = 0.0;

    // Fetch all order_products for this session in one query, then group in Dart.
    final allOps = orderIds.isNotEmpty
        ? await (_db.select(_db.orderProducts)
              ..where((op) => op.orderId.isIn(orderIds)))
            .get()
        : <OrderProduct>[];
    final opIds = allOps.map((op) => op.id).toList();
    final compPerUnit = <int, double>{};
    if (opIds.isNotEmpty) {
      final comps = await (_db.select(_db.orderProductComponents)
            ..where((c) => c.orderProductId.isIn(opIds)))
          .get();
      for (final c in comps) {
        compPerUnit[c.orderProductId] =
            (compPerUnit[c.orderProductId] ?? 0) + c.price * c.quantity;
      }
    }
    final pctByOrder = {for (final o in orders) o.id: o.discountPercentage};
    for (final op in allOps) {
      if (op.state == 'CANCELED') continue;
      final acc =
          productAcc.putIfAbsent(op.productId, () => _EmailProductAcc());
      acc.quantity += op.quantity;
      // Same split as the Z (§1), so the email and the paper agree.
      final money = LineMoney.of(op,
          componentsPerUnit: compPerUnit[op.id] ?? 0,
          orderDiscountPercentage: pctByOrder[op.orderId] ?? 0);
      acc.grossRevenue += money.gross;
      acc.discountTotal += money.discount;
      acc.netRevenue += money.net;
      discountTotal += money.discount;
    }

    // Resolve product metadata
    final productIds = productAcc.keys.toList();
    final productsDb = productIds.isNotEmpty
        ? await (_db.select(_db.products)
              ..where((p) => p.id.isIn(productIds)))
            .get()
        : <Product>[];
    final productById = {for (final p in productsDb) p.id: p};

    // Resolve category names (used in product rows only)
    final categoryIds =
        productsDb.map((p) => p.categoryId).whereType<int>().toSet().toList();
    final categoriesDb = categoryIds.isNotEmpty
        ? await (_db.select(_db.categories)
              ..where((c) => c.id.isIn(categoryIds)))
            .get()
        : <Category>[];
    final categoryById = {for (final c in categoriesDb) c.id: c};

    final productRows = productAcc.entries.map((e) {
      final p = productById[e.key];
      final catId = p?.categoryId;
      return {
        'productId': e.key,
        'productName': p?.name ?? 'Unknown',
        'categoryId': catId,
        'categoryName': catId != null ? categoryById[catId]?.name : null,
        'quantity': e.value.quantity,
        'grossRevenue': _round2(e.value.grossRevenue),
        'discountTotal': _round2(e.value.discountTotal),
        'netRevenue': _round2(e.value.netRevenue),
      };
    }).toList()
      ..sort((a, b) =>
          (b['netRevenue'] as double).compareTo(a['netRevenue'] as double));

    final moneyAtEnd = session.startingBalance + session.paidByCash;

    return {
      'clientRequestId': clientRequestId ?? const Uuid().v4(),
      'session': {
        'code': session.sessionCode,
        'cashierId': session.cashierId,
        'cashierName': session.cashierName ?? 'Cashier #${session.cashierId}',
        'startedAt': session.startedAt.toUtc().toIso8601String(),
        'endedAt':
            (session.endedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'moneyAtStart': _round2(session.startingBalance),
        'moneyAtEnd': _round2(moneyAtEnd),
        'countedCash':
            session.countedCash != null ? _round2(session.countedCash!) : null,
        'variance':
            session.variance != null ? _round2(session.variance!) : null,
        'countNotes': session.countNotes,
      },
      'totals': {
        'currency': currency,
        'ordersCount': session.totalOrders,
        'ticketsCount': session.totalTickets,
        'unpaidAmount': _round2(session.unpaidAmount),
        'discountTotal': _round2(discountTotal),
        'byPaymentMethod': {
          'CASH': _round2(session.paidByCash),
          'CARD': _round2(session.paidByCard),
          'PHONE': _round2(session.paidByPhone),
          'OTHER': _round2(session.paidByOther),
          'EXCHANGE': _round2(session.paidByExchange),
        },
      },
      'products': productRows,
      'categories': [],
      'stations': [],
      'zReport': {
        'issuedAt': DateTime.now().toUtc().toIso8601String(),
        'zNumber': zNumber ?? 1,
        'refundsTotal': _round2(await _refundsTotalForSession(sessionId)),
        'voidedTotal': _round2(session.cancelledAmount),
      },
    };
  }

  /// Money handed back during a session. Was hardcoded 0 before the POS had
  /// any refund flow, which quietly overstated every Z report's net.
  Future<double> _refundsTotalForSession(int sessionId) async {
    final rows = await (_db.select(_db.refunds)
          ..where((r) => r.sessionId.equals(sessionId)))
        .get();
    return rows.fold<double>(0, (s, r) => s + r.totalAmount);
  }

  static double _round2(double v) =>
      double.parse(v.toStringAsFixed(2));
}

/// Private mutable accumulator used by `_getSessionSummary` and
/// `generateReport`. Surfaced as `WaiterBreakdown` (immutable) once the
/// totals settle. Kept file-private to avoid leaking a mutable type into
/// the rest of the codebase.
class _WaiterAcc {
  int ordersCount = 0;
  double expected = 0;
  double paid = 0;
  double paidByCash = 0;
  double paidByCard = 0;
  double paidByPhone = 0;
  double paidByOther = 0;
}

class _EmailProductAcc {
  double quantity = 0;
  double grossRevenue = 0;
  double discountTotal = 0;
  double netRevenue = 0;
}

class _ProductAcc {
  double quantity = 0;
  double gross = 0;
  double discount = 0;
  double net = 0;
}

/// Everything the orders-list and products-summary reports read, fetched once
/// per scope in a fixed number of batched queries.
class _ScopeData {
  final List<Order> orders;
  final List<OrderProduct> orderProducts;
  final List<Ticket> tickets;
  final List<OrderProductComponent> components;
  final Map<int, double> compCostByOpId;
  final Map<int, String> tableNameById;
  final Map<int, String> waiterNameById;

  const _ScopeData({
    required this.orders,
    required this.orderProducts,
    required this.tickets,
    this.components = const [],
    required this.compCostByOpId,
    required this.tableNameById,
    required this.waiterNameById,
  });

  factory _ScopeData.empty() => const _ScopeData(
        orders: [],
        orderProducts: [],
        tickets: [],
        compCostByOpId: {},
        tableNameById: {},
        waiterNameById: {},
      );
}


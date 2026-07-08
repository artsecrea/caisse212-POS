import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../core/enums.dart';
import '../data/database/app_database.dart';
import '../utils/user_display.dart';
import 'session_service.dart' show PaymentBreakdown;

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
  final int cancelledTickets;
  final double cancelledAmount;
  // Z-report fields (null when the session was closed without a cash count).
  final double? countedCash;
  final double? variance;
  final DateTime? countedAt;
  final String? countNotes;
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
    this.cancelledTickets = 0,
    this.cancelledAmount = 0,
    this.countedCash,
    this.variance,
    this.countedAt,
    this.countNotes,
    this.waiterBreakdown = const [],
  });

  double get totalPaid => paidByCash + paidByCard + paidByPhone + paidByOther;
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
  final double totalStartingBalance;
  final double totalEndingBalance;
  final int totalCancelledTickets;
  final double totalCancelledAmount;
  /// Aggregated waiter rollup across every session in the report. Same
  /// waiter appearing in multiple sessions gets a single merged row.
  final List<WaiterBreakdown> totalWaiterBreakdown;

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
    required this.totalStartingBalance,
    required this.totalEndingBalance,
    this.totalCancelledTickets = 0,
    this.totalCancelledAmount = 0,
    this.totalWaiterBreakdown = const [],
  });

  double get totalPaid => totalPaidByCash + totalPaidByCard + totalPaidByPhone + totalPaidByOther;
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
    double totalStartingBalance = 0;
    double totalEndingBalance = 0;
    int totalCancelledTickets = 0;
    double totalCancelledAmount = 0;

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
      totalStartingBalance += session.startingBalance;
      totalEndingBalance += session.endingBalance ?? 0;
      totalCancelledTickets += session.cancelledTickets;
      totalCancelledAmount += session.cancelledAmount;

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
      totalStartingBalance: totalStartingBalance,
      totalEndingBalance: totalEndingBalance,
      totalCancelledTickets: totalCancelledTickets,
      totalCancelledAmount: totalCancelledAmount,
      totalWaiterBreakdown: totalWaiterBreakdown,
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

    // Per-waiter rollup accumulator. Key = waiterId. An order with no
    // waiterId (cashier rang it up directly) is excluded.
    final waiterAcc = <int, _WaiterAcc>{};

    for (final order in orders) {
      // Get order products to calculate order total
      final orderProducts = await (_db.select(_db.orderProducts)
        ..where((op) => op.orderId.equals(order.id)))
          .get();

      double subtotal = 0.0;
      double itemDiscount = 0.0;
      double totalTva = 0.0;

      for (final product in orderProducts) {
        // Get components for this order product
        final orderComponents = await (_db.select(_db.orderProductComponents)
          ..where((tbl) => tbl.orderProductId.equals(product.id)))
            .get();

        // Calculate component total using stored prices
        double componentTotal = 0.0;
        for (final orderComp in orderComponents) {
          componentTotal += orderComp.price * orderComp.quantity;
        }

        // Calculate product discount (manual + unitary)
        final productDiscount = (product.manualDiscount + product.unitaryDiscount) * product.quantity;

        // Calculate item subtotal: (unitaryPrice - unitaryTva + unitaryDiscount + componentTotal) * quantity
        // This matches the logic in _buildOrderFullDetails
        final itemSubtotal = ((product.unitaryPrice - product.unitaryTva + product.unitaryDiscount) + componentTotal) * product.quantity;
        final itemTva = product.unitaryTva * product.quantity;

        subtotal += itemSubtotal;
        itemDiscount += productDiscount;
        totalTva += itemTva;
      }

      // Calculate manual discount from percentage
      final discountPercentage = order.discountPercentage;
      final manualDiscountAmount = (subtotal + totalTva - itemDiscount) * (discountPercentage / 100);
      final totalDiscount = itemDiscount + manualDiscountAmount;

      // Calculate final total
      final orderTotal = subtotal + totalTva - totalDiscount;

      expectedFromOrders += orderTotal;

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
      cancelledTickets: cancelledTicketCount,
      cancelledAmount: cancelledAmount,
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

  /// Build the JSON payload for `POST /pos/cash-sessions/{code}/email-report`.
  /// Includes session financials and per-product breakdown.
  /// [currency] should come from [AppSettings.currency].
  Future<Map<String, dynamic>> buildEmailReportPayload(
    int sessionId, {
    String currency = 'MAD',
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
    for (final op in allOps) {
      final acc =
          productAcc.putIfAbsent(op.productId, () => _EmailProductAcc());
      acc.quantity += op.quantity;
      final gross = op.unitaryPrice * op.quantity;
      final disc = (op.unitaryDiscount + op.manualDiscount) * op.quantity;
      acc.grossRevenue += gross;
      acc.discountTotal += disc;
      acc.netRevenue += gross - disc;
      discountTotal += disc;
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
      'clientRequestId': const Uuid().v4(),
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
        },
      },
      'products': productRows,
      'categories': [],
      'stations': [],
      'zReport': {
        'issuedAt': DateTime.now().toUtc().toIso8601String(),
        'zNumber': 1,
        'refundsTotal': 0.0,
        'voidedTotal': _round2(session.cancelledAmount),
      },
    };
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


import '../data/database/app_database.dart';
import 'package:drift/drift.dart';

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
    }

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
    }

    // Calculate ticket totals by payment method (excluding cancelled)
    double paidByCash = 0;
    double paidByCard = 0;
    double paidByPhone = 0;
    double paidByOther = 0;
    double expectedFromTickets = 0;

    for (final ticket in tickets) {
      expectedFromTickets += ticket.amount;

      switch (ticket.paymentMethod.toLowerCase()) {
        case 'cash':
          paidByCash += ticket.amount;
          break;
        case 'card':
          paidByCard += ticket.amount;
          break;
        case 'phone':
          paidByPhone += ticket.amount;
          break;
        default:
          paidByOther += ticket.amount;
      }
    }

    // Calculate cancelled ticket totals
    final cancelledTicketCount = cancelledTickets.length;
    final cancelledAmount = cancelledTickets.fold<double>(0, (sum, t) => sum + t.amount);

    return SessionSummaryReport(
      sessionId: session.id,
      sessionCode: session.code,
      cashierId: session.cashierId,
      cashierName: user != null ? '${user.firstName} ${user.lastName}' : null,
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
    );
  }
}



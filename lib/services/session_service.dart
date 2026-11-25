import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import '../core/enums.dart';
import '../data/database/app_database.dart';
import '../domain/models/session_rules.dart';
import 'cash_movement_service.dart';
import 'daily_summary_service.dart';
import 'session_z_details.dart';
import 'cash_report_sections.dart' show CashReportSections;
import 'refund_service.dart';
import 'pending_operations_service.dart';
import '../utils/pos_log.dart';

/// Per-method money breakdown for a set of tickets.
///
/// Single source of truth so the close-session drawer figure and the Z-report
/// can never diverge. Rules:
///  - Cancelled tickets are excluded from every method bucket and tallied
///    separately in [cancelled] / [cancelledCount].
///  - Only paid tickets (`isPaid == true`) contribute to the method totals.
///  - Methods are matched via the [TransactionType] enum (not stringly-typed
///    lowercase literals) so a renamed enum value can't silently misfile money.
class PaymentBreakdown {
  final double cash;
  final double card;
  final double mobile;
  final double other;

  /// Exchange credit spent on new orders. Takings in the books (the new sale
  /// is real) but not money: it cancels against the exchange part of refunds.
  final double exchange;
  final double cancelled;
  final int cancelledCount;
  final int paidCount;

  const PaymentBreakdown({
    this.cash = 0,
    this.card = 0,
    this.mobile = 0,
    this.other = 0,
    this.exchange = 0,
    this.cancelled = 0,
    this.cancelledCount = 0,
    this.paidCount = 0,
  });

  /// Total takings across every payment method (paid, non-cancelled tickets).
  double get totalPaid => cash + card + mobile + other + exchange;

  Map<String, dynamic> toJson() => {
        'cash': cash,
        'card': card,
        'mobile': mobile,
        'other': other,
        'exchange': exchange,
        'cancelled': cancelled,
        'cancelledCount': cancelledCount,
        'paidCount': paidCount,
        'totalPaid': totalPaid,
      };

  /// [feeByTicketId] adds the delivery charge collected on a ticket to the
  /// method that collected it.
  ///
  /// `Ticket.amount` is products-only by design — every sales figure is built
  /// from it — so a delivery fee appears on no ticket row at all. It is still
  /// money in the drawer, and without this the close-session count came up
  /// over by exactly the fees taken in cash. Empty map = the old behaviour.
  static PaymentBreakdown fromTickets(
    Iterable<Ticket> tickets, {
    Map<int, double> feeByTicketId = const {},
  }) {
    double cash = 0, card = 0, mobile = 0, other = 0, exchange = 0;
    double cancelled = 0;
    int cancelledCount = 0, paidCount = 0;
    for (final t in tickets) {
      if (t.isCancelled) {
        cancelled += t.amount;
        cancelledCount++;
        continue;
      }
      if (!t.isPaid) continue;
      paidCount++;
      switch (TransactionType.fromString(t.paymentMethod)) {
        case TransactionType.cash:
          cash += t.amount + (feeByTicketId[t.id] ?? 0.0);
          break;
        case TransactionType.card:
          card += t.amount + (feeByTicketId[t.id] ?? 0.0);
          break;
        case TransactionType.mobile:
          mobile += t.amount + (feeByTicketId[t.id] ?? 0.0);
          break;
        case TransactionType.other:
          other += t.amount + (feeByTicketId[t.id] ?? 0.0);
          break;
        case TransactionType.exchange:
          exchange += t.amount;
          break;
      }
    }
    return PaymentBreakdown(
      cash: cash,
      card: card,
      mobile: mobile,
      other: other,
      exchange: exchange,
      cancelled: cancelled,
      cancelledCount: cancelledCount,
      paidCount: paidCount,
    );
  }
}

/// Session summary with calculated totals.
///
/// Backward-compatible getters (`totalCash`, `totalCard`, `totalCheck`,
/// `totalOther`, `totalAmount`, `expectedCashAtEnd`) are preserved for existing
/// UI callers. `totalCheck` is retained for compatibility only — the CHECK
/// payment method no longer exists, so it is always 0.
class SessionSummary {
  final CashSession session;
  final PaymentBreakdown breakdown;
  final int ticketCount;

  /// Signed net of non-sale cash movements (paid-in minus paid-out) for this
  /// session. Positive = money was added to the drawer.
  final double cashMovementsNet;

  /// Gross sides of [cashMovementsNet], so a report can show both lines — a
  /// float top-up and a payout of the same size net to zero but are two
  /// separate facts the owner wants on the Z.
  final double cashPaidIn;
  final double cashPaidOut;

  /// Refunds recorded against this session. [refundsTotal] is every method —
  /// a report line; [refundsCash] is the cash-only part, the only one that
  /// physically left the drawer.
  final double refundsTotal;
  final double refundsCash;

  /// Count, per-method split, earlier-sales part and waste of the same
  /// refunds — what the Z prints and the session `details` carry.
  final RefundBreakdown refunds;

  SessionSummary({
    required this.session,
    required this.breakdown,
    required this.ticketCount,
    this.cashMovementsNet = 0,
    this.cashPaidIn = 0,
    this.cashPaidOut = 0,
    this.refundsTotal = 0,
    this.refundsCash = 0,
    this.refunds = RefundBreakdown.empty,
  });

  double get totalCash => breakdown.cash;
  double get totalCard => breakdown.card;
  double get totalMobile => breakdown.mobile;
  double get totalOther => breakdown.other;
  double get totalCheck => 0; // legacy — CHECK method removed
  double get cancelledAmount => breakdown.cancelled;
  int get cancelledCount => breakdown.cancelledCount;

  /// Full takings across every payment method.
  double get totalPaid => breakdown.totalPaid;

  /// Backward-compatible alias for [totalPaid].
  double get totalAmount => breakdown.totalPaid;

  /// Physical cash expected in the drawer: opening float + cash takings, plus
  /// whatever was paid in, minus whatever was paid out, minus cash refunds.
  ///
  /// The movements term is what stops a petty-cash withdrawal from showing up
  /// as an unexplained shortfall in [CloseSessionDialog]'s variance line.
  ///
  /// Refunds are NOT transactions — nothing in the refund path writes to
  /// `transactions`, so `breakdown.cash` has never seen them. Without the last
  /// term the drawer reads short by exactly the cash refunded, every close.
  /// Only the cash part is subtracted: a card sale refunded to a card moves no
  /// notes, and counting it would invent a surplus instead.
  double get expectedCashAtEnd =>
      session.moneyAtStart +
      breakdown.cash +
      cashMovementsNet -
      refundsCash;

  /// Key/value snapshot persisted on the session at close.
  Map<String, dynamic> get details => {
        ...breakdown.toJson(),
        'ticketCount': ticketCount,
        'moneyAtStart': session.moneyAtStart,
        'expectedCashAtEnd': expectedCashAtEnd,
        'cashPaidIn': cashPaidIn,
        'cashPaidOut': cashPaidOut,
        'refundsTotal': refundsTotal,
        'refundsCash': refundsCash,
      };
}

class SessionWithCashier {
  final CashSession session;
  final String cashierName;
  final SessionSummary? summary;

  const SessionWithCashier({
    required this.session,
    required this.cashierName,
    this.summary,
  });
}

/// cash session service
/// Whether closing this session needs a supervisor's sign-off.
///
/// Two ways a session fails to balance, and the rule treats them the same:
/// the drawer is short or over against what the tickets say, or orders are
/// still unpaid on the floor. Either is a discrepancy somebody should have to
/// own; a shop that wants one supervised almost always wants the other.
///
/// [tolerance] is the same epsilon the close dialog uses to decide the
/// variance is "on target" — a count that is off by a rounding penny is not a
/// discrepancy and must not summon a manager.
///
/// Returns false when the feature is off, which is the default and the
/// behaviour every existing till already has.
bool closeNeedsSignOff({
  required bool featureEnabled,
  required double? countedCash,
  required double expectedCash,
  required bool hasUnpaidOrders,
  double tolerance = 0.005,
}) {
  if (!featureEnabled) return false;
  if (hasUnpaidOrders) return true;
  // A blank count is not a clean close: nobody counted the drawer, so nobody
  // can say it balances. The dialog pre-fills the expected figure, so reaching
  // here with null means the cashier deliberately cleared it.
  if (countedCash == null) return true;
  return (countedCash - expectedCash).abs() > tolerance;
}

class SessionService {
  final AppDatabase _database;

  SessionService(this._database);

  /// Start a new cash session
  ///
  /// [moneyEntered] is the cash the cashier brought in, [moneyCarriedOver]
  /// what was left from the previous session — both POS-counted and sent as
  /// is; the server only sums them per Z.
  /// [posId] is this terminal's id with the backend (`ApiService.getPosId`).
  /// It goes into the session code so two tills can never mint the same one;
  /// null on a till that was never registered.
  Future<CashSession> startSession({
    required int cashierId,
    required double moneyAtStart,
    double? moneyEntered,
    double? moneyCarriedOver,
    int? posId,
  }) async {
    // Check if there's an active session for this user
    final existingSession = await getActiveSession(cashierId);
    if (existingSession != null) {
      throw Exception('User already has an active session');
    }

    final sessionCode = await _uniqueSessionCode(DateTime.now(), posId: posId);

    final id = await _database.into(_database.cashSessions).insert(
      CashSessionsCompanion.insert(
        id: const Value.absent(),
        code: sessionCode,
        cashierId: cashierId,
        moneyAtStart: moneyAtStart,
        moneyEntered: Value(moneyEntered),
        moneyCarriedOver: Value(moneyCarriedOver),
        status: const Value('active'),
        startedAt: Value(DateTime.now()),
      ),
    );

    return (await _database.select(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(id)))
      .getSingle();
  }

  static final _random = Random.secure();

  /// `CS-YYYYMMDD-<posId>-HHMMSS-XXX`, or `CS-YYYYMMDD-HHMMSS-XXX` on a till
  /// with no POS id. The POS id keeps two tills from ever minting the same
  /// code. The random suffix, re-drawn on a clash with a session this till
  /// already has, keeps two sessions of one till in the same second apart; it
  /// used to be the clock's milliseconds, and the second insert failed.
  Future<String> _uniqueSessionCode(DateTime now, {int? posId}) async {
    String two(int v) => v.toString().padLeft(2, '0');
    final day = '${now.year}${two(now.month)}${two(now.day)}';
    final time = '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final stamp = posId == null ? '$day-$time' : '$day-$posId-$time';
    Future<bool> free(String code) async =>
        await (_database.select(_database.cashSessions)
              ..where((s) => s.code.equals(code)))
            .getSingleOrNull() ==
        null;
    String withSuffix(int n) => 'CS-$stamp-${n.toString().padLeft(3, '0')}';

    for (var attempt = 0; attempt < 20; attempt++) {
      final code = withSuffix(_random.nextInt(1000));
      if (await free(code)) return code;
    }
    // Twenty clashes in one second: walk the rest rather than guess again.
    for (var n = 0; n < 1000; n++) {
      if (await free(withSuffix(n))) return withSuffix(n);
    }
    throw StateError('No free session code left for $stamp');
  }

  /// End a cash session - calculates money at end from tickets.
  ///
  /// If [countedCash] is provided, it represents the physical cash the cashier
  /// counted in the drawer. We compute `variance = countedCash - expectedCash`
  /// and store both. `moneyAtEnd` becomes the counted amount (the number an
  /// accountant cares about); otherwise it falls back to the expected amount,
  /// preserving the old single-arg behaviour.
  ///
  /// [autoClosed] marks a session ended by the system (a Z close sweeping it
  /// up, the day rollover, a session rule) rather than by its cashier.
  Future<void> endSession({
    required int sessionId,
    double? countedCash,
    String? countNotes,
    bool autoClosed = false,
  }) async {
    final session = await getSessionById(sessionId);
    if (session == null) {
      throw Exception('Session not found');
    }

    // Calculate totals from session tickets.
    final summary = await getSessionSummary(sessionId);
    final expectedCash = summary.expectedCashAtEnd;
    final endedAt = DateTime.now();
    // `moneyAtEnd` remains the physical cash-drawer figure (counted if the
    // cashier entered a count, else the expected cash). `totalPaid`/`details`
    // capture the full multi-method takings alongside it.
    final moneyAtEnd = countedCash ?? expectedCash;
    final variance =
        countedCash == null ? null : countedCash - expectedCash;
    // Full figures for the server's Z sum. A report failure must never block
    // the close: the payment totals alone still go.
    CashReportSections? sections;
    try {
      sections = (await DailySummaryService(_database)
              .generateSessionReport(sessionId))
          .sections;
    } catch (e) {
      posLog('Session details: report sections unavailable: $e');
    }
    final details =
        buildSessionDetails(summary, sections: sections, variance: variance);

    await (_database.update(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(sessionId)))
      .write(
        CashSessionsCompanion(
          endedAt: Value(endedAt),
          moneyAtEnd: Value(moneyAtEnd),
          totalPaid: Value(summary.totalPaid),
          details: Value(jsonEncode(details)),
          status: const Value('ended'),
          countedCash: Value(countedCash),
          variance: Value(variance),
          countedAt: Value(countedCash == null ? null : endedAt),
          countNotes: Value(countNotes),
          autoClosed: Value(autoClosed),
          // Always mark unsynced so syncSessionsBulk / syncSingleSession
          // can push the closed state to the server on next opportunity.
          isSynced: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
  }

  /// Pause a session. Returns whether it was active — false when it was
  /// already paused (or gone), so callers notify only a real change.
  Future<bool> pauseSession(int sessionId) async {
    final before = await getSessionById(sessionId);
    await (_database.update(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(sessionId)))
      .write(
        CashSessionsCompanion(
          pausedAt: Value(DateTime.now()),
          status: const Value('paused'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    return before?.status == 'active';
  }

  /// Resume a paused session. Returns when it was paused, or null when it
  /// was not paused — callers notify only a real change.
  Future<DateTime?> resumeSession(int sessionId) async {
    final before = await getSessionById(sessionId);
    await (_database.update(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(sessionId)))
      .write(
        CashSessionsCompanion(
          pausedAt: const Value(null),
          status: const Value('active'),
          updatedAt: Value(DateTime.now()),
        ),
      );
    if (before?.status != 'paused') return null;
    return before?.pausedAt ?? before?.updatedAt;
  }

  /// Verify if a session exists and is active
  Future<CashSession?> verifySession(int sessionId) async {
    return await (_database.select(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(sessionId) & tbl.status.equals('active')))
      .getSingleOrNull();
  }

  /// Get active session for a user
  Future<CashSession?> getActiveSession(int cashierId) async {
    return await (_database.select(_database.cashSessions)
      ..where((tbl) =>
        tbl.cashierId.equals(cashierId) &
        tbl.status.isIn(['active', 'paused'])))
      .getSingleOrNull();
  }

  /// Get session by ID
  Future<CashSession?> getSessionById(int sessionId) async {
    return await (_database.select(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(sessionId)))
      .getSingleOrNull();
  }

  /// Checks whether [rules] allow a new session to be opened right now.
  ///
  /// Pass [isAdmin: true] to bypass all checks (admin users are exempt).
  /// Throws [SessionRuleViolation] with a human-readable message on failure.
  Future<void> checkOpenRules(
    SessionRules rules, {
    required bool isAdmin,
    required int cashierId,
    double moneyAtStart = 0,
  }) async {
    if (isAdmin) return;
    if (!rules.hasAnyRule) return;

    if (rules.requireOpeningFloat && moneyAtStart <= 0) {
      throw SessionRuleViolation('An opening float is required');
    }

    final maxOpen = rules.maxOpenSessionsPerTerminal;
    if (maxOpen != null && maxOpen > 0) {
      final open = await (_database.select(_database.cashSessions)
            ..where((s) => s.status.isIn(['active', 'paused'])))
          .get();
      if (open.length >= maxOpen) {
        throw SessionRuleViolation(
            'Maximum $maxOpen open session(s) on this terminal reached');
      }
    }

    final hour = DateTime.now().hour;

    if (rules.minStartHour != null && hour < rules.minStartHour!) {
      throw SessionRuleViolation(
          'Sessions cannot be opened before ${rules.minStartHour!.toString().padLeft(2, '0')}:00');
    }

    if (rules.cantOpenAfterHour != null && hour >= rules.cantOpenAfterHour!) {
      throw SessionRuleViolation(
          'Sessions cannot be opened at or after ${rules.cantOpenAfterHour!.toString().padLeft(2, '0')}:00');
    }

    if (rules.maxSessionsPerUserPerDay != null) {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));
      final allSessions = await getUserSessions(cashierId);
      final todayCount = allSessions.where((s) {
        return s.startedAt.isAfter(startOfDay) &&
            s.startedAt.isBefore(endOfDay);
      }).length;
      if (todayCount >= rules.maxSessionsPerUserPerDay!) {
        throw SessionRuleViolation(
            'Maximum ${rules.maxSessionsPerUserPerDay} session(s) per day reached');
      }
    }
  }

  /// Get all sessions for a user
  Future<List<CashSession>> getUserSessions(int cashierId) async {
    return await (_database.select(_database.cashSessions)
      ..where((tbl) => tbl.cashierId.equals(cashierId))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.startedAt)]))
      .get();
  }

  /// Get all sessions
  Future<List<CashSession>> getAllSessions() async {
    return await (_database.select(_database.cashSessions)
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.startedAt)]))
      .get();
  }

  /// Delete a session
  Future<void> deleteSession(int sessionId, {bool queueSyncOperation = true}) async {
    // Check if session was synced
    final session = await getSessionById(sessionId);
    if (session == null) {
      throw Exception('Session not found');
    }
    // A closed session is part of its Z's totals: the server refuses to
    // delete it (409), and a queued delete would retry forever.
    if (session.status == 'ended') {
      throw Exception('A closed session cannot be deleted');
    }
    final wasSynced = session.isSynced;

    // Queue delete operation if session was synced
    if (wasSynced && queueSyncOperation) {
      try {
        final pendingOpsService = PendingOperationsService(_database);
        await pendingOpsService.queueSessionDelete(
          entityId: sessionId,
          sessionCode: session.code,
        );
        posLog('Queued delete operation for synced session code=${session.code}');
      } catch (e) {
        posLog('Failed to queue session delete operation: $e');
      }
    }

    await (_database.delete(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(sessionId)))
      .go();
  }

  /// Get tickets for a session
  Future<List<Ticket>> getSessionTickets(int sessionId) async {
    return await (_database.select(_database.tickets)
      ..where((tbl) => tbl.sessionId.equals(sessionId))
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.date)]))
      .get();
  }

  /// Which ticket collected each order's delivery charge.
  ///
  /// An order carries one charge however many ways the bill is divided, and it
  /// rides the FIRST settlement — the same rule `deliveryFeeToCollect` applies
  /// when taking the money, and the same rule a reprint uses. Keyed by ticket
  /// so the caller can attribute it to the method that ticket was paid with.
  Future<Map<int, double>> _deliveryFeeByTicket(List<Ticket> tickets) async {
    final live = tickets.where((t) => t.isPaid && !t.isCancelled).toList();
    if (live.isEmpty) return const {};

    final orderIds = live.map((t) => t.orderId).toSet().toList();
    final orders = await (_database.select(_database.orders)
          ..where((o) => o.id.isIn(orderIds)))
        .get();
    final feeByOrder = {
      for (final o in orders)
        if ((o.deliveryFee ?? 0) > 0) o.id: o.deliveryFee!,
    };
    if (feeByOrder.isEmpty) return const {};

    final firstTicketByOrder = <int, Ticket>{};
    for (final t in live) {
      if (!feeByOrder.containsKey(t.orderId)) continue;
      final held = firstTicketByOrder[t.orderId];
      if (held == null || t.id < held.id) firstTicketByOrder[t.orderId] = t;
    }
    return {
      for (final entry in firstTicketByOrder.entries)
        entry.value.id: feeByOrder[entry.key]!,
    };
  }

  /// Get session summary with calculated totals
  Future<SessionSummary> getSessionSummary(int sessionId) async {
    final session = await getSessionById(sessionId);
    if (session == null) {
      throw Exception('Session not found');
    }

    final tickets = await getSessionTickets(sessionId);

    // Non-sale drawer movements. Folded in here, at the single place the summary
    // is built, so every consumer (close dialog, sessions list, X/Z reports,
    // email report) gets the same expected-cash figure.
    final movements = CashMovementService(_database);
    final totals = await movements.totalsForSessions([sessionId]);

    // Refunds, folded in at the same single place for the same reason: every
    // consumer must agree on the expected-cash figure.
    final refunds = RefundService(_database);
    final refundsTotal = await refunds.totalForSession(sessionId);
    final refundsCash = await refunds.cashTotalForSession(sessionId);
    final refundBreakdown = await refunds.breakdownForSessions([sessionId]);

    // Delivery charges, attributed the way the payment screen collects them:
    // one per order, on whichever ticket settled first. Reconstructed rather
    // than read off a ticket row because no ticket row carries it.
    final feeByTicketId = await _deliveryFeeByTicket(tickets);

    return SessionSummary(
      session: session,
      breakdown:
          PaymentBreakdown.fromTickets(tickets, feeByTicketId: feeByTicketId),
      ticketCount: tickets.length,
      cashMovementsNet: totals.paidIn - totals.paidOut,
      cashPaidIn: totals.paidIn,
      cashPaidOut: totals.paidOut,
      refundsTotal: refundsTotal,
      refundsCash: refundsCash,
      refunds: refundBreakdown,
    );
  }

  /// Paginated, filtered, sorted sessions with resolved cashier names and summaries.
  Future<(List<SessionWithCashier>, int)> getSessionsPage({
    required int offset,
    required int limit,
    String statusFilter = 'ALL',
    String searchQuery = '',
    DateTime? startDate,
    DateTime? endDate,
    int sortColumn = 2,
    bool sortAscending = false,
  }) async {
    final users = await _database.select(_database.users).get();
    String resolveName(int cashierId) {
      final u = users.where((u) => u.id == cashierId).firstOrNull;
      if (u == null) return '#$cashierId';
      final dn = u.displayName;
      return (dn != null && dn.isNotEmpty) ? dn : '${u.firstName} ${u.lastName}'.trim();
    }

    final query = _database.select(_database.cashSessions);
    if (statusFilter != 'ALL') {
      query.where((tbl) => tbl.status.equals(statusFilter));
    }
    if (searchQuery.isNotEmpty) {
      query.where((tbl) => tbl.code.contains(searchQuery));
    }
    if (startDate != null) {
      query.where((tbl) => tbl.startedAt.isBiggerOrEqualValue(startDate));
    }
    if (endDate != null) {
      final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      query.where((tbl) => tbl.startedAt.isSmallerOrEqualValue(endOfDay));
    }

    final all = await query.get();

    all.sort((a, b) {
      int cmp;
      switch (sortColumn) {
        case 0:
          cmp = a.code.compareTo(b.code);
          break;
        case 1:
          cmp = resolveName(a.cashierId).compareTo(resolveName(b.cashierId));
          break;
        case 3:
          cmp = a.status.compareTo(b.status);
          break;
        case 4:
          cmp = a.moneyAtStart.compareTo(b.moneyAtStart);
          break;
        default: // 2 = startedAt
          cmp = a.startedAt.compareTo(b.startedAt);
      }
      return sortAscending ? cmp : -cmp;
    });

    final total = all.length;
    final page = all.skip(offset).take(limit).toList();

    final rows = <SessionWithCashier>[];
    for (final session in page) {
      SessionSummary? summary;
      try {
        summary = await getSessionSummary(session.id);
      } catch (_) {}
      rows.add(SessionWithCashier(
        session: session,
        cashierName: resolveName(session.cashierId),
        summary: summary,
      ));
    }

    return (rows, total);
  }
}
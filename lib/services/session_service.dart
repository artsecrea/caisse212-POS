import 'dart:convert';
import 'package:drift/drift.dart';
import '../core/enums.dart';
import '../data/database/app_database.dart';
import '../domain/models/session_rules.dart';
import 'pending_operations_service.dart';

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
  final double cancelled;
  final int cancelledCount;
  final int paidCount;

  const PaymentBreakdown({
    this.cash = 0,
    this.card = 0,
    this.mobile = 0,
    this.other = 0,
    this.cancelled = 0,
    this.cancelledCount = 0,
    this.paidCount = 0,
  });

  /// Total takings across every payment method (paid, non-cancelled tickets).
  double get totalPaid => cash + card + mobile + other;

  Map<String, dynamic> toJson() => {
        'cash': cash,
        'card': card,
        'mobile': mobile,
        'other': other,
        'cancelled': cancelled,
        'cancelledCount': cancelledCount,
        'paidCount': paidCount,
        'totalPaid': totalPaid,
      };

  static PaymentBreakdown fromTickets(Iterable<Ticket> tickets) {
    double cash = 0, card = 0, mobile = 0, other = 0, cancelled = 0;
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
          cash += t.amount;
          break;
        case TransactionType.card:
          card += t.amount;
          break;
        case TransactionType.mobile:
          mobile += t.amount;
          break;
        case TransactionType.other:
          other += t.amount;
          break;
      }
    }
    return PaymentBreakdown(
      cash: cash,
      card: card,
      mobile: mobile,
      other: other,
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

  SessionSummary({
    required this.session,
    required this.breakdown,
    required this.ticketCount,
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

  /// Physical cash expected in the drawer: opening float + cash takings only.
  double get expectedCashAtEnd => session.moneyAtStart + breakdown.cash;

  /// Key/value snapshot persisted on the session at close.
  Map<String, dynamic> get details => {
        ...breakdown.toJson(),
        'ticketCount': ticketCount,
        'moneyAtStart': session.moneyAtStart,
        'expectedCashAtEnd': expectedCashAtEnd,
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
class SessionService {
  final AppDatabase _database;

  SessionService(this._database);

  /// Start a new cash session
  Future<CashSession> startSession({
    required int cashierId,
    required double moneyAtStart,
  }) async {
    // Check if there's an active session for this user
    final existingSession = await getActiveSession(cashierId);
    if (existingSession != null) {
      throw Exception('User already has an active session');
    }

    // Generate unique session code (format: CS-YYYYMMDD-HHMMSS-XXX)
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final randomSuffix = now.microsecond.toString().padLeft(3, '0').substring(0, 3);
    final sessionCode = 'CS-$dateStr-$timeStr-$randomSuffix';

    final id = await _database.into(_database.cashSessions).insert(
      CashSessionsCompanion.insert(
        id: const Value.absent(),
        code: sessionCode,
        cashierId: cashierId,
        moneyAtStart: moneyAtStart,
        status: const Value('active'),
        startedAt: Value(DateTime.now()),
      ),
    );

    return (await _database.select(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(id)))
      .getSingle();
  }

  /// End a cash session - calculates money at end from tickets.
  ///
  /// If [countedCash] is provided, it represents the physical cash the cashier
  /// counted in the drawer. We compute `variance = countedCash - expectedCash`
  /// and store both. `moneyAtEnd` becomes the counted amount (the number an
  /// accountant cares about); otherwise it falls back to the expected amount,
  /// preserving the old single-arg behaviour.
  Future<void> endSession({
    required int sessionId,
    double? countedCash,
    String? countNotes,
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

    await (_database.update(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(sessionId)))
      .write(
        CashSessionsCompanion(
          endedAt: Value(endedAt),
          moneyAtEnd: Value(moneyAtEnd),
          totalPaid: Value(summary.totalPaid),
          details: Value(jsonEncode(summary.details)),
          status: const Value('ended'),
          countedCash: Value(countedCash),
          variance: Value(variance),
          countedAt: Value(countedCash == null ? null : endedAt),
          countNotes: Value(countNotes),
          // Always mark unsynced so syncSessionsBulk / syncSingleSession
          // can push the closed state to the server on next opportunity.
          isSynced: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
  }

  /// Pause a session
  Future<void> pauseSession(int sessionId) async {
    await (_database.update(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(sessionId)))
      .write(
        CashSessionsCompanion(
          pausedAt: Value(DateTime.now()),
          status: const Value('paused'),
          updatedAt: Value(DateTime.now()),
        ),
      );
  }

  /// Resume a paused session
  Future<void> resumeSession(int sessionId) async {
    await (_database.update(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(sessionId)))
      .write(
        CashSessionsCompanion(
          pausedAt: const Value(null),
          status: const Value('active'),
          updatedAt: Value(DateTime.now()),
        ),
      );
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
  }) async {
    if (isAdmin) return;
    if (!rules.hasAnyRule) return;

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
    final wasSynced = session.isSynced;

    // Queue delete operation if session was synced
    if (wasSynced && queueSyncOperation) {
      try {
        final pendingOpsService = PendingOperationsService(_database);
        await pendingOpsService.queueSessionDelete(
          entityId: sessionId,
          sessionCode: session.code,
        );
        print('Queued delete operation for synced session code=${session.code}');
      } catch (e) {
        print('Failed to queue session delete operation: $e');
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

  /// Get session summary with calculated totals
  Future<SessionSummary> getSessionSummary(int sessionId) async {
    final session = await getSessionById(sessionId);
    if (session == null) {
      throw Exception('Session not found');
    }

    final tickets = await getSessionTickets(sessionId);

    return SessionSummary(
      session: session,
      breakdown: PaymentBreakdown.fromTickets(tickets),
      ticketCount: tickets.length,
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
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';

/// Session summary with calculated totals
class SessionSummary {
  final CashSession session;
  final double totalCash;
  final double totalCard;
  final double totalCheck;
  final double totalOther;
  final int ticketCount;

  SessionSummary({
    required this.session,
    required this.totalCash,
    required this.totalCard,
    required this.totalCheck,
    required this.totalOther,
    required this.ticketCount,
  });

  double get totalAmount => totalCash + totalCard + totalCheck + totalOther;
  double get expectedCashAtEnd => session.moneyAtStart + totalCash;
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

    final id = await _database.into(_database.cashSessions).insert(
      CashSessionsCompanion.insert(
        id: const Value.absent(),
        cashierId: cashierId,
        moneyAtStart: moneyAtStart,
        status: const Value('active'),
      ),
    );

    return (await _database.select(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(id)))
      .getSingle();
  }

  /// End a cash session - calculates money at end from tickets
  Future<void> endSession({
    required int sessionId,
  }) async {
    // Calculate total cash from session tickets
    final summary = await getSessionSummary(sessionId);
    final moneyAtEnd = summary.expectedCashAtEnd;

    await (_database.update(_database.cashSessions)
      ..where((tbl) => tbl.id.equals(sessionId)))
      .write(
        CashSessionsCompanion(
          endedAt: Value(DateTime.now()),
          moneyAtEnd: Value(moneyAtEnd),
          status: const Value('ended'),
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
  Future<void> deleteSession(int sessionId) async {
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

    double totalCash = 0;
    double totalCard = 0;
    double totalCheck = 0;
    double totalOther = 0;

    for (final ticket in tickets) {
      if (ticket.isPaid) {
        switch (ticket.paymentMethod.toLowerCase()) {
          case 'cash':
            totalCash += ticket.amount;
            break;
          case 'card':
            totalCard += ticket.amount;
            break;
          case 'check':
            totalCheck += ticket.amount;
            break;
          default:
            totalOther += ticket.amount;
        }
      }
    }

    return SessionSummary(
      session: session,
      totalCash: totalCash,
      totalCard: totalCard,
      totalCheck: totalCheck,
      totalOther: totalOther,
      ticketCount: tickets.length,
    );
  }
}
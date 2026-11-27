import '../../data/database/app_database.dart' show CashSession;
import '../../services/session_service.dart'
    show SessionSummary, SessionWithCashier;

/// What the screens read about cash sessions. An interface because, linked
/// to a hub, a till shows the hub's sessions: standalone, it reads its own
/// database (`SessionService`).
abstract interface class SessionQueries {
  /// Get active session for a user
  ///
  /// Newest first: a till that already holds two open sessions for one
  /// cashier (a double-fired login on 2026-11-26) must still let them sign
  /// in, and `getSingleOrNull` threw "Bad state: Too many elements" there.
  /// The session taking money on this till now, whoever's it is: the
  /// newest active one. A paused session does not count.
  Future<CashSession?> activeSessionOnTill();

  Future<CashSession?> getActiveSession(int cashierId);

  /// Get session by ID
  Future<CashSession?> getSessionById(int sessionId);

  /// The sessions behind a report scope. Unordered unless [oldestFirst]:
  /// the day-scope check only asks whether any is still open, while the
  /// settle-unpaid target falls back to the day's first shift.
  Future<List<CashSession>> getSessionsByIds(Iterable<int> ids,
      {bool oldestFirst = false});

  /// Get session summary with calculated totals
  Future<SessionSummary> getSessionSummary(int sessionId);

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
  });
}

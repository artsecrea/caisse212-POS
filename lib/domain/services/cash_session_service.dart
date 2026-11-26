import '../../data/database/app_database.dart' show CashMovement;
import '../../services/daily_summary_service.dart' show DailySummaryReport;

/// The person who closed a session, as the activity log records them.
typedef SessionCloser = ({int? userId, String? username});

/// What a till does to a cash session and its drawer. An interface because a
/// session is shared state — on a hub, the hub records it — so a standalone
/// till answers from its own database (`LocalCashSessionService`) and a
/// hub-linked one will ask the hub.
abstract interface class CashSessionService {
  /// Pause [sessionId] and tell the admins. False when it was not open, and
  /// nothing changed.
  Future<bool> pause(int sessionId);

  /// Resume [sessionId] and, unless [notifyAdmins] is false, tell the admins
  /// how long it was paused. Returns when it had been paused; null when it
  /// was not paused, and nothing changed.
  Future<DateTime?> resume(int sessionId, {bool notifyAdmins = true});

  /// End [sessionId] with the cash counted in the drawer. [closedBy] is the
  /// person who closed it, and their close is logged: a close with no log
  /// entry is one nobody asked for — the timer's ([autoClosed]) or the remote
  /// console's. [freeTables] frees every table its orders still hold.
  Future<void> close(
    int sessionId, {
    double? countedCash,
    String? notes,
    bool autoClosed = false,
    SessionCloser? closedBy,
    bool freeTables = false,
  });

  /// Once a session is closed — and its Z, when the close ended the day:
  /// send its session, movements, orders, tickets and refunds to the cloud,
  /// then the email report, and tell the admins with [report]. Failures are
  /// logged; whatever did not go stays queued.
  Future<void> publishClose(int sessionId, {DailySummaryReport? report});

  /// Delete [sessionId]. Throws for a closed session.
  Future<void> delete(int sessionId);

  /// Put cash into, or take it out of, the drawer: [direction] is `IN` or
  /// `OUT`, [amount] is unsigned.
  Future<CashMovement> recordMovement({
    required String direction,
    required double amount,
    required String reason,
    String? reference,
    int? sessionId,
    DateTime? zDay,
    int? createdBy,
  });

  Future<void> deleteMovement(int movementId);

  /// [sessionId]'s cash movements.
  Future<List<CashMovement>> movementsOf(int sessionId);
}

import '../../data/database/app_database.dart' show CashMovement;

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

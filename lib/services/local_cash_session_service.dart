import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/services/cash_session_service.dart';
import '../providers/database_providers.dart';
import 'cash_movement_service.dart';
import 'pos_notifications.dart' show notifySessionPauseChange;
import 'session_service.dart';

/// [CashSessionService] on this till's own database: the standalone till.
/// Each action is the [SessionService] or [CashMovementService] call the
/// screens made, with the admin notification each pause and resume paired
/// with by hand.
class LocalCashSessionService implements CashSessionService {
  LocalCashSessionService(this._ref);

  final Ref _ref;

  SessionService get _sessions => _ref.read(sessionServiceProvider);
  CashMovementService get _movements => _ref.read(cashMovementServiceProvider);

  @override
  Future<bool> pause(int sessionId) async {
    if (!await _sessions.pauseSession(sessionId)) return false;
    await notifySessionPauseChange(_ref.read, sessionId);
    return true;
  }

  @override
  Future<DateTime?> resume(int sessionId, {bool notifyAdmins = true}) async {
    final pausedAt = await _sessions.resumeSession(sessionId);
    if (pausedAt != null && notifyAdmins) {
      await notifySessionPauseChange(_ref.read, sessionId, pausedAt: pausedAt);
    }
    return pausedAt;
  }

  @override
  Future<void> delete(int sessionId) => _sessions.deleteSession(sessionId);

  @override
  Future<CashMovement> recordMovement({
    required String direction,
    required double amount,
    required String reason,
    String? reference,
    int? sessionId,
    DateTime? zDay,
    int? createdBy,
  }) =>
      _movements.record(
        direction: direction,
        amount: amount,
        reason: reason,
        reference: reference,
        sessionId: sessionId,
        zDay: zDay,
        createdBy: createdBy,
      );

  @override
  Future<void> deleteMovement(int movementId) => _movements.delete(movementId);

  @override
  Future<List<CashMovement>> movementsOf(int sessionId) =>
      _movements.forSession(sessionId);
}

/// The session actions for the screens. A hub-linked till overrides this one
/// provider; nothing else changes.
final cashSessionServiceProvider =
    Provider<CashSessionService>((ref) => LocalCashSessionService(ref));

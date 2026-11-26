import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../domain/services/cash_session_service.dart';
import '../providers/database_providers.dart';
import '../providers/settings_provider.dart';
import 'activity_log_service.dart';
import 'cash_movement_service.dart';
import 'daily_summary_service.dart';
import 'local_floor_service.dart';
import 'pos_notifications.dart'
    show notifySessionClosed, notifySessionPauseChange;
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
  Future<void> close(
    int sessionId, {
    double? countedCash,
    String? notes,
    bool autoClosed = false,
    SessionCloser? closedBy,
    bool freeTables = false,
  }) async {
    await _sessions.endSession(
      sessionId: sessionId,
      countedCash: countedCash,
      countNotes: notes,
      autoClosed: autoClosed,
    );
    if (closedBy != null) {
      try {
        await _ref.read(activityLogServiceProvider).logSessionEnd(
              userId: closedBy.userId,
              username: closedBy.username,
            );
      } catch (_) {}
    }
    // The floor starts empty next session, orders paid earlier in the shift
    // included, whatever the per-payment "free the table" setting says.
    if (freeTables) {
      try {
        await _ref.read(floorServiceProvider).freeTablesForSession(sessionId);
      } catch (_) {}
    }
  }

  @override
  Future<void> publishClose(int sessionId,
      {DailySummaryReport? report}) async {
    // Best-effort: offline, the rows stay unsynced and the next sync sends
    // them. The session carries its Z label and, if it closed the Z, the
    // close fields — there is no separate Z push.
    try {
      final sync =
          _ref.read(dataSyncServiceFactoryProvider)(_ref.read(apiServiceProvider));
      await sync.syncSessionsBulk();
      await sync.syncCashMovementsBulk();
      await sync.syncOrdersBulk();
      await sync.syncTicketsBulk();
      // After orders + tickets, so each refund's order (and its server line
      // ids) already exist — and before the email report, whose refundsTotal
      // should reflect what the server now knows.
      await sync.syncRefundsBulk();
    } catch (_) {}

    // After the push, so the server already has what the report references.
    await _sendEmailReport(sessionId);

    // Fire-and-forget: the close must not wait on admin devices.
    if (report != null && report.sessions.isNotEmpty) {
      unawaited(notifySessionClosed(_ref.read, sessionId, report: report));
    }
  }

  Future<void> _sendEmailReport(int sessionId) async {
    try {
      final currency = _ref.read(settingsProvider).currency;
      final session = await _sessions.getSessionById(sessionId);
      final z = session?.zId == null
          ? null
          : await _ref.read(zServiceProvider).getById(session!.zId!);

      // The server's idempotency key is (tenant, sessionCode,
      // clientRequestId). Minting a fresh uuid per attempt would make a retry
      // — or a second close of the same session from Sessions Management —
      // look like a new request and send a duplicate email. So it is
      // generated once per session and kept in prefs until the server
      // accepts it.
      final prefs = _ref.read(sharedPreferencesProvider);
      final ridKey = 'email_report_rid_$sessionId';
      var rid = prefs.getString(ridKey);
      if (rid == null) {
        rid = const Uuid().v4();
        await prefs.setString(ridKey, rid);
      }

      final payload = await _ref
          .read(dailySummaryServiceProvider)
          .buildEmailReportPayload(
            sessionId,
            currency: currency,
            zNumber: z?.zSeq,
            clientRequestId: rid,
          );
      final sessionCode = (payload['session'] as Map)['code'] as String;
      await _ref
          .read(apiServiceProvider)
          .sendSessionEmailReport(sessionCode, payload);
      // Accepted (any of the five terminal statuses) — the key has done its
      // job.
      await prefs.remove(ridKey);
    } catch (e) {
      // Key deliberately left in prefs so the next attempt reuses it.
      Logger.instance
          .warning('email-report: failed for session $sessionId: $e');
    }
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

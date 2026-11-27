import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../domain/services/cash_session_service.dart';
import '../providers/database_providers.dart';
import '../providers/session_rules_provider.dart';
import '../providers/settings_provider.dart';
import 'activity_log_service.dart';
import 'api_service.dart';
import 'cash_movement_service.dart';
import 'daily_summary_service.dart';
import 'local_floor_service.dart';
import 'notification_params.dart';
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
  Future<OpenedSession> openForCashier({
    required SessionActor cashier,
    required double moneyAtStart,
    required bool isAdmin,
    int? zId,
  }) async {
    final cashierId = cashier.userId!;
    final log = _ref.read(activityLogServiceProvider);
    final existing = await _sessions.getActiveSession(cashierId);
    if (existing != null) {
      if (existing.status != 'paused') {
        return (session: existing, how: SessionOpening.continued);
      }
      await resume(existing.id);
      final resumed = (await _sessions.getSessionById(existing.id))!;
      await log.logSessionResume(
          userId: cashierId, username: cashier.username);
      return (session: resumed, how: SessionOpening.resumed);
    }

    await _sessions.checkOpenRules(
      _ref.read(sessionRulesProvider),
      isAdmin: isAdmin,
      cashierId: cashierId,
      moneyAtStart: moneyAtStart,
    );
    var session = await _sessions.startSession(
      cashierId: cashierId,
      moneyAtStart: moneyAtStart,
      posId: _ref.read(apiServiceProvider).getPosId(),
      // Each cashier brings their own float for now; nothing carries over
      // from the previous session.
      moneyEntered: moneyAtStart,
    );
    // Attach BEFORE the first push: the session carries its Z label (and, as
    // the Z's first session, its open mode) to the server.
    if (zId != null) {
      await _ref.read(zServiceProvider).attachSession(session.id, zId);
      session = (await _sessions.getSessionById(session.id))!;
    }
    // Best-effort: offline, isSynced stays false and syncSessionsBulk sends
    // it later.
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      await _ref
          .read(dataSyncServiceFactoryProvider)(ApiService(prefs))
          .syncSingleSession(session.id);
    } catch (_) {}
    await log.logSessionStart(userId: cashierId, username: cashier.username);
    // Fire-and-forget: the sign-in must not wait on admin devices.
    unawaited(_ref.read(notificationOutboxProvider).send(
          'POS_SESSION_OPENED',
          NotificationParams.sessionOpened(
            terminalName: _ref.read(apiServiceProvider).getPosName() ?? '',
            cashierName: cashier.username ?? '',
            cashierId: cashierId,
            openedAt: session.startedAt,
            startingBalance: moneyAtStart,
            currency: _ref.read(settingsProvider).currency,
          ),
          refId: session.id.toString(),
        ));
    return (session: session, how: SessionOpening.started);
  }

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
    SessionActor? closedBy,
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

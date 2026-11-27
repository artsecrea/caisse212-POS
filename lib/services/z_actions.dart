import 'dart:async';

import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart' as db;
import '../domain/services/day_service.dart';
import '../domain/models/session_rules.dart';
import '../providers/business_day_provider.dart';
import '../providers/database_providers.dart';
import '../providers/network_provider.dart';
import '../providers/session_rules_provider.dart';
import '../utils/admin_auth.dart' show userHasPermission;
import 'activity_log_service.dart';
import 'daily_summary_service.dart';
import 'pos_notifications.dart'
    show ProviderReader, notifySessionClosed, notifyZClosed;
import 'permission_service.dart' show Permissions;
import 'z_rules.dart';
import 'z_service.dart';

/// Z (day close) orchestration for the v3 contract: the standalone till's
/// [DayService] (`LocalDayService`) runs it on this till's database.
///
/// A Z is a (zDay, zSeq) label on sessions; the till owns the counter and the
/// server learns everything from the session push. See
/// `bms/docs/POS_Z_CONTRACT.md`.

/// Refresh the business-day definition and the terminal's Z rules from the
/// server. Best-effort and bounded: offline, the cached copies stand.
Future<void> refreshZConfig(ProviderReader read) async {
  if (!read(lastKnownOnlineStatusProvider)) return;
  final sync = read(dataSyncServiceProvider);
  try {
    final config = await sync
        .syncBusinessDayConfig()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (config != null) {
      await read(businessDayProvider.notifier).update(config);
    }
  } catch (_) {}
  try {
    final rules = await sync
        .syncSessionRules()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (rules != null) {
      await read(sessionRulesProvider.notifier).updateRules(rules);
    }
  } catch (_) {}
}

typedef _Planned = ({
  ZPlan plan,
  db.Z? localOpen,
  String? serverCloseMode,
  String currentZDay,
  ZSnapshot? server,
  List<Map<String, dynamic>> serverOpenSessions,
});

/// Ask the server where this terminal's counter stands, and plan from it.
Future<_Planned> _planZ(ProviderReader read) async {
  final zService = read(zServiceProvider);
  var currentZDay = read(businessDayProvider.notifier).currentZDay();

  ZSnapshot? server;
  String? serverCloseMode;
  var serverOpenSessions = const <Map<String, dynamic>>[];
  if (read(lastKnownOnlineStatusProvider)) {
    final cur = await read(apiServiceProvider)
        .fetchCurrentZ()
        .timeout(const Duration(seconds: 5), onTimeout: () => null);
    if (cur != null) {
      server = ZSnapshot.fromServer(cur);
      serverCloseMode = cur['closeMode']?.toString();
      final open = cur['openSessions'];
      if (open is List) {
        serverOpenSessions = [
          for (final o in open)
            if (o is Map) Map<String, dynamic>.from(o),
        ];
      }
      // The server computes the day in the tenant's timezone; prefer it.
      final sDay = cur['currentZDay']?.toString();
      if (sDay != null && parseZDay(sDay) != null) {
        if (sDay.substring(0, 10) != currentZDay) {
          Logger.instance.warning(
              'Z: server business day $sDay differs from local $currentZDay');
        }
        currentZDay = sDay.substring(0, 10);
      }
    }
  }

  final open = await zService.getOpenZ();
  final latest = await zService.latestZ();
  final plan = planZ(
    currentZDay: currentZDay,
    localOpen: open == null ? null : ZService.labelOf(open),
    localLatest: latest == null
        ? null
        : ZSnapshot(ZService.labelOf(latest),
            closed: latest.status == 'closed'),
    server: server,
  );
  return (
    plan: plan,
    localOpen: open,
    serverCloseMode: serverCloseMode,
    currentZDay: currentZDay,
    server: server,
    serverOpenSessions: serverOpenSessions,
  );
}

/// Close the sessions the server holds open but this till has no record of —
/// left behind by a reinstall. A new device has no count or tickets for them,
/// so they are closed (`autoClosed`), never continued. When their Z's day is
/// over, the last of them also closes that Z FORCED — but only for the
/// server's latest Z while it is still open: any other Z may already have a
/// closing session, and a second one would shadow its close.
Future<void> _closeServerOrphans(ProviderReader read, _Planned planned) async {
  if (planned.serverOpenSessions.isEmpty) return;
  final database = read(databaseProvider);
  final orphans = <Map<String, dynamic>>[];
  for (final o in planned.serverOpenSessions) {
    final code = o['code']?.toString();
    if (code == null) continue;
    final local = await (database.select(database.cashSessions)
          ..where((s) => s.code.equals(code)))
        .getSingleOrNull();
    if (local == null) orphans.add(o);
  }
  if (orphans.isEmpty) return;

  // Group by Z; the server lists them oldest first.
  final byZ = <String, List<Map<String, dynamic>>>{};
  for (final o in orphans) {
    final day = o['zDay']?.toString() ?? '';
    byZ.putIfAbsent('$day#${o['zSeq']}', () => []).add(o);
  }
  final api = read(apiServiceProvider);
  final now = DateTime.now().toIso8601String();
  final latest = planned.server;
  for (final group in byZ.values) {
    final day = group.first['zDay']?.toString() ?? '';
    final seq = group.first['zSeq'];
    final isOpenLatest = latest != null &&
        !latest.closed &&
        day.length >= 10 &&
        latest.label ==
            ZLabel(day.substring(0, 10),
                seq is num ? seq.toInt() : int.tryParse('$seq') ?? 1);
    final stale = isOpenLatest &&
        day.substring(0, 10).compareTo(planned.currentZDay) < 0;
    for (var i = 0; i < group.length; i++) {
      final closesZ = stale && i == group.length - 1;
      final code = group[i]['code'].toString();
      try {
        await api.closeServerSession(code, {
          'endedAt': now,
          'autoClosed': true,
          if (closesZ) ...{
            'isClosingSession': true,
            'zCloseMode': ZService.closeForced,
            'zClosedAt': now,
          },
        });
      } catch (e) {
        // Next login tries again; the server's own sweep covers stale Zs.
        Logger.instance.warning('Z: could not close orphan session $code: $e');
      }
    }
  }
}

/// Close whatever the plan says must go before a new Z can start.
Future<void> _applyPlanCloses(ProviderReader read, _Planned planned) async {
  await _closeServerOrphans(read, planned);
  final open = planned.localOpen;
  if (open == null) return;
  final zService = read(zServiceProvider);
  if (planned.plan.closeLocalAsServerClosed) {
    await zService.markClosedByServer(open.id,
        closeMode: planned.serverCloseMode);
  }
}

/// The Z the next session of [user] belongs to: the open one, a server Z to
/// adopt after a reinstall, or a new one — which must pass the terminal's
/// open rules. Throws [ZRuleViolation] when a new Z may not open by itself.
/// [superAdmin] (a master-password sign-in) holds every Z permission.
Future<db.Z> ensureZForSession(ProviderReader read,
    {required db.User user, bool superAdmin = false}) async {
  final zService = read(zServiceProvider);
  final planned = await _planZ(read);
  final plan = planned.plan;

  if (plan.action == ZPlanAction.continueOpen) {
    await _closeServerOrphans(read, planned);
    final z = planned.localOpen!;
    read(currentZProvider.notifier).state = z;
    return z;
  }

  // A new Z must be allowed BEFORE the stale one is closed, so a refusal
  // leaves the till exactly as it was.
  var usedOverride = false;
  if (plan.action == ZPlanAction.openNew) {
    usedOverride = _checkOpen(
      read,
      plan.next,
      explicitOpen: false,
      hasOpenPermission:
          superAdmin || userHasPermission(user, Permissions.zOpen),
      hasOverride: superAdmin || userHasPermission(user, Permissions.zOverride),
    );
  }

  await _applyPlanCloses(read, planned);

  final z = await zService.openZ(
    label: plan.next,
    createdBy: user.id,
    openMode: plan.action == ZPlanAction.adoptServer ? null : ZService.openAuto,
    posId: read(apiServiceProvider).getPosId(),
    openOverride: usedOverride,
  );
  read(currentZProvider.notifier).state = z;
  read(activityLogServiceProvider)
      .logZOpened(ZService.displayName(z), userId: user.id);
  return z;
}

/// A user deliberately opens the Z (the "Open Z" button, or MANUAL mode).
/// Returns the open Z — the existing one when a Z is already open.
Future<db.Z> openZManually(
  ProviderReader read, {
  required int userId,
  required bool hasOpenPermission,
  required bool hasOverride,
}) async {
  final planned = await _planZ(read);
  final plan = planned.plan;
  if (plan.action == ZPlanAction.continueOpen) {
    await _closeServerOrphans(read, planned);
    read(currentZProvider.notifier).state = planned.localOpen;
    return planned.localOpen!;
  }
  var usedOverride = false;
  if (plan.action == ZPlanAction.openNew) {
    usedOverride = _checkOpen(
      read,
      plan.next,
      explicitOpen: true,
      hasOpenPermission: hasOpenPermission,
      hasOverride: hasOverride,
    );
  }
  await _applyPlanCloses(read, planned);
  final z = await read(zServiceProvider).openZ(
        label: plan.next,
        createdBy: userId,
        openMode:
            plan.action == ZPlanAction.adoptServer ? null : ZService.openManual,
        posId: read(apiServiceProvider).getPosId(),
        openOverride: usedOverride,
      );
  read(currentZProvider.notifier).state = z;
  read(activityLogServiceProvider)
      .logZOpened(ZService.displayName(z), userId: userId);
  return z;
}

/// Whether [z] may be closed now (MANUAL / AUTO). Other sessions still open
/// do not block: the close ends them (`autoClosed`), so a session never
/// outlives its Z.
Future<ZRuleViolation?> zCloseBlock(
  ProviderReader read,
  db.Z z, {
  required bool hasClosePermission,
  required bool hasOverride,
}) async {
  final rules = read(sessionRulesProvider);
  final block = checkZClose(
    now: DateTime.now(),
    zDay: ZService.labelOf(z).zDay,
    startHour: read(businessDayProvider).startHour,
    earliestCloseTime: rules.zEarliestCloseTime,
    hasClosePermission: hasClosePermission,
    hasOverride: hasOverride,
  );
  return block == null
      ? null
      : ZRuleViolation(block, limit: rules.zEarliestCloseTime);
}

/// Whether closing [z] now is only allowed through `pos:z:override` — i.e.
/// it is before `zEarliestCloseTime`. Recorded on the closing session.
bool zCloseNeedsOverride(ProviderReader read, db.Z z) =>
    checkZClose(
      now: DateTime.now(),
      zDay: ZService.labelOf(z).zDay,
      startHour: read(businessDayProvider).startHour,
      earliestCloseTime: read(sessionRulesProvider).zEarliestCloseTime,
      hasClosePermission: true,
      hasOverride: false,
      ) ==
    ZRuleBlock.tooEarlyToClose;

/// Throws [ZRuleViolation] when [label] may not open; returns whether it
/// opens only thanks to `pos:z:override`.
bool _checkOpen(
  ProviderReader read,
  ZLabel label, {
  required bool explicitOpen,
  required bool hasOpenPermission,
  required bool hasOverride,
}) {
  final rules = read(sessionRulesProvider);
  ZRuleBlock? check(bool override) => checkZOpen(
        now: DateTime.now(),
        zDay: label.zDay,
        startHour: read(businessDayProvider).startHour,
        openMode: rules.zOpenMode,
        cantOpenAfter: rules.zCantOpenAfter,
        explicitOpen: explicitOpen,
        hasOpenPermission: hasOpenPermission,
        hasOverride: override,
      );
  final block = check(hasOverride);
  if (block != null) throw ZRuleViolation(block, limit: rules.zCantOpenAfter);
  return hasOverride && check(false) == ZRuleBlock.tooLateToOpen;
}

/// Whether a session closing now should ASK to close the Z (AUTO_AFTER_HOUR).
bool zAutoCloseDueFor(ProviderReader read, db.Z z) {
  final SessionRules rules = read(sessionRulesProvider);
  return zAutoCloseDue(
    now: DateTime.now(),
    zDay: ZService.labelOf(z).zDay,
    startHour: read(businessDayProvider).startHour,
    closeMode: rules.zCloseMode,
    autoCloseAfter: rules.zAutoCloseAfter,
  );
}

/// `BY_SESSION`: whether closing [sessionId] closes [z] with it.
Future<bool> zClosesWithSessionFor(
    ProviderReader read, db.Z z, int sessionId) async {
  final others =
      await read(zServiceProvider).openSessionsOf(z.id, except: sessionId);
  return zClosesWithSession(
    closeMode: read(sessionRulesProvider).zCloseMode,
    otherOpenSessions: others.length,
    tooEarly: zCloseNeedsOverride(read, z),
  );
}

/// Close [z] with [closeMode] (rules already checked by the caller), then
/// push its closing session. Does not print — callers drive the paper.
Future<void> closeZNow(
  ProviderReader read,
  db.Z z, {
  required String closeMode,
  int? endedBy,
}) async {
  // The sessions the close is about to end for their cashiers: each still
  // owes the admin its own POS_SESSION_CLOSED card.
  final autoEnded = await read(zServiceProvider).openSessionsOf(z.id);
  await read(zServiceProvider).closeZ(
        zId: z.id,
        closeMode: closeMode,
        sessionService: read(sessionServiceProvider),
        endedBy: endedBy,
        closeOverride:
            closeMode != ZService.closeForced && zCloseNeedsOverride(read, z),
      );
  read(currentZProvider.notifier).state = null;
  for (final s in autoEnded) {
    unawaited(notifySessionClosed(read, s.id));
  }
  unawaited(notifyZClosed(read, z.id));

  final closed = await read(zServiceProvider).getById(z.id);
  final total = closed?.totalPaid;
  read(activityLogServiceProvider).logZClosed(
        ZService.displayName(z),
        total: total?.toStringAsFixed(2),
        userId: endedBy,
      );
  await _pushSessions(read);
}

Future<void> _pushSessions(ProviderReader read) async {
  try {
    await read(dataSyncServiceProvider)
        .syncSessionsBulk()
        .timeout(const Duration(seconds: 15));
  } catch (e) {
    // Offline: the closing session stays unsynced and the next sync sends it.
    Logger.instance.warning('Z close push deferred: $e');
  }
}

/// An X (mid-Z snapshot) or the Z of [zId], summed from its sessions.
Future<ZReport?> zReportFor(
  ProviderReader read,
  int zId, {
  required bool isX,
}) async {
  final database = read(databaseProvider);
  final zService = read(zServiceProvider);
  final sessions = await zService.sessionsForZ(zId);
  if (sessions.isEmpty) return null;
  final z = await zService.getById(zId);
  final start = sessions
      .map((s) => s.startedAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  // A reprint states the period the Z actually covered, not today's clock.
  final end = isX ? DateTime.now() : (z?.endedAt ?? DateTime.now());

  final report = await DailySummaryService(database).generateReport(
    startDate: start,
    endDate: end,
    sessionIds: sessions.map((s) => s.id).toList(),
  );
  return (report: report, zLabel: z == null ? null : ZService.displayName(z));
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart' as db;
import '../providers/database_providers.dart';
import '../providers/network_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/z_day_provider.dart';
import 'activity_log_service.dart';
import 'daily_summary_service.dart';

/// Shared open/close/report orchestration for the Z (shift) entity, reused by
/// the login auto-open, the login-screen Z dialog, and the in-app close button.

/// Ensure a Z is open for this terminal and set it active. Adopts a server-side
/// open Z when one exists (uniqueness), else opens a new local Z. Returns it.
Future<db.Z> openActiveZ(WidgetRef ref, {required int createdBy}) async {
  final zService = ref.read(zServiceProvider);
  final api = ref.read(apiServiceProvider);
  final posId = api.getPosId();

  var z = await zService.getOpenZ(posId: posId);
  final freshlyOpened = z == null;
  if (z == null) {
    // Uniqueness: adopt the server's open Z for this POS if there is one.
    if (ref.read(lastKnownOnlineStatusProvider)) {
      try {
        final serverZ = await api.fetchOpenZ();
        if (serverZ != null && serverZ['code'] != null) {
          z = await zService.adoptServerZ(serverZ, posId: posId);
        }
      } catch (_) {/* best-effort; local open still applies */}
    }
    final settings = ref.read(settingsProvider);
    final dayState = ref.read(zDayStateProvider);
    z ??= await zService.ensureOpenZ(
      createdBy: createdBy,
      posId: posId,
      codePrefix: settings.zCodePrefix,
      number: dayState.zNumber == 0 ? 1 : dayState.zNumber,
      businessDay: zBusinessDayKey(DateTime.now(), settings.zDayStartHour),
    );
  }
  ref.read(currentZProvider.notifier).state = z;
  // Audit: only when this call actually opened/adopted a Z (not when one was
  // already open for the terminal), so repeated logins don't spam the log.
  if (freshlyOpened) {
    ref.read(activityLogServiceProvider).logZOpened(z.code, userId: createdBy);
  }
  return z;
}

/// Close the active Z (auto-closing its open sessions) and clear the active-Z /
/// active-session state. Does NOT print — the caller offers Print Z / Print X
/// buttons in the close dialog.
Future<void> closeActiveZ(WidgetRef ref, {int? endedBy}) async {
  final zService = ref.read(zServiceProvider);
  final z = ref.read(currentZProvider) ?? await zService.getOpenZ();
  if (z == null) return;
  await zService.closeZ(
    zId: z.id,
    sessionService: ref.read(sessionServiceProvider),
    endedBy: endedBy,
  );
  ref.read(currentZProvider.notifier).state = null;
  ref.read(currentSessionProvider.notifier).state = null;

  // Audit: capture the closed Z with its aggregated total (re-read post-close).
  final closed = await zService.getById(z.id);
  final currency = ref.read(settingsProvider).currency;
  final total = closed?.totalPaid;
  ref.read(activityLogServiceProvider).logZClosed(
        z.code,
        total: total == null ? null : '${total.toStringAsFixed(2)} $currency',
        userId: endedBy,
      );
}

/// Close the active Z **and** mark the terminal's business day closed, so no
/// non-admin can log in again until the day rolls over (or a manager reopens).
/// Returns whether a Z was actually closed. Does not print — the caller drives
/// the X / Z / extra tickets so paper never waits on this.
///
/// Must run AFTER the cashier's session has been ended with its counted cash:
/// [ZService.closeZ] auto-ends any still-open session with no count, which
/// would silently discard the variance.
Future<bool> closeBusinessDay(
  WidgetRef ref, {
  int? endedBy,
  String? endedByName,
}) async {
  final settings = ref.read(settingsProvider);
  final today = zBusinessDayKey(DateTime.now(), settings.zDayStartHour);
  final zService = ref.read(zServiceProvider);
  final z = ref.read(currentZProvider) ?? await zService.getOpenZ();

  if (z != null) {
    await closeActiveZ(ref, endedBy: endedBy);
  }

  await ref.read(zDayStateProvider.notifier).markDayClosed(
        today: today,
        byUserId: endedBy,
        byName: endedByName,
        zCode: z?.code,
      );
  ref.read(activityLogServiceProvider).logZDayClosed(
        today,
        zCode: z?.code,
        userId: endedBy,
        username: endedByName,
      );
  return z != null;
}

/// Print an X (mid-shift snapshot) or Z (close) report spanning every session
/// in [zId]. Returns whether it printed.
Future<bool> printZReport(WidgetRef ref, int zId, {required bool isX}) async {
  final database = ref.read(databaseProvider);
  final sessions = await (database.select(database.cashSessions)
        ..where((s) => s.zId.equals(zId)))
      .get();
  if (sessions.isEmpty) return false;
  final ids = sessions.map((s) => s.id).toList();
  final start = sessions
      .map((s) => s.startedAt)
      .reduce((a, b) => a.isBefore(b) ? a : b);

  // A REPRINT of a closed Z must state the period that Z actually covered.
  // `now` is right for an X (the snapshot ends at the moment it is taken) and
  // wrong for anything reprinted later — it used to put today's clock on a Z
  // from last week, which the banded report shows on its "Période" line.
  final z = await (database.select(database.zs)..where((r) => r.id.equals(zId)))
      .getSingleOrNull();
  final end = isX ? DateTime.now() : (z?.endedAt ?? DateTime.now());

  final report = await DailySummaryService(database).generateReport(
    startDate: start,
    endDate: end,
    sessionIds: ids,
  );
  return ref
      .read(printingServiceProvider)
      .printDailySummaryReport(report: report, reportType: isX ? 'X' : 'Z');
}

import 'dart:io';
import 'dart:ui';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database/app_database.dart';
import '../data/database/tables/activity_log_table.dart';
import '../providers/database_providers.dart';
import '../providers/settings_provider.dart';
import '../utils/app_localizations.dart';

/// Records human-readable user-action phrases (in the configured logging
/// language) to the [ActivityLogs] table, and handles rolling 30-day
/// retention with export to a text file on the Desktop.
class ActivityLogService {
  final Ref _ref;
  final AppDatabase _db;

  ActivityLogService(this._ref, this._db);

  static const int retentionDays = 30;

  /// Render [l10nKey] in the logging language, substitute {0},{1}… with [args],
  /// and insert a log row. Never throws — logging must not break the action.
  Future<void> log(
    String actionType,
    String l10nKey,
    List<Object?> args, {
    int? userId,
    String? username,
  }) async {
    try {
      final lang = _ref.read(settingsProvider).loggingLanguage;
      final l10n = AppLocalizations(Locale(lang));
      var phrase = l10n.translate(l10nKey);
      for (var i = 0; i < args.length; i++) {
        phrase = phrase.replaceAll('{$i}', args[i]?.toString() ?? '');
      }

      // Activity logs intentionally capture the legal full name (not the
      // cashier-set displayName/nickname) so the audit trail can't be
      // rewritten by someone changing their display label later.
      var name = username;
      if (name == null && userId != null) {
        final user = await (_db.select(_db.users)
              ..where((u) => u.id.equals(userId)))
            .getSingleOrNull();
        if (user != null) {
          name = '${user.firstName} ${user.lastName}'.trim();
        }
      }

      await _db.into(_db.activityLogs).insert(
            ActivityLogsCompanion.insert(
              actionType: actionType,
              phrase: phrase,
              userId: Value(userId),
              username: Value(name),
            ),
          );
    } catch (e) {
      debugPrint('ActivityLogService.log failed: $e');
    }
  }

  // ── Convenience wrappers ───────────────────────────────────────────────

  Future<void> logOrderCreated(String orderCode, {int? userId, String? username}) =>
      log(ActivityAction.orderCreated, 'audit_order_created', [orderCode, username ?? ''],
          userId: userId, username: username);

  Future<void> logOrderUpdated(String orderCode, {int? userId, String? username}) =>
      log(ActivityAction.orderUpdated, 'audit_order_updated', [orderCode, username ?? ''],
          userId: userId, username: username);

  /// Audit line listing the items dropped from an order when the cashier
  /// removed a line (or reduced its quantity) and re-saved. [summary] is the
  /// pre-formatted list, e.g. "2× Coffee (Large), 1× Pizza".
  Future<void> logOrderItemsRemoved(String orderCode, String summary,
          {int? userId, String? username}) =>
      log(ActivityAction.orderUpdated, 'audit_order_items_removed',
          [orderCode, summary, username ?? ''],
          userId: userId, username: username);

  Future<void> logOrderConfirmed(String orderCode, {int? userId, String? username}) =>
      log(ActivityAction.orderConfirmed, 'audit_order_confirmed', [orderCode, username ?? ''],
          userId: userId, username: username);

  Future<void> logOrderCancelled(String orderCode,
      {int? userId, String? username, String? reason}) {
    final hasReason = reason != null && reason.trim().isNotEmpty;
    return log(
      ActivityAction.orderCancelled,
      hasReason ? 'audit_order_cancelled_reason' : 'audit_order_cancelled',
      hasReason ? [orderCode, username ?? '', reason] : [orderCode, username ?? ''],
      userId: userId,
      username: username,
    );
  }

  Future<void> logOrderStatusChanged(String orderCode, String from, String to,
          {int? userId, String? username}) =>
      log(ActivityAction.orderStatusChanged, 'audit_order_status_changed',
          [orderCode, from, to, username ?? ''],
          userId: userId, username: username);

  Future<void> logOrderTransferred(String orderCode, String fromTable, String toTable,
          {int? userId, String? username}) =>
      log(ActivityAction.orderTransferred, 'audit_order_transferred',
          [orderCode, fromTable, toTable, username ?? ''],
          userId: userId, username: username);

  Future<void> logPayment(String amount, String orderCode,
          {int? userId, String? username}) =>
      log(ActivityAction.payment, 'audit_payment', [amount, orderCode, username ?? ''],
          userId: userId, username: username);

  Future<void> logLogin({int? userId, String? username}) =>
      log(ActivityAction.login, 'audit_login', [username ?? ''],
          userId: userId, username: username);

  Future<void> logLogout({int? userId, String? username}) =>
      log(ActivityAction.logout, 'audit_logout', [username ?? ''],
          userId: userId, username: username);

  Future<void> logSessionStart({int? userId, String? username}) =>
      log(ActivityAction.sessionStart, 'audit_session_start', [username ?? ''],
          userId: userId, username: username);

  Future<void> logSessionPause({int? userId, String? username}) =>
      log(ActivityAction.sessionPause, 'audit_session_pause', [username ?? ''],
          userId: userId, username: username);

  Future<void> logSessionResume({int? userId, String? username}) =>
      log(ActivityAction.sessionResume, 'audit_session_resume', [username ?? ''],
          userId: userId, username: username);

  Future<void> logSessionEnd({int? userId, String? username}) =>
      log(ActivityAction.sessionEnd, 'audit_session_end', [username ?? ''],
          userId: userId, username: username);

  /// Records that [username] upgraded to admin mode using [adminUsername]'s password.
  Future<void> logAdminElevationGranted({
    int? userId,
    String? username,
    required String adminUsername,
  }) =>
      log(
        ActivityAction.adminElevationGranted,
        'audit_admin_elevation_granted',
        [username ?? '', adminUsername],
        userId: userId,
        username: username,
      );

  /// Records that [username] exited admin mode.
  Future<void> logAdminElevationRevoked({int? userId, String? username}) =>
      log(ActivityAction.adminElevationRevoked, 'audit_admin_elevation_revoked',
          [username ?? ''],
          userId: userId, username: username);

  // ── Queries ────────────────────────────────────────────────────────────

  /// Paginated, server-filtered query for the logs screen. Newest first.
  /// [search] matches `phrase` or `username` (case-insensitive). Returns at most
  /// [limit] rows starting from [offset].
  Future<List<ActivityLog>> getLogsPage({
    DateTime? from,
    DateTime? to,
    String? search,
    int limit = 50,
    int offset = 0,
  }) {
    final query = _db.select(_db.activityLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
      ..limit(limit, offset: offset);
    if (from != null) {
      query.where((t) => t.timestamp.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((t) => t.timestamp.isSmallerOrEqualValue(to));
    }
    final q = search?.trim();
    if (q != null && q.isNotEmpty) {
      final pattern = '%${q.toLowerCase()}%';
      query.where((t) =>
          t.phrase.lower().like(pattern) | t.username.lower().like(pattern));
    }
    return query.get();
  }

  /// Live stream of logs (newest first), optionally bounded by a date range.
  Stream<List<ActivityLog>> watchLogs({DateTime? from, DateTime? to}) {
    final query = _db.select(_db.activityLogs)
      ..orderBy([(t) => OrderingTerm.desc(t.timestamp)]);
    if (from != null) {
      query.where((t) => t.timestamp.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where((t) => t.timestamp.isSmallerOrEqualValue(to));
    }
    return query.watch();
  }

  // ── Export & retention ─────────────────────────────────────────────────

  String _formatLine(ActivityLog l) {
    final ts = l.timestamp.toIso8601String();
    return '$ts  ${l.phrase}';
  }

  /// Resolve a writable export directory: the user's Desktop, else the app
  /// Documents directory as a fallback.
  Future<Directory> _exportDirectory() async {
    final home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final desktop = Directory(p.join(home, 'Desktop'));
      try {
        if (await desktop.exists()) return desktop;
      } catch (_) {/* fall through */}
    }
    return getApplicationDocumentsDirectory();
  }

  /// Export the current table contents to a timestamped file on the Desktop.
  /// Returns the number of rows written.
  Future<int> exportNow() async {
    final logs = await (_db.select(_db.activityLogs)
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
        .get();
    if (logs.isEmpty) return 0;

    final dir = await _exportDirectory();
    final now = DateTime.now();
    final stamp =
        '${now.year}-${_pad2(now.month)}-${_pad2(now.day)}_${_pad2(now.hour)}${_pad2(now.minute)}';
    final file = File(p.join(dir.path, 'caisse212_activity_log_$stamp.txt'));
    final buffer = StringBuffer()
      ..writeln('caisse212 activity log export — ${now.toIso8601String()}')
      ..writeln('-----------------------------------------------------------');
    for (final l in logs) {
      buffer.writeln(_formatLine(l));
    }
    await file.writeAsString(buffer.toString());
    return logs.length;
  }

  static const String _lastPurgeDateKey = 'last_log_purge_date';

  /// Run [purgeAndArchive] at most once per calendar day (date-gated via prefs).
  /// Safe to call on every app start.
  Future<void> purgeIfDue() async {
    try {
      final prefs = _ref.read(sharedPreferencesProvider);
      final lastStr = prefs.getString(_lastPurgeDateKey);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final last = lastStr != null ? DateTime.tryParse(lastStr) : null;
      final due = last == null ||
          today.isAfter(DateTime(last.year, last.month, last.day));
      if (!due) return;
      await purgeAndArchive();
      await prefs.setString(_lastPurgeDateKey, now.toIso8601String());
    } catch (e) {
      debugPrint('ActivityLogService.purgeIfDue failed: $e');
    }
  }

  /// Rolling retention: append rows older than [retentionDays] to a cumulative
  /// Desktop archive file, then delete them from the table.
  Future<void> purgeAndArchive() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
      final old = await (_db.select(_db.activityLogs)
            ..where((t) => t.timestamp.isSmallerThanValue(cutoff))
            ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
          .get();
      if (old.isEmpty) return;

      final dir = await _exportDirectory();
      final file = File(p.join(dir.path, 'caisse212_activity_log.txt'));
      final buffer = StringBuffer();
      for (final l in old) {
        buffer.writeln(_formatLine(l));
      }
      await file.writeAsString(buffer.toString(), mode: FileMode.append);

      await (_db.delete(_db.activityLogs)
            ..where((t) => t.timestamp.isSmallerThanValue(cutoff)))
          .go();
    } catch (e) {
      debugPrint('ActivityLogService.purgeAndArchive failed: $e');
    }
  }

  String _pad2(int n) => n.toString().padLeft(2, '0');
}

final activityLogServiceProvider = Provider<ActivityLogService>((ref) {
  return ActivityLogService(ref, ref.watch(databaseProvider));
});

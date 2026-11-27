import 'dart:convert';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import '../domain/models/z_day_option.dart';
import 'session_service.dart';
import 'z_rules.dart';
import '../domain/services/z_queries.dart';

/// The till's local Z records (contract v3): one open Z at a time, each a
/// (zDay, zSeq) label over a run of cash sessions. Nothing here talks to the
/// server — the Z reaches it through the fields its sessions carry.
class ZService implements ZQueries {
  final AppDatabase _database;

  ZService(this._database);

  static const String openAuto = 'AUTO';
  static const String openManual = 'MANUAL';
  static const String closeManual = 'MANUAL';
  static const String closeAuto = 'AUTO';
  static const String closeForced = 'FORCED';

  /// Local row key. Never sent: the server keys a Z by (terminal, zDay, zSeq).
  String _generateCode(ZLabel label) {
    final now = DateTime.now();
    final t = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final suffix = now.microsecond.toString().padLeft(3, '0').substring(0, 3);
    return 'Z-${label.zDay.replaceAll('-', '')}-${label.zSeq}-$t$suffix';
  }

  /// The business day of [z]: its stored label, or its opening calendar day on
  /// a row too old to have one.
  static DateTime zDayOf(Z z) =>
      parseZDay(z.zDay) ??
      DateTime(z.startedAt.year, z.startedAt.month, z.startedAt.day);

  static ZLabel labelOf(Z z) => ZLabel(formatZDay(zDayOf(z)), z.zSeq);

  /// "2026-09-25 · Z1" — how a Z is named on screen and on paper.
  static String displayName(Z z) {
    final l = labelOf(z);
    return '${l.zDay} · Z${l.zSeq}';
  }

  /// The open Z as it changes: for screens that show it before the current
  /// Z is known (the login screen).
  @override
  Stream<Z?> watchOpenZ() => (_database.select(_database.zs)
        ..where((z) => z.status.equals('open'))
        ..orderBy([(z) => OrderingTerm.desc(z.startedAt)])
        ..limit(1))
      .watchSingleOrNull();

  @override
  Future<Z?> getOpenZ() => (_database.select(_database.zs)
        ..where((z) => z.status.equals('open'))
        ..orderBy([(z) => OrderingTerm.desc(z.startedAt)])
        ..limit(1))
      .getSingleOrNull();

  /// Newest Z of any status, by label.
  Future<Z?> latestZ() => (_database.select(_database.zs)
        ..orderBy([
          (z) => OrderingTerm.desc(z.zDay),
          (z) => OrderingTerm.desc(z.zSeq),
          (z) => OrderingTerm.desc(z.startedAt),
        ])
        ..limit(1))
      .getSingleOrNull();

  @override
  Future<Z?> getById(int zId) => (_database.select(_database.zs)
        ..where((z) => z.id.equals(zId)))
      .getSingleOrNull();

  /// Most recent Zs (open + closed), newest first — for the history list.
  @override
  Future<List<Z>> recentZs({int limit = 25}) => (_database.select(_database.zs)
        ..orderBy([
          (z) => OrderingTerm.desc(z.zDay),
          (z) => OrderingTerm.desc(z.zSeq),
          (z) => OrderingTerm.desc(z.startedAt),
        ])
        ..limit(limit))
      .get();

  /// Every CLOSED business day that has at least one cash session, newest
  /// first.
  ///
  /// A Z is only printable once the day is over on paper: a day still holding
  /// an open or paused session, or a Z that has not been closed, is left out —
  /// its figures are not final, and a Z printed from them would be a legal
  /// document that later disagrees with the real one. Its X is always there.
  ///
  /// Days are business days: a session belongs to its Z's zDay, and a legacy
  /// session with no Z to the day it opened.
  ///
  /// Capped because this feeds a dropdown, not an archive browser; a shop
  /// wanting an older day has the sessions screen. The cap is generous enough
  /// to cover a quarter of trading.
  @override
  Future<List<ZDayOption>> zDayOptions({int limitDays = 120}) async {
    final sessions = await (_database.select(_database.cashSessions)
          ..orderBy([(s) => OrderingTerm.desc(s.startedAt)]))
        .get();

    final zs = await _database.select(_database.zs).get();
    final zById = {for (final z in zs) z.id: z};

    final byDay = <DateTime, List<CashSession>>{};
    final unfinished = <DateTime>{};
    for (final s in sessions) {
      final z = s.zId == null ? null : zById[s.zId];
      final d = z != null
          ? zDayOf(z)
          : DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day);
      byDay.putIfAbsent(d, () => []).add(s);
      if (s.status != 'ended') unfinished.add(d);
    }

    // Z rows are matched by their business day. A day with several Zs names
    // the first; the report itself covers every session of the day.
    final zByDay = <DateTime, Z>{};
    for (final z in zs) {
      final d = zDayOf(z);
      if (z.status != 'closed') unfinished.add(d);
      final held = zByDay[d];
      if (held == null || z.zSeq < held.zSeq) zByDay[d] = z;
    }

    final days = byDay.keys.where((d) => !unfinished.contains(d)).toList()
      ..sort((a, b) => b.compareTo(a));
    return [
      for (final day in days.take(limitDays))
        ZDayOption(
          day: day,
          sessionIds: [for (final s in byDay[day]!) s.id],
          sessionCodes: [for (final s in byDay[day]!) s.code],
          zCode: zByDay[day]?.code,
          zNumber: zByDay[day]?.zSeq,
        ),
    ];
  }

  /// True while the till is still trading: a Z is open, or a cash session is
  /// active or paused. The Z report is the closing document, so it is not
  /// printable until then — mid-shift figures are the X report's job.
  @override
  Future<bool> reportBlockedByOpenShift() async {
    final openZ = await (_database.select(_database.zs)
          ..where((z) => z.status.equals('open'))
          ..limit(1))
        .getSingleOrNull();
    if (openZ != null) return true;
    final running = await (_database.select(_database.cashSessions)
          ..where((s) => s.status.isIn(const ['active', 'paused']))
          ..limit(1))
        .getSingleOrNull();
    return running != null;
  }

  /// Open a Z under [label]. [openMode] is null for a Z adopted from the
  /// server, whose opening session is already there.
  ///
  /// [openOverride]: opened past `zCantOpenAfter` under `pos:z:override`.
  Future<Z> openZ({
    required ZLabel label,
    required int createdBy,
    String? openMode,
    int? posId,
    bool openOverride = false,
  }) async {
    final existing = await getOpenZ();
    if (existing != null) return existing;
    final id = await _database.into(_database.zs).insert(
          ZsCompanion.insert(
            id: const Value.absent(),
            code: _generateCode(label),
            posId: Value(posId),
            createdBy: createdBy,
            startedAt: Value(DateTime.now()),
            status: const Value('open'),
            zDay: Value(label.zDay),
            zSeq: Value(label.zSeq),
            openMode: Value(openMode),
            openOverride: Value(openOverride),
          ),
        );
    return (await getById(id))!;
  }

  /// Link [sessionId] to [zId]. The first session of a Z that this till
  /// opened carries its open mode, which is how the server learns the Z began.
  Future<void> attachSession(int sessionId, int zId) async {
    final z = await getById(zId);
    final earlier = await (_database.select(_database.cashSessions)
          ..where((s) => s.zId.equals(zId) & s.id.isNotValue(sessionId)))
        .get();
    final isOpener = earlier.isEmpty && z?.openMode != null;
    await (_database.update(_database.cashSessions)
          ..where((s) => s.id.equals(sessionId)))
        .write(CashSessionsCompanion(
      zId: Value(zId),
      zOpenMode: isOpener ? Value(z!.openMode) : const Value.absent(),
      zOverride: isOpener && z!.openOverride
          ? const Value(true)
          : const Value.absent(),
      isSynced: const Value(false),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// All sessions that belong to [zId], oldest first.
  @override
  Future<List<CashSession>> sessionsForZ(int zId) =>
      (_database.select(_database.cashSessions)
            ..where((s) => s.zId.equals(zId))
            ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
          .get();

  /// Sessions of [zId] still active or paused, other than [except].
  @override
  Future<List<CashSession>> openSessionsOf(int zId, {int? except}) async {
    final all = await sessionsForZ(zId);
    return all
        .where((s) =>
            (s.status == 'active' || s.status == 'paused') && s.id != except)
        .toList();
  }

  /// Close a Z.
  ///
  /// A session never outlives its Z: every session still open or paused —
  /// other cashiers' included — is ended first, uncounted and flagged
  /// `autoClosed`. The session ended LAST is then flagged as the closing one
  /// and marked unsynced: closing a Z on the server means re-pushing that
  /// session with the close fields, which the server fills once even on a
  /// session it already has closed. [closeOverride]: closed before
  /// `zEarliestCloseTime` under `pos:z:override`.
  Future<void> closeZ({
    required int zId,
    required String closeMode,
    required SessionService sessionService,
    int? endedBy,
    bool closeOverride = false,
  }) async {
    for (final s in await openSessionsOf(zId)) {
      await sessionService.endSession(sessionId: s.id, autoClosed: true);
    }

    final sessions = await sessionsForZ(zId);
    final byEnd = [...sessions]..sort((a, b) =>
        (a.endedAt ?? a.startedAt).compareTo(b.endedAt ?? b.startedAt));
    final now = DateTime.now();
    var totalPaid = 0.0;
    for (final s in sessions) {
      totalPaid += s.totalPaid ?? 0.0;
    }

    await _database.transaction(() async {
      if (byEnd.isNotEmpty) {
        await (_database.update(_database.cashSessions)
              ..where((s) => s.id.equals(byEnd.last.id)))
            .write(CashSessionsCompanion(
          isClosingSession: const Value(true),
          zOverride: closeOverride ? const Value(true) : const Value.absent(),
          isSynced: const Value(false),
          updatedAt: Value(now),
        ));
      }
      await (_database.update(_database.zs)..where((z) => z.id.equals(zId)))
          .write(ZsCompanion(
        status: const Value('closed'),
        endedAt: Value(now),
        endedBy: Value(endedBy),
        closeMode: Value(closeMode),
        totalPaid: Value(totalPaid),
        details: Value(jsonEncode({
          'sessionCount': sessions.length,
          'sessionCodes': sessions.map((s) => s.code).toList(),
        })),
        updatedAt: Value(now),
      ));
    });
  }

  /// The server already has this Z closed (another path closed it, e.g. its
  /// stale-day sweep). Close the local row to match — nothing to push.
  Future<void> markClosedByServer(int zId, {String? closeMode}) async {
    await (_database.update(_database.zs)..where((z) => z.id.equals(zId)))
        .write(ZsCompanion(
      status: const Value('closed'),
      endedAt: Value(DateTime.now()),
      closeMode: Value(closeMode ?? closeForced),
      updatedAt: Value(DateTime.now()),
    ));
  }
}

import 'dart:convert';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import 'session_service.dart';

/// Manages the "Z" shift entity: one open Z per POS terminal, owning one or more
/// cash sessions. Mirrors [SessionService] conventions (code generation,
/// unique code, isSynced push flag).
class ZService {
  final AppDatabase _database;

  ZService(this._database);

  /// Z code — `<prefix>-YYYYMMDD-HHMMSS-XXX` (prefix configurable, default 'Z').
  String _generateCode(String prefix) {
    final p = prefix.trim().isEmpty ? 'Z' : prefix.trim();
    final now = DateTime.now();
    final d = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final t = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final suffix = now.microsecond.toString().padLeft(3, '0').substring(0, 3);
    return '$p-$d-$t-$suffix';
  }

  /// The currently-open Z for this terminal (or null). When [posId] is given,
  /// it's matched (an open Z with a null posId also counts, so a Z opened
  /// before the terminal id was known is still adopted).
  Future<Z?> getOpenZ({int? posId}) async {
    final open = await (_database.select(_database.zs)
          ..where((z) => z.status.equals('open'))
          ..orderBy([(z) => OrderingTerm.desc(z.startedAt)]))
        .get();
    if (open.isEmpty) return null;
    if (posId == null) return open.first;
    return open.firstWhere(
      (z) => z.posId == null || z.posId == posId,
      orElse: () => open.first,
    );
  }

  /// Returns this terminal's open Z, creating one if none exists.
  ///
  /// [number] / [businessDay] come from the terminal's `ZDayState` and are
  /// stamped into `details` so the Z number reaches the backend without a
  /// schema or API change.
  Future<Z> ensureOpenZ({
    required int createdBy,
    int? posId,
    String codePrefix = 'Z',
    int? number,
    String? businessDay,
  }) async {
    final existing = await getOpenZ(posId: posId);
    if (existing != null) return existing;

    final now = DateTime.now();
    final details = <String, dynamic>{
      if (number != null) 'number': number,
      if (businessDay != null) 'businessDay': businessDay,
    };
    final id = await _database.into(_database.zs).insert(
          ZsCompanion.insert(
            id: const Value.absent(),
            code: _generateCode(codePrefix),
            posId: Value(posId),
            createdBy: createdBy,
            startedAt: Value(now),
            status: const Value('open'),
            details:
                details.isEmpty ? const Value.absent() : Value(jsonEncode(details)),
          ),
        );
    return (await _database.select(_database.zs)..where((z) => z.id.equals(id)))
        .getSingle();
  }

  /// The Z number stamped into `details` at open (null on legacy rows opened
  /// before Z-day numbering existed).
  static int? numberOf(Z? z) {
    if (z?.details == null) return null;
    try {
      final decoded = jsonDecode(z!.details!);
      if (decoded is Map) return (decoded['number'] as num?)?.toInt();
    } catch (_) {}
    return null;
  }

  Future<Z?> getById(int zId) => (_database.select(_database.zs)
        ..where((z) => z.id.equals(zId)))
      .getSingleOrNull();

  /// Most-recent Z's (open + closed), newest first — for the history list in
  /// the Z management dialog.
  Future<List<Z>> recentZs({int limit = 25}) =>
      (_database.select(_database.zs)
            ..orderBy([(z) => OrderingTerm.desc(z.startedAt)])
            ..limit(limit))
          .get();

  /// Link a cash session to its Z (shift).
  Future<void> attachSession(int sessionId, int zId) async {
    await (_database.update(_database.cashSessions)
          ..where((s) => s.id.equals(sessionId)))
        .write(CashSessionsCompanion(
      zId: Value(zId),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Insert (or return existing) a Z that the SERVER already has open for this
  /// terminal, so we adopt it instead of opening a duplicate. Marked synced.
  Future<Z> adoptServerZ(Map<String, dynamic> data, {int? posId}) async {
    final code = data['code'] as String;
    final existing = await (_database.select(_database.zs)
          ..where((z) => z.code.equals(code)))
        .getSingleOrNull();
    if (existing != null) return existing;
    final startedAt =
        DateTime.tryParse('${data['startedAt'] ?? ''}') ?? DateTime.now();
    // Carry the server's details across (it holds the Z number) so a Z adopted
    // on a second terminal keeps its original numbering.
    String? details;
    final raw = data['details'];
    if (raw is String && raw.trim().isNotEmpty) {
      details = raw;
    } else if (raw is Map) {
      details = jsonEncode(raw);
    }
    final id = await _database.into(_database.zs).insert(
          ZsCompanion.insert(
            id: const Value.absent(),
            code: code,
            posId: Value(posId ?? (data['posId'] as num?)?.toInt()),
            createdBy: (data['createdBy'] as num?)?.toInt() ?? 0,
            startedAt: Value(startedAt),
            status: const Value('open'),
            isSynced: const Value(true),
            details: Value(details),
          ),
        );
    return (_database.select(_database.zs)..where((z) => z.id.equals(id)))
        .getSingle();
  }

  /// All sessions that belong to [zId].
  Future<List<CashSession>> sessionsForZ(int zId) =>
      (_database.select(_database.cashSessions)
            ..where((s) => s.zId.equals(zId))
            ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
          .get();

  /// Close a Z: end every still-open/paused session it owns (expected cash),
  /// aggregate the Z totals, and mark it closed + unsynced. [sessionService] is
  /// used to end the sessions so their close totals/tickets are consistent.
  Future<void> closeZ({
    required int zId,
    required SessionService sessionService,
    int? endedBy,
  }) async {
    final sessions = await sessionsForZ(zId);

    // 1. Auto-close any session still open/paused.
    for (final s in sessions) {
      if (s.status == 'active' || s.status == 'paused') {
        await sessionService.endSession(sessionId: s.id);
      }
    }

    // 2. Re-read (now-ended) sessions and aggregate.
    final ended = await sessionsForZ(zId);
    var totalPaid = 0.0;
    var moneyAtStart = 0.0;
    for (final s in ended) {
      totalPaid += s.totalPaid ?? 0.0;
      moneyAtStart += s.moneyAtStart;
    }
    // Merge, never replace: `details` already carries the Z number and business
    // day written at open. Overwriting it here would drop the number before it
    // is ever pushed to the server.
    final prev = <String, dynamic>{};
    final current = await getById(zId);
    if (current?.details != null) {
      try {
        final decoded = jsonDecode(current!.details!);
        if (decoded is Map) prev.addAll(Map<String, dynamic>.from(decoded));
      } catch (_) {/* corrupt blob — the close must still succeed */}
    }
    final details = {
      ...prev,
      'sessionCount': ended.length,
      'sessionCodes': ended.map((s) => s.code).toList(),
      'totalPaid': totalPaid,
      'moneyAtStart': moneyAtStart,
    };

    // 3. Mark the Z closed.
    await (_database.update(_database.zs)..where((z) => z.id.equals(zId))).write(
      ZsCompanion(
        status: const Value('closed'),
        endedAt: Value(DateTime.now()),
        endedBy: Value(endedBy),
        totalPaid: Value(totalPaid),
        details: Value(jsonEncode(details)),
        isSynced: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}

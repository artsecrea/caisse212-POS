import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import 'z_service.dart';

/// The single source of `z_day`: the opening day of the cash session the row
/// belongs to.
///
/// Every entity that lands in a Z report — orders, their lines, tickets,
/// refunds, cash movements — carries a `z_day`, and it must come from the
/// SESSION, never from the clock and never from the row's own date. A shift
/// that opens at 20:00 and runs to 02:00 is one Z day; an order rung up at
/// 00:30 inside it belongs to the day the shift opened, not to the calendar
/// day it happened to be typed on.
///
/// Reading it from the clock is what put orders in the next day's Z, and
/// reading it from `orders.date` is what moved them there again on the next
/// delta pull. Both paths now come through here.
///
/// Database-backed on purpose. The in-memory `currentSessionProvider` is only
/// ever populated by the login screen, so it is null on a terminal that has
/// restarted mid-shift and on every LAN request that arrives before a cashier
/// signs in — exactly the moments the old fallback stamped today's date on
/// yesterday's shift. The row in `cash_sessions` is true regardless.
class ZDayResolver {
  final AppDatabase _database;

  ZDayResolver(this._database);

  /// Midnight of [at] — the canonical shape stored in a `z_day` column.
  static DateTime dayOf(DateTime at) => DateTime(at.year, at.month, at.day);

  /// The cash session currently open on this terminal, or null when none is.
  ///
  /// `paused` does not count: a paused session takes no money, and a row
  /// created while one is paused belongs to whatever shift resumes it.
  Future<CashSession?> activeSession() async {
    final open = await (_database.select(_database.cashSessions)
          ..where((s) => s.status.equals('active'))
          ..orderBy([(s) => OrderingTerm.desc(s.startedAt)])
          ..limit(1))
        .getSingleOrNull();
    return open;
  }

  /// The `z_day` of a specific session, or null when [sessionId] is null or
  /// names a session that no longer exists.
  ///
  /// A session that belongs to a Z takes the Z's business day, so every
  /// session in one Z shares a single `z_day`; a legacy row without a Z takes
  /// its own opening day.
  Future<DateTime?> forSession(int? sessionId) async {
    if (sessionId == null) return null;
    final session = await (_database.select(_database.cashSessions)
          ..where((s) => s.id.equals(sessionId)))
        .getSingleOrNull();
    return _forSessionRow(session);
  }

  /// The `z_day` of the currently-active session, or null when none is open.
  Future<DateTime?> current() async => _forSessionRow(await activeSession());

  /// [forSession], falling back to the active session when the row has none.
  ///
  /// The shape most callers want: an order already tied to a session keeps
  /// that session's day even after the shift has moved on, and one that is
  /// not yet tied to anything joins the shift collecting it now.
  Future<DateTime?> forSessionOrCurrent(int? sessionId) async =>
      await forSession(sessionId) ?? await current();

  /// [current], falling back to today's calendar day when no session is open.
  ///
  /// The last resort, and deliberately a separate method so the callers that
  /// accept a guess are visible. Prefer leaving `z_day` null over guessing
  /// wherever a null is allowed: the backend derives its own day from the
  /// row's timestamp, which is no worse than this and is at least honest
  /// about being derived.
  Future<DateTime> currentOrToday() async =>
      await current() ?? dayOf(DateTime.now());

  Future<DateTime?> _forSessionRow(CashSession? session) async {
    if (session == null) return null;
    if (session.zId != null) {
      final z = await (_database.select(_database.zs)
            ..where((t) => t.id.equals(session.zId!)))
          .getSingleOrNull();
      if (z != null) return ZService.zDayOf(z);
    }
    return dayOf(session.startedAt);
  }
}

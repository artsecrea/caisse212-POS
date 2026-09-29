import 'package:drift/drift.dart';

import '../data/database/app_database.dart';

/// Records non-sale cash in and out of the drawer, and totals it for the
/// expected-cash figure and the X/Z reports.
///
/// The point of this is variance. Before it existed, "opening float + cash
/// sales" was the only prediction of what should be in the till, so every petty
/// cash withdrawal made the count look short and the cashier look wrong.
class CashMovementService {
  final AppDatabase _database;

  CashMovementService(this._database);

  static const String directionIn = 'IN';
  static const String directionOut = 'OUT';

  Future<CashMovement> record({
    required String direction,
    required double amount,
    required String reason,
    String? reference,
    int? sessionId,
    DateTime? zDay,
    int? createdBy,
  }) async {
    // Amount is stored unsigned — `direction` is the sign. Guarding here rather
    // than trusting callers keeps the totals below from ever double-negating.
    final magnitude = amount.abs();
    if (magnitude <= 0) {
      throw ArgumentError('A cash movement needs a non-zero amount');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('A cash movement needs a reason');
    }
    final dir = direction == directionIn ? directionIn : directionOut;

    final now = DateTime.now();
    final code = 'CM-${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}-'
        '${now.microsecondsSinceEpoch.remainder(1000000).toString().padLeft(6, '0')}';
    final id = await _database.into(_database.cashMovements).insert(
          CashMovementsCompanion.insert(
            code: Value(code),
            direction: Value(dir),
            amount: magnitude,
            reason: reason.trim(),
            reference: Value(reference?.trim().isEmpty ?? true
                ? null
                : reference!.trim()),
            sessionId: Value(sessionId),
            zDay: Value(zDay),
            createdBy: Value(createdBy),
          ),
        );
    return (_database.select(_database.cashMovements)
          ..where((m) => m.id.equals(id)))
        .getSingle();
  }

  Future<List<CashMovement>> forSession(int sessionId) =>
      (_database.select(_database.cashMovements)
            ..where((m) => m.sessionId.equals(sessionId))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .get();

  Future<void> delete(int id) =>
      (_database.delete(_database.cashMovements)..where((m) => m.id.equals(id)))
          .go();

  /// Signed net effect on the drawer for one session: IN adds, OUT subtracts.
  /// Add this to "opening float + cash sales" to get the real expected cash.
  Future<double> netForSession(int sessionId) async {
    final rows = await forSession(sessionId);
    return _net(rows);
  }

  /// Same, across every session of a z-day.
  Future<double> netForSessions(List<int> sessionIds) async {
    if (sessionIds.isEmpty) return 0;
    final rows = await (_database.select(_database.cashMovements)
          ..where((m) => m.sessionId.isIn(sessionIds)))
        .get();
    return _net(rows);
  }

  /// Gross totals, so a report can show paid-in and paid-out on their own lines
  /// rather than only the net — a £200 float top-up and a £200 payout net to
  /// zero but are two things the owner wants to see.
  Future<({double paidIn, double paidOut})> totalsForSessions(
      List<int> sessionIds) async {
    if (sessionIds.isEmpty) return (paidIn: 0.0, paidOut: 0.0);
    final rows = await (_database.select(_database.cashMovements)
          ..where((m) => m.sessionId.isIn(sessionIds)))
        .get();
    var inSum = 0.0;
    var outSum = 0.0;
    for (final r in rows) {
      if (r.direction == directionIn) {
        inSum += r.amount;
      } else {
        outSum += r.amount;
      }
    }
    return (paidIn: inSum, paidOut: outSum);
  }

  static double _net(List<CashMovement> rows) {
    var net = 0.0;
    for (final r in rows) {
      net += r.direction == directionIn ? r.amount : -r.amount;
    }
    return net;
  }
}

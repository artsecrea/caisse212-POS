import 'package:drift/drift.dart';

class CashSessions extends Table {
  IntColumn get id => integer()();
  TextColumn get code => text().unique()(); // Unique code for backend identification
  IntColumn get cashierId => integer()();

  @override
  Set<Column> get primaryKey => {id};
  DateTimeColumn get startedAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get endedAt => dateTime().nullable()();
  DateTimeColumn get pausedAt => dateTime().nullable()();
  RealColumn get moneyAtStart => real()();
  RealColumn get moneyAtEnd => real().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))(); // 'active', 'paused', 'ended'
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))(); // Track if synced to server (only ended sessions sync)
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();

  // Z-report / cash-count fields (schema v11). Filled in at session close
  // when the cashier types a counted-cash figure; null on sessions closed
  // before the feature shipped, or closed without counting.
  RealColumn get countedCash => real().nullable()();
  RealColumn get variance => real().nullable()();
  DateTimeColumn get countedAt => dateTime().nullable()();
  TextColumn get countNotes => text().nullable()();

  // Session close totals (schema v24). Filled in at session close.
  // `totalPaid` = sum of all paid, non-cancelled tickets across every payment
  //   method (cash + card + mobile + other) — the full takings for the session,
  //   independent of the physical cash drawer figure in `moneyAtEnd`.
  // `details` = JSON snapshot of the per-method breakdown captured at close
  //   ({cash, card, mobile, other, cancelled, ...}). Null on sessions closed
  //   before the feature shipped.
  RealColumn get totalPaid => real().nullable()();
  TextColumn get details => text().nullable()();

  // The Z this session belongs to (schema v25). Local FK to Zs.id; on sync the
  // session sends that Z's `zDay` / `zSeq`. Null only on legacy rows.
  IntColumn get zId => integer().nullable()();

  // Cash the cashier brought in at open, and cash left over from the previous
  // session (schema v53). POS-counted; the server stores and sums them as sent.
  RealColumn get moneyEntered => real().nullable()();
  RealColumn get moneyCarriedOver => real().nullable()();

  // Set on the session that opened its Z (`AUTO` | `MANUAL`), and the flag on
  // the one that closed it (schema v53). Both ride the session push; the close
  // details themselves (mode, by, at) are read from the Z row.
  TextColumn get zOpenMode => text().nullable()();
  BoolColumn get isClosingSession =>
      boolean().withDefault(const Constant(false))();

  // Ended by the system rather than by its cashier — a Z close sweeping up
  // other sessions, the day rollover, a session rule (schema v54).
  BoolColumn get autoClosed => boolean().withDefault(const Constant(false))();

  // A time limit was bypassed with `pos:z:override` when this session opened
  // its Z or closed it (schema v54). Sent so the back office can audit it.
  BoolColumn get zOverride => boolean().withDefault(const Constant(false))();
}


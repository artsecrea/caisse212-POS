import 'package:drift/drift.dart';

/// The terminal's local record of a Z: the label (business day, sequence)
/// shared by a run of cash sessions. Exactly one Z may be `open` at a time.
///
/// Local only. Under the v3 contract the server has no Z entity: it learns a
/// Z from the `zDay` / `zSeq` / open / close fields carried on the SESSIONS
/// (see `bms/docs/POS_Z_CONTRACT.md`). This row exists so the till can group
/// its sessions, resume the counter, and print the Z from their sum.
/// `code` and `isSynced` are leftovers from the v2 push and are never sent.
class Zs extends Table {
  IntColumn get id => integer()();
  TextColumn get code => text().unique()(); // local key only — never synced

  @override
  Set<Column> get primaryKey => {id};

  // Terminal that owns this Z (from ApiService.getPosId). Null when the POS id
  // isn't known yet; the server also derives it from the X-Pos-Id header.
  IntColumn get posId => integer().nullable()();

  IntColumn get createdBy => integer()(); // user id who opened the Z
  DateTimeColumn get startedAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get endedBy => integer().nullable()(); // user id who closed it

  TextColumn get status => text().withDefault(const Constant('open'))(); // 'open' | 'closed'

  // Aggregate totals captured at close (across all the Z's sessions).
  RealColumn get totalPaid => real().nullable()();
  TextColumn get details => text().nullable()(); // JSON snapshot, encoded/decoded via json

  /// Business day this Z belongs to, `yyyy-MM-dd` (schema v53). Computed from
  /// the tenant's `businessDayStartHour` when the Z opens, and never relabelled
  /// afterwards — a Z that outlives its day is closed FORCED, not moved.
  TextColumn get zDay => text().nullable()();

  /// Ordinal of this Z within [zDay]: 1, 2, 3… (schema v53).
  IntColumn get zSeq => integer().withDefault(const Constant(1))();

  /// How the Z opened (`AUTO` | `MANUAL`) and closed (`MANUAL` | `AUTO` |
  /// `FORCED`) — sent on the opening / closing session respectively.
  TextColumn get openMode => text().nullable()();
  TextColumn get closeMode => text().nullable()();

  /// Opened past `zCantOpenAfter` under `pos:z:override` (schema v54) —
  /// carried to the opening session as `zOverride`.
  BoolColumn get openOverride => boolean().withDefault(const Constant(false))();

  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}



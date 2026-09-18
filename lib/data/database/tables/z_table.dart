import 'package:drift/drift.dart';

/// A "Z" is a shift that owns one or more cash sessions. Exactly one Z may be
/// `open` per POS terminal at a time. It is the single source of `z_day` for
/// every row created while it's open, and is pushed to the backend BEFORE its
/// sessions (sessions reference it by `code`). Mirrors the conventions of
/// [CashSessions] (INTEGER rowid PK, unique `code`, `isSynced` push flag).
class Zs extends Table {
  IntColumn get id => integer()();
  TextColumn get code => text().unique()(); // backend identifier: Z-YYYYMMDD-HHMMSS-XXX

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

  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}



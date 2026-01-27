import 'package:drift/drift.dart';

class CashSessions extends Table {
  IntColumn get id => integer()();
  TextColumn get code => text().unique()(); // Unique code for backend identification
  IntColumn get cashierId => integer()();

  @override
  Set<Column> get primaryKey => {id};
  DateTimeColumn get startedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get endedAt => dateTime().nullable()();
  DateTimeColumn get pausedAt => dateTime().nullable()();
  RealColumn get moneyAtStart => real()();
  RealColumn get moneyAtEnd => real().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))(); // 'active', 'paused', 'ended'
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))(); // Track if synced to server (only ended sessions sync)
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}


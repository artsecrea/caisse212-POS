import 'package:drift/drift.dart';

/// Last per-session order number handed out, one row per numbering scope.
///
/// The scope is what the number restarts with — `session:<id>`, `z:<id>` or
/// `manual` — so switching the restart mode never has to rewrite history:
/// each mode just reads a different row. See [AppDatabase.nextSessionOrderNo].
class OrderNumberCounters extends Table {
  TextColumn get scope => text()();
  IntColumn get seq => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {scope};
}

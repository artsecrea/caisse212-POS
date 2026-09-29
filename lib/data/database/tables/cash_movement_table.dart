import 'package:drift/drift.dart';

/// Cash that entered or left the drawer for a reason that is not a sale.
///
/// Without this, a petty-cash withdrawal, a supplier paid in cash, or a float
/// top-up all landed as unexplained **variance** on the Z report — the cashier
/// counted less than "opening + cash sales" and got blamed for it. The backend
/// contract already assumes these exist: it defines `moneyAtEnd` as
/// "open + cash sales − refunds − **payouts**".
///
/// Pushed to `/pos/cash-movements` (schema v53) as PAY_IN / PAY_OUT, attached
/// to its session by `sessionCode`.
class CashMovements extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Sync key, `CM-…`. Nullable only so the v53 migration can add it; every
  /// row is backfilled and every new row gets one.
  TextColumn get code => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();

  /// `IN` = money added to the drawer (float top-up, change delivery).
  /// `OUT` = money removed (petty cash, supplier payment, bank drop).
  TextColumn get direction => text().withDefault(const Constant('OUT'))();

  /// Always POSITIVE — [direction] carries the sign. Storing a signed amount
  /// invites double-negation bugs when totalling.
  RealColumn get amount => real()();

  /// Free-text why. Required in the UI: an unexplained movement is barely
  /// better than an unexplained variance.
  TextColumn get reason => text()();

  /// Optional reference — receipt number, invoice, envelope id.
  TextColumn get reference => text().nullable()();

  /// The session (and business day) this movement belongs to, so it lands in
  /// the right Z report.
  IntColumn get sessionId => integer().nullable()();
  DateTimeColumn get zDay => dateTime().nullable()();

  IntColumn get createdBy => integer().nullable()();
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();
}

import 'package:drift/drift.dart';

/// A refund issued against a paid order.
///
/// Mirrors the conventions of [CashSessions] / [Zs]: an INTEGER rowid PK, a
/// unique `code` that is the backend's idempotency key (re-sending the same
/// code is a no-op server-side), and an `isSynced` push flag so the row
/// survives being created offline.
///
/// Money is stored the same way the rest of the POS stores it — as `real`,
/// matching `tickets.amount` and `order_products.unitaryPrice`.
class Refunds extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Backend identity + idempotency key: `RF-<POS>-YYYYMMDD-HHMMSS-XXX`.
  TextColumn get code => text().unique()();

  /// Local order row this refund belongs to.
  IntColumn get orderId => integer()();

  /// The order's stable backend key. Denormalised so the sync payload can be
  /// built without joining, exactly as tickets carry `orderCode`.
  TextColumn get orderCode => text()();

  /// CASH | CARD | TRANSFER | CHECK — the server rejects anything else.
  TextColumn get method => text().withDefault(const Constant('CASH'))();

  /// Sum of the line amounts, cached so lists don't have to aggregate.
  RealColumn get totalAmount => real().withDefault(const Constant(0.0))();

  TextColumn get reason => text().nullable()();

  /// User id who issued it.
  IntColumn get refundedBy => integer().nullable()();
  DateTimeColumn get refundedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// Cash session / Z the refund was taken in, so it lands in the right
  /// Z-report. Nullable for refunds issued outside an open session.
  IntColumn get sessionId => integer().nullable()();
  DateTimeColumn get zDay => dateTime().nullable()();

  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  /// Why the server refused this refund, if it did.
  ///
  /// The bulk endpoint runs the batch in ONE transaction, so a single bad
  /// refund rolls back the valid ones alongside it. Retrying the same batch
  /// then fails forever and blocks every later refund behind it. A refund
  /// that fails on its own is parked here instead: skipped by the batch
  /// builder, and surfaced for someone to look at.
  TextColumn get syncError => text().nullable()();
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();
}

/// One refunded order line. `restock: true` posts a positive stock movement
/// server-side; `false` is money-only (the goods are waste).
class RefundLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get refundId => integer()();

  /// Local `order_products.id`. The server wants its OWN line id, so the sync
  /// payload maps this through [orderProductServerId] when it is known.
  IntColumn get orderProductId => integer()();

  /// Server-side `order_products.id`, when the order has been synced and the
  /// mapping is known. Null → the refund waits for the order to sync first.
  IntColumn get orderProductServerId => integer().nullable()();

  /// Refunded quantity — real to match `order_products.quantity` (weighed
  /// goods can be partially refunded).
  RealColumn get quantity => real().withDefault(const Constant(1.0))();

  /// Money returned for this line. Null lets the server derive it from the
  /// order line's per-unit total × quantity.
  /// Money for this line. ALWAYS populated locally — the slip is printed
  /// from this row, and a null here prints "1 x 0.00" under a correct
  /// total, which reads as a bug to the customer holding the paper.
  RealColumn get amount => real().nullable()();

  /// True only when a cashier typed the amount instead of taking the
  /// derived one.
  ///
  /// Drives what goes on the wire: the contract prefers `amount` OMITTED so
  /// the server derives it from its own copy of the line. Sending our local
  /// figure would risk a 400 whenever the two derivations disagree — an
  /// order-level discount, for one, is in the server's line total but not in
  /// our per-unit arithmetic. So a derived amount stays local and only a
  /// deliberate override is transmitted.
  BoolColumn get amountOverridden =>
      boolean().withDefault(const Constant(false))();

  BoolColumn get restock => boolean().withDefault(const Constant(true))();
  TextColumn get reason => text().nullable()();
}

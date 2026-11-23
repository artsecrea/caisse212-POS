import 'package:drift/drift.dart';

/// An order line cancelled WHOLE, kept so the v2 order push can still send it.
///
/// The v2 push (`PUT /pos/v2/orders/{code}`) sends the full order, and a line
/// missing from it is removed on the server as an untracked deletion. A
/// cancelled line therefore has to keep travelling with its order, as
/// `state: CANCELED` with `canceledQuantity`, under its own `lineUid`.
///
/// It lives here rather than in `order_products` on purpose: every total,
/// ticket, kitchen send, payment and Z reads `order_products` as "what is
/// sold", and a cancelled row left among them would have to be filtered out
/// by each of them. Only the push reads this table. What the cashier SEES of
/// cancellations (the panel row, the X/Z section) still comes from
/// `removed_order_items`, which this does not replace.
class CancelledOrderLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer()();

  /// The line's identity, carried over from `order_products.line_uid`. Null
  /// for a line written before v66 — its order stays on the v1 push.
  TextColumn get lineUid => text().nullable()();
  IntColumn get serverId => integer().nullable()();

  IntColumn get productId => integer()();
  IntColumn get variantId => integer().nullable()();

  /// Units the line had when it was cancelled.
  RealColumn get quantity => real()();

  /// Running total of units cancelled on the line, including any earlier
  /// quantity cut: a 3 cut to 1 and then cancelled is 3.
  RealColumn get canceledQuantity => real()();

  RealColumn get unitaryPrice => real()();
  RealColumn get unitaryDiscount => real().withDefault(const Constant(0.0))();
  RealColumn get unitaryTva => real().withDefault(const Constant(0.0))();
  RealColumn get manualDiscount => real().withDefault(const Constant(0.0))();
  RealColumn get cost => real().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get saleUomId => integer().nullable()();
  IntColumn get courseNo => integer().nullable()();
  DateTimeColumn get zDay => dateTime().nullable()();

  /// The line's options as sent on a push: JSON list of
  /// `{componentId, quantity, price, isSpecial, name}`.
  TextColumn get componentsJson => text().nullable()();

  DateTimeColumn get canceledAt =>
      dateTime().clientDefault(() => DateTime.now())();
  IntColumn get canceledBy => integer().nullable()();
}

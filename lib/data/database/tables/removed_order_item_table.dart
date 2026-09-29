import 'package:drift/drift.dart';

/// A line that was taken OFF a saved order — a tombstone for food that was
/// rung up and then pulled.
///
/// The Z has to answer "what was annulled during this shift", and until now it
/// could not: removing a line deletes the `order_products` row outright, so by
/// the time the report runs there is nothing left to count. The only trace was
/// a rendered sentence in `ActivityLogs` ("Items removed: 2× Pizza"), which is
/// written for a human to read and is the wrong shape to total — no amount, no
/// session, and parsing it back would break the first time somebody changes the
/// logging language.
///
/// So each removal writes a row here instead. Deliberately denormalised:
/// [productName] and [unitaryPrice] are snapshotted at removal time rather than
/// resolved later, because the catalogue is reconciled against the server and a
/// product deleted there would otherwise take the evidence of its own
/// cancellation with it.
///
/// Covers removals from a SAVED order only. A line dropped from a basket that
/// was never saved has never existed as far as the till is concerned, and an
/// order cancelled whole already reports through `orders.status` +
/// `tickets.isCancelled`.
///
/// Local-only, like [CashMovements]: there is no POS endpoint for annulments,
/// so this feeds the X/Z without a sync flag. Add `isSynced` and a bulk push in
/// the usual pattern when one appears.
class RemovedOrderItems extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get orderId => integer()();

  /// Kept alongside [orderId] so the report can name the order even after a
  /// retention purge has taken the `orders` row.
  TextColumn get orderCode => text().nullable()();

  /// The session (and business day) the removal belongs to, so it lands in the
  /// right Z. Read off the order at removal time.
  IntColumn get sessionId => integer().nullable()();
  DateTimeColumn get zDay => dateTime().nullable()();

  IntColumn get productId => integer()();
  IntColumn get variantId => integer().nullable()();

  /// Snapshotted at removal time — see the class doc.
  TextColumn get productName => text()();
  TextColumn get variantName => text().nullable()();

  /// How many units came off. Real, not int: weighed lines sell in kg.
  RealColumn get quantity => real()();

  /// Unit price as it stood on the pulled line.
  RealColumn get unitaryPrice => real().withDefault(const Constant(0.0))();

  /// `quantity * unitaryPrice`, stored rather than derived so the report totals
  /// what was actually pulled even if the price later changes.
  RealColumn get amount => real().withDefault(const Constant(0.0))();

  /// Whether the kitchen had already been told to make it. A line pulled
  /// before it was ever sent costs nothing; one pulled after is real waste,
  /// and the two should not read the same on the Z.
  BoolColumn get wasSentToKitchen =>
      boolean().withDefault(const Constant(false))();

  /// `POS` or `WAITER` — which side pulled it.
  TextColumn get source => text().withDefault(const Constant('POS'))();

  IntColumn get removedBy => integer().nullable()();
  TextColumn get removedByName => text().nullable()();

  /// `clientDefault`, not `currentDateAndTime`: datetimes are stored as TEXT in
  /// this schema, and the SQL default writes a different format from every
  /// Dart-side write, which puts the row outside its own date filters.
  DateTimeColumn get removedAt =>
      dateTime().clientDefault(() => DateTime.now())();
}

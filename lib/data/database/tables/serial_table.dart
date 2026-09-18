import 'package:drift/drift.dart';

/// One physical unit of a serial-tracked product (IMEI, chassis number, …).
///
/// Read-only from the POS's point of view: the web dashboard creates these at
/// reception. The POS caches them so a cashier can pick or scan the exact unit
/// being sold, including offline, and so the picker can be filtered without a
/// round trip.
class Serials extends Table {
  /// Server id. This is the value sent as `serialId` on the order line.
  IntColumn get id => integer()();

  /// What the cashier reads off the box and what a scanner emits.
  TextColumn get serialNumber => text()();
  TextColumn get code => text().nullable()();

  IntColumn get productId => integer()();
  IntColumn get batchId => integer().nullable()();

  /// `true` = in stock and sellable. `false` = already sold, or its reception
  /// has not been validated yet — the POS treats both the same way: not
  /// offerable.
  ///
  /// Locally this doubles as the reservation flag: a serial is flipped to false
  /// the moment it lands in a basket and back to true if the line is removed, so
  /// two baskets on the same terminal cannot claim one unit. Server truth wins
  /// on the next catalogue pull, which is what recovers a crash mid-order.
  BoolColumn get isAvailable => boolean().withDefault(const Constant(true))();

  /// Denormalised display fields straight from the API, so the picker needs no
  /// joins on the hot path.
  TextColumn get productName => text().nullable()();
  TextColumn get batchCode => text().nullable()();
  IntColumn get uomId => integer().nullable()();
  TextColumn get uomAbbreviation => text().nullable()();

  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {id};
}

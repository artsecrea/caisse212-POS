import 'package:drift/drift.dart';

/// A unit this terminal sold that the server gave to another order.
///
/// The loser side of a double sale. The backend's `serial_logs` ledger records
/// the WINNER — by design the loser gets no row there — so this table plus the
/// history note on the order line is the only record that this till ever
/// claimed the unit. It is deliberately not derived from anything: once the
/// link is nulled there is nothing left to derive it from.
///
/// Rows are kept after acknowledgement rather than deleted. Somebody will ask
/// what happened to that box.
class SerialConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Our order, the one that lost the unit.
  TextColumn get orderCode => text()();
  IntColumn get productId => integer()();

  /// The serial this terminal claimed.
  IntColumn get serialId => integer()();
  TextColumn get serialNumber => text().nullable()();

  /// The order that kept it. Null when the unit was unavailable for a reason
  /// that was not another sale.
  TextColumn get winningOrderCode => text().nullable()();
  TextColumn get reason => text().nullable()();

  DateTimeColumn get detectedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// When a human said they had seen it. Null until then, which is what the
  /// alert counts.
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();
}

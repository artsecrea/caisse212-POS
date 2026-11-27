import '../../services/unpaid_orders_service.dart'
    show UnpaidOrderEntry, UnpaidOrdersSummary;

/// What the floor still owes. An interface because, linked to a hub, a till
/// shows what the whole floor owes, by the hub: standalone, it reads its own
/// database (`UnpaidOrdersService`).
abstract interface class UnpaidQueries {
  /// Every unpaid order, newest first — tables and parked orders alike.
  ///
  /// Cancelled orders are excluded, and so are zero-value ones: an empty
  /// order occupying a table is a floor-reconciliation problem, not money
  /// anybody is owed.
  ///
  /// [tablesOnly] narrows it to orders sitting on a table, which is what the
  /// floor view wants; the reports want both.
  Future<List<UnpaidOrderEntry>> unpaidOrders({bool tablesOnly = false});

  /// The whole floor's outstanding position in one object.
  Future<UnpaidOrdersSummary> summary({bool tablesOnly = false});

  /// [summary], re-read whenever anything that could change it changes.
  ///
  /// The trivial `SELECT 1` is a drift idiom, not a mistake: declaring
  /// `readsFrom` makes the stream re-emit on any write to those tables, which
  /// is what lets one recomputation cover orders, their lines, their tickets
  /// and the floor plan together. Watching only `orders` would miss a
  /// payment, and the figures on the floor would quietly go stale.
  Stream<UnpaidOrdersSummary> watchSummary({bool tablesOnly = false});
}

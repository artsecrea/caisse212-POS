/// Whether a table is still genuinely occupied by the order it points at.
///
/// A table is held by `area_tables.order_id`, and that pointer is cleared by
/// whichever code path finishes the order. That is the weakness: every path
/// has to remember, and one that forgets leaves a table showing occupied with
/// nobody sitting at it and no way for the floor to reclaim it except a manual
/// clear. Rather than add a seventh place that remembers, this decides
/// occupancy from the order itself, so a stuck table corrects itself the next
/// time anyone looks at the floor.
library;

/// Order statuses that mean nobody can be sitting at that table, whatever the
/// settings say.
const _kDeadStatuses = {'CANCELED', 'CANCELLED'};

/// Why a table should be released, or null when it should stay held.
enum TableReleaseReason {
  /// The order it points at is gone — deleted, purged by retention, or never
  /// existed. A pointer to nothing can never be cleared by the normal path,
  /// because the normal path starts from the order.
  danglingOrder,

  /// The order was cancelled. Nobody is eating a cancelled order.
  orderCancelled,

  /// Every line is paid or voided. Only a release when the till is configured
  /// to free tables on payment — otherwise a paid table stays held on purpose,
  /// for customers who are still sitting there.
  orderSettled,
}

/// Whether an order's lines are all settled: everything paid or voided, and at
/// least one thing actually paid.
///
/// Deliberately reads the LINE states and never `orders.status`. Orders in this
/// system are born COMPLETED so the cloud is never left holding a stale
/// intermediate state, which makes the order's own status useless for deciding
/// whether money changed hands.
bool isOrderSettled(Iterable<String> lineStates) {
  var hasPaid = false;
  for (final state in lineStates) {
    if (state == 'PAID') {
      hasPaid = true;
      continue;
    }
    if (state == 'CANCELED' || state == 'CANCELLED') continue;
    return false; // something is still outstanding
  }
  return hasPaid;
}

/// Decide whether a held table should be let go.
///
/// [orderExists] false covers the dangling case. [lineStates] is empty for an
/// order with no lines at all, which is not settled — an empty order is more
/// likely one being built than one finished, and freeing it under the cashier
/// would be worse than leaving it held.
TableReleaseReason? tableReleaseReason({
  required bool orderExists,
  required String orderStatus,
  required Iterable<String> lineStates,
  required bool freeOnPayment,
}) {
  if (!orderExists) return TableReleaseReason.danglingOrder;
  if (_kDeadStatuses.contains(orderStatus.toUpperCase())) {
    return TableReleaseReason.orderCancelled;
  }
  if (!freeOnPayment) return null;
  final states = lineStates.toList();
  if (states.isEmpty) return null;
  return isOrderSettled(states) ? TableReleaseReason.orderSettled : null;
}

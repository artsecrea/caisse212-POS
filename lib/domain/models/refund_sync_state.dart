/// How a refund is doing on its way to the server.
///
/// A refund is money already handed over, so "not on the server yet" is a fact
/// the cashier is entitled to see. The terminal retries every unsynced refund
/// on every cycle and never gives up on one — which is right, and which leaves
/// a gap: a permanently invalid refund and one that failed a moment ago look
/// identical, both retrying quietly forever. This is the distinction that
/// closes it, drawn on age rather than on an attempt count.
///
/// Age is the better measure. Attempts depend on how often the terminal syncs
/// and whether it was switched on at all; a refund that has been owed to the
/// server since this morning is a problem regardless of how many times it was
/// tried.
library;

enum RefundSyncState {
  /// The server has it. Nothing to do.
  synced,

  /// Waiting its turn, nothing has gone wrong.
  queued,

  /// Refused on its last attempt, recently. Usually clears on its own.
  failing,

  /// Refused and still refused, long enough that nobody should expect it to
  /// fix itself. Needs a person.
  stuck,
}

/// How long a refund may keep failing before it is somebody's problem.
///
/// Long enough that a network outage over lunch does not raise an alarm, short
/// enough to be caught within the same shift.
const kRefundStuckAfter = Duration(hours: 2);

RefundSyncState refundSyncState({
  required bool isSynced,
  required String? syncError,
  required DateTime refundedAt,
  required DateTime now,
  Duration stuckAfter = kRefundStuckAfter,
}) {
  if (isSynced) return RefundSyncState.synced;
  if (syncError == null || syncError.isEmpty) return RefundSyncState.queued;
  return now.difference(refundedAt) >= stuckAfter
      ? RefundSyncState.stuck
      : RefundSyncState.failing;
}

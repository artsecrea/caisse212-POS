import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/refund_sync_state.dart';

/// Telling a refund that will fix itself from one that will not.
///
/// The terminal retries every unsynced refund forever and gives up on none —
/// which is right, and which means a permanently invalid refund and one that
/// failed thirty seconds ago look identical while both retry quietly. This is
/// the only place that difference is drawn, so it is the only place it can be
/// got wrong.

final refundedAt = DateTime(2026, 9, 1, 9);

RefundSyncState stateAt(
  Duration since, {
  bool isSynced = false,
  String? syncError = 'Over-refund on line 55',
}) =>
    refundSyncState(
      isSynced: isSynced,
      syncError: syncError,
      refundedAt: refundedAt,
      now: refundedAt.add(since),
    );

void main() {
  test('a synced refund is done, whatever it did on the way', () {
    expect(
        stateAt(const Duration(days: 3),
            isSynced: true, syncError: 'an old message'),
        RefundSyncState.synced);
  });

  test('no error means it is simply waiting its turn', () {
    expect(stateAt(const Duration(days: 3), syncError: null),
        RefundSyncState.queued);
    expect(stateAt(const Duration(minutes: 1), syncError: ''),
        RefundSyncState.queued,
        reason: 'an empty message is not a failure');
  });

  test('a fresh refusal is expected to clear itself', () {
    expect(stateAt(Duration.zero), RefundSyncState.failing);
    expect(stateAt(const Duration(minutes: 45)), RefundSyncState.failing);
  });

  test('a refusal that outlives the window needs a person', () {
    expect(stateAt(const Duration(hours: 3)), RefundSyncState.stuck);
    expect(stateAt(const Duration(days: 2)), RefundSyncState.stuck);
  });

  test('the boundary belongs to stuck, not to failing', () {
    // Exactly on the threshold should escalate rather than sit one more cycle.
    expect(stateAt(kRefundStuckAfter), RefundSyncState.stuck);
    expect(stateAt(kRefundStuckAfter - const Duration(seconds: 1)),
        RefundSyncState.failing);
  });

  test('a clock that went backwards does not escalate', () {
    // Time can move the wrong way on a till: a manual correction, an NTP jump.
    // A negative age must read as fresh, not as days old.
    expect(
        refundSyncState(
          isSynced: false,
          syncError: 'boom',
          refundedAt: refundedAt,
          now: refundedAt.subtract(const Duration(hours: 5)),
        ),
        RefundSyncState.failing);
  });

  test('the window is adjustable without touching the rule', () {
    expect(stateAt(const Duration(minutes: 10)), RefundSyncState.failing);
    expect(
        refundSyncState(
          isSynced: false,
          syncError: 'boom',
          refundedAt: refundedAt,
          now: refundedAt.add(const Duration(minutes: 10)),
          stuckAfter: const Duration(minutes: 5),
        ),
        RefundSyncState.stuck);
  });
}

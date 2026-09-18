import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/services/api_service.dart';

/// The bulk refund endpoint answers **200 even when it refused some records**.
/// Treating a 200 as total success marks a rejected refund as synced, and it
/// then disappears: money handed back at the counter, no server record, nothing
/// on screen. These pin the parsing that prevents that.
void main() {
  group('partial success', () {
    test('created and skipped both count as accepted, failed does not', () {
      final r = RefundSyncResult.fromJson({
        'message': 'Refunds synced successfully',
        'count': 2,
        'created': [
          {'code': 'RF-1'}
        ],
        'skipped': [
          {'code': 'RF-2'}
        ],
        'failed': [
          {'code': 'RF-3', 'error': 'Over-refund on line 55'}
        ],
      }, sentCodes: ['RF-1', 'RF-2', 'RF-3']);

      expect(r.accepted, {'RF-1', 'RF-2'});
      expect(r.failed['RF-3'], 'Over-refund on line 55');
      expect(r.accepted.contains('RF-3'), isFalse);
    });

    test('skipped is a SUCCESS — the idempotent re-send working', () {
      // After a timeout the client re-sends; the server already has it. Marking
      // that as failure would strand a refund that is safely recorded.
      final r = RefundSyncResult.fromJson({
        'skipped': [
          {'code': 'RF-1'}
        ],
      }, sentCodes: ['RF-1']);
      expect(r.accepted, {'RF-1'});
      expect(r.failed, isEmpty);
    });

    test('outcomes are matched by code, not by position', () {
      // The server may return them in any order. A positional match would mark
      // the wrong refunds synced — the worst possible failure here.
      final r = RefundSyncResult.fromJson({
        'created': [
          {'code': 'RF-C'}
        ],
        'failed': [
          {'code': 'RF-A', 'error': 'Unknown order'}
        ],
      }, sentCodes: ['RF-A', 'RF-B', 'RF-C']);

      expect(r.accepted, {'RF-C'});
      expect(r.failed.keys, {'RF-A'});
      // RF-B got no verdict at all: not accepted, not failed. The caller must
      // leave it pending rather than assume either way.
      expect(r.accepted.contains('RF-B'), isFalse);
      expect(r.failed.containsKey('RF-B'), isFalse);
    });

    test('plain string arrays are accepted as well as objects', () {
      final r = RefundSyncResult.fromJson({
        'created': ['RF-1', 'RF-2'],
      }, sentCodes: ['RF-1', 'RF-2']);
      expect(r.accepted, {'RF-1', 'RF-2'});
    });
  });

  group('older servers', () {
    test('a bare {message, count} 200 means the whole batch went through', () {
      // The previous contract: one transaction, 200 = everything committed.
      // Reading that as "nothing was accepted" would re-send forever.
      final r = RefundSyncResult.fromJson({
        'message': 'Refunds synced successfully',
        'count': 2,
      }, sentCodes: ['RF-1', 'RF-2']);
      expect(r.accepted, {'RF-1', 'RF-2'});
      expect(r.failed, isEmpty);
    });

    test('an empty body is treated the same way', () {
      final r = RefundSyncResult.fromJson({}, sentCodes: ['RF-1']);
      expect(r.accepted, {'RF-1'});
    });

    test('but an explicit failure is NEVER upgraded to success', () {
      // The fallback must not fire when the server did answer per-record.
      final r = RefundSyncResult.fromJson({
        'failed': [
          {'code': 'RF-1', 'error': 'Over-refund'}
        ],
      }, sentCodes: ['RF-1']);
      expect(r.accepted, isEmpty);
      expect(r.failed['RF-1'], 'Over-refund');
    });

    test('a failure without an error string still parks with a reason', () {
      final r = RefundSyncResult.fromJson({
        'failed': [
          {'code': 'RF-1'}
        ],
      }, sentCodes: ['RF-1']);
      expect(r.failed['RF-1'], isNotEmpty);
    });
  });
}

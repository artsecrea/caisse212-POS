import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/serial_conflict.dart';

/// Parsing the `serialConflicts` array off a sync response.
///
/// This runs immediately after a sync the SERVER HAS ALREADY ACCEPTED. A
/// surprise in this array must never turn that into a failure: the order is
/// saved and counted server-side, so throwing here would re-queue a batch that
/// will never succeed — the exact failure the feature was built to remove.
/// Most of these tests are about that, not about the happy path.

const bulkBody = {
  'message': 'Orders synced successfully',
  'count': 2,
  'serialConflicts': [
    {
      'orderCode': 'T1-0042',
      'productId': 118,
      'serialId': 907,
      'serialNumber': 'SN-4471-A',
      'winningOrderCode': 'T2-0017',
      'reason': "Serial 'SN-4471-A' is not available",
    }
  ],
};

void main() {
  group('the documented bodies', () {
    test('the bulk response parses', () {
      final conflicts = SerialConflictReport.listFrom(bulkBody);
      expect(conflicts.length, 1);
      final c = conflicts.single;
      expect(c.orderCode, 'T1-0042');
      expect(c.productId, 118);
      expect(c.serialId, 907);
      expect(c.serialNumber, 'SN-4471-A');
      expect(c.winningOrderCode, 'T2-0017');
    });

    test('the single-order response parses identically', () {
      // A batch of one routes to the single path; it must not behave
      // differently from a batch of two.
      final conflicts = SerialConflictReport.listFrom({
        'message': 'Order synced successfully',
        'orderCode': 'T1-0042',
        'serialConflicts': bulkBody['serialConflicts'],
      });
      expect(conflicts.single.serialId, 907);
    });

    test('a clean sync yields nothing to do', () {
      expect(
          SerialConflictReport.listFrom(
              {'message': 'ok', 'count': 3, 'serialConflicts': []}),
          isEmpty);
    });
  });

  group('nothing here may throw', () {
    test('a body that is not a map', () {
      for (final body in [null, 'ok', 42, <int>[]]) {
        expect(SerialConflictReport.listFrom(body), isEmpty,
            reason: 'body: $body');
      }
    });

    test('the field missing entirely — an older server', () {
      expect(SerialConflictReport.listFrom({'message': 'ok'}), isEmpty);
    });

    test('the field present but not a list', () {
      expect(
          SerialConflictReport.listFrom({'serialConflicts': 'none'}), isEmpty);
    });

    test('junk entries are skipped, good ones survive', () {
      final conflicts = SerialConflictReport.listFrom({
        'serialConflicts': [
          'not an object',
          null,
          {'orderCode': 'T1-1', 'serialId': 5},
        ],
      });
      expect(conflicts.length, 1);
      expect(conflicts.single.orderCode, 'T1-1');
    });
  });

  group('entries we cannot act on are dropped', () {
    test('no order code means no line to find', () {
      expect(
          SerialConflictReport.listFrom({
            'serialConflicts': [
              {'serialId': 907, 'serialNumber': 'SN-1'}
            ]
          }),
          isEmpty);
    });

    test('no serial id means nothing to match on', () {
      // Matching is by (orderCode, serialId); without the id we would not
      // know which line lost its unit.
      expect(
          SerialConflictReport.listFrom({
            'serialConflicts': [
              {'orderCode': 'T1-0042'}
            ]
          }),
          isEmpty);
    });
  });

  group('what gets left on the line', () {
    test('names the unit and where it went', () {
      final c = SerialConflictReport.listFrom(bulkBody).single;
      expect(c.historyNote, 'Serial SN-4471-A went with order T2-0017');
    });

    test('an unclaimed unit says so rather than naming nobody', () {
      // Unavailable for a reason that is not another sale — a reception never
      // validated, for instance.
      final c = SerialConflictReport.listFrom({
        'serialConflicts': [
          {
            'orderCode': 'T1-0042',
            'serialId': 907,
            'serialNumber': 'SN-4471-A',
            'winningOrderCode': null,
          }
        ]
      }).single;
      expect(c.historyNote, 'Serial SN-4471-A could not be claimed');
    });

    test('falls back to the id when the number is missing', () {
      final c = SerialConflictReport.listFrom({
        'serialConflicts': [
          {'orderCode': 'T1-0042', 'serialId': 907}
        ]
      }).single;
      expect(c.historyNote, contains('#907'));
    });
  });
}

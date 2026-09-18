import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/external_order_models.dart';
import 'package:caisse212/services/external_order_queue_service.dart';

/// Covers the external-order queue contract: page/counts parsing, the confirm
/// guard, and the `OTHER` source rule. These are the parts where being wrong
/// means either accepting an order the kitchen can't build, or showing the
/// cashier a pager that lies about how much work is left.

Map<String, dynamic> item({
  int id = 1,
  String status = 'PENDING',
  String source = 'GLOVO',
  bool unmapped = false,
  String? externalOrderId = 'glovo-123',
}) =>
    {
      'id': id,
      'orderCode': 'ORD-$id',
      'source': source,
      'status': status,
      'order': {
        'type': 'DELIVERY',
        'items': const [],
        'hasUnmappedItems': unmapped,
        'courierName': 'Sam',
        'total': 120.5,
      },
      'createdAt': '2026-08-18T12:00:00.000',
      if (externalOrderId != null) 'externalOrderId': externalOrderId,
      'externalStoreId': 'store-9',
    };

void main() {
  group('ExternalQueueItem parsing', () {
    test('carries the platform ids and acknowledgement fields', () {
      final i = ExternalQueueItem.fromJson({
        ...item(),
        'acknowledgedOrderId': 77,
        'acknowledgedAt': '2026-08-18T12:05:00.000',
      });
      expect(i.externalOrderId, 'glovo-123');
      expect(i.externalStoreId, 'store-9');
      expect(i.acknowledgedOrderId, 77);
      expect(i.acknowledgedAt, isNotNull);
    });

    test('reads courier and total off the order preview', () {
      final i = ExternalQueueItem.fromJson(item());
      expect(i.order.courierName, 'Sam');
      expect(i.order.total, 120.5);
    });

    test('survives a numeric id arriving as a double', () {
      final j = item()..['id'] = 5.0;
      expect(ExternalQueueItem.fromJson(j).id, 5);
    });

    test('a missing order object does not throw', () {
      final j = item()..remove('order');
      final i = ExternalQueueItem.fromJson(j);
      expect(i.order.items, isEmpty);
      expect(i.order.hasUnmappedItems, isFalse);
    });

    test('an absent hasUnmappedItems defaults to false', () {
      // A server predating the flag must not make every order unconfirmable.
      final j = item();
      (j['order'] as Map).remove('hasUnmappedItems');
      expect(ExternalQueueItem.fromJson(j).order.hasUnmappedItems, isFalse);
    });
  });

  group('canConfirm guard', () {
    test('a pending, fully-mapped item can be confirmed', () {
      expect(ExternalQueueItem.fromJson(item()).canConfirm, isTrue);
    });

    test('unmapped lines block confirm', () {
      expect(
          ExternalQueueItem.fromJson(item(unmapped: true)).canConfirm, isFalse);
    });

    test('a non-pending item cannot be confirmed again', () {
      for (final s in ['CONFIRMED', 'CANCELLED', 'ACKNOWLEDGED']) {
        expect(ExternalQueueItem.fromJson(item(status: s)).canConfirm, isFalse,
            reason: '$s must not be confirmable');
      }
    });

    test('status helpers are case-insensitive', () {
      final i = ExternalQueueItem.fromJson(item(status: 'pending'));
      expect(i.isPending, isTrue);
    });
  });

  group('source matching', () {
    test('known platforms match by name', () {
      expect(ExternalOrderQueueService.matchesSource('GLOVO', 'GLOVO'), isTrue);
      expect(ExternalOrderQueueService.matchesSource('WEB', 'GLOVO'), isFalse);
    });

    test('OTHER means anything outside WEB/GLOVO/KOOUL', () {
      // The contract defines OTHER by exclusion — DealUp and WhatsApp both land
      // there, so equality matching would silently hide them.
      expect(ExternalOrderQueueService.matchesSource('DEALUP', 'OTHER'), isTrue);
      expect(
          ExternalOrderQueueService.matchesSource('WHATSAPP', 'OTHER'), isTrue);
      expect(ExternalOrderQueueService.matchesSource('GLOVO', 'OTHER'), isFalse);
      expect(ExternalOrderQueueService.matchesSource('WEB', 'OTHER'), isFalse);
      expect(ExternalOrderQueueService.matchesSource('KOOUL', 'OTHER'), isFalse);
    });
  });

  group('QueuePage', () {
    test('reads the server envelope', () {
      final p = QueuePage.fromJson({
        'content': [item(id: 1), item(id: 2)],
        'page': 1,
        'size': 20,
        'totalElements': 64,
        'totalPages': 4,
        'first': false,
        'last': false,
      });
      expect(p.content.length, 2);
      expect(p.page, 1);
      expect(p.totalElements, 64);
      expect(p.totalPages, 4);
      expect(p.first, isFalse);
    });

    test('derives totalPages when the server omits it', () {
      final p = QueuePage.fromJson({
        'content': const [],
        'size': 20,
        'totalElements': 61,
      });
      // 61 items at 20/page is 4 pages, not 3 — the partial page counts.
      expect(p.totalPages, 4);
    });

    test('one malformed row does not blank the page', () {
      final p = QueuePage.fromJson({
        'content': [item(id: 1), {'garbage': true}, item(id: 3)],
        'totalElements': 3,
        'size': 20,
      });
      expect(p.content.map((e) => e.id), [1, 3]);
    });

    test('an empty page is empty, not an error', () {
      final p = QueuePage.fromJson(const {'content': []});
      expect(p.isEmpty, isTrue);
      expect(p.totalElements, 0);
    });
  });

  group('QueueCounts', () {
    test('all four source keys are present even when the server omits them', () {
      // The chips are rendered from this map, so a missing key would drop a
      // whole platform out of the filter bar.
      final c = QueueCounts.fromJson({
        'total': 40,
        'bySource': {'GLOVO': 40},
      });
      expect(c.total, 40);
      for (final k in QueueCounts.sourceKeys) {
        expect(c.bySource.containsKey(k), isTrue, reason: '$k missing');
      }
      expect(c.countFor('GLOVO'), 40);
      expect(c.countFor('WEB'), 0);
    });

    test('an unknown source the server adds later is kept', () {
      final c = QueueCounts.fromJson({
        'total': 5,
        'bySource': {'UBEREATS': 5},
      });
      expect(c.countFor('UBEREATS'), 5,
          reason: 'a new platform must appear without a client release');
    });

    test('a missing bySource yields zeroes rather than throwing', () {
      final c = QueueCounts.fromJson(const {'total': 0});
      expect(c.countFor('GLOVO'), 0);
    });
  });
}

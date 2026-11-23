import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/services/sse_service.dart';

/// Every event name the queue contract defines must map to a handled type.
///
/// This is not a formality. An unrecognised name degrades to
/// [SseEventType.unknown] and is dropped without a trace, which is exactly how
/// `order-cancelled` went unnoticed: the platform cancelled orders, the server
/// sent the event, and the POS silently ignored it — leaving cancelled tickets
/// on the board for cashiers to work and kitchens to cook.
void main() {
  group('contract event names', () {
    const names = {
      'connected': SseEventType.connected,
      'new-order': SseEventType.newOrder,
      'order-state-changed': SseEventType.orderStateChanged,
      'order-cancelled': SseEventType.orderCancelled,
      'order-ready': SseEventType.orderReady,
      'order-delivery-status-changed': SseEventType.orderDeliveryStatusChanged,
      'pos-command': SseEventType.posCommand,
      'heartbeat': SseEventType.heartbeat,
      'reservation-updated': SseEventType.reservationUpdated,
    };

    test('every documented event is recognised', () {
      for (final entry in names.entries) {
        expect(SseService.toEventType(entry.key), entry.value,
            reason: entry.key);
      }
    });

    test('none of them falls through to unknown', () {
      for (final name in names.keys) {
        expect(SseService.toEventType(name), isNot(SseEventType.unknown),
            reason: '$name would be silently dropped');
      }
    });

    test('an event the contract does not define is unknown, not a crash', () {
      // Forward compatibility: the server may add events before the POS knows
      // them, and that must be inert rather than fatal.
      expect(SseService.toEventType('something-new-in-2027'),
          SseEventType.unknown);
      expect(SseService.toEventType(''), SseEventType.unknown);
    });

    test('names are matched exactly, not loosely', () {
      // A near-miss must NOT silently resolve to a real event — that would be
      // worse than dropping it, because it would act on the wrong thing.
      expect(SseService.toEventType('order_cancelled'), SseEventType.unknown);
      expect(SseService.toEventType('ORDER-CANCELLED'), SseEventType.unknown);
      expect(SseService.toEventType('new-order '), SseEventType.unknown);
    });
  });
}

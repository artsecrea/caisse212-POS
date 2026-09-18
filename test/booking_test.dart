import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/booking_models.dart';

/// The booking contract has a few rules that are easy to break quietly and
/// expensive to break in a shop:
///
///   * a slot's status is derived from the clock and never stored;
///   * every instant on the wire is UTC while every instant on screen is local;
///   * the agenda uses **overlap** semantics, so a booking that runs past
///     midnight belongs to both days;
///   * `value` is expected money, net of discounts and without TVA — a
///     forecast, not takings.
///
/// A regression in any of them shows up as a barber staring at a diary that
/// says the 09:00 cut has not started yet, at noon — or a shop banking a
/// number that is not revenue.

void main() {
  group('bookingTimeStatus', () {
    final start = DateTime(2026, 8, 24, 9, 0);
    final end = DateTime(2026, 8, 24, 9, 30);

    test('before the start it is upcoming', () {
      expect(
        bookingTimeStatus(start, end, now: DateTime(2026, 8, 24, 8, 59)),
        BookingTimeStatus.notYet,
      );
    });

    test('the start instant is already in progress', () {
      // Half-open on the left: at exactly 09:00 the customer is in the chair.
      expect(bookingTimeStatus(start, end, now: start),
          BookingTimeStatus.inProgress);
    });

    test('between start and end it is in progress', () {
      expect(
        bookingTimeStatus(start, end, now: DateTime(2026, 8, 24, 9, 15)),
        BookingTimeStatus.inProgress,
      );
    });

    test('the end instant is done, not still running', () {
      // Half-open on the right, so a slot cannot read as both running and
      // finished on the tick it ends.
      expect(bookingTimeStatus(start, end, now: end), BookingTimeStatus.done);
    });

    test('after the end it is done', () {
      expect(
        bookingTimeStatus(start, end, now: DateTime(2026, 8, 24, 12, 0)),
        BookingTimeStatus.done,
      );
    });

    test('a zero-length booking is never in progress', () {
      expect(
          bookingTimeStatus(start, start, now: start), BookingTimeStatus.done);
    });
  });

  group('AgendaBookingDto', () {
    Map<String, dynamic> nested({
      String start = '2026-08-24T08:00:00Z',
      String? end = '2026-08-24T08:30:00Z',
    }) =>
        {
          'id': 42,
          'planStartAt': start,
          if (end != null) 'planEndAt': end,
          'planWaiterId': 4,
          'planResourceId': 5,
          'state': 'PENDING',
          'value': 150.0,
          'note': 'fringe',
          'updatedAt': '2026-08-23T10:00:00Z',
          'order': {'id': 2, 'code': 'ORD-2', 'clientId': 9},
          'product': {'id': 3, 'name': 'Haircut'},
          'customer': {
            'id': 9,
            'firstName': 'Sam',
            'lastName': 'Ito',
            'phone': '0600',
          },
          'waiter': {'id': 4, 'firstName': 'Rae', 'lastName': 'Ng'},
          'resource': {'id': 5, 'name': 'Chair 2', 'type': 'CHAIR'},
          // Derived server-side from the clock; must not survive into a model
          // that outlives the response.
          'timeStatus': 'NOT_YET',
        };

    test('reads the nested order/product/customer/waiter/resource objects', () {
      final b = AgendaBookingDto.fromJson(nested());
      expect(b.orderProductId, 42);
      expect(b.orderId, 2);
      expect(b.orderCode, 'ORD-2');
      expect(b.productName, 'Haircut');
      expect(b.customerName, 'Sam Ito');
      expect(b.customerPhone, '0600');
      expect(b.planWaiterName, 'Rae Ng');
      expect(b.planResourceName, 'Chair 2');
      expect(b.planResourceType, 'CHAIR');
      expect(b.value, 150.0);
    });

    test('still reads the flat shape an older backend sends', () {
      final b = AgendaBookingDto.fromJson({
        'orderProductId': 7,
        'orderCode': 'ORD-7',
        'productName': 'Shave',
        'customerName': 'Kim',
        'planStartAt': '2026-08-24T08:00:00Z',
        'planEndAt': '2026-08-24T08:20:00Z',
        'planWaiterName': 'Rae',
      });
      expect(b.orderProductId, 7);
      expect(b.orderCode, 'ORD-7');
      expect(b.productName, 'Shave');
      expect(b.customerName, 'Kim');
      expect(b.planWaiterName, 'Rae');
    });

    test('UTC instants land as local times', () {
      final b = AgendaBookingDto.fromJson(nested());
      expect(b.planStartAt.isUtc, isFalse);
      expect(b.planStartAt.toUtc(), DateTime.utc(2026, 8, 24, 8, 0));
      expect(b.planEndAt.difference(b.planStartAt), const Duration(minutes: 30));
    });

    test('a missing end does not produce a backwards window', () {
      final b = AgendaBookingDto.fromJson(nested(end: null));
      expect(b.planEndAt.isBefore(b.planStartAt), isFalse);
      expect(b.hasWindow, isFalse);
    });

    test('overlap puts a booking on every day it touches', () {
      // 23:30 -> 00:15 the next morning.
      final b = AgendaBookingDto.fromJson({
        'id': 1,
        'planStartAt': DateTime(2026, 8, 24, 23, 30).toUtc().toIso8601String(),
        'planEndAt': DateTime(2026, 8, 25, 0, 15).toUtc().toIso8601String(),
      });

      final day24 = DateTime(2026, 8, 24);
      final day25 = DateTime(2026, 8, 25);
      final day26 = DateTime(2026, 8, 26);

      expect(b.overlaps(day24, day25), isTrue, reason: 'the day it starts');
      expect(b.overlaps(day25, day26), isTrue, reason: 'the day it ends');
      expect(b.overlaps(day26, day26.add(const Duration(days: 1))), isFalse);
    });

    test('a booking that ends exactly at midnight does not spill over', () {
      final b = AgendaBookingDto.fromJson({
        'id': 1,
        'planStartAt': DateTime(2026, 8, 24, 23, 0).toUtc().toIso8601String(),
        'planEndAt': DateTime(2026, 8, 25).toUtc().toIso8601String(),
      });
      expect(b.overlaps(DateTime(2026, 8, 25), DateTime(2026, 8, 26)), isFalse);
    });

    test('the line state is carried but is not a booking status', () {
      final b = AgendaBookingDto.fromJson(nested());
      expect(b.lineState, 'PENDING');
    });
  });

  group('AgendaPage', () {
    Map<String, dynamic> item(int id, {double value = 100, String? day}) => {
          'id': id,
          'planStartAt': '${day ?? '2026-08-24'}T08:00:00Z',
          'planEndAt': '${day ?? '2026-08-24'}T09:00:00Z',
          'value': value,
        };

    test('reads the data + summary envelope', () {
      final page = AgendaPage.fromResponse({
        'data': [item(1), item(2)],
        'summary': {
          'count': 2,
          'reservedValue': 200.0,
          'days': [
            {'date': '2026-08-24', 'count': 2, 'reservedValue': 200.0},
          ],
        },
      });
      expect(page.items, hasLength(2));
      expect(page.summary.count, 2);
      expect(page.summary.reservedValue, 200.0);
      expect(page.summary.days.single.count, 2);
    });

    test('derives a summary when the backend answers a bare array', () {
      final page = AgendaPage.fromResponse([
        item(1, value: 60),
        item(2, value: 40, day: '2026-08-25'),
      ]);
      expect(page.summary.count, 2);
      expect(page.summary.reservedValue, 100.0);
      expect(page.summary.days, hasLength(2));
      expect(page.summary.days.first.date.isBefore(page.summary.days.last.date),
          isTrue);
    });

    test('drops rows that cannot be placed or rescheduled', () {
      final page = AgendaPage.fromResponse([
        item(1),
        // no line id — nothing /schedule could address
        {'planStartAt': '2026-08-24T08:00:00Z', 'planEndAt': '2026-08-24T09:00:00Z'},
        // zero-length window — nothing to draw
        {'id': 3, 'planStartAt': '2026-08-24T08:00:00Z', 'planEndAt': '2026-08-24T08:00:00Z'},
      ]);
      expect(page.items.map((i) => i.orderProductId), [1]);
    });

    test('an unexpected body is empty, not an exception', () {
      expect(AgendaPage.fromResponse('nonsense').items, isEmpty);
      expect(AgendaPage.fromResponse(null).summary.count, 0);
    });
  });

  group('ScheduleConflict', () {
    test('a resource conflict reports how full it is', () {
      final c = ScheduleConflict.fromJson(
          {'message': 'Room is full', 'current': 2, 'capacity': 2});
      expect(c.isResource, isTrue);
      expect(c.current, 2);
      expect(c.capacity, 2);
    });

    test('a provider conflict is not a resource conflict', () {
      // Provider capacity is always 1, so there is no occupancy to report.
      final c = ScheduleConflict.fromJson({'message': 'Rae is busy'});
      expect(c.isResource, isFalse);
      expect(c.capacity, isNull);
    });

    test('an empty body still yields something sayable', () {
      expect(ScheduleConflict.fromJson(const {}).message, isNotEmpty);
    });
  });

  group('AvailabilityResponse', () {
    test('no candidates means no availability, not an error', () {
      final a = AvailabilityResponse.fromJson({
        'productId': 3,
        'date': '2026-08-24',
        'serviceDurationMinutes': 30,
        'candidates': const [],
      });
      expect(a.hasAnyAvailability, isFalse);
      expect(a.serviceDurationMinutes, 30);
    });

    test('a candidate with no free windows also means no availability', () {
      final a = AvailabilityResponse.fromJson({
        'productId': 3,
        'serviceDurationMinutes': 30,
        'candidates': [
          {'waiterId': 11, 'waiterName': 'Rae', 'freeIntervals': const []},
        ],
      });
      expect(a.hasAnyAvailability, isFalse);
    });

    test('free intervals arrive as local times', () {
      final a = AvailabilityResponse.fromJson({
        'productId': 3,
        'serviceDurationMinutes': 45,
        'requiresResource': true,
        'eligibleResourceIds': [7, 8],
        'resolvedResourceId': 7,
        'candidates': [
          {
            'waiterId': 4,
            'waiterName': 'Rae',
            'freeIntervals': [
              {'start': '2026-08-24T08:00:00Z', 'end': '2026-08-24T12:00:00Z'},
            ],
          },
        ],
      });
      expect(a.hasAnyAvailability, isTrue);
      expect(a.requiresResource, isTrue);
      expect(a.eligibleResourceIds, [7, 8]);
      expect(a.resolvedResourceId, 7);

      final interval = a.candidates.single.freeIntervals.single;
      expect(interval.start.isUtc, isFalse);
      expect(interval.length, const Duration(hours: 4));
    });
  });
}

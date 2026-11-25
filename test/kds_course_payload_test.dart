import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/socket_models.dart';
import 'package:caisse212/services/kitchen_timing.dart';

/// What the KDS needs to time lines by preparation time and to hold a course
/// until the earlier ones are done: the product's time, when a line was
/// finished, and the whole order's course progress (every station).
void main() {
  final t0 = DateTime(2026, 11, 24, 12, 0);
  DateTime at(int m) => t0.add(Duration(minutes: m));

  OrderProduct row(
    int id, {
    String state = 'PENDING',
    int? courseNo,
    DateTime? kitchenAt,
    DateTime? readyAt,
    DateTime? servedAt,
  }) =>
      OrderProduct(
        id: id,
        orderId: 1,
        productId: id,
        quantity: 1,
        unitaryPrice: 10,
        unitaryTva: 0,
        unitaryDiscount: 0,
        manualDiscount: 0,
        cost: 0,
        state: state,
        courseNo: courseNo,
        kdsPrintedQuantity: 0,
        orderTicketPrintedQuantity: 0,
        canceledQuantity: 0,
        kitchenAt: kitchenAt,
        readyAt: readyAt,
        servedAt: servedAt,
        updatedAt: t0,
      );

  group('kitchenDoneAt', () {
    test('ready time first, then served time', () {
      expect(kitchenDoneAt(row(1, state: 'READY', readyAt: at(5))), at(5));
      // A KDS "done" goes straight to COMPLETED, which only stamps servedAt.
      expect(kitchenDoneAt(row(1, state: 'COMPLETED', servedAt: at(7))),
          at(7));
      expect(
          kitchenDoneAt(row(1,
              state: 'DELIVERED', readyAt: at(5), servedAt: at(9))),
          at(5));
    });

    test('a line still to make has none, whatever stamps it kept', () {
      expect(kitchenDoneAt(row(1, state: 'PENDING', readyAt: at(5))), isNull);
      expect(kitchenDoneAt(row(1, state: 'PREPARING')), isNull);
    });

    test('a finished line from before the stamps existed has none', () {
      expect(kitchenDoneAt(row(1, state: 'COMPLETED')), isNull);
    });
  });

  group('kdsCourseLines', () {
    test('only course-tagged lines, cancelled and held ones left out', () {
      final lines = kdsCourseLines([
        row(1, courseNo: 1, state: 'COMPLETED', kitchenAt: t0, servedAt: at(8)),
        row(2, courseNo: 2, kitchenAt: t0),
        row(3, kitchenAt: t0), // a drink, no course
        row(4, courseNo: 1, state: 'CANCELED', kitchenAt: t0),
        row(5, courseNo: 3, state: 'ONHOLD', kitchenAt: t0),
        row(6, courseNo: 99, kitchenAt: t0), // not a course
      ], fallback: t0);
      expect(lines.map((l) => l.id), [1, 2]);
      expect(lines.first.doneAt, at(8));
      expect(lines.last.doneAt, isNull);
    });

    test('no tagged line: nothing to send', () {
      expect(kdsCourseLines([row(1, kitchenAt: t0)], fallback: t0), isEmpty);
    });

    test('a row older than kitchenAt falls back to the order time', () {
      final lines = kdsCourseLines([row(1, courseNo: 2)], fallback: at(-3));
      expect(lines.single.kitchenAt, at(-3));
    });
  });

  group('wire format', () {
    SocketOrderProductModel line({int? prepMinutes, DateTime? doneAt}) =>
        SocketOrderProductModel(
          id: 1,
          productId: 1,
          productName: 'Tagine',
          quantity: 1,
          unitaryPrice: 10,
          state: 'PENDING',
          components: const [],
          prepMinutes: prepMinutes,
          doneAt: doneAt,
        );

    test('prep time and done time ride on the line when known', () {
      final json = line(prepMinutes: 25, doneAt: at(4)).toJson();
      expect(json['prepMinutes'], 25);
      expect(json['doneAt'], '2026-11-24T12:04:00.000');
      final back = SocketOrderProductModel.fromJson(json);
      expect(back.prepMinutes, 25);
      expect(back.doneAt, at(4));
    });

    test('left off the wire when unknown', () {
      final json = line().toJson();
      expect(json.containsKey('prepMinutes'), isFalse);
      expect(json.containsKey('doneAt'), isFalse);
    });

    test('course lines ride on the order only when there are some', () {
      SocketOrderModel order(List<KdsCourseLine> courseLines) =>
          SocketOrderModel(
            id: 1,
            code: 'A1',
            status: 'COMPLETED',
            type: 'DINE_IN',
            priority: 0,
            date: t0,
            products: [line()],
            courseLines: courseLines,
          );
      expect(order(const []).toJson().containsKey('courseLines'), isFalse);
      final json = order([
        KdsCourseLine(
            id: 7, courseNo: 1, state: 'READY', kitchenAt: t0, doneAt: at(6)),
      ]).toJson();
      expect(json['courseLines'], [
        {
          'id': 7,
          'courseNo': 1,
          'state': 'READY',
          'kitchenAt': '2026-11-24T12:00:00.000',
          'doneAt': '2026-11-24T12:06:00.000',
        }
      ]);
    });
  });
}

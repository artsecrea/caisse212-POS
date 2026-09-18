import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/table_occupancy.dart';

/// Whether a table is still genuinely held.
///
/// Occupancy is a pointer that whichever path finishes an order is expected to
/// clear, across six or seven paths. One that forgets strands a table showing
/// occupied with nobody at it. These pin the rule that recomputes the answer
/// instead of trusting every path to remember — so the two ways to get it
/// wrong are freeing a table people are still sitting at, and leaving one held
/// forever. Both are here.

void main() {
  group('is the order settled', () {
    test('every line paid', () {
      expect(isOrderSettled(['PAID', 'PAID']), isTrue);
    });

    test('a voided line does not block it', () {
      // The original bug this replaced: one cancelled line left an order
      // permanently un-settleable and its table permanently held.
      expect(isOrderSettled(['PAID', 'CANCELED']), isTrue);
      expect(isOrderSettled(['PAID', 'CANCELLED']), isTrue,
          reason: 'both spellings appear in this codebase');
    });

    test('one outstanding line is enough to keep it open', () {
      expect(isOrderSettled(['PAID', 'PENDING']), isFalse);
      expect(isOrderSettled(['PAID', 'PREPARING']), isFalse);
    });

    test('all voided and nothing paid is not settled', () {
      // Nobody paid anything. That is a cancelled order, and it is released
      // for being cancelled rather than for being settled.
      expect(isOrderSettled(['CANCELED', 'CANCELED']), isFalse);
    });

    test('no lines at all is not settled', () {
      expect(isOrderSettled([]), isFalse);
    });
  });

  group('should the table be released', () {
    TableReleaseReason? reason({
      bool orderExists = true,
      String status = 'COMPLETED',
      List<String> lines = const ['PAID'],
      bool freeOnPayment = true,
    }) =>
        tableReleaseReason(
          orderExists: orderExists,
          orderStatus: status,
          lineStates: lines,
          freeOnPayment: freeOnPayment,
        );

    test('a pointer to an order that no longer exists', () {
      // Nothing else can ever clear this one: every other path starts from the
      // order, and the order is gone.
      expect(reason(orderExists: false), TableReleaseReason.danglingOrder);
      expect(reason(orderExists: false, freeOnPayment: false),
          TableReleaseReason.danglingOrder,
          reason: 'a dangling pointer is released whatever the setting says');
    });

    test('a cancelled order releases its table either way', () {
      expect(reason(status: 'CANCELED'), TableReleaseReason.orderCancelled);
      expect(reason(status: 'CANCELED', freeOnPayment: false),
          TableReleaseReason.orderCancelled);
      expect(reason(status: 'cancelled'), TableReleaseReason.orderCancelled,
          reason: 'case and spelling both vary in the wild');
    });

    test('a settled order releases only when the till is set to', () {
      expect(reason(lines: ['PAID', 'CANCELED']),
          TableReleaseReason.orderSettled);
      expect(reason(lines: ['PAID', 'CANCELED'], freeOnPayment: false), isNull,
          reason: 'paid customers still sitting at the table keep it');
    });

    test('an order still being served keeps its table', () {
      expect(reason(lines: ['PAID', 'PENDING']), isNull);
    });

    test('an empty order keeps its table', () {
      // More likely one being built than one finished. Freeing it under the
      // cashier would be worse than leaving it.
      expect(reason(lines: []), isNull);
    });

    test('the order status is never what decides settled', () {
      // Orders here are born COMPLETED so the cloud is not left holding a
      // stale intermediate state. Reading that as "finished" would free the
      // table of every order the moment it was created.
      expect(reason(status: 'COMPLETED', lines: ['PENDING']), isNull);
      expect(reason(status: 'PENDING', lines: ['PAID']),
          TableReleaseReason.orderSettled);
    });
  });
}

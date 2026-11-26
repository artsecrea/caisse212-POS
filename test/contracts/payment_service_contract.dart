import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/services/payment_service.dart';

/// What a [PaymentService] must do, whoever implements it: the local service
/// runs these on the till's database, a hub-backed one will run them against
/// the hub with its own harness.
abstract class PaymentHarness {
  PaymentService get payments;

  /// An order with [lines] unpaid lines; returns its id and the line ids.
  Future<({int orderId, List<int> lineIds})> orderWithLines(int lines);

  /// A paid ticket on [orderId] carrying [lineIds], inside a session that is
  /// still open unless [sessionEnded].
  Future<int> paidTicket(int orderId, List<int> lineIds,
      {bool sessionEnded = false});

  Future<({String method, double amount, int printCount, bool isSynced})?>
      ticket(int ticketId);
  Future<int?> ticketOfLine(int lineId);

  Future<void> dispose();
}

void paymentServiceContract(
    String name, Future<PaymentHarness> Function() make) {
  group('$name honours the PaymentService contract', () {
    late PaymentHarness h;

    setUp(() async => h = await make());
    tearDown(() => h.dispose());

    test('a draft split is saved, replaced whole, and cleared', () async {
      final o = await h.orderWithLines(2);
      final a = o.lineIds[0], b = o.lineIds[1];

      await h.payments.saveDraftSplit(o.orderId, [
        (orderProductId: a, draftIndex: 0, quantity: 1),
        (orderProductId: b, draftIndex: 1, quantity: 2),
      ]);
      expect((await h.payments.draftSplit(o.orderId)).toSet(), {
        (orderProductId: a, draftIndex: 0, quantity: 1.0),
        (orderProductId: b, draftIndex: 1, quantity: 2.0),
      });

      await h.payments.saveDraftSplit(
          o.orderId, [(orderProductId: a, draftIndex: 0, quantity: 3)]);
      expect(await h.payments.draftSplit(o.orderId),
          [(orderProductId: a, draftIndex: 0, quantity: 3.0)],
          reason: 'a new arrangement replaces the old one entirely');

      await h.payments.clearDraftSplit(o.orderId);
      expect(await h.payments.draftSplit(o.orderId), isEmpty);
    });

    test('a print is counted, not sent back to the cloud as an edit',
        () async {
      final o = await h.orderWithLines(1);
      final t = await h.paidTicket(o.orderId, o.lineIds);

      await h.payments.recordPrint(t);
      await h.payments.recordPrint(t);

      final row = (await h.ticket(t))!;
      expect(row.printCount, 2);
      expect(row.isSynced, isTrue);
    });

    test('an edited ticket keeps its new method and amount, and is resent',
        () async {
      final o = await h.orderWithLines(1);
      final t = await h.paidTicket(o.orderId, o.lineIds);

      await h.payments.editTicket(t, paymentMethod: 'CARD', amount: 7.5);

      final row = (await h.ticket(t))!;
      expect(row.method, 'CARD');
      expect(row.amount, 7.5);
      expect(row.isSynced, isFalse);
    });

    test('a deleted ticket leaves its lines unpaid', () async {
      final o = await h.orderWithLines(2);
      final t = await h.paidTicket(o.orderId, o.lineIds);

      await h.payments.deleteTicket(t);

      expect(await h.ticket(t), isNull);
      for (final l in o.lineIds) {
        expect(await h.ticketOfLine(l), isNull);
      }
    });

    test('a ticket of a closed session cannot be deleted', () async {
      final o = await h.orderWithLines(1);
      final t = await h.paidTicket(o.orderId, o.lineIds, sessionEnded: true);

      await expectLater(h.payments.deleteTicket(t), throwsA(anything));
      expect(await h.ticket(t), isNotNull);
    });
  });
}

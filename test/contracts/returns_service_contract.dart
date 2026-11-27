import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart' show Order;
import 'package:caisse212/domain/models/exchange.dart';
import 'package:caisse212/domain/services/returns_service.dart';
import 'package:caisse212/services/refund_service.dart' show RefundLineDraft;

/// What a [ReturnsService] must do, whoever implements it: the local service
/// runs these on the till's database, a hub-backed one will run them against
/// the hub with its own harness. The lookup needs a server answering, so it
/// is not here.
abstract class ReturnsHarness {
  ReturnsService get returns;

  /// A Z, open unless [closed], with an open session in it.
  Future<({int zId, int sessionId})> zWithSession({bool closed = false});

  /// A sale paid in full in [sessionId]: one line of 2 × 50.
  Future<({Order order, int lineId})> sale(int sessionId);

  /// A new order of one unpaid line at [total], saved, as Pay leaves it.
  Future<({int orderId, String code})> newOrder(double total);

  /// Whether every line of [orderId] is settled on a ticket.
  Future<bool> linesPaid(int orderId);

  Future<void> dispose();
}

void returnsServiceContract(
    String name, Future<ReturnsHarness> Function() make) {
  group('$name honours the ReturnsService contract', () {
    late ReturnsHarness h;

    setUp(() async => h = await make());
    tearDown(() => h.dispose());

    test('a refund is recorded against its lines and listed', () async {
      final now = await h.zWithSession();
      final sold = await h.sale(now.sessionId);

      final refund = await h.returns.refund(
        order: sold.order,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: sold.lineId, quantity: 1)],
        sessionId: now.sessionId,
      );

      expect(await h.returns.refundedQuantities(sold.order.id),
          {sold.lineId: 1.0});
      expect((await h.returns.refundsForOrder(sold.order.id)).map((r) => r.id),
          [refund.id]);
      expect(
          (await h.returns.refunds(sessionId: now.sessionId)).map((r) => r.id),
          [refund.id]);
      expect((await h.returns.slipFor(refund)).code, refund.code);
    });

    test('a sale of a closed Z is an earlier sale; one of the open Z is not',
        () async {
      final before = await h.zWithSession(closed: true);
      final now = await h.zWithSession();
      final old = await h.sale(before.sessionId);
      final recent = await h.sale(now.sessionId);

      Future<bool> closed(Order o) async =>
          (await h.returns.policyContextFor(o,
                  currentZId: now.zId, currentZDay: DateTime.now()))
              .saleZClosed;

      expect(await closed(old.order), isTrue);
      expect(await closed(recent.order), isFalse);
    });

    test('an exchange refunds the goods back and pays the new order with them',
        () async {
      final now = await h.zWithSession();
      final sold = await h.sale(now.sessionId);
      final next = await h.newOrder(80);

      final result = await h.returns.settleExchange(
        draft: ExchangeDraft(order: sold.order, lines: [
          ExchangeReturnLine(
              orderProductId: sold.lineId,
              name: 'Shirt',
              quantity: 1,
              amount: 50,
              restock: true),
        ]),
        newOrderId: next.orderId,
        newOrderCode: next.code,
        newTotal: 80,
        payMethod: 'CASH',
        backMethod: 'CASH',
        sessionId: now.sessionId,
        zDay: null,
      );

      expect(result.refund.exchangeOrderId, next.orderId);
      expect(result.settlement.creditUsed, 50);
      expect(result.settlement.customerPays, 30);
      expect(await h.linesPaid(next.orderId), isTrue);
      expect(await h.returns.refundedQuantities(sold.order.id),
          {sold.lineId: 1.0});
    });

    test('publishing offline neither throws nor loses the refund', () async {
      final now = await h.zWithSession();
      final sold = await h.sale(now.sessionId);
      await h.returns.refund(
        order: sold.order,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: sold.lineId, quantity: 2)],
        sessionId: now.sessionId,
      );

      await h.returns.publish();

      expect(await h.returns.refundsForOrder(sold.order.id), hasLength(1));
    });
  });
}

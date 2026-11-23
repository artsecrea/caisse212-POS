import 'package:drift/drift.dart';

import '../core/enums.dart';
import '../data/database/app_database.dart';
import '../domain/models/exchange.dart';
import 'refund_service.dart';

class ExchangeResult {
  final Refund refund;
  final ExchangeSettlement settlement;

  /// The ticket the new order's lines were settled on (the receipt's).
  final int lastTicketId;
  final String lastTicketNum;

  const ExchangeResult({
    required this.refund,
    required this.settlement,
    required this.lastTicketId,
    required this.lastTicketNum,
  });
}

/// Writes an exchange: the refund for the goods brought back, the new order's
/// EXCHANGE credit ticket and the customer's ticket for the difference, and
/// the new order's lines settled — all in ONE transaction, so a crash can
/// never leave a refund without its new sale or the reverse.
///
/// The new order must already be saved (the till saves it on Pay, as for any
/// sale). Completing it (status, table) is the caller's next step, exactly as
/// after a normal payment.
class ExchangeService {
  final AppDatabase _db;
  ExchangeService(this._db);

  Future<ExchangeResult> settle({
    required ExchangeDraft draft,
    required int newOrderId,
    required String newOrderCode,
    required double newTotal,
    // The customer's method for the difference (TransactionType value).
    required String payMethod,
    // The refund method for money given back (refund vocabulary).
    required String backMethod,
    required int sessionId,
    required DateTime? zDay,
    int? refundedBy,
    String? posName,
  }) async {
    final settlement = settleExchange(draft.credit, newTotal);
    final refunds = RefundService(_db);

    late Refund refund;
    int? lastTicketId;
    var lastTicketNum = '';
    await _db.transaction(() async {
      // The refund. Its credit part is not paid back; only the remainder (if
      // any) goes out by [backMethod].
      refund = await refunds.createRefund(
        order: draft.order,
        method: settlement.paidBack > 0.005 ? backMethod : 'CASH',
        lines: [
          for (final l in draft.lines)
            RefundLineDraft(
              orderProductId: l.orderProductId,
              quantity: l.quantity,
              amount: l.amountOverridden ? l.amount : null,
              restock: l.restock,
            ),
        ],
        reason: draft.reason,
        reasonCode: draft.reasonCode,
        approvedBy: draft.approvedBy,
        policyFlags: draft.policyFlags,
        earlierSale: draft.earlierSale,
        refundedElsewhere: draft.refundedElsewhere,
        refundedBy: refundedBy,
        sessionId: sessionId,
        zDay: zDay,
        posName: posName,
        exchangeAmount: settlement.creditUsed,
        exchangeOrderId: newOrderId,
        exchangeOrderCode: newOrderCode,
      );

      final existing = await (_db.select(_db.tickets)
            ..where((t) => t.orderId.equals(newOrderId)))
          .get();
      var num = existing
          .map((t) => int.tryParse(t.num) ?? 0)
          .fold<int>(0, (a, b) => a > b ? a : b);
      Future<int> ticket(String method, double amount, {String? refundCode}) {
        num++;
        lastTicketNum = num.toString().padLeft(4, '0');
        return _db.into(_db.tickets).insert(TicketsCompanion.insert(
              num: lastTicketNum,
              orderId: newOrderId,
              paymentMethod: method,
              amount: amount,
              sessionId: Value(sessionId),
              zDay: Value(zDay),
              isPaid: const Value(true),
              date: Value(DateTime.now()),
              exchangeRefundCode: Value(refundCode),
            ));
      }

      if (settlement.creditUsed > 0.005) {
        lastTicketId = await ticket(
            TransactionType.exchange.value, settlement.creditUsed,
            refundCode: refund.code);
      }
      if (settlement.customerPays > 0.005) {
        lastTicketId = await ticket(payMethod, settlement.customerPays);
      }
      // New goods worth nothing still get their paper.
      lastTicketId ??= await ticket(TransactionType.exchange.value, 0,
          refundCode: refund.code);

      // Every open line of the new order is settled on the last ticket.
      await (_db.update(_db.orderProducts)
            ..where((p) =>
                p.orderId.equals(newOrderId) &
                p.ticketId.isNull() &
                p.state.isNotValue('CANCELED')))
          .write(OrderProductsCompanion(
        ticketId: Value(lastTicketId),
        updatedAt: Value(DateTime.now()),
      ));
    });

    return ExchangeResult(
      refund: refund,
      settlement: settlement,
      lastTicketId: lastTicketId!,
      lastTicketNum: lastTicketNum,
    );
  }
}

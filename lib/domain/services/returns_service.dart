import '../../data/database/app_database.dart' show Order, Refund;
import '../../services/exchange_service.dart' show ExchangeResult;
import '../../services/refund_service.dart'
    show RefundLineDraft, RefundOrderContext, RefundSlipData;
import '../models/exchange.dart' show ExchangeDraft;
import '../models/refund_policy.dart' show RefundPolicyFlag;

/// An order found for a refund, and what other tills already gave back of
/// each of its lines (by local line id). [order] is null when not found.
typedef RefundableOrder = ({Order? order, Map<int, double> refundedElsewhere});

/// Money given back for goods returned, and goods exchanged. An interface
/// because a refund is checked against every till's refunds of the order:
/// standalone, against the cloud (`LocalReturnsService`); linked to a hub,
/// the hub will answer.
abstract interface class ReturnsService {
  /// Find [orderCode] to refund: the business's latest copy of the order
  /// (this till's unsent changes go first) and what other tills refunded
  /// of it. Needs the network; throws a `RefundLookupException` when the
  /// lookup itself fails.
  Future<RefundableOrder> lookup(String orderCode);

  /// What the refund policy needs to know about [order]: whether it was
  /// sold in an earlier, closed Z.
  Future<RefundOrderContext> policyContextFor(
    Order order, {
    required int? currentZId,
    required DateTime? currentZDay,
  });

  /// Quantities of each line of [orderId] this till already refunded.
  Future<Map<int, double>> refundedQuantities(int orderId);

  /// Record a refund of [lines] of [order] and tell the admins. Nothing is
  /// sent: [publish] does, after the slip has printed.
  Future<Refund> refund({
    required Order order,
    required String method,
    required List<RefundLineDraft> lines,
    String? reason,
    String? reasonCode,
    int? approvedBy,
    List<RefundPolicyFlag> policyFlags = const [],
    bool earlierSale = false,
    Map<int, double> refundedElsewhere = const {},
    int? refundedBy,
    int? sessionId,
    DateTime? zDay,
    String? posName,
  });

  /// Settle an exchange: the refund of what came back and the payment of the
  /// difference on [newOrderId], which is then completed like any paid
  /// order. The admins are told; the payment is logged as [cashierName]'s.
  /// Nothing prints or is sent: [publish] with [newOrderId] does the sending.
  Future<ExchangeResult> settleExchange({
    required ExchangeDraft draft,
    required int newOrderId,
    required String newOrderCode,
    required double newTotal,
    required String payMethod,
    required String backMethod,
    required int sessionId,
    required DateTime? zDay,
    int? refundedBy,
    String? cashierName,
    String? posName,
  });

  /// Send the refunds not sent yet — after [exchangeOrderId], the order an
  /// exchange paid for, since its refund names it. Best-effort: offline,
  /// they stay queued.
  Future<void> publish({int? exchangeOrderId});

  /// What a refund slip prints for [refund].
  Future<RefundSlipData> slipFor(Refund refund);

  /// [orderId]'s refunds, newest first.
  Future<List<Refund>> refundsForOrder(int orderId);

  /// This till's refunds, newest first: of [sessionId], or since [since].
  Future<List<Refund>> refunds({int? sessionId, DateTime? since});
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart';
import '../domain/models/exchange.dart';
import '../domain/models/refund_policy.dart';
import '../domain/services/returns_service.dart';
import '../providers/database_providers.dart';
import '../providers/order_provider.dart' show orderRepositoryProvider;
import 'activity_log_service.dart';
import 'exchange_service.dart';
import 'local_payment_service.dart';
import 'pos_notifications.dart' show notifyRefund;
import 'refund_service.dart';

/// [ReturnsService] on this till's own database, checked against the cloud:
/// the standalone till. Each action is the sequence the refund and exchange
/// dialogs ran themselves.
class LocalReturnsService implements ReturnsService {
  LocalReturnsService(this._ref);

  final Ref _ref;

  RefundService get _refunds => _ref.read(refundServiceProvider);

  @override
  Future<RefundableOrder> lookup(String orderCode) async {
    final api = _ref.read(apiServiceProvider);
    final sync = _ref.read(dataSyncServiceProvider);
    final orderRepo = _ref.read(orderRepositoryProvider);

    // An order of this till not on the server yet has nothing to check
    // against: push it first.
    final before = await orderRepo.findOrderRowByCode(orderCode);
    if (before != null && !before.isSynced) {
      await sync.syncSingleOrder(before.id);
    }

    final item = await api.fetchOrderForRefund(orderCode);
    final serverRefunds = await api.fetchRefundsForRefund(orderCode);

    // Take the server's copy (lines, payments, cancellations). Skipped by
    // applyServerOrder only when this till still has an edit to push, in
    // which case the local row is the newer one anyway.
    await sync.applyServerOrder(item);
    final order = await orderRepo.findOrderRowByCode(orderCode);
    if (order == null) return (order: null, refundedElsewhere: const <int, double>{});
    return (
      order: order,
      refundedElsewhere: otherTillsRefunded(
        serverRefunds: serverRefunds,
        localCodes: await _refunds.localRefundCodes(order.id),
        localIdByServerId: await _refunds.localIdsByServerId(order.id),
      ),
    );
  }

  @override
  Future<RefundOrderContext> policyContextFor(
    Order order, {
    required int? currentZId,
    required DateTime? currentZDay,
  }) =>
      _refunds.policyContextFor(order,
          currentZId: currentZId, currentZDay: currentZDay);

  @override
  Future<Map<int, double>> refundedQuantities(int orderId) =>
      _refunds.refundedQuantitiesForOrder(orderId);

  @override
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
  }) async {
    final created = await _refunds.createRefund(
      order: order,
      method: method,
      lines: lines,
      reason: reason,
      reasonCode: reasonCode,
      approvedBy: approvedBy,
      policyFlags: policyFlags,
      earlierSale: earlierSale,
      refundedElsewhere: refundedElsewhere,
      refundedBy: refundedBy,
      sessionId: sessionId,
      zDay: zDay,
      posName: posName,
    );
    _notify(created);
    return created;
  }

  @override
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
  }) async {
    final result = await _ref.read(exchangeServiceProvider).settle(
          draft: draft,
          newOrderId: newOrderId,
          newOrderCode: newOrderCode,
          newTotal: newTotal,
          payMethod: payMethod,
          backMethod: backMethod,
          sessionId: sessionId,
          zDay: zDay,
          refundedBy: refundedBy,
          posName: posName,
        );

    // Complete the new order (status, table) exactly as a payment does.
    try {
      await _ref.read(paymentServiceProvider).completeIfSettled(newOrderId);
    } catch (e) {
      Logger.instance.error('Exchange order completion failed: $e');
    }

    _notify(result.refund);
    await _ref.read(activityLogServiceProvider).logPayment(
          newTotal.toStringAsFixed(2),
          newOrderCode,
          userId: refundedBy,
          username: cashierName,
        );
    return result;
  }

  void _notify(Refund refund) => notifyRefund(
        _ref.read,
        orderCode: refund.orderCode,
        amount: refund.totalAmount,
        method: refund.method,
        reason: refund.reason,
      );

  @override
  Future<void> publish({int? exchangeOrderId}) async {
    final sync = _ref.read(dataSyncServiceProvider);
    try {
      // syncRefundsBulk would push the order too, but the exchange's new
      // order goes first by itself so its refund finds it.
      if (exchangeOrderId != null) await sync.syncSingleOrder(exchangeOrderId);
      await sync.syncRefundsBulk();
    } catch (e) {
      Logger.instance.warning('Refund sync deferred: $e');
    }
  }

  @override
  Future<RefundSlipData> slipFor(Refund refund) => _refunds.slipFor(refund);

  @override
  Future<List<Refund>> refundsForOrder(int orderId) =>
      _refunds.refundsForOrder(orderId);

  @override
  Future<List<Refund>> refunds({int? sessionId, DateTime? since}) =>
      _refunds.localRefunds(sessionId: sessionId, since: since);
}

/// The refund and exchange actions for the screens. A hub-linked till
/// overrides this one provider; nothing else changes.
final returnsServiceProvider =
    Provider<ReturnsService>((ref) => LocalReturnsService(ref));

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/order_models.dart';
import '../domain/services/order_service.dart';
import '../providers/database_providers.dart';
import '../providers/order_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_manager_provider.dart';

/// [OrderService] on this till's own database: the standalone till. Each
/// action is the [OrderRepository] call the screens made, plus the steps
/// every caller had to remember after it.
class LocalOrderService implements OrderService {
  LocalOrderService(this._ref);

  final Ref _ref;

  OrderRepository get _orders => _ref.read(orderRepositoryProvider);

  @override
  Future<SubmittedCart> submitCart(
    CurrentOrder cart, {
    required int userId,
    required int sessionId,
    bool headerOnly = false,
  }) async {
    final orders = _orders;
    final int orderId;
    if (cart.isSaved()) {
      await orders.updateOrder(cart, headerOnly: headerOnly);
      orderId = cart.orderId!;
    } else {
      orderId = await orders.saveOrder(
        cart,
        userId,
        status: _ref.read(settingsProvider).defaultOrderStatus,
        sessionId: sessionId,
      );
      if (cart.tableId != null) {
        await orders.setTableOrderId(cart.tableId!, orderId);
      }
    }
    return (orderId: orderId, reloaded: await orders.getOrderById(orderId));
  }

  @override
  Future<void> updateCart(CurrentOrder cart, {bool headerOnly = false}) =>
      _orders.updateOrder(cart, headerOnly: headerOnly);

  /// Frees the tables only once the cancel has landed: releasing first would
  /// hand the table to the next party while the order it still carries failed
  /// to cancel. Keyed on the tables' own pointers, so a stale table id in a
  /// cart cannot leave one held.
  @override
  Future<void> cancelOrder(int orderId, {String? reason, int? userId}) async {
    await _orders.updateOrderStatus(
      orderId,
      'CANCELED',
      cancellationReason: reason,
      userId: userId,
    );
    await _orders.freeTablesForOrder(orderId);
  }

  /// The status write already pushes in the background; the back office also
  /// waits for a push of its own so it can say whether the change landed.
  @override
  Future<bool> changeStatus(int orderId, String status,
      {String? reason}) async {
    if (status == 'CANCELED') {
      await cancelOrder(orderId, reason: reason);
    } else {
      await _orders.updateOrderStatus(orderId, status,
          cancellationReason: reason);
    }
    if (status == 'ONHOLD' || !_ref.read(networkStateProvider)) return false;
    try {
      return await _ref.read(syncManagerProvider.notifier).autoSyncOrder(orderId);
    } catch (_) {
      // The order is already unsynced; the periodic sync retries it.
      return false;
    }
  }

  @override
  Future<void> setTags(int orderId, List<int> tagIds) async {
    await _orders.setOrderTags(orderId, tagIds);
    unawaited(_ref.read(dataSyncServiceProvider).pushOrderTags());
  }

  @override
  Future<void> resetOrderNumber(int? sessionId, {String mode = 'session'}) =>
      _orders.resetOrderNumber(sessionId, mode: mode);
}

/// The order actions for the screens. A hub-linked till overrides this one
/// provider; nothing else changes.
final orderServiceProvider =
    Provider<OrderService>((ref) => LocalOrderService(ref));

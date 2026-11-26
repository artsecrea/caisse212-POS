import '../models/order_models.dart' show CurrentOrder;

/// A cart once written: its order id, and the order read back from the store
/// with every line's id and printed quantities — null only if it vanished.
typedef SubmittedCart = ({int orderId, CurrentOrder? reloaded});

/// What a till does to an order as a whole. An interface because tills
/// sharing a hub must agree on every order: a standalone till answers from
/// its own database (`LocalOrderService`), a hub-linked one will ask the hub.
///
/// One method is one intent, and it carries everything that intent implies —
/// the caller does not free the table after a cancel or push the tags after
/// setting them.
abstract interface class OrderService {
  /// Write the till's [cart]: a new order is created in [sessionId] by
  /// [userId] at the default status and seated at its table; a saved one is
  /// updated ([headerOnly] keeps its lines, for a waiter's order the cashier
  /// may not edit).
  Future<SubmittedCart> submitCart(
    CurrentOrder cart, {
    required int userId,
    required int sessionId,
    bool headerOnly = false,
  });

  /// Write a saved [cart] back — its header alone when [headerOnly].
  Future<void> updateCart(CurrentOrder cart, {bool headerOnly = false});

  /// Cancel [orderId] and free every table it holds. [reason] is the
  /// cancellation reason, [userId] the till user who cancelled.
  Future<void> cancelOrder(int orderId, {String? reason, int? userId});

  /// Move [orderId] to [status] from the back office. `CANCELED` is a
  /// [cancelOrder]. Returns true when the change has already reached the
  /// cloud; false when it is still queued, or when [status] is `ONHOLD`,
  /// which stays on this till.
  Future<bool> changeStatus(int orderId, String status, {String? reason});

  /// Replace [orderId]'s tags and send them to the cloud.
  Future<void> setTags(int orderId, List<int> tagIds);
}

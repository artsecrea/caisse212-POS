import '../../services/kitchen_board_service.dart' show KitchenBoardOrder;

/// What the kitchen changes on an order: a line's stage, the rush flag, and
/// the "ready" call to a delivery platform. An interface because a KDS and a
/// till sharing a hub must see the same kitchen: a standalone till answers
/// from its own database (`LocalKitchenService`), a hub-linked one will ask
/// the hub.
abstract interface class KitchenService {
  /// The open lines of [sessionId] as the kitchen board shows them, live.
  Stream<List<KitchenBoardOrder>> watchBoard(int sessionId);

  /// Move line [lineId] to [newState] as a KDS bump does: stage stamps, the
  /// waiter's "ready" event, the order rollup and its log. [source] names who
  /// moved it in that log. False when the line does not exist.
  Future<bool> setLineState(int lineId, String newState,
      {String source = 'POS'});

  /// Flag or unflag [orderId] as a rush, shown first on every KDS.
  Future<void> setRush(int orderId, bool rush);

  /// Tell the delivery platform a platform order is ready for pickup, once,
  /// and only while online. Failures are logged, never thrown.
  Future<void> signalOrderReady(int orderId);
}

import '../../data/database/app_database.dart' show Serial, SerialConflict;

/// Unit-level stock: the serial numbers of serial-tracked products, which
/// one is in a basket, and the conflicts when two tills sold the same unit.
/// An interface because a unit is one for the whole shop: standalone, this
/// till keeps its synced copy (`LocalSerialService`); linked to a hub, the
/// hub will hold the units.
abstract interface class SerialService {
  Future<Serial?> byId(int id);

  /// Serial number by id, so a refund slip names the exact unit going back.
  /// Ids no longer in the cache are simply absent.
  Future<Map<int, String>> serialNumbersByIds(Iterable<int> ids);

  /// Tracked = the product's flag OR the specific variant's flag. Either side
  /// can turn it on, so a variant of an untracked product is still tracked.
  Future<bool> isTracked({required int productId, int? variantId});

  /// Hold a unit while it sits in a basket, so a second line on this terminal
  /// cannot claim it. Server truth overwrites this on the next catalogue pull,
  /// which is what recovers a crash mid-order.
  Future<void> reserve(int serialId);

  Future<void> releaseAll(Iterable<int> serialIds);

  /// Reactive variant for the picker, so another terminal's sale (arriving via
  /// a catalogue pull) removes the unit from an open list.
  Stream<List<Serial>> watchAvailableFor(int productId);

  /// Units this till sold that went to another order and nobody has said they
  /// have seen yet, newest first.
  Stream<List<SerialConflict>> watchUnacknowledgedConflicts();

  /// Acknowledged, not deleted: somebody will ask what happened to that box
  /// weeks from now. Every row gets the same [at].
  Future<void> acknowledgeConflicts(Iterable<int> ids, DateTime at);
}

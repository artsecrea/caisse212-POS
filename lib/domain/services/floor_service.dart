import '../../data/database/app_database.dart' show AreaTable;
import '../models/order_models.dart' show CurrentOrder;

/// Who holds which table. An interface because table occupancy is the first
/// thing two tills sharing a hub fight over: a standalone till answers from
/// its own database (`LocalFloorService`), a hub-linked one will ask the hub.
///
/// Everything here is an action or a read the floor must agree on across
/// tills. Linking an order to a table as it is saved, and freeing it as it
/// is paid, belong to the order and payment actions, not here.
abstract interface class FloorService {
  /// Every table with the order it holds, as it changes.
  Stream<List<AreaTable>> watchTables();

  /// The order occupying [tableId], or null when the table is free.
  Future<CurrentOrder?> openTable(int tableId);

  /// Move [orderId] from [fromTableId] to [toTableId]. Throws, and moves
  /// nothing, when [toTableId] already holds another order.
  Future<void> transfer(
    int orderId, {
    required int fromTableId,
    required int toTableId,
  });

  /// Release [tableId] by hand, whatever it holds.
  Future<void> clearTable(int tableId);

  /// Free every table whose order is gone or cancelled — or settled, when
  /// [freeOnPayment] — and return how many were freed. A repair for tables
  /// left held by a path that forgot to let go.
  Future<int> reconcile({required bool freeOnPayment});

  /// Free every table held by an order of [sessionId].
  Future<void> freeTablesForSession(int sessionId);
}

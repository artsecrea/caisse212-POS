import '../../data/database/app_database.dart' show AreaTable;
import '../models/order_models.dart' show CurrentOrder;

/// Who is acting on the floor. The till's signed-in cashier is the default;
/// a waiter acts from the waiter app, and is logged as themselves rather than
/// as whoever happens to be signed in on the till.
sealed class FloorActor {
  const FloorActor();
}

class ByCashier extends FloorActor {
  const ByCashier();
}

class ByWaiter extends FloorActor {
  const ByWaiter(this.waiterId);

  final int waiterId;
}

/// A transfer refused because the target table holds another order.
class TableOccupiedException implements Exception {
  const TableOccupiedException(this.tableName);

  final String tableName;

  @override
  String toString() => 'Exception: Table $tableName already has an open order '
      '— settle or move it first';
}

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

  /// Move [orderId] to [toTableId], freeing [fromTableId] (null for an order
  /// on no table yet). Throws [TableOccupiedException], and moves nothing,
  /// when [toTableId] already holds another order.
  Future<void> transfer(
    int orderId, {
    int? fromTableId,
    required int toTableId,
    FloorActor by = const ByCashier(),
  });

  /// Release [tableId] by hand, whatever it holds.
  Future<void> clearTable(int tableId, {FloorActor by = const ByCashier()});

  /// Free every table whose order is gone or cancelled — or settled, when
  /// [freeOnPayment] — and return how many were freed. A repair for tables
  /// left held by a path that forgot to let go.
  Future<int> reconcile({required bool freeOnPayment});

  /// Free every table held by an order of [sessionId].
  Future<void> freeTablesForSession(int sessionId);
}

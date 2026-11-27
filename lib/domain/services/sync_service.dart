import '../../data/database/app_database.dart' show Refund;
import '../models/reservation_models.dart' show ReservationLink;
import '../models/session_rules.dart' show SessionRules;

/// The cloud sync as the screens drive it: the "sync now" buttons, the pull
/// at sign-in, the push after a close, the dump and wipe at sign-out, and the
/// sync inspector. An interface because a hub-linked till does not sync — the
/// hub does — so these become the hub's: standalone, the till syncs itself
/// (`LocalSyncService`, over `DataSyncService`).
abstract interface class SyncService {
  /// Progress of [syncAll], for the first sign-in's screen.
  set onProgress(void Function(String message, double progress)? report);

  /// Ids of orders a pull just changed, so an open order can reload.
  Stream<int> get syncedOrderUpdates;

  /// Orders the server saved while another order held their reservation.
  Stream<ReservationLink> get reservationDuplicates;

  /// Pull everything: users, catalogue, floor, settings, orders.
  Future<void> syncAll();

  /// Send the queued writes.
  Future<void> syncPendingOperations();

  Future<int> syncSessions();
  Future<int> syncOrders();
  Future<int> syncTickets();
  Future<int> syncCashMovements();
  Future<int> syncRefunds();

  /// Send [orderId]'s tickets, within [deadline]. True when they went.
  Future<bool> syncTicketsForOrder(int orderId, {Duration? deadline});

  /// Re-read the sessions the server holds open.
  Future<({int applied, int skipped})> refreshOpenSessions();

  Future<int> syncIntegrationMappings();
  Future<int> syncPendingNotifications();

  /// This terminal's session rules, or null when they could not be read.
  Future<SessionRules?> syncSessionRules();

  /// Save a copy of the database before [clearAllData]; its path, or null.
  Future<String?> dumpDatabaseBeforeClear();

  /// Wipe the till's data (sign-out of the tenant).
  Future<void> clearAllData();

  /// Refunds the server refused, set aside.
  Future<List<Refund>> parkedRefunds();
  Future<void> unparkRefund(int refundId);

  /// Where each pull cursor stands.
  Future<Map<String, String?>> deltaSyncMeta();
  Future<void> resetOrdersCursor();
  Future<void> resetPaymentsCursor();
  Future<void> pullAllDeltas();
}

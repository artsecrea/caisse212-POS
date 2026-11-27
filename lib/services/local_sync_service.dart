import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../domain/models/reservation_models.dart';
import '../domain/models/session_rules.dart';
import '../domain/services/sync_service.dart';
import '../providers/database_providers.dart';
import 'api_service.dart';
import 'data_sync_service.dart';

/// [SyncService] for the standalone till: each call is the [DataSyncService]
/// one the screens made, with this till's preferences where it needs them.
class LocalSyncService implements SyncService {
  LocalSyncService(this._sync, this._prefs);

  final DataSyncService _sync;
  final SharedPreferences _prefs;

  @override
  set onProgress(void Function(String message, double progress)? report) =>
      _sync.onProgress = report;

  @override
  Stream<int> get syncedOrderUpdates => _sync.syncedOrderUpdatedStream;

  @override
  Stream<ReservationLink> get reservationDuplicates =>
      _sync.reservationDuplicates;

  @override
  Future<void> syncAll() => _sync.syncAllData();

  @override
  Future<void> syncPendingOperations() => _sync.syncPendingOperations();

  @override
  Future<int> syncSessions() => _sync.syncSessionsBulk();

  @override
  Future<int> syncOrders() => _sync.syncOrdersBulk();

  @override
  Future<int> syncTickets() => _sync.syncTicketsBulk();

  @override
  Future<int> syncCashMovements() => _sync.syncCashMovementsBulk();

  @override
  Future<int> syncRefunds() => _sync.syncRefundsBulk();

  @override
  Future<bool> syncTicketsForOrder(int orderId, {Duration? deadline}) =>
      _sync.syncTicketsForOrder(orderId, deadline: deadline);

  @override
  Future<({int applied, int skipped})> refreshOpenSessions() =>
      _sync.refreshOpenSessions();

  @override
  Future<int> syncIntegrationMappings() => _sync.syncIntegrationMappings();

  @override
  Future<int> syncPendingNotifications() => _sync.syncPendingNotifications();

  @override
  Future<SessionRules?> syncSessionRules() => _sync.syncSessionRules();

  @override
  Future<String?> dumpDatabaseBeforeClear() => _sync.dumpDatabaseBeforeClear();

  @override
  Future<void> clearAllData() => _sync.clearAllData();

  @override
  Future<List<Refund>> parkedRefunds() => _sync.parkedRefunds();

  @override
  Future<void> unparkRefund(int refundId) => _sync.unparkRefund(refundId);

  @override
  Future<Map<String, String?>> deltaSyncMeta() =>
      _sync.getDeltaSyncMeta(_prefs);

  @override
  Future<void> resetOrdersCursor() => _sync.resetOrdersCursor(_prefs);

  @override
  Future<void> resetPaymentsCursor() => _sync.resetPaymentsCursor(_prefs);

  @override
  Future<void> pullAllDeltas() => _sync.pullAllDeltas(_prefs);
}

/// The sync for the screens. A hub-linked till overrides this provider and
/// [syncServiceFactoryProvider]; nothing else changes.
final syncServiceProvider = Provider<SyncService>((ref) => LocalSyncService(
    ref.watch(dataSyncServiceProvider), ref.watch(sharedPreferencesProvider)));

/// A sync of its own, through [api], for the screens that must not share
/// [syncServiceProvider]'s (see `dataSyncServiceFactoryProvider`).
final syncServiceFactoryProvider =
    Provider<SyncService Function(ApiService api, [SharedPreferences? prefs])>(
        (ref) {
  final make = ref.watch(dataSyncServiceFactoryProvider);
  final tillPrefs = ref.watch(sharedPreferencesProvider);
  return (api, [prefs]) => LocalSyncService(make(api, prefs), prefs ?? tillPrefs);
});

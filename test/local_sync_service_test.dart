import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/session_rules.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/local_sync_service.dart';

/// Records which sync the adapter asked for, and with which preferences.
class _Recorder extends DataSyncService {
  _Recorder(super.db, super.api);

  final calls = <String>[];
  final prefsSeen = <SharedPreferences>[];

  @override
  Future<void> syncAllData() async => calls.add('syncAllData');
  @override
  Future<void> syncPendingOperations() async => calls.add('syncPendingOperations');
  @override
  Future<int> syncSessionsBulk({int batchSize = 50}) async {
    calls.add('syncSessionsBulk');
    return 0;
  }

  @override
  Future<int> syncOrdersBulk({int batchSize = 50}) async {
    calls.add('syncOrdersBulk');
    return 0;
  }

  @override
  Future<int> syncTicketsBulk({int batchSize = 100}) async {
    calls.add('syncTicketsBulk');
    return 0;
  }

  @override
  Future<int> syncCashMovementsBulk({int batchSize = 50}) async {
    calls.add('syncCashMovementsBulk');
    return 0;
  }

  @override
  Future<int> syncRefundsBulk({int batchSize = 50}) async {
    calls.add('syncRefundsBulk');
    return 0;
  }

  @override
  Future<bool> syncTicketsForOrder(int orderId, {Duration? deadline}) async {
    calls.add('syncTicketsForOrder $orderId $deadline');
    return true;
  }

  @override
  Future<SessionRules?> syncSessionRules() async {
    calls.add('syncSessionRules');
    return null;
  }

  @override
  Future<Map<String, String?>> getDeltaSyncMeta(SharedPreferences prefs) async {
    prefsSeen.add(prefs);
    return const {};
  }

  @override
  Future<void> resetOrdersCursor(SharedPreferences prefs) async =>
      prefsSeen.add(prefs);

  @override
  Future<void> resetPaymentsCursor(SharedPreferences prefs) async =>
      prefsSeen.add(prefs);

  @override
  Future<void> pullAllDeltas(SharedPreferences prefs) async =>
      prefsSeen.add(prefs);
}

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late _Recorder sync;
  late LocalSyncService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sync = _Recorder(db, ApiService(prefs));
    service = LocalSyncService(sync, prefs);
  });
  tearDown(() => db.close());

  test('each sync is the DataSyncService one the screens called', () async {
    await service.syncAll();
    await service.syncPendingOperations();
    await service.syncSessions();
    await service.syncOrders();
    await service.syncTickets();
    await service.syncCashMovements();
    await service.syncRefunds();
    await service.syncTicketsForOrder(4, deadline: const Duration(seconds: 10));
    await service.syncSessionRules();

    expect(sync.calls, [
      'syncAllData',
      'syncPendingOperations',
      'syncSessionsBulk',
      'syncOrdersBulk',
      'syncTicketsBulk',
      'syncCashMovementsBulk',
      'syncRefundsBulk',
      'syncTicketsForOrder 4 0:00:10.000000',
      'syncSessionRules',
    ]);
  });

  test('the cursor tools run on this till’s preferences', () async {
    await service.deltaSyncMeta();
    await service.resetOrdersCursor();
    await service.resetPaymentsCursor();
    await service.pullAllDeltas();

    expect(sync.prefsSeen, [prefs, prefs, prefs, prefs]);
  });

  test('progress reports reach the sync', () {
    void report(String m, double p) {}
    service.onProgress = report;
    expect(sync.onProgress, same(report));
  });
}

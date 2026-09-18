import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';

/// Which refunds are still owed to the server.
///
/// A refund is money already handed to a customer. If the terminal ever stops
/// re-sending one, that cash never reaches the books and the only trace is a
/// line on a screen nobody is watching. The POS used to drop any refund the
/// server had refused once — safe only if every refusal were permanent, which
/// the backend confirms it is not: a transient database error inside the
/// per-refund transaction arrives in the same failure map as an over-refund,
/// with nothing in the message to tell them apart.
///
/// Re-sending is safe in both directions: a failed refund rolled back, and an
/// accepted one is recognised by `code` and returns as skipped.

Future<DataSyncService> serviceWith(AppDatabase db) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  // Nothing here reaches the network: only the queue predicate is exercised.
  return DataSyncService(db, ApiService(prefs), prefs);
}

Future<int> insertRefund(
  AppDatabase db, {
  required String code,
  bool isSynced = false,
  String? syncError,
}) =>
    db.into(db.refunds).insert(RefundsCompanion.insert(
          code: code,
          orderId: 1,
          orderCode: 'T1-0001',
          method: const Value('CASH'),
          totalAmount: const Value(10.0),
          refundedAt: Value(DateTime(2026, 9, 1)),
          isSynced: Value(isSynced),
          syncError: Value(syncError),
        ));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DataSyncService sync;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sync = await serviceWith(db);
  });
  tearDown(() => db.close());

  test('a fresh refund is queued', () async {
    await insertRefund(db, code: 'RF-1');
    final queued = await sync.refundsAwaitingSync();
    expect(queued.map((r) => r.code), ['RF-1']);
  });

  test('a refund the server refused is STILL queued', () async {
    // The regression that matters. Excluding this row is how a refund is
    // lost: one transient failure and it is never sent again.
    await insertRefund(db, code: 'RF-2', syncError: 'Over-refund on line 55');
    final queued = await sync.refundsAwaitingSync();
    expect(queued.map((r) => r.code), ['RF-2']);
  });

  test('a synced refund is not queued, error or no error', () async {
    await insertRefund(db, code: 'RF-3', isSynced: true);
    await insertRefund(db, code: 'RF-4', isSynced: true, syncError: 'stale');
    expect(await sync.refundsAwaitingSync(), isEmpty);
  });

  test('refused and fresh refunds queue together', () async {
    // One bad record must not hold back the good ones behind it — the server
    // runs each refund in its own transaction, so a batch cannot be poisoned.
    await insertRefund(db, code: 'RF-5', syncError: 'Unknown order');
    await insertRefund(db, code: 'RF-6');
    final queued = await sync.refundsAwaitingSync();
    expect(queued.map((r) => r.code).toSet(), {'RF-5', 'RF-6'});
  });

  test('the batch size is respected', () async {
    for (var i = 0; i < 5; i++) {
      await insertRefund(db, code: 'RF-B$i');
    }
    expect((await sync.refundsAwaitingSync(3)).length, 3);
  });

  test('parkedRefunds still lists what is currently failing', () async {
    // The screen needs to show these; it just no longer means "given up on".
    await insertRefund(db, code: 'RF-7', syncError: 'Over-refund');
    await insertRefund(db, code: 'RF-8');
    final parked = await sync.parkedRefunds();
    expect(parked.map((r) => r.code), ['RF-7']);
  });
}

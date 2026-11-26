import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/services/cash_session_service.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/local_cash_session_service.dart';

import 'contracts/cash_session_service_contract.dart';

/// The till's own database behind [CashSessionService], driven by the shared
/// contract a hub-backed service will have to pass too.
class _LocalCashSessionHarness implements CashSessionHarness {
  _LocalCashSessionHarness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;
  var _seq = 0;

  static Future<_LocalCashSessionHarness> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    return _LocalCashSessionHarness(db, container);
  }

  @override
  CashSessionService get sessions => container.read(cashSessionServiceProvider);

  @override
  Future<int> session(String status) => db.into(db.cashSessions).insert(
      CashSessionsCompanion.insert(
          code: 'S${++_seq}',
          cashierId: 1,
          moneyAtStart: 0,
          status: Value(status),
          pausedAt: status == 'paused'
              ? Value(DateTime.now().subtract(const Duration(minutes: 5)))
              : const Value.absent()));

  @override
  Future<int> seatedOrderIn(int sessionId) async {
    final table = await db
        .into(db.areaTables)
        .insert(AreaTablesCompanion.insert(name: 'T${++_seq}'));
    final order = await db.into(db.orders).insert(OrdersCompanion.insert(
        code: 'O$_seq', sessionId: Value(sessionId), tableId: Value(table)));
    await (db.update(db.areaTables)..where((t) => t.id.equals(table)))
        .write(AreaTablesCompanion(orderId: Value(order)));
    return table;
  }

  @override
  Future<int?> holderOf(int tableId) async =>
      (await (db.select(db.areaTables)..where((t) => t.id.equals(tableId)))
              .getSingle())
          .orderId;

  @override
  Future<double?> countedCashOf(int sessionId) async =>
      (await (db.select(db.cashSessions)..where((s) => s.id.equals(sessionId)))
              .getSingle())
          .countedCash;

  @override
  Future<String?> statusOf(int sessionId) async =>
      (await (db.select(db.cashSessions)..where((s) => s.id.equals(sessionId)))
              .getSingleOrNull())
          ?.status;

  @override
  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The admin notice behind a pause asks the platform whether the till is
  // online before it tries to send.
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  cashSessionServiceContract(
      'LocalCashSessionService', _LocalCashSessionHarness.create);
}

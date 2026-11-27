import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/session_rules.dart';
import 'package:caisse212/domain/services/day_service.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/session_rules_provider.dart';
import 'package:caisse212/services/local_day_service.dart';

import 'contracts/day_service_contract.dart';

/// The till's own database behind [DayService], offline, driven by the
/// shared contract a hub-backed service will have to pass too.
class _LocalDayHarness implements DayHarness {
  _LocalDayHarness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;
  var _seq = 0;

  static Future<_LocalDayHarness> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    return _LocalDayHarness(db, container);
  }

  @override
  DayService get days => container.read(dayServiceProvider);

  @override
  Future<User> cashier() async {
    final id = await db.into(db.users).insert(UsersCompanion.insert(
        username: 'cashier${++_seq}',
        password: 'x',
        firstName: 'C',
        lastName: '',
        type: 'CASHIER'));
    return (db.select(db.users)..where((u) => u.id.equals(id))).getSingle();
  }

  @override
  Future<void> rules({String? openMode, String? closeMode}) => container
      .read(sessionRulesProvider.notifier)
      .updateRules(SessionRules(zOpenMode: openMode, zCloseMode: closeMode));

  @override
  Future<int> openSessionIn(int zId) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
          code: 'S${++_seq}',
          cashierId: 1,
          moneyAtStart: 0,
          zId: Value(zId)));

  @override
  Future<int?> openZId() async =>
      (await (db.select(db.zs)..where((z) => z.status.equals('open')))
              .getSingleOrNull())
          ?.id;

  @override
  Future<String?> zStatus(int zId) async =>
      (await (db.select(db.zs)..where((z) => z.id.equals(zId)))
              .getSingleOrNull())
          ?.status;

  @override
  Future<String?> sessionStatus(int sessionId) async =>
      (await (db.select(db.cashSessions)..where((s) => s.id.equals(sessionId)))
              .getSingleOrNull())
          ?.status;

  @override
  Future<void> endSession(int sessionId) =>
      (db.update(db.cashSessions)..where((s) => s.id.equals(sessionId)))
          .write(const CashSessionsCompanion(status: Value('ended')));

  @override
  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Offline: the till plans its Z from its own rows, never the server's.
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  dayServiceContract('LocalDayService', _LocalDayHarness.create);
}

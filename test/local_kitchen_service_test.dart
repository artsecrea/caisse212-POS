import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/services/kitchen_service.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/local_kitchen_service.dart';

import 'contracts/kitchen_service_contract.dart';

/// The till's own database behind [KitchenService], driven by the shared
/// contract a hub-backed kitchen will have to pass too.
class _LocalKitchenHarness implements KitchenHarness {
  _LocalKitchenHarness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;
  var _seq = 0;

  static Future<_LocalKitchenHarness> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'Tajine', price: 10, finalPrice: 10));
    return _LocalKitchenHarness(db, container);
  }

  @override
  KitchenService get kitchen => container.read(kitchenServiceProvider);

  @override
  Future<({int orderId, List<int> lineIds})> openOrder(int sessionId,
      {int lines = 1}) async {
    final orderId = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'K${++_seq}',
          sessionId: Value(sessionId),
          status: const Value('COMPLETED'),
        ));
    final ids = [
      for (var i = 0; i < lines; i++)
        await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId, productId: 1, unitaryPrice: 10)),
    ];
    return (orderId: orderId, lineIds: ids);
  }

  Future<OrderProduct> _line(int id) =>
      (db.select(db.orderProducts)..where((l) => l.id.equals(id))).getSingle();

  Future<Order> _order(int id) =>
      (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();

  @override
  Future<String> stateOf(int lineId) async => (await _line(lineId)).state;

  @override
  Future<DateTime?> preparingAtOf(int lineId) async =>
      (await _line(lineId)).preparingAt;

  @override
  Future<String> orderStatusOf(int orderId) async =>
      (await _order(orderId)).status;

  @override
  Future<bool> isRush(int orderId) async => (await _order(orderId)).priority > 0;

  @override
  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // A terminal rollup kicks a sync, which asks the platform whether the till
  // is online.
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  kitchenServiceContract('LocalKitchenService', _LocalKitchenHarness.create);
}

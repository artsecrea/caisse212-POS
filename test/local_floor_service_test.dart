import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/domain/services/floor_service.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/local_floor_service.dart';

import 'contracts/floor_service_contract.dart';

/// The till's own database behind [FloorService], driven by the shared
/// contract — the same cases a hub-backed floor will have to pass.
class _LocalFloorHarness implements FloorHarness {
  _LocalFloorHarness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;
  var _seq = 0;

  static Future<_LocalFloorHarness> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'P', price: 10, finalPrice: 10));
    return _LocalFloorHarness(db, container);
  }

  @override
  FloorService get floor => container.read(floorServiceProvider);

  @override
  Future<int> addTable(String name) =>
      db.into(db.areaTables).insert(AreaTablesCompanion.insert(name: name));

  @override
  Future<int> addSession() => db.into(db.cashSessions).insert(
      CashSessionsCompanion.insert(
          code: 'S${++_seq}', cashierId: 1, moneyAtStart: 0));

  @override
  Future<int> openOrderAt(
    int tableId, {
    String lineState = 'PENDING',
    bool paid = false,
    String status = 'COMPLETED',
    int? sessionId,
  }) async {
    final order = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'O${++_seq}',
          status: Value(status),
          tableId: Value(tableId),
          sessionId: Value(sessionId),
        ));
    int? ticketId;
    if (paid) {
      ticketId = await db.into(db.tickets).insert(TicketsCompanion.insert(
          num: '0001',
          orderId: order,
          paymentMethod: 'CASH',
          amount: 10,
          isPaid: const Value(true)));
    }
    await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
        orderId: order,
        productId: 1,
        unitaryPrice: 10,
        state: Value(lineState),
        ticketId: Value(ticketId)));
    await (db.update(db.areaTables)..where((t) => t.id.equals(tableId)))
        .write(AreaTablesCompanion(orderId: Value(order)));
    return order;
  }

  @override
  Future<int?> holderOf(int tableId) async =>
      (await (db.select(db.areaTables)..where((t) => t.id.equals(tableId)))
              .getSingle())
          .orderId;

  @override
  Future<int?> tableOfOrder(int orderId) async =>
      (await (db.select(db.orders)..where((o) => o.id.equals(orderId)))
              .getSingle())
          .tableId;

  @override
  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

/// A floor that answers from somewhere else — what a hub-linked till does.
class _FakeFloor implements FloorService {
  @override
  Future<CurrentOrder?> openTable(int tableId) async => null;

  @override
  Stream<List<AreaTable>> watchTables() => const Stream.empty();

  @override
  Future<void> transfer(int orderId,
      {int? fromTableId,
      required int toTableId,
      FloorActor by = const ByCashier()}) async {}

  @override
  Future<void> clearTable(int tableId,
      {FloorActor by = const ByCashier()}) async {}

  @override
  Future<int> reconcile({required bool freeOnPayment}) async => 42;

  @override
  Future<void> freeTablesForSession(int sessionId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The repository kicks a sync after a transfer, which asks the platform
  // whether the till is online.
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  floorServiceContract('LocalFloorService', _LocalFloorHarness.create);

  test('one provider override swaps the floor for the whole app', () async {
    final h = await _LocalFloorHarness.create();
    final container = ProviderContainer(
      parent: h.container,
      overrides: [floorServiceProvider.overrideWithValue(_FakeFloor())],
    );
    addTearDown(() async {
      container.dispose();
      await h.dispose();
    });

    expect(await container.read(floorServiceProvider).reconcile(
        freeOnPayment: true), 42);
  });
}

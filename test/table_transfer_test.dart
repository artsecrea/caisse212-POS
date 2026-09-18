import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/order_provider.dart';

/// Moving an order between tables.
///
/// The floor's occupancy is a pointer (`area_tables.order_id`) and the order
/// names its table back (`orders.table_id`). A transfer has to move both, or
/// leave neither moved — and it must never point a table at a second order,
/// because `reconcileTableOccupancy` only ever RELEASES tables and so could
/// not repair a bill stranded off the floor.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late OrderRepository repo;

  Future<void> boot() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    repo = OrderRepository(db, container.read(_refProvider));
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await boot();
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<int> area() => db.into(db.areas).insert(AreasCompanion.insert(name: 'Main'));

  Future<int> table(int areaId, String name) => db
      .into(db.areaTables)
      .insert(AreaTablesCompanion.insert(name: name, areaId: Value(areaId)));

  Future<int> order(String code, {int? tableId, bool synced = true}) =>
      db.into(db.orders).insert(OrdersCompanion.insert(
            code: code,
            tableId: Value(tableId),
            isSynced: Value(synced),
          ));

  Future<AreaTable> readTable(int id) =>
      (db.select(db.areaTables)..where((t) => t.id.equals(id))).getSingle();

  Future<Order> readOrder(int id) =>
      (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();

  test('moves both pointers and flags the order for sync', () async {
    final a = await area();
    final from = await table(a, 'T1');
    final to = await table(a, 'T2');
    final id = await order('ORD1', tableId: from);
    await repo.setTableOrderId(from, id);

    await repo.transferOrderToTable(id, from, to);

    expect((await readTable(from)).orderId, isNull, reason: 'old table freed');
    expect((await readTable(to)).orderId, id, reason: 'new table holds it');
    expect((await readOrder(id)).tableId, to, reason: 'order names its table');
    expect((await readOrder(id)).isSynced, isFalse,
        reason: 'a table move is an order change the server must see');
  });

  test('refuses to land on a table that already has an order', () async {
    final a = await area();
    final from = await table(a, 'T1');
    final to = await table(a, 'T2');
    final moving = await order('ORD1', tableId: from);
    final sitting = await order('ORD2', tableId: to);
    await repo.setTableOrderId(from, moving);
    await repo.setTableOrderId(to, sitting);

    await expectLater(
      repo.transferOrderToTable(moving, from, to),
      throwsA(isA<Exception>()),
    );

    // Nothing moved: the whole transfer is one transaction, so a refusal must
    // leave the floor exactly as it was rather than half-applied.
    expect((await readTable(from)).orderId, moving);
    expect((await readTable(to)).orderId, sitting);
    expect((await readOrder(moving)).tableId, from);
    expect((await readOrder(sitting)).tableId, to);
  });

  test('re-transferring an order onto the table it already holds is allowed',
      () async {
    // The guard compares against the MOVING order, so a repeat of the same
    // move (a double tap, a retried sync) is not mistaken for a collision.
    final a = await area();
    final from = await table(a, 'T1');
    final to = await table(a, 'T2');
    final id = await order('ORD1', tableId: from);
    await repo.setTableOrderId(to, id);

    await repo.transferOrderToTable(id, from, to);

    expect((await readTable(to)).orderId, id);
    expect((await readOrder(id)).tableId, to);
  });
}

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_tag_codec.dart';
import 'package:caisse212/domain/services/order_service.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/local_order_service.dart';

import 'contracts/order_service_contract.dart';

/// The till's own database behind [OrderService], driven by the shared
/// contract a hub-backed service will have to pass too.
class _LocalOrderHarness implements OrderHarness {
  _LocalOrderHarness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;
  var _seq = 0;

  static Future<_LocalOrderHarness> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      // Offline, so nothing tries to reach a cloud.
      networkStateProvider.overrideWith((ref) => false),
    ]);
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'P', price: 10, finalPrice: 10));
    return _LocalOrderHarness(db, container);
  }

  @override
  OrderService get orders => container.read(orderServiceProvider);

  @override
  int get productId => 1;

  @override
  Future<int> openSession() => db.into(db.cashSessions).insert(
      CashSessionsCompanion.insert(
          code: 'S${++_seq}', cashierId: 1, moneyAtStart: 0));

  @override
  Future<int> addTable() => db
      .into(db.areaTables)
      .insert(AreaTablesCompanion.insert(name: 'T${++_seq}'));

  @override
  Future<int> lineCountOf(int orderId) async =>
      (await (db.select(db.orderProducts)
                ..where((l) => l.orderId.equals(orderId)))
              .get())
          .length;

  @override
  Future<({int orderId, int tableId, int ticketId})> seatedPaidOrder() async {
    final n = ++_seq;
    final tableId =
        await db.into(db.areaTables).insert(AreaTablesCompanion.insert(name: 'T$n'));
    final orderId = await db.into(db.orders).insert(OrdersCompanion.insert(
        code: 'O$n', status: const Value('COMPLETED'), tableId: Value(tableId)));
    final ticketId = await db.into(db.tickets).insert(TicketsCompanion.insert(
        num: '0001',
        orderId: orderId,
        paymentMethod: 'CASH',
        amount: 10,
        isPaid: const Value(true)));
    await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
        orderId: orderId,
        productId: 1,
        unitaryPrice: 10,
        ticketId: Value(ticketId)));
    await (db.update(db.areaTables)..where((t) => t.id.equals(tableId)))
        .write(AreaTablesCompanion(orderId: Value(orderId)));
    return (orderId: orderId, tableId: tableId, ticketId: ticketId);
  }

  Future<Order> _order(int id) =>
      (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();

  @override
  Future<String> statusOf(int orderId) async => (await _order(orderId)).status;

  @override
  Future<String?> cancellationReasonOf(int orderId) async =>
      (await _order(orderId)).cancellationReason;

  @override
  Future<int?> holderOf(int tableId) async =>
      (await (db.select(db.areaTables)..where((t) => t.id.equals(tableId)))
              .getSingle())
          .orderId;

  @override
  Future<bool> ticketCancelled(int ticketId) async =>
      (await (db.select(db.tickets)..where((t) => t.id.equals(ticketId)))
              .getSingle())
          .isCancelled;

  @override
  Future<List<int>> tagsOf(int orderId) async =>
      parseTagIds((await _order(orderId)).tagIds);

  @override
  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The status write's background push asks the platform whether the till
  // is online.
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  orderServiceContract('LocalOrderService', _LocalOrderHarness.create);
}

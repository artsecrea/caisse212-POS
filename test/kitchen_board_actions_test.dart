import 'dart:io' show HttpOverrides;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/kitchen_board_service.dart';
import 'package:caisse212/services/local_kitchen_service.dart';

/// What the POS kitchen board's actions do: move lines exactly as a KDS bump
/// would (stamps + the change-log entry the KDS polls on), and flag a rush.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  late AppDatabase db;
  late ProviderContainer container;
  late int orderId;
  late int lineId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(1), name: 'Tajine', price: 10, finalPrice: 10));
    orderId = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'K1',
          sessionId: const Value(1),
          status: const Value('COMPLETED'),
        ));
    lineId = await db.into(db.orderProducts).insert(
        OrderProductsCompanion.insert(
            orderId: orderId, productId: 1, unitaryPrice: 10));
  });
  tearDown(() async {
    container.dispose();
    await db.close();
  });

  Future<OrderProduct> line() =>
      (db.select(db.orderProducts)..where((l) => l.id.equals(lineId)))
          .getSingle();
  Future<int> logCount() async => (await db.select(db.orderLogs).get()).length;

  test('a line moved from the till is stamped and logged for the KDS',
      () async {
    final kitchen = container.read(kitchenServiceProvider);
    final before = await logCount();

    expect(await kitchen.setLineState(lineId, 'PREPARING'), isTrue);
    final cooking = await line();
    expect(cooking.state, 'PREPARING');
    expect(cooking.preparingAt, isNotNull);
    expect(await logCount(), greaterThan(before),
        reason: 'the KDS only sees changes through the change log');

    await kitchen.setLineState(lineId, 'COMPLETED');
    final done = await line();
    expect(done.state, 'COMPLETED');
    expect(done.servedAt, isNotNull);
  });

  test('an unknown line is reported, not invented', () async {
    expect(
        await container
            .read(kitchenServiceProvider)
            .setLineState(9999, 'PREPARING'),
        isFalse);
  });

  test('a rush rides the order priority and puts it first on the board',
      () async {
    final other = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'K0',
          sessionId: const Value(1),
          status: const Value('COMPLETED'),
        ));
    // K0's line is older, so it would come first without the rush.
    await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
        orderId: other,
        productId: 1,
        unitaryPrice: 10,
        kitchenAt: Value(DateTime.now().subtract(const Duration(hours: 1)))));

    await container.read(kitchenServiceProvider).setRush(orderId, true);
    final order = await (db.select(db.orders)
          ..where((o) => o.id.equals(orderId)))
        .getSingle();
    expect(order.priority, 1);

    final board = kitchenBoardView(
        await KitchenBoardService(db).watch(1).first, DateTime.now());
    expect(board.first.code, 'K1');
    expect(board.first.rush, isTrue);

    await container.read(kitchenServiceProvider).setRush(orderId, false);
    final cleared = kitchenBoardView(
        await KitchenBoardService(db).watch(1).first, DateTime.now());
    expect(cleared.first.code, 'K0');
  });
}

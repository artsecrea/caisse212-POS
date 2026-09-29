import 'dart:convert';
import 'dart:io' show HttpOverrides;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/server_provider.dart';
import 'package:caisse212/services/kds_feed_scope.dart';
import 'package:caisse212/services/server_service.dart';

/// The KDS feed's printer-style options (`unassigned`, `linked`, `types`,
/// `sources`), hit over real HTTP against a running [ServerService].
///
/// Catalogue: Tajine → Cuisine, Coca → Bar, Pain → no station. The Tajine
/// menu carries a "Coca" option linked to the Coca product.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  group('normalizeOrderSource', () {
    test('folds the stored origins onto the printer-rule set', () {
      expect(normalizeOrderSource(null), 'POS');
      expect(normalizeOrderSource('waiter'), 'WAITER');
      expect(normalizeOrderSource('DEALUP'), 'EXTERNAL');
      expect(normalizeOrderSource('KIOSK'), 'KIOSK');
    });
  });

  late AppDatabase db;
  late ProviderContainer container;
  late ServerService server;
  const port = 18121;
  final base = Uri.parse('http://127.0.0.1:$port');
  late int tajineLine;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);

    await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
        id: const Value(1), code: '1', cashierId: 1, moneyAtStart: 0.0));
    final session = await (db.select(db.cashSessions)
          ..where((s) => s.id.equals(1)))
        .getSingle();
    container.read(currentSessionProvider.notifier).state = session;

    await db.into(db.stations).insert(
        StationsCompanion.insert(id: const Value(1), name: 'Cuisine'));
    await db
        .into(db.stations)
        .insert(StationsCompanion.insert(id: const Value(2), name: 'Bar'));
    Future<void> product(int id, String name, int? station) =>
        db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: name,
            price: 10,
            finalPrice: 10,
            stationId: Value(station)));
    await product(10, 'Tajine', 1);
    await product(20, 'Coca', 2);
    await product(30, 'Pain', null);
    await db.into(db.components).insert(ComponentsCompanion.insert(
        id: const Value(5), name: 'Coca menu', linkedProductId: const Value(20)));

    Future<int> order(String code, String type, String? source) =>
        db.into(db.orders).insert(OrdersCompanion.insert(
              code: code,
              type: Value(type),
              source: Value(source),
              sessionId: const Value(1),
              status: const Value('COMPLETED'),
            ));
    Future<int> line(int orderId, int productId, {double qty = 1}) =>
        db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
              orderId: orderId,
              productId: productId,
              unitaryPrice: 10,
              quantity: Value(qty),
            ));

    final a = await order('A', 'DINE_IN', 'WAITER');
    tajineLine = await line(a, 10, qty: 2);
    await db.into(db.orderProductComponents).insert(
        OrderProductComponentsCompanion.insert(
            componentId: 5, orderProductId: tajineLine));
    await line(a, 30);
    final b = await order('B', 'TAKE_AWAY', null);
    await line(b, 10);

    server = container.read(serverServiceProvider);
    await server.start(port: port);
  });

  tearDown(() async {
    await server.stop();
    container.dispose();
    await db.close();
  });

  Future<Map<String, List<Map<String, dynamic>>>> feed(
      Map<String, String> q) async {
    final res = await http.get(base.replace(path: '/orders', queryParameters: q));
    expect(res.statusCode, 200, reason: res.body);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return {
      for (final o in body['orders'] as List)
        (o as Map<String, dynamic>)['code'] as String: [
          for (final p in o['products'] as List) p as Map<String, dynamic>
        ]
    };
  }

  test('a station KDS sees only its own lines by default', () async {
    final got = await feed({'station': 'Cuisine'});
    expect(got.keys, unorderedEquals(['A', 'B']));
    expect(got['A']!.map((p) => p['productName']), ['Tajine']);
    expect(await feed({'station': 'Bar'}), isEmpty);
  });

  test('unassigned=1 adds the stationless lines', () async {
    final got = await feed({'station': 'Cuisine', 'unassigned': '1'});
    expect(got['A']!.map((p) => p['productName']),
        unorderedEquals(['Tajine', 'Pain']));
  });

  test('linked=1 brings the menu drink to the bar, read-only', () async {
    final got = await feed({'station': 'Bar', 'linked': '1'});
    expect(got.keys, ['A']);
    final drink = got['A']!.single;
    expect(drink['productName'], 'Coca menu');
    expect(drink['quantity'], 2.0, reason: 'one per parent unit');
    expect(drink['id'], lessThan(0));
    expect(drink['parentLineId'], tajineLine);
    expect(drink['stationName'], 'Bar');
  });

  test('the kitchen does not get the drink twice', () async {
    final got = await feed({'station': 'Cuisine', 'linked': '1'});
    expect(got['A']!.map((p) => p['productName']), ['Tajine']);
  });

  test('types and sources filter whole orders', () async {
    expect((await feed({'station': 'Cuisine', 'types': 'TAKE_AWAY'})).keys,
        ['B']);
    expect((await feed({'station': 'Cuisine', 'sources': 'WAITER'})).keys,
        ['A']);
    expect(
        (await feed({'station': 'Cuisine', 'sources': 'POS'})).keys, ['B'],
        reason: 'a null source is the till\'s own');
  });

  test('no station = full order: every line of every order', () async {
    final got = await feed({});
    expect(got['A']!.map((p) => p['productName']),
        unorderedEquals(['Tajine', 'Pain']));
  });
}

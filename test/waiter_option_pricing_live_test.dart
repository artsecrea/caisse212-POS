import 'dart:convert';
import 'dart:io' show HttpOverrides;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/server_provider.dart';
import 'package:caisse212/services/server_service.dart';

/// The waiter API used to store whatever option price the tablet sent. It now
/// checks and prices options the way the till's product dialog does: only
/// what the product offers, within each group's min/max, at the catalogue
/// price with the group's free allowance. Create, add-product and
/// add-products all go through the same check.
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
  late ServerService server;
  const port = 18152;
  final base = Uri.parse('http://127.0.0.1:$port');

  // Burger (10) offers: Cheese 4.00 and Bacon 6.00 in "Extras" (max 2, one
  // free), Sauce 1.50 ungrouped with a 0.50 override, and Olives 2.00 86'd.
  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    final s = await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
        id: const Value(1), code: '1', cashierId: 1, moneyAtStart: 0.0));
    container.read(currentSessionProvider.notifier).state =
        await (db.select(db.cashSessions)..where((t) => t.id.equals(s)))
            .getSingle();
    await db.into(db.waiters).insert(
        WaitersCompanion.insert(id: const Value(1), firstName: 'Amina'));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(10), name: 'Burger', price: 50, finalPrice: 50));
    await db.into(db.componentGroups).insert(ComponentGroupsCompanion.insert(
        id: const Value(3),
        name: 'Extras',
        maxSelection: const Value(2),
        freeQuantity: const Value(1)));
    for (final c in [
      ComponentsCompanion.insert(
          id: const Value(1),
          name: 'Cheese',
          price: const Value(4),
          componentGroupId: const Value(3)),
      ComponentsCompanion.insert(
          id: const Value(2),
          name: 'Bacon',
          price: const Value(6),
          componentGroupId: const Value(3)),
      ComponentsCompanion.insert(
          id: const Value(4), name: 'Sauce', price: const Value(1.5)),
      ComponentsCompanion.insert(
          id: const Value(5),
          name: 'Olives',
          price: const Value(2),
          isActive: const Value(false)),
      ComponentsCompanion.insert(id: const Value(6), name: 'Not on burger'),
    ]) {
      await db.into(db.components).insert(c);
    }
    for (final link in [
      ProductComponentsCompanion.insert(productId: 10, componentId: 1),
      ProductComponentsCompanion.insert(productId: 10, componentId: 2),
      ProductComponentsCompanion.insert(
          productId: 10,
          componentId: 4,
          defaultPrice: const Value(0.5),
          maxQuantity: const Value(2)),
      ProductComponentsCompanion.insert(productId: 10, componentId: 5),
    ]) {
      await db.into(db.productComponents).insert(link);
    }
    server = container.read(serverServiceProvider);
    await server.start(port: port);
  });
  tearDown(() async {
    await server.stop();
    container.dispose();
    await db.close();
  });

  Map<String, dynamic> burger(List<Map<String, dynamic>> components) =>
      {'productId': 10, 'quantity': 1, 'components': components};

  Future<http.Response> create(List<Map<String, dynamic>> components) =>
      http.post(base.replace(path: '/waiters/orders'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'waiterId': 1,
            'type': 'TAKE_AWAY',
            'products': [burger(components)],
          }));

  Future<String> emptyOrder() async {
    final res = await create(const []);
    expect(res.statusCode, 201, reason: res.body);
    return (jsonDecode(res.body) as Map<String, dynamic>)['code'] as String;
  }

  Future<List<OrderProductComponent>> optionsOfLastLine() async {
    final line = (await db.select(db.orderProducts).get()).last;
    return (db.select(db.orderProductComponents)
          ..where((c) => c.orderProductId.equals(line.id))
          ..orderBy([(c) => OrderingTerm(expression: c.id)]))
        .get();
  }

  test('the catalogue sets the price, whatever the tablet says', () async {
    final res = await create([
      {'componentId': 4, 'quantity': 2, 'price': 99.0, 'name': 'Hack'},
    ]);
    expect(res.statusCode, 201, reason: res.body);
    final rows = await optionsOfLastLine();
    expect(rows.single.price, 0.5, reason: 'the product link override');
    expect(rows.single.quantity, 2);
    expect(rows.single.name, 'Sauce', reason: 'the catalogue name');
  });

  test('the free allowance covers the dearest unit, as on the till', () async {
    final res = await create([
      {'componentId': 1, 'quantity': 1, 'price': 0},
      {'componentId': 2, 'quantity': 1, 'price': 0},
    ]);
    expect(res.statusCode, 201, reason: res.body);
    final rows = await optionsOfLastLine();
    final byComponent = {for (final r in rows) r.componentId: r.price};
    expect(byComponent, {1: 4.0, 2: 0.0},
        reason: 'bacon (6.00) is free, cheese is charged');
  });

  test('a tablet that already split free and charged rows gets the same',
      () async {
    final res = await create([
      {'componentId': 2, 'quantity': 1, 'price': 0},
      {'componentId': 1, 'quantity': 1, 'price': 4},
    ]);
    expect(res.statusCode, 201, reason: res.body);
    final total = (await optionsOfLastLine())
        .fold<double>(0, (s, r) => s + r.price * r.quantity);
    expect(total, 4.0);
  });

  test('an option the product does not offer is refused', () async {
    final res = await create([
      {'componentId': 6, 'quantity': 1},
    ]);
    expect(res.statusCode, 400);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['error'], 'option_not_offered');
    expect(body['componentId'], 6);
    expect(body['productId'], 10);
    expect(await db.select(db.orders).get(), isEmpty,
        reason: 'nothing of the order is written');
  });

  test('more of one option than its own limit is refused', () async {
    final res = await create([
      {'componentId': 4, 'quantity': 3},
    ]);
    expect(res.statusCode, 400);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['error'], 'option_too_many');
    expect(body['componentId'], 4);
  });

  test("an 86'd option is refused", () async {
    final res = await create([
      {'componentId': 5, 'quantity': 1},
    ]);
    expect(res.statusCode, 400);
    expect((jsonDecode(res.body) as Map)['error'], 'option_not_offered');
  });

  test('more than the group allows is refused', () async {
    final res = await create([
      {'componentId': 1, 'quantity': 2},
      {'componentId': 2, 'quantity': 1},
    ]);
    expect(res.statusCode, 400);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['error'], 'option_group_too_many');
    expect(body['componentGroupId'], 3);
    expect(body['maxSelection'], 2);
  });

  test('add-product checks the same way', () async {
    final code = await emptyOrder();
    final res = await http.put(
        base.replace(path: '/waiters/orders/$code/add-product'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'waiterId': 1,
          ...burger([
            {'componentId': 6, 'quantity': 1}
          ]),
        }));
    expect(res.statusCode, 400, reason: res.body);
    expect((jsonDecode(res.body) as Map)['error'], 'option_not_offered');
    expect(await db.select(db.orderProducts).get(), hasLength(1),
        reason: 'only the line the order was opened with');

    final ok = await http.put(
        base.replace(path: '/waiters/orders/$code/add-product'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'waiterId': 1,
          ...burger([
            {'componentId': 4, 'quantity': 1, 'price': 99}
          ]),
        }));
    expect(ok.statusCode, 200, reason: ok.body);
    expect((await optionsOfLastLine()).single.price, 0.5);
  });

  test('add-products refuses the round and says which line', () async {
    final code = await emptyOrder();
    final res = await http.put(
        base.replace(path: '/waiters/orders/$code/add-products'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'waiterId': 1,
          'products': [
            burger(const []),
            burger([
              {'componentId': 6, 'quantity': 1}
            ]),
          ],
        }));
    expect(res.statusCode, 400, reason: res.body);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['error'], 'option_not_offered');
    expect(body['index'], 1);
    expect(await db.select(db.orderProducts).get(), hasLength(1),
        reason: 'the good line of the refused round is not kept either');
  });
}

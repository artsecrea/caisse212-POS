import 'dart:convert';
import 'dart:io' show HttpOverrides;

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/server_provider.dart';
import 'package:caisse212/providers/settings_provider.dart';
import 'package:caisse212/services/server_service.dart';

/// One table, one live order — whoever is asking.
///
/// The occupancy guard used to exempt the waiter who already held the table,
/// on the assumption that nobody opens the same table twice. They do: the same
/// waiter signed in on two phones opens two. The second overwrote
/// `area_tables.orderId`, and the first order was orphaned — gone from the
/// floor plan with its food already sent to the kitchen.

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
  const port = 18102;
  final base = Uri.parse('http://127.0.0.1:$port');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);

    final sessionId = await db.into(db.cashSessions).insert(
          CashSessionsCompanion.insert(
            id: const Value(1),
            code: '1',
            cashierId: 1,
            moneyAtStart: 0.0,
          ),
        );
    container.read(currentSessionProvider.notifier).state =
        await (db.select(db.cashSessions)..where((s) => s.id.equals(sessionId)))
            .getSingle();

    await db.into(db.waiters).insert(
        WaitersCompanion.insert(id: const Value(1), firstName: 'Amina'));
    await db.into(db.waiters).insert(
        WaitersCompanion.insert(id: const Value(2), firstName: 'Karim'));
    await db.into(db.areaTables).insert(
        AreaTablesCompanion.insert(id: const Value(7), name: 'T7'));
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value(100),
          name: 'P100',
          price: 50.0,
          finalPrice: 50.0,
        ));

    server = container.read(serverServiceProvider);
    await server.start(port: port);
  });

  tearDown(() async {
    await server.stop();
    container.dispose();
    await db.close();
  });

  Future<http.Response> createOrder({int waiterId = 1, int tableId = 7}) =>
      http.post(
        base.replace(path: '/waiters/orders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'waiterId': waiterId,
          'tableId': tableId,
          'products': [
            {'productId': 100, 'quantity': 1}
          ],
        }),
      );

  Future<AreaTable> table(int id) =>
      (db.select(db.areaTables)..where((t) => t.id.equals(id))).getSingle();

  Future<List<Order>> orders() => (db.select(db.orders)
        ..orderBy([(o) => OrderingTerm(expression: o.id)]))
      .get();

  test('the SAME waiter on two phones cannot open a second order', () async {
    final first = await createOrder();
    expect(first.statusCode, anyOf(200, 201), reason: first.body);
    final firstCode =
        (jsonDecode(first.body) as Map<String, dynamic>)['code'] as String;
    final linkedFirst = (await table(7)).orderId;

    // Second phone, same waiter, same table.
    final second = await createOrder();

    expect(second.statusCode, 409, reason: second.body);
    final body = jsonDecode(second.body) as Map<String, dynamic>;
    expect(body['error'], 'table_already_has_your_order');
    expect(body['orderCode'], firstCode,
        reason: 'the tablet needs to know which order to open instead');

    // The first order still owns the table, and no second one was written.
    expect((await table(7)).orderId, linkedFirst,
        reason: 'this is the bug: the table used to be relinked to the second '
            'order, orphaning the first');
    expect(await orders(), hasLength(1));
  });

  test('another waiter is still blocked, and told whose it is', () async {
    final first = await createOrder(waiterId: 1);
    final firstCode =
        (jsonDecode(first.body) as Map<String, dynamic>)['code'] as String;

    final second = await createOrder(waiterId: 2);

    expect(second.statusCode, 409, reason: second.body);
    final body = jsonDecode(second.body) as Map<String, dynamic>;
    expect(body['error'], 'table_taken_by_other_waiter');
    expect(body['message'], contains('Amina'));
    expect(body['orderCode'], firstCode);
    expect(await orders(), hasLength(1));
  });

  test('nothing at all is written by the refused call', () async {
    await createOrder();
    final linesBefore = await db.select(db.orderProducts).get();

    await createOrder();

    expect(await db.select(db.orderProducts).get(), hasLength(linesBefore.length),
        reason: 'the whole transaction rolls back — no half-made order, no '
            'stray lines');
  });

  test('a settled table is free again', () async {
    await createOrder();
    // Everything paid → the order is no longer live.
    await (db.update(db.orderProducts))
        .write(const OrderProductsCompanion(state: Value('PAID')));

    final second = await createOrder();

    expect(second.statusCode, anyOf(200, 201), reason: second.body);
    expect(await orders(), hasLength(2),
        reason: 'blocking must not outlive the order that caused it');
  });

  test('a cancelled order does not hold the table either', () async {
    await createOrder();
    await (db.update(db.orders))
        .write(const OrdersCompanion(status: Value('CANCELED')));

    final second = await createOrder();
    expect(second.statusCode, anyOf(200, 201), reason: second.body);
  });

  test('a different table is unaffected', () async {
    await db.into(db.areaTables).insert(
        AreaTablesCompanion.insert(id: const Value(8), name: 'T8'));
    await createOrder(tableId: 7);

    final second = await createOrder(tableId: 8);
    expect(second.statusCode, anyOf(200, 201), reason: second.body);
    expect(await orders(), hasLength(2));
  });
}

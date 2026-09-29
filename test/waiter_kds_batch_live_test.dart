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

/// Adding several items to an OPEN table must reach the kitchen as ONE ticket.
///
/// The waiter app has no cart in that flow — its add-product screen sends one
/// product and navigates straight back to the menu — so three items arrive as
/// three separate PUTs and used to cut three separate tickets. Nothing on the
/// wire marks the last one, so the POS holds the ticket briefly and lets the
/// run accumulate onto it.
///
/// Driven over REAL HTTP against a REAL [ServerService], because the thing
/// being tested is what a sequence of requests does, not what one method does.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test's binding forces every dart:io request to 400.
  HttpOverrides.global = null;
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  late AppDatabase db;
  late ProviderContainer container;
  late ServerService server;
  const port = 18101;
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
    final session = await (db.select(db.cashSessions)
          ..where((s) => s.id.equals(sessionId)))
        .getSingle();
    container.read(currentSessionProvider.notifier).state = session;

    await db.into(db.waiters).insert(
        WaitersCompanion.insert(id: const Value(1), firstName: 'Amina'));
    await db.into(db.areaTables).insert(
        AreaTablesCompanion.insert(id: const Value(7), name: 'T7'));
    for (final id in [100, 101, 102, 103]) {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: 'P$id',
            price: 50.0,
            finalPrice: 50.0,
          ));
    }

    server = container.read(serverServiceProvider);
    await server.start(port: port);
  });

  tearDown(() async {
    await server.stop();
    container.dispose();
    await db.close();
  });

  Future<String> createOrder() async {
    final res = await http.post(
      base.replace(path: '/waiters/orders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'waiterId': 1,
        'tableId': 7,
        'products': [
          {'productId': 100, 'quantity': 1}
        ],
      }),
    );
    expect(res.statusCode, anyOf(200, 201), reason: res.body);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return ((body['order'] ?? body) as Map<String, dynamic>)['code'] as String;
  }

  Future<void> addProduct(String code, int productId) async {
    final res = await http.put(
      base.replace(path: '/waiters/orders/$code/add-product'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'waiterId': 1, 'productId': productId, 'quantity': 1}),
    );
    expect(res.statusCode, 200, reason: res.body);
  }

  Future<List<OrderProduct>> lines(String code) async {
    final order = await (db.select(db.orders)..where((o) => o.code.equals(code)))
        .getSingle();
    return (db.select(db.orderProducts)
          ..where((p) => p.orderId.equals(order.id))
          ..orderBy([(p) => OrderingTerm(expression: p.id)]))
        .get();
  }

  test('three adds to one table leave ONE ticket waiting, not three', () async {
    await container
        .read(settingsProvider.notifier)
        .setWaiterKdsBatchSeconds(30);
    final code = await createOrder();

    for (final productId in [101, 102, 103]) {
      await addProduct(code, productId);
      // Each add restarts the wait; none of them may cut its own ticket.
      expect(server.pendingWaiterKdsCount, 1,
          reason: 'after adding $productId there must still be exactly one '
              'ticket pending for this order');
    }

    // All four lines are on the order and none has gone to the kitchen yet,
    // so the one pending ticket is what carries the whole run.
    final rows = await lines(code);
    expect(rows.map((r) => r.productId).toList(), [100, 101, 102, 103]);
    expect(rows.where((r) => r.kdsPrintedQuantity > 0), isEmpty);
  });

  test('every item is still saved, whatever the printer does', () async {
    await container
        .read(settingsProvider.notifier)
        .setWaiterKdsBatchSeconds(30);
    final code = await createOrder();
    for (final productId in [101, 102, 103]) {
      await addProduct(code, productId);
    }

    final rows = await lines(code);
    expect(rows, hasLength(4),
        reason: 'persistence must not depend on the print path at all');
    for (final row in rows) {
      expect(row.quantity, 1.0);
      expect(row.unitaryPrice, 50.0);
    }
  });

  test('zero seconds keeps the old print-immediately behaviour', () async {
    await container.read(settingsProvider.notifier).setWaiterKdsBatchSeconds(0);
    final code = await createOrder();
    await addProduct(code, 101);

    expect(server.pendingWaiterKdsCount, 0,
        reason: 'nothing is held back when batching is switched off');
  });

  test('shutting the server down flushes a waiting ticket', () async {
    await container
        .read(settingsProvider.notifier)
        .setWaiterKdsBatchSeconds(30);
    final code = await createOrder();
    await addProduct(code, 101);
    expect(server.pendingWaiterKdsCount, 1);

    // A ticket stranded in a timer at shutdown is food nobody cooks.
    await server.stop();
    expect(server.pendingWaiterKdsCount, 0);
  });

  test('two tables batch independently', () async {
    await container
        .read(settingsProvider.notifier)
        .setWaiterKdsBatchSeconds(30);
    await db.into(db.areaTables).insert(
        AreaTablesCompanion.insert(id: const Value(8), name: 'T8'));

    final first = await createOrder();
    await addProduct(first, 101);
    expect(server.pendingWaiterKdsCount, 1);

    final res = await http.post(
      base.replace(path: '/waiters/orders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'waiterId': 1,
        'tableId': 8,
        'products': [
          {'productId': 100, 'quantity': 1}
        ],
      }),
    );
    final second =
        ((jsonDecode(res.body) as Map<String, dynamic>)['code']) as String;
    await addProduct(second, 102);

    expect(server.pendingWaiterKdsCount, 2,
        reason: 'one table must never sweep another table\'s ticket onto its '
            'own');
  });
}

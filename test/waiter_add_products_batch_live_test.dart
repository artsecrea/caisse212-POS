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
import 'package:caisse212/domain/models/order_course.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/server_provider.dart';
import 'package:caisse212/providers/settings_provider.dart';
import 'package:caisse212/services/server_service.dart';

/// `PUT /waiters/orders/{code}/add-products` — a whole round of ordering in
/// one call, so the kitchen gets one ticket for it without the POS having to
/// guess where the round ended.
///
/// The single-product route it sits beside is deliberately untouched: waiter
/// tablets that have not been updated must keep working exactly as before, so
/// both are exercised here against the same real server.

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
  const port = 18100;
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
    await db.into(db.waiters).insert(
        WaitersCompanion.insert(id: const Value(2), firstName: 'Karim'));
    await db.into(db.areaTables).insert(
        AreaTablesCompanion.insert(id: const Value(7), name: 'T7'));
    for (final id in [100, 101, 102, 103]) {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: 'P$id',
            price: 50.0,
            finalPrice: 50.0,
            tvaAmount: const Value(10.0),
          ));
    }
    await db.into(db.components).insert(
        ComponentsCompanion.insert(id: const Value(9), name: 'Extra'));

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
    return ((jsonDecode(res.body) as Map<String, dynamic>)['code']) as String;
  }

  Future<http.Response> addProducts(
          String code, List<Map<String, dynamic>> products,
          {int waiterId = 1}) =>
      http.put(
        base.replace(path: '/waiters/orders/$code/add-products'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'waiterId': waiterId, 'products': products}),
      );

  Future<List<OrderProduct>> lines(String code) async {
    final order = await (db.select(db.orders)..where((o) => o.code.equals(code)))
        .getSingle();
    return (db.select(db.orderProducts)
          ..where((p) => p.orderId.equals(order.id))
          ..orderBy([(p) => OrderingTerm(expression: p.id)]))
        .get();
  }

  test('a round of three arrives as three lines, printed as one round',
      () async {
    await container
        .read(settingsProvider.notifier)
        .setWaiterKdsBatchSeconds(30);
    final code = await createOrder();

    final res = await addProducts(code, [
      {'productId': 101, 'quantity': 2},
      {'productId': 102, 'quantity': 1},
      {'productId': 103, 'quantity': 1},
    ]);

    expect(res.statusCode, 200, reason: res.body);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['added'], 3);
    expect(body['skipped'], isEmpty);

    final rows = await lines(code);
    expect(rows.map((r) => r.productId).toList(), [100, 101, 102, 103]);
    expect(rows[1].quantity, 2.0);
    expect(server.pendingWaiterKdsCount, 0,
        reason: 'one round, one ticket, and no waiting — the call itself said '
            'the round was finished');
  });

  test('a batch prints at once — the wait is only for looped adds', () async {
    await container
        .read(settingsProvider.notifier)
        .setWaiterKdsBatchSeconds(30);
    final code = await createOrder();

    final res = await addProducts(code, [
      {'productId': 101, 'quantity': 1},
      {'productId': 102, 'quantity': 1},
    ]);
    expect(res.statusCode, 200, reason: res.body);

    // Nothing is held back: the call itself said the round was finished, so a
    // 30s window would be a delay bought for nothing.
    expect(server.pendingWaiterKdsCount, 0,
        reason: 'the batch must not sit in the grouping timer');
  });

  test('a batch also flushes a single add still waiting on that order',
      () async {
    await container
        .read(settingsProvider.notifier)
        .setWaiterKdsBatchSeconds(30);
    final code = await createOrder();

    // One looped add starts the window...
    await http.put(
      base.replace(path: '/waiters/orders/$code/add-product'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'waiterId': 1, 'productId': 101, 'quantity': 1}),
    );
    expect(server.pendingWaiterKdsCount, 1);

    // ...and a batch arriving behind it ends the round for both.
    await addProducts(code, [
      {'productId': 102, 'quantity': 1}
    ]);

    expect(server.pendingWaiterKdsCount, 0,
        reason: 'the stale timer would otherwise wake with nothing to say');
    expect(await lines(code), hasLength(3));
  });

  test('a single add still waits, so looped rounds keep grouping', () async {
    await container
        .read(settingsProvider.notifier)
        .setWaiterKdsBatchSeconds(30);
    final code = await createOrder();

    await http.put(
      base.replace(path: '/waiters/orders/$code/add-product'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'waiterId': 1, 'productId': 101, 'quantity': 1}),
    );

    expect(server.pendingWaiterKdsCount, 1,
        reason: 'the immediate path must not leak into the single-add route');
  });

  test('prices and TVA come from the catalogue, never from the tablet',
      () async {
    final code = await createOrder();
    await addProducts(code, [
      {'productId': 101, 'quantity': 1, 'price': 1.0, 'unitaryPrice': 1.0},
    ]);

    final row = (await lines(code)).last;
    expect(row.unitaryPrice, 50.0, reason: 'a tablet cannot name its own price');
    expect(row.unitaryTva, 10.0);
  });

  test('options ride along with their line', () async {
    final code = await createOrder();
    await addProducts(code, [
      {
        'productId': 101,
        'quantity': 1,
        'components': [
          {'componentId': 9, 'quantity': 2, 'price': 3.0, 'name': 'Extra'}
        ],
      },
    ]);

    final row = (await lines(code)).last;
    final comps = await (db.select(db.orderProductComponents)
          ..where((c) => c.orderProductId.equals(row.id)))
        .get();
    expect(comps, hasLength(1));
    expect(comps.single.componentId, 9);
    expect(comps.single.quantity, 2);
  });

  test('an unknown product is reported, not fatal to the round', () async {
    final code = await createOrder();
    final res = await addProducts(code, [
      {'productId': 101, 'quantity': 1},
      {'productId': 9999, 'quantity': 1},
    ]);

    expect(res.statusCode, 200, reason: res.body);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['added'], 1);
    expect(body['skipped'], [
      {'index': 1, 'productId': 9999}
    ], reason: 'the index identifies WHICH line was lost — a bare productId '
        'cannot, since a cart may hold two of the same product differing only '
        'by variant, options or course');
    expect(await lines(code), hasLength(2));
  });

  test('a round of only unknown products is refused and writes nothing',
      () async {
    final code = await createOrder();
    final res = await addProducts(code, [
      {'productId': 9998, 'quantity': 1},
    ]);

    expect(res.statusCode, 400, reason: res.body);
    expect((jsonDecode(res.body) as Map<String, dynamic>)['skipped'], [
      {'index': 0, 'productId': 9998}
    ]);
    expect(await lines(code), hasLength(1), reason: 'only the original line');
  });

  test('another waiter cannot add to this order', () async {
    final code = await createOrder();
    final res = await addProducts(code, [
      {'productId': 101, 'quantity': 1}
    ], waiterId: 2);

    expect(res.statusCode, 403);
    expect(await lines(code), hasLength(1));
  });

  test('an empty array is refused rather than silently doing nothing',
      () async {
    final code = await createOrder();
    final res = await addProducts(code, []);
    expect(res.statusCode, 400);
  });

  test('an unknown order code is a 404', () async {
    final res = await addProducts('NOPE', [
      {'productId': 101, 'quantity': 1}
    ]);
    expect(res.statusCode, 404);
  });

  test('the round is flagged for sync, or the next delta loses it', () async {
    final code = await createOrder();
    await addProducts(code, [
      {'productId': 101, 'quantity': 1}
    ]);

    final order = await (db.select(db.orders)..where((o) => o.code.equals(code)))
        .getSingle();
    expect(order.isSynced, isFalse);
  });

  test('a batched round always sections by course, whatever the timing',
      () async {
    await container
        .read(settingsProvider.notifier)
        .setWaiterKdsBatchSeconds(30);
    final code = await createOrder();

    await addProducts(code, [
      {'productId': 101, 'quantity': 1, 'courseNo': 1},
      {'productId': 102, 'quantity': 1, 'courseNo': 2},
      {'productId': 103, 'quantity': 1, 'courseNo': 3},
    ]);

    // The whole round is unprinted, so it is one ticket and the section rule
    // sees every course on it.
    final unprinted = (await lines(code))
        .where((r) => r.kdsPrintedQuantity <= 0)
        .map((r) => r.courseNo)
        .toList();
    expect(shouldSplitByCourse(unprinted), isTrue,
        reason: 'starters, mains and desserts are three sections');

    // A ticket carrying a single line can never split, whatever course it is
    // on — the floor under the two looped cases below.
    expect(shouldSplitByCourse(const [1]), isFalse);
    expect(shouldSplitByCourse(const [2]), isFalse);
    expect(shouldSplitByCourse(const [3]), isFalse);
  });

  /// Does a LOOPED round section, or not? The claim "a loop can never section"
  /// and the existence of the 12s grouping window cannot both be true.
  test('a looped round DOES section — while the taps land inside the window',
      () async {
    await container
        .read(settingsProvider.notifier)
        .setWaiterKdsBatchSeconds(30);
    final code = await createOrder();
    // Create's own `full` ticket has printed and marked its line.
    for (final row in await lines(code)) {
      await (db.update(db.orderProducts)..where((t) => t.id.equals(row.id)))
          .write(OrderProductsCompanion(
              kdsPrintedQuantity: Value(row.quantity)));
    }

    for (final entry in [
      {'productId': 101, 'courseNo': 1},
      {'productId': 102, 'courseNo': 2},
      {'productId': 103, 'courseNo': 3},
    ]) {
      final res = await http.put(
        base.replace(path: '/waiters/orders/$code/add-product'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'waiterId': 1, ...entry, 'quantity': 1}),
      );
      expect(res.statusCode, 200, reason: res.body);
    }

    // The window collapsed three calls into ONE pending job...
    expect(server.pendingWaiterKdsCount, 1);
    // ...and that job's delta is every unprinted line, so it carries three
    // distinct courses and WILL split.
    final delta = (await lines(code))
        .where((r) => r.kdsPrintedQuantity <= 0)
        .map((r) => r.courseNo)
        .toList();
    expect(shouldSplitByCourse(delta), isTrue,
        reason: 'a looped round DOES section when the grouping window swallows '
            'the whole run — so "a loop can never section" is wrong');
  });

  test('with the window at 0 a looped round cannot section at all', () async {
    await container.read(settingsProvider.notifier).setWaiterKdsBatchSeconds(0);
    final code = await createOrder();

    // The create's own ticket has printed and marked its line — that is what
    // `KdsPrintMode.full` does at create time, and without it the line is still
    // owed to the kitchen and the first add legitimately sweeps it in.
    for (final row in await lines(code)) {
      await (db.update(db.orderProducts)..where((t) => t.id.equals(row.id)))
          .write(OrderProductsCompanion(
              kdsPrintedQuantity: Value(row.quantity)));
    }

    // Nothing is held, so each call is its own job of one line. Simulated the
    // way the real queue behaves: a job prints its delta, then marks it.
    final sectioned = <bool>[];
    for (final entry in [
      {'productId': 101, 'courseNo': 1},
      {'productId': 102, 'courseNo': 2},
      {'productId': 103, 'courseNo': 3},
    ]) {
      await http.put(
        base.replace(path: '/waiters/orders/$code/add-product'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'waiterId': 1, ...entry, 'quantity': 1}),
      );
      expect(server.pendingWaiterKdsCount, 0, reason: 'nothing is held at 0');
      final delta = (await lines(code))
          .where((r) => r.kdsPrintedQuantity <= 0)
          .map((r) => r.courseNo)
          .toList();
      sectioned.add(shouldSplitByCourse(delta));
      for (final row in await lines(code)) {
        await (db.update(db.orderProducts)..where((t) => t.id.equals(row.id)))
            .write(OrderProductsCompanion(
                kdsPrintedQuantity: Value(row.quantity)));
      }
    }

    expect(sectioned, [false, false, false],
        reason: 'one line per ticket, and one line can never split — a shop '
            'that sets 0 while its waiters still loop loses course sections '
            'on every round after the first');
  });

  test('the OLD single-product route still works, untouched', () async {
    final code = await createOrder();
    final res = await http.put(
      base.replace(path: '/waiters/orders/$code/add-product'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'waiterId': 1, 'productId': 101, 'quantity': 3}),
    );

    expect(res.statusCode, 200, reason: res.body);
    final rows = await lines(code);
    expect(rows, hasLength(2));
    expect(rows.last.productId, 101);
    expect(rows.last.quantity, 3.0);
    expect(rows.last.unitaryPrice, 50.0);
  });

  test('old and new routes can be mixed on the same order', () async {
    final code = await createOrder();
    await http.put(
      base.replace(path: '/waiters/orders/$code/add-product'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'waiterId': 1, 'productId': 101, 'quantity': 1}),
    );
    await addProducts(code, [
      {'productId': 102, 'quantity': 1},
      {'productId': 103, 'quantity': 1},
    ]);

    expect((await lines(code)).map((r) => r.productId).toList(),
        [100, 101, 102, 103]);
  });
}

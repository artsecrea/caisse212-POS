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
import 'package:caisse212/services/server_service.dart';

/// The waiter component-rules endpoints, hit with REAL HTTP requests against
/// a REAL running [ServerService] — not a call into the handler function, an
/// actual socket round trip through the Shelf router, CORS middleware and
/// JSON encoder, exactly as the waiter app receives it.
///
/// This is the gap the waiter-app session (a peer Claude session building the
/// waiter client against this same set of endpoints) flagged: both sides had
/// verified "the code that produces/consumes the bytes" but neither had
/// verified the bytes themselves. It matters here specifically because a
/// component-rules payload carries money — a free-allowance split that reads
/// correctly in a unit test but serializes wrong over the wire would show up
/// as a customer undercharged or overcharged, not as a crash.
///
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test's binding installs an HttpOverrides that forces every
  // dart:io HttpClient request to 400 — a guard against a test accidentally
  // hitting a real remote API. This file's whole point is the opposite: a
  // real loopback round trip against a server this test itself started, so
  // the guard is exactly what would otherwise hide a real wire bug.
  HttpOverrides.global = null;

  // The waiter order-create endpoint fires a fire-and-forget connectivity
  // check in the background (auto-sync-on-create). With no real platform
  // plugin registered in this test binary, that throws
  // MissingPluginException asynchronously and unhandled — never reaching any
  // of this file's assertions, but still failing the test. Answer the
  // channel directly rather than suppressing the check: "no network" is the
  // correct, honest answer for a test binary, and it is what makes the
  // caller skip the sync attempt on its own, same as it would offline.
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  late AppDatabase db;
  late ProviderContainer container;
  late ServerService server;
  const port = 18099;
  final base = Uri.parse('http://127.0.0.1:$port');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);

    // An open cash session — GET/POST /waiters/orders both require one.
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

    server = container.read(serverServiceProvider);
    await server.start(port: port);
  });

  tearDown(() async {
    await server.stop();
    container.dispose();
    await db.close();
  });

  /// One product, two component groups (SINGLE required + QUANTITY with a
  /// free allowance), three active components, one 86'd component, and a
  /// per-product override touching only PART of the QUANTITY group's rule —
  /// the specific shape that exercises every field this round adds.
  Future<void> seedCatalog() async {
    await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value(100),
          name: 'Tacos Mixte',
          price: 50.0,
          finalPrice: 50.0,
        ));

    await db.into(db.componentGroups).insert(ComponentGroupsCompanion.insert(
          id: const Value(1),
          name: 'Cuisson',
          selectionType: const Value('SINGLE'),
          minSelection: const Value(1),
          maxSelection: const Value(1),
        ));
    await db.into(db.componentGroups).insert(ComponentGroupsCompanion.insert(
          id: const Value(2),
          name: 'Suppléments',
          selectionType: const Value('QUANTITY'),
          freeQuantity: const Value(1),
        ));

    await db.into(db.components).insert(ComponentsCompanion.insert(
          id: const Value(10),
          name: 'À point',
          componentGroupId: const Value(1),
          displayOrder: const Value(1),
        ));
    await db.into(db.components).insert(ComponentsCompanion.insert(
          id: const Value(11),
          name: 'Bien cuit',
          componentGroupId: const Value(1),
          displayOrder: const Value(2),
        ));
    await db.into(db.components).insert(ComponentsCompanion.insert(
          id: const Value(12),
          name: 'Fromage',
          price: const Value(8.0),
          componentGroupId: const Value(2),
          displayOrder: const Value(1),
        ));
    // 86'd — must never appear in /waiters/components.
    await db.into(db.components).insert(ComponentsCompanion.insert(
          id: const Value(13),
          name: 'Old Sauce',
          componentGroupId: const Value(2),
          isActive: const Value(false),
        ));

    await db.into(db.productComponents).insert(ProductComponentsCompanion.insert(
          productId: 100,
          componentId: 12,
          chargeOnRemoval: const Value(true),
        ));

    // Overrides ONLY maxSelection for (product 100, group 2). selectionType,
    // minSelection and freeQuantity are left unset — the omission contract.
    await db.into(db.productComponentGroups).insert(
          ProductComponentGroupsCompanion.insert(
            productId: 100,
            groupId: 2,
            maxSelection: const Value(3),
          ),
        );
  }

  group('GET /waiters/components — real bytes', () {
    test('serves the new fields and drops the 86\'d row', () async {
      await seedCatalog();

      final res = await http.get(base.replace(path: '/waiters/components'));
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list = (body['components'] as List).cast<Map<String, dynamic>>();

      expect(list.map((c) => c['id']), isNot(contains(13)),
          reason: 'the 86\'d component must never reach the wire');

      final fromage = list.firstWhere((c) => c['id'] == 12);
      expect(fromage['name'], 'Fromage');
      expect(fromage['price'], 8.0);
      expect(fromage['componentGroupId'], 2);
      expect(fromage['displayOrder'], 1);
      expect(fromage['isActive'], isTrue);
    });
  });

  group('GET /waiters/component-groups — real bytes', () {
    test('serves selection rules, null maxSelection stays null', () async {
      await seedCatalog();

      final res = await http.get(base.replace(path: '/waiters/component-groups'));
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final list =
          (body['componentGroups'] as List).cast<Map<String, dynamic>>();

      final cuisson = list.firstWhere((g) => g['id'] == 1);
      expect(cuisson['selectionType'], 'SINGLE');
      expect(cuisson['minSelection'], 1);
      expect(cuisson['maxSelection'], 1);

      final supplements = list.firstWhere((g) => g['id'] == 2);
      expect(supplements['selectionType'], 'QUANTITY');
      expect(supplements['freeQuantity'], 1);
      // Group's OWN default has no cap — null must survive the wire as null,
      // not as a missing key and not as 0.
      expect(supplements.containsKey('maxSelection'), isTrue);
      expect(supplements['maxSelection'], isNull);
    });
  });

  group('GET /waiters/product-components — real bytes', () {
    test('serves chargeOnRemoval', () async {
      await seedCatalog();

      final res =
          await http.get(base.replace(path: '/waiters/product-components'));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final row = (body['productComponents'] as List)
          .cast<Map<String, dynamic>>()
          .single;

      expect(row['productId'], 100);
      expect(row['componentId'], 12);
      expect(row['chargeOnRemoval'], isTrue);
    });
  });

  group('GET /waiters/product-component-groups — real bytes', () {
    test('the override row omits every field it did not set', () async {
      await seedCatalog();

      final res = await http
          .get(base.replace(path: '/waiters/product-component-groups'));
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rows =
          (body['productComponentGroups'] as List).cast<Map<String, dynamic>>();

      expect(rows.length, 1,
          reason: 'only the one genuinely-overridden pair should appear');
      final row = rows.single;
      expect(row['productId'], 100);
      expect(row['componentGroupId'], 2);
      expect(row['maxSelection'], 3);
      expect(row['displayOrder'], 0);

      // The wire-level contract: containsKey false, not "key present as
      // null". A parser using containsKey to mean "is this overridden" must
      // see false for every field this row never touched.
      expect(row.containsKey('selectionType'), isFalse);
      expect(row.containsKey('minSelection'), isFalse);
      expect(row.containsKey('freeQuantity'), isFalse);
    });

    test('a product with no override has no row at all', () async {
      await seedCatalog();
      // Product 100/group 1 (Cuisson) was never overridden.
      final res = await http
          .get(base.replace(path: '/waiters/product-component-groups'));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rows =
          (body['productComponentGroups'] as List).cast<Map<String, dynamic>>();

      expect(rows.any((r) => r['componentGroupId'] == 1), isFalse);
    });
  });

  group('the money math, through the real intake path', () {
    test(
        'a free-allowance split posted as two array entries lands as two '
        'billed rows and the order total is correct',
        () async {
      await seedCatalog();
      await db.into(db.waiters).insert(WaitersCompanion.insert(
            id: const Value(1),
            firstName: 'Sam',
          ));

      // What allocateFreeAllowance would emit for 3 units of Fromage (8.0/u)
      // with a freeQuantity of 1: 1 unit covered at 0.00, 2 units charged.
      final createRes = await http.post(
        base.replace(path: '/waiters/orders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'waiterId': 1,
          'type': 'TAKE_AWAY',
          'persons': 1,
          'products': [
            {
              'productId': 100,
              'quantity': 1,
              'components': [
                {'componentId': 12, 'quantity': 1, 'price': 0.0},
                {'componentId': 12, 'quantity': 2, 'price': 8.0},
              ],
            }
          ],
        }),
      );

      expect(createRes.statusCode, 201,
          reason: 'server said: ${createRes.body}');
      final created = jsonDecode(createRes.body) as Map<String, dynamic>;
      final code = created['code'] as String;

      final detailRes = await http.get(
        base.replace(path: '/waiters/orders/$code', queryParameters: {
          'waiterId': '1',
        }),
      );
      expect(detailRes.statusCode, 200);
      final detail = jsonDecode(detailRes.body) as Map<String, dynamic>;

      final line =
          (detail['products'] as List).cast<Map<String, dynamic>>().single;
      final comps =
          (line['components'] as List).cast<Map<String, dynamic>>();

      // Both halves of the split survived intake as distinct rows — the
      // exact contract the waiter app's own toInput() test pins on its side.
      expect(comps.length, 2);
      expect(comps.map((c) => c['componentId']).toSet(), {12});
      expect(comps.map((c) => (c['price'] as num).toDouble()).toList()..sort(),
          [0.0, 8.0]);

      // (50 product + 0×1 + 8×2 component) × 1 parent unit = 66.
      expect((line['lineTotal'] as num).toDouble(), closeTo(66.0, 0.001));
      expect((detail['totalAmount'] as num).toDouble(), closeTo(66.0, 0.001));
      expect((detail['balanceAmount'] as num).toDouble(), closeTo(66.0, 0.001));
    });
  });
}

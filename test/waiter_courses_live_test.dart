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
import 'package:caisse212/providers/settings_provider.dart';
import 'package:caisse212/services/server_service.dart';

/// Courses over the waiter LAN API, hit with REAL HTTP against a REAL running
/// [ServerService] — the same reasoning as the component-rules live test: both
/// sides can verify the code that produces and consumes the bytes and still
/// disagree about the bytes.
///
/// It matters more than usual here because the waiter app already shipped a
/// client-only course concept whose default was "plat" on every line. If the
/// wire contract is off by a level or a name, their lines arrive silently
/// mistagged rather than failing loudly, and the kitchen gets steaks under the
/// starters heading.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // See waiter_component_endpoints_live_test.dart: flutter_test's binding
  // forces every dart:io request to 400, which is exactly what this file
  // exists to avoid.
  HttpOverrides.global = null;
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  late AppDatabase db;
  late ProviderContainer container;
  late ServerService server;
  const port = 18098;
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
    // A DINE_IN order needs a table; the endpoint rejects it otherwise.
    await db.into(db.areaTables).insert(
        AreaTablesCompanion.insert(id: const Value(7), name: 'T7'));
    for (final id in [100, 101]) {
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

  Future<String> createOrder(List<Map<String, dynamic>> products) async {
    final res = await http.post(
      base.replace(path: '/waiters/orders'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(
          {'waiterId': 1, 'tableId': 7, 'products': products}),
    );
    expect(res.statusCode, anyOf(200, 201), reason: res.body);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final order = (body['order'] ?? body) as Map<String, dynamic>;
    return order['code'] as String;
  }

  Future<List<dynamic>> readLines(String code) async {
    final res = await http.get(base.replace(
      path: '/waiters/orders/$code',
      queryParameters: {'waiterId': '1'},
    ));
    expect(res.statusCode, 200, reason: res.body);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final order = (body['order'] ?? body) as Map<String, dynamic>;
    return (order['products'] ?? order['items'] ?? body['products'])
        as List<dynamic>;
  }

  group('GET /health carries the switch', () {
    test('false by default — the feature stays dark', () async {
      final res = await http.get(base.replace(path: '/health'));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body.containsKey('coursesEnabled'), isTrue,
          reason: 'always present: an absent field reads as false on their '
              'side, which is right for an old build but confusing to debug');
      expect(body['coursesEnabled'], isFalse);
    });

    test('follows the setting, so a mid-shift toggle reaches every waiter',
        () async {
      await container.read(settingsProvider.notifier).setCoursesEnabled(true);
      final res = await http.get(base.replace(path: '/health'));
      expect((jsonDecode(res.body) as Map)['coursesEnabled'], isTrue);
    });
  });

  group('courseNo over the wire', () {
    test('a course sent on create comes back on read', () async {
      final code = await createOrder([
        {'productId': 100, 'quantity': 1, 'courseNo': 1},
        {'productId': 101, 'quantity': 1, 'courseNo': 2},
      ]);

      final byProduct = {
        for (final l in await readLines(code))
          l['productId'] as int: l['courseNo'],
      };
      expect(byProduct[100], 1);
      expect(byProduct[101], 2);
    });

    test('omitting it means no course, not a default', () async {
      // The waiter app used to default every line to "plat". If that value
      // ever reaches us as an implied 2, a shop that never uses courses gets
      // every kitchen ticket silently relabelled.
      final code = await createOrder([
        {'productId': 100, 'quantity': 1},
      ]);
      expect((await readLines(code)).single['courseNo'], isNull);
    });

    test('an explicit null is accepted and stays null', () async {
      final code = await createOrder([
        {'productId': 100, 'quantity': 1, 'courseNo': null},
      ]);
      expect((await readLines(code)).single['courseNo'], isNull);
    });

    test('add-product reads courseNo at the top level of the body', () async {
      // The level the waiter app asked me to confirm: beside productId and
      // quantity, not nested under a product key.
      final code = await createOrder([
        {'productId': 100, 'quantity': 1, 'courseNo': 1},
      ]);

      final res = await http.put(
        base.replace(path: '/waiters/orders/$code/add-product'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'waiterId': 1,
          'productId': 101,
          'quantity': 1,
          'courseNo': 3,
        }),
      );
      expect(res.statusCode, anyOf(200, 201), reason: res.body);

      final added = (await readLines(code))
          .firstWhere((l) => l['productId'] == 101);
      expect(added['courseNo'], 3);
    });

    test('every line carries the key even when nobody uses courses', () async {
      // A missing key and a null value must not be made to mean different
      // things by accident.
      final code = await createOrder([
        {'productId': 100, 'quantity': 1},
      ]);
      expect((await readLines(code)).single.containsKey('courseNo'), isTrue);
    });
  });

  group('a bad course from the wire is refused, not stored', () {
    /// The waiter app normalises through OrderCourse before serialising, so
    /// today nothing out of range can leave their build. They flagged that
    /// this makes the guarantee theirs rather than the contract's — which is
    /// one build of theirs away from not being a guarantee at all. So the
    /// boundary normalises too, and these pin it.
    Future<void> expectStoredAsNull(Object? sent) async {
      final code = await createOrder([
        {'productId': 100, 'quantity': 1, 'courseNo': sent},
      ]);
      expect((await readLines(code)).single['courseNo'], isNull,
          reason: 'courseNo $sent must not reach the column');
    }

    test('zero — the case they raised', () => expectStoredAsNull(0));
    test('out of range', () => expectStoredAsNull(4));
    test('negative', () => expectStoredAsNull(-1));

    test('a string is refused rather than coerced', () async {
      // JSON is not typed; "2" must not quietly become a main course.
      await expectStoredAsNull('2');
    });

    test('add-product normalises on the same terms', () async {
      final code = await createOrder([
        {'productId': 100, 'quantity': 1, 'courseNo': 1},
      ]);
      final res = await http.put(
        base.replace(path: '/waiters/orders/$code/add-product'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'waiterId': 1,
          'productId': 101,
          'quantity': 1,
          'courseNo': 0,
        }),
      );
      expect(res.statusCode, anyOf(200, 201), reason: res.body);

      final added =
          (await readLines(code)).firstWhere((l) => l['productId'] == 101);
      expect(added['courseNo'], isNull);
    });

    test('a bad value is dropped without failing the order', () async {
      // It must degrade to "no course", never to a rejected order: a waiter
      // should not lose a table's food to a field nobody looks at.
      final code = await createOrder([
        {'productId': 100, 'quantity': 1, 'courseNo': 99},
        {'productId': 101, 'quantity': 1, 'courseNo': 2},
      ]);
      final byProduct = {
        for (final l in await readLines(code))
          l['productId'] as int: l['courseNo'],
      };
      expect(byProduct[100], isNull);
      expect(byProduct[101], 2, reason: 'the good line is untouched');
    });
  });
}

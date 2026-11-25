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

/// `POST /orders` (kiosk / legacy KDS) wrote the header, the table link, the
/// lines and their options one statement at a time. A failure part way left
/// a half-written order — on the floor plan, with lines missing.
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
  const port = 18151;
  final base = Uri.parse('http://127.0.0.1:$port');

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
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: const Value(10), name: 'Tajine', price: 10, finalPrice: 10));
    await db.into(db.components).insert(
        ComponentsCompanion.insert(id: const Value(5), name: 'Olives'));
    await db.into(db.areaTables).insert(
        AreaTablesCompanion.insert(id: const Value(4), name: 'T4'));
    server = container.read(serverServiceProvider);
    await server.start(port: port);
  });
  tearDown(() async {
    await server.stop();
    container.dispose();
    await db.close();
  });

  Future<http.Response> post(String code) => http.post(
        base.replace(path: '/orders'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'status': 'COMPLETED',
          'type': 'DINE_IN',
          'tableId': 4,
          'products': [
            {
              'productId': 10,
              'quantity': 2,
              'unitaryPrice': 10,
              'components': [
                {
                  'componentId': 5,
                  'componentName': 'Olives',
                  'quantity': 1,
                  'isSpecial': false,
                  'extraPrice': 1.5,
                }
              ],
            }
          ],
        }),
      );

  test('a whole order lands: header, table, line and option', () async {
    final res = await post('K1');
    expect(res.statusCode, 201, reason: res.body);
    final order = await (db.select(db.orders)..where((o) => o.code.equals('K1')))
        .getSingle();
    final table = await (db.select(db.areaTables)..where((t) => t.id.equals(4)))
        .getSingle();
    expect(table.orderId, order.id);
    expect(await db.select(db.orderProducts).get(), hasLength(1));
    expect(await db.select(db.orderProductComponents).get(), hasLength(1));
  });

  test('a failure part way leaves nothing behind', () async {
    // The option insert fails after the header, table link and line went in.
    await db.customStatement('CREATE TRIGGER boom BEFORE INSERT ON '
        "order_product_components BEGIN SELECT RAISE(ABORT, 'boom'); END;");

    final res = await post('K2');
    expect(res.statusCode, 500);
    expect(await db.select(db.orders).get(), isEmpty);
    expect(await db.select(db.orderProducts).get(), isEmpty);
    final table = await (db.select(db.areaTables)..where((t) => t.id.equals(4)))
        .getSingle();
    expect(table.orderId, isNull);
  });
}

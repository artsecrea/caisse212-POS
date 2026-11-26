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

/// The waiter app moving an order to another table, and freeing a table.
/// Pins what the waiter API answers and writes, so the same calls can run
/// through the till's FloorService without the tablet seeing a difference.
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
  const port = 18153;
  final base = Uri.parse('http://127.0.0.1:$port');

  late int t1, t2, t3;
  late int mine, theirs;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    await db.into(db.waiters).insert(
        WaitersCompanion.insert(id: const Value(1), firstName: 'Amina'));
    await db.into(db.waiters).insert(
        WaitersCompanion.insert(id: const Value(2), firstName: 'Karim'));
    t1 = await db.into(db.areaTables).insert(AreaTablesCompanion.insert(name: 'T1'));
    t2 = await db.into(db.areaTables).insert(AreaTablesCompanion.insert(name: 'T2'));
    t3 = await db.into(db.areaTables).insert(AreaTablesCompanion.insert(name: 'T3'));
    mine = await db.into(db.orders).insert(OrdersCompanion.insert(
        code: 'MINE',
        waiterId: const Value(1),
        tableId: Value(t1),
        isSynced: const Value(true)));
    theirs = await db.into(db.orders).insert(OrdersCompanion.insert(
        code: 'THEIRS', waiterId: const Value(2), tableId: Value(t3)));
    await (db.update(db.areaTables)..where((t) => t.id.equals(t1)))
        .write(AreaTablesCompanion(orderId: Value(mine)));
    await (db.update(db.areaTables)..where((t) => t.id.equals(t3)))
        .write(AreaTablesCompanion(orderId: Value(theirs)));
    server = container.read(serverServiceProvider);
    await server.start(port: port);
  });
  tearDown(() async {
    await server.stop();
    container.dispose();
    await db.close();
  });

  Future<http.Response> transfer(String code, int waiterId, int tableId) =>
      http.post(base.replace(path: '/waiters/orders/$code/transfer-table'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'waiterId': waiterId, 'tableId': tableId}));

  Future<http.Response> clear(int tableId, int waiterId) =>
      http.post(base.replace(path: '/waiters/tables/$tableId/clear'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'waiterId': waiterId}));

  Future<int?> holderOf(int tableId) async =>
      (await (db.select(db.areaTables)..where((t) => t.id.equals(tableId)))
              .getSingle())
          .orderId;

  Future<Order> order(int id) =>
      (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();

  Future<List<String?>> logsOf(int orderId) async => [
        for (final l in await (db.select(db.orderLogs)
              ..where((l) => l.orderId.equals(orderId)))
            .get())
          l.description
      ];

  group('transfer-table', () {
    test('moves the order to a free table', () async {
      final res = await transfer('MINE', 1, t2);

      expect(res.statusCode, 200, reason: res.body);
      expect(jsonDecode(res.body), {'transferred': true, 'tableId': t2});
      expect(await holderOf(t1), isNull);
      expect(await holderOf(t2), mine);
      final o = await order(mine);
      expect(o.tableId, t2);
      expect(o.isSynced, isFalse, reason: 'the move has to reach the cloud');
      expect(await logsOf(mine),
          contains('Order moved to table #$t2 by waiter #1'));
    });

    test('an order on no table yet takes the new one', () async {
      final loose = await db.into(db.orders).insert(
          OrdersCompanion.insert(code: 'LOOSE', waiterId: const Value(1)));

      final res = await transfer('LOOSE', 1, t2);

      expect(res.statusCode, 200, reason: res.body);
      expect(await holderOf(t2), loose);
      expect((await order(loose)).tableId, t2);
    });

    test('a held table is refused and nothing moves', () async {
      final res = await transfer('MINE', 1, t3);

      expect(res.statusCode, 400);
      expect((jsonDecode(res.body) as Map)['error'], 'target_table_occupied');
      expect(await holderOf(t1), mine);
      expect(await holderOf(t3), theirs);
      expect((await order(mine)).tableId, t1);
    });

    test("another waiter's order is not theirs to move", () async {
      final res = await transfer('MINE', 2, t2);
      expect(res.statusCode, 403);
      expect(await holderOf(t1), mine);
    });

    test('unknown order or table', () async {
      expect((await transfer('NOPE', 1, t2)).statusCode, 404);
      expect((await transfer('MINE', 1, 999)).statusCode, 404);
    });
  });

  group('clear', () {
    test('frees the table and says so on the order', () async {
      final res = await clear(t1, 1);

      expect(res.statusCode, 200, reason: res.body);
      expect(jsonDecode(res.body), {'cleared': true});
      expect(await holderOf(t1), isNull);
      expect(await logsOf(mine), contains('Table #$t1 cleared by waiter #1'));
    });

    test('a free table clears without a log', () async {
      final res = await clear(t2, 1);
      expect(res.statusCode, 200);
      expect(await db.select(db.orderLogs).get(), isEmpty);
    });

    test('unknown table', () async {
      expect((await clear(999, 1)).statusCode, 404);
    });
  });
}

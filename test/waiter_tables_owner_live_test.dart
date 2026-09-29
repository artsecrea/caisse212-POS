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

/// `GET /waiters/tables` says who is serving each table.
///
/// The waiter app needs it for a "my tables" view. Area scoping already
/// decides which tables a waiter RECEIVES, so it cannot answer "which of
/// these am I holding" on a section two waiters share — that is a view over
/// data they are already entitled to, and it needs the owner on each row.
///
/// The null semantics are the part worth pinning: null means "nobody's", and
/// must never read as a wildcard that makes a table match every waiter.

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
  const port = 18103;
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

    await db.into(db.waiters).insert(WaitersCompanion.insert(
        id: const Value(1), firstName: 'Amina', lastName: const Value('B')));
    await db.into(db.waiters).insert(
        WaitersCompanion.insert(id: const Value(2), firstName: 'Salma'));
    for (final id in [7, 8, 9]) {
      await db.into(db.areaTables).insert(
          AreaTablesCompanion.insert(id: Value(id), name: 'T$id'));
    }

    server = container.read(serverServiceProvider);
    await server.start(port: port);
  });

  tearDown(() async {
    await server.stop();
    container.dispose();
    await db.close();
  });

  /// Seat [tableId] with an order belonging to [waiterId] (null = the cashier).
  Future<void> seat(int tableId, {int? waiterId}) async {
    final orderId = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'O$tableId',
          tableId: Value(tableId),
          waiterId: Value(waiterId),
        ));
    await (db.update(db.areaTables)..where((t) => t.id.equals(tableId)))
        .write(OrdersCompanionTableLink(orderId));
  }

  Future<Map<int, Map<String, dynamic>>> tables({int waiterId = 1}) async {
    final res = await http.get(base.replace(
      path: '/waiters/tables',
      queryParameters: {'waiterId': '$waiterId'},
    ));
    expect(res.statusCode, 200, reason: res.body);
    final list = (jsonDecode(res.body) as Map<String, dynamic>)['tables']
        as List<dynamic>;
    return {
      for (final t in list) (t as Map<String, dynamic>)['id'] as int: t,
    };
  }

  test('a table names the waiter holding it', () async {
    await seat(7, waiterId: 1);
    final rows = await tables();

    expect(rows[7]!['orderWaiterId'], 1);
    expect(rows[7]!['orderWaiterName'], 'Amina B');
  });

  test('a colleague on the same section is named too', () async {
    await seat(7, waiterId: 1);
    await seat(8, waiterId: 2);
    final rows = await tables(waiterId: 1);

    expect(rows[8]!['orderWaiterId'], 2,
        reason: 'this is the whole point — telling my table from hers on a '
            'shared section');
    expect(rows[8]!['orderWaiterName'], 'Salma');
  });

  test('a free table is null, never a wildcard', () async {
    final rows = await tables();
    expect(rows[9]!['orderWaiterId'], isNull);
    expect(rows[9]!['orderWaiterName'], isNull);
  });

  test('an order the cashier rang up is null, not blank or zero', () async {
    await seat(7); // no waiterId — the till took it
    final rows = await tables();

    expect(rows[7]!['orderId'], isNotNull, reason: 'the table IS occupied');
    expect(rows[7]!['orderWaiterId'], isNull,
        reason: 'it belongs to nobody on the floor');
    expect(rows[7]!['orderWaiterName'], isNull);
  });

  test('the key is present on every row, so absent never means anything else',
      () async {
    await seat(7, waiterId: 1);
    final rows = await tables();
    for (final row in rows.values) {
      expect(row.containsKey('orderWaiterId'), isTrue);
      expect(row.containsKey('orderWaiterName'), isTrue);
    }
  });

  test('the existing fields are untouched', () async {
    await seat(7, waiterId: 1);
    final row = (await tables())[7]!;
    expect(row['name'], 'T7');
    expect(row['orderCode'], 'O7');
    expect(row['totalAmount'], 0.0);
  });
}

/// `area_tables.orderId` only — writing the whole companion would clear the
/// row's other columns.
class OrdersCompanionTableLink extends AreaTablesCompanion {
  OrdersCompanionTableLink(int orderId) : super(orderId: Value(orderId));
}

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_tag_codec.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';

/// Order tags: made in the back office, put on orders at the till, pushed
/// with PUT /pos/orders/{code}/tags and pulled back on order snapshots.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('codec', () {
    test('ids round-trip, duplicates and junk dropped', () {
      expect(parseTagIds('1, 4,x,4'), [1, 4]);
      expect(parseTagIds(null), isEmpty);
      expect(encodeTagIds([4, 1, 4]), '4,1');
      expect(encodeTagIds([]), isNull);
    });

    test('snapshot tags: absent = no info, [] = cleared', () {
      expect(tagIdsFromSnapshot({'code': 'X'}), isNull);
      expect(tagIdsFromSnapshot({'tags': []}), isEmpty);
      expect(
          tagIdsFromSnapshot({
            'tags': [
              {'id': 3, 'label': 'VIP'},
              {'id': '5'}
            ]
          }),
          [3, 5]);
    });

    test('colors: #RGB and #RRGGBB, anything else falls back', () {
      expect(parseTagColor('#E53935'), 0xFFE53935);
      expect(parseTagColor('#ABC'), 0xFFAABBCC);
      expect(parseTagColor(null), isNull);
      expect(parseTagColor('red'), isNull);
    });

    test('filter: ANY of the tags, plus untagged on request', () {
      bool m(List<int> tags, Set<int> f, {bool untagged = false}) =>
          orderMatchesTagFilter(tags, tagIds: f, untagged: untagged);
      expect(m([1, 2], {}), isTrue, reason: 'no filter');
      expect(m([1, 2], {2, 9}), isTrue);
      expect(m([1], {2}), isFalse);
      expect(m([], {2}), isFalse);
      expect(m([], {}, untagged: true), isTrue);
      expect(m([1], {}, untagged: true), isFalse);
      expect(m([1], {1}, untagged: true), isTrue);
    });
  });

  group('sync', () {
    late AppDatabase db;
    late DataSyncService sync;
    late HttpServer server;
    late List<String> puts;
    late Map<String, int> putStatus; // order code → status to answer

    setUp(() async {
      HttpOverrides.global = null;
      puts = [];
      putStatus = {};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final res = req.response..headers.contentType = ContentType.json;
        final path = req.uri.path;
        if (path.endsWith('/pos/order-tags')) {
          res.write(jsonEncode({
            'tags': [
              {'id': 1, 'label': 'VIP', 'color': '#E53935', 'sortOrder': 2},
              {'id': 2, 'label': 'URG', 'color': null, 'sortOrder': 1},
            ]
          }));
        } else if (req.method == 'PUT' && path.contains('/pos/orders/')) {
          final code = path.split('/')[path.split('/').length - 2];
          puts.add('$code ${await utf8.decoder.bind(req).join()}');
          final st = putStatus[code] ?? 200;
          res.statusCode = st;
          if (st == 400) res.write(jsonEncode({'message': 'Unknown tag 99'}));
          // The server drops tag 2 as deleted meanwhile: stores [1] only.
          if (st == 200) {
            res.write(jsonEncode({
              'orderCode': code,
              'tags': [
                {'id': 1, 'label': 'VIP'}
              ]
            }));
          }
        } else {
          res.statusCode = 404;
        }
        await res.close();
      });
      SharedPreferences.setMockInitialValues(
          {'api_base_url': 'http://127.0.0.1:${server.port}'});
      final prefs = await SharedPreferences.getInstance();
      db = AppDatabase.forTesting(NativeDatabase.memory());
      sync = DataSyncService(db, ApiService(prefs), prefs);
    });
    tearDown(() async {
      await db.close();
      await server.close(force: true);
    });

    Future<Order> order(String code) =>
        (db.select(db.orders)..where((o) => o.code.equals(code))).getSingle();

    test('the catalogue is replaced whole (a deleted tag disappears)', () async {
      await db.into(db.orderTags).insert(
          OrderTagsCompanion.insert(id: const Value(77), label: 'OLD'));
      await sync.syncOrderTagCatalogue();
      final tags = await db.select(db.orderTags).get();
      expect(tags.map((t) => t.label).toSet(), {'VIP', 'URG'});
    });

    test('push: 200 marks synced, 404 waits, 400 is parked', () async {
      for (final code in ['A', 'B', 'C']) {
        await db.into(db.orders).insert(OrdersCompanion.insert(
              code: code,
              isSynced: const Value(true),
              tagIds: const Value('1,2'),
              tagsSynced: const Value(false),
            ));
      }
      putStatus = {'B': 404, 'C': 400};
      final pushed = await sync.pushOrderTags();

      expect(pushed, 1);
      expect(puts.firstWhere((p) => p.startsWith('A ')), contains('"tagIds":[1,2]'));
      expect((await order('A')).tagsSynced, isTrue);
      expect((await order('A')).tagIds, '1',
          reason: 'the till takes the set the server actually stored');
      expect((await order('B')).tagsSynced, isFalse, reason: 'order not on the server yet');
      expect((await order('B')).tagsSyncError, isNull);
      expect((await order('C')).tagsSyncError, 'Unknown tag 99');

      // A parked one is not re-sent on the next cycle.
      puts.clear();
      await sync.pushOrderTags();
      expect(puts.where((p) => p.startsWith('C ')), isEmpty);
    });

    test('an order not pushed yet is not tagged on the server yet', () async {
      await db.into(db.orders).insert(OrdersCompanion.insert(
            code: 'D',
            isSynced: const Value(false),
            tagIds: const Value('1'),
            tagsSynced: const Value(false),
          ));
      await sync.pushOrderTags();
      expect(puts, isEmpty);
    });

    Map<String, dynamic> snapshot(String code, List<int> tags) => {
          'code': code,
          'status': 'COMPLETED',
          'products': [],
          'payments': [],
          'tags': [for (final t in tags) {'id': t, 'label': 'T$t'}],
        };

    test('pull: server tags land, unless the till has a change to push',
        () async {
      await db.into(db.orders).insert(
          OrdersCompanion.insert(code: 'E', isSynced: const Value(true)));
      await sync.applyServerOrder(snapshot('E', [2, 1]));
      expect((await order('E')).tagIds, '2,1');

      // The back office cleared them: [] means cleared.
      await sync.applyServerOrder(snapshot('E', []));
      expect((await order('E')).tagIds, isNull);

      // A local change still waiting to go up wins over the snapshot.
      await (db.update(db.orders)..where((o) => o.code.equals('E'))).write(
          const OrdersCompanion(
              tagIds: Value('1'), tagsSynced: Value(false)));
      await sync.applyServerOrder(snapshot('E', [2]));
      expect((await order('E')).tagIds, '1');
    });
  });
}

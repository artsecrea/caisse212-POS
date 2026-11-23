import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/order_cancellations_provider.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/line_cancellation.dart';
import 'package:caisse212/utils/line_uid.dart';

/// Cancelled lines (backend v2 order push, 2026-10-20): a removed line is a
/// cancellation that keeps travelling with its order, not a deletion.
void main() {
  late AppDatabase db;
  late OrderRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OrderRepository(db);
    for (var i = 1; i <= 3; i++) {
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: Value(i), name: 'P$i', price: 10, finalPrice: 10));
    }
  });
  tearDown(() => db.close());

  Future<int> seed({String code = 'C1'}) async {
    final orderId =
        await db.into(db.orders).insert(
        OrdersCompanion.insert(code: code, status: const Value('COMPLETED')));
    for (final p in [1, 2]) {
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
          orderId: orderId,
          productId: p,
          quantity: const Value(3),
          unitaryPrice: 10,
          kdsPrintedQuantity: Value(p == 1 ? 3 : 0)));
    }
    return orderId;
  }

  Future<List<OrderProduct>> live(int orderId) =>
      (db.select(db.orderProducts)
            ..where((t) => t.orderId.equals(orderId))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();

  Future<List<CancelledOrderLine>> cancelled(int orderId) =>
      (db.select(db.cancelledOrderLines)
            ..where((t) => t.orderId.equals(orderId)))
          .get();

  test('every new line gets a permanent 7-character id', () async {
    final orderId = await seed();
    final uids = [for (final r in await live(orderId)) r.lineUid];
    expect(uids.every((u) => u != null && u.length == lineUidLength), isTrue);
    expect(uids.toSet(), hasLength(2));

    final cart = (await repo.getOrderById(orderId))!;
    await repo.updateOrder(
        cart.copyWith(items: [
          cart.items.first.copyWith(quantity: 5),
          cart.items.last,
        ]),
        queueSyncOperation: false);
    expect([for (final r in await live(orderId)) r.lineUid], uids,
        reason: 'an edit must never re-mint the identity');
  });

  test('a line removed in the panel is kept as a cancelled line', () async {
    final orderId = await seed();
    final p2 = (await live(orderId)).firstWhere((r) => r.productId == 2);
    final cart = (await repo.getOrderById(orderId))!;

    await repo.updateOrder(
        cart.copyWith(
            items: cart.items.where((i) => i.productId == 1).toList()),
        queueSyncOperation: false);

    expect((await live(orderId)).map((r) => r.productId), [1],
        reason: 'what is sold is unchanged: the line is gone from the bill');
    final c = (await cancelled(orderId)).single;
    expect(c.lineUid, p2.lineUid);
    expect(c.quantity, 3);
    expect(c.canceledQuantity, 3);
    expect(await db.select(db.removedOrderItems).get(), hasLength(1),
        reason: 'the X/Z tombstone is still written');
  });

  test('a quantity cut is a running total on the live line', () async {
    final orderId = await seed();
    var cart = (await repo.getOrderById(orderId))!;
    await repo.updateOrder(
        cart.copyWith(items: [
          cart.items.first.copyWith(quantity: 2),
          cart.items.last,
        ]),
        queueSyncOperation: false);
    cart = (await repo.getOrderById(orderId))!;
    await repo.updateOrder(
        cart.copyWith(items: [
          cart.items.first.copyWith(quantity: 1),
          cart.items.last,
        ]),
        queueSyncOperation: false);

    final p1 = (await live(orderId)).firstWhere((r) => r.productId == 1);
    expect(p1.quantity, 1);
    expect(p1.canceledQuantity, 2);
    expect(p1.canceledAt, isNotNull);
    expect(await cancelled(orderId), isEmpty);
  });

  test('cut then removed: canceledQuantity counts every unit', () async {
    final orderId = await seed();
    var cart = (await repo.getOrderById(orderId))!;
    await repo.updateOrder(
        cart.copyWith(items: [
          cart.items.first.copyWith(quantity: 1),
          cart.items.last,
        ]),
        queueSyncOperation: false);
    cart = (await repo.getOrderById(orderId))!;
    await repo.updateOrder(cart.copyWith(items: [cart.items.last]),
        queueSyncOperation: false);

    final c = (await cancelled(orderId)).single;
    expect(c.quantity, 1);
    expect(c.canceledQuantity, 3);
  });

  test('the waiter route keeps its removal too', () async {
    final orderId = await seed();
    final row = (await live(orderId)).first;
    await keepCancelledLine(db, row);
    final c = (await cancelled(orderId)).single;
    expect(c.lineUid, row.lineUid);
    expect(c.canceledBy, isNull, reason: 'a waiter id is not a user id');
  });

  group('the push', () {
    late DataSyncService sync;
    late _RecordingApi api;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      api = _RecordingApi(prefs);
      sync = DataSyncService(db, api, prefs);
    });

    Future<Order> order(int id) =>
        (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();

    test('v2 carries the full order: live, cut and cancelled lines',
        () async {
      final orderId = await seed();
      final cart = (await repo.getOrderById(orderId))!;
      await repo.updateOrder(
          cart.copyWith(items: [cart.items.first.copyWith(quantity: 2)]),
          queueSyncOperation: false);

      final lines =
          await sync.orderLinesForSync(await order(orderId), await live(orderId));
      expect(lines.v2, isTrue);
      expect(lines.products, hasLength(2));
      final cut = lines.products.firstWhere((p) => p['productId'] == 1);
      expect(cut['quantity'], 2);
      expect(cut['canceledQuantity'], 1);
      expect(cut['lineUid'], isNotNull);
      final gone = lines.products.firstWhere((p) => p['productId'] == 2);
      expect(gone['state'], 'CANCELED');
      expect(gone['quantity'], 3);
      expect(gone['canceledQuantity'], 3);
      expect(gone['canceledAt'],
          matches(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}$')));
    });

    test('an order with a line from before v66 stays on v1, unchanged',
        () async {
      final orderId = await seed();
      final first = (await live(orderId)).first;
      await (db.update(db.orderProducts)..where((t) => t.id.equals(first.id)))
          .write(const OrderProductsCompanion(lineUid: Value(null)));

      final lines =
          await sync.orderLinesForSync(await order(orderId), await live(orderId));
      expect(lines.v2, isFalse);
      expect(lines.products.every((p) => !p.containsKey('lineUid')), isTrue);
      expect(lines.products.every((p) => !p.containsKey('canceledQuantity')),
          isTrue);
    });

    test('single and bulk pushes pick the route per order', () async {
      final v2Order = await seed(code: 'V2');
      final legacy = await seed(code: 'V1');
      final first = (await live(legacy)).first;
      await (db.update(db.orderProducts)..where((t) => t.id.equals(first.id)))
          .write(const OrderProductsCompanion(lineUid: Value(null)));

      // Two unsynced orders → one sweep, split by route.
      await sync.syncOrdersBulk();
      expect(api.bulks, hasLength(2));
      expect(api.bulks.any((b) => b.$2 && b.$1.join() == 'V2'), isTrue);
      expect(api.bulks.any((b) => !b.$2 && b.$1.join() == 'V1'), isTrue);

      await sync.syncSingleOrder(v2Order, force: true);
      expect(api.singles.single, ('V2', true));
      expect(api.sentKeys.contains('_v2'), isFalse,
          reason: 'the route marker never reaches the wire');
    });

    test('a pull adopts the server line id when the till has none', () async {
      final orderId = await seed();
      final first = (await live(orderId)).first;
      await (db.update(db.orderProducts)..where((t) => t.id.equals(first.id)))
          .write(const OrderProductsCompanion(lineUid: Value(null)));

      await sync.applyOrderDeltaForTesting({
        'code': 'C1',
        'products': [
          {'id': 501, 'productId': 1, 'quantity': 3, 'unitaryPrice': 10,
            'lineUid': 'Srv0001X'},
        ],
      });
      final after = (await live(orderId)).firstWhere((r) => r.id == first.id);
      expect(after.lineUid, 'Srv0001X');
    });
  });

  test('the panel still shows recorded and unsaved cancellations', () async {
    final orderId = await seed();
    final cart = (await repo.getOrderById(orderId))!;
    final saved = [
      for (final r in await live(orderId)) SavedOrderLine(r, 'P${r.productId}'),
    ];
    final pending = pendingCancellations(
        cart.copyWith(items: [cart.items.first.copyWith(quantity: 1)]), saved);
    expect(pending.map((p) => '${p.name}:${p.quantity}'),
        containsAll(['P1:2.0', 'P2:3.0']));
  });
}

class _RecordingApi extends ApiService {
  _RecordingApi(super.prefs);
  final singles = <(String, bool)>[];
  final bulks = <(List<String>, bool)>[];
  final sentKeys = <String>{};

  @override
  Future<OrderPushResult> syncSingleOrder(
      String orderCode, Map<String, dynamic> orderData,
      {bool v2 = false}) async {
    singles.add((orderCode, v2));
    sentKeys.addAll(orderData.keys);
    return const OrderPushResult([], []);
  }

  @override
  Future<OrderPushResult> syncOrders(List<Map<String, dynamic>> orders,
      {bool v2 = false}) async {
    bulks.add(([for (final o in orders) o['code'] as String], v2));
    for (final o in orders) {
      sentKeys.addAll(o.keys);
    }
    return const OrderPushResult([], []);
  }
}

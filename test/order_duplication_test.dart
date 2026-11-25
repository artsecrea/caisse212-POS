import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/waiter_request_replay.dart';

/// Every way an order's lines were found doubled (2026-10-19 investigation),
/// each reproduced in a sandbox till before the fix.
void main() {
  group('a cashier save', () {
    late AppDatabase db;
    late OrderRepository repo;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = OrderRepository(db);
      for (var i = 1; i <= 4; i++) {
        await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(i), name: 'P$i', price: 10, finalPrice: 10));
      }
    });
    tearDown(() => db.close());

    Future<int> seed(String code, List<int> productIds) async {
      final orderId =
          await db.into(db.orders).insert(OrdersCompanion.insert(code: code));
      for (final p in productIds) {
        await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: p,
            quantity: const Value(1),
            unitaryPrice: 10));
      }
      return orderId;
    }

    Future<List<OrderProduct>> lines(int orderId) =>
        (db.select(db.orderProducts)
              ..where((t) => t.orderId.equals(orderId))
              ..orderBy([(t) => OrderingTerm(expression: t.id)]))
            .get();

    test('saving the same cart twice does not double it', () async {
      // The waiter button saved the cart and left it in the panel; Continuer
      // then saved it again. 3 lines became 6.
      final orderId = await seed('A', [1, 2, 3]);
      final cart = (await repo.getOrderById(orderId))!;

      await repo.updateOrder(cart, queueSyncOperation: false);
      await repo.updateOrder(cart, queueSyncOperation: false);

      expect((await lines(orderId)).map((l) => l.productId), [1, 2, 3]);
    });

    test('a held cart resumed after another save does not double it',
        () async {
      final orderId = await seed('B', [1, 2]);
      final held = (await repo.getOrderById(orderId))!;

      // The table is reopened and saved while the first cart sits on hold.
      final fresh = (await repo.getOrderById(orderId))!;
      await repo.updateOrder(fresh, queueSyncOperation: false);

      await repo.updateOrder(held, queueSyncOperation: false);

      expect((await lines(orderId)).map((l) => l.productId), [1, 2]);
    });

    test('a line keeps its id across saves', () async {
      final orderId = await seed('C', [1]);
      final before = (await lines(orderId)).single.id;
      final cart = (await repo.getOrderById(orderId))!;
      await repo.updateOrder(
          cart.copyWith(items: [cart.items.single.copyWith(quantity: 3)]),
          queueSyncOperation: false);
      final after = (await lines(orderId)).single;
      expect(after.id, before);
      expect(after.quantity, 3);
    });

    test('does not bring back a line the waiter removed meanwhile', () async {
      final orderId = await seed('D', [1, 2]);
      final cart = (await repo.getOrderById(orderId))!;

      final pulled = (await lines(orderId)).firstWhere((l) => l.productId == 2);
      await (db.delete(db.orderProducts)..where((t) => t.id.equals(pulled.id)))
          .go();

      await repo.updateOrder(cart, queueSyncOperation: false);

      expect((await lines(orderId)).map((l) => l.productId), [1]);
    });

    test('does not re-sell a line that was paid meanwhile', () async {
      final orderId = await seed('E', [1, 2]);
      final cart = (await repo.getOrderById(orderId))!;

      final ticketId = await db.into(db.tickets).insert(TicketsCompanion.insert(
          num: '0001', orderId: orderId, paymentMethod: 'CASH', amount: 10));
      final paid = (await lines(orderId)).firstWhere((l) => l.productId == 2);
      await (db.update(db.orderProducts)..where((t) => t.id.equals(paid.id)))
          .write(OrderProductsCompanion(ticketId: Value(ticketId)));

      await repo.updateOrder(cart, queueSyncOperation: false);

      final rows = await lines(orderId);
      expect(rows.where((l) => l.productId == 2), hasLength(1));
      expect(rows.firstWhere((l) => l.productId == 2).ticketId, ticketId);
    });

    test('still removes a line the cashier dropped, even one the KDS touched',
        () async {
      final orderId = await seed('F', [1, 2]);
      final cart = (await repo.getOrderById(orderId))!;

      // The kitchen bumps the line after the cart was read.
      final bumped = (await lines(orderId)).firstWhere((l) => l.productId == 2);
      await (db.update(db.orderProducts)..where((t) => t.id.equals(bumped.id)))
          .write(OrderProductsCompanion(
              state: const Value('PREPARING'),
              updatedAt: Value(DateTime.now().add(const Duration(seconds: 5)))));

      await repo.updateOrder(
          cart.copyWith(
              items: cart.items.where((i) => i.productId != 2).toList()),
          queueSyncOperation: false);

      expect((await lines(orderId)).map((l) => l.productId), [1]);
    });

    test('keeps the print stamps a cart read before the print landed',
        () async {
      final orderId = await seed('G', [1]);
      final cart = (await repo.getOrderById(orderId))!;
      final row = (await lines(orderId)).single;
      await (db.update(db.orderProducts)..where((t) => t.id.equals(row.id)))
          .write(const OrderProductsCompanion(
              kdsPrintedQuantity: Value(1),
              orderTicketPrintedQuantity: Value(1)));

      await repo.updateOrder(cart, queueSyncOperation: false);

      final after = (await lines(orderId)).single;
      expect(after.kdsPrintedQuantity, 1);
      expect(after.orderTicketPrintedQuantity, 1);
    });

    test('a line belonging to another order is moved in, not dropped',
        () async {
      final source = await seed('H1', [3]);
      final target = await seed('H2', [1]);
      final moving = (await repo.getOrderById(source))!.items.single;
      final cart = (await repo.getOrderById(target))!;

      await repo.updateOrder(cart.copyWith(items: [...cart.items, moving]),
          queueSyncOperation: false);

      expect((await lines(target)).map((l) => l.productId), [1, 3]);
    });
  });

  group('waiter request replay', () {
    late int runs;
    late WaiterRequestReplay replay;
    Future<Response> handler(Request r) async {
      runs++;
      await r.readAsString();
      return Response(201,
          body: jsonEncode({'code': 'X$runs'}),
          headers: {'Content-Type': 'application/json'});
    }

    Request req(Map<String, Object?> body, {String? key}) => Request(
        'POST', Uri.parse('http://pos/waiters/orders'),
        body: jsonEncode(body),
        headers: {if (key != null) 'idempotency-key': key});

    setUp(() {
      runs = 0;
      replay = WaiterRequestReplay();
    });

    test('a retry with the same requestId gets the first answer', () async {
      final a = await replay.run(req({'requestId': 'r1', 'p': 1}), 's', handler);
      final b = await replay.run(req({'requestId': 'r1', 'p': 1}), 's', handler);
      expect(runs, 1);
      expect(await b.readAsString(), await a.readAsString());
      expect(b.headers[WaiterRequestReplay.replayHeader], 'true');
    });

    test('the header key works the same way', () async {
      await replay.run(req({'p': 1}, key: 'k'), 's', handler);
      await replay.run(req({'p': 2}, key: 'k'), 's', handler);
      expect(runs, 1);
    });

    test('a double tap waits for the first attempt instead of racing it',
        () async {
      final gate = Completer<void>();
      Future<Response> slow(Request r) async {
        await gate.future;
        return handler(r);
      }

      final first = replay.run(req({'requestId': 'r'}), 's', slow);
      final second = replay.run(req({'requestId': 'r'}), 's', slow);
      gate.complete();
      await Future.wait([first, second]);
      expect(runs, 1);
    });

    test('a refused attempt is not remembered', () async {
      var refuse = true;
      Future<Response> h(Request r) async {
        runs++;
        return refuse ? Response(409, body: '{}') : Response.ok('{}');
      }

      await replay.run(req({'requestId': 'r'}), 's', h);
      refuse = false;
      final b = await replay.run(req({'requestId': 'r'}), 's', h);
      expect(runs, 2);
      expect(b.statusCode, 200);
    });

    test('without a key every request runs: identical rounds can be real',
        () async {
      await replay.run(req({'p': 1}), 'b', handler);
      await replay.run(req({'p': 1}), 'b', handler);
      expect(runs, 2);
    });

    test('a key is forgotten after its window', () async {
      var now = DateTime(2026);
      replay = WaiterRequestReplay(clock: () => now);
      await replay.run(req({'requestId': 'r'}), 'b', handler);
      now = now.add(const Duration(minutes: 11));
      await replay.run(req({'requestId': 'r'}), 'b', handler);
      expect(runs, 2);
    });
  });

  group('order push', () {
    test('never runs two pushes of one order at the same time', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final api = _CountingApi(prefs);
      final sync = DataSyncService(db, api, prefs);
      final orderId =
          await db.into(db.orders).insert(OrdersCompanion.insert(code: 'P1'));

      // A save, a payment and a waiter round, milliseconds apart.
      await Future.wait([
        sync.syncSingleOrder(orderId, force: true),
        sync.syncSingleOrder(orderId, force: true),
        sync.syncSingleOrder(orderId, force: true),
      ]);

      expect(api.maxConcurrent, 1);
      expect(api.calls, lessThanOrEqualTo(2),
          reason: 'requests arriving during a push share one follow-up');
    });
  });
}

class _CountingApi extends ApiService {
  _CountingApi(super.prefs);
  int running = 0, maxConcurrent = 0, calls = 0;

  @override
  Future<OrderPushResult> syncSingleOrder(
      String orderCode, Map<String, dynamic> orderData,
      {bool v2 = false}) async {
    calls++;
    running++;
    if (running > maxConcurrent) maxConcurrent = running;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    running--;
    return const OrderPushResult([], []);
  }
}

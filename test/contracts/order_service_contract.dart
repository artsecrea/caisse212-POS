import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/domain/services/order_service.dart';

/// What an [OrderService] must do, whoever implements it: the local service
/// runs these on the till's database, a hub-backed one will run them against
/// the hub with its own harness. Run offline: nothing reaches a cloud.
abstract class OrderHarness {
  OrderService get orders;

  /// An open cash session, for carts to be submitted into.
  Future<int> openSession();

  Future<int> addTable();

  /// A product the carts can sell, priced [price].
  int get productId;

  Future<int> lineCountOf(int orderId);

  /// An open order seated at a new table, with one paid ticket.
  Future<({int orderId, int tableId, int ticketId})> seatedPaidOrder();

  Future<String> statusOf(int orderId);
  Future<String?> cancellationReasonOf(int orderId);
  Future<int?> holderOf(int tableId);
  Future<bool> ticketCancelled(int ticketId);
  Future<List<int>> tagsOf(int orderId);

  Future<void> dispose();
}

void orderServiceContract(String name, Future<OrderHarness> Function() make) {
  group('$name honours the OrderService contract', () {
    late OrderHarness h;

    setUp(() async => h = await make());
    tearDown(() => h.dispose());

    test('a cancel lands, frees the table and voids the tickets', () async {
      final o = await h.seatedPaidOrder();

      await h.orders.cancelOrder(o.orderId, reason: 'customer left');

      expect(await h.statusOf(o.orderId), 'CANCELED');
      expect(await h.cancellationReasonOf(o.orderId), 'customer left');
      expect(await h.holderOf(o.tableId), isNull);
      expect(await h.ticketCancelled(o.ticketId), isTrue);
    });

    test('the back office cancelling frees the table too', () async {
      final o = await h.seatedPaidOrder();

      await h.orders.changeStatus(o.orderId, 'CANCELED');

      expect(await h.statusOf(o.orderId), 'CANCELED');
      expect(await h.holderOf(o.tableId), isNull);
    });

    test('another status keeps the table and reports nothing pushed offline',
        () async {
      final o = await h.seatedPaidOrder();

      final pushed = await h.orders.changeStatus(o.orderId, 'DELIVERED');

      expect(pushed, isFalse);
      expect(await h.statusOf(o.orderId), 'DELIVERED');
      expect(await h.holderOf(o.tableId), o.orderId);
    });

    test('an order put on hold never counts as pushed', () async {
      final o = await h.seatedPaidOrder();
      expect(await h.orders.changeStatus(o.orderId, 'ONHOLD'), isFalse);
      expect(await h.statusOf(o.orderId), 'ONHOLD');
    });

    CurrentOrder cart({int? tableId, double qty = 2}) => CurrentOrder(
          tableId: tableId,
          items: [
            OrderItem(
                productId: h.productId,
                productName: 'P',
                finalPrice: 10,
                quantity: qty),
          ],
        );

    test('a new cart becomes an order, seated, and comes back with ids',
        () async {
      final session = await h.openSession();
      final table = await h.addTable();

      final s = await h.orders
          .submitCart(cart(tableId: table), userId: 1, sessionId: session);

      expect(await h.holderOf(table), s.orderId);
      expect(s.reloaded?.orderId, s.orderId);
      expect(s.reloaded!.items.single.id, isNotNull,
          reason: 'the reload carries the line ids the cart lacked');
      expect(s.reloaded!.items.single.quantity, 2);
    });

    test('a reset restarts the session\u2019s order numbers at 1', () async {
      final session = await h.openSession();
      Future<int?> next() async => (await h.orders
              .submitCart(cart(), userId: 1, sessionId: session))
          .reloaded
          ?.sessionOrderNo;

      expect(await next(), 1);
      expect(await next(), 2);
      await h.orders.resetOrderNumber(session);
      expect(await next(), 1);
    });

    test('a saved cart is updated in place', () async {
      final session = await h.openSession();
      final first = await h.orders
          .submitCart(cart(), userId: 1, sessionId: session);
      final saved = first.reloaded!;
      final more = saved.copyWith(items: [
        ...saved.items,
        OrderItem(productId: h.productId, productName: 'P', finalPrice: 10),
      ]);

      final again =
          await h.orders.submitCart(more, userId: 1, sessionId: session);

      expect(again.orderId, first.orderId);
      expect(await h.lineCountOf(first.orderId), 2);
    });

    test('a header-only write keeps the lines as they are', () async {
      final session = await h.openSession();
      final saved = (await h.orders
              .submitCart(cart(), userId: 1, sessionId: session))
          .reloaded!;

      await h.orders.updateCart(saved.copyWith(items: const []),
          headerOnly: true);

      expect(await h.lineCountOf(saved.orderId!), 1);
    });

    test('tags are replaced', () async {
      final o = await h.seatedPaidOrder();

      await h.orders.setTags(o.orderId, [3, 1]);
      expect((await h.tagsOf(o.orderId))..sort(), [1, 3]);

      await h.orders.setTags(o.orderId, []);
      expect(await h.tagsOf(o.orderId), isEmpty);
    });
  });
}

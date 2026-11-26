import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/services/order_service.dart';

/// What an [OrderService] must do, whoever implements it: the local service
/// runs these on the till's database, a hub-backed one will run them against
/// the hub with its own harness. Run offline: nothing reaches a cloud.
abstract class OrderHarness {
  OrderService get orders;

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

    test('tags are replaced', () async {
      final o = await h.seatedPaidOrder();

      await h.orders.setTags(o.orderId, [3, 1]);
      expect((await h.tagsOf(o.orderId))..sort(), [1, 3]);

      await h.orders.setTags(o.orderId, []);
      expect(await h.tagsOf(o.orderId), isEmpty);
    });
  });
}

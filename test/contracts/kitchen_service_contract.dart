import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/services/kitchen_service.dart';

/// What a [KitchenService] must do, whoever implements it: the local service
/// runs these on the till's database, a hub-backed one will run them against
/// the hub with its own harness.
abstract class KitchenHarness {
  KitchenService get kitchen;

  /// An open order of [sessionId] with [lines] lines, all PENDING. Returns
  /// the order id and the line ids.
  Future<({int orderId, List<int> lineIds})> openOrder(int sessionId,
      {int lines = 1});

  Future<String> stateOf(int lineId);
  Future<DateTime?> preparingAtOf(int lineId);
  Future<String> orderStatusOf(int orderId);
  Future<bool> isRush(int orderId);

  Future<void> dispose();
}

void kitchenServiceContract(
    String name, Future<KitchenHarness> Function() make) {
  group('$name honours the KitchenService contract', () {
    late KitchenHarness h;

    setUp(() async => h = await make());
    tearDown(() => h.dispose());

    test('a line moves stage and is stamped once', () async {
      final o = await h.openOrder(1);
      final line = o.lineIds.single;

      expect(await h.kitchen.setLineState(line, 'PREPARING'), isTrue);
      expect(await h.stateOf(line), 'PREPARING');
      final first = await h.preparingAtOf(line);
      expect(first, isNotNull);

      await h.kitchen.setLineState(line, 'READY');
      await h.kitchen.setLineState(line, 'PREPARING');
      expect(await h.preparingAtOf(line), first,
          reason: 'a remake keeps the original prep start');
    });

    test('an unknown line is reported, not invented', () async {
      expect(await h.kitchen.setLineState(999999, 'PREPARING'), isFalse);
    });

    test('a micro-state never drags the order status down', () async {
      final o = await h.openOrder(1, lines: 2);
      for (final l in o.lineIds) {
        await h.kitchen.setLineState(l, 'READY');
      }
      expect(await h.orderStatusOf(o.orderId), 'COMPLETED');
    });

    test('every line cancelled cancels the order', () async {
      final o = await h.openOrder(1, lines: 2);
      for (final l in o.lineIds) {
        await h.kitchen.setLineState(l, 'CANCELED');
      }
      expect(await h.orderStatusOf(o.orderId), 'CANCELED');
    });

    test('rush is set and cleared', () async {
      final o = await h.openOrder(1);
      await h.kitchen.setRush(o.orderId, true);
      expect(await h.isRush(o.orderId), isTrue);
      await h.kitchen.setRush(o.orderId, false);
      expect(await h.isRush(o.orderId), isFalse);
    });

    test('the board shows the open lines of the session', () async {
      final o = await h.openOrder(1);
      final board = await h.kitchen.watchBoard(1).first;
      expect(board.map((b) => b.id), contains(o.orderId));
    });
  });
}

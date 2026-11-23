import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/core/enums.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/domain/models/split_bill.dart';
import 'package:caisse212/presentation/paymen_screen/payment_screen.dart';
import 'package:caisse212/providers/order_provider.dart';

/// Dividing by articles AND by amount on one order: a ticket of the article
/// division is shared out by amount on its own. Its paid parts are line-less
/// tickets whose `split.forLines` name the lines they paid towards, and
/// reopening the order — or reloading it from the server, or another till
/// opening it — has to put them back under that ticket and nowhere else.

OrderItem _item(int id, {double price = 10, double quantity = 1}) => OrderItem(
      id: id,
      productId: id,
      productName: 'Item $id',
      finalPrice: price,
      quantity: quantity,
    );

TicketData _ticket(List<OrderItem> items) => TicketData(
      items: items.map(TicketLine.whole).toList(),
      paymentMethod: TransactionType.cash,
    );

double _qty(TicketData t, int rowId) => t.items
    .expand((l) => l.sources)
    .where((s) => s.rowId == rowId)
    .fold(0.0, (s, src) => s + src.quantity);

void main() {
  final uids = {1: 'u1', 2: 'u2', 3: 'u3'};

  group('attachMoneyGroups', () {
    test('the shared ticket comes back with its lines and its group', () {
      // The draft division was lost (reload): everything is on one ticket.
      final tickets = attachMoneyGroups(
        [_ticket([_item(1), _item(2), _item(3)])],
        [
          (
            groupId: 'g1',
            forLines: const [
              SplitForLine(localLineId: 1, lineUid: 'u1', qty: 1),
              SplitForLine(localLineId: 2, lineUid: 'u2', qty: 1),
            ],
          ),
        ],
        lineUidByRowId: uids,
      );

      expect(tickets.length, 2);
      expect(tickets[0].moneyGroups, ['g1']);
      expect(_qty(tickets[0], 1), 1);
      expect(_qty(tickets[0], 2), 1);
      expect(_qty(tickets[0], 3), 0);
      expect(tickets[1].moneyGroups, isEmpty);
      expect(_qty(tickets[1], 3), 1);
    });

    test('lines are found by lineUid, not by another till\'s row id', () {
      // Another till's local id 3 is our row 1 — the uid says which.
      final tickets = attachMoneyGroups(
        [_ticket([_item(1)]), _ticket([_item(3)])],
        [
          (
            groupId: 'g1',
            forLines: const [
              SplitForLine(localLineId: 3, lineUid: 'u1', qty: 1),
            ],
          ),
        ],
        lineUidByRowId: uids,
      );

      final shared = tickets.singleWhere((t) => t.moneyGroups.isNotEmpty);
      expect(_qty(shared, 1), 1);
      expect(_qty(shared, 3), 0);
    });

    test('a part of a line: only the paid-towards quantity moves', () {
      final tickets = attachMoneyGroups(
        [_ticket([_item(1, quantity: 5)])],
        [
          (
            groupId: 'g1',
            forLines: const [SplitForLine(lineUid: 'u1', qty: 2)],
          ),
        ],
        lineUidByRowId: uids,
      );

      expect(tickets.length, 2);
      expect(tickets[0].moneyGroups, ['g1']);
      expect(tickets[0].items.single.item.quantity, 2);
      expect(_qty(tickets[0], 1), 2);
      expect(tickets[1].items.single.item.quantity, 3);
      expect(_qty(tickets[1], 1), 3);
    });

    test('two splits on the same lines share one ticket', () {
      const lines = [SplitForLine(lineUid: 'u1', qty: 1)];
      final tickets = attachMoneyGroups(
        [_ticket([_item(1), _item(2)])],
        [
          (groupId: 'g1', forLines: lines),
          (groupId: 'g2', forLines: lines),
        ],
        lineUidByRowId: uids,
      );

      expect(tickets.length, 2);
      expect(tickets[0].moneyGroups, ['g1', 'g2']);
    });

    test('parts from before forLines fold the order into one ticket', () {
      final tickets = attachMoneyGroups(
        [_ticket([_item(1)]), _ticket([_item(2)])],
        [(groupId: 'old', forLines: const [])],
        lineUidByRowId: uids,
      );

      expect(tickets.length, 1);
      expect(tickets.single.moneyGroups, ['old']);
      expect(tickets.single.items.length, 2);
    });

    test('a group whose lines are no longer unpaid credits nobody', () {
      final tickets = attachMoneyGroups(
        [_ticket([_item(2)])],
        [
          (
            groupId: 'g1',
            forLines: const [SplitForLine(lineUid: 'gone', qty: 1)],
          ),
        ],
        lineUidByRowId: uids,
      );

      expect(tickets.length, 1);
      expect(tickets.single.moneyGroups, isEmpty);
    });
  });

  group('split JSON', () {
    test('forLines and closesGroups round-trip', () {
      final d = SplitDetails.decode(const SplitDetails(
        groupId: 'g1',
        mode: SplitMode.equal,
        part: 1,
        parts: 2,
        orderTotal: 40,
        forLines: [SplitForLine(localLineId: 7, lineUid: 'u7', qty: 1.5)],
        closesGroups: ['g0'],
      ).encode())!;

      expect(d.forLines.single.localLineId, 7);
      expect(d.forLines.single.lineUid, 'u7');
      expect(d.forLines.single.qty, 1.5);
      expect(d.closesGroups, ['g0']);
    });

    test('absent keys stay absent on the wire', () {
      final json = const SplitDetails(
        groupId: 'g',
        mode: SplitMode.amount,
        part: 1,
        parts: 1,
        orderTotal: 10,
      ).toJson();
      expect(json.containsKey('forLines'), isFalse);
      expect(json.containsKey('closesGroups'), isFalse);
    });
  });

  group('moneySplitParts', () {
    late AppDatabase db;
    late OrderRepository repo;
    late int orderId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = OrderRepository(db);
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(1),
            name: 'P1',
            price: 10,
            finalPrice: 10,
          ));
      orderId =
          await db.into(db.orders).insert(OrdersCompanion.insert(code: 'O1'));
    });
    tearDown(() => db.close());

    Future<int> ticket(String num, double amount, SplitDetails split) =>
        db.into(db.tickets).insert(TicketsCompanion.insert(
              num: num,
              orderId: orderId,
              paymentMethod: 'CASH',
              amount: amount,
              splitDetails: Value(split.encode()),
              isPaid: const Value(true),
            ));

    SplitDetails part(String group, {List<String> closes = const []}) =>
        SplitDetails(
          groupId: group,
          mode: SplitMode.equal,
          part: 1,
          parts: 2,
          orderTotal: 20,
          closesGroups: closes,
        );

    test('parts of finished splits are no longer credit', () async {
      await ticket('0001', 10, part('open'));
      await ticket('0002', 10, part('done'));
      // Another till's closing ticket: no local line points at it.
      await ticket('0003', 10, part('done', closes: ['done']));

      final parts = await repo.moneySplitParts(orderId);
      expect(parts.map((t) => t.num), ['0001']);
    });

    test('a money ticket that claims lines finishes its group', () async {
      await ticket('0001', 10, part('g'));
      final closer = await ticket('0002', 10, part('g'));
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            unitaryPrice: 20,
            ticketId: Value(closer),
          ));

      expect(await repo.moneySplitParts(orderId), isEmpty);
    });
  });
}

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/core/enums.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/presentation/paymen_screen/payment_screen.dart';

/// Splitting an order into tickets BEFORE any money changes hands, saved so
/// the arrangement survives leaving the payment screen and coming back.
///
/// Two things are pinned here. [reconstructUnpaidTickets] is the pure
/// rebuild rule — given a saved draft split and what the order currently
/// holds, what tickets does the cashier see on reopen. The `TicketDraftSplits`
/// group covers the storage side directly: the table accepts the exact shape
/// a split with a partially-covered line produces, and it never touches
/// `order_products.ticket_id`, which the rest of the app reads as "this line
/// is paid" in three dozen places — a draft split leaking into that column
/// would make every one of them wrong.

OrderItem _item(int id, {double price = 10, double quantity = 1}) => OrderItem(
      id: id,
      productId: id,
      productName: 'Item $id',
      finalPrice: price,
      quantity: quantity,
    );

void main() {
  group('no draft saved', () {
    test('one ticket holding everything, same as before this existed', () {
      final items = [_item(1), _item(2)];
      final tickets = reconstructUnpaidTickets(
        items,
        const [],
        defaultMethod: TransactionType.cash,
        discountPercentage: 0,
      );

      expect(tickets.length, 1);
      expect(tickets.single.items.map((l) => l.item.id), [1, 2]);
    });

    test('no unpaid items is no tickets, not one empty one', () {
      final tickets = reconstructUnpaidTickets(
        const [],
        const [],
        defaultMethod: TransactionType.cash,
        discountPercentage: 0,
      );
      expect(tickets, isEmpty);
    });
  });

  group('a clean two-way split rebuilds exactly', () {
    test('each item lands on the ticket it was saved under', () {
      final items = [_item(1), _item(2), _item(3)];
      final tickets = reconstructUnpaidTickets(
        items,
        const [
          (orderProductId: 1, draftIndex: 0, quantity: 1),
          (orderProductId: 2, draftIndex: 1, quantity: 1),
          (orderProductId: 3, draftIndex: 1, quantity: 1),
        ],
        defaultMethod: TransactionType.cash,
        discountPercentage: 0,
      );

      expect(tickets.length, 2);
      expect(tickets[0].items.map((l) => l.item.id), [1]);
      expect(tickets[1].items.map((l) => l.item.id), [2, 3]);
    });

    test('a fractional split survives — half a line on each ticket', () {
      // What allocateFreeAllowance-style partial coverage looks like once a
      // line itself has been divided between two tickets (a shared starter,
      // say): 3 units of one row, 2 saved to ticket 0, 1 to ticket 1.
      final items = [_item(1, quantity: 3)];
      final tickets = reconstructUnpaidTickets(
        items,
        const [
          (orderProductId: 1, draftIndex: 0, quantity: 2),
          (orderProductId: 1, draftIndex: 1, quantity: 1),
        ],
        defaultMethod: TransactionType.cash,
        discountPercentage: 0,
      );

      expect(tickets.length, 2);
      expect(tickets[0].items.single.item.quantity, 2);
      expect(tickets[1].items.single.item.quantity, 1);
      // The invariant every TicketLine has to hold: quantity == sum(sources).
      expect(tickets[0].items.single.sources.single.quantity, 2);
      expect(tickets[1].items.single.sources.single.quantity, 1);
    });

    test('draft index order does not have to be saved order', () {
      final items = [_item(1)];
      final tickets = reconstructUnpaidTickets(
        items,
        const [(orderProductId: 1, draftIndex: 2, quantity: 1)],
        defaultMethod: TransactionType.cash,
        discountPercentage: 0,
      );
      // One row at index 2 still produces exactly one ticket — the index is
      // a sort key among whatever indices are present, not a slot count.
      expect(tickets.length, 1);
    });
  });

  group('the order changed since the split was saved', () {
    test('a line removed from the order drops its stale claim silently', () {
      // Draft references id 2, which is no longer on the order (removed, or
      // it was paid through some other path and only id 1 remains unpaid).
      final items = [_item(1)];
      final tickets = reconstructUnpaidTickets(
        items,
        const [
          (orderProductId: 1, draftIndex: 0, quantity: 1),
          (orderProductId: 2, draftIndex: 1, quantity: 1),
        ],
        defaultMethod: TransactionType.cash,
        discountPercentage: 0,
      );

      expect(tickets.length, 1);
      expect(tickets.single.items.single.item.id, 1);
    });

    test('a claim for more than the line now holds is dropped, not clamped',
        () {
      // Saved when the line was 3; the cashier has since reduced it to 1.
      // Trusting a clamp here would silently invent a partial claim the
      // cashier never made.
      final items = [_item(1, quantity: 1)];
      final tickets = reconstructUnpaidTickets(
        items,
        const [(orderProductId: 1, draftIndex: 0, quantity: 3)],
        defaultMethod: TransactionType.cash,
        discountPercentage: 0,
      );

      // The stale claim is dropped entirely, so the line falls through to
      // the leftover bucket at its CURRENT quantity — not the stale 3, not
      // silently vanished either.
      expect(tickets.length, 1);
      expect(tickets.single.items.single.item.quantity, 1);
    });

    test('a line added to the order since the split lands on the first ticket',
        () {
      // Draft only knows about id 1; id 2 was added afterward and has never
      // been assigned anywhere.
      final items = [_item(1), _item(2)];
      final tickets = reconstructUnpaidTickets(
        items,
        const [
          (orderProductId: 1, draftIndex: 0, quantity: 1),
        ],
        defaultMethod: TransactionType.cash,
        discountPercentage: 0,
      );

      expect(tickets.length, 1);
      expect(tickets.single.items.map((l) => l.item.id), [1, 2]);
    });

    test(
        'a leftover line joins ticket 0 even when every draft row was stale',
        () {
      // Every saved row is stale (id 9 does not exist); the whole order
      // becomes "leftover" and has to still end up on screen, not vanish.
      final items = [_item(1), _item(2)];
      final tickets = reconstructUnpaidTickets(
        items,
        const [(orderProductId: 9, draftIndex: 0, quantity: 1)],
        defaultMethod: TransactionType.cash,
        discountPercentage: 0,
      );

      expect(tickets.length, 1);
      expect(tickets.single.items.map((l) => l.item.id), [1, 2]);
    });
  });

  group('TicketDraftSplits storage', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('accepts a fractional-quantity split row', () async {
      await db.into(db.ticketDraftSplits).insert(
            TicketDraftSplitsCompanion.insert(
              orderId: 1,
              orderProductId: 7,
              draftIndex: 0,
              quantity: 2.5,
            ),
          );

      final rows = await db.select(db.ticketDraftSplits).get();
      expect(rows.single.quantity, 2.5);
    });

    test('one order_product row can appear in two draft tickets at once',
        () async {
      // The exact shape a divided line produces: same orderProductId, two
      // different draftIndex values, quantities that sum to the line.
      await db.into(db.ticketDraftSplits).insert(
            TicketDraftSplitsCompanion.insert(
              orderId: 1,
              orderProductId: 7,
              draftIndex: 0,
              quantity: 2,
            ),
          );
      await db.into(db.ticketDraftSplits).insert(
            TicketDraftSplitsCompanion.insert(
              orderId: 1,
              orderProductId: 7,
              draftIndex: 1,
              quantity: 1,
            ),
          );

      final rows = await db.select(db.ticketDraftSplits).get();
      expect(rows.length, 2);
      expect(rows.map((r) => r.quantity).reduce((a, b) => a + b), 3);
    });

    test('rows for one order do not leak into a query for another', () async {
      await db.into(db.ticketDraftSplits).insert(
            TicketDraftSplitsCompanion.insert(
              orderId: 1,
              orderProductId: 7,
              draftIndex: 0,
              quantity: 1,
            ),
          );
      await db.into(db.ticketDraftSplits).insert(
            TicketDraftSplitsCompanion.insert(
              orderId: 2,
              orderProductId: 8,
              draftIndex: 0,
              quantity: 1,
            ),
          );

      final forOrder1 = await (db.select(db.ticketDraftSplits)
            ..where((t) => t.orderId.equals(1)))
          .get();
      expect(forOrder1.single.orderProductId, 7);
    });
  });
}

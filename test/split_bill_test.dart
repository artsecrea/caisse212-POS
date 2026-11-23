import 'dart:convert';

import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/domain/models/split_bill.dart';
import 'package:caisse212/presentation/paymen_screen/payment_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('equalPartAmount', () {
    test('last part takes the rounding remainder', () {
      expect(equalPartAmount(100, 3, 1), 33.33);
      expect(equalPartAmount(100, 3, 2), 33.33);
      expect(equalPartAmount(100, 3, 3), 33.34);
    });

    test('parts always add up to the bill', () {
      for (final total in [10.0, 99.99, 240.0, 0.05, 1234.57]) {
        for (var n = 2; n <= 7; n++) {
          final sum = [
            for (var i = 1; i <= n; i++) equalPartAmount(total, n, i),
          ].fold<double>(0, (s, v) => s + v);
          expect(roundMoney(sum), roundMoney(total), reason: '$total / $n');
        }
      }
    });

    test('one part is the whole bill', () {
      expect(equalPartAmount(42.5, 1, 1), 42.5);
    });
  });

  group('nextTicketNumber', () {
    test('max + 1, four digits', () {
      expect(nextTicketNumber(['0001', '0003']), '0004');
      expect(nextTicketNumber(const []), '0001');
    });

    test('server numbers count too, so two tills cannot both mint one', () {
      expect(nextTicketNumber(['0001'], ['0001', '0002']), '0003');
    });

    test('junk numbers are ignored', () {
      expect(nextTicketNumber(['abc', '0002']), '0003');
    });
  });

  group('SplitDetails', () {
    test('wire shape', () {
      final json = const SplitDetails(
        groupId: 'g1',
        mode: SplitMode.equal,
        part: 2,
        parts: 3,
        orderTotal: 100.004,
      ).toJson();
      expect(json, {
        'v': 1,
        'groupId': 'g1',
        'mode': 'EQUAL',
        'part': 2,
        'parts': 3,
        'orderTotal': 100.0,
      });
    });

    test('money parts carry no lines key', () {
      final json = const SplitDetails(
        groupId: 'g',
        mode: SplitMode.amount,
        part: 1,
        parts: 1,
        orderTotal: 10,
      ).toJson();
      expect(json.containsKey('lines'), isFalse);
    });

    test('decode round-trips and is lenient', () {
      final d = SplitDetails.decode(
        const SplitDetails(
          groupId: 'g',
          mode: SplitMode.products,
          part: 1,
          parts: 2,
          orderTotal: 50,
        ).encode(),
      );
      expect(d?.mode, SplitMode.products);
      expect(d?.parts, 2);
      expect(SplitDetails.decode('not json'), isNull);
      expect(SplitDetails.decode('{"mode":"WHAT"}'), isNull);
      expect(SplitDetails.decode(null), isNull);
    });

    test('isMoney', () {
      expect(SplitMode.products.isMoney, isFalse);
      expect(SplitMode.amount.isMoney, isTrue);
      expect(SplitMode.equal.isMoney, isTrue);
    });
  });

  group('resolveSplitServerIds', () {
    final raw = jsonEncode({
      'v': 1,
      'mode': 'PRODUCTS',
      'lines': [
        {'localLineId': 5, 'productId': 1, 'qty': 1},
        {'localLineId': 6, 'orderProductId': 99, 'productId': 2, 'qty': 1},
        {'localLineId': 7, 'productId': 3, 'qty': 0.5},
      ],
    });

    test('fills missing ids, keeps existing ones', () {
      final out = jsonDecode(resolveSplitServerIds(raw, {5: 501, 6: 777})!);
      final lines = out['lines'] as List;
      expect(lines[0]['orderProductId'], 501);
      expect(lines[1]['orderProductId'], 99);
      expect(lines[2].containsKey('orderProductId'), isFalse);
    });

    test('unchanged input when nothing resolves', () {
      expect(resolveSplitServerIds(raw, const {}), same(raw));
      expect(resolveSplitServerIds(null, const {1: 2}), isNull);
    });

    test('splitHasUnresolvedLines', () {
      expect(splitHasUnresolvedLines(raw), isTrue);
      expect(
        splitHasUnresolvedLines(resolveSplitServerIds(raw, {5: 1, 7: 2})),
        isFalse,
      );
      expect(splitHasUnresolvedLines('{"mode":"EQUAL"}'), isFalse);
    });
  });

  group('payment screen money credit', () {
    TicketData ticket(double price) => TicketData(
      items: [
        TicketLine.whole(
          OrderItem(productId: 1, productName: 'Item', finalPrice: price),
        ),
      ],
    );

    test('ticketDueAfterCredit never goes negative', () {
      expect(ticketDueAfterCredit(100, 33.33), 66.67);
      expect(ticketDueAfterCredit(100, 120), 0);
    });

    test('a paid money part means the delivery fee was collected', () {
      expect(deliveryFeeToCollect(15, const []), 15);
      expect(deliveryFeeToCollect(15, const [], moneyPartsPaid: true), 0);
    });

    test('plan amount is capped at what is due', () {
      const plan = MoneySplitPlan(
        groupId: 'g',
        mode: SplitMode.equal,
        parts: 3,
        base: 100,
        paidParts: {1, 2},
      );
      expect(plan.amountFor(100), 33.34);
      expect(plan.amountFor(20), 20);
      expect(plan.afterPaying(3), isNull);

      const custom = MoneySplitPlan(
        groupId: 'g',
        mode: SplitMode.amount,
        parts: 1,
        base: 100,
        customAmount: 40,
      );
      expect(custom.amountFor(100), 40);
    });

    test('any equal part can be picked first, in any order', () {
      const plan = MoneySplitPlan(
        groupId: 'g',
        mode: SplitMode.equal,
        parts: 3,
        base: 100,
      );
      expect(plan.upcoming(100).map((b) => b.part), [1, 2, 3]);
      expect(plan.current(100), (part: 1, amount: 33.33));

      final last = plan.withSelected(2);
      expect(last.current(100), (part: 3, amount: 33.34));

      final next = last.afterPaying(3)!;
      expect(next.paidParts, {3});
      expect(next.selected, 0);
      expect(next.upcoming(66.66), [
        (part: 1, amount: 33.33),
        (part: 2, amount: 33.33),
      ]);

      final middle = next.withSelected(1).afterPaying(2)!;
      expect(middle.upcoming(33.33), [(part: 1, amount: 33.33)]);
      expect(middle.afterPaying(1), isNull);
    });

    test('a custom split can take its rest first', () {
      const custom = MoneySplitPlan(
        groupId: 'g',
        mode: SplitMode.amount,
        parts: 1,
        base: 100,
        customAmount: 40,
      );
      expect(custom.upcoming(100), [
        (part: null, amount: 40.0),
        (part: null, amount: 60.0),
      ]);
      expect(custom.withSelected(1).amountFor(100), 60);
      expect(custom.afterPaying(null), isNull);
    });

    test('an equal split never picks a stray remainder or a bad index', () {
      const plan = MoneySplitPlan(
        groupId: 'g',
        mode: SplitMode.equal,
        parts: 2,
        base: 100,
      );
      // The ticket grew after the split: the extra is not a part.
      expect(plan.upcoming(110).last, (part: null, amount: 10.0));
      expect(plan.canSelect(110, 2), isFalse);
      expect(plan.withSelected(2).current(110).part, 1);
      expect(plan.withSelected(9).current(100).part, 1);
    });

    test('exactAmountDueFor subtracts the credit, and the fee is gone', () {
      final t = ticket(100);
      expect(exactAmountDueFor(t, [t], orderDeliveryFee: 15), 115);
      expect(
        exactAmountDueFor(t, [t], orderDeliveryFee: 15, moneyCredit: 33.33),
        66.67,
      );
      // Fully covered by parts: nothing sensible to pre-fill.
      expect(
        exactAmountDueFor(t, [t], orderDeliveryFee: 0, moneyCredit: 100),
        isNull,
      );
    });
  });
}

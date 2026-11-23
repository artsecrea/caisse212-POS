import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart' show CurrentUser;
import 'package:caisse212/services/permission_service.dart';
import 'package:caisse212/services/refund_service.dart';

/// The two server-side rules that hold no matter what the client does — the
/// over-refund cap and the amount ceiling — plus the permission gate.
///
/// Both money rules are enforced locally on purpose: an offline refund that
/// breaks either is accepted on screen, the cash leaves the drawer, and the
/// rejection only surfaces at sync, hours later, with nobody at the counter.
void main() {
  late AppDatabase db;
  late RefundService refunds;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    refunds = RefundService(db);
  });
  tearDown(() => db.close());

  Future<Order> order({String code = 'ORD-1'}) async {
    final id = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: code,
          status: const Value('COMPLETED'),
        ));
    return (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();
  }

  Future<int> line(int orderId,
          {double qty = 2, double price = 90}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 5,
            quantity: Value(qty),
            unitaryPrice: price,
            state: const Value('PENDING'),
          ));

  group('over-refund cap', () {
    test('refunding more than was sold is refused', () async {
      final o = await order();
      final l = await line(o.id, qty: 2);
      expect(
        () => refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: l, quantity: 3)],
        ),
        throwsA(isA<RefundCapException>()),
      );
    });

    test('a second refund cannot exceed what is left', () async {
      final o = await order();
      final l = await line(o.id, qty: 2);
      await refunds.createRefund(
        order: o,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: l, quantity: 1)],
      );
      // 1 of 2 already given back, so asking for 2 more must fail.
      expect(
        () => refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: l, quantity: 2)],
        ),
        throwsA(isA<RefundCapException>()),
      );
    });

    test('refunding exactly the remainder is allowed', () async {
      final o = await order();
      final l = await line(o.id, qty: 2);
      await refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);
      final second = await refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);
      expect(second.totalAmount, greaterThan(0));
    });

    test('a PENDING (unsynced) refund still counts towards the cap', () async {
      // Counting only synced refunds is how two offline refunds both pass
      // locally and the second is rejected days later.
      final o = await order();
      final l = await line(o.id, qty: 1);
      final first = await refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);
      expect(first.isSynced, isFalse, reason: 'created locally, not yet pushed');

      expect(
        () => refunds.createRefund(
            order: o,
            method: 'CASH',
            lines: [RefundLineDraft(orderProductId: l, quantity: 1)]),
        throwsA(isA<RefundCapException>()),
      );
    });

    test('a weighed line refunds fractionally without a rounding refusal',
        () async {
      final o = await order();
      final l = await line(o.id, qty: 0.75);
      final r = await refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: l, quantity: 0.75)]);
      expect(r.totalAmount, greaterThan(0));
    });

    test('a line from another order is refused', () async {
      final o = await order();
      final other = await order(code: 'ORD-2');
      final foreign = await line(other.id);
      expect(
        () => refunds.createRefund(
            order: o,
            method: 'CASH',
            lines: [RefundLineDraft(orderProductId: foreign, quantity: 1)]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('amount ceiling', () {
    test('more than the line is worth is refused before the drawer opens',
        () async {
      final o = await order();
      final l = await line(o.id, qty: 1, price: 90);
      expect(
        () => refunds.createRefund(
            order: o,
            method: 'CASH',
            lines: [
              RefundLineDraft(orderProductId: l, quantity: 1, amount: 900)
            ]),
        throwsA(isA<RefundAmountException>()),
      );
    });

    test('a LOWER amount is allowed — that is the override case', () async {
      final o = await order();
      final l = await line(o.id, qty: 1, price: 90);
      final r = await refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: l, quantity: 1, amount: 50)]);
      expect(r.totalAmount, 50);
    });

    test('the one-centime rounding slack is honoured', () async {
      final o = await order();
      final l = await line(o.id, qty: 1, price: 90);
      final r = await refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [
            RefundLineDraft(orderProductId: l, quantity: 1, amount: 90.01)
          ]);
      expect(r.totalAmount, closeTo(90.01, 0.001));
    });

    test('a negative amount is refused', () async {
      final o = await order();
      final l = await line(o.id, qty: 1);
      expect(
        () => refunds.createRefund(
            order: o,
            method: 'CASH',
            lines: [
              RefundLineDraft(orderProductId: l, quantity: 1, amount: -10)
            ]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('permission rollout', () {
    CurrentUser user(String perms, {String type = 'cashier'}) => CurrentUser(
        1, 'u', 'p', 'A', 'B', type, null, null, null, perms,
        DateTime(2026), DateTime(2026), null);

    test('a role predating the tokens keeps working', () {
      // V148 seeded these; a role from before it holds none. Enforcing strictly
      // would disable refunds for the whole floor on upgrade.
      final svc = PermissionService(user('pos:orders:view,pos:payments:create'));
      expect(svc.hasRefundPermission(Permissions.refundsCreate), isTrue);
      expect(svc.hasRefundPermission(Permissions.refundsWaste), isTrue);
    });

    test('once ANY refund token is present, the set is enforced', () {
      // A cashier seeded with view+create must not also get waste.
      final svc = PermissionService(
          user('pos:refunds:view,pos:refunds:create'));
      expect(svc.hasRefundPermission(Permissions.refundsCreate), isTrue);
      expect(svc.hasRefundPermission(Permissions.refundsWaste), isFalse);
      expect(svc.hasRefundPermission(Permissions.refundsAmountOverride),
          isFalse);
    });

    test('a supervisor holding all four gets all four', () {
      final svc = PermissionService(user(
          'pos:refunds:view,pos:refunds:create,pos:refunds:waste,'
          'pos:refunds:amount:override'));
      for (final t in const [
        Permissions.refundsView,
        Permissions.refundsCreate,
        Permissions.refundsWaste,
        Permissions.refundsAmountOverride,
      ]) {
        expect(svc.hasRefundPermission(t), isTrue, reason: t);
      }
      // The policy tokens are separate grants: the V148 four don't imply them.
      expect(svc.hasRefundPermission(Permissions.refundsClosedZ), isFalse);
      expect(svc.hasRefundPermission(Permissions.refundsOverride), isFalse);
    });

    test('an admin is never blocked', () {
      final svc = PermissionService(user('', type: 'admin'));
      expect(svc.hasRefundPermission(Permissions.refundsWaste), isTrue);
    });

    test('a pos:* wildcard grants the refund tokens', () {
      final svc = PermissionService(user('pos:*'));
      expect(svc.hasRefundPermission(Permissions.refundsWaste), isTrue);
    });
  });

  group('refund codes', () {
    test('two refunds in the same second get DIFFERENT codes', () async {
      // The flake that exposed this: on Windows DateTime.now().microsecond is
      // 0, so the old "unique" suffix was always "000" and the second refund
      // hit the UNIQUE constraint — after the cash was already handed back.
      final o = await order();
      final l = await line(o.id, qty: 5);
      final a = await refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);
      final b = await refunds.createRefund(
          order: o,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);
      expect(a.code, isNot(b.code));
    });

    test('a burst of refunds all get distinct codes', () async {
      final o = await order();
      final l = await line(o.id, qty: 10);
      final codes = <String>{};
      for (var i = 0; i < 6; i++) {
        final r = await refunds.createRefund(
            order: o,
            method: 'CASH',
            lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);
        codes.add(r.code);
      }
      expect(codes.length, 6, reason: 'every refund needs its own code');
    });

    test('the code carries the terminal name', () async {
      final o = await order();
      final l = await line(o.id, qty: 1);
      final r = await refunds.createRefund(
          order: o,
          method: 'CASH',
          posName: 'CAISSE 1',
          lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);
      expect(r.code, startsWith('RF-CAISSE1-'),
          reason: 'support identifies the terminal from the code');
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/providers/database_providers.dart' show CurrentUser;
import 'package:caisse212/providers/admin_elevation_provider.dart';
import 'package:caisse212/services/permission_service.dart';
import 'package:caisse212/utils/order_permissions.dart';

/// A waiter's order is not the cashier's to rewrite.
///
/// The waiter owns their table, their covers and their attribution, so a
/// cashier silently editing a waiter-raised order corrupts the waiter's own
/// accounting — the kind of thing nobody notices until a shift doesn't
/// reconcile. Two halves get pinned here: what counts as a waiter order, and
/// who is allowed past the rule.
///
/// The discriminator is the one most likely to be got wrong by a future
/// change, which is why it has its own group: `waiterId` is NOT the marker.

CurrentUser _user(String perms, {String type = 'cashier'}) => CurrentUser(
    1, 'u', 'p', 'A', 'B', type, null, null, null, perms,
    DateTime(2026), DateTime(2026), null);

void main() {
  group('what counts as a waiter order', () {
    test('source WAITER does', () {
      expect(isWaiterRaisedOrder('WAITER'), isTrue);
    });

    test('case does not matter — the column is free text from two writers',
        () {
      expect(isWaiterRaisedOrder('waiter'), isTrue);
      expect(isWaiterRaisedOrder('Waiter'), isTrue);
    });

    test('every other source does not', () {
      for (final s in const ['POS', 'KIOSK', 'EXTERNAL']) {
        expect(isWaiterRaisedOrder(s), isFalse, reason: s);
      }
    });

    test('a null source does not — an unsaved cart is nobody else\'s order',
        () {
      expect(isWaiterRaisedOrder(null), isFalse);
    });

    test('a waiter ATTACHED to a cashier order is not a waiter order', () {
      // The rule this whole file exists to protect. A cashier can attach a
      // waiter to an order they rang up themselves (the Waiter action
      // button), so keying off waiterId would lock the cashier out of their
      // OWN order. Only `source` answers who raised it.
      final order = CurrentOrder(
        orderId: 1,
        waiterId: 7,
        waiterName: 'Sam',
        source: 'POS',
      );
      expect(isWaiterRaisedOrder(order.source), isFalse);
      expect(order.waiterId, isNotNull,
          reason: 'the waiter really is attached — that must not matter');
    });
  });

  group('who gets past the rule', () {
    test('a plain cashier does not', () {
      final svc = PermissionService(
          _user('pos:orders:view,pos:orders:item:add,pos:orders:item:modify'));
      expect(svc.hasPermission(Permissions.ordersWaiterUpdate), isFalse);
    });

    test('a cashier holding the explicit grant does', () {
      final svc = PermissionService(_user('pos:orders:waiter:update'));
      expect(svc.hasPermission(Permissions.ordersWaiterUpdate), isTrue);
    });

    test('an admin does, holding no tokens at all', () {
      final svc = PermissionService(_user('', type: 'admin'));
      expect(svc.hasPermission(Permissions.ordersWaiterUpdate), isTrue);
    });

    test('an elevated cashier does — the Admin chip bypasses everything', () {
      final svc = PermissionService(
        _user('pos:orders:view'),
        elevation: const AdminElevation(adminId: 9, adminUsername: 'boss'),
      );
      expect(svc.hasPermission(Permissions.ordersWaiterUpdate), isTrue);
    });

    test('holding every OTHER order permission is still not enough', () {
      // The point of a separate token: "may edit orders" and "may edit
      // someone else's order" are different questions, and a manager granted
      // the full order set must not acquire this one by accident.
      final svc = PermissionService(_user(
          'pos:orders:create,pos:orders:view,pos:orders:update,'
          'pos:orders:delete,pos:orders:cancel,pos:orders:item:add,'
          'pos:orders:item:remove,pos:orders:item:modify,'
          'pos:orders:item:price'));
      expect(svc.hasPermission(Permissions.ordersWaiterUpdate), isFalse);
    });
  });

  group('the source survives the cart model', () {
    test('copyWith carries it through an unrelated change', () {
      final order = CurrentOrder(orderId: 1, source: 'WAITER');
      expect(order.copyWith(numberOfPersons: 4).source, 'WAITER');
    });

    test('a fresh cart has no source', () {
      expect(CurrentOrder().source, isNull);
    });
  });
}

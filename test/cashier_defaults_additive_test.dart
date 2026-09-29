import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/permission_service.dart';

/// Settings → cashier role defaults is the ONLY way the POS itself can grant a
/// permission: `users.permissions` is display-only in Users Management, and
/// the user sync overwrites that column outright every time it runs
/// (`data_sync_service.dart:695` passes `Value(...)`, not `Value.absent()`).
///
/// So the question that matters before relying on it: does ticking a box in
/// the defaults ADD to what a cashier already has, or REPLACE it? These pin
/// that it is strictly additive — a cashier keeps every backend-granted token,
/// including wildcards, and gains the ticked one on top.

void main() {
  CurrentUser user({
    String type = 'cashier',
    String permissions = '',
  }) =>
      CurrentUser(1, 'amina', 'x', 'Amina', 'B', type, null, null, null,
          permissions, DateTime(2026, 9, 18), DateTime(2026, 9, 18), null);

  PermissionService svc(CurrentUser u, List<String> defaults) =>
      PermissionService(u, cashierDefaults: defaults);

  group('a cashier keeps what the backend gave them', () {
    // What the backend actually seeds for a till cashier.
    const backendGranted =
        'pos:orders:create,pos:orders:view,pos:tickets:create,pos:printing';

    test('every existing token still passes after adding a default', () {
      final s = svc(
        user(permissions: backendGranted),
        const ['pos:orders:item:remove', 'pos:orders:waiter:update'],
      );

      for (final token in backendGranted.split(',')) {
        expect(s.hasPermission(token), isTrue,
            reason: '$token was granted by the backend and must survive');
      }
    });

    test('and the newly ticked ones now pass too', () {
      final s = svc(
        user(permissions: backendGranted),
        const ['pos:orders:item:remove', 'pos:orders:waiter:update'],
      );

      expect(s.hasPermission('pos:orders:item:remove'), isTrue);
      expect(s.hasPermission('pos:orders:waiter:update'), isTrue,
          reason: 'the backend does not seed this one — the defaults list is '
              'how the POS grants it without waiting for that');
    });

    test('nothing unticked leaks in', () {
      final s = svc(
        user(permissions: backendGranted),
        const ['pos:orders:item:remove'],
      );

      expect(s.hasPermission('pos:orders:item:modify'), isFalse);
      expect(s.hasPermission('pos:users:delete'), isFalse);
    });

    test('a wildcard the backend granted is untouched', () {
      final s = svc(
        user(permissions: 'pos:tickets:*'),
        const ['pos:orders:item:remove'],
      );

      expect(s.hasPermission('pos:tickets:print'), isTrue,
          reason: 'wildcards are evaluated after the defaults and must still '
              'be reached');
      expect(s.hasPermission('pos:orders:item:remove'), isTrue);
    });

    test('a cashier with no backend tokens at all still gets the defaults', () {
      final s = svc(user(), const ['pos:orders:item:remove']);
      expect(s.hasPermission('pos:orders:item:remove'), isTrue);
    });

    test('an empty defaults list changes nothing', () {
      final s = svc(user(permissions: backendGranted), const []);
      expect(s.hasPermission('pos:orders:create'), isTrue);
      expect(s.hasPermission('pos:orders:item:remove'), isFalse);
    });
  });

  group('the type gate', () {
    test('only type "cashier" picks the defaults up', () {
      final s = svc(
        user(type: 'manager', permissions: 'pos:orders:view'),
        const ['pos:orders:item:remove'],
      );

      expect(s.hasPermission('pos:orders:view'), isTrue,
          reason: 'their own tokens are unaffected by the gate');
      expect(s.hasPermission('pos:orders:item:remove'), isFalse,
          reason: 'this is the trap: the defaults silently cover one role name');
    });

    test('case does not matter', () {
      final s = svc(
        user(type: 'Cashier'),
        const ['pos:orders:item:remove'],
      );
      expect(s.hasPermission('pos:orders:item:remove'), isTrue);
    });

    test('an admin has everything regardless', () {
      final s = svc(user(type: 'admin'), const []);
      expect(s.hasPermission('pos:orders:item:remove'), isTrue);
      expect(s.hasPermission('pos:orders:waiter:update'), isTrue);
    });
  });
}

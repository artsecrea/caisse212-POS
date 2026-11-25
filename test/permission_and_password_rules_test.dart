import 'package:bcrypt/bcrypt.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/models/permission_rules.dart';
import 'package:caisse212/utils/password_check.dart';

/// The permission rule and the password check each used to be written out in
/// three places — PermissionService, CurrentUser and the admin prompt; the
/// login screen, the profile dialog and the admin prompt.
void main() {
  group('roleGrants', () {
    bool grants(String perms, String perm, {String type = 'cashier'}) =>
        roleGrants(userType: type, permissions: perms, permission: perm);

    test('admin holds everything, whatever the case of the type', () {
      expect(grants('', 'pos:z:close', type: 'admin'), isTrue);
      expect(grants('', 'pos:z:close', type: 'ADMIN'), isTrue);
    });

    test('an exact token, with spaces around it', () {
      expect(grants('pos:orders:view, pos:z:view', 'pos:z:view'), isTrue);
      expect(grants('pos:orders:view', 'pos:z:view'), isFalse);
    });

    test('a :* token grants its prefix and nothing beside it', () {
      expect(grants('pos:*', 'pos:z:close'), isTrue);
      expect(grants('pos:orders:*', 'pos:orders:item:price'), isTrue);
      expect(grants('pos:orders:*', 'pos:z:close'), isFalse);
      // "pos:order" is not "pos:orders".
      expect(grants('pos:order:*', 'pos:orders:view'), isFalse);
    });

    test('no tokens grant nothing', () {
      expect(grants('', 'pos:orders:view'), isFalse);
    });
  });

  group('password check', () {
    final hash = BCrypt.hashpw('1234', BCrypt.gensalt(logRounds: 4));
    final other = BCrypt.hashpw('9999', BCrypt.gensalt(logRounds: 4));

    test('the synced hash or the local one', () {
      expect(matchesUserPassword('1234', storedHash: hash), isTrue);
      expect(matchesUserPassword('9999', storedHash: hash, customHash: other),
          isTrue);
      expect(matchesUserPassword('0000', storedHash: hash, customHash: other),
          isFalse);
    });

    test('a missing or malformed hash is a miss, not an error', () {
      expect(bcryptMatches('1234', null), isFalse);
      expect(bcryptMatches('1234', ''), isFalse);
      expect(bcryptMatches('1234', 'not-a-hash'), isFalse);
      expect(matchesUserPassword('9999', storedHash: 'junk', customHash: other),
          isTrue);
    });

    test('the local hash lives under the historic key', () {
      expect(customPasswordKey(7), 'custom_password_7');
    });
  });
}

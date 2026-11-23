import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/utils/admin_auth.dart';
import 'package:caisse212/utils/master_password.dart';
import 'package:caisse212/utils/super_admin_auth.dart';

/// The master password passes every admin-credential gate for any listed user
/// and is flagged on the elevation, so the caller can log it; the user's own
/// password never carries the flag.
void main() {
  late AppDatabase db;
  late SharedPreferences prefs;

  String todayHash() => BCrypt.hashpw(
      superAdminDateKey(DateTime.now()), BCrypt.gensalt(logRounds: 4));

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    for (final (id, name, type) in [(1, 'boss', 'admin'), (2, 'sara', 'cashier')]) {
      await db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: name,
            password: BCrypt.hashpw('own-$name', BCrypt.gensalt(logRounds: 4)),
            firstName: name,
            lastName: '',
            type: type,
            permissions: const Value(''),
          ));
    }
  });
  tearDown(() => db.close());

  test('is the super admin code of today', () {
    expect(masterPasswordAccepted(todayHash()), isTrue);
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    expect(
        masterPasswordAccepted(BCrypt.hashpw(
            superAdminDateKey(yesterday), BCrypt.gensalt(logRounds: 4))),
        isFalse);
  });

  test('admin gate: master password is accepted and flagged', () async {
    final e = await verifyAdminCredentials(db, prefs,
        username: 'boss', password: todayHash());
    expect(e?.adminId, 1);
    expect(e?.viaMasterPassword, isTrue);
  });

  test('admin gate: own password is not flagged', () async {
    final e = await verifyAdminCredentials(db, prefs,
        username: 'boss', password: 'own-boss');
    expect(e?.viaMasterPassword, isFalse);
  });

  test('manager gate: accepted for a listed user, flagged', () async {
    final e = await verifyManagerCredentials(db, prefs,
        username: 'boss', password: todayHash(), permission: 'pos:z:open');
    expect(e?.viaMasterPassword, isTrue);
    // The dialog only lists token holders, and the check agrees.
    expect(
        await verifyManagerCredentials(db, prefs,
            username: 'sara', password: todayHash(), permission: 'pos:z:open'),
        isNull);
  });

  test('wrong password is refused', () async {
    expect(
        await verifyAdminCredentials(db, prefs,
            username: 'boss', password: 'nope'),
        isNull);
  });
}

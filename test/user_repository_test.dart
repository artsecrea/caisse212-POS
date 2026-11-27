import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/services/user_service.dart';
import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/user_provider.dart';

/// User reads and writes the login, admin prompt, profile and top bar made
/// on the database directly.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late UserService repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    repo = container.read(userServiceProvider);
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<int> user(int id, String username, {String type = 'cashier'}) =>
      db.into(db.users).insert(UsersCompanion.insert(
          id: Value(id),
          username: username,
          password: 'x',
          firstName: 'First$id',
          lastName: 'Last$id',
          type: type));

  group('findByUsername', () {
    test('exact, case-sensitive match or null', () async {
      await user(1, 'ali');
      expect((await repo.findByUsername('ali'))?.id, 1);
      expect(await repo.findByUsername('Ali'), isNull);
      expect(await repo.findByUsername('sara'), isNull);
    });

    // Why one method serves both the login (no limit) and the admin prompt
    // (limit 1): a second row with the same username cannot exist, so the
    // limit never changes the answer.
    test('the schema refuses a duplicate username', () async {
      await user(1, 'ali');
      expect(() => user(2, 'ali'), throwsA(isA<SqliteException>()));
    });
  });

  test('setDisplayName writes displayName alone, null clears it', () async {
    await user(1, 'ali');
    await user(2, 'sara');
    final before = (await repo.getUserById(1))!;

    await repo.setDisplayName(1, 'Chef');
    final named = (await repo.getUserById(1))!;
    expect(named.displayName, 'Chef');
    expect(named.updatedAt, before.updatedAt);
    expect((await repo.getUserById(2))!.displayName, isNull);

    await repo.setDisplayName(1, null);
    expect((await repo.getUserById(1))!.displayName, isNull);
  });

  group('reloadCurrentUser', () {
    test('picks up a role change from the table', () async {
      await user(1, 'ali');
      final snapshot = CurrentUser.fromUser((await repo.getUserById(1))!);
      await (db.update(db.users)..where((u) => u.id.equals(1)))
          .write(const UsersCompanion(type: Value('admin')));

      final fresh = await repo.reloadCurrentUser(snapshot);
      expect(fresh.type, 'admin');
    });

    test('a missing row returns the user unchanged', () async {
      await user(1, 'ali');
      final snapshot = CurrentUser.fromUser((await repo.getUserById(1))!);
      await (db.delete(db.users)..where((u) => u.id.equals(1))).go();
      expect(identical(await repo.reloadCurrentUser(snapshot), snapshot),
          isTrue);
    });
  });
}

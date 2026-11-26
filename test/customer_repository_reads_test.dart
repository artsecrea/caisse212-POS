import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/customer_repository.dart';

/// The customer reads the screens used to make on the database directly.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late CustomerRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    repo = container.read(customerRepositoryProvider);
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<int> customer(int id,
          {String first = '', String last = '', String? phone, String? norm}) =>
      db.into(db.customers).insert(CustomersCompanion.insert(
          id: Value(id),
          firstName: Value(first),
          lastName: Value(last),
          phone: Value(phone),
          phoneNormalized: Value(norm)));

  test('watchAll emits every customer and re-emits on a write', () async {
    await customer(1, first: 'Ali');
    final stream = repo.watchAll();
    expect((await stream.first).map((c) => c.id), [1]);
    final later = stream.firstWhere((rows) => rows.length == 2);
    await customer(2, first: 'Sara');
    expect((await later).map((c) => c.id).toSet(), {1, 2});
  });

  test('getAll, getById, getByIds', () async {
    await customer(1, first: 'Ali');
    await customer(2, first: 'Sara');
    await customer(3, first: 'Omar');
    expect((await repo.getAll()).length, 3);
    expect((await repo.getById(2))?.firstName, 'Sara');
    expect(await repo.getById(4), isNull);
    expect((await repo.getByIds({1, 3, 9})).map((c) => c.id).toSet(), {1, 3});
    expect(await repo.getByIds(const <int>[]), isEmpty);
  });

  group('searchByNameOrPhone', () {
    test('names case-insensitively, phone and normalised phone', () async {
      await customer(1, first: 'ALI');
      await customer(2, last: 'Alilou');
      await customer(3, phone: '+212 600', norm: '212600');
      await customer(4, first: 'Sara', phone: '0700', norm: '212700');
      expect((await repo.searchByNameOrPhone('ali')).map((c) => c.id).toSet(),
          {1, 2});
      expect((await repo.searchByNameOrPhone('+212')).map((c) => c.id), [3]);
      expect((await repo.searchByNameOrPhone('2127')).map((c) => c.id), [4]);
    });

    test('at most six suggestions', () async {
      for (var i = 1; i <= 8; i++) {
        await customer(i, first: 'Ali $i');
      }
      expect((await repo.searchByNameOrPhone('ali')).length, 6);
    });
  });

  group('findByPhoneNormalized', () {
    test('row or null', () async {
      await customer(1, first: 'Ali', norm: '212600');
      expect((await repo.findByPhoneNormalized('212600'))?.id, 1);
      expect(await repo.findByPhoneNormalized('212700'), isNull);
    });

    test('duplicates do not throw; one of them comes back', () async {
      await customer(5, first: 'A', norm: '212600');
      await customer(2, first: 'B', norm: '212600');
      final hit = await repo.findByPhoneNormalized('212600');
      expect(hit?.id, anyOf(5, 2));
    });
  });
}

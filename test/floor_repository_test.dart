import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/domain/services/floor_queries.dart';
import 'package:caisse212/providers/floor_repository.dart';

/// Floor and waiter reads moved out of the screens: same rows, same order.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late FloorQueries repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    repo = container.read(floorQueriesProvider);
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<void> tables() async {
    // Inserted out of name order, so insertion order and name order differ.
    for (final (id, name) in [(1, 'T3'), (2, 'T1'), (3, 'T2')]) {
      await db.into(db.areaTables).insert(AreaTablesCompanion.insert(
          id: Value(id), name: name, areaId: const Value(9)));
    }
  }

  test('allTables: every table; ordered by name only when asked', () async {
    await tables();
    final plain = await repo.allTables();
    expect(plain.map((t) => t.id).toSet(), {1, 2, 3});
    final byName = await repo.allTables(orderByName: true);
    expect(byName.map((t) => t.name).toList(), ['T1', 'T2', 'T3']);
  });

  test('tableById: row or null', () async {
    await tables();
    expect((await repo.tableById(2))?.areaId, 9);
    expect(await repo.tableById(4), isNull);
  });

  test('waitersByIds and allWaiters include inactive waiters', () async {
    await db.into(db.waiters).insert(WaitersCompanion.insert(
        id: const Value(1), firstName: 'Ali', lastName: const Value('B')));
    await db.into(db.waiters).insert(WaitersCompanion.insert(
        id: const Value(2), firstName: 'Sara', isActive: const Value(false)));
    await db.into(db.waiters).insert(
        WaitersCompanion.insert(id: const Value(3), firstName: 'Omar'));

    expect((await repo.waitersByIds([2, 3, 4])).map((w) => w.id).toSet(),
        {2, 3});
    expect(await repo.waitersByIds(const <int>[]), isEmpty);
    expect((await repo.allWaiters()).map((w) => w.id).toSet(), {1, 2, 3});
  });
}

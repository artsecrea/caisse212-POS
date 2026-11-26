import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import 'database_providers.dart';

/// One-shot reads of the floor (tables) and the waiters working it, for
/// screens that need rows rather than the live streams in
/// database_providers.dart.
class FloorRepository {
  final AppDatabase _database;

  FloorRepository(this._database);

  Future<List<AreaTable>> allTables({bool orderByName = false}) {
    final query = _database.select(_database.areaTables);
    if (orderByName) query.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.get();
  }

  Future<AreaTable?> tableById(int id) =>
      (_database.select(_database.areaTables)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<List<Waiter>> waitersByIds(Iterable<int> ids) async {
    if (ids.isEmpty) return [];
    return (_database.select(_database.waiters)..where((w) => w.id.isIn(ids)))
        .get();
  }

  /// Inactive waiters included — unlike `waitersProvider` — so a report can
  /// still be filtered on someone who has since left.
  Future<List<Waiter>> allWaiters() => _database.select(_database.waiters).get();
}

final floorRepositoryProvider = Provider<FloorRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return FloorRepository(database);
});

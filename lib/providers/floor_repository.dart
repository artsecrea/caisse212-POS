import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import 'database_providers.dart';
import 'order_provider.dart' show OrderRepository;
import '../domain/services/floor_queries.dart';

/// One-shot reads of the floor (tables) and the waiters working it, for
/// screens that need rows rather than the live streams in
/// database_providers.dart.
class FloorRepository implements FloorQueries {
  final AppDatabase _database;

  FloorRepository(this._database);

  @override
  Future<List<AreaTable>> allTables({bool orderByName = false}) {
    final query = _database.select(_database.areaTables);
    if (orderByName) query.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.get();
  }

  @override
  Future<AreaTable?> tableById(int id) =>
      (_database.select(_database.areaTables)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<List<Waiter>> waitersByIds(Iterable<int> ids) async {
    if (ids.isEmpty) return [];
    return (_database.select(_database.waiters)..where((w) => w.id.isIn(ids)))
        .get();
  }

  /// Inactive waiters included — unlike `waitersProvider` — so a report can
  /// still be filtered on someone who has since left.
  @override
  Future<List<Waiter>> allWaiters() => _database.select(_database.waiters).get();

  /// The areas, as they change.
  @override
  Stream<List<Area>> watchAreas() =>
      (_database.select(_database.areas)..watch()).watch();

  /// The active waiters by first name, as they change.
  @override
  Stream<List<Waiter>> watchActiveWaiters() => (_database.select(_database.waiters)
        ..where((tbl) => tbl.isActive.equals(true))
        ..orderBy([(tbl) => OrderingTerm.asc(tbl.firstName)]))
      .watch();

  /// The active waiters serving [areaId]: those assigned to it, and those
  /// with no area at all, who serve every area. Every active waiter when
  /// [areaId] is null.
  @override
  Future<List<Waiter>> waitersForArea(int? areaId) async {
    final database = _database;

    // Get all active waiters
    final allWaiters = await (database.select(database.waiters)
      ..where((tbl) => tbl.isActive.equals(true)))
      .get();

    if (areaId == null) {
      // No area selected, return all waiters
      return allWaiters;
    }

    // Get all waiter-area assignments
    final allAssignments = await database.select(database.waiterAreas).get();

    // Group assignments by waiter ID
    final waiterAreaMap = <int, List<int>>{};
    for (final assignment in allAssignments) {
      waiterAreaMap.putIfAbsent(assignment.waiterId, () => []).add(assignment.areaId);
    }

    // Filter waiters: include those assigned to this area OR those with no assignments (serve all)
    final result = <Waiter>[];
    for (final waiter in allWaiters) {
      final assignedAreas = waiterAreaMap[waiter.id] ?? [];
      if (assignedAreas.isEmpty || assignedAreas.contains(areaId)) {
        result.add(waiter);
      }
    }

    return result;
  }

  /// The ids of the areas [waiterId] is assigned to.
  @override
  Future<List<int>> areasOfWaiter(int waiterId) async {
    final waiterAreas = await (_database.select(_database.waiterAreas)
      ..where((tbl) => tbl.waiterId.equals(waiterId)))
      .get();
    return waiterAreas.map((wa) => wa.areaId).toList();
  }

  /// [waiterId]'s open orders: `totalOrders`, and `unpaidTotal` still owed
  /// on them.
  @override
  Future<Map<String, dynamic>> waiterStats(int waiterId) async {
    final database = _database;

    // Orders are born COMPLETED, so the status says nothing about whether one
    // is still open. "Unpaid" is the same test the unpaid chip, the resume
    // picker and the close gate use, and the balance is what it compares.
    final orders = await (database.select(database.orders)
          ..where((tbl) => tbl.waiterId.equals(waiterId))
          ..where((_) => OrderRepository.unpaidOrderSql))
        .get();
    final orderIds = [for (final o in orders) o.id];
    double unpaidTotal = 0.0;
    if (orderIds.isNotEmpty) {
      final totals = await OrderRepository(database).getOrderTotals(orderIds);
      final paidTickets = await (database.select(database.tickets)
            ..where((t) =>
                t.orderId.isIn(orderIds) &
                t.isPaid.equals(true) &
                t.isCancelled.equals(false)))
          .get();
      final paidByOrder = <int, double>{};
      for (final t in paidTickets) {
        paidByOrder[t.orderId] = (paidByOrder[t.orderId] ?? 0) + t.amount;
      }
      for (final id in orderIds) {
        unpaidTotal += (totals[id] ?? 0) - (paidByOrder[id] ?? 0);
      }
    }
    final totalOrders = orderIds.length;

    return {
      'totalOrders': totalOrders,
      'unpaidTotal': unpaidTotal,
    };
  }
}

/// The floor and its waiters for the screens. A hub-linked till overrides
/// this one provider; nothing else changes.
final floorQueriesProvider = Provider<FloorQueries>((ref) {
  final database = ref.watch(databaseProvider);
  return FloorRepository(database);
});

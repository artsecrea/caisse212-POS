import '../../data/database/app_database.dart' show Area, AreaTable, Waiter;

/// The floor — areas and tables — and the waiters working it, as the screens
/// read them. An interface because, linked to a hub, a till shows the hub's
/// floor: standalone, it reads its own database (`FloorRepository`).
abstract interface class FloorQueries {
  Future<List<AreaTable>> allTables({bool orderByName = false});

  Future<AreaTable?> tableById(int id);

  Future<List<Waiter>> waitersByIds(Iterable<int> ids);

  /// Inactive waiters included — unlike `waitersProvider` — so a report can
  /// still be filtered on someone who has since left.
  Future<List<Waiter>> allWaiters();

  /// The areas, as they change.
  Stream<List<Area>> watchAreas();

  /// The active waiters by first name, as they change.
  Stream<List<Waiter>> watchActiveWaiters();

  /// The active waiters serving [areaId]: those assigned to it, and those
  /// with no area at all, who serve every area. Every active waiter when
  /// [areaId] is null.
  Future<List<Waiter>> waitersForArea(int? areaId);

  /// The ids of the areas [waiterId] is assigned to.
  Future<List<int>> areasOfWaiter(int waiterId);

  /// [waiterId]'s open orders: `totalOrders`, and `unpaidTotal` still owed
  /// on them.
  Future<Map<String, dynamic>> waiterStats(int waiterId);
}

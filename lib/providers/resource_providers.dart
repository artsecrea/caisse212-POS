import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import 'database_providers.dart';

/// All active bookable resources (staff, rooms, chairs, equipment), reactive
/// to the local Resources table. In the back office's order.
final resourcesProvider = StreamProvider<List<Resource>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.resources)
        ..where((r) => r.isActive.equals(true))
        ..orderBy([
          (r) => OrderingTerm(expression: r.sortOrder),
          (r) => OrderingTerm(expression: r.name),
        ]))
      .watch();
});

/// Quick id → resource lookup for rendering assigned resources on the agenda.
final resourcesByIdProvider = Provider<Map<int, Resource>>((ref) {
  final list = ref.watch(resourcesProvider).valueOrNull ?? const [];
  return {for (final r in list) r.id: r};
});

/// The resource pool eligible for a given product (its `resourceIds` synced into
/// [ProductResources]). Empty ⇒ the service needs no resource.
final eligibleResourcesProvider =
    FutureProvider.family<List<Resource>, int>((ref, productId) async {
  final db = ref.watch(databaseProvider);
  final links = await (db.select(db.productResources)
        ..where((t) => t.productId.equals(productId)))
      .get();
  final ids = links.map((l) => l.resourceId).toList();
  if (ids.isEmpty) return const [];
  return (db.select(db.resources)
        ..where((r) => r.id.isIn(ids) & r.isActive.equals(true))
        ..orderBy([(r) => OrderingTerm(expression: r.name)]))
      .get();
});

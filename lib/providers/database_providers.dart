import 'package:drift/drift.dart' hide Column show OrderingTerm, BooleanExpressionOperators;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/app_database.dart';
import '../data/database/app_database.dart' as db;

// Database Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

// Shared Preferences Provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden');
});

// Current User Provider
final currentUserProvider = StateProvider<db.User?>((ref) => null);

// Network State Provider
final networkStateProvider = StateProvider<bool>((ref) => true);

// Categories Provider
final categoriesProvider = StreamProvider<List<db.Category>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.categories)
    ..where((tbl) => tbl.isActive.equals(true))
    ..orderBy([(tbl) => OrderingTerm(expression: tbl.displayOrder)])
    ..watch()).watch();
});

// Selected Category Provider
final selectedCategoryProvider = StateProvider<int?>((ref) => null);

// Products by Category Provider
final productsByCategoryProvider = StreamProvider.autoDispose.family<List<db.Product>, int?>((ref, categoryId) {
  final database = ref.watch(databaseProvider);

  if (categoryId == null) {
    return (database.select(database.products)
      ..where((tbl) => tbl.isActive.equals(true))
      ..watch()).watch();
  }

  return (database.select(database.products)
    ..where((tbl) => tbl.isActive.equals(true) & tbl.categoryId.equals(categoryId))
    ..watch()).watch();
});

// Area Tables Provider
final areaTablesProvider = StreamProvider<List<db.AreaTable>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.areaTables)..watch()).watch();
});

// Commercials Provider
final commercialsProvider = StreamProvider<List<db.Commercial>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.commercials)..watch()).watch();
});

// Components Provider
final componentsProvider = StreamProvider<List<db.Component>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.components)..watch()).watch();
});

// Component Groups Provider
final componentGroupsProvider = StreamProvider<List<db.ComponentGroup>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.componentGroups)
    ..orderBy([(tbl) => OrderingTerm(expression: tbl.displayOrder)])
    ..watch()).watch();
});

// Product Components by Product ID Provider (components available for a product)
final productComponentsProvider = StreamProvider.autoDispose.family<List<db.Component>, int>((ref, productId) async* {
  final database = ref.watch(databaseProvider);

  // Get product-component relationships
  final productComponents = await (database.select(database.productComponents)
    ..where((tbl) => tbl.productId.equals(productId))).get();

  if (productComponents.isEmpty) {
    yield [];
    return;
  }

  // Get the actual components
  final componentIds = productComponents.map((pc) => pc.componentId).toList();
  final components = await (database.select(database.components)
    ..where((tbl) => tbl.id.isIn(componentIds))).get();

  yield components;
});


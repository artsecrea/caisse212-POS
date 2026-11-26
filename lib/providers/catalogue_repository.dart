import 'package:drift/drift.dart' hide Component;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import 'database_providers.dart';

/// Reads of the local catalogue (products, variants, components, categories)
/// for screens that need a row rather than the scoped, ordered streams in
/// database_providers.dart.
class CatalogueRepository {
  final AppDatabase _database;

  CatalogueRepository(this._database);

  /// Every one is returned, not just the first: a reference (SKU) on one
  /// product can equal another product's barcode, and the scanner prefers the
  /// exact barcode hit.
  Future<List<Product>> findActiveByBarcodeOrReference(String code) =>
      (_database.select(_database.products)
            ..where((tbl) => tbl.barcode.equals(code) | tbl.reference.equals(code))
            ..where((tbl) => tbl.isActive.equals(true)))
          .get();

  Future<Product?> productById(int id) => (_database.select(_database.products)
        ..where((tbl) => tbl.id.equals(id)))
      .getSingleOrNull();

  Future<ProductVariant?> variantById(int id) =>
      (_database.select(_database.productVariants)
            ..where((tbl) => tbl.id.equals(id)))
          .getSingleOrNull();

  Future<Component?> componentById(int id) =>
      (_database.select(_database.components)
            ..where((tbl) => tbl.id.equals(id)))
          .getSingleOrNull();

  Future<List<Product>> productsByIds(Iterable<int> ids) async {
    if (ids.isEmpty) return [];
    return (_database.select(_database.products)
          ..where((tbl) => tbl.id.isIn(ids)))
        .get();
  }

  /// Inactive products included: callers filter for themselves.
  Future<List<Product>> allProducts() =>
      _database.select(_database.products).get();

  /// Every category, inactive and out-of-scope ones included — unlike
  /// `categoriesProvider`, which only serves the grid.
  Future<Map<int, String>> categoryNamesById() async {
    final cats = await _database.select(_database.categories).get();
    return {for (final c in cats) c.id: c.name};
  }

  /// Writes `isAvailable` alone, not `updatedAt`, exactly as the grid's
  /// available/unavailable switch always has.
  Future<void> setProductAvailability(int productId, bool isAvailable) async {
    await (_database.update(_database.products)
          ..where((tbl) => tbl.id.equals(productId)))
        .write(ProductsCompanion(isAvailable: Value(isAvailable)));
  }
}

final catalogueRepositoryProvider = Provider<CatalogueRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return CatalogueRepository(database);
});

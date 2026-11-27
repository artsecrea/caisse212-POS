import 'package:drift/drift.dart' hide Component;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/models/component_rules.dart' show ComponentGroupRule;
import '../utils/pos_log.dart';
import 'database_providers.dart';
import '../domain/services/catalogue_service.dart';

/// Reads of the local catalogue (products, variants, components, categories)
/// for screens that need a row rather than the scoped, ordered streams in
/// database_providers.dart.
class CatalogueRepository implements CatalogueService {
  final AppDatabase _database;

  CatalogueRepository(this._database);

  /// Every one is returned, not just the first: a reference (SKU) on one
  /// product can equal another product's barcode, and the scanner prefers the
  /// exact barcode hit.
  @override
  Future<List<Product>> findActiveByBarcodeOrReference(String code) =>
      (_database.select(_database.products)
            ..where((tbl) => tbl.barcode.equals(code) | tbl.reference.equals(code))
            ..where((tbl) => tbl.isActive.equals(true)))
          .get();

  @override
  Future<Product?> productById(int id) => (_database.select(_database.products)
        ..where((tbl) => tbl.id.equals(id)))
      .getSingleOrNull();

  @override
  Future<ProductVariant?> variantById(int id) =>
      (_database.select(_database.productVariants)
            ..where((tbl) => tbl.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<Component?> componentById(int id) =>
      (_database.select(_database.components)
            ..where((tbl) => tbl.id.equals(id)))
          .getSingleOrNull();

  @override
  Future<List<Product>> productsByIds(Iterable<int> ids) async {
    if (ids.isEmpty) return [];
    return (_database.select(_database.products)
          ..where((tbl) => tbl.id.isIn(ids)))
        .get();
  }

  /// Inactive products included: callers filter for themselves.
  @override
  Future<List<Product>> allProducts() =>
      _database.select(_database.products).get();

  /// Every category, inactive and out-of-scope ones included — unlike
  /// `categoriesProvider`, which only serves the grid.
  @override
  Future<Map<int, String>> categoryNamesById() async {
    final cats = await _database.select(_database.categories).get();
    return {for (final c in cats) c.id: c.name};
  }

  /// Writes `isAvailable` alone, not `updatedAt`, exactly as the grid's
  /// available/unavailable switch always has.
  @override
  Future<void> setProductAvailability(int productId, bool isAvailable) async {
    await (_database.update(_database.products)
          ..where((tbl) => tbl.id.equals(productId)))
        .write(ProductsCompanion(isAvailable: Value(isAvailable)));
  }

  /// The order-tag catalogue, in the back office's order, as it changes.
  @override
  Stream<List<OrderTag>> watchOrderTags() =>
      (_database.select(_database.orderTags)
            ..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.label),
            ]))
          .watch();

  /// The active categories in display order, as they change.
  @override
  Stream<List<Category>> watchActiveCategories() =>
      (_database.select(_database.categories)
            ..where((tbl) => tbl.isActive.equals(true))
            ..orderBy([(tbl) => OrderingTerm(expression: tbl.displayOrder)])
            ..watch())
          .watch();

  /// The active products — of [categoryId], or every one when null — as
  /// they change.
  @override
  Stream<List<Product>> watchActiveProducts({int? categoryId}) {
    if (categoryId == null) {
      return (_database.select(_database.products)
            ..where((tbl) => tbl.isActive.equals(true))
            ..watch())
          .watch();
    }
    return (_database.select(_database.products)
          ..where((tbl) =>
              tbl.isActive.equals(true) & tbl.categoryId.equals(categoryId))
          ..watch())
        .watch();
  }

  /// The commercials, as they change.
  @override
  Stream<List<Commercial>> watchCommercials() =>
      (_database.select(_database.commercials)..watch()).watch();

  /// The component groups in display order, as they change.
  @override
  Stream<List<ComponentGroup>> watchComponentGroups() =>
      (_database.select(_database.componentGroups)
            ..orderBy([(tbl) => OrderingTerm(expression: tbl.displayOrder)])
            ..watch())
          .watch();

  /// The components [productId] offers, each with that product's
  /// constraints on it: `component`, `isRequired`, `minQuantity`,
  /// `maxQuantity`, `defaultPrice`, `defaultQuantity`, `chargeOnRemoval`.
  @override
  Stream<List<Map<String, dynamic>>> productComponentsOf(int productId) async* {
    final database = _database;

    // Get product-component relationships with constraints
    final productComponents = await (database.select(database.productComponents)
      ..where((tbl) => tbl.productId.equals(productId))).get();

    posLog(productComponents.toString());


    if (productComponents.isEmpty) {
      yield [];
      return;
    }

    // Get the actual components with their constraints. 86'd components are
    // left out of ordering entirely — the row stays for history, but nobody can
    // add one to a ticket.
    final componentIds = productComponents.map((pc) => pc.componentId).toList();
    final components = await (database.select(database.components)
      ..where((tbl) => tbl.id.isIn(componentIds))
      ..where((tbl) => tbl.isActive.equals(true))
      ..orderBy([
        (tbl) => OrderingTerm(expression: tbl.displayOrder),
        (tbl) => OrderingTerm(expression: tbl.name),
      ])).get();

    // Combine component data with relationship constraints
    final result = components.map((component) {
      final productComponent = productComponents.firstWhere(
        (pc) => pc.componentId == component.id,
      );

      return {
        'component': component,
        'isRequired': productComponent.isRequired,
        'minQuantity': productComponent.minQuantity,
        'maxQuantity': productComponent.maxQuantity,
        // The resolved price: this link's override, or the component's own.
        // Everything downstream — pricing, the free allowance, removal charges —
        // reads this one number, so the precedence lives in exactly one place.
        'defaultPrice': productComponent.defaultPrice ?? component.price,
        'defaultQuantity': productComponent.defaultQuantity,
        'chargeOnRemoval': productComponent.chargeOnRemoval,
      };
    }).toList();

    yield result;
  }

  /// The component-group rules in force for [productId] — see
  /// [loadComponentGroupRules].
  @override
  Future<Map<int?, ComponentGroupRule>> componentGroupRulesOf(int productId) =>
      loadComponentGroupRules(_database, productId);

  /// [productId]'s active variants, each with its attribute values:
  /// `variant`, `attributeValues`.
  @override
  Future<List<Map<String, dynamic>>> variantsOf(int productId) async {
    final database = _database;

    // Get all variants for this product
    final variants = await (database.select(database.productVariants)
      ..where((tbl) => tbl.productId.equals(productId))
      ..where((tbl) => tbl.isActive.equals(true))).get();

    if (variants.isEmpty) {
      return [];
    }

    // Get all attribute values for these variants
    final variantIds = variants.map((v) => v.id).toList();
    final attributeValues = await (database.select(database.variantAttributeValues)
      ..where((tbl) => tbl.variantId.isIn(variantIds))).get();

    // Group attribute values by variant
    final result = variants.map((variant) {
      final variantAttrs = attributeValues
          .where((av) => av.variantId == variant.id)
          .toList();

      return {
        'variant': variant,
        'attributeValues': variantAttrs,
      };
    }).toList();

    return result;
  }

  /// The attributes [productId]'s active variants vary on, each with its
  /// possible values: `attributeId`, `attributeName`, `values`.
  @override
  Future<List<Map<String, dynamic>>> attributesOf(int productId) async {
    final database = _database;

    // Get all variants for this product
    final variants = await (database.select(database.productVariants)
      ..where((tbl) => tbl.productId.equals(productId))
      ..where((tbl) => tbl.isActive.equals(true))).get();

    if (variants.isEmpty) {
      return [];
    }

    // Get all attribute values for these variants
    final variantIds = variants.map((v) => v.id).toList();
    final attributeValues = await (database.select(database.variantAttributeValues)
      ..where((tbl) => tbl.variantId.isIn(variantIds))).get();

    // Group by attributeId to get unique attributes with their possible values
    final attributesMap = <int, Map<String, dynamic>>{};

    for (final av in attributeValues) {
      if (!attributesMap.containsKey(av.attributeId)) {
        attributesMap[av.attributeId] = {
          'attributeId': av.attributeId,
          'attributeName': av.attributeName ?? 'Attribute ${av.attributeId}',
          'values': <Map<String, dynamic>>[],
        };
      }

      // Add value if not already present
      final values = attributesMap[av.attributeId]!['values'] as List<Map<String, dynamic>>;
      final exists = values.any((v) => v['valueId'] == av.valueId);
      if (!exists) {
        values.add({
          'valueId': av.valueId,
          'value': av.value ?? 'Value ${av.valueId}',
        });
      }
    }

    return attributesMap.values.toList();
  }
}

/// The catalogue for the screens. A hub-linked till overrides this one
/// provider; nothing else changes.
final catalogueServiceProvider = Provider<CatalogueService>((ref) {
  final database = ref.watch(databaseProvider);
  return CatalogueRepository(database);
});

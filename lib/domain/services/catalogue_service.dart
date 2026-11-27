import '../../data/database/app_database.dart'
    show
        Category,
        Commercial,
        Component,
        ComponentGroup,
        OrderTag,
        Product,
        ProductVariant;
import '../models/component_rules.dart' show ComponentGroupRule;

/// The catalogue as the screens use it: products, variants, components and
/// their groups and rules, categories, order tags, commercials, and the
/// grid's availability switch. An interface because, linked to a hub, a till
/// serves the hub's catalogue: standalone, it reads its own synced copy
/// (`CatalogueRepository`).
abstract interface class CatalogueService {
  /// Every one is returned, not just the first: a reference (SKU) on one
  /// product can equal another product's barcode, and the scanner prefers the
  /// exact barcode hit.
  Future<List<Product>> findActiveByBarcodeOrReference(String code);

  Future<Product?> productById(int id);

  Future<ProductVariant?> variantById(int id);

  Future<Component?> componentById(int id);

  Future<List<Product>> productsByIds(Iterable<int> ids);

  /// Inactive products included: callers filter for themselves.
  Future<List<Product>> allProducts();

  /// Every category, inactive and out-of-scope ones included — unlike
  /// `categoriesProvider`, which only serves the grid.
  Future<Map<int, String>> categoryNamesById();

  /// Writes `isAvailable` alone, not `updatedAt`, exactly as the grid's
  /// available/unavailable switch always has.
  Future<void> setProductAvailability(int productId, bool isAvailable);

  /// The order-tag catalogue, in the back office's order, as it changes.
  Stream<List<OrderTag>> watchOrderTags();

  /// The active categories in display order, as they change.
  Stream<List<Category>> watchActiveCategories();

  /// The active products — of [categoryId], or every one when null — as
  /// they change.
  Stream<List<Product>> watchActiveProducts({int? categoryId});

  /// The commercials, as they change.
  Stream<List<Commercial>> watchCommercials();

  /// The component groups in display order, as they change.
  Stream<List<ComponentGroup>> watchComponentGroups();

  /// The components [productId] offers, each with that product's
  /// constraints on it: `component`, `isRequired`, `minQuantity`,
  /// `maxQuantity`, `defaultPrice`, `defaultQuantity`, `chargeOnRemoval`.
  Stream<List<Map<String, dynamic>>> productComponentsOf(int productId);

  /// The component-group rules in force for [productId] — see
  /// [loadComponentGroupRules].
  Future<Map<int?, ComponentGroupRule>> componentGroupRulesOf(int productId);

  /// [productId]'s active variants, each with its attribute values:
  /// `variant`, `attributeValues`.
  Future<List<Map<String, dynamic>>> variantsOf(int productId);

  /// The attributes [productId]'s active variants vary on, each with its
  /// possible values: `attributeId`, `attributeName`, `values`.
  Future<List<Map<String, dynamic>>> attributesOf(int productId);
}

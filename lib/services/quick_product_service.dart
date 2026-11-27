import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import '../domain/models/quick_product.dart';
import 'api_service.dart';
import 'data_sync_service.dart';
import '../domain/services/quick_product_service.dart';

/// Outcome of a till-side product creation.
/// Create a product from the till: name, barcode, price, category. Nothing else.
///
/// The server owns every other field — TVA, stock behaviour, images, active
/// flags — and stamps tenant and business from the terminal header. It also
/// enforces the subscription's product cap, which is precisely why this cannot
/// be a local insert that syncs later: the till would happily create a product
/// the plan does not allow and only discover it much later.
class LocalQuickProductService implements QuickProductService {
  final ApiService _api;
  final AppDatabase _db;
  final DataSyncService _sync;

  LocalQuickProductService(this._api, this._db, this._sync);

  /// Create (or find, by barcode) and persist locally.
  ///
  /// Throws [PosCatalogException] — 403 when the role lacks `pos:catalog`, or a
  /// plan-limit message meant to be shown verbatim.
  @override
  Future<QuickCreateResult> create({
    required String name,
    required double price,
    String? barcode,
    int? categoryId,
    String? newCategoryName,
  }) async {
    final payload = await _api.createPosProduct(
      name: name,
      price: price,
      barcode: barcode,
      categoryId: categoryId,
      categoryName: newCategoryName,
    );

    final productJson = payload['product'];
    if (productJson is! Map) {
      throw PosCatalogException(
          'The server did not return a product for "$name".');
    }

    // Category first: the product row references it, and a grid that renders
    // before the category exists shows the item under a blank heading.
    final categoryJson = payload['category'];
    if (categoryJson is Map) {
      await _sync.persistServerCategory(Map<String, dynamic>.from(categoryJson));
    }

    // Written through the SAME path as a catalogue sync, so the row is
    // identical to what the next full refresh would produce.
    await _sync
        .persistServerProduct(Map<String, dynamic>.from(productJson));

    final id = (productJson['id'] as num?)?.toInt();
    if (id == null) {
      throw PosCatalogException('The server returned a product with no id.');
    }
    final row = await (_db.select(_db.products)
          ..where((p) => p.id.equals(id))
          ..limit(1))
        .getSingleOrNull();
    if (row == null) {
      throw PosCatalogException(
          'The product was created but could not be read back locally.');
    }

    return QuickCreateResult(
      product: row,
      // `created:false` means the barcode already existed. Both branches are a
      // successful selection as far as the till is concerned.
      created: payload['created'] as bool? ?? true,
    );
  }

  /// Categories offered in the picker — local rows, so this works offline even
  /// though creating does not.
  @override
  Future<List<Category>> localCategories() =>
      (_db.select(_db.categories)..orderBy([(c) => OrderingTerm.asc(c.name)]))
          .get();
}

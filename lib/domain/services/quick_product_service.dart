import '../../data/database/app_database.dart' show Category;
import '../models/quick_product.dart';

/// Creating a product from the till: name, barcode, price, category. An
/// interface because the product is created by the back office: standalone,
/// this till asks the cloud (`LocalQuickProductService`); linked to a hub,
/// the hub will.
abstract interface class QuickProductService {
  /// Create (or find, by barcode) and persist locally.
  ///
  /// Throws [PosCatalogException] — 403 when the role lacks `pos:catalog`, or a
  /// plan-limit message meant to be shown verbatim.
  Future<QuickCreateResult> create({
    required String name,
    required double price,
    String? barcode,
    int? categoryId,
    String? newCategoryName,
  });

  /// Categories offered in the picker — local rows, so this works offline even
  /// though creating does not.
  Future<List<Category>> localCategories();
}

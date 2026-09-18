import 'package:drift/drift.dart';

/// The pool of resources eligible for a time-managed product (service) — mirrors
/// [ProductStations]. Populated from the server's `PosProductResponse.resourceIds`.
/// A product with no rows here needs no resource (`requiresResource == false`).
class ProductResources extends Table {
  IntColumn get productId => integer()();
  IntColumn get resourceId => integer()();

  @override
  Set<Column> get primaryKey => {productId, resourceId};
}

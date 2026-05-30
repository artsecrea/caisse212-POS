import 'package:drift/drift.dart';

/// Extra stations a product belongs to, in addition to its primary
/// `Products.stationId`. A product's effective station set is
/// `{stationId} ∪ {rows here}`, so single-station products need no rows here
/// and keep working exactly as before (backward compatible).
class ProductStations extends Table {
  IntColumn get productId => integer()();
  IntColumn get stationId => integer()();

  @override
  Set<Column> get primaryKey => {productId, stationId};
}

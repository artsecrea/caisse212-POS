import 'package:drift/drift.dart';

/// A sellable unit of a product beyond its base unit — the `units[]` array on
/// `GET /pos/products` (e.g. a "box" of 6 at a bundle price).
///
/// `price` here is display/precompute only: the server re-converts the sold
/// quantity to the base unit itself at stock-deduction time, driven by the
/// `saleUomId` the order line carries. A line with no `saleUomId` is the base
/// unit at 1:1.
class ProductUnits extends Table {
  IntColumn get productId => integer()();

  /// Backend UOM id — this is what an order line sends as `saleUomId`.
  IntColumn get uomId => integer()();

  /// Abbreviation shown on the line ("box", "kg").
  TextColumn get unitName => text()();

  /// How many base units one of these is worth. Drives the local stock and
  /// price maths so the POS agrees with the server's conversion.
  RealColumn get factor => real().withDefault(const Constant(1.0))();

  /// Price for one whole unit at this UOM.
  RealColumn get price => real().withDefault(const Constant(0.0))();

  @override
  Set<Column> get primaryKey => {productId, uomId};
}

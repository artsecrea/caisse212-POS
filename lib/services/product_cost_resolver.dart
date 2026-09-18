import 'package:drift/drift.dart';

import '../data/database/app_database.dart';

/// Resolves the per-unit cost to stamp on an order line.
///
/// One place, because the rule is stamped at every point an order line is
/// created — the POS cart, the payment screen, the LAN waiter/kiosk endpoints,
/// and the external-order queue — and a copy of it that drifted would quietly
/// produce different margins depending on where the order came from.
///
/// The rule: a variant's own cost wins when the line sold a variant (a large
/// size can cost more to make than the base product), else the product's cost,
/// else `null`. Never 0.0 as a stand-in for unknown — zero reads as "free to
/// make", i.e. a 100% margin, on any report downstream.
class ProductCostResolver {
  final AppDatabase _db;

  /// Per-instance memo. Line creation runs in loops over a basket that usually
  /// repeats the same few products, and the catalogue cannot change mid-basket.
  final Map<String, double?> _memo = {};

  ProductCostResolver(this._db);

  Future<double?> resolve({required int productId, int? variantId}) async {
    final key = '$productId/${variantId ?? ''}';
    if (_memo.containsKey(key)) return _memo[key];

    double? cost;
    if (variantId != null) {
      final v = await (_db.select(_db.productVariants)
            ..where((t) => t.id.equals(variantId))
            ..limit(1))
          .getSingleOrNull();
      cost = v?.cost;
    }
    if (cost == null) {
      final p = await (_db.select(_db.products)
            ..where((t) => t.id.equals(productId))
            ..limit(1))
          .getSingleOrNull();
      cost = p?.cost;
    }

    _memo[key] = cost;
    return cost;
  }

  /// Convenience for the drift companions at the call sites.
  Future<Value<double?>> resolveValue(
          {required int productId, int? variantId}) async =>
      Value(await resolve(productId: productId, variantId: variantId));
}

import '../data/database/app_database.dart';
import '../domain/models/external_order_models.dart';

/// What a single platform line resolved to locally.
class ResolvedLine {
  final int productId;
  final int? variantId;

  /// Which strategy produced it — logged, and shown when nothing matched.
  final String via;

  const ResolvedLine({
    required this.productId,
    this.variantId,
    required this.via,
  });

  bool get isResolved => productId > 0;
}

/// Resolves platform order lines to local products **automatically**, with no
/// mapping screen and no operator step.
///
/// There is no manual mapping on the till by design: the cashier confirms an
/// order that arrived seconds ago, and asking them to link a Glovo item id to a
/// product mid-service is not a workable ask. Everything here runs off data the
/// terminal already holds.
///
/// Four strategies, in order of trust:
///
/// 1. **The server already resolved it.** `productId > 0` on the line — nothing
///    to do, and never second-guessed.
/// 2. **Glovo ids we minted ourselves.** A menu exported from our side uses
///    `p{productId}` for items and `a{productId}-{componentId}` for addons, so
///    the id *is* the answer; no lookup, works offline, cannot go stale.
/// 3. **The mappings snapshot** pulled from `/pos/mappings` and cached locally,
///    keyed `(provider, externalId)`. This is what covers a menu built on the
///    platform's own dashboard, where the ids are opaque.
/// 4. **SKU match on `products.reference`.** Kooul sends our SKU as the external
///    id, so a product with its `reference` filled in self-matches. Last because
///    a reference is free text and two products can carry the same one; an
///    ambiguous match is refused rather than guessed.
///
/// Strategies 2 and 4 need no server round trip at all, which is what makes the
/// flow work on a terminal that has been offline since the last catalogue sync.
class ExternalItemResolver {
  final AppDatabase _db;

  ExternalItemResolver(this._db);

  /// `p42` → 42. Anything else → null.
  static int? glovoProductIdFrom(String? externalId) {
    if (externalId == null) return null;
    final m = RegExp(r'^p(\d+)$').firstMatch(externalId.trim());
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// `a42-7` → (productId 42, componentId 7). Anything else → null.
  static ({int productId, int componentId})? glovoAddonIdsFrom(
      String? externalId) {
    if (externalId == null) return null;
    final m = RegExp(r'^a(\d+)-(\d+)$').firstMatch(externalId.trim());
    if (m == null) return null;
    final p = int.tryParse(m.group(1)!);
    final c = int.tryParse(m.group(2)!);
    if (p == null || c == null) return null;
    return (productId: p, componentId: c);
  }

  /// Resolve every line and component of [order], returning a copy with the
  /// local ids filled in wherever a match was found.
  ///
  /// Batched: the catalogue and the mapping cache are read once for the whole
  /// order, not once per line.
  Future<ExternalQueueOrder> resolveOrder(
    ExternalQueueOrder order, {
    required String source,
  }) async {
    final provider = source.toUpperCase();

    // Everything unresolved that we might have to look up.
    final needIds = <String>{};
    for (final line in order.items) {
      if (line.productId <= 0 && line.externalProductId != null) {
        needIds.add(line.externalProductId!);
      }
      for (final c in line.components) {
        if (c.componentId <= 0 && c.externalComponentId != null) {
          needIds.add(c.externalComponentId!);
        }
      }
    }

    final mappings = needIds.isEmpty
        ? <String, IntegrationMapping>{}
        : await _mappingsFor(provider, needIds);
    final byReference =
        needIds.isEmpty ? <String, Product>{} : await _productsByReference(needIds);

    final resolvedItems = <ExternalQueueOrderItem>[];
    for (final line in order.items) {
      final r = _resolveLine(line, mappings, byReference);
      final comps = [
        for (final c in line.components)
          _resolveComponent(c, mappings),
      ];
      resolvedItems.add(line.copyWith(
        productId: r.productId,
        variantId: r.variantId,
        mapped: r.isResolved,
        components: comps,
      ));
    }

    final stillUnmapped = resolvedItems.any((i) => i.productId <= 0) ||
        resolvedItems.any((i) => i.components.any((c) => c.componentId <= 0));

    return order.copyWith(
      items: resolvedItems,
      hasUnmappedItems: stillUnmapped,
    );
  }

  ResolvedLine _resolveLine(
    ExternalQueueOrderItem line,
    Map<String, IntegrationMapping> mappings,
    Map<String, Product> byReference,
  ) {
    // 1. The server got there first.
    if (line.productId > 0) {
      return ResolvedLine(
          productId: line.productId, variantId: line.variantId, via: 'server');
    }

    final ext = line.externalProductId;
    if (ext == null || ext.trim().isEmpty) {
      return const ResolvedLine(productId: 0, via: 'no-external-id');
    }

    // 2. An id we minted when publishing the menu.
    final own = glovoProductIdFrom(ext);
    if (own != null) {
      return ResolvedLine(productId: own, via: 'glovo-id');
    }

    // 3. The cached mapping table.
    final m = mappings[_key(ext)];
    if (m != null && (m.productId ?? 0) > 0) {
      return ResolvedLine(
          productId: m.productId!, variantId: m.variantId, via: 'mapping');
    }

    // 4. Our SKU.
    final p = byReference[_key(ext)];
    if (p != null) {
      return ResolvedLine(productId: p.id, via: 'reference');
    }

    return const ResolvedLine(productId: 0, via: 'unresolved');
  }

  ExternalQueueComponent _resolveComponent(
    ExternalQueueComponent c,
    Map<String, IntegrationMapping> mappings,
  ) {
    if (c.componentId > 0) return c;
    final ext = c.externalComponentId;
    if (ext == null || ext.trim().isEmpty) return c;

    final addon = glovoAddonIdsFrom(ext);
    if (addon != null) {
      return c.copyWith(componentId: addon.componentId, mapped: true);
    }

    final m = mappings[_key(ext)];
    if (m != null && (m.componentId ?? 0) > 0) {
      return c.copyWith(componentId: m.componentId!, mapped: true);
    }
    return c;
  }

  Future<Map<String, IntegrationMapping>> _mappingsFor(
      String provider, Set<String> externalIds) async {
    final rows = await (_db.select(_db.integrationMappings)
          ..where((t) => t.externalId.isIn(externalIds.toList())))
        .get();
    final out = <String, IntegrationMapping>{};
    for (final r in rows) {
      // Provider-scoped, but a row from another provider is still better than
      // nothing when only one exists — platforms do not reuse each other's ids.
      final same = r.provider.toUpperCase() == provider;
      final key = _key(r.externalId);
      if (same || !out.containsKey(key)) out[key] = r;
    }
    return out;
  }

  Future<Map<String, Product>> _productsByReference(
      Set<String> externalIds) async {
    final rows = await (_db.select(_db.products)
          ..where((t) => t.reference.isNotNull()))
        .get();
    final wanted = externalIds.map(_key).toSet();

    final counts = <String, int>{};
    final found = <String, Product>{};
    for (final p in rows) {
      final key = _key(p.reference!);
      if (!wanted.contains(key)) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      found[key] = p;
    }
    // A reference is free text and nothing stops two products sharing one.
    // Refusing an ambiguous match is the only safe answer: silently picking one
    // sells the wrong item.
    counts.forEach((k, n) {
      if (n > 1) found.remove(k);
    });
    return found;
  }

  static String _key(String s) => s.trim().toLowerCase();
}

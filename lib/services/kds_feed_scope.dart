import 'package:drift/drift.dart' hide Component;

import '../data/database/app_database.dart';

/// Order origins a KDS can filter on — the same set the printer rules use
/// (`kAllOrderSources` in printing_service.dart).
const Set<String> kKdsOrderSources = {'POS', 'WAITER', 'KIOSK', 'EXTERNAL'};
const Set<String> kKdsOrderTypes = {'DINE_IN', 'TAKE_AWAY', 'DELIVERY'};

/// `Orders.source` folded onto [kKdsOrderSources]. Null is the till's own
/// legacy default; anything that is not ours or the waiter's or a kiosk's came
/// from an outside platform (DEALUP, WHATSAPP, …).
String normalizeOrderSource(String? raw) {
  final s = (raw ?? '').trim().toUpperCase();
  if (s.isEmpty || s == 'POS') return 'POS';
  if (s == 'WAITER' || s == 'KIOSK') return s;
  return 'EXTERNAL';
}

/// The printer-style options a KDS sends on `GET /orders`, beyond `station`.
///
/// Every option is opt-in and absent means today's behaviour, so an older KDS
/// polling a newer POS sees exactly what it always saw.
class KdsFeedFilter {
  /// `types=DINE_IN,TAKE_AWAY` — null = every type.
  final Set<String>? types;

  /// `sources=POS,WAITER` — null = every source.
  final Set<String>? sources;

  /// `unassigned=1` — also show lines whose product has no station at all,
  /// like the printer's "print unassigned items".
  final bool unassigned;

  /// `linked=1` — an option that IS a product (the drink inside a menu) shows
  /// on that product's station, like the printer's "linked components".
  final bool linked;

  const KdsFeedFilter({
    this.types,
    this.sources,
    this.unassigned = false,
    this.linked = false,
  });

  static Set<String>? _csv(String? raw) {
    if (raw == null) return null;
    final set = raw
        .split(',')
        .map((s) => s.trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    return set.isEmpty ? null : set;
  }

  static bool _flag(String? raw) => raw == '1' || raw == 'true';

  factory KdsFeedFilter.fromQuery(Map<String, String> q) => KdsFeedFilter(
        types: _csv(q['types']),
        sources: _csv(q['sources']),
        unassigned: _flag(q['unassigned']),
        linked: _flag(q['linked']),
      );

  bool allowsOrder(Order o) {
    if (types != null && !types!.contains(o.type.toUpperCase())) return false;
    if (sources != null && !sources!.contains(normalizeOrderSource(o.source))) {
      return false;
    }
    return true;
  }
}

/// componentId → the catalogue product it stands for. A linked variant routes
/// by the product that owns it: stations belong to products, not variants.
Future<Map<int, int>> linkedProductByComponent(
    AppDatabase db, Iterable<Component> components) async {
  final variantIds = {
    for (final c in components)
      if (c.linkedVariantId != null) c.linkedVariantId!,
  };
  final productByVariant = <int, int>{};
  if (variantIds.isNotEmpty) {
    final variants = await (db.select(db.productVariants)
          ..where((t) => t.id.isIn(variantIds)))
        .get();
    for (final v in variants) {
      productByVariant[v.id] = v.productId;
    }
  }
  final out = <int, int>{};
  for (final c in components) {
    final viaVariant =
        c.linkedVariantId == null ? null : productByVariant[c.linkedVariantId!];
    final linked = viaVariant ?? c.linkedProductId;
    if (linked != null) out[c.id] = linked;
  }
  return out;
}

/// productId → every station it routes to (primary + product_stations).
Future<Map<int, Set<int>>> stationIdsByProduct(
    AppDatabase db, Iterable<int> productIds) async {
  final ids = productIds.toSet();
  if (ids.isEmpty) return const {};
  final products =
      await (db.select(db.products)..where((t) => t.id.isIn(ids))).get();
  final extra = await (db.select(db.productStations)
        ..where((t) => t.productId.isIn(ids)))
      .get();
  final out = <int, Set<int>>{
    for (final p in products)
      p.id: {if (p.stationId != null) p.stationId!},
  };
  for (final ps in extra) {
    (out[ps.productId] ??= <int>{}).add(ps.stationId);
  }
  return out;
}

/// Components whose linked product routes to one of [stationIds] — the
/// options a `linked=1` KDS on those stations has to hear about.
Future<Set<int>> linkedComponentIdsForStations(
    AppDatabase db, Set<int> stationIds) async {
  if (stationIds.isEmpty) return const {};
  final comps = await (db.select(db.components)
        ..where((t) => t.linkedProductId.isNotNull() | t.linkedVariantId.isNotNull()))
      .get();
  if (comps.isEmpty) return const {};
  final linked = await linkedProductByComponent(db, comps);
  final stations = await stationIdsByProduct(db, linked.values);
  return {
    for (final e in linked.entries)
      if ((stations[e.value] ?? const <int>{}).any(stationIds.contains)) e.key,
  };
}

/// Synthetic id for a linked line: negative so it can never collide with a
/// real order line, and so the KDS knows not to PUT a state for it.
int linkedLineId(int parentLineId, int index) => -(parentLineId * 100 + index + 1);

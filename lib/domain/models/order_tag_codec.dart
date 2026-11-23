/// Order tags on the wire and in the `orders.tag_ids` column.
library;

/// The server refuses more than this many tags on one order.
const kMaxOrderTags = 10;

/// "1,4" → [1, 4]. Unparseable pieces are dropped; order kept, duplicates not.
List<int> parseTagIds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return const [];
  final out = <int>[];
  for (final p in raw.split(',')) {
    final id = int.tryParse(p.trim());
    if (id != null && !out.contains(id)) out.add(id);
  }
  return out;
}

/// [1, 4] → "1,4"; empty → null (untagged).
String? encodeTagIds(Iterable<int> ids) {
  final list = ids.toSet().toList();
  return list.isEmpty ? null : list.join(',');
}

/// Tag ids out of an order snapshot's `"tags":[{id,label,color}]`.
/// Null when the snapshot says nothing about tags (key absent) — which means
/// "keep what the till has", unlike `[]`, which means "cleared".
List<int>? tagIdsFromSnapshot(Map<String, dynamic> order) {
  if (!order.containsKey('tags')) return null;
  final raw = order['tags'];
  if (raw is! List) return const [];
  final out = <int>[];
  for (final t in raw) {
    final v = t is Map ? t['id'] : t;
    final id = v is int ? v : int.tryParse('${v ?? ''}');
    if (id != null && !out.contains(id)) out.add(id);
  }
  return out;
}

/// "#E53935" / "#E53" → ARGB int, or null for anything else (the caller
/// falls back to a theme color).
int? parseTagColor(String? raw) {
  if (raw == null) return null;
  var h = raw.trim();
  if (!h.startsWith('#')) return null;
  h = h.substring(1);
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : 0xFF000000 | v;
}

/// The order-management tag filter: ANY of [tagIds], or untagged when
/// [untagged]. With neither set, everything matches.
bool orderMatchesTagFilter(List<int> orderTags,
    {required Set<int> tagIds, required bool untagged}) {
  if (tagIds.isEmpty && !untagged) return true;
  if (untagged && orderTags.isEmpty) return true;
  return orderTags.any(tagIds.contains);
}

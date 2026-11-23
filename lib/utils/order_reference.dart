/// Longest reference the server takes (proposed contract, not yet confirmed).
const int kOrderReferenceMaxLength = 100;

/// The take-away / delivery reference as the order push sends it: trimmed,
/// capped, and null when blank — the key is then left out, which the server
/// reads as "don't change".
String? referenceForSync(String? reference) {
  final r = reference?.trim() ?? '';
  if (r.isEmpty) return null;
  return r.length > kOrderReferenceMaxLength
      ? r.substring(0, kOrderReferenceMaxLength)
      : r;
}

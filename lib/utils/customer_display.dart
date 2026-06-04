import '../data/database/app_database.dart' show Customer;

extension CustomerDisplayExt on Customer {
  /// User-facing label for this customer. Resolution order:
  ///   1. "first last" trimmed, if either part is non-empty.
  ///   2. `phone`, if set.
  ///   3. `email`, if set.
  ///   4. "#<id>" as a last resort.
  ///
  /// Names are now optional on the customer table — phone is the canonical
  /// identifier — so every UI that previously read `firstName lastName`
  /// must use this helper to avoid empty / blank labels.
  String get displayLabel {
    final fn = firstName.trim();
    final ln = lastName.trim();
    final full = '$fn $ln'.trim();
    if (full.isNotEmpty) return full;
    final p = phone?.trim();
    if (p != null && p.isNotEmpty) return p;
    final e = email?.trim();
    if (e != null && e.isNotEmpty) return e;
    return '#$id';
  }

  /// First letter used by the CircleAvatar list cells. Falls back to the
  /// first digit/character of the phone or the literal `#` when neither
  /// names nor phone are available.
  String get displayInitial {
    final label = displayLabel;
    if (label.isEmpty) return '#';
    return label.substring(0, 1).toUpperCase();
  }
}

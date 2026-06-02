import '../data/database/app_database.dart' show User;

extension UserDisplayExt on User {
  /// The user-facing label for this user. Resolution order:
  ///   1. [displayName] if non-empty (the cashier's chosen nickname).
  ///   2. "first last" trimmed, if either component is non-empty.
  ///   3. [username] as a last resort.
  ///
  /// Use this everywhere the app surfaces a user's name — login dropdown,
  /// users management table, dashboards, daily summaries, activity log —
  /// so the cashier sees the same label everywhere.
  String get displayLabel {
    final dn = displayName?.trim();
    if (dn != null && dn.isNotEmpty) return dn;
    final fn = firstName.trim();
    final ln = lastName.trim();
    final full = '$fn $ln'.trim();
    if (full.isNotEmpty) return full;
    return username;
  }
}

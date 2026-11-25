import 'package:bcrypt/bcrypt.dart';

/// Where this till keeps a password the user changed locally, as a bcrypt
/// hash in SharedPreferences. The synced DB hash keeps working beside it.
String customPasswordKey(int userId) => 'custom_password_$userId';

/// bcrypt check that reads a missing or malformed hash as "no match".
bool bcryptMatches(String password, String? hash) {
  if (hash == null || hash.isEmpty) return false;
  try {
    return BCrypt.checkpw(password, hash);
  } catch (_) {
    return false;
  }
}

/// The user's synced password, or the one changed on this till.
bool matchesUserPassword(
  String password, {
  required String storedHash,
  String? customHash,
}) =>
    bcryptMatches(password, storedHash) || bcryptMatches(password, customHash);

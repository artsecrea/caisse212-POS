import '../../data/database/app_database.dart' show User;
import '../models/current_user.dart';

/// The till's users as the screens look them up — to sign in, to check an
/// admin's credentials, to name who did what — and the two writes a user
/// makes to their own row. An interface because, linked to a hub, a till
/// asks the hub: standalone, it reads its own synced copy (`UserRepository`).
abstract interface class UserService {
  Future<List<User>> getAllUsers();

  Future<List<User>> getUsersByType(String type);

  Future<User?> getUserById(int id);

  /// `username` is UNIQUE in the schema, so at most one row can match. The
  /// limit is there for the reader, not for the database.
  Future<User?> findByUsername(String username);

  /// Writes `displayName` alone, not `updatedAt`, as the profile dialog
  /// always has. Null falls back to first + last name.
  Future<void> setDisplayName(int userId, String? displayName);

  Future<CurrentUser> reloadCurrentUser(CurrentUser user);

  Future<void> updateLastLogin(int userId);
}

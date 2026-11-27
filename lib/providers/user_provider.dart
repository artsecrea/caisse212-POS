import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import 'database_providers.dart';
import 'database_providers.dart' as providers show reloadCurrentUser;
import '../domain/services/user_service.dart';

class UserRepository implements UserService {
  final AppDatabase _database;

  UserRepository(this._database);

  // Get all users
  @override
  Future<List<User>> getAllUsers() async {
    return await _database.select(_database.users).get();
  }

  // Get users by type. Case-tolerant: the DB may store the user type in any
  // casing ("Admin", "ADMIN", "admin"…) depending on which seed/sync ran,
  // and the rest of the codebase normalises via `.toLowerCase()` — so this
  // method matches that convention with a `LOWER(type) = ?` predicate.
  @override
  Future<List<User>> getUsersByType(String type) async {
    final needle = type.toLowerCase();
    return await (_database.select(_database.users)
          ..where((tbl) => tbl.type.lower().equals(needle)))
        .get();
  }

  // Get user by id
  @override
  Future<User?> getUserById(int id) async {
    return await (_database.select(_database.users)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
  }

  /// `username` is UNIQUE in the schema, so at most one row can match. The
  /// limit is there for the reader, not for the database.
  @override
  Future<User?> findByUsername(String username) async {
    return await (_database.select(_database.users)
          ..where((tbl) => tbl.username.equals(username))
          ..limit(1))
        .getSingleOrNull();
  }

  /// Writes `displayName` alone, not `updatedAt`, as the profile dialog
  /// always has. Null falls back to first + last name.
  @override
  Future<void> setDisplayName(int userId, String? displayName) async {
    await (_database.update(_database.users)
          ..where((tbl) => tbl.id.equals(userId)))
        .write(UsersCompanion(displayName: Value(displayName)));
  }

  @override
  Future<CurrentUser> reloadCurrentUser(CurrentUser user) =>
      providers.reloadCurrentUser(_database, user);

  // Update last login
  @override
  Future<void> updateLastLogin(int userId) async {
    await (_database.update(_database.users)
          ..where((tbl) => tbl.id.equals(userId)))
        .write(
      UsersCompanion(
        lastLogin: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // Get users grouped by type
  Future<Map<String, List<User>>> getUsersGroupedByType() async {
    final users = await getAllUsers();
    final Map<String, List<User>> grouped = {};

    for (final user in users) {
      if (!grouped.containsKey(user.type)) {
        grouped[user.type] = [];
      }
      grouped[user.type]!.add(user);
    }

    return grouped;
  }
}

/// The users for the screens. A hub-linked till overrides this one provider;
/// nothing else changes.
final userServiceProvider = Provider<UserService>((ref) {
  final database = ref.watch(databaseProvider);
  return UserRepository(database);
});


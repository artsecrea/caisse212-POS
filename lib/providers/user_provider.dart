import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../data/database/app_database.dart';
import 'database_providers.dart';

class UserRepository {
  final AppDatabase _database;

  UserRepository(this._database);

  // Get all users
  Future<List<User>> getAllUsers() async {
    return await _database.select(_database.users).get();
  }

  // Get users by type
  Future<List<User>> getUsersByType(String type) async {
    return await (_database.select(_database.users)
          ..where((tbl) => tbl.type.equals(type)))
        .get();
  }

  // Get user by id
  Future<User?> getUserById(int id) async {
    return await (_database.select(_database.users)
          ..where((tbl) => tbl.id.equals(id)))
        .getSingleOrNull();
  }

  // Update last login
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

final userRepositoryProvider = Provider<UserRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return UserRepository(database);
});


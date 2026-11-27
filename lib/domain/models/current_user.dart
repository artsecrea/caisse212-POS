import '../../data/database/app_database.dart' show User;
import 'permission_rules.dart';

/// The signed-in user, as taken from the users table at login.
class CurrentUser {
  final int id;
  final String username;
  final String password;
  final String firstName;
  final String lastName;
  final String? displayName;
  final String type;
  final String? imageUrl;
  final String? accessToken;
  final String? refreshToken;
  final String permissions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  CurrentUser(this.id, this.username, this.password, this.firstName,
      this.lastName, this.type, this.imageUrl, this.accessToken,
      this.refreshToken, this.permissions, this.createdAt, this.updatedAt,
      this.lastLogin, {this.displayName});

  String get effectiveDisplayName {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    return '$firstName $lastName'.trim();
  }

  /// Legal full name (firstName + lastName). Used by activity log entries so
  /// the audit trail keeps the legal identity even when the cashier sets a
  /// nickname via [displayName].
  String get fullName => '$firstName $lastName'.trim();

  static CurrentUser fromUser(User user) {
    return CurrentUser(
        user.id,
        user.username,
        user.password,
        user.firstName,
        user.lastName,
        user.type,
        user.imageUrl,
        user.accessToken,
        user.refreshToken,
        user.permissions ?? "",
        user.createdAt,
        user.updatedAt,
        user.lastLogin,
        displayName: user.displayName,
    );
  }

  /// Whether this user has [perm]. Mirrors PermissionService: admin bypass,
  /// exact match, and prefix wildcards (e.g. "pos:*", "pos:orders:*").
  bool hasPermission(String perm) =>
      roleGrants(userType: type, permissions: permissions, permission: perm);

  CurrentUser copyWith({String? displayName}) {
    return CurrentUser(
      id, username, password, firstName, lastName, type, imageUrl,
      accessToken, refreshToken, permissions, createdAt, updatedAt, lastLogin,
      displayName: displayName ?? this.displayName,
    );
  }
}

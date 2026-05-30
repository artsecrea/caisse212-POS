import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Identity of the admin who authorised a session-level "admin mode" elevation.
/// While this is set on [adminElevationProvider], `PermissionService.hasPermission`
/// returns true for any check — the current user temporarily acts as an admin.
class AdminElevation {
  final int adminId;
  final String adminUsername;
  const AdminElevation({required this.adminId, required this.adminUsername});
}

/// Holds the currently active admin-mode elevation, or null if none.
/// Cleared on logout / login.
final adminElevationProvider = StateProvider<AdminElevation?>((ref) => null);

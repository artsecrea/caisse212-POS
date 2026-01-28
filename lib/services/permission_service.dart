import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/database_providers.dart';

/// Permission Service for checking user permissions
class PermissionService {
  final CurrentUser? currentUser;

  PermissionService(this.currentUser);

  /// Check if user has a specific permission
  bool hasPermission(String permission) {
    if (currentUser == null) return false;

    // Admin users have all permissions
    if (currentUser!.type.toLowerCase() == 'admin') return true;
    return true;

    // Parse user permissions (stored as comma-separated string)
    final userPermissions = currentUser!.permissions.split(',').map((p) => p.trim()).toList();

    // Check for exact match
    if (userPermissions.contains(permission)) return true;

    // Check for wildcard permissions (e.g., "pos:*" grants all pos permissions)
    for (final userPerm in userPermissions) {
      if (userPerm.endsWith(':*')) {
        final prefix = userPerm.substring(0, userPerm.length - 1);
        if (permission.startsWith(prefix)) return true;
      }
    }

    return false;
  }

  /// Check if user has any of the specified permissions
  bool hasAnyPermission(List<String> permissions) {
    return permissions.any((perm) => hasPermission(perm));
  }

  /// Check if user has all of the specified permissions
  bool hasAllPermissions(List<String> permissions) {
    return permissions.every((perm) => hasPermission(perm));
  }
}

/// Permission constants
class Permissions {
  // Manual Discount
  static const String manualDiscount = 'pos:manualDiscount';

  // Printing
  static const String printing = 'pos:printing';

  // Orders
  static const String ordersDelete = 'pos:orders:delete';
  static const String ordersUpdate = 'pos:orders:update';
  static const String ordersCreate = 'pos:orders:create';
  static const String ordersView = 'pos:orders:view';

  // Tickets
  static const String ticketsDelete = 'pos:tickets:delete';
  static const String ticketsCreate = 'pos:tickets:create';
  static const String ticketsView = 'pos:tickets:view';
  static const String ticketsPrint = 'pos:tickets:print';

  // Sessions
  static const String sessionsStart = 'pos:sessions:start';
  static const String sessionsEnd = 'pos:sessions:end';
  static const String sessionsPause = 'pos:sessions:pause';
  static const String sessionsView = 'pos:sessions:view';
  static const String sessionsDelete = 'pos:sessions:delete';

  // Commercials
  static const String commercialSet = 'pos:commercial:set';
  static const String commercialCreate = 'pos:commercial:create';
  static const String commercialView = 'pos:commercial:view';

  // Customers
  static const String customerSet = 'pos:customer:set';
  static const String customerCreate = 'pos:customer:create';
  static const String customerView = 'pos:customer:view';
  static const String customerDelete = 'pos:customer:delete';

  // Devices (Printers, etc.)
  static const String devicesUse = 'pos:devices:use';
  static const String devicesDelete = 'pos:devices:delete';
  static const String devicesUpdate = 'pos:devices:update';
  static const String devicesView = 'pos:devices:view';

  // Tables
  static const String tablesSet = 'pos:tables:set';
  static const String tablesClear = 'pos:tables:clear';

  // Products
  static const String productsView = 'pos:products:view';
  static const String productsModify = 'pos:products:modify';

  // Settings
  static const String settingsView = 'pos:settings:view';
  static const String settingsUpdate = 'pos:settings:update';

  // Reports
  static const String reportsView = 'pos:reports:view';

  // Sync Operations
  static const String syncOrders = 'pos:sync:orders';
  static const String syncTickets = 'pos:sync:tickets';
  static const String syncSessions = 'pos:sync:sessions';
  static const String syncCustomers = 'pos:sync:customers';
  static const String syncAll = 'pos:sync:all';
  static const String viewPendingOperations = 'pos:sync:viewPending';
  static const String managePendingOperations = 'pos:sync:managePending';

  // Wildcard - all permissions
  static const String all = 'pos:*';
}

/// Provider for Permission Service
final permissionServiceProvider = Provider<PermissionService>((ref) {
  final currentUser = ref.watch(currentUserProvider);
  return PermissionService(currentUser);
});


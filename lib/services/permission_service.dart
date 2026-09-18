import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/database_providers.dart';
import '../providers/admin_elevation_provider.dart';
import '../providers/settings_provider.dart';

/// Permission Service for checking user permissions
class PermissionService {
  final CurrentUser? currentUser;

  /// Session-level admin-mode elevation (set by tapping the Admin chip and
  /// authenticating). While non-null, every permission check passes.
  final AdminElevation? elevation;

  /// Permission tokens auto-granted to any user with `type == 'cashier'` —
  /// configured by the admin in Settings → "Cashier role defaults".
  final List<String> cashierDefaults;

  PermissionService(
    this.currentUser, {
    this.elevation,
    this.cashierDefaults = const [],
  });

  /// Check if user has a specific permission
  bool hasPermission(String permission) {
    if (currentUser == null) return false;

    // Session-level admin-mode elevation: bypass everything.
    if (elevation != null) return true;

    // Admin users have all permissions
    if (currentUser!.type.toLowerCase() == 'admin') return true;

    // Parse user permissions (stored as comma-separated string)
    final userPermissions =
        currentUser!.permissions.split(',').map((p) => p.trim()).toList();

    // Check for exact match
    if (userPermissions.contains(permission)) return true;

    // Cashier role defaults (admin-configured auto-grants).
    if (currentUser!.type.toLowerCase() == 'cashier' &&
        cashierDefaults.contains(permission)) {
      return true;
    }

    // Check for wildcard permissions (e.g., "pos:*" grants all pos permissions,
    // "pos:orders:*" grants all order permissions)
    for (final userPerm in userPermissions) {
      if (userPerm.endsWith(':*')) {
        final prefix = userPerm.substring(0, userPerm.length - 1);
        if (permission.startsWith(prefix)) return true;
      }
    }

    return false;
  }

  /// Refund gate that tolerates roles predating the refund permissions.
  ///
  /// `/api/pos/**` has no server-side permission check, so these tokens are only
  /// as real as this client makes them. But terminals did not gate refunds
  /// before, and a role seeded before V148 carries none of them — enforcing
  /// strictly would disable refunds for the whole floor on upgrade.
  ///
  /// So: if the user holds NO `pos:refunds:*` token at all, the tokens have not
  /// been rolled out to them and previous behaviour stands. Once ANY of them is
  /// present the set is live and the specific one is required.
  bool hasRefundPermission(String permission) {
    if (currentUser == null) return false;
    if (elevation != null) return true;
    if (currentUser!.type.toLowerCase() == 'admin') return true;

    final userPermissions =
        currentUser!.permissions.split(',').map((p) => p.trim()).toSet();

    final hasAnyRefundToken = Permissions.refundTokens.any((t) =>
            userPermissions.contains(t)) ||
        userPermissions.any((p) =>
            p.endsWith(':*') && 'pos:refunds:'.startsWith(p.substring(0, p.length - 1)));

    // Not rolled out to this role yet — keep doing what the POS did before.
    if (!hasAnyRefundToken) return true;

    return hasPermission(permission);
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

  // Refunds. Seeded server-side by V148: POS_ADMIN and POS_SUPERVISOR hold all
  // four, POS_CASHIER holds view + create. `waste` and `amount:override` are the
  // two that can hide money or stock, which is why they sit with the supervisor.
  static const String refundsView = 'pos:refunds:view';
  static const String refundsCreate = 'pos:refunds:create';
  static const String refundsWaste = 'pos:refunds:waste';
  static const String refundsAmountOverride = 'pos:refunds:amount:override';

  /// Every refund token, used to detect a role that predates V148.
  static const List<String> refundTokens = [
    refundsView,
    refundsCreate,
    refundsWaste,
    refundsAmountOverride,
  ];

  // Printing
  static const String printing = 'pos:printing';

  // Orders
  static const String ordersDelete = 'pos:orders:delete';
  static const String ordersUpdate = 'pos:orders:update'; // general/lifecycle: status, cancel, transfer, persist
  static const String ordersCreate = 'pos:orders:create';
  static const String ordersView = 'pos:orders:view';
  // Granular item edits on a SAVED order (anti-fraud: remove/modify are manager-level)
  static const String ordersItemAdd = 'pos:orders:item:add';
  static const String ordersItemRemove = 'pos:orders:item:remove';
  static const String ordersItemModify = 'pos:orders:item:modify';
  static const String ordersItemPrice = 'pos:orders:item:price';
  // Cancelling an order (own permission — like delete, it can hide a sale)
  static const String ordersCancel = 'pos:orders:cancel';
  /// Editing an order a WAITER raised (`Orders.source == 'WAITER'`).
  ///
  /// Separate from the item permissions above because it answers a different
  /// question: not "may this user edit orders" but "may this user edit
  /// someone else's order". A waiter owns what they rang up — the table, the
  /// covers, the tip attribution — and a cashier quietly changing it breaks
  /// the waiter's own accounting.
  ///
  /// Admins bypass it (as they bypass everything, see [hasPermission]).
  /// NOTE: like `pos:z:*` and `pos:orders:item:price`, this name is NOT yet
  /// seeded by the backend, so in practice it grants to nobody and the rule
  /// is admin-only until the backend adds it — which is the intended default.
  static const String ordersWaiterUpdate = 'pos:orders:waiter:update';

  // Tickets
  static const String ticketsDelete = 'pos:tickets:delete';
  static const String ticketsCreate = 'pos:tickets:create';
  static const String ticketsUpdate = 'pos:tickets:update';
  static const String ticketsView = 'pos:tickets:view';
  static const String ticketsPrint = 'pos:tickets:print';

  /// Open printer setup without holding [settingsView].
  ///
  /// Printer setup IS settings: it decides what every ticket says, where each
  /// station's food prints, and the business identity on the customer's
  /// receipt. It used to sit behind [devicesView] — held by anyone who can
  /// look at the KDS list — and behind no PIN at all, so a cashier locked out
  /// of Settings could still walk in and re-point the receipt printer.
  ///
  /// Access is now [settingsView] OR this, plus the settings PIN either way.
  /// This name exists for the shop that wants a technician who sets printers
  /// up but has no business in Settings.
  ///
  /// NOTE: like `pos:z:*` and [ordersWaiterUpdate], it is NOT yet seeded by
  /// the backend, so today it grants to nobody and printer setup is
  /// settings-holders plus admins — the intended default.
  static const String printersManage = 'pos:printers:manage';

  /// Sign off a session close that does not balance — see
  /// `AppSettings.requireAdminToCloseUnbalanced`. Held by a shift manager who
  /// is trusted to accept a shortfall without being an admin.
  ///
  /// NOTE: like `pos:z:*`, not yet seeded by the backend, so today the sign-off
  /// is admins only — the intended default.
  static const String sessionsCloseUnbalanced =
      'pos:sessions:close:unbalanced';

  // Sessions
  static const String sessionsStart = 'pos:sessions:start';
  static const String sessionsEnd = 'pos:sessions:end';
  static const String sessionsPause = 'pos:sessions:pause';
  static const String sessionsView = 'pos:sessions:view';
  static const String sessionsDelete = 'pos:sessions:delete';

  // Z (shift) tracking
  static const String zOpen = 'pos:z:open';
  static const String zClose = 'pos:z:close';
  static const String zView = 'pos:z:view';
  static const String zPrint = 'pos:z:print';

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

  // Waiters
  static const String waiterSet = 'pos:waiter:set';
  static const String waiterView = 'pos:waiter:view';

  // Products
  static const String productsView = 'pos:products:view';
  /// Create a product from the till (name/barcode/price/category only).
  /// Everything else about the product stays a back-office decision.
  static const String catalog = 'pos:catalog';
  static const String productsModify = 'pos:products:modify';

  // Settings
  static const String settingsView = 'pos:settings:view';
  static const String settingsUpdate = 'pos:settings:update';

  // Users
  static const String usersView = 'pos:users:view';
  static const String usersCreate = 'pos:users:create';
  static const String usersUpdate = 'pos:users:update';
  static const String usersDelete = 'pos:users:delete';

  // Waiters (extra to set/view)
  static const String waiterCreate = 'pos:waiter:create';
  static const String waiterDelete = 'pos:waiter:delete';

  // Notes
  static const String notesView = 'pos:notes:view';
  static const String notesCreate = 'pos:notes:create';
  static const String notesUpdate = 'pos:notes:update';
  static const String notesDelete = 'pos:notes:delete';

  // Agenda / Planning
  static const String agendaView = 'pos:agenda:view';
  static const String agendaManage = 'pos:agenda:manage';

  // Reports / Dashboard
  static const String reportsView = 'pos:reports:view';

  // Activity logs
  static const String logsView = 'pos:logs:view';

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
  final elevation = ref.watch(adminElevationProvider);
  final cashierDefaults = ref.watch(settingsProvider).cashierDefaultPermissions;
  return PermissionService(
    currentUser,
    elevation: elevation,
    cashierDefaults: cashierDefaults,
  );
});


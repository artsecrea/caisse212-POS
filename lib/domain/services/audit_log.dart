import '../../data/database/app_database.dart' show ActivityLog;

/// The audit trail as the screens write and read it: who signed in, paid,
/// changed a price or elevated, and the logs screen. An interface because,
/// linked to a hub, a till's actions are the hub's to record: standalone, it
/// keeps its own (`ActivityLogService`).
abstract interface class AuditLog {
  /// Render [l10nKey] in the logging language, substitute {0},{1}… with [args],
  /// and insert a log row. Never throws — logging must not break the action.
  Future<void> log(
    String actionType,
    String l10nKey,
    List<Object?> args, {
    int? userId,
    String? username,
  });

  Future<void> logLogin({int? userId, String? username});

  Future<void> logLogout({int? userId, String? username});

  /// Records that a super admin signed in with [username]'s credentials using
  /// the master password.
  Future<void> logMasterPasswordLogin({int? userId, String? username});

  /// Records that a super admin passed an admin prompt in [adminUsername]'s
  /// name using the master password, while [username] was signed in.
  Future<void> logMasterPasswordElevation({
    int? userId,
    String? username,
    required String adminUsername,
  });

  /// Records that [username] upgraded to admin mode using [adminUsername]'s password.
  Future<void> logAdminElevationGranted({
    int? userId,
    String? username,
    required String adminUsername,
  });

  /// Records that [username] exited admin mode.
  Future<void> logAdminElevationRevoked({int? userId, String? username});

  Future<void> logPayment(String amount, String orderCode,
          {int? userId, String? username});

  /// Audit line recording that a cashier overrode the unit price of a line
  /// item. [oldPrice]/[newPrice] are the pre-formatted amounts.
  Future<void> logPriceChanged(
          String productName, String oldPrice, String newPrice,
          {String? orderCode, int? userId, String? username});

  /// Paginated, server-filtered query for the logs screen. Newest first.
  /// [search] matches `phrase` or `username` (case-insensitive). Returns at most
  /// [limit] rows starting from [offset].
  Future<List<ActivityLog>> getLogsPage({
    DateTime? from,
    DateTime? to,
    String? search,
    int limit = 50,
    int offset = 0,
  });

  /// Export the current table contents to a timestamped file on the Desktop.
  /// Returns the number of rows written.
  Future<int> exportNow();
}

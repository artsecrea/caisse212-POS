import 'package:drift/drift.dart';

/// User-action audit log. Each row is a pre-rendered, human-readable phrase
/// (in the configured logging language) plus a timestamp and the actor.
/// Distinct from [OrderLogs], which is reserved for sync delta tracking.
class ActivityLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get timestamp => dateTime().clientDefault(() => DateTime.now())();
  IntColumn get userId => integer().nullable()();
  TextColumn get username => text().nullable()();

  /// Stable, language-independent key for filtering (see [ActivityAction]).
  TextColumn get actionType => text()();

  /// The rendered, localized sentence shown in the logs screen / export.
  TextColumn get phrase => text()();
}

/// Stable action-type keys stored in [ActivityLogs.actionType].
/// These never change with language and are safe to filter on.
class ActivityAction {
  static const String orderCreated = 'ORDER_CREATED';
  static const String orderUpdated = 'ORDER_UPDATED';
  static const String orderConfirmed = 'ORDER_CONFIRMED';
  static const String orderCancelled = 'ORDER_CANCELLED';
  static const String orderStatusChanged = 'ORDER_STATUS_CHANGED';
  static const String orderTransferred = 'ORDER_TRANSFERRED';
  // Cashier overrode the unit price of a line item (anti-fraud audit trail).
  static const String priceChanged = 'PRICE_CHANGED';
  static const String payment = 'PAYMENT';
  static const String login = 'LOGIN';
  static const String logout = 'LOGOUT';
  static const String sessionStart = 'SESSION_START';
  static const String sessionPause = 'SESSION_PAUSE';
  static const String sessionResume = 'SESSION_RESUME';
  static const String sessionEnd = 'SESSION_END';
  // Z (shift) tracking lifecycle.
  static const String zOpened = 'Z_OPENED';
  static const String zClosed = 'Z_CLOSED';
  // Fiscal day close / manager reopen (Z mode day lock).
  static const String zDayClosed = 'Z_DAY_CLOSED';
  static const String zDayReopened = 'Z_DAY_REOPENED';
  // Session-level "admin mode" elevation toggle.
  static const String adminElevationGranted = 'ADMIN_ELEVATION_GRANTED';
  static const String adminElevationRevoked = 'ADMIN_ELEVATION_REVOKED';
  // The master password was used instead of a user's own password.
  static const String masterPasswordUsed = 'MASTER_PASSWORD_USED';
  // Remote command received via SSE from the server.
  static const String posCommand = 'POS_COMMAND';
  // Cashier rang a waiter's phone over the LAN push channel.
  static const String waiterCalled = 'WAITER_CALLED';
}

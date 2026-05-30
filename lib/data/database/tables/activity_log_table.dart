import 'package:drift/drift.dart';

/// User-action audit log. Each row is a pre-rendered, human-readable phrase
/// (in the configured logging language) plus a timestamp and the actor.
/// Distinct from [OrderLogs], which is reserved for sync delta tracking.
class ActivityLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();
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
  static const String payment = 'PAYMENT';
  static const String login = 'LOGIN';
  static const String logout = 'LOGOUT';
  static const String sessionStart = 'SESSION_START';
  static const String sessionPause = 'SESSION_PAUSE';
  static const String sessionResume = 'SESSION_RESUME';
  static const String sessionEnd = 'SESSION_END';
  // Session-level "admin mode" elevation toggle.
  static const String adminElevationGranted = 'ADMIN_ELEVATION_GRANTED';
  static const String adminElevationRevoked = 'ADMIN_ELEVATION_REVOKED';
}

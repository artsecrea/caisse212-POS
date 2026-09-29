import 'package:drift/drift.dart';

/// Outbox for `POST /pos/notify`.
///
/// Every notification is written here BEFORE it is sent, and its row is
/// deleted once the server accepts it. A till offline when a session closes,
/// a discount is given or an order is cancelled keeps the notification and
/// delivers it on the next sync instead of losing it.
class PendingNotifications extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Notification type, e.g. `POS_SESSION_CLOSED`, `POS_DISCOUNT_APPLIED`.
  TextColumn get type => text()();

  /// JSON object of String → String — the `params` of the notify payload.
  TextColumn get params => text()();

  TextColumn get refId => text().nullable()();

  /// Idempotency key, minted once when the row is created: a retry after a
  /// timeout that DID reach the server must not notify twice.
  TextColumn get clientRequestId => text()();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now())();

  /// Refusals by the server (4xx). Network failures do not count: they are
  /// the case the outbox exists for.
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
}

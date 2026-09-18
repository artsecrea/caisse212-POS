import 'package:drift/drift.dart';

/// Last pulled view of the shop's diary, from `GET /pos/agenda`.
///
/// A read-only cache, not a source of truth. Scheduling is online-only, so the
/// server always knows the real diary; this table exists so the agenda screen
/// still renders during an outage instead of showing an empty day. Rows are
/// replaced wholesale for the pulled window on every successful pull,
/// matched by **overlap** so a booking spanning midnight is refreshed by
/// either day it touches.
///
/// It denormalises the product/customer/order labels because an appointment
/// may belong to an order this terminal has never held — pulling the diary
/// must not require the orders behind it to be synced down too.
///
/// `timeStatus` is deliberately **absent**. The server derives it from the
/// clock, so a stored copy is wrong the moment it is written; the UI computes
/// NOT_YET / IN_PROGRESS / DONE from [planStartAt] and [planEndAt] as it
/// paints. See `bookingTimeStatus`.
class AgendaBookings extends Table {
  /// `order_products.id` on the server — the thing `PATCH /schedule` addresses.
  IntColumn get orderProductId => integer()();

  IntColumn get orderId => integer().nullable()();
  TextColumn get orderCode => text().nullable()();
  IntColumn get productId => integer().nullable()();
  TextColumn get productName => text().nullable()();
  TextColumn get customerName => text().nullable()();
  TextColumn get customerPhone => text().nullable()();
  TextColumn get note => text().nullable()();

  DateTimeColumn get planStartAt => dateTime()();
  DateTimeColumn get planEndAt => dateTime()();
  IntColumn get planWaiterId => integer().nullable()();
  TextColumn get planWaiterName => text().nullable()();
  IntColumn get planResourceId => integer().nullable()();
  TextColumn get planResourceName => text().nullable()();

  /// Net line value — price x qty less discounts, no TVA. Money *expected*
  /// on this booking, which is not revenue until the service happens.
  RealColumn get value => real().nullable()();

  TextColumn get planResourceType => text().nullable()();

  /// Kitchen line state (PENDING, PREPARING, …). Stored for display only and
  /// **never** consulted by booking logic: scheduling status is derived from
  /// the plan times alone, and lines of canceled orders never reach us because
  /// the server excludes them.
  TextColumn get state => text().withDefault(const Constant('PENDING'))();

  /// When this row was pulled, so the screen can say how stale it is.
  DateTimeColumn get fetchedAt =>
      dateTime().clientDefault(() => DateTime.now())();

  @override
  Set<Column> get primaryKey => {orderProductId};
}

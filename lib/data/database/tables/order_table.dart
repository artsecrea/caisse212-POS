import 'package:drift/drift.dart';

class Orders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get code => text().unique()();
  TextColumn get status => text().withDefault(const Constant('ONHOLD'))(); // ONHOLD, PENDING, PREPARING, READY, DELIVERED
  TextColumn get type => text().withDefault(const Constant('DINE_IN'))(); // DINE_IN, TAKE_AWAY, DELIVERY
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get coupon => text().nullable()();
  IntColumn get persons => integer().withDefault(const Constant(1))();
  DateTimeColumn get date => dateTime().clientDefault(() => DateTime.now())();
  IntColumn get paymentId => integer().nullable()();
  IntColumn get tableId => integer().nullable()();
  TextColumn get source => text().nullable()(); // Source of the order (table, kiosk, etc.)
  IntColumn get sourceId => integer().nullable()();
  RealColumn get discountPercentage => real().withDefault(const Constant(0.0))(); // Manual discount percentage (0-100)
  // Tip stored separately from the items total. Nullable: an order with no
  // tip is `null`, not 0 (matches backend semantics — `tip: null` in the
  // JSON contract means "no tip recorded", clearing sets it back to null).
  // Goes up to the server via the normal PUT /pos/orders/{code} payload
  // (see `data_sync_service.dart::getOrdersForSync`).
  RealColumn get tip => real().nullable()();
  /// Delivery charge, kept out of the products total exactly like [tip].
  ///
  /// Nullable on purpose, and the two empty-ish values mean different things:
  /// `null` = no delivery fee was ever recorded, `0` = delivery is explicitly
  /// free. Collapsing them would make "free delivery" indistinguishable from
  /// "nobody filled this in", and the server contract draws the same line —
  /// omitting/null on an upsert means "don't change".
  ///
  /// Never rolls into ticket amounts or any product/Z total; it is reported as
  /// its own line (see `DailySummaryService`).
  RealColumn get deliveryFee => real().nullable()();

  /// What the backend says has been collected against this order, and what is
  /// still owed. The server is authoritative: deposits, part payments and
  /// refunds all land there, and a service order is routinely paid across two
  /// visits, so a locally-summed total would drift the moment another till or
  /// the web took money.
  ///
  /// Nullable because an older backend does not send them, and 0.0 would be a
  /// lie — "nothing paid" and "we were not told" have to stay distinguishable.
  RealColumn get amountPaid => real().nullable()();
  RealColumn get balanceDue => real().nullable()();

  /// UNPAID | PARTIAL | PAID | OVERPAID, as sent. Kept as text rather than an
  /// enum so a value this build has not heard of survives a round trip.
  TextColumn get paymentStatus => text().nullable()();
  IntColumn get createdBy => integer().nullable()(); // User who created the order
  IntColumn get takenBy => integer().nullable()(); // User who took the order
  IntColumn get waiterId => integer().nullable()(); // Waiter/server assigned to the order
  IntColumn get clientId => integer().nullable()();
  IntColumn get commercialId => integer().nullable()();
  // Order-level note from the cashier, shown on the KDS board and the kitchen
  // ticket ("allergy: nuts", "serve together"). Goes up to the backend as the
  // contract's `note` field.
  TextColumn get note => text().nullable()();
  // Why the order-level manual discount was given. Used to live in `note`,
  // which meant applying a discount silently overwrote the kitchen note —
  // separate column so the two can coexist.
  TextColumn get discountReason => text().nullable()();
  TextColumn get address => text().nullable()(); // Delivery address (for DELIVERY order type)
  TextColumn get cancellationReason => text().nullable()(); // Reason for cancellation when status is CANCELED
  IntColumn get sessionId => integer().nullable()(); // Cash session this order was created in (for Z-report locking)
  // Delivery-platform fields. `externalOrderId` echoes the id from the queue
  // payload back on every re-sync (the server can backfill it from the queue by
  // code, but echoing keeps the link explicit). `deliveryStatus` is only sent
  // for DELIVERY orders — omitting it means "don't change".
  TextColumn get externalOrderId => text().nullable()();
  /// The code the COURIER reads in their app — Glovo `order_code`, Kooul
  /// `reference`. Distinct from [externalOrderId], which is a machine id and
  /// must never be shown or printed.
  ///
  /// Stored on the order, not just read from the queue, because queue rows
  /// are purged after 7 days and a reprint has to keep working after that.
  TextColumn get externalOrderCode => text().nullable()();
  TextColumn get deliveryStatus => text().nullable()(); // NONE|ACCEPTED|PICKED_UP|DELIVERED…
  TextColumn get courierName => text().nullable()();
  TextColumn get courierPhone => text().nullable()();
  // Set once the platform has been told the order is ready, so the signal is
  // fired at most once per order (the endpoint is idempotent, but this saves
  // a pointless round-trip and lets the UI show the state).
  DateTimeColumn get readySignalAt => dateTime().nullable()();
  DateTimeColumn get zDay => dateTime().nullable()(); // Calendar day the session opened — stays constant even if order crosses midnight
  DateTimeColumn get createdAt => dateTime().clientDefault(() => DateTime.now())();
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))(); // Track if synced to server
}


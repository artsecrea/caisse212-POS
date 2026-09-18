import 'package:drift/drift.dart';

class OrderProducts extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer()();
  IntColumn get productId => integer()();
  IntColumn get variantId => integer().nullable()();
  IntColumn get ticketId => integer().nullable()();
  RealColumn get quantity => real().withDefault(const Constant(1.0))();
  RealColumn get unitaryPrice => real()();
  /// Cost per unit **snapshotted when the line was rung up**, from the
  /// variant's cost when the line sold one, else the product's.
  ///
  /// Deliberately a snapshot and not a live lookup: an order held offline
  /// across a supplier price change must keep the cost that applied at the
  /// sale, or its margin is retroactively rewritten. Nullable because the
  /// catalogue does not always carry a cost, and 0.0 would read as "free".
  RealColumn get cost => real().nullable()();
  RealColumn get unitaryDiscount => real().withDefault(const Constant(0.0))();
  RealColumn get unitaryTva => real().withDefault(const Constant(0.0))();
  RealColumn get manualDiscount => real().withDefault(const Constant(0.0))();
  TextColumn get manualDiscountReason => text().nullable()();
  // Backend `order_products.id`. Learned from a delta pull or an explicit
  // GET /pos/orders/{code}; refunds reference the server's line id, not ours.
  IntColumn get serverId => integer().nullable()();
  // UOM this line's quantity is expressed in (null = base unit 1:1).
  IntColumn get saleUomId => integer().nullable()();
  /// The individual unit sold, for serial-tracked products. Non-null implies
  /// `quantity == 1` — the backend rejects the order otherwise.
  IntColumn get serialId => integer().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('PENDING'))(); // PENDING, PREPARING, COMPLETED, CANCELED (KDS) | PAID (cashier)
  DateTimeColumn get planStartAt => dateTime().nullable()(); // Planned start time
  DateTimeColumn get planEndAt => dateTime().nullable()(); // Planned end time
  IntColumn get planWaiterId => integer().nullable()(); // Assigned waiter for this booking
  IntColumn get planResourceId => integer().nullable()(); // Assigned resource (room/chair/equipment) for this booking
  /// Which course this line belongs to: 1 entrée, 2 plat, 3 dessert.
  ///
  /// Null means the cashier did not say, which is the normal state — the
  /// whole feature is off by default and most shops never turn it on. An
  /// order where every line is null (or where they all share one course)
  /// prints the kitchen ticket exactly as it always did; the sections only
  /// appear when there is genuinely something to separate.
  ///
  /// An integer rather than a name so the sections sort themselves: starters
  /// print above mains whatever language the till is in.
  IntColumn get courseNo => integer().nullable()();

  DateTimeColumn get kdsPrintedAt => dateTime().nullable()(); // When item was sent to kitchen (KDS ticket printed)
  RealColumn get kdsPrintedQuantity => real().withDefault(const Constant(0.0))(); // Quantity already sent to kitchen — enables modifications-only delta printing when qty increases

  /// Quantity of this line already put on a printed ORDER TICKET — the
  /// customer-facing counterpart to [kdsPrintedQuantity].
  ///
  /// Exists because the order ticket had no delta concept at all: every
  /// Continue on an open table reprinted the whole order from the top, so a
  /// table that ordered three more drinks got a fresh full bill each round
  /// instead of a slip for the three drinks. The kitchen never had this
  /// problem because `KdsPrintMode.modificationsOnly` has always been the
  /// default there.
  ///
  /// Deliberately NOT shared with [kdsPrintedQuantity]: the two printers run
  /// on independent rules (a station can be silenced, the order ticket can be
  /// disabled by a print rule), so a line can legitimately have reached the
  /// kitchen but never a customer slip, or the reverse.
  RealColumn get orderTicketPrintedQuantity =>
      real().withDefault(const Constant(0.0))();
  // KDS stage timestamps — stamped the FIRST time the item reaches each state,
  // for LOCAL kitchen analytics (prep time = readyAt − preparingAt, pickup wait
  // = servedAt − readyAt). Nullable: null until/unless it passes that stage.
  DateTimeColumn get preparingAt => dateTime().nullable()(); // → PREPARING
  DateTimeColumn get readyAt => dateTime().nullable()();     // → READY
  DateTimeColumn get servedAt => dateTime().nullable()();    // → DELIVERED/COMPLETED
  DateTimeColumn get zDay => dateTime().nullable()(); // Calendar day the session opened (inherited from parent order)
  DateTimeColumn get updatedAt => dateTime().clientDefault(() => DateTime.now())();
}

import '../../data/database/app_database.dart'
    show Order, OrderProduct, OrderProductComponent, Product, RemovedOrderItem, Ticket;
import '../models/order_models.dart'
    show CurrentOrder, OrderFullDetails, PaginatedOrders;
import '../models/order_read_models.dart';

/// What the screens read about orders. An interface because, linked to a
/// hub, a till shows the hub's orders: standalone, it reads its own database
/// (`OrderRepository`).
abstract interface class OrderQueries {
  /// [orderId]'s row as it changes — with the backend's payment position,
  /// which the server owns: a service order is routinely part-paid across
  /// tills.
  Stream<Order?> watchOrderRow(int orderId);

  /// Which waiter is on each order, keyed by `orders.id`, as it changes.
  Stream<Map<int, int>> watchWaiterIdsByOrder();

  /// Cancellations recorded on [orderId], newest first, as they come.
  Stream<List<RemovedOrderItem>> watchCancellations(int orderId);

  /// [orderId]'s lines as the database holds them, with their product's
  /// name, as they change.
  Stream<List<SavedOrderLine>> watchSavedLines(int orderId);

  Future<CurrentOrder?> getOrderById(int orderId);

  /// The bare `orders` row, for screens that only need its columns and not
  /// the hydrated cart [getOrderById] builds.
  Future<Order?> getOrderRow(int id);

  /// The `orders` row carrying [code] (codes are unique), or null.
  Future<Order?> findOrderRowByCode(String code);

  Future<CurrentOrder?> getOrderByCode(String orderCode);

  Future<CurrentOrder> loadOrderDetails(Order order);

  Future<OrderFullDetails> getOrderFullDetails(int orderId);

  Future<PaginatedOrders> getPaginatedOrdersWithFullDetails({
    required int page,
    required int pageSize,
    String? statusFilter,
    String? typeFilter,
    bool unpaidOnly = false,
    String? searchQuery,
    int? customerId,
    int? cashierId,
    int? tableId,
    int? waiterId,
    int? sessionId,
    // Several sessions at once — the Z close asks about all of its sessions.
    Iterable<int>? sessionIds,
    DateTime? startDate,
    DateTime? endDate,
    String sortColumn = 'createdAt',
    bool sortAscending = false,
    // Order tags: keep orders carrying ANY of [tagIds], plus untagged orders
    // when [untagged]. Both empty/false = no tag filter.
    Set<int> tagIds = const {},
    bool untagged = false,
  });

  Future<List<Order>> getHeldOrders();

  /// Fetches the small ranked list of orders that the cashier can
  /// "resume" from the empty cart panel.
  ///
  /// Inclusion rule = "the cashier might want to pick this back up":
  ///   * [unpaidOrderSql] holds (which also rules out `CANCELED`) — i.e. line items haven't
  ///     been fully covered by paid tickets yet. `ONHOLD` orders pass
  ///     this naturally since they have no tickets.
  ///
  /// Filters are pushed into SQL where they're cheap (`type`, `tableId`)
  /// and applied in memory where they need joins (customer-name match).
  /// [customerQuery] does a case-insensitive substring match on the
  /// concatenated first + last name; an empty / null value means "no
  /// customer filter".
  ///
  /// [search] is the panel's single search box — see [orderMatchesSearch].
  ///
  /// Cap defaults to 50 — the dialog this feeds is meant for "pick the
  /// one you were just working on", not for browsing a long history.
  /// The orders-management screen handles the deep-browse case.
  Future<List<Order>> getUnpaidOrdersForResume({
    String? typeFilter,
    int? tableId,
    String? customerQuery,
    String? search,
    int? cashierId,
    int limit = 50,
  });

  Future<Map<int, double>> getOrderTotals(List<int> orderIds);

  /// Returns the correctly-computed total for each requested order.
  ///
  /// Formula matches [OrderItem.totalPrice] + [CurrentOrder.total]:
  ///   componentTotal = Σ (component.price × component.quantity)
  ///   itemTotal      = (unitaryPrice + componentTotal − manualDiscount) × quantity
  ///   beforeDiscount = Σ itemTotal
  ///   total          = beforeDiscount − (beforeDiscount × discountPct / 100)
  ///
  /// Batched: three queries total (orders, orderProducts,
  /// orderProductComponents) no matter how many ids are passed in.
  /// Empty input or empty order returns 0 for that id.
  ///
  /// Previous version (`_isOrderUnpaid` baseline) summed only
  /// `unitaryPrice × quantity` — dropped every component price, every
  /// manual discount, and the entire order-level discount %, so totals
  /// looked wildly off for any order with paid add-ons (Cheese,
  /// Mushrooms, etc.) or a discount applied.
  /// Per-order "what is in it" summary for pick-lists: total units and a short
  /// product preview.
  ///
  /// Batched like [getOrderTotals] — two queries for the whole list rather than
  /// two per order, because this feeds a dialog that can show dozens of parked
  /// orders at once.
  ///
  /// The preview is capped at [previewLimit] names and reports how many lines it
  /// left out, so a 40-line table renders in the same space as a two-line one.
  Future<Map<int, OrderContentSummary>> getOrderContentSummaries(
    List<int> orderIds, {
    int previewLimit = 3,
  });

  /// Orders created in [from, to). With [userId], only those that user
  /// created or took — either side of the hand-over counts as theirs.
  Future<List<Order>> ordersCreatedBetween(DateTime from, DateTime to,
      {int? userId});

  /// The 100 newest orders a note can be linked to.
  ///
  /// The 'CANCELLED' spelling matches no row — the app writes 'CANCELED' —
  /// so cancelled orders are offered too. Kept as the note dialog always had
  /// it; excluding them would be a deliberate change of its own.
  Future<List<Order>> recentOrdersForNoteLink();

  /// Every line of [orderId], oldest first: a refund line names a real row.
  Future<List<OrderProduct>> linesOfOrder(int orderId);

  /// Every line of [orderIds], unordered.
  Future<List<OrderProduct>> linesForOrders(List<int> orderIds);

  /// The components chosen on [lineIds], unordered.
  Future<List<OrderProductComponent>> componentsOfLines(
      Iterable<int> lineIds);

  /// Each line of [orderId] with its cross-till `lineUid`, keyed by local
  /// row id, so a money split can name its lines on every till.
  Future<Map<int, String?>> lineUidsForOrder(int orderId);

  /// The order's paid split-by-amount parts (AMOUNT/EQUAL tickets that
  /// claim no line) of splits still open, oldest first — money already taken
  /// towards lines still unpaid.
  ///
  /// A split is finished once a ticket names it in `closesGroups`, or a money
  /// ticket of that group claims lines (how a closing part looked before
  /// `closesGroups` existed). Its parts paid for lines that are now settled,
  /// so they are no longer credit — counting them would discount another
  /// ticket of the same order.
  Future<List<Ticket>> moneySplitParts(int orderId);

  /// Find an active product by its MBW / PLU code (string comparison only).
  Future<Product?> findByMbwCode(String plu);
}

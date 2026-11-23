import 'dart:async';
import '../utils/order_reference.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import '../domain/models/order_course.dart';
import '../domain/models/order_models.dart';
import '../domain/models/order_tag_codec.dart';
import '../domain/models/line_payment.dart';
import '../domain/models/split_bill.dart';
import '../domain/models/table_occupancy.dart';
import '../data/database/app_database.dart';
import '../domain/models/order_events.dart';
import '../services/kitchen_timing.dart';
import '../services/line_cancellation.dart';
import '../services/pending_operations_service.dart';
import '../services/data_sync_service.dart';
import '../services/order_log_service.dart';
import '../services/printing_service.dart';
import '../services/activity_log_service.dart';
import '../utils/customer_display.dart';
import '../utils/order_code.dart';
import 'database_providers.dart';
import 'network_provider.dart';
import 'settings_provider.dart';
import '../services/waiter_kitchen_events.dart';
import '../services/product_cost_resolver.dart';
import '../services/z_day_resolver.dart';
import '../services/pos_notifications.dart';

// Current Order State Provider
/// What an order contains, condensed for a pick-list row.
class OrderContentSummary {
  /// Total units, so "3 articles" means three things to hand over.
  final double units;

  /// Distinct lines, which is what the preview is truncated against.
  final int lineCount;

  /// Up to N "2x Tajine" strings.
  final List<String> preview;

  /// How many lines the preview left out. Reported as a number rather than
  /// left to an ellipsis: "+4" tells the waiter how much they cannot see.
  final int hiddenLines;

  const OrderContentSummary({
    this.units = 0,
    this.lineCount = 0,
    this.preview = const [],
    this.hiddenLines = 0,
  });

  bool get isEmpty => lineCount == 0;

  /// Whole counts read "3", weighed ones keep their decimals.
  String get unitsLabel => units == units.roundToDouble()
      ? units.toStringAsFixed(0)
      : units.toStringAsFixed(3);

  String get previewLabel {
    if (preview.isEmpty) return '';
    final joined = preview.join(' · ');
    return hiddenLines > 0 ? '$joined  +$hiddenLines' : joined;
  }
}

class OrderNotifier extends StateNotifier<CurrentOrder> {
  /// Optional so nothing that constructs a bare notifier (tests, throwaway
  /// state) has to care. Present in the app, where it is used to hand a
  /// serial-tracked unit back to stock when its line leaves the basket.
  final Ref? _ref;

  OrderNotifier([this._ref]) : super(CurrentOrder());

  /// Return units to local stock when their line goes away. Fire-and-forget:
  /// the basket must not stall on a DB write, and the next catalogue pull
  /// re-asserts server truth anyway.
  void _releaseSerials(Iterable<OrderItem> gone) {
    final ref = _ref;
    if (ref == null) return;
    final ids = gone
        .where((i) => i.serialId != null)
        .map((i) => i.serialId!)
        .toSet();
    if (ids.isEmpty) return;
    ref.read(serialServiceProvider).releaseAll(ids);
  }

  void addItem(OrderItem item) {
    // Check if trying to add an item that belongs to a paid ticket
    if (item.ticketId != null) {
      throw Exception('Cannot add items from paid tickets');
    }

    // Check for duplicate items (same product, note, and components)
    final existingItemIndex = _findDuplicateItemIndex(item);

    if (existingItemIndex != -1) {
      // Merge with existing item by adding quantities
      final items = List<OrderItem>.from(state.items);
      final existingItem = items[existingItemIndex];

      items[existingItemIndex] = existingItem.copyWith(
        quantity: existingItem.quantity + item.quantity,
      );
      state = state.copyWith(items: items);
    } else {
      // Add as new item
      state = state.copyWith(items: [...state.items, item]);
    }
  }

  /// Adds a weighed (scale) item — always as a distinct line.
  /// quantity=weightKg, unitPrice=pricePerKg for both barcode types.
  void addWeighedItem({
    required int productId,
    required String productName,
    String? imageUrl,
    required double quantity,
    required double unitPrice,
    double weightKg = 0.0,
    double? pricePerKgDisplay,
    String? unitName,
  }) {
    final item = OrderItem(
      productId: productId,
      productName: productName,
      imageUrl: imageUrl,
      finalPrice: unitPrice,
      quantity: quantity,
      isWeighedItem: true,
      weightKg: weightKg,
      pricePerKgDisplay: pricePerKgDisplay,
      unitName: unitName,
    );
    state = state.copyWith(items: [...state.items, item]);
  }

  /// Find the index of a duplicate item in the current order
  /// Returns -1 if no duplicate is found
  /// Items are duplicates if they have:
  /// - Same productId
  /// - Same note (null or matching string)
  /// - Same components (same componentId and quantity for each)
  /// - Not already paid (ticketId is null)
  int _findDuplicateItemIndex(OrderItem newItem) {
    for (int i = 0; i < state.items.length; i++) {
      final existingItem = state.items[i];

      // Skip items that are already paid
      if (existingItem.ticketId != null) {
        continue;
      }

      // A line that is already in the database is closed for merging: the new
      // units go on a line of their own, at the top of the panel.
      //
      // Merging into it instead would bump a saved line's quantity, which
      // reads as "this round added nothing" on the panel while quietly owing
      // the kitchen more food. The cashier then cannot see what they just
      // rang up, and the kitchen ticket for it is a delta on an old line
      // rather than a fresh one. Round-by-round lines are what both of them
      // actually want to read.
      //
      // Only applies to persisted lines — two taps of the same product before
      // Continue still collapse into one "2x" line, which is the behaviour
      // that makes ringing up fast.
      if (existingItem.id != null) {
        continue;
      }

      // Check if product IDs match
      if (existingItem.productId != newItem.productId) {
        continue;
      }

      // A serial line is one specific physical unit, so it can never merge:
      // two units are two different serials, and the backend rejects any serial
      // line with quantity != 1. Without this, adding two iPhones would collapse
      // into one line of quantity 2 and the whole order would 400.
      if (existingItem.isSerialLine || newItem.isSerialLine) {
        continue;
      }

      // A line carrying a manual price override is its own line: merging it
      // into a same-product line priced differently would silently discard the
      // price the cashier just typed.
      if (existingItem.finalPrice != newItem.finalPrice) {
        continue;
      }

      // Check if notes match (both null or same string)
      final notesMatch =
          (existingItem.note == null && newItem.note == null) ||
          (existingItem.note != null &&
              newItem.note != null &&
              existingItem.note == newItem.note);

      if (!notesMatch) {
        continue;
      }

      // Check if components match
      if (!_componentsMatch(existingItem.components, newItem.components)) {
        continue;
      }

      // Found a duplicate
      return i;
    }

    return -1;
  }

  /// Check if two component lists are identical
  /// They match if they have the same components with the same quantities
  bool _componentsMatch(
    List<OrderItemComponent> list1,
    List<OrderItemComponent> list2,
  ) {
    // Different number of components
    if (list1.length != list2.length) {
      return false;
    }

    // Both empty
    if (list1.isEmpty) {
      return true;
    }

    // Sort both lists by componentId for comparison
    final sorted1 = List<OrderItemComponent>.from(list1)
      ..sort((a, b) => a.componentId.compareTo(b.componentId));
    final sorted2 = List<OrderItemComponent>.from(list2)
      ..sort((a, b) => a.componentId.compareTo(b.componentId));

    // Compare each component
    for (int i = 0; i < sorted1.length; i++) {
      if (sorted1[i].componentId != sorted2[i].componentId ||
          sorted1[i].quantity != sorted2[i].quantity) {
        return false;
      }
    }

    return true;
  }

  void removeItem(int index) {
    final items = List<OrderItem>.from(state.items);

    // Don't allow removing items from paid tickets
    if (items[index].ticketId != null) {
      throw Exception('Cannot remove items from paid tickets');
    }

    final removed = items.removeAt(index);
    _releaseSerials([removed]);
    state = state.copyWith(items: items);
  }

  void updateItemQuantity(int index, double quantity) {
    if (quantity <= 0) {
      removeItem(index);
      return;
    }

    final items = List<OrderItem>.from(state.items);
    items[index] = items[index].copyWith(quantity: quantity);
    state = state.copyWith(items: items);
  }

  void updateItem(int index, OrderItem item) {
    final items = List<OrderItem>.from(state.items);

    // Don't allow updating items from paid tickets
    if (items[index].ticketId != null) {
      throw Exception('Cannot update items from paid tickets');
    }

    items[index] = item;
    state = state.copyWith(items: items);
  }

  void setTable(int? tableId, String? tableName) {
    clearOrder();
    state = state.copyWith(tableId: tableId, tableName: tableName);
  }

  // Update table for existing order (used for transfer)
  void updateTable(int? tableId, String? tableName) {
    state = state.copyWith(tableId: tableId, tableName: tableName);
  }

  void clearTable() {
    state = state.copyWith(tableId: null, tableName: null);
  }

  void setCustomer(
    int? customerId,
    String? customerName, {
    String? customerPhone,
  }) {
    state = state.copyWith(
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
    );
  }

  void clearCustomer() {
    state = CurrentOrder(
      orderId: state.orderId,
      tagIds: state.tagIds,
      orderCode: state.orderCode,
      sessionOrderNo: state.sessionOrderNo,
      items: state.items,
      tableId: state.tableId,
      tableName: state.tableName,
      customerId: null,
      customerName: null,
      customerPhone: null,
      commercialId: state.commercialId,
      commercialName: state.commercialName,
      waiterId: state.waiterId,
      waiterName: state.waiterName,
      coupon: state.coupon,
      discountPercentage: state.discountPercentage,
      note: state.note,
      type: state.type,
      numberOfPersons: state.numberOfPersons,
      // These rebuilds drop every field they don't name. Carrying the fee
      // explicitly stops "clear the customer" from silently erasing it.
      deliveryFee: state.deliveryFee,
      reservationCode: state.reservationCode,
    );
  }

  void setCommercial(int? commercialId, String? commercialName) {
    state = state.copyWith(
      commercialId: commercialId,
      commercialName: commercialName,
    );
  }

  void clearCommercial() {
    state = CurrentOrder(
      orderId: state.orderId,
      tagIds: state.tagIds,
      orderCode: state.orderCode,
      sessionOrderNo: state.sessionOrderNo,
      items: state.items,
      tableId: state.tableId,
      tableName: state.tableName,
      customerId: state.customerId,
      customerName: state.customerName,
      commercialId: null,
      commercialName: null,
      waiterId: state.waiterId,
      waiterName: state.waiterName,
      coupon: state.coupon,
      discountPercentage: state.discountPercentage,
      note: state.note,
      type: state.type,
      numberOfPersons: state.numberOfPersons,
      // These rebuilds drop every field they don't name. Carrying the fee
      // explicitly stops "clear the customer" from silently erasing it.
      deliveryFee: state.deliveryFee,
      reservationCode: state.reservationCode,
    );
  }

  void setWaiter(int? waiterId, String? waiterName) {
    state = state.copyWith(waiterId: waiterId, waiterName: waiterName);
  }

  void clearWaiter() {
    state = CurrentOrder(
      orderId: state.orderId,
      tagIds: state.tagIds,
      orderCode: state.orderCode,
      sessionOrderNo: state.sessionOrderNo,
      items: state.items,
      tableId: state.tableId,
      tableName: state.tableName,
      customerId: state.customerId,
      customerName: state.customerName,
      commercialId: state.commercialId,
      commercialName: state.commercialName,
      waiterId: null,
      waiterName: null,
      coupon: state.coupon,
      discountPercentage: state.discountPercentage,
      note: state.note,
      type: state.type,
      numberOfPersons: state.numberOfPersons,
      // These rebuilds drop every field they don't name. Carrying the fee
      // explicitly stops "clear the customer" from silently erasing it.
      deliveryFee: state.deliveryFee,
      reservationCode: state.reservationCode,
    );
  }

  void setDiscountPercentage(double percentage) {
    state = state.copyWith(discountPercentage: percentage);
  }

  /// Order-level kitchen note. `copyWith` treats null as "keep", so clearing
  /// the note has to rebuild the state explicitly.
  /// The order tags on the cart. Saved with the order; for an order already
  /// saved, [OrderRepository.setOrderTags] writes and queues them too.
  void setTagIds(List<int> ids) {
    state = state.copyWith(tagIds: List.unmodifiable(ids));
  }

  void setNote(String? note) {
    final trimmed = (note == null || note.trim().isEmpty) ? null : note.trim();
    state = trimmed == null
        ? CurrentOrder(
            orderId: state.orderId,
            tagIds: state.tagIds,
            orderCode: state.orderCode,
            sessionOrderNo: state.sessionOrderNo,
            items: state.items,
            tableId: state.tableId,
            tableName: state.tableName,
            customerId: state.customerId,
            customerName: state.customerName,
            customerPhone: state.customerPhone,
            commercialId: state.commercialId,
            commercialName: state.commercialName,
            waiterId: state.waiterId,
            waiterName: state.waiterName,
            coupon: state.coupon,
            discountPercentage: state.discountPercentage,
            note: null,
            discountReason: state.discountReason,
            type: state.type,
            deliveryAddress: state.deliveryAddress,
            reference: state.reference,
            numberOfPersons: state.numberOfPersons,
            reservationCode: state.reservationCode,
            tip: state.tip,
            deliveryFee: state.deliveryFee,
          )
        : state.copyWith(note: trimmed);
  }

  void setDiscountReason(String? reason) {
    state = state.copyWith(
      discountReason: (reason == null || reason.trim().isEmpty)
          ? null
          : reason.trim(),
    );
  }

  void setOrderType(String type) {
    // A table needs no pickup reference; leaving one would print it.
    state = type == 'DINE_IN'
        ? state.copyWith(type: type, reference: '')
        : state.copyWith(type: type);
  }

  void setDeliveryAddress(String? address) {
    state = state.copyWith(deliveryAddress: address);
  }

  /// Set the take-away / delivery reference; blank clears it.
  void setReference(String? reference) {
    state = state.copyWith(reference: reference?.trim() ?? '');
  }

  /// Record (or clear) the delivery charge. Passing `null` clears it back to
  /// "no fee recorded"; passing `0` records free delivery, which is a
  /// different, printable fact — see [CurrentOrder.deliveryFee].
  void setDeliveryFee(double? value) {
    state = value == null
        ? state.copyWith(clearDeliveryFee: true)
        : state.copyWith(deliveryFee: value < 0 ? 0.0 : value);
  }

  void setNumberOfPersons(int count) {
    state = state.copyWith(numberOfPersons: count);
  }

  /// Stamps the tip value returned by `PATCH /orders/{id}/tip` onto the
  /// in-memory order. The server is the source of truth; this just keeps
  /// the UI in sync so the tip button label and the payment screen totals
  /// reflect what's saved.
  void setTip(double value) {
    state = state.copyWith(tip: value);
  }

  /// Replace the in-memory order outright with [order]. Used after a save
  /// + reload pass when the caller wants the DB-loaded copy (with
  /// auto-generated ids, etc.) to become the working order.
  void setOrder(CurrentOrder order) {
    state = order;
  }

  void clearOrder() {
    // Cancelling the order frees every unit it was holding.
    _releaseSerials(state.items);
    state = CurrentOrder();
  }

  void loadOrder(CurrentOrder order) {
    state = order;
  }

  void mergeItems(List<OrderItem> newItems) {
    state = state.copyWith(items: [...state.items, ...newItems]);
  }

  void holdOrder() {
    // Save to held orders - will be implemented in repository
  }
}

final orderProvider = StateNotifierProvider<OrderNotifier, CurrentOrder>((ref) {
  return OrderNotifier(ref);
});

// Order Repository
/// Whether [order] answers the resume panel's search box.
///
/// * `#12` or `12` — the per-session order number (exact);
/// * any text — part of the order code, of the take-away / delivery
///   reference, or of the customer's name or phone (case-insensitive).
bool orderMatchesSearch(Order order, String search, {Customer? customer}) {
  final q = search.trim().toLowerCase();
  if (q.isEmpty) return true;
  final number = int.tryParse(q.startsWith('#') ? q.substring(1) : q);
  if (number != null && order.sessionOrderNo == number) return true;
  bool has(String? field) => (field ?? '').toLowerCase().contains(q);
  if (has(order.code) || has(order.reference)) return true;
  if (customer != null) {
    final name = '${customer.firstName} ${customer.lastName}';
    if (has(name) || has(customer.phone)) return true;
  }
  return false;
}

String? _blankToNull(String? s) =>
    (s == null || s.trim().isEmpty) ? null : s.trim();

class OrderRepository {
  final AppDatabase _database;
  final Ref? _ref;
  final _logger = Logger.instance;
  late final OrderLogService _logService;

  // Optional sync service and network status callback for auto-sync
  DataSyncService? _syncService;
  bool Function()? _isOnlineCallback;

  /// Run [work] off the caller's critical path.
  ///
  /// Every auto-sync in this repository is an OPTIMISATION — never the thing
  /// that makes an order durable. By the time any of them runs, the row is
  /// already committed with `isSynced = false`, and
  /// `DataSyncService.getOrdersForSync` / `getTicketsForSync` sweep exactly
  /// that flag on the periodic job (`SyncJobService`, default 5 min) and again
  /// on every reconnect (`network_provider.dart`). Awaiting the push buys no
  /// guarantee the sweep does not already provide; it only makes the cashier
  /// stand at the till through a Dio call configured for a 10s connect and a
  /// 30s receive (`api_service.dart`) before the panel can clear.
  ///
  /// Safe against the sweep racing it: `ApiService.syncSingleOrder` is a PUT
  /// keyed on `order.code` (create-or-update), so pushing the same order twice
  /// is idempotent rather than duplicating it.
  ///
  /// Never call this from inside a `transaction()` — the detached work would
  /// escape the transaction's scope.
  /// Deadline for the "prompt push" the cashier's tap kicks off.
  ///
  /// These pushes are detached, so this is no longer about making the till
  /// responsive — [_detach] already did that. It bounds how long a hanging
  /// server can delay the FALLBACK: `updateOrder` / `updateOrderStatus` only
  /// record a pending-sync operation once the push has failed, and on Dio's
  /// defaults that verdict could take 10s connect + 30s receive. It also stops
  /// pushes stacking up in flight during an outage.
  ///
  /// Abandoning the wait is safe and cannot lose the push: the row is still
  /// `isSynced = false`, and `ApiService.syncSingleOrder` is a PUT keyed on
  /// `order.code`, so the sweep re-pushing it is idempotent — and a request
  /// that lands late still marks the order synced.
  static const Duration _promptPushDeadline = Duration(seconds: 6);

  void _detach(String label, Future<void> Function() work) {
    unawaited(
      work().catchError((Object e) {
        _logger.error('$label failed — the sync sweep will retry: $e');
      }),
    );
  }

  OrderRepository(this._database, [this._ref]) {
    _logService = OrderLogService(_database);
  }

  /// Records a user-action audit entry for the current actor (if available).
  void _audit(
    void Function(ActivityLogService log, int? userId, String? username) action,
  ) {
    final ref = _ref;
    if (ref == null) return;
    try {
      final actor = ref.read(currentUserProvider);
      action(
        ref.read(activityLogServiceProvider),
        actor?.id,
        actor?.effectiveDisplayName,
      );
    } catch (e) {
      _logger.error('Activity log failed: $e');
    }
  }

  /// Set sync service for auto-syncing completed orders
  void setSyncService(
    DataSyncService syncService,
    bool Function() isOnlineCallback,
  ) {
    _syncService = syncService;
    _isOnlineCallback = isOnlineCallback;
  }

  // Event stream for socket service integration
  final StreamController<OrderEvent> _eventController =
      StreamController<OrderEvent>.broadcast();

  /// Stream of order events (insert, update, delete, status changes, etc.)
  Stream<OrderEvent> get events => _eventController.stream;

  /// Dispose the repository and close streams
  void dispose() {
    _eventController.close();
  }

  /// Emit an event to listeners
  void _emitEvent(OrderEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  // Returns z_day from the active session (O(1) state read — no DB hit).
  DateTime _currentZDay() {
    final ref = _ref;
    if (ref != null) return ref.read(currentZDayProvider);
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // Returns z_day derived from a SPECIFIC session (the one the order belongs
  // to), so a saved order's z_day matches its own session rather than merely
  // the currently-open one. Falls back to the session open now, and only then
  // to today — see [ZDayResolver] for why the fallback reads the DB rather
  // than the in-memory session.
  Future<DateTime> _zDayForSessionId(int? sessionId) async =>
      await ZDayResolver(_database).forSessionOrCurrent(sessionId) ??
      _currentZDay();

  /// The order's paid split-by-amount parts (AMOUNT/EQUAL tickets that
  /// claim no line) of splits still open, oldest first — money already taken
  /// towards lines still unpaid.
  ///
  /// A split is finished once a ticket names it in `closesGroups`, or a money
  /// ticket of that group claims lines (how a closing part looked before
  /// `closesGroups` existed). Its parts paid for lines that are now settled,
  /// so they are no longer credit — counting them would discount another
  /// ticket of the same order.
  Future<List<Ticket>> moneySplitParts(int orderId) async {
    final rows =
        await (_database.select(_database.tickets)
              ..where(
                (t) =>
                    t.orderId.equals(orderId) &
                    t.isCancelled.equals(false) &
                    t.isPaid.equals(true) &
                    t.splitDetails.isNotNull(),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.id)]))
            .get();
    if (rows.isEmpty) return const [];
    final lineTicketIds =
        (await (_database.select(_database.orderProducts)..where(
                  (p) => p.orderId.equals(orderId) & p.ticketId.isNotNull(),
                ))
                .get())
            .map((p) => p.ticketId!)
            .toSet();
    final closed = <String>{};
    for (final r in rows) {
      final split = SplitDetails.decode(r.splitDetails);
      if (split == null) continue;
      closed.addAll(split.closesGroups);
      if (split.mode.isMoney && lineTicketIds.contains(r.id)) {
        closed.add(split.groupId);
      }
    }
    return [
      for (final r in rows)
        if (!lineTicketIds.contains(r.id))
          if (SplitDetails.decode(r.splitDetails) case final split?)
            if (split.mode.isMoney &&
                split.closesGroups.isEmpty &&
                !closed.contains(split.groupId))
              r,
    ];
  }

  /// Settle one order fully as cash: insert a CASH ticket covering the
  /// remaining [due], mark every still-unpaid line PAID + attach the ticket
  /// (in one transaction), then move the order to [paidStatus]. Used by the
  /// bulk "pay all unpaid" flow at session close.
  ///
  /// Returns the created ticket's id / number / amount so the caller can print
  /// an optional receipt, or null when nothing was due.
  Future<({int ticketId, String ticketNum, double due})?> settleOrderAsCash(
    int orderId,
    double due, {
    int? sessionId,
    required String paidStatus,

    /// Force the Z-day the ticket is accounted to, overriding the one implied
    /// by [sessionId].
    ///
    /// For the bulk settlement of stale orders, where an admin decides which
    /// day absorbs the cash: the orders' own days, today, or a chosen one.
    /// Left null everywhere else, where the session's own day is right.
    DateTime? zDayOverride,
  }) async {
    if (due <= 0.005) return null;
    // z_day from the order's own session so the ticket lands in the right
    // Z-report even when settled right at close/after midnight.
    final zDay = zDayOverride ?? await _zDayForSessionId(sessionId);

    late final int ticketId;
    late final String ticketNumStr;
    await _database.transaction(() async {
      final existing = await (_database.select(
        _database.tickets,
      )..where((t) => t.orderId.equals(orderId))).get();
      final maxNum = existing.isEmpty
          ? 0
          : existing
                .map((t) => int.tryParse(t.num) ?? 0)
                .reduce((a, b) => a > b ? a : b);
      ticketNumStr = (maxNum + 1).toString().padLeft(4, '0');
      ticketId = await _database
          .into(_database.tickets)
          .insert(
            TicketsCompanion.insert(
              num: ticketNumStr,
              orderId: orderId,
              paymentMethod: 'CASH',
              amount: due,
              sessionId: Value(sessionId),
              zDay: Value(zDay),
              isPaid: const Value(true),
              printCount: const Value(0),
              date: Value(DateTime.now()),
            ),
          );
      // Attach the ticket to every not-yet-paid line; leave already-paid lines
      // (partials) untouched. `state` is the kitchen's and stays as it is.
      await (_database.update(_database.orderProducts)..where(
            (p) =>
                p.orderId.equals(orderId) &
                p.ticketId.isNull() &
                p.state.isNotValue('PAID'),
          ))
          .write(
            OrderProductsCompanion(
              ticketId: Value(ticketId),
              updatedAt: Value(DateTime.now()),
            ),
          );
      if (_ref?.read(settingsProvider).paymentCompletesKitchen ?? false) {
        await completeKitchenForTicket(_database, ticketId);
      }
    });

    // Status change carries its own Z-report guard + logging + isSynced flip.
    await updateOrderStatus(orderId, paidStatus, queueSyncOperation: false);

    // Free the table this order occupied so the floor shows it empty once the
    // order is settled (mirrors the cashier payment-screen flow). Without this,
    // paying orders at session close left their tables stuck showing "busy".
    final settled = await (_database.select(
      _database.orders,
    )..where((t) => t.id.equals(orderId))).getSingleOrNull();
    if (settled?.tableId != null) {
      await clearTableOrder(settled!.tableId!);
    }

    return (ticketId: ticketId, ticketNum: ticketNumStr, due: due);
  }

  /// Guards that [sessionId] points to a currently OPEN (`active`) cash session.
  /// Throws otherwise. This is the single source of truth for the rule "a POS
  /// order must belong to a live session".
  ///
  /// Why this matters: persisting an order with a null / ended / paused session
  /// orphans it — the row is written, but it then vanishes from every
  /// session-scoped view (the Z-report, the resume/unpaid pickers, the waiter
  /// list) and can be swept by the daily data-clear. That's the "my orders just
  /// disappeared" symptom. Every legitimate caller already passes the active
  /// session; this converts a silent data-loss path into a loud, catchable
  /// error the UI surfaces as a snackbar.
  Future<void> _assertActiveSession(int? sessionId) async {
    if (sessionId == null) {
      throw Exception(
        'Cannot save an order without an active cash session. Open a session first.',
      );
    }
    final s = await (_database.select(
      _database.cashSessions,
    )..where((t) => t.id.equals(sessionId))).getSingleOrNull();
    if (s == null) {
      throw Exception(
        'Cannot save an order: cash session #$sessionId no longer exists. Open a session first.',
      );
    }
    if (s.status != 'active') {
      throw Exception(
        'Cannot save an order: the cash session is "${s.status}". Resume or open an active session first.',
      );
    }
  }

  Future<int> saveOrder(
    CurrentOrder order,
    int userId, {
    String status = 'PENDING',
    int? sessionId,
  }) async {
    if (order.orderId != null) {
      throw Exception(
        "Order already has an order code, use updateOrder instead.",
      );
    }

    // Check if order has items
    if (order.items.isEmpty) {
      throw Exception("Cannot save order with no items");
    }

    // Hard guard: never persist an order that isn't tied to an OPEN session.
    // (See [_assertActiveSession].)
    await _assertActiveSession(sessionId);

    _logger.debug(
      'saveOrder: ${order.items.length} items, first item: ${order.items.first.toJson()}',
    );
    // Generate order code — short uppercase alphanumeric (e.g. RGH7IE3H3LR),
    // consistent with the waiter-app path. Uniqueness is checked just below.
    final orderCode = order.orderCode ?? generateOrderCode();

    // check if the order with that code exists
    final existingOrder = await (_database.select(
      _database.orders,
    )..where((tbl) => tbl.code.equals(orderCode))).getSingleOrNull();
    if (existingOrder != null) {
      throw Exception("Order with code $orderCode already exists.");
    }

    // Derive z_day from THIS order's session (the sessionId being saved) so it
    // belongs to the correct Z-report even if created after midnight.
    final zDay = await _zDayForSessionId(sessionId);
    // Held carts stay ONHOLD; everything else enters the kitchen at the
    // configured default KDS state (the live kitchen flow runs on products —
    // the order header itself is born [status], typically COMPLETED).
    final defaultKdsState =
        _ref?.read(settingsProvider).defaultKdsState ?? 'PENDING';
    final itemState = status == 'ONHOLD' ? 'ONHOLD' : defaultKdsState;

    // Order header + products + components are written atomically. Without a
    // transaction an app-kill mid-write could leave an order row with missing
    // or zero products (a half-written order).
    final orderId = await _database.transaction<int>(() async {
      final newOrderId = await _database
          .into(_database.orders)
          .insert(
            OrdersCompanion.insert(
              code: orderCode,
              status: Value(status),
              type: Value(order.type),
              priority: Value(0),
              note: Value(order.note),
              discountReason: Value(order.discountReason),
              // Tags chosen on the basket go up once the order itself has.
              tagIds: Value(encodeTagIds(order.tagIds)),
              tagsSynced: Value(order.tagIds.isEmpty),
              address: Value(order.deliveryAddress),
              reference: Value(_blankToNull(order.reference)),
              reservationCode: Value(order.reservationCode),
              tableId: Value(order.tableId),
              source: Value('POS'),
              sourceId: Value(null),
              discountPercentage: Value(order.discountPercentage),
              // Only persist a tip when the cashier actually entered one — keeps
              // the column null for the "no tip recorded" case, matching the
              // backend's `tip: null` semantic.
              tip: order.tip > 0 ? Value(order.tip) : const Value.absent(),
              // Absent, not Value(null), when no fee was recorded — an explicit 0
              // has to survive as 0 ("free delivery"), so the test is on the
              // nullable field itself and never on `> 0`.
              deliveryFee: order.hasDeliveryFee
                  ? Value(order.deliveryFee)
                  : const Value.absent(),
              createdBy: Value(userId),
              takenBy: Value(userId),
              waiterId: Value(order.waiterId),
              persons: Value(order.numberOfPersons),
              clientId: Value(order.customerId),
              commercialId: Value(order.commercialId),
              sessionId: Value(sessionId),
              sessionOrderNo: Value(
                await _database.nextSessionOrderNo(
                  sessionId,
                  mode:
                      _ref?.read(settingsProvider).orderNumberResetMode ??
                      'session',
                ),
              ),
              zDay: Value(zDay),
              date: Value(DateTime.now()),
              createdAt: Value(DateTime.now()),
              updatedAt: Value(DateTime.now()),
            ),
          );
      final costResolver = ProductCostResolver(_database);
      for (final item in order.items) {
        final orderProductId = await _database
            .into(_database.orderProducts)
            .insert(
              OrderProductsCompanion.insert(
                orderId: newOrderId,
                productId: item.productId,
                variantId: Value(item.variantId),
                quantity: Value(item.quantity),
                unitaryPrice: item.finalPrice,
                // Cost snapshotted at ring-up, so margin is fixed at the sale.
                cost: await costResolver.resolveValue(
                  productId: item.productId,
                  variantId: item.variantId,
                ),
                serialId: Value(item.serialId),
                unitaryDiscount: Value(item.discount),
                manualDiscount: Value(item.manualDiscount),
                note: Value(item.note),
                unitaryTva: Value(item.tva),
                state: Value(itemState),
                zDay: Value(zDay),
                kdsPrintedAt: Value(item.kdsPrintedAt),
                kdsPrintedQuantity: Value(item.kdsPrintedQuantity),
                // Carried through on every write: omitting it would let the
                // column default (0.0) win on an update and make every line
                // look unprinted to the additions-only order ticket.
                orderTicketPrintedQuantity: Value(
                  item.orderTicketPrintedQuantity,
                ),
                courseNo: Value(item.courseNo),
              ),
            );

        // Insert order product components
        for (final component in item.components) {
          await _database
              .into(_database.orderProductComponents)
              .insert(
                OrderProductComponentsCompanion.insert(
                  componentId: component.componentId,
                  orderProductId: orderProductId,
                  quantity: Value(component.quantity),
                  price: Value(component.price),
                  isSpecial: Value(component.isSpecial),
                  // Snapshot the name as sold — a later rename or 86 must not
                  // rewrite what an already-printed ticket said.
                  name: Value(component.name),
                  removalCharge: Value(component.removalCharge),
                ),
              );
        }
      }
      return newOrderId;
    });

    // Emit event
    _emitEvent(
      OrderInsertedEvent(
        orderId: orderId,
        orderCode: orderCode,
        status: status,
      ),
    );

    // Log order creation
    await _logService.logOrderCreated(
      orderId,
      'Order created with code $orderCode, status $status',
    );
    _audit(
      (log, uid, uname) =>
          log.logOrderCreated(orderCode, userId: uid, username: uname),
    );
    final reader = _ref;
    if (reader != null) {
      notifyDiscounts(reader.read, orderCode: orderCode, order: order);
    }

    // Auto-sync if network is available. Detached: the order is already
    // durable (committed above with isSynced = false), so the cashier must not
    // wait on the network to get the till back. See [_detach].
    if (_syncService != null && _isOnlineCallback != null) {
      final isOnline = _isOnlineCallback!();
      _logger.debug(
        'Auto-sync on create: online=$isOnline orderCode=$orderCode',
      );
      if (isOnline) {
        _detach('Auto-sync of new order code=$orderCode', () async {
          final orderSynced = await _syncService!.syncSingleOrder(
            orderId,
            deadline: _promptPushDeadline,
          );
          if (orderSynced) {
            await _syncService!.syncTicketsForOrder(
              orderId,
              deadline: _promptPushDeadline,
            );
          }
          _logger.info('Auto-synced new $status order code=$orderCode');
        });
      }
    }

    return orderId;
  }

  Future<int> holdOrder(
    CurrentOrder order,
    int userId, {
    int? sessionId,
  }) async {
    // Check if order is already saved (has orderId)
    if (order.isSaved()) {
      // Check if there are new items added (items without IDs are new)
      final hasNewItems = order.items.any((item) => item.id == null);

      if (hasNewItems) {
        // Cannot hold an order that has new unsaved items
        // User must press "Proceed" first to save those items
        throw Exception(
          'Cannot hold order with new items. Press Proceed first to save them.',
        );
      }

      // No new items, just update status to ONHOLD
      final orderId = order.orderId!;
      await updateOrderStatus(orderId, "ONHOLD");

      // Update all unpaid items to ONHOLD state
      for (final item in order.items) {
        if (item.id != null && item.ticketId == null) {
          await (_database.update(
            _database.orderProducts,
          )..where((tbl) => tbl.id.equals(item.id!))).write(
            OrderProductsCompanion(
              state: const Value('ONHOLD'),
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
      }

      final savedOrder = await (_database.select(
        _database.orders,
      )..where((tbl) => tbl.id.equals(orderId))).getSingle();

      // Emit hold event
      _emitEvent(OrderHeldEvent(orderId: orderId, orderCode: savedOrder.code));
      return order.orderId!;
    }

    // Save new order as ONHOLD — must still belong to an active session
    // (saveOrder enforces this via _assertActiveSession).
    final orderId = await saveOrder(
      order,
      userId,
      status: 'ONHOLD',
      sessionId: sessionId,
    );
    final savedOrder = await (_database.select(
      _database.orders,
    )..where((tbl) => tbl.id.equals(orderId))).getSingle();

    // Emit hold event
    _emitEvent(OrderHeldEvent(orderId: orderId, orderCode: savedOrder.code));

    return orderId;
  }

  /// Persist [order].
  ///
  /// [headerOnly] writes the order's own fields — discount, note, covers, tip,
  /// table, customer — and leaves `order_products` completely alone.
  ///
  /// That is the shape a cashier is allowed on a WAITER's order: the remise and
  /// the note are the cashier's business, the lines are the waiter's. It is
  /// enforced here rather than by refusing to save at all, because refusing
  /// meant a cashier could apply a remise, hit Print, and watch it silently not
  /// stick. Doing it in the repository also means the guarantee does not depend
  /// on the panel having disabled the right buttons: even a cart whose items
  /// were somehow altered cannot write a line through this path.
  Future<void> updateOrder(
    CurrentOrder order, {
    bool queueSyncOperation = true,
    bool headerOnly = false,
  }) async {
    int orderId = order.orderId!;

    final existingOrder = await (_database.select(
      _database.orders,
    )..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();

    // An order left over from a closed shift is not frozen — it is a table
    // with people at it. Move it onto the open session and today's Z-day
    // rather than refusing to touch it; see [_rehomeIfSessionClosed]. Only
    // when nothing is open is there genuinely no shift to account it to.
    DateTime? rehomedZDay;
    if (existingOrder != null) {
      final rehomed = await _rehomeIfSessionClosed(existingOrder);
      if (rehomed != null) {
        rehomedZDay = rehomed.zDay;
      } else {
        final session = existingOrder.sessionId == null
            ? null
            : await (_database.select(_database.cashSessions)
                    ..where((tbl) => tbl.id.equals(existingOrder.sessionId!)))
                  .getSingleOrNull();
        if (session?.status == 'ended') {
          throw Exception(
            'Cannot modify order from a closed (Z-report) session',
          );
        }
      }
    }

    final wasAlreadySynced = existingOrder?.isSynced ?? false;
    final orderCode = existingOrder?.code ?? order.orderCode ?? '';
    // Preserve the original z_day — re-inserted products must stay on the
    // same Z-day as the order even if the update happens after midnight. The
    // exception is an order just re-homed out of a closed shift: its lines
    // belong to the Z-day now collecting them, not to the one that already
    // reported without them.
    // Last resort resolves through the order's OWN session, not the clock: an
    // order with no z_day yet still knows which shift it belongs to, and that
    // shift is the answer even when the save happens after midnight.
    final orderZDay =
        rehomedZDay ??
        existingOrder?.zDay ??
        await _zDayForSessionId(existingOrder?.sessionId);

    // Count unpaid items to be updated
    final unpaidItems = order.items
        .where((item) => item.ticketId == null)
        .toList();
    _logger.debug(
      'updateOrder: total items=${order.items.length}, unpaid items=${unpaidItems.length}',
    );

    // If there are no unpaid items and no items at all, something is wrong
    if (order.items.isEmpty && unpaidItems.isEmpty) {
      _logger.warning(
        'updateOrder called with zero items - this should not happen',
      );
    }

    // Snapshot of the existing UNPAID lines (filled inside the transaction
    // below, before they're wiped) so that afterwards we can diff old vs new
    // and surface which items the cashier dropped (or reduced) in this save.
    // Paid items are excluded — they're not touched by the update.
    //
    // Key = (productId, variantId ?? -1). Two lines with the same product +
    // variant collapse into one entry whose value is the summed quantity, so
    // a partial reduction (e.g. removing one of two Pizzas) still surfaces.
    final removedSnapshot = <String, double>{};

    // Unit price per key, captured with the snapshot so an annulment can be
    // valued after the row it describes has been deleted. Last writer wins —
    // two lines of the same product+variant at different prices are already
    // collapsed into one snapshot entry, and the report wants an order of
    // magnitude, not a per-line audit.
    final removedPrices = <String, double>{};

    // Per-unit manual discount each line carried before this save, so a remise
    // added now is told apart from one already reported.
    final previousLineDiscount = <String, double>{};

    // Per product+variant, how much of it the kitchen has been asked to cook.
    // Compared against what survives this save to work out what somebody is
    // cooking for an order that no longer wants it — see [cancelledQuantity].
    final kitchenSent = <String, double>{};
    // Filled after the re-insert, and printed once the transaction has
    // committed: a cancellation ticket must never be the thing that rolls
    // back the edit it is announcing.
    final cancelledForKitchen = <OrderItem>[];
    // The cart lines this save actually wrote. A line removed or paid since
    // the cart was read is not among them, and must not count as surviving.
    final written = <OrderItem>[];

    // Header and line writes commit together: a crash part-way must not leave
    // the header saying one thing and the lines another.
    await _database.transaction(() async {
      // Update order details
      await (_database.update(
        _database.orders,
      )..where((tbl) => tbl.id.equals(orderId))).write(
        OrdersCompanion(
          tableId: Value(order.tableId),
          clientId: Value(order.customerId),
          commercialId: Value(order.commercialId),
          waiterId: Value(order.waiterId),
          discountPercentage: Value(order.discountPercentage),
          // Tip — passes `null` when cleared (cashier picked "No tip" on the
          // dialog), so the server's clear-semantic round-trips correctly via
          // the normal order update path.
          tip: Value(order.tip > 0 ? order.tip : null),
          // Written unconditionally so clearing the fee round-trips: `null`
          // here means the cashier removed it, `0.0` means free delivery.
          deliveryFee: Value(order.deliveryFee),
          persons: Value(order.numberOfPersons),
          type: Value(order.type),
          note: Value(order.note),
          discountReason: Value(order.discountReason),
          address: Value(order.deliveryAddress),
          reference: Value(_blankToNull(order.reference)),
          // Set once by conversion; an edit never clears it (omitting it from
          // a push never unlinks either).
          reservationCode: order.reservationCode == null
              ? const Value.absent()
              : Value(order.reservationCode),
          // The header's z_day was computed above but only ever written onto the
          // lines, so an order that arrived without one (a delivery-queue order,
          // a legacy row) kept a null header z_day while its lines carried the
          // right day — and the header is what the order push sends. Written
          // only when it actually moves: re-homing out of a closed shift, or
          // filling in a null. An order already sitting on its own day is left
          // exactly where it is.
          zDay: rehomedZDay != null || existingOrder?.zDay == null
              ? Value(orderZDay)
              : const Value<DateTime?>.absent(),
          updatedAt: Value(DateTime.now()),

          // Mark as not synced if changes were made to a previously synced order
          isSynced: Value(
            wasAlreadySynced ? false : existingOrder?.isSynced ?? false,
          ),
        ),
      );

      // Header written, lines untouched — see [headerOnly].
      if (headerOnly) return;

      final allUnpaidRows = await (_database.select(
        _database.orderProducts,
      )..where((t) => t.orderId.equals(orderId) & t.ticketId.isNull())).get();

      // Lines this cart never saw: written into the order AFTER it was loaded,
      // by something that is not this screen — the waiter app's add-product
      // route inserts straight into `order_products` over the LAN, and the
      // cashier's panel is never told.
      //
      // A line absent from `order.items` is either one the cart loaded and the
      // cashier then dropped (a genuine removal) or one the cart never held,
      // which it cannot be asserting the removal of. [CurrentOrder.loadedLineIds]
      // tells them apart exactly. Carts without it fall back to the load
      // timestamp, and carts with neither (never loaded from the database)
      // have no foreign rows at all, which is the oldest behaviour.
      final cartRowIds = {
        for (final item in order.items)
          if (item.ticketId == null && item.id != null) item.id!,
      };
      final loadedIds = order.loadedLineIds;
      final loadedAt = order.loadedAt;
      final foreignRows = <OrderProduct>[];
      final existingUnpaidRows = <OrderProduct>[];
      for (final row in allUnpaidRows) {
        final bool isForeign;
        if (cartRowIds.contains(row.id)) {
          isForeign = false;
        } else if (loadedIds != null) {
          isForeign = !loadedIds.contains(row.id);
        } else {
          // `>=`, not `>`: Windows hands out the same `DateTime.now()` for
          // calls milliseconds apart, so a strict comparison threw away the
          // line it was written to save.
          isForeign = loadedAt != null && !row.updatedAt.isBefore(loadedAt);
        }
        (isForeign ? foreignRows : existingUnpaidRows).add(row);
      }
      final foreignIds = [for (final row in foreignRows) row.id];
      if (foreignIds.isNotEmpty) {
        _logger.info(
          'updateOrder: preserving ${foreignIds.length} line(s) added to '
          'order $orderId since the cart was loaded',
        );
      }

      // The tombstone's price is what one unit was billed at — options in,
      // manual discount out — so the Z's cancelled-lines row reads what the
      // customer would have paid, not the bare catalogue price.
      final removedCompPerUnit = <int, double>{};
      if (existingUnpaidRows.isNotEmpty) {
        final comps = await (_database.select(_database.orderProductComponents)
              ..where((c) => c.orderProductId
                  .isIn(existingUnpaidRows.map((r) => r.id).toList())))
            .get();
        for (final c in comps) {
          removedCompPerUnit[c.orderProductId] =
              (removedCompPerUnit[c.orderProductId] ?? 0) + c.price * c.quantity;
        }
      }

      for (final row in existingUnpaidRows) {
        final key = '${row.productId}:${row.variantId ?? -1}';
        removedSnapshot[key] = (removedSnapshot[key] ?? 0) + row.quantity;
        removedPrices[key] = row.unitaryPrice +
            (removedCompPerUnit[row.id] ?? 0) -
            row.manualDiscount;
        previousLineDiscount[key] = row.manualDiscount;
        // What the KITCHEN was told, which is a different question from what
        // the bill said: a line can be rung up and pulled before it is ever
        // sent, and that needs no cancellation ticket.
        if (row.kdsPrintedQuantity > 0) {
          kitchenSent[key] = (kitchenSent[key] ?? 0) + row.kdsPrintedQuantity;
        }
      }

      // Cart lines whose row is no longer an unpaid line of this order: it was
      // removed (by the waiter, another screen, a server deletion) or paid
      // since this cart was read. Re-inserting them is what brought a line a
      // waiter had pulled back onto the bill, so only a line that now belongs
      // to ANOTHER order is still written — that is a line being moved here.
      final rowById = {for (final r in existingUnpaidRows) r.id: r};
      final goneIds = [
        for (final item in order.items)
          if (item.ticketId == null &&
              item.id != null &&
              !rowById.containsKey(item.id))
            item.id!,
      ];
      final goneRows = goneIds.isEmpty
          ? const <OrderProduct>[]
          : await (_database.select(
              _database.orderProducts,
            )..where((t) => t.id.isIn(goneIds))).get();
      final goneById = {for (final r in goneRows) r.id: r};

      // Lines are updated IN PLACE, never deleted and re-inserted. A line
      // keeps its id across saves, so a cart that was not reloaded after an
      // earlier save (the waiter button, a held cart resumed later) still
      // points at the right rows. With delete-and-reinsert its ids went stale,
      // the rows it had just written looked like somebody else's, and the next
      // save kept them AND wrote the cart again — every line doubled.
      final costResolver = ProductCostResolver(_database);
      final now = DateTime.now();
      final updatedIds = <int>{};
      var skippedGone = 0;

      Future<void> writeComponents(int orderProductId, OrderItem item) async {
        for (final component in item.components) {
          await _database
              .into(_database.orderProductComponents)
              .insert(
                OrderProductComponentsCompanion.insert(
                  componentId: component.componentId,
                  orderProductId: orderProductId,
                  quantity: Value(component.quantity),
                  price: Value(component.price),
                  isSpecial: Value(component.isSpecial),
                  // Snapshot the name as sold — a later rename or 86 must not
                  // rewrite what an already-printed ticket said.
                  name: Value(component.name),
                  removalCharge: Value(component.removalCharge),
                ),
              );
        }
      }

      for (final item in order.items) {
        if (item.ticketId != null) {
          // Skip items that are already ticketed
          continue;
        }
        final before = item.id == null ? null : rowById[item.id];

        if (before == null && item.id != null) {
          final gone = goneById[item.id];
          if (gone == null || gone.orderId == orderId) {
            skippedGone++;
            continue;
          }
        }

        final kitchen = carriedKitchenProgress(
          before: before,
          quantity: item.quantity,
          now: now,
          orderCreatedAt: existingOrder?.createdAt,
        );

        if (before != null) {
          final sameGoods =
              before.productId == item.productId &&
              before.variantId == item.variantId;
          await (_database.update(
            _database.orderProducts,
          )..where((t) => t.id.equals(before.id))).write(
            OrderProductsCompanion(
              productId: Value(item.productId),
              variantId: Value(item.variantId),
              quantity: Value(item.quantity),
              unitaryPrice: Value(item.finalPrice),
              // Cost was snapshotted at ring-up; only a change of goods resets it.
              cost: sameGoods && before.cost != null
                  ? const Value.absent()
                  : await costResolver.resolveValue(
                      productId: item.productId,
                      variantId: item.variantId,
                    ),
              serialId: Value(item.serialId),
              unitaryDiscount: Value(item.discount),
              manualDiscount: Value(item.manualDiscount),
              note: Value(item.note),
              unitaryTva: Value(item.tva),
              // The kitchen's work on the line stands: adding a drink to a
              // table must not send every dish back to PENDING on the KDS.
              state: Value(kitchen.state),
              preparingAt: Value(kitchen.preparingAt),
              readyAt: Value(kitchen.readyAt),
              servedAt: Value(kitchen.servedAt),
              kitchenAt: Value(kitchen.kitchenAt),
              zDay: Value(orderZDay),
              // The row's own print stamps win over a cart that read them
              // before the print landed — writing the cart's older zeros back
              // made the kitchen get the whole order again next round. A
              // quantity cut is clamped below, with its cancellation ticket.
              kdsPrintedAt: Value(item.kdsPrintedAt ?? before.kdsPrintedAt),
              kdsPrintedQuantity: Value(
                item.kdsPrintedQuantity > before.kdsPrintedQuantity
                    ? item.kdsPrintedQuantity
                    : before.kdsPrintedQuantity,
              ),
              orderTicketPrintedQuantity: Value(
                item.orderTicketPrintedQuantity >
                        before.orderTicketPrintedQuantity
                    ? item.orderTicketPrintedQuantity
                    : before.orderTicketPrintedQuantity,
              ),
              courseNo: Value(item.courseNo),
              // A quantity cut is a cancellation of those units: a running total
              // on the live line, sent with the v2 push. [quantity] stays the
              // sold amount, so no total reads this.
              canceledQuantity: item.quantity < before.quantity - 1e-9
                  ? Value(
                      before.canceledQuantity +
                          (before.quantity - item.quantity),
                    )
                  : const Value.absent(),
              canceledAt: item.quantity < before.quantity - 1e-9
                  ? Value(now)
                  : const Value.absent(),
              canceledBy: item.quantity < before.quantity - 1e-9
                  ? Value(_ref?.read(currentUserProvider)?.id)
                  : const Value.absent(),
              updatedAt: Value(now),
            ),
          );
          await (_database.delete(
            _database.orderProductComponents,
          )..where((c) => c.orderProductId.equals(before.id))).go();
          await writeComponents(before.id, item);
          updatedIds.add(before.id);
          written.add(item);
          continue;
        }

        final orderProductId = await _database
            .into(_database.orderProducts)
            .insert(
              OrderProductsCompanion.insert(
                orderId: orderId,
                productId: item.productId,
                variantId: Value(item.variantId),
                quantity: Value(item.quantity),
                unitaryPrice: item.finalPrice,
                cost: await costResolver.resolveValue(
                  productId: item.productId,
                  variantId: item.variantId,
                ),
                serialId: Value(item.serialId),
                unitaryDiscount: Value(item.discount),
                manualDiscount: Value(item.manualDiscount),
                note: Value(item.note),
                unitaryTva: Value(item.tva),
                state: Value(kitchen.state),
                preparingAt: Value(kitchen.preparingAt),
                readyAt: Value(kitchen.readyAt),
                servedAt: Value(kitchen.servedAt),
                kitchenAt: Value(kitchen.kitchenAt),
                zDay: Value(orderZDay),
                kdsPrintedAt: Value(item.kdsPrintedAt),
                kdsPrintedQuantity: Value(item.kdsPrintedQuantity),
                // Carried through on every write: omitting it would let the
                // column default (0.0) win and make the line look unprinted to
                // the additions-only order ticket.
                orderTicketPrintedQuantity: Value(
                  item.orderTicketPrintedQuantity,
                ),
                courseNo: Value(item.courseNo),
              ),
            );
        await writeComponents(orderProductId, item);
        written.add(item);
      }
      if (skippedGone > 0) {
        _logger.info(
          'updateOrder: $skippedGone line(s) of order $orderId were '
          'removed or paid since the cart was loaded — not written back',
        );
      }

      // Lines the cart loaded and the cashier dropped. Their draft-division
      // claims go with them; every other claim still points at a live row.
      final removedIds = [
        for (final row in existingUnpaidRows)
          if (!updatedIds.contains(row.id)) row.id,
      ];
      if (removedIds.isNotEmpty) {
        // Kept for the v2 push before the row goes: a line missing from the
        // full order is an untracked deletion on the server, a cancelled one
        // is a cancellation.
        final by = _ref?.read(currentUserProvider)?.id;
        for (final row in existingUnpaidRows) {
          if (removedIds.contains(row.id)) {
            await keepCancelledLine(_database, row, by: by, at: now);
          }
        }
        await (_database.delete(
          _database.orderProductComponents,
        )..where((c) => c.orderProductId.isIn(removedIds))).go();
        await (_database.delete(
          _database.ticketDraftSplits,
        )..where((t) => t.orderProductId.isIn(removedIds))).go();
        await (_database.delete(
          _database.orderProducts,
        )..where((t) => t.id.isIn(removedIds))).go();
      }

      // What the kitchen is now cooking for nothing.
      //
      // Computed per product+variant rather than per row: "two of the three
      // steaks were pulled" is a fact about the product, not about a row id.
      if (kitchenSent.isNotEmpty) {
        final survivingByKey = <String, double>{};
        final itemByKey = <String, OrderItem>{};
        for (final item in written) {
          final key = '${item.productId}:${item.variantId ?? -1}';
          survivingByKey[key] = (survivingByKey[key] ?? 0) + item.quantity;
          itemByKey.putIfAbsent(key, () => item);
        }
        // Preserved lines are still on the order, so the kitchen is not
        // cooking them for nothing. Counting them here stops the block below
        // firing a cancellation ticket for food that is very much still
        // wanted, and stops it clawing back their printed-quantity cursor.
        for (final row in foreignRows) {
          final key = '${row.productId}:${row.variantId ?? -1}';
          survivingByKey[key] = (survivingByKey[key] ?? 0) + row.quantity;
        }
        for (final entry in kitchenSent.entries) {
          final gone = cancelledQuantity(
            sent: entry.value,
            remaining: survivingByKey[entry.key] ?? 0,
          );
          if (gone <= 0) continue;
          final template = itemByKey[entry.key];
          cancelledForKitchen.add(
            (template ?? _removedItemTemplate(entry.key, existingUnpaidRows))
                .copyWith(quantity: gone, kdsPrintQuantity: gone),
          );
        }

        // Stop the delta bookkeeping claiming more was sent than the line is
        // now worth. Without this, cutting 3 down to 1 and back up to 3 sends
        // the kitchen nothing the second time — it still thinks it has asked
        // for 3 — and the customer waits for food nobody is making.
        for (final key in kitchenSent.keys) {
          final remaining = survivingByKey[key] ?? 0;
          final parts = key.split(':');
          final productId = int.parse(parts[0]);
          final variantId = int.parse(parts[1]);
          final clamp = _database.update(_database.orderProducts)
            ..where(
              (t) =>
                  t.orderId.equals(orderId) &
                  t.ticketId.isNull() &
                  t.productId.equals(productId) &
                  (variantId == -1
                      ? t.variantId.isNull()
                      : t.variantId.equals(variantId)) &
                  t.kdsPrintedQuantity.isBiggerThanValue(remaining),
            );
          // This cart never held the preserved lines, so it has no business
          // rewriting what the kitchen was told about them.
          if (foreignIds.isNotEmpty) {
            clamp.where((t) => t.id.isNotIn(foreignIds));
          }
          await clamp.write(
            OrderProductsCompanion(kdsPrintedQuantity: Value(remaining)),
          );
        }
      }
    });

    // If order was previously synced, we need to sync the update
    if (wasAlreadySynced && queueSyncOperation && orderCode.isNotEmpty) {
      // Try to sync immediately if online, otherwise queue
      if (_syncService != null && _isOnlineCallback != null) {
        final isOnline = _isOnlineCallback!();
        if (isOnline) {
          _logger.debug(
            'Auto-sync on update: online=$isOnline orderCode=$orderCode',
          );
          // Detached — see [_detach]. The queue-on-failure fallback travels
          // INSIDE the detached job because it is gated on whether the push
          // succeeded; leaving it behind would drop the fallback entirely.
          _detach('Re-sync of updated order code=$orderCode', () async {
            try {
              // Re-sync the entire order with updated products
              final orderSynced = await _syncService!.syncSingleOrder(
                orderId,
                deadline: _promptPushDeadline,
              );
              if (orderSynced) {
                await _syncService!.syncTicketsForOrder(
                  orderId,
                  deadline: _promptPushDeadline,
                );
              }
              _logger.info('Re-synced updated order code=$orderCode');
            } catch (e) {
              _logger.error(
                'Failed to re-sync updated order, queuing update: $e',
              );
              // Queue update operation as fallback
              await _queueOrderUpdate(orderId, orderCode, order);
            }
          });
        } else {
          // Offline - queue the update
          await _queueOrderUpdate(orderId, orderCode, order);
        }
      } else {
        // No sync service - queue the update
        await _queueOrderUpdate(orderId, orderCode, order);
      }
    }

    // Tell the kitchen to stop making what was pulled. After the transaction
    // for the same reason as the claim below: printing is the least reliable
    // thing here and must never be able to undo the edit.
    if (cancelledForKitchen.isNotEmpty) {
      await _printKitchenCancellation(orderId, cancelledForKitchen);
    }

    // Whoever just changed this order now owns it. After the transaction, so
    // a claim failure cannot roll back the edit itself.
    await claimOrderForCurrentUser(orderId);

    // Emit event
    _emitEvent(OrderUpdatedEvent(orderId: orderId));
    _emitEvent(
      OrderItemsChangedEvent(orderId: orderId, itemCount: order.items.length),
    );

    // Log order update
    await _logService.logOrderUpdated(
      orderId,
      'Order updated: code=$orderCode',
    );
    _audit(
      (log, uid, uname) =>
          log.logOrderUpdated(orderCode, userId: uid, username: uname),
    );
    final reader = _ref;
    if (reader != null) {
      notifyDiscounts(
        reader.read,
        orderCode: orderCode,
        order: order,
        previousPercent: existingOrder?.discountPercentage ?? 0,
        previousLineDiscount: previousLineDiscount,
      );
    }

    // Subtract the new state from the snapshot — anything left is what got
    // removed (whole line dropped OR quantity reduced). We do this AFTER the
    // re-insert so the snapshot map is still untouched by intermediate state.
    for (final item in written) {
      final key = '${item.productId}:${item.variantId ?? -1}';
      final remaining = (removedSnapshot[key] ?? 0) - item.quantity;
      if (remaining <= 0) {
        removedSnapshot.remove(key);
      } else {
        removedSnapshot[key] = remaining;
      }
    }
    if (removedSnapshot.isNotEmpty) {
      await _logRemovedItems(
        orderId,
        orderCode,
        removedSnapshot,
        prices: removedPrices,
        kitchenSent: kitchenSent,
      );
    }
  }

  /// Resolves product/variant names for the leftover snapshot entries and
  /// writes both the technical (`OrderLogs`) and audit (`ActivityLogs`) lines.
  /// Wrapped in try/catch — a logging failure must never abort an order save.
  Future<void> _logRemovedItems(
    int orderId,
    String orderCode,
    Map<String, double> removed, {
    Map<String, double> prices = const {},
    Map<String, double> kitchenSent = const {},
  }) async {
    try {
      final productIds = <int>{};
      final variantIds = <int>{};
      for (final key in removed.keys) {
        final parts = key.split(':');
        productIds.add(int.parse(parts[0]));
        final vid = int.parse(parts[1]);
        if (vid != -1) variantIds.add(vid);
      }

      final productsById = <int, Product>{};
      if (productIds.isNotEmpty) {
        final rows = await (_database.select(
          _database.products,
        )..where((t) => t.id.isIn(productIds))).get();
        for (final p in rows) {
          productsById[p.id] = p;
        }
      }
      final variantsById = <int, ProductVariant>{};
      if (variantIds.isNotEmpty) {
        final rows = await (_database.select(
          _database.productVariants,
        )..where((t) => t.id.isIn(variantIds))).get();
        for (final v in rows) {
          variantsById[v.id] = v;
        }
      }

      final parts = <String>[];
      removed.forEach((key, qty) {
        final split = key.split(':');
        final pid = int.parse(split[0]);
        final vid = int.parse(split[1]);
        final productName = productsById[pid]?.name ?? 'item #$pid';
        final variantName = vid != -1 ? variantsById[vid]?.name : null;
        final label = variantName != null
            ? '$productName ($variantName)'
            : productName;
        parts.add('$qty× $label');
      });
      final summary = parts.join(', ');

      await _logService.logOrderUpdated(orderId, 'Items removed: $summary');
      _audit(
        (log, uid, uname) => log.logOrderItemsRemoved(
          orderCode,
          summary,
          userId: uid,
          username: uname,
        ),
      );

      // Structured tombstones for the Z. The sentence above is for a human to
      // read; these are what the report totals.
      final orderRow = await (_database.select(
        _database.orders,
      )..where((o) => o.id.equals(orderId))).getSingleOrNull();
      final actor = _ref?.read(currentUserProvider);
      await recordRemovedItems([
        for (final entry in removed.entries)
          () {
            final split = entry.key.split(':');
            final pid = int.parse(split[0]);
            final vid = int.parse(split[1]);
            final price = prices[entry.key] ?? 0.0;
            final productName = productsById[pid]?.name ?? 'item #$pid';
            return RemovedOrderItemsCompanion.insert(
              orderId: orderId,
              orderCode: Value(orderCode),
              sessionId: Value(orderRow?.sessionId),
              zDay: Value(orderRow?.zDay),
              productId: pid,
              variantId: Value(vid == -1 ? null : vid),
              productName: productName,
              variantName: Value(vid != -1 ? variantsById[vid]?.name : null),
              quantity: entry.value,
              unitaryPrice: Value(price),
              amount: Value(entry.value * price),
              wasSentToKitchen: Value((kitchenSent[entry.key] ?? 0) > 0),
              source: const Value('POS'),
              removedBy: Value(actor?.id),
              removedByName: Value(actor?.effectiveDisplayName),
            );
          }(),
      ]);

      // ignore: unawaited_futures
      _ref
          ?.read(waiterKitchenEventServiceProvider)
          .linesCanceled(
            orderId: orderId,
            lines: [
              for (final entry in removed.entries)
                () {
                  final split = entry.key.split(':');
                  final pid = int.parse(split[0]);
                  final vid = int.parse(split[1]);
                  final productName = productsById[pid]?.name ?? 'item #$pid';
                  final variantName = vid != -1
                      ? variantsById[vid]?.name
                      : null;
                  return CanceledLine(
                    name: variantName != null
                        ? '$productName ($variantName)'
                        : productName,
                    quantity: entry.value,
                  );
                }(),
            ],
          );
    } catch (e) {
      _logger.error('Failed to log removed items for order $orderCode: $e');
    }
  }

  /// Persist annulment tombstones. Best-effort by design: a failure here must
  /// never abort the save that produced it, and a missing Z line is a smaller
  /// problem than a lost order edit.
  Future<void> recordRemovedItems(List<RemovedOrderItemsCompanion> rows) async {
    if (rows.isEmpty) return;
    final reader = _ref;
    if (reader != null) notifyRemovedItems(reader.read, rows);
    try {
      await _database.batch(
        (b) => b.insertAll(_database.removedOrderItems, rows),
      );
    } catch (e) {
      _logger.error('Failed to record removed-item tombstones: $e');
    }
  }

  /// Helper to queue order update operation.
  ///
  /// CRITICAL: every field the server should see on a queued replay MUST
  /// be in this map. The pending-operations queue does a plain `PUT
  /// /pos/orders/{code}` with this body and nothing else — anything missing
  /// here is silently dropped server-side. Past omissions:
  ///   - `tip` was forgotten and never reached the backend when the cashier
  ///     was offline or the auto-sync hit a transient error and fell back
  ///     to the queue. Adding it here closes that gap.
  ///   - `customerPhoneNormalized` replaces the old `customerId` lookup per
  ///     the latest backend contract — server dedups customers by phone,
  ///     ignores ids on the order payload.
  Future<void> _queueOrderUpdate(
    int orderId,
    String orderCode,
    CurrentOrder order,
  ) async {
    try {
      final phoneNormalized = await _lookupCustomerPhoneNormalized(
        order.customerId,
      );
      final pendingOpsService = PendingOperationsService(_database);
      await pendingOpsService.queueOrderUpdate(
        entityId: orderId,
        orderCode: orderCode,
        updateData: {
          'tableId': order.tableId,
          // Kept for backward compat — server ignores it now, but old
          // server builds still read it. No harm sending both.
          'clientId': order.customerId,
          'customerPhoneNormalized': phoneNormalized,
          'commercialId': order.commercialId,
          'discountPercentage': order.discountPercentage,
          'tip': order.tip,
          // Only sent when recorded. The contract reads a missing/null
          // `deliveryFee` as "don't change", so replaying an order that never
          // had one must not blank out a fee the server already holds.
          if (order.hasDeliveryFee) 'deliveryFee': order.deliveryFee,
          'note': order.note,
          'type': order.type,
          'address': order.deliveryAddress,
          if (referenceForSync(order.reference) case final ref?)
            'reference': ref,
        },
      );
      _logger.info('Queued update operation for order code=$orderCode');
    } catch (e) {
      _logger.error('Failed to queue update operation: $e');
    }
  }

  /// Resolve the canonical `phone_normalized` for [customerId], or `null`
  /// if there's no customer or the customer has no phone on record. Used
  /// to build order payloads that key customers by phone instead of by id.
  Future<String?> _lookupCustomerPhoneNormalized(int? customerId) async {
    if (customerId == null) return null;
    final row = await (_database.select(
      _database.customers,
    )..where((c) => c.id.equals(customerId))).getSingleOrNull();
    return row?.phoneNormalized;
  }

  Future<CurrentOrder?> getOrderByTable(int tableId) async {
    // Get the most recent ONHOLD order for this table
    final table = await (_database.select(
      _database.areaTables,
    )..where((tbl) => tbl.id.equals(tableId))).getSingleOrNull();

    if (table == null || table.orderId == null) return null;

    final order = await (_database.select(
      _database.orders,
    )..where((tbl) => tbl.id.equals(table.orderId!))).getSingleOrNull();

    if (order == null) return null;

    return await loadOrderDetails(order);
  }

  Future<void> updateOrderProductState(
    int orderId,
    int productId,
    String newState,
  ) async {
    await (_database.update(_database.orderProducts)..where(
          (tbl) => tbl.orderId.equals(orderId) & tbl.id.equals(productId),
        ))
        .write(
          OrderProductsCompanion(
            state: Value(newState),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// Replaces the tags of a SAVED order and queues the push. Tags never move
  /// money, so this is allowed on an order of a closed session too.
  Future<void> setOrderTags(int orderId, List<int> tagIds) async {
    await (_database.update(
      _database.orders,
    )..where((o) => o.id.equals(orderId))).write(
      OrdersCompanion(
        tagIds: Value(encodeTagIds(tagIds)),
        tagsSynced: const Value(false),
        tagsSyncError: const Value(null),
      ),
    );
  }

  Future<CurrentOrder?> getOrderById(int orderId) async {
    final order = await (_database.select(
      _database.orders,
    )..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();

    if (order == null) return null;

    return await loadOrderDetails(order);
  }

  /// Find an active product by its MBW / PLU code (string comparison only).
  Future<Product?> findByMbwCode(String plu) async {
    return (_database.select(_database.products)
          ..where((t) => t.mbwCode.equals(plu))
          ..where((t) => t.isActive.equals(true)))
        .getSingleOrNull();
  }

  Future<CurrentOrder?> getOrderByCode(String orderCode) async {
    final order = await (_database.select(
      _database.orders,
    )..where((tbl) => tbl.code.equals(orderCode))).getSingleOrNull();

    if (order == null) return null;

    return await loadOrderDetails(order);
  }

  Future<CurrentOrder> loadOrderDetails(Order order) async {
    // Batched-fetch rewrite: collapses the previous N+1 pattern
    // (one query per item × product / variant / OPCs / per-component) into
    // ~5 IN(...) queries regardless of order size. Saves the
    // "Continue with table's order" lag on big orders.
    final orderProducts = await (_database.select(
      _database.orderProducts,
    )..where((tbl) => tbl.orderId.equals(order.id))).get();

    final items = <OrderItem>[];
    if (orderProducts.isNotEmpty) {
      final productIds = orderProducts.map((p) => p.productId).toSet();
      final variantIds = orderProducts
          .where((p) => p.variantId != null)
          .map((p) => p.variantId!)
          .toSet();
      final orderProductIds = orderProducts.map((p) => p.id).toSet();

      // 1) All products in one IN(...) query
      final products = productIds.isEmpty
          ? const <Product>[]
          : await (_database.select(
              _database.products,
            )..where((t) => t.id.isIn(productIds))).get();
      final productById = {for (final p in products) p.id: p};

      // 2) All variants in one IN(...) query
      final productVariantById = <int, ProductVariant>{};
      if (variantIds.isNotEmpty) {
        final variants = await (_database.select(
          _database.productVariants,
        )..where((t) => t.id.isIn(variantIds))).get();
        for (final v in variants) {
          productVariantById[v.id] = v;
        }
      }

      // 3) All order_product_components for these order products, grouped
      //    by orderProductId in memory.
      final allOpcs = orderProductIds.isEmpty
          ? const <OrderProductComponent>[]
          : await (_database.select(
              _database.orderProductComponents,
            )..where((t) => t.orderProductId.isIn(orderProductIds))).get();
      final opcsByOp = <int, List<OrderProductComponent>>{};
      for (final c in allOpcs) {
        opcsByOp.putIfAbsent(c.orderProductId, () => []).add(c);
      }

      // Serial numbers for any serial-tracked line, in one query. Keyed
      // nullably so the lookup below can be unconditional.
      final serialIds = orderProducts
          .map((op) => op.serialId)
          .whereType<int>()
          .toSet();
      final serialNumberById = <int?, String?>{};
      if (serialIds.isNotEmpty) {
        final rows = await (_database.select(
          _database.serials,
        )..where((t) => t.id.isIn(serialIds))).get();
        for (final r in rows) {
          serialNumberById[r.id] = r.serialNumber;
        }
      }

      // 4) All distinct components those reference, in one query.
      //    The map is left untyped to avoid the name clash between drift's
      //    framework `Component` class and the project's `Component` table
      //    row class — both are visible through the imports above.
      final componentIds = allOpcs.map((c) => c.componentId).toSet();
      final componentById = {
        if (componentIds.isNotEmpty)
          for (final c in await (_database.select(
            _database.components,
          )..where((t) => t.id.isIn(componentIds))).get())
            c.id: c,
      };

      // 5) Assemble OrderItems from the in-memory lookups — no awaits.
      for (final orderProduct in orderProducts) {
        final product = productById[orderProduct.productId];
        if (product == null) continue; // tolerate orphan rows like before

        String? variantName;
        String? variantImageUrl;
        if (orderProduct.variantId != null) {
          final v = productVariantById[orderProduct.variantId!];
          variantName = v?.name;
          variantImageUrl = v?.imageUrl;
        }

        final components = <OrderItemComponent>[];
        for (final orderComp in opcsByOp[orderProduct.id] ?? const []) {
          final component = componentById[orderComp.componentId];
          if (component != null) {
            components.add(
              OrderItemComponent(
                componentId: component.id,
                name: component.name,
                quantity: orderComp.quantity,
                price: orderComp.price, // Use stored price from order time
                isSpecial: orderComp.isSpecial,
                removalCharge: orderComp.removalCharge,
              ),
            );
          }
        }

        items.add(
          OrderItem(
            id: orderProduct.id,
            productId: product.id,
            productName: product.name,
            variantId: orderProduct.variantId,
            variantName: variantName,
            imageUrl: variantImageUrl ?? product.imageUrl,
            finalPrice: orderProduct.unitaryPrice,
            quantity: orderProduct.quantity,
            // Baseline for the decrement floor — cashier can take back only
            // what they added on top of this in the current session.
            savedQuantity: orderProduct.quantity,
            components: components,
            note: orderProduct.note,
            discount: orderProduct.unitaryDiscount,
            manualDiscount: orderProduct.manualDiscount,
            tva: orderProduct.unitaryTva,
            ticketId: orderProduct.ticketId,
            state: orderProduct.state,
            kdsPrintedAt: orderProduct.kdsPrintedAt,
            kdsPrintedQuantity: orderProduct.kdsPrintedQuantity,
            // Counterpart for the customer slip — without it, reopening a table
            // would make every line look never-printed and the additions-only
            // order ticket would reprint the whole bill.
            orderTicketPrintedQuantity: orderProduct.orderTicketPrintedQuantity,
            // Normalised on the way OUT of the database as well as on the
            // way in over the wire. Same argument either direction: a
            // column holding a value every reader has to remember to
            // ignore is a column that will eventually be read by someone
            // who forgets. A hand-edited row, or one written by a build
            // that knew about a fourth course, reads as untagged here.
            courseNo: normalizeCourseNo(orderProduct.courseNo),
            // Restore the unit sold, so re-opening a saved order shows the serial
            // on the line and re-syncing it still carries the same unit. The
            // number is looked up below rather than stored on the line.
            serialId: orderProduct.serialId,
            serialNumber: serialNumberById[orderProduct.serialId],
            // Round-trips through the delete-and-reinsert in [updateOrder] —
            // see the field's own doc comment for what dropping it costs.
            serverId: orderProduct.serverId,
          ),
        );
      }
    }

    // Get table name
    String? tableName;
    if (order.tableId != null) {
      final table = await (_database.select(
        _database.areaTables,
      )..where((tbl) => tbl.id.equals(order.tableId!))).getSingleOrNull();
      tableName = table?.name;
    }

    // Get customer name and phone
    String? customerName;
    String? customerPhone;
    if (order.clientId != null) {
      final customer = await (_database.select(
        _database.customers,
      )..where((tbl) => tbl.id.equals(order.clientId!))).getSingleOrNull();
      if (customer != null) {
        customerName = customer.displayLabel;
        customerPhone = customer.phone;
      }
    }

    // Get commercial name
    String? commercialName;
    if (order.commercialId != null) {
      final commercial = await (_database.select(
        _database.commercials,
      )..where((tbl) => tbl.id.equals(order.commercialId!))).getSingleOrNull();
      commercialName = commercial != null
          ? '${commercial.firstName} ${commercial.lastName}'
          : null;
    }

    // Get waiter name
    String? waiterName;
    if (order.waiterId != null) {
      final waiter = await (_database.select(
        _database.waiters,
      )..where((tbl) => tbl.id.equals(order.waiterId!))).getSingleOrNull();
      waiterName = waiter != null
          ? '${waiter.firstName} ${waiter.lastName ?? ''}'.trim()
          : null;
    }

    int numberOfPersons = order.persons;

    return CurrentOrder(
      orderId: order.id,
      orderCode: order.code,
      sessionOrderNo: order.sessionOrderNo,
      items: items,
      numberOfPersons: numberOfPersons,

      tableId: order.tableId,
      tableName: tableName,
      customerId: order.clientId,
      customerName: customerName,
      customerPhone: customerPhone,
      commercialId: order.commercialId,
      commercialName: commercialName,
      waiterId: order.waiterId,
      waiterName: waiterName,
      discountPercentage: order.discountPercentage,
      note: order.note,
      discountReason: order.discountReason,
      tagIds: parseTagIds(order.tagIds),
      type: order.type,
      deliveryAddress: order.address,
      reference: order.reference,
      reservationCode: order.reservationCode,
      tip: order.tip ?? 0.0,
      // Straight through — null stays null so "no fee" never becomes "free".
      deliveryFee: order.deliveryFee,
      // Needed by the waiter-order edit guard, which must not infer "a waiter
      // raised this" from waiterId — a cashier can attach a waiter to their
      // own order. See `isWaiterRaisedOrder`.
      source: order.source,
      // Stamped on the way out so [updateOrder] can tell lines this cart has
      // seen from lines written into the order behind its back (the waiter
      // app's add-product route). See [CurrentOrder.loadedAt].
      loadedAt: DateTime.now(),
      loadedLineIds: {for (final op in orderProducts) op.id},
    );
  }

  // Get all tables with their active orders
  Future<List<TableWithOrder>> getTablesWithOrders() async {
    final tables = await _database.select(_database.areaTables).get();
    final result = <TableWithOrder>[];

    for (final table in tables) {
      if (table.orderId == null) continue;

      final order = await (_database.select(
        _database.orders,
      )..where((tbl) => tbl.id.equals(table.orderId!))).getSingleOrNull();

      if (order == null) continue;

      // Calculate total
      final orderProducts = await (_database.select(
        _database.orderProducts,
      )..where((tbl) => tbl.orderId.equals(order.id))).get();

      double total = 0.0;
      for (final product in orderProducts) {
        final subtotal = product.unitaryPrice * product.quantity;
        final discount = product.unitaryDiscount * product.quantity;
        final tva = product.unitaryTva * product.quantity;
        total += subtotal - discount + tva;
      }

      result.add(
        TableWithOrder(
          table: table,
          orderCount: 1,
          total: total,
          lastUpdated: order.updatedAt,
        ),
      );
    }

    return result;
  }

  Stream<List<Order>> getOrdersByTable(int tableId) {
    return (_database.select(
      _database.orders,
    )..where((tbl) => tbl.tableId.equals(tableId))).watch();
  }

  Stream<List<Order>> getPendingOrders() {
    return (_database.select(
      _database.orders,
    )..where((tbl) => tbl.status.isNotIn(['DELIVERED', 'CANCELED']))).watch();
  }

  // Get all held orders (ONHOLD status)
  Future<List<Order>> getHeldOrders() async {
    return await (_database.select(_database.orders)
          ..where((tbl) => tbl.status.equals('ONHOLD'))
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]))
        .get();
  }

  // Get all orders with full details
  Future<List<OrderWithDetails>> getAllOrdersWithDetails() async {
    final orders = await (_database.select(
      _database.orders,
    )..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)])).get();

    final result = <OrderWithDetails>[];
    for (final order in orders) {
      // Get order products count
      final orderProducts = await (_database.select(
        _database.orderProducts,
      )..where((tbl) => tbl.orderId.equals(order.id))).get();

      // Calculate total
      double total = 0.0;
      for (final product in orderProducts) {
        final subtotal = product.unitaryPrice * product.quantity;
        final discount = product.unitaryDiscount * product.quantity;
        final tva = product.unitaryTva * product.quantity;
        total += subtotal - discount + tva;
      }

      // Get table name
      String? tableName;
      if (order.tableId != null) {
        final table = await (_database.select(
          _database.areaTables,
        )..where((tbl) => tbl.id.equals(order.tableId!))).getSingleOrNull();
        tableName = table?.name;
      }

      result.add(
        OrderWithDetails(
          order: order,
          tableName: tableName,
          itemCount: orderProducts.length,
          total: total,
        ),
      );
    }

    return result;
  }

  Future<void> updateOrderStatus(
    int orderId,
    String status, {
    bool queueSyncOperation = true,
    String? cancellationReason,
    int? sessionId,
    int? userId,
    int? waiterId,
  }) async {
    // Get current status before updating
    final currentOrder = await (_database.select(
      _database.orders,
    )..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();
    final oldStatus = currentOrder?.status ?? '';
    final wasAlreadySynced = currentOrder?.isSynced ?? false;
    final orderCode = currentOrder?.code ?? '';

    // Cancelling the order cancels everything the kitchen was told to cook.
    // Read BEFORE the status write, because [_allSentToKitchen] reads the
    // lines and a cancel may take them with it, and printed after so a dead
    // printer cannot block the cancellation itself.
    final cancelledWhole =
        status == 'CANCELED' &&
            currentOrder != null &&
            currentOrder.status != 'CANCELED'
        ? await _allSentToKitchen(orderId)
        : const <OrderItem>[];

    // Same rule as [updateOrder]: an order inherited from a closed shift
    // moves onto the open one rather than being frozen. COMPLETED was always
    // allowed through — finalising a payment must never be blocked — and now
    // every other status is too, on the session actually collecting it.
    if (currentOrder != null && status != 'COMPLETED') {
      final rehomed = await _rehomeIfSessionClosed(currentOrder);
      if (rehomed == null && currentOrder.sessionId != null) {
        final session =
            await (_database.select(_database.cashSessions)
                  ..where((tbl) => tbl.id.equals(currentOrder.sessionId!)))
                .getSingleOrNull();
        if (session?.status == 'ended') {
          throw Exception(
            'Cannot change status of order from a closed (Z-report) session',
          );
        }
      }
    }

    // Stamp sessionId if order has none and caller is providing one (confirmation flow)
    final sessionIdToStamp =
        (currentOrder?.sessionId == null && sessionId != null)
        ? Value(sessionId)
        : const Value<int?>.absent();

    // z_day follows the session onto the order, always. Stamping one without
    // the other left confirmed orders (an ONHOLD cart, a delivery-queue order)
    // sitting in a session with a null z_day, and a null z_day is what makes
    // the backend fall back to `createdAt` — which for anything confirmed
    // after midnight, or ingested from a platform that timestamped it
    // yesterday, is the wrong day.
    final zDayToStamp = sessionIdToStamp.present || currentOrder?.zDay == null
        ? Value(
            await _zDayForSessionId(
              sessionIdToStamp.present ? sessionId : currentOrder?.sessionId,
            ),
          )
        : const Value<DateTime?>.absent();

    // On confirmation (ONHOLD → anything else), stamp the confirming user + optional waiter
    final isConfirming = oldStatus == 'ONHOLD' && status != 'ONHOLD';

    // Build the update companion including cancellationReason
    final updateCompanion = OrdersCompanion(
      status: Value(status),
      updatedAt: Value(DateTime.now()),
      // Mark as not synced when status changes (except ONHOLD which doesn't sync)
      isSynced: Value(status == 'ONHOLD'),
      // Set cancellation reason when cancelled, clear it otherwise
      cancellationReason: Value(
        status == 'CANCELED' ? cancellationReason : null,
      ),
      sessionId: sessionIdToStamp,
      zDay: zDayToStamp,
      createdBy: isConfirming && userId != null
          ? Value(userId)
          : const Value<int?>.absent(),
      takenBy: isConfirming && userId != null
          ? Value(userId)
          : const Value<int?>.absent(),
      waiterId: isConfirming && waiterId != null
          ? Value(waiterId)
          : const Value<int?>.absent(),
    );

    await (_database.update(
      _database.orders,
    )..where((tbl) => tbl.id.equals(orderId))).write(updateCompanion);

    // A held order reaches the kitchen only now: its lines' KDS clocks start
    // at the release, not at the moment they were rung up and parked.
    if (isConfirming) {
      await (_database.update(_database.orderProducts)..where(
            (t) =>
                t.orderId.equals(orderId) &
                t.ticketId.isNull() &
                t.preparingAt.isNull(),
          ))
          .write(OrderProductsCompanion(kitchenAt: Value(DateTime.now())));
    }

    final reader = _ref;
    if (reader != null && status == 'CANCELED' && oldStatus != 'CANCELED') {
      try {
        final amount = (await getOrderTotals([orderId]))[orderId] ?? 0.0;
        final actor = reader.read(currentUserProvider);
        notifyOrderCancelled(
          reader.read,
          orderCode: orderCode,
          amount: amount,
          reason: cancellationReason,
          byName: actor?.effectiveDisplayName,
          byId: actor?.id ?? userId,
        );
      } catch (e) {
        _logger.warning('Cancel notification skipped: $e');
      }
    }

    // Cancellation has to reach the tickets, or the money stays in the books.
    //
    // Session totals and the Z report are built from tickets, and
    // PaymentBreakdown excludes cancelled ones from every method bucket and
    // tallies them separately. That only works if something sets the flag —
    // and it used to be set by ONE screen's cancel handler, so any other route
    // to CANCELED left a paid ticket counting towards the day's takings.
    // Doing it here means every caller gets it, including ones not yet written.
    //
    // Written on the way back out of CANCELED too: un-cancelling an order must
    // put its tickets back in the totals.
    try {
      await (_database.update(
        _database.tickets,
      )..where((t) => t.orderId.equals(orderId))).write(
        TicketsCompanion(
          isCancelled: Value(status == 'CANCELED'),
          isSynced: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } catch (e) {
      _logger.error(
        'Could not flag tickets of order $orderId as '
        '${status == 'CANCELED' ? 'cancelled' : 'active'}: $e',
      );
    }

    // Handle sync based on status change (skip ONHOLD)
    if (queueSyncOperation && orderCode.isNotEmpty && status != 'ONHOLD') {
      // Detached — see [_detach]. The push and its queue-on-failure fallback
      // both go, because the fallback is gated on whether the push succeeded.
      //
      // Note this whole branch is skipped by `settleOrderAndFreeTable`, which
      // passes queueSyncOperation: false — so nothing is ever detached from
      // inside that method's transaction.
      _detach('Status sync for order code=$orderCode', () async {
        bool syncedSuccessfully = false;

        // Try to sync if online
        if (_syncService != null && _isOnlineCallback != null) {
          final isOnline = _isOnlineCallback!();
          if (isOnline) {
            _logger.debug(
              'Auto-sync on status change: online=$isOnline orderCode=$orderCode newStatus=$status',
            );
            try {
              final orderSynced = await _syncService!.syncSingleOrder(
                orderId,
                deadline: _promptPushDeadline,
              );
              if (orderSynced) {
                await _syncService!.syncTicketsForOrder(
                  orderId,
                  deadline: _promptPushDeadline,
                );
                syncedSuccessfully = true;
              }
              _logger.info('Synced $status order code=$orderCode');
            } catch (e) {
              _logger.error('Failed to sync $status order: $e');
              // Will queue operation below
            }
          }
        }

        // If order was previously synced and we didn't sync successfully now, queue the update
        if (wasAlreadySynced && !syncedSuccessfully) {
          try {
            final pendingOpsService = PendingOperationsService(_database);
            await pendingOpsService.queueOrderUpdate(
              entityId: orderId,
              orderCode: orderCode,
              updateData: {
                'status': status,
                if (cancellationReason != null)
                  'cancellationReason': cancellationReason,
              },
            );
            _logger.info(
              'Queued status update operation for order code=$orderCode',
            );
          } catch (e) {
            _logger.error('Failed to queue status update operation: $e');
          }
        }
      });
    }

    // Emit event
    _emitEvent(
      OrderStatusChangedEvent(
        orderId: orderId,
        oldStatus: oldStatus,
        newStatus: status,
      ),
    );

    // Log order status update
    await _logService.logOrderUpdated(
      orderId,
      'Order status changed from $oldStatus to $status',
    );
    _audit((log, uid, uname) {
      if (status == 'CANCELED') {
        log.logOrderCancelled(
          orderCode,
          userId: uid,
          username: uname,
          reason: cancellationReason,
        );
      } else if (isConfirming) {
        log.logOrderConfirmed(orderCode, userId: uid, username: uname);
      } else {
        log.logOrderStatusChanged(
          orderCode,
          oldStatus,
          status,
          userId: uid,
          username: uname,
        );
      }
    });

    // The kitchen keeps cooking until somebody says otherwise.
    if (cancelledWhole.isNotEmpty) {
      await _printKitchenCancellation(orderId, cancelledWhole);
    }

    if (status == 'CANCELED' &&
        currentOrder != null &&
        currentOrder.status != 'CANCELED') {
      // ignore: unawaited_futures
      _ref
          ?.read(waiterKitchenEventServiceProvider)
          .linesCanceled(
            orderId: orderId,
            wholeOrder: true,
            reason: cancellationReason,
            lines: [
              for (final i in cancelledWhole)
                CanceledLine(
                  lineId: i.id,
                  name: i.variantName != null
                      ? '${i.productName} (${i.variantName})'
                      : i.productName,
                  quantity: i.quantity,
                  courseNo: i.courseNo,
                ),
            ],
          );
    }
  }

  Future<void> setTableOrderId(int tableId, int? orderId) async {
    await (_database.update(_database.areaTables)
          ..where((tbl) => tbl.id.equals(tableId)))
        .write(AreaTablesCompanion(orderId: Value(orderId)));
  }

  // Clear table order assignment (set orderId to null)
  Future<void> clearTableOrder(int tableId) async {
    await setTableOrderId(tableId, null);
  }

  /// Free EVERY table currently pointing at [orderId] — keyed on the real
  /// occupancy (`area_tables.orderId == orderId`) rather than a caller-supplied
  /// table id. This is what makes freeing robust: a stale or missing in-memory
  /// `order.tableId` (order loaded before the table was attached, or attached
  /// only on the table row) can no longer leave a table stuck as occupied. A
  /// no-op when nothing points at the order.
  Future<void> freeTablesForOrder(int orderId) async {
    await (_database.update(_database.areaTables)
          ..where((t) => t.orderId.equals(orderId)))
        .write(const AreaTablesCompanion(orderId: Value(null)));
  }

  /// Atomically finalize a fully-settled order and (optionally) free its table.
  ///
  /// "Settled" = every line is PAID **or CANCELED**, with at least one PAID.
  /// The old callers required `every state == 'PAID'`, so a single voided
  /// (CANCELED) line — or a leftover non-ticketed line — left the order stuck
  /// un-completed and its table occupied forever. Treating CANCELED as settled
  /// fixes that.
  ///
  /// When settled: bumps the order to [paidStatus] via [updateOrderStatus]
  /// (`queueSyncOperation: false`, so it stays DB-only and joins this
  /// transaction — the caller runs any network sync AFTER this returns) and,
  /// when [clearTable], frees every table pointing at the order. Status change
  /// and table free commit together, so a payment can never leave the table
  /// occupied while the order reads as paid.
  ///
  /// Returns true when the order was settled & updated, false when outstanding
  /// (PENDING/unsettled) lines remain.
  /// Make [orderId] belong to whoever is at the till right now.
  ///
  /// A shift change used to strand tables: they stayed stamped with the
  /// cashier who rang them up and with that cashier's session, so the money
  /// collected by the next person landed in a session that had already been
  /// Z-ed — and once that session closed, [updateOrder] refused to touch the
  /// order at all. Rather than make the handover a separate act somebody has
  /// to remember, ownership simply follows the work: paying or modifying an
  /// order claims it.
  ///
  /// Touches `takenBy` and the session, and nothing else that carries meaning:
  ///   * `waiterId` (`servedBy` upstream) stays put, so the waiter who served
  ///     the table keeps their attribution, settlement and per-waiter Z line.
  ///   * `source` stays put, so a WAITER-raised order is still recognised as
  ///     one and the cashier edit lock keeps applying after the claim.
  ///
  /// A no-op when the order is already theirs, when nobody is logged in, or
  /// when the order is gone — this is called from payment paths and must never
  /// be the thing that fails one. Marks the order unsynced so the new owner
  /// reaches the backend on the next push.
  /// Stand-in [OrderItem] for a line that was deleted outright.
  ///
  /// The surviving-items map has nothing to copy from when the whole line is
  /// gone, so the pre-delete snapshot supplies the name and price. Falls back
  /// to the product id when even that is missing — a cancellation ticket
  /// reading "1x #57" is poor, but it is a great deal better than the kitchen
  /// never being told.
  OrderItem _removedItemTemplate(String key, List<OrderProduct> before) {
    final parts = key.split(':');
    final productId = int.parse(parts[0]);
    final variantId = int.parse(parts[1]);
    final row = before.where((r) {
      return r.productId == productId && (r.variantId ?? -1) == variantId;
    }).firstOrNull;
    return OrderItem(
      productId: productId,
      // Filled in by [_printKitchenCancellation], which resolves every name
      // in one query rather than one per cancelled line.
      productName: '#$productId',
      variantId: variantId == -1 ? null : variantId,
      finalPrice: row?.unitaryPrice ?? 0,
      quantity: 0,
    );
  }

  /// Print the "stop making this" ticket, to the stations that were told to
  /// make it.
  ///
  /// Routed through the ordinary KDS path so it reaches exactly the printers
  /// the food went to — a void that went somewhere else would be worse than
  /// none. Swallows its own failures: the order has already been changed, and
  /// a dead printer must not surface as a failed edit.
  Future<void> _printKitchenCancellation(
    int orderId,
    List<OrderItem> cancelled, {
    CurrentOrder? snapshot,
  }) async {
    final ref = _ref;
    if (ref == null || cancelled.isEmpty) return;
    try {
      if (!ref.read(settingsProvider).printKitchenCancellations) return;
      final printing = ref.read(printingServiceProvider);
      if (!printing.config.kdsEnabled) return;

      // [snapshot] is for the delete path, where the order no longer exists
      // by the time this runs — the ticket still needs its code and table to
      // be any use to the pass.
      final order = snapshot ?? await getOrderById(orderId);
      if (order == null) return;
      await printing.printKdsTicket(
        order: order.copyWith(items: await _namedForKitchen(cancelled)),
        cashierName: ref.read(currentUserProvider)?.firstName,
        purpose: KdsPrintPurpose.cancel,
      );
    } catch (e) {
      _logger.error('Kitchen cancellation ticket failed for #$orderId: $e');
    }
  }

  /// Fill in product names for cancellation lines.
  ///
  /// `order_products` stores no name — it is resolved from the catalogue on
  /// read — so a line rebuilt from a deleted row arrives as "#57". One batched
  /// lookup rather than one per line: a whole-order void can be forty lines,
  /// and the pass is waiting.
  ///
  /// A product deleted from the catalogue since it was ordered keeps its id
  /// as its name. Ugly, and still the right answer: the kitchen is told to
  /// stop making something rather than not told at all.
  Future<List<OrderItem>> _namedForKitchen(List<OrderItem> items) async {
    final unnamed = {
      for (final i in items)
        if (i.productName.startsWith('#')) i.productId,
    };
    if (unnamed.isEmpty) return items;
    final rows = await (_database.select(
      _database.products,
    )..where((p) => p.id.isIn(unnamed.toList()))).get();
    final nameById = {for (final r in rows) r.id: r.name};
    return [
      for (final i in items)
        nameById[i.productId] == null
            ? i
            : i.copyWith(productName: nameById[i.productId]),
    ];
  }

  /// Everything on this order the kitchen has been asked to cook, as
  /// cancellation lines — for a whole-order void or delete.
  Future<List<OrderItem>> _allSentToKitchen(int orderId) async {
    final rows =
        await (_database.select(_database.orderProducts)..where(
              (t) =>
                  t.orderId.equals(orderId) &
                  t.kdsPrintedQuantity.isBiggerThanValue(0.0),
            ))
            .get();
    return _namedForKitchen([
      for (final r in rows)
        OrderItem(
          id: r.id,
          productId: r.productId,
          productName: '#${r.productId}',
          variantId: r.variantId,
          finalPrice: r.unitaryPrice,
          quantity: r.kdsPrintedQuantity,
          kdsPrintQuantity: r.kdsPrintedQuantity,
          note: r.note,
          courseNo: normalizeCourseNo(r.courseNo),
        ),
    ]);
  }

  Future<bool> claimOrderForCurrentUser(int orderId) async {
    final ref = _ref;
    if (ref == null) return false;
    try {
      final user = ref.read(currentUserProvider);
      if (user == null) return false;

      final order = await (_database.select(
        _database.orders,
      )..where((o) => o.id.equals(orderId))).getSingleOrNull();
      if (order == null) return false;

      final session = ref.read(currentSessionProvider);
      final sessionMoves =
          session != null &&
          session.status == 'active' &&
          order.sessionId != session.id;
      if (order.takenBy == user.id && !sessionMoves) return false;

      // An order changing hands across a session boundary has to change
      // Z-DAY with it, not just session. The two are what the reports scope
      // on — the X / Z prints select by `sessionId`, `generateZDayReport`
      // selects by date — so moving one without the other put the order in
      // the new shift's Z and the old shift's day at the same time, and the
      // two reports disagreed about which day its money belonged to.
      //
      // Read from the session being moved INTO rather than from the clock:
      // a session opened before midnight keeps its own Z-day afterwards, and
      // `_zDayForSessionId` resolves that through the session's Z the same
      // way saveOrder does. Matches `_rehomeIfSessionClosed`, which has
      // always moved both.
      final movedZDay = sessionMoves
          ? await _zDayForSessionId(session.id)
          : null;

      await (_database.update(
        _database.orders,
      )..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(
          takenBy: Value(user.id),
          // Absent, not null: "leave the session alone" has to stay
          // distinguishable from "clear it".
          sessionId: sessionMoves ? Value(session.id) : const Value.absent(),
          zDay: movedZDay == null ? const Value.absent() : Value(movedZDay),
          isSynced: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (order.takenBy != user.id) {
        _logger.info(
          'Order #$orderId claimed by user ${user.id} '
          '(was ${order.takenBy})',
        );
        await _logService.logOrderUpdated(
          orderId,
          'Order claimed by user ${user.id}',
        );
      }
      return true;
    } catch (e) {
      // Never let a claim break a payment. The order stays with its previous
      // owner, which is wrong but harmless; the next touch claims it again.
      _logger.error('Claim failed for order #$orderId: $e');
      return false;
    }
  }

  /// Move an order out of a session that has already been Z-ed and onto the
  /// one open now, returning the session it should be accounted to.
  ///
  /// The guard this replaces threw outright: "cannot modify an order from a
  /// closed Z-report session". Correct as bookkeeping — you cannot add a line
  /// to a shift that has been reported — but useless as behaviour, because
  /// the order in front of the cashier is a real table with real people at
  /// it. They inherited it from the last shift and now cannot touch it.
  ///
  /// So the order moves instead. Its takings are accounted to the session and
  /// the Z-day actually collecting them, which is the honest answer anyway:
  /// the money is coming in now, not last night.
  ///
  /// Returns null when there is nowhere to move it to — no session is open —
  /// and the caller must then still refuse, because there is no shift to
  /// account the change to.
  Future<({int sessionId, DateTime zDay})?> _rehomeIfSessionClosed(
    Order existing,
  ) async {
    if (existing.sessionId == null) return null;
    final session = await (_database.select(
      _database.cashSessions,
    )..where((t) => t.id.equals(existing.sessionId!))).getSingleOrNull();
    if (session == null || session.status != 'ended') return null;

    final open = _ref?.read(currentSessionProvider);
    if (open == null || open.status != 'active') return null;

    final zDay = _currentZDay();
    await (_database.update(
      _database.orders,
    )..where((o) => o.id.equals(existing.id))).write(
      OrdersCompanion(
        sessionId: Value(open.id),
        zDay: Value(zDay),
        isSynced: const Value(false),
        updatedAt: Value(DateTime.now()),
      ),
    );
    _logger.info(
      'Order #${existing.id} re-homed from closed session '
      '${existing.sessionId} to ${open.id} (z-day $zDay)',
    );
    await _logService.logOrderUpdated(
      existing.id,
      'Order moved from closed session ${existing.sessionId} '
      'to open session ${open.id}',
    );
    return (sessionId: open.id, zDay: zDay);
  }

  Future<bool> settleOrderAndFreeTable(
    int orderId, {
    required String paidStatus,
    required bool clearTable,
  }) async {
    return _database.transaction(() async {
      final products = await (_database.select(
        _database.orderProducts,
      )..where((p) => p.orderId.equals(orderId))).get();
      if (products.isEmpty) return false;

      // Same predicate the floor sweep uses, so the two can never disagree
      // about what "settled" means.
      if (!isOrderSettled(
        products.map((p) => settlementState(p.state, p.ticketId)),
      )) {
        return false;
      }

      await updateOrderStatus(orderId, paidStatus, queueSyncOperation: false);
      if (clearTable) {
        await freeTablesForOrder(orderId);
      }
      // NOTE: the claim is NOT made here. Settling runs inside this
      // transaction and the claim writes the same row; it is made by the
      // callers once the transaction has committed, so a claim failure can
      // never roll back a completed payment.
      return true;
    });
  }

  /// Release any table still holding an order that cannot be sitting at it.
  ///
  /// The floor's occupancy is a pointer (`area_tables.order_id`) that whichever
  /// code path finishes an order is expected to clear. That is one obligation
  /// spread across six or seven paths — payment, split payment, quick cash,
  /// waiter settlement, cancellation, session close, the LAN server — and a
  /// path that forgets, or one that fails halfway, strands a table showing
  /// occupied with nobody at it. The floor then needs a manual clear, by
  /// someone who knows that is even possible.
  ///
  /// So rather than add another place that must remember, this recomputes the
  /// answer from the orders themselves and fixes whatever it finds. Cheap
  /// enough to run whenever the floor is looked at, and it repairs tables
  /// stranded by bugs that have not been written yet as readily as by ones
  /// that have.
  ///
  /// Returns how many tables it released, for logging.
  ///
  /// [freeOnPayment] must be the `autoClearTableAfterPaying` setting. With it
  /// off, a paid table stays held on purpose — the customers are still sitting
  /// there — and only dangling or cancelled orders are swept.
  Future<int> reconcileTableOccupancy({required bool freeOnPayment}) async {
    final held = await (_database.select(
      _database.areaTables,
    )..where((t) => t.orderId.isNotNull())).get();
    if (held.isEmpty) return 0;

    final orderIds = held.map((t) => t.orderId!).toSet();
    final orders = await (_database.select(
      _database.orders,
    )..where((o) => o.id.isIn(orderIds))).get();
    final orderById = {for (final o in orders) o.id: o};

    final lines = await (_database.select(
      _database.orderProducts,
    )..where((p) => p.orderId.isIn(orderIds))).get();
    final statesByOrder = <int, List<String>>{};
    for (final line in lines) {
      (statesByOrder[line.orderId] ??= []).add(
        settlementState(line.state, line.ticketId),
      );
    }

    final release = <int>[];
    for (final table in held) {
      final order = orderById[table.orderId!];
      final reason = tableReleaseReason(
        orderExists: order != null,
        orderStatus: order?.status ?? '',
        lineStates: statesByOrder[table.orderId!] ?? const [],
        freeOnPayment: freeOnPayment,
      );
      if (reason != null) {
        release.add(table.id);
        _logger.info(
          'Releasing table ${table.name} held by order '
          '${table.orderId}: ${reason.name}',
        );
      }
    }
    if (release.isEmpty) return 0;

    await (_database.update(_database.areaTables)
          ..where((t) => t.id.isIn(release)))
        .write(const AreaTablesCompanion(orderId: Value(null)));
    return release.length;
  }

  /// Free every table currently holding an order that belongs to [sessionId].
  /// Used at session close so the floor starts empty for the next session —
  /// covers orders paid earlier in the shift (when "auto-clear table on pay" is
  /// off) as well as ones just settled at close.
  Future<void> clearTablesForSession(int sessionId) async {
    final orderIds = await (_database.select(
      _database.orders,
    )..where((o) => o.sessionId.equals(sessionId))).map((o) => o.id).get();
    if (orderIds.isEmpty) return;
    await (_database.update(_database.areaTables)
          ..where((t) => t.orderId.isIn(orderIds)))
        .write(const AreaTablesCompanion(orderId: Value(null)));
  }

  // Transfer order from one table to another
  Future<void> transferOrderToTable(
    int orderId,
    int oldTableId,
    int newTableId,
  ) async {
    // Move both table pointers and the order's tableId atomically so a crash
    // can't leave the old table freed while the order still points at it, or
    // two tables pointing at one order.
    //
    // Critically, mark the order isSynced=false in the SAME write: the table
    // move is an order change that must reach the server. The periodic
    // getOrdersForSync sweep only re-pushes unsynced orders, so without this
    // the transfer was silently never propagated (server kept the old table).
    await _database.transaction(() async {
      // Refuse to land on an occupied table. The table picker only offers a
      // transfer to an empty one, so the floor cannot reach this today — but
      // setTableOrderId overwrites the pointer blindly, and an overwrite here
      // would leave the displaced order still naming the table while the table
      // names this one: a live bill on a floor that shows nobody sitting there,
      // and reconcileTableOccupancy only ever releases tables, so it would
      // never repair it.
      //
      // Checked INSIDE the transaction, like the waiter-order table check, so
      // two tills transferring onto the same free table cannot both pass a
      // pre-check and then both write.
      final target = await (_database.select(
        _database.areaTables,
      )..where((t) => t.id.equals(newTableId))).getSingleOrNull();
      if (target?.orderId != null && target!.orderId != orderId) {
        throw Exception(
          'Table ${target.name} already has an open order — settle or move it first',
        );
      }

      await clearTableOrder(oldTableId);
      await setTableOrderId(newTableId, orderId);
      await (_database.update(
        _database.orders,
      )..where((tbl) => tbl.id.equals(orderId))).write(
        OrdersCompanion(
          tableId: Value(newTableId),
          isSynced: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });

    // Log the transfer
    await _logService.logOrderUpdated(
      orderId,
      'Order transferred from table $oldTableId to table $newTableId',
    );
    final transferred = await (_database.select(
      _database.orders,
    )..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();
    final transferCode = transferred?.code ?? '#$orderId';
    _audit(
      (log, uid, uname) => log.logOrderTransferred(
        transferCode,
        '$oldTableId',
        '$newTableId',
        userId: uid,
        username: uname,
      ),
    );

    // Push immediately when online; the isSynced=false flag above guarantees
    // the periodic sweep retries if this fails or we're offline. Detached, like
    // every other prompt push here — the table has already moved locally, so
    // the cashier must not watch a network round-trip to see it. See [_detach].
    if (_syncService != null &&
        _isOnlineCallback != null &&
        _isOnlineCallback!()) {
      _detach('Transfer sync for order #$orderId', () async {
        final synced = await _syncService!.syncSingleOrder(
          orderId,
          deadline: _promptPushDeadline,
        );
        if (synced) {
          await _syncService!.syncTicketsForOrder(
            orderId,
            deadline: _promptPushDeadline,
          );
        }
      });
    }
  }

  // Get all orders with full details including user, products, discounts, TVA, and paid amounts
  Future<List<OrderFullDetails>> getAllOrdersWithFullDetails() async {
    final orders = await (_database.select(
      _database.orders,
    )..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)])).get();
    return _buildOrderFullDetailsBatch(orders);
  }

  /// Local calendar day as 'YYYY-MM-DD' — the stable prefix shared by every
  /// datetime text encoding (legacy UTC/space and current local/'T'). Used to
  /// range-filter on the day rather than the full timestamp, which sorts
  /// inconsistently across encodings.
  static String _dayStr(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Expression<bool> _dateOnOrAfterDay(
    GeneratedColumn<DateTime> col,
    DateTime day,
  ) =>
      CustomExpression<bool>("substr(${col.name}, 1, 10) >= '${_dayStr(day)}'");

  Expression<bool> _dateOnOrBeforeDay(
    GeneratedColumn<DateTime> col,
    DateTime day,
  ) =>
      CustomExpression<bool>("substr(${col.name}, 1, 10) <= '${_dayStr(day)}'");

  // Get paginated orders with full details - real database-level pagination
  /// The per-session order number a search box query asks for ("12" or
  /// "#12"), or null when it is not one or the feature is switched off.
  int? _searchedOrderNo(String query) {
    if (_ref?.read(settingsProvider).showOrderNumberInLists != true) {
      return null;
    }
    final q = query.trim();
    return int.tryParse(q.startsWith('#') ? q.substring(1) : q);
  }

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
  }) async {
    final orders = _database.orders;
    // Every filter is SQL, so the count and the page are both answered by the
    // database: the history is never loaded to show ten rows of it.
    final filter = await _ordersFilter(
      statusFilter: statusFilter,
      typeFilter: typeFilter,
      unpaidOnly: unpaidOnly,
      searchQuery: searchQuery,
      customerId: customerId,
      cashierId: cashierId,
      tableId: tableId,
      waiterId: waiterId,
      sessionIds: {
        if (sessionId != null) sessionId,
        ...?sessionIds,
      },
      startDate: startDate,
      endDate: endDate,
      tagIds: tagIds,
      untagged: untagged,
    );

    final count = orders.id.count();
    final totalCount = await (_database.selectOnly(orders)
          ..addColumns([count])
          ..where(filter))
        .map((r) => r.read(count) ?? 0)
        .getSingle();

    final totalPages = (totalCount / pageSize).ceil();
    if (totalPages == 0) {
      return PaginatedOrders(
        orders: [],
        totalCount: 0,
        page: page,
        pageSize: pageSize,
        totalPages: 0,
      );
    }

    final mode = sortAscending ? OrderingMode.asc : OrderingMode.desc;
    final Expression sortBy = switch (sortColumn) {
      'id' => orders.id,
      'code' => orders.code,
      'status' => orders.status,
      _ => orders.createdAt,
    };
    final pageOrders = await (_database.select(orders)
          ..where((_) => filter)
          ..orderBy([
            (_) => OrderingTerm(expression: sortBy, mode: mode),
            // Ties (same second, same status) would otherwise move between
            // pages from one query to the next.
            (tbl) => OrderingTerm(expression: tbl.id, mode: mode),
          ])
          ..limit(pageSize, offset: page * pageSize))
        .get();

    // Batch Z-lock: one query for all session IDs on this page (like tickets' _enrichTickets)
    final pageSessionIds = {
      for (final o in pageOrders)
        if (o.sessionId != null) o.sessionId!,
    };
    final endedSessionIds = <int>{};
    if (pageSessionIds.isNotEmpty) {
      final sessions = await (_database.select(
        _database.cashSessions,
      )..where((s) => s.id.isIn(pageSessionIds))).get();
      for (final s in sessions) {
        if (s.status == 'ended') endedSessionIds.add(s.id);
      }
    }

    return PaginatedOrders(
      orders: await _buildOrderFullDetailsBatch(
        pageOrders,
        endedSessionIds: endedSessionIds,
      ),
      totalCount: totalCount,
      page: page,
      pageSize: pageSize,
      totalPages: totalPages,
    );
  }

  /// `%`, `_` and the escape itself taken literally in a LIKE pattern.
  static String _likeContains(String needle) =>
      '%${needle.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

  /// The orders list's filters as one SQL predicate on `orders`.
  ///
  /// Search keeps the meaning it had when it ran in Dart: a substring of the
  /// code, the reference, the cashier's username or the customer's display
  /// label, or the per-session number. Users and customers are matched in Dart
  /// (their labels have fallbacks SQL would have to duplicate) and passed in as
  /// id lists — both tables are small next to the orders.
  Future<Expression<bool>> _ordersFilter({
    String? statusFilter,
    String? typeFilter,
    bool unpaidOnly = false,
    bool excludeCanceled = false,
    String? searchQuery,
    int? customerId,
    int? cashierId,
    int? tableId,
    int? waiterId,
    Set<int> sessionIds = const {},
    DateTime? startDate,
    DateTime? endDate,
    Set<int> tagIds = const {},
    bool untagged = false,
  }) async {
    final t = _database.orders;
    final parts = <Expression<bool>>[
      if (statusFilter != null && statusFilter != 'ALL')
        t.status.equals(statusFilter),
      if (excludeCanceled) t.status.equals('CANCELED').not(),
      if (typeFilter != null && typeFilter != 'ALL') t.type.equals(typeFilter),
      if (customerId != null) t.clientId.equals(customerId),
      if (cashierId != null) t.takenBy.equals(cashierId),
      if (tableId != null) t.tableId.equals(tableId),
      if (waiterId != null) t.waiterId.equals(waiterId),
      if (sessionIds.isNotEmpty) t.sessionId.isIn(sessionIds),
      // Day-prefix comparison — dates are stored as TEXT and legacy rows may
      // use the UTC/space encoding that sorts before 'T', which would drop
      // same-day orders on the range's start day. See _dayStr / ticket filter.
      if (startDate != null) _dateOnOrAfterDay(t.date, startDate),
      if (endDate != null) _dateOnOrBeforeDay(t.date, endDate),
      if (unpaidOnly) unpaidOrderSql,
    ];

    if (tagIds.isNotEmpty || untagged) {
      // tag_ids is a comma list ("1,4"); fenced with commas so 1 never
      // matches 12.
      const fenced =
          "(',' || REPLACE(COALESCE(orders.tag_ids, ''), ' ', '') || ',')";
      parts.add(CustomExpression<bool>('(${[
        if (untagged) "TRIM(COALESCE(orders.tag_ids, '')) = ''",
        for (final id in tagIds) "$fenced LIKE '%,$id,%'",
      ].join(' OR ')})'));
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      final needle = searchQuery.toLowerCase();
      final pattern = _likeContains(searchQuery);
      final searchNo = _searchedOrderNo(searchQuery);
      final userIds = [
        for (final u in await _database.select(_database.users).get())
          if (u.username.toLowerCase().contains(needle)) u.id,
      ];
      final customerIds = [
        for (final c in await _database.select(_database.customers).get())
          if (c.displayLabel.toLowerCase().contains(needle)) c.id,
      ];
      parts.add(Expression.or([
        t.code.like(pattern, escapeChar: r'\'),
        t.reference.like(pattern, escapeChar: r'\'),
        if (searchNo != null) t.sessionOrderNo.equals(searchNo),
        if (userIds.isNotEmpty) t.takenBy.isIn(userIds),
        if (customerIds.isNotEmpty) t.clientId.isIn(customerIds),
      ]));
    }

    return Expression.and(parts);
  }

  /// "Is this order unpaid?" — the canonical check behind the orders-screen
  /// unpaid chip, the resume picker and the close-time unpaid gate.
  ///
  /// Same formula as [getOrderTotals] (lines with their components, less
  /// manual discounts, less the order's discount %), against the paid,
  /// uncancelled tickets; an empty order and a CANCELED one are not unpaid.
  /// The 0.005 epsilon keeps rounding from flagging a fully-paid order.
  /// Correlated on `orders.id`, so it filters inside the query.
  static final Expression<bool> unpaidOrderSql = CustomExpression<bool>(
    "(orders.status <> 'CANCELED' AND $_orderTotalSql > 0 AND "
    '(SELECT COALESCE(SUM(t.amount), 0) FROM tickets t '
    'WHERE t.order_id = orders.id AND t.is_paid = 1 AND t.is_cancelled = 0)'
    ' + 0.005 < $_orderTotalSql)',
  );

  static const _orderLinesSql =
      '(SELECT COALESCE(SUM(((op.unitary_price + COALESCE((SELECT SUM(c.price * c.quantity) '
      'FROM order_product_components c WHERE c.order_product_id = op.id), 0))'
      ' - op.manual_discount) * op.quantity), 0) '
      'FROM order_products op WHERE op.order_id = orders.id)';

  static const _orderTotalSql =
      '($_orderLinesSql * (1 - COALESCE(orders.discount_percentage, 0) / 100.0))';

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
  }) async {
    // Orders are born COMPLETED (that's the cloud-terminal order status —
    // payment is tracked on the PRODUCTS / tickets, not order.status), so
    // status says nothing here: the unpaid test runs in SQL, and only what is
    // still owed ever leaves the database. CANCELED is excluded by it.
    final searching = (search ?? '').trim().isNotEmpty;
    final needle = (customerQuery ?? '').trim().toLowerCase();
    final filteredInDart = searching || needle.isNotEmpty;

    final query = _database.select(_database.orders)
      ..where((_) => unpaidOrderSql)
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]);
    if (typeFilter != null && typeFilter != 'ALL') {
      query.where((tbl) => tbl.type.equals(typeFilter));
    }
    if (tableId != null) query.where((tbl) => tbl.tableId.equals(tableId));
    if (cashierId != null) query.where((tbl) => tbl.takenBy.equals(cashierId));
    if (!filteredInDart) query.limit(limit);

    final candidates = await query.get();
    if (!filteredInDart) return candidates;

    // The candidates are only the unpaid orders, so matching customers in
    // Dart (one batched load) stays cheap and keeps [orderMatchesSearch].
    final customers = <int, Customer>{};
    final ids = {
      for (final o in candidates)
        if (o.clientId != null) o.clientId!,
    };
    if (ids.isNotEmpty) {
      for (final c in await (_database.select(
        _database.customers,
      )..where((c) => c.id.isIn(ids))).get()) {
        customers[c.id] = c;
      }
    }

    final result = <Order>[];
    for (final order in candidates) {
      final customer =
          order.clientId == null ? null : customers[order.clientId!];
      if (searching &&
          !orderMatchesSearch(order, search!, customer: customer)) {
        continue;
      }
      if (needle.isNotEmpty) {
        if (customer == null) continue;
        final fullName = '${customer.firstName} ${customer.lastName}'
            .toLowerCase();
        if (!fullName.contains(needle)) continue;
      }
      result.add(order);
      if (result.length >= limit) break;
    }
    return result;
  }

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
  }) async {
    if (orderIds.isEmpty) return const {};

    final lines = await (_database.select(
      _database.orderProducts,
    )..where((p) => p.orderId.isIn(orderIds))).get();
    if (lines.isEmpty) {
      return {for (final id in orderIds) id: const OrderContentSummary()};
    }

    final productIds = lines.map((l) => l.productId).toSet().toList();
    final products = await (_database.select(
      _database.products,
    )..where((p) => p.id.isIn(productIds))).get();
    final nameById = {for (final p in products) p.id: p.name};

    final byOrder = <int, List<OrderProduct>>{};
    for (final l in lines) {
      // A cancelled line is not part of what the waiter is carrying back.
      if (l.state == 'CANCELED') continue;
      byOrder.putIfAbsent(l.orderId, () => []).add(l);
    }

    final result = <int, OrderContentSummary>{};
    for (final id in orderIds) {
      final own = byOrder[id] ?? const [];
      final units = own.fold<double>(0, (sum, l) => sum + l.quantity);
      final names = own.take(previewLimit).map((l) {
        final qty = l.quantity == l.quantity.roundToDouble()
            ? l.quantity.toStringAsFixed(0)
            : l.quantity.toStringAsFixed(3);
        return '${qty}x ${nameById[l.productId] ?? '#${l.productId}'}';
      }).toList();
      result[id] = OrderContentSummary(
        units: units,
        lineCount: own.length,
        preview: names,
        hiddenLines: own.length > previewLimit ? own.length - previewLimit : 0,
      );
    }
    return result;
  }

  Future<Map<int, double>> getOrderTotals(List<int> orderIds) async {
    if (orderIds.isEmpty) return const {};

    final orders = await (_database.select(
      _database.orders,
    )..where((o) => o.id.isIn(orderIds))).get();
    final discountPctById = {
      for (final o in orders) o.id: o.discountPercentage,
    };

    final products = await (_database.select(
      _database.orderProducts,
    )..where((p) => p.orderId.isIn(orderIds))).get();
    if (products.isEmpty) {
      return {for (final id in orderIds) id: 0.0};
    }

    final productIds = products.map((p) => p.id).toList();
    final allComps = await (_database.select(
      _database.orderProductComponents,
    )..where((c) => c.orderProductId.isIn(productIds))).get();
    final compsByProductId = <int, List<OrderProductComponent>>{};
    for (final c in allComps) {
      compsByProductId.putIfAbsent(c.orderProductId, () => []).add(c);
    }

    final beforeDiscount = <int, double>{};
    for (final p in products) {
      final comps = compsByProductId[p.id] ?? const <OrderProductComponent>[];
      final componentTotal = comps.fold<double>(
        0.0,
        (sum, c) => sum + (c.price * c.quantity),
      );
      final itemTotal =
          ((p.unitaryPrice + componentTotal) - p.manualDiscount) * p.quantity;
      beforeDiscount[p.orderId] = (beforeDiscount[p.orderId] ?? 0) + itemTotal;
    }

    final result = <int, double>{};
    for (final id in orderIds) {
      final before = beforeDiscount[id] ?? 0;
      final pct = discountPctById[id] ?? 0;
      result[id] = before - (before * pct / 100);
    }
    return result;
  }

  // Helper method to build OrderFullDetails from an Order
  Future<OrderFullDetails> _buildOrderFullDetails(
    Order order, {
    Set<int>? endedSessionIds,
  }) async =>
      (await _buildOrderFullDetailsBatch(
        [order],
        endedSessionIds: endedSessionIds,
      )).single;

  /// `isIn` in slices, under SQLite's bound-variable limit.
  static Future<List<R>> _fetchIn<R>(
    Iterable<int> ids,
    Future<List<R>> Function(List<int> slice) fetch,
  ) async {
    final all = ids.toSet().toList();
    final out = <R>[];
    for (var i = 0; i < all.length; i += 900) {
      out.addAll(await fetch(
          all.sublist(i, i + 900 > all.length ? all.length : i + 900)));
    }
    return out;
  }

  /// [OrderFullDetails] for a list of orders, in that order. One query per
  /// table for the whole list — a page of the orders screen used to cost a
  /// query per line, per component and per ticket.
  Future<List<OrderFullDetails>> _buildOrderFullDetailsBatch(
    List<Order> orders, {
    Set<int>? endedSessionIds,
  }) async {
    if (orders.isEmpty) return const [];
    final db = _database;

    final lines = await _fetchIn(
      orders.map((o) => o.id),
      (ids) => (db.select(db.orderProducts)
            ..where((t) => t.orderId.isIn(ids))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get(),
    );
    final linesByOrder = <int, List<OrderProduct>>{};
    for (final l in lines) {
      linesByOrder.putIfAbsent(l.orderId, () => []).add(l);
    }

    final orderComponents = await _fetchIn(
      lines.map((l) => l.id),
      (ids) => (db.select(db.orderProductComponents)
            ..where((t) => t.orderProductId.isIn(ids))
            ..orderBy([(t) => OrderingTerm.asc(t.id)]))
          .get(),
    );
    final compsByLine = <int, List<OrderProductComponent>>{};
    for (final c in orderComponents) {
      compsByLine.putIfAbsent(c.orderProductId, () => []).add(c);
    }

    final users = {
      for (final u in await _fetchIn(
        orders.where((o) => o.takenBy != null).map((o) => o.takenBy!),
        (ids) => (db.select(db.users)..where((t) => t.id.isIn(ids))).get(),
      ))
        u.id: u,
    };
    final tables = {
      for (final t in await _fetchIn(
        orders.where((o) => o.tableId != null).map((o) => o.tableId!),
        (ids) =>
            (db.select(db.areaTables)..where((t) => t.id.isIn(ids))).get(),
      ))
        t.id: t,
    };
    final customers = {
      for (final c in await _fetchIn(
        orders.where((o) => o.clientId != null).map((o) => o.clientId!),
        (ids) =>
            (db.select(db.customers)..where((t) => t.id.isIn(ids))).get(),
      ))
        c.id: c,
    };
    final products = {
      for (final p in await _fetchIn(
        lines.map((l) => l.productId),
        (ids) => (db.select(db.products)..where((t) => t.id.isIn(ids))).get(),
      ))
        p.id: p,
    };
    final variants = {
      for (final v in await _fetchIn(
        lines.where((l) => l.variantId != null).map((l) => l.variantId!),
        (ids) => (db.select(db.productVariants)..where((t) => t.id.isIn(ids)))
            .get(),
      ))
        v.id: v,
    };
    final components = {
      for (final c in await _fetchIn(
        orderComponents.map((c) => c.componentId),
        (ids) =>
            (db.select(db.components)..where((t) => t.id.isIn(ids))).get(),
      ))
        c.id: c,
    };
    final tickets = {
      for (final t in await _fetchIn(
        lines.where((l) => l.ticketId != null).map((l) => l.ticketId!),
        (ids) => (db.select(db.tickets)..where((t) => t.id.isIn(ids))).get(),
      ))
        t.id: t,
    };
    final ended = endedSessionIds ??
        {
          for (final s in await _fetchIn(
            orders.where((o) => o.sessionId != null).map((o) => o.sessionId!),
            (ids) => (db.select(db.cashSessions)..where((t) => t.id.isIn(ids)))
                .get(),
          ))
            if (s.status == 'ended') s.id,
        };

    final result = <OrderFullDetails>[];
    for (final order in orders) {
      final orderProducts = linesByOrder[order.id] ?? const <OrderProduct>[];
      final customer =
          order.clientId == null ? null : customers[order.clientId!];

      // Calculate totals
      double subtotal = 0.0;
      double itemDiscount = 0.0;
      double totalTva = 0.0;
      double totalPaid = 0.0;
      final seenTicketIds = <int>{};

      final itemDetails = <OrderItemDetails>[];
      for (final product in orderProducts) {
        // Calculate component total using stored prices
        double componentTotal = 0.0;
        final componentDetails = <ComponentDetails>[];
        for (final orderComp
            in compsByLine[product.id] ?? const <OrderProductComponent>[]) {
          componentTotal += orderComp.price * orderComp.quantity;
          final component = components[orderComp.componentId];
          if (component != null) {
            componentDetails.add(
              ComponentDetails(
                name: component.name,
                quantity: orderComp.quantity,
                price: orderComp.price,
              ),
            );
          }
        }

        // unitaryPrice = basePrice + tva - preDiscount (all baked in).
        // Subtract unitaryTva so subtotal is tax-exclusive (HT); totalTva is added
        // back later in the final total formula to avoid double-counting.
        // productDiscount covers both the pre-discount and any manual discount.
        // totalPrice = itemSubtotal + totalTva - productDiscount
        //            = (unitaryPrice - unitaryTva + unitaryDiscount + componentTotal) * qty + tva*qty - (unitaryDiscount + manualDiscount) * qty
        //            = (unitaryPrice + componentTotal - manualDiscount) * qty  ✓
        final productDiscount =
            (product.unitaryDiscount + product.manualDiscount) *
                product.quantity;
        final itemSubtotal =
            (product.unitaryPrice -
                product.unitaryTva +
                product.unitaryDiscount +
                componentTotal) *
            product.quantity;
        final itemTva = product.unitaryTva * product.quantity;

        subtotal += itemSubtotal;
        itemDiscount += productDiscount;
        totalTva += itemTva;

        // Check if item is paid (has a ticket)
        final isPaid = product.ticketId != null;
        String? ticketNum;
        if (isPaid) {
          final ticket = tickets[product.ticketId!];
          ticketNum = ticket?.num;
          if (ticket != null && seenTicketIds.add(ticket.id)) {
            totalPaid += ticket.amount;
          }
        }

        itemDetails.add(
          OrderItemDetails(
            productName: products[product.productId]?.name ?? 'Unknown Product',
            variantId: product.variantId,
            variantName: product.variantId == null
                ? null
                : variants[product.variantId!]?.name,
            quantity: product.quantity,
            totalPrice: itemSubtotal + itemTva - productDiscount,
            isPaid: isPaid,
            ticketNum: ticketNum,
            components: componentDetails,
            kitchenState: product.state,
            kitchenAt: kitchenSince(product, fallback: order.createdAt),
            preparingAt: product.preparingAt,
            kitchenDoneAt: product.readyAt ?? product.servedAt,
          ),
        );
      }

      // Calculate manual discount from percentage
      final discountPercentage = order.discountPercentage;
      final manualDiscountAmount =
          (subtotal + totalTva - itemDiscount) * (discountPercentage / 100);
      final totalDiscount = itemDiscount + manualDiscountAmount;

      // Calculate final total
      final total = subtotal + totalTva - totalDiscount;

      result.add(OrderFullDetails(
        order: order,
        userName: order.takenBy == null ? null : users[order.takenBy!]?.username,
        tableName: order.tableId == null ? null : tables[order.tableId!]?.name,
        customerName: customer?.displayLabel,
        customerPhone: customer?.phone,
        customerId: customer?.id,
        productCount: orderProducts.length,
        subtotal: subtotal,
        itemDiscount: itemDiscount,
        discountPercentage: discountPercentage,
        manualDiscountAmount: manualDiscountAmount,
        totalDiscount: totalDiscount,
        totalTva: totalTva,
        total: total,
        totalPaid: totalPaid,
        deliveryFee: order.deliveryFee ?? 0.0,
        items: itemDetails,
        isZLocked: order.sessionId != null && ended.contains(order.sessionId!),
      ));
    }
    return result;
  }

  // Get full details for a specific order
  Future<OrderFullDetails> getOrderFullDetails(int orderId) async {
    final order = await (_database.select(
      _database.orders,
    )..where((tbl) => tbl.id.equals(orderId))).getSingle();
    return _buildOrderFullDetails(order);
  }

  // Delete an order
  Future<void> deleteOrder(
    int orderId, {
    bool queueSyncOperation = true,
  }) async {
    final order = await (_database.select(
      _database.orders,
    )..where((tbl) => tbl.id.equals(orderId))).getSingleOrNull();

    // Z-report guard: refuse deletes on orders from a closed session
    if (order?.sessionId != null) {
      final session = await (_database.select(
        _database.cashSessions,
      )..where((tbl) => tbl.id.equals(order!.sessionId!))).getSingleOrNull();
      if (session?.status == 'ended') {
        throw Exception('Cannot delete order from a closed (Z-report) session');
      }
    }

    // Read before the rows are gone; printed at the end, so a dead printer
    // cannot leave the order half-deleted. The order itself is snapshotted
    // too: by print time there is no row left to look its code up from.
    final sentToKitchen = await _allSentToKitchen(orderId);
    final deletedSnapshot = sentToKitchen.isEmpty
        ? null
        : await getOrderById(orderId);
    // An order already CANCELED has had its notification; an empty one took
    // nothing off the books.
    final lineCount =
        await (_database.selectOnly(_database.orderProducts)
              ..addColumns([_database.orderProducts.id.count()])
              ..where(_database.orderProducts.orderId.equals(orderId)))
            .map((r) => r.read(_database.orderProducts.id.count()) ?? 0)
            .getSingle();
    final notifyDeleted =
        order != null && order.status != 'CANCELED' && lineCount > 0;
    final deletedAmount = notifyDeleted
        ? (await getOrderTotals([orderId]))[orderId] ?? 0.0
        : 0.0;

    if (order != null && order.isSynced && queueSyncOperation) {
      // Try to delete from server if online, otherwise queue
      if (_syncService != null && _isOnlineCallback != null) {
        final isOnline = _isOnlineCallback!();
        if (isOnline) {
          try {
            await _syncService!.deleteOrderEntity(
              entityId: orderId,
              orderCode: order.code,
              isOnline: true,
            );
            _logger.info('Deleted order code=${order.code} from server');
          } catch (e) {
            _logger.error('Failed to delete order from server: $e');
            // Queue for later if immediate delete failed
            await _queueOrderDelete(orderId, order.code);
          }
        } else {
          // Offline - queue the delete
          await _queueOrderDelete(orderId, order.code);
        }
      } else {
        // No sync service available - just queue
        await _queueOrderDelete(orderId, order.code);
      }
    } else if (order != null && !order.isSynced) {
      _logger.info(
        'Deleting local-only order #$orderId (not synced, no queue needed)',
      );
    }

    // CASCADE DELETE: Delete all tickets associated with this order
    final tickets = await (_database.select(
      _database.tickets,
    )..where((tbl) => tbl.orderId.equals(orderId))).get();
    for (final ticket in tickets) {
      // Delete the ticket
      await (_database.delete(
        _database.tickets,
      )..where((tbl) => tbl.id.equals(ticket.id))).go();
      _logger.info(
        'Deleted ticket #${ticket.id} (num=${ticket.num}) for order #$orderId',
      );
    }

    // Delete order product components first
    final orderProducts = await (_database.select(
      _database.orderProducts,
    )..where((tbl) => tbl.orderId.equals(orderId))).get();
    for (final product in orderProducts) {
      await (_database.delete(
        _database.orderProductComponents,
      )..where((tbl) => tbl.orderProductId.equals(product.id))).go();
    }

    // Delete order products
    await (_database.delete(
      _database.orderProducts,
    )..where((tbl) => tbl.orderId.equals(orderId))).go();

    // Log order deletion BEFORE deleting the order
    if (order != null) {
      await _logService.logOrderDeleted(
        orderId,
        'Order deleted: code=${order.code}',
      );
    }

    // Delete the order
    await (_database.delete(
      _database.orders,
    )..where((tbl) => tbl.id.equals(orderId))).go();

    // Emit event
    _emitEvent(OrderDeletedEvent(orderId: orderId));

    final reader = _ref;
    if (notifyDeleted && reader != null) {
      final actor = reader.read(currentUserProvider);
      notifyOrderCancelled(
        reader.read,
        orderCode: order.code,
        amount: deletedAmount,
        byName: actor?.effectiveDisplayName,
        byId: actor?.id,
        afterKitchen: sentToKitchen.isNotEmpty,
        deleted: true,
      );
    }

    // The order is gone from the till; the food is still on the pass.
    if (sentToKitchen.isNotEmpty) {
      await _printKitchenCancellation(
        orderId,
        sentToKitchen,
        snapshot: deletedSnapshot,
      );
    }
  }

  /// Helper to queue order delete operation
  Future<void> _queueOrderDelete(int orderId, String orderCode) async {
    try {
      final pendingOpsService = PendingOperationsService(_database);
      await pendingOpsService.queueOrderDelete(
        entityId: orderId,
        orderCode: orderCode,
      );
      _logger.info('Queued delete operation for synced order code=$orderCode');
    } catch (e) {
      _logger.error('Failed to queue delete operation: $e');
    }
  }
}

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final database = ref.watch(databaseProvider);
  final repository = OrderRepository(database, ref);

  // Set up sync service and network status callback.
  // Use ref.read inside the callback so it always returns the CURRENT online state,
  // rather than capturing a stale value at provider creation time.
  final syncService = ref.watch(dataSyncServiceProvider);
  repository.setSyncService(
    syncService,
    () => ref.read(lastKnownOnlineStatusProvider),
  );

  return repository;
});

/// The backend's payment position for an order: what has been collected and
/// what is still owed. Watched rather than computed locally because the
/// server owns the sum — a service order is routinely part-paid across tills.
final orderPaymentPositionProvider = StreamProvider.family<Order?, int>((
  ref,
  orderId,
) {
  final db = ref.watch(databaseProvider);
  return (db.select(
    db.orders,
  )..where((o) => o.id.equals(orderId))).watchSingleOrNull();
});

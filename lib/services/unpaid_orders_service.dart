import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import '../domain/models/order_money.dart';
import '../domain/models/order_money_rows.dart';
import '../domain/services/unpaid_queries.dart';

/// One unpaid order, with who is currently carrying it.
class UnpaidOrderEntry {
  final Order order;
  final String? tableName;

  /// What the order comes to, and what has actually been collected against
  /// it. A part-paid table is still transferable — [due] is what moves.
  final double total;
  final double paid;

  /// `takenBy`, falling back to `createdBy` for rows written before `takenBy`
  /// was populated.
  final int? holderId;
  final String? holderName;

  final int? sessionId;
  final String? sessionCode;

  /// The session this table is stamped with has been closed. These are the
  /// "old ones" a cashier needs pulled onto their own session: while the
  /// order sits in an ended session, [OrderRepository.updateOrder] refuses to
  /// touch it, so it can be neither edited nor paid.
  final bool sessionEnded;

  /// This is the order the table is actually holding right now
  /// (`area_tables.order_id`), not merely an unpaid order that names the
  /// table.
  ///
  /// The two come apart more often than they look: an order left unpaid when
  /// its table was cleared, or re-seated, still carries the old `tableId`
  /// forever. Summing those into the table's figure showed a table owing far
  /// more than the people sitting at it — or, worse, showed last week's
  /// abandoned order instead of tonight's. The floor view uses only the
  /// current one; the reports still list every unpaid order, which is the
  /// point of them.
  final bool isCurrentForTable;

  const UnpaidOrderEntry({
    required this.order,
    required this.tableName,
    required this.total,
    required this.paid,
    required this.holderId,
    required this.holderName,
    required this.sessionId,
    required this.sessionCode,
    required this.sessionEnded,
    this.isCurrentForTable = false,
  });

  double get due {
    final d = total - paid;
    return d < 0 ? 0 : d;
  }

  /// True for an order sitting on a table — what the floor calls an open
  /// table, as opposed to a parked takeaway or delivery.
  bool get isTable => order.tableId != null;

  String get label => tableName ?? order.code;
}

/// What is still outstanding across the floor, ready to print or head a
/// dialog. Tables and non-table orders are counted separately because the two
/// mean different things to a cashier closing up: an open table is somebody
/// still sitting there, a parked takeaway is money nobody collected.
class UnpaidOrdersSummary {
  final List<UnpaidOrderEntry> entries;
  final DateTime at;

  const UnpaidOrdersSummary({required this.entries, required this.at});

  Iterable<UnpaidOrderEntry> get tables => entries.where((e) => e.isTable);
  Iterable<UnpaidOrderEntry> get others => entries.where((e) => !e.isTable);

  int get count => entries.length;
  int get tableCount => tables.length;

  /// What the orders come to in full, what has been collected against them,
  /// and what is left — the three figures a handover turns on.
  double get totalValue => entries.fold(0.0, (s, e) => s + e.total);
  double get totalPaid => entries.fold(0.0, (s, e) => s + e.paid);
  double get totalDue => entries.fold(0.0, (s, e) => s + e.due);

  /// Indexed for the floor view, which asks per table rather than per order.
  ///
  /// Only the order each table is actually holding — see
  /// [UnpaidOrderEntry.isCurrentForTable]. Indexing every unpaid order by its
  /// `tableId` both double-counted and, because later writes win and the list
  /// is newest-first, left the OLDEST stray order as the one on show.
  Map<int, UnpaidOrderEntry> get byTableId => {
        for (final e in entries)
          if (e.isCurrentForTable && e.order.tableId != null)
            e.order.tableId!: e,
      };

  /// The floor as the tables themselves show it: one entry per occupied
  /// table. What the totals bar above the table grid must add up, so the bar
  /// and the sum of the cards can never disagree.
  Iterable<UnpaidOrderEntry> get seatedTables =>
      entries.where((e) => e.isCurrentForTable);

  double get tablesDue => tables.fold(0.0, (s, e) => s + e.due);
  double get othersDue => others.fold(0.0, (s, e) => s + e.due);
}

/// What is still owed across the floor, and who owns it.
///
/// A shift change leaves live tables behind. They stay stamped with the
/// outgoing cashier and their (soon closed) session, which the floor feels
/// immediately: the money eventually collected lands in a session that has
/// already been Z-ed, and once that session is closed `updateOrder` refuses to
/// modify the order at all — the table can be neither added to nor paid.
///
/// The handover is not a separate act any more. Whoever pays or modifies an
/// unpaid order [claim]s it as they go, so the order follows the person
/// actually working it and the next cashier simply picks the table up. This
/// service is what the floor, the reports and that claim all read from.
class UnpaidOrdersService implements UnpaidQueries {
  final AppDatabase _db;

  UnpaidOrdersService(this._db);

  /// Every unpaid order, newest first — tables and parked orders alike.
  ///
  /// Cancelled orders are excluded, and so are zero-value ones: an empty
  /// order occupying a table is a floor-reconciliation problem, not money
  /// anybody is owed.
  ///
  /// [tablesOnly] narrows it to orders sitting on a table, which is what the
  /// floor view wants; the reports want both.
  @override
  Future<List<UnpaidOrderEntry>> unpaidOrders({bool tablesOnly = false}) async {
    final query = _db.select(_db.orders)
      ..where((o) => o.status.equals('CANCELED').not())
      ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]);
    if (tablesOnly) query.where((o) => o.tableId.isNotNull());
    final orders = await query.get();
    if (orders.isEmpty) return const [];

    final orderIds = [for (final o in orders) o.id];
    final lines = await (_db.select(_db.orderProducts)
          ..where((p) => p.orderId.isIn(orderIds)))
        .get();
    final components = lines.isEmpty
        ? <OrderProductComponent>[]
        : await (_db.select(_db.orderProductComponents)
              ..where((c) => c.orderProductId.isIn([for (final l in lines) l.id])))
            .get();
    final compCost = <int, double>{};
    for (final c in components) {
      compCost[c.orderProductId] =
          (compCost[c.orderProductId] ?? 0.0) + c.price * c.quantity;
    }

    // Same arithmetic as OrderRepository.getOrderTotals — components in,
    // manual discount off the unit, then the order-level percentage.
    final totalByOrder = <int, double>{};
    for (final l in lines) {
      if (!lineCountsInTotal(l.state, paid: l.ticketId != null)) continue;
      totalByOrder[l.orderId] = (totalByOrder[l.orderId] ?? 0.0) +
          l.amounts(componentsPerUnit: compCost[l.id] ?? 0.0).net;
    }

    final tickets = await (_db.select(_db.tickets)
          ..where((t) =>
              t.orderId.isIn(orderIds) &
              t.isPaid.equals(true) &
              t.isCancelled.equals(false)))
        .get();
    final paidByOrder = <int, double>{};
    for (final t in tickets) {
      paidByOrder[t.orderId] = (paidByOrder[t.orderId] ?? 0.0) + t.amount;
    }

    final tableIds = {
      for (final o in orders)
        if (o.tableId != null) o.tableId!,
    }.toList();
    final tables = tableIds.isEmpty
        ? <AreaTable>[]
        : await (_db.select(_db.areaTables)..where((t) => t.id.isIn(tableIds)))
            .get();
    final tableNameById = {for (final t in tables) t.id: t.name};
    // The order each table is holding right now, which is not the same thing
    // as "an unpaid order that names this table".
    final currentOrderByTable = {
      for (final t in tables)
        if (t.orderId != null) t.id: t.orderId!,
    };

    final userIds = {
      for (final o in orders)
        if ((o.takenBy ?? o.createdBy) != null) (o.takenBy ?? o.createdBy)!,
    }.toList();
    final users = userIds.isEmpty
        ? <User>[]
        : await (_db.select(_db.users)..where((u) => u.id.isIn(userIds))).get();
    final userNameById = {
      for (final u in users)
        u.id: '${u.firstName} ${u.lastName}'.trim().isEmpty
            ? u.username
            : '${u.firstName} ${u.lastName}'.trim()
    };

    final sessionIds = {
      for (final o in orders)
        if (o.sessionId != null) o.sessionId!,
    }.toList();
    final sessions = sessionIds.isEmpty
        ? <CashSession>[]
        : await (_db.select(_db.cashSessions)..where((s) => s.id.isIn(sessionIds)))
            .get();
    final sessionById = {for (final s in sessions) s.id: s};

    final out = <UnpaidOrderEntry>[];
    for (final o in orders) {
      final total = totalByOrder[o.id] ?? 0.0;
      if (total <= 0) continue;
      final withDiscount = applyOrderDiscount(total, o.discountPercentage);
      final paid = paidByOrder[o.id] ?? 0.0;
      // Epsilon so a fully-paid table is not offered for handover over a
      // rounding penny.
      if (paid + 0.005 >= withDiscount) continue;

      final holderId = o.takenBy ?? o.createdBy;
      final session = o.sessionId == null ? null : sessionById[o.sessionId!];
      out.add(UnpaidOrderEntry(
        order: o,
        tableName: o.tableId == null ? null : tableNameById[o.tableId!],
        total: withDiscount,
        paid: paid,
        holderId: holderId,
        holderName: holderId == null ? null : userNameById[holderId],
        sessionId: o.sessionId,
        sessionCode: session?.code,
        sessionEnded: session != null && session.status == 'ended',
        isCurrentForTable:
            o.tableId != null && currentOrderByTable[o.tableId!] == o.id,
      ));
    }
    return out;
  }

  /// [summary], re-read whenever anything that could change it changes.
  ///
  /// The trivial `SELECT 1` is a drift idiom, not a mistake: declaring
  /// `readsFrom` makes the stream re-emit on any write to those tables, which
  /// is what lets one recomputation cover orders, their lines, their tickets
  /// and the floor plan together. Watching only `orders` would miss a
  /// payment, and the figures on the floor would quietly go stale.
  @override
  Stream<UnpaidOrdersSummary> watchSummary({bool tablesOnly = false}) => _db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          _db.orders,
          _db.orderProducts,
          _db.orderProductComponents,
          _db.tickets,
          _db.areaTables,
        },
      )
      .watch()
      .asyncMap((_) => summary(tablesOnly: tablesOnly));

  /// The whole floor's outstanding position in one object.
  @override
  Future<UnpaidOrdersSummary> summary({bool tablesOnly = false}) async =>
      UnpaidOrdersSummary(
        entries: await unpaidOrders(tablesOnly: tablesOnly),
        at: DateTime.now(),
      );

  /// What is owed per table, keyed by table id — for the floor view, where
  /// each table shows what has been collected on it and what has not.
  Future<Map<int, UnpaidOrderEntry>> byTable() async {
    final rows = await unpaidOrders(tablesOnly: true);
    return {
      for (final e in rows)
        if (e.order.tableId != null) e.order.tableId!: e,
    };
  }

  /// Re-stamp [orderIds] onto [toUserId] and their session — the claim that
  /// happens whenever a cashier pays or modifies someone else's order.
  ///
  /// [toSessionId] is the claiming cashier's OPEN session. Passing null leaves
  /// the session alone, which is right when only ownership is changing;
  /// passing it is what unsticks an order marooned in a closed session.
  ///
  /// Touches `takenBy` and nothing else that carries meaning:
  ///   * `waiterId` (`servedBy` to the backend) stays put, so the waiter who
  ///     served the table keeps their attribution, their settlement and their
  ///     line on the per-waiter Z ticket.
  ///   * `source` stays put, so a WAITER-raised order is still recognised as
  ///     one and the cashier edit lock keeps applying after the claim.
  ///
  /// Marks each order unsynced so the new ownership reaches the backend on the
  /// next push (it goes up as `takenBy`), and returns how many rows moved.
  ///
  /// Deliberately NOT routed through [OrderRepository.updateOrder]: that is
  /// refused outright for an order in a closed session — exactly the ones most
  /// in need of claiming — and it rewrites every line, which a change of owner
  /// has no business doing.
  Future<int> claim({
    required List<int> orderIds,
    required int toUserId,
    int? toSessionId,
  }) async {
    if (orderIds.isEmpty) return 0;
    var moved = 0;
    await _db.transaction(() async {
      for (final id in orderIds) {
        final n = await (_db.update(_db.orders)..where((o) => o.id.equals(id)))
            .write(OrdersCompanion(
          takenBy: Value(toUserId),
          // Absent, not null: leaving the session alone has to stay
          // distinguishable from clearing it.
          sessionId: toSessionId == null
              ? const Value.absent()
              : Value(toSessionId),
          isSynced: const Value(false),
          updatedAt: Value(DateTime.now()),
        ));
        moved += n;
      }
    });
    return moved;
  }
}

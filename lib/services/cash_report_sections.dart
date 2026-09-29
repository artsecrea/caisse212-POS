import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import '../domain/models/table_occupancy.dart' show isOrderSettled;

/// The banded cash report — the nine sections of a French-style X / Z.
///
/// Computed over a set of cash sessions (a shift, a Z, or a date range's worth
/// of them) and rendered identically whether the heading says X or Z: an X is a
/// snapshot of the same figures mid-shift, which is why nothing here knows
/// which of the two it is.
///
/// Deliberately absent, because the data model has no concept of them — rather
/// than printing a line that is always zero:
///   * Gratuités / Offerts — no "comped line" flag on `order_products`.
///   * Arrondis — no rounding column on `tickets`.
///   * Chèque / Bon / Crédit client — `TransactionType` is CASH, CARD, MOBILE
///     and OTHER, so those three are indistinguishable from any other "other".
class CashReportSections {
  const CashReportSections({
    required this.general,
    required this.salesByType,
    required this.vatBands,
    required this.cash,
    required this.indicators,
    required this.families,
    required this.topArticles,
    required this.live,
    this.removedItems = const RemovedItemsSummary(),
  });

  final GeneralSummary general;

  /// Order type -> net TTC. Keyed by the raw `orders.type` so the printer owns
  /// the labels.
  final Map<String, double> salesByType;

  final List<VatBand> vatBands;
  final CashMovements cash;
  final RestaurantIndicators indicators;

  /// §7, every category that sold, biggest first.
  final List<CategoryRow> families;

  /// §8, the best sellers. Capped by the builder — it is an extract, not a
  /// stock list.
  final List<CategoryRow> topArticles;

  final LiveStatuses live;

  /// Lines taken OFF saved orders during the period — read from the annulment
  /// tombstones, not from `order_products`, because the rows they describe
  /// have been deleted by the time this runs.
  final RemovedItemsSummary removedItems;

  double get vatTotalHt =>
      vatBands.fold(0.0, (sum, b) => sum + b.baseHt);
  double get vatTotalVat => vatBands.fold(0.0, (sum, b) => sum + b.vat);
  double get vatTotalTtc => vatBands.fold(0.0, (sum, b) => sum + b.ttc);

  /// An empty report — the shape a period with no sessions still has to print.
  static const CashReportSections empty = CashReportSections(
    general: GeneralSummary(),
    salesByType: {},
    vatBands: [],
    cash: CashMovements(),
    indicators: RestaurantIndicators(),
    families: [],
    topArticles: [],
    live: LiveStatuses(),
  );
}

/// Annulments: what was rung up and then pulled off a SAVED order.
///
/// Sourced from `removed_order_items`. Separate from
/// [GeneralSummary.cancelledLines], which counts lines still present on the
/// order but struck (state CANCELED) — these are lines that no longer exist.
class RemovedItemsSummary {
  const RemovedItemsSummary({
    this.lineCount = 0,
    this.quantity = 0,
    this.amount = 0,
    this.afterKitchenQuantity = 0,
    this.afterKitchenAmount = 0,
    this.rows = const [],
  });

  /// How many annulment events — one per product+variant pulled.
  final int lineCount;

  /// Units pulled. Real, because weighed lines sell in kg.
  final double quantity;

  /// What those units were worth at the price they carried.
  final double amount;

  /// The subset the kitchen had already been told to make. This is the figure
  /// that means waste; the rest was pulled before anyone started cooking.
  final double afterKitchenQuantity;
  final double afterKitchenAmount;

  /// Per-article detail, biggest first.
  final List<CategoryRow> rows;

  bool get isEmpty => lineCount == 0;
}

/// §1 RESUME GENERAL.
class GeneralSummary {
  const GeneralSummary({
    this.grossSales = 0,
    this.discounts = 0,
    this.cancelledTickets = 0,
    this.cancelledLines = 0,
    this.refunds = 0,
  });

  /// What the lines were worth at catalogue price, before anything came off.
  final double grossSales;

  /// Per-line discount plus manual discount plus the order-level percentage,
  /// as a positive number. Printed negative.
  final double discounts;

  /// Money on tickets that were voided after the fact.
  final double cancelledTickets;

  /// Lines struck off an order that was not itself cancelled.
  final double cancelledLines;

  /// Money handed back through the refund flow.
  final double refunds;

  /// What the shop actually kept.
  double get netTotal =>
      grossSales - discounts - cancelledTickets - cancelledLines - refunds;
}

/// One row of §4, a single VAT rate.
class VatBand {
  const VatBand({
    required this.rate,
    required this.baseHt,
    required this.vat,
  });

  /// Percentage, e.g. 20 for 20%.
  final double rate;

  /// Net of tax.
  final double baseHt;

  /// The tax itself.
  final double vat;

  double get ttc => baseHt + vat;
}

/// §5 MOUVEMENTS DE CAISSE.
class CashMovements {
  const CashMovements({
    this.openingFloat = 0,
    this.cashSales = 0,
    this.cashDeliveryFees = 0,
    this.cashIn = 0,
    this.cashOut = 0,
    this.countedCash,
  });

  final double openingFloat;

  /// Takings in physical cash — the only payment method that reaches the
  /// drawer, which is what makes the expected figure below meaningful.
  final double cashSales;

  /// Delivery charges collected in cash, inside [cashSales].
  ///
  /// Broken out for the printed report only: the fee is real money in the
  /// drawer, but it is not a product sale, and a manager counting down wants
  /// to see why the takings exceed the ticket rows.
  final double cashDeliveryFees;

  /// Paid in / paid out through the cash-movement flow.
  final double cashIn;
  final double cashOut;

  /// What the cashier counted. Null while the shift is open (an X), which is
  /// why the variance is null too rather than a misleading zero.
  final double? countedCash;

  double get expectedCash => openingFloat + cashSales + cashIn - cashOut;

  double? get variance =>
      countedCash == null ? null : countedCash! - expectedCash;
}

/// §6 INDICATEURS RESTAURANT.
class RestaurantIndicators {
  const RestaurantIndicators({
    this.ticketCount = 0,
    this.cancelledTicketCount = 0,
    this.cancelledLineCount = 0,
    this.totalDiscounts = 0,
    this.totalRefunds = 0,
    this.covers = 0,
    this.tablesOpen = 0,
    this.tablesClosed = 0,
    this.ordersByStation = const {},
    this.netSales = 0,
  });

  final int ticketCount;
  final int cancelledTicketCount;
  final int cancelledLineCount;
  final double totalDiscounts;
  final double totalRefunds;

  /// Heads through the door — `orders.persons` summed.
  final int covers;

  /// Still seated at the moment the report was taken.
  final int tablesOpen;

  /// Settled during the period.
  final int tablesClosed;

  /// Station name -> how many orders reached it. The "commandes cuisine /
  /// commandes bar" split, derived from each product's station rather than a
  /// hardcoded pair, so a shop with three stations gets three rows.
  final Map<String, int> ordersByStation;

  final double netSales;

  double get averageTicket => ticketCount == 0 ? 0 : netSales / ticketCount;
}

/// A named row with a quantity and a money column — §7 and §8 share the shape.
class CategoryRow {
  const CategoryRow({
    required this.name,
    required this.quantity,
    required this.amount,
  });

  final String name;
  final double quantity;
  final double amount;
}

/// §9 STATUTS EN COURS — a live snapshot, not a period total.
class LiveStatuses {
  const LiveStatuses({
    this.parkedOrders = 0,
    this.openTables = 0,
    this.sentToKitchen = 0,
    this.readyNotServed = 0,
  });

  /// Held / on-hold orders waiting to be picked back up.
  final int parkedOrders;

  /// Tables currently holding an order.
  final int openTables;

  /// Lines the kitchen has been told about and not finished.
  final int sentToKitchen;

  /// Lines the kitchen finished that nobody has taken out.
  final int readyNotServed;
}

/// Builds [CashReportSections] for a set of sessions.
///
/// One pass per table rather than per order: a busy shift is thousands of
/// lines, and the previous per-order queries made the Z take long enough that
/// cashiers thought the till had hung.
class CashReportBuilder {
  CashReportBuilder(this._db);

  final AppDatabase _db;

  /// How many rows §8 keeps. It is labelled "extrait" on the paper.
  static const int topArticlesLimit = 10;

  Future<CashReportSections> build({
    required List<int> sessionIds,
    double? countedCash,
  }) async {
    if (sessionIds.isEmpty) return CashReportSections.empty;

    final orders = await (_db.select(_db.orders)
          ..where((o) => o.sessionId.isIn(sessionIds)))
        .get();
    if (orders.isEmpty) {
      return _emptyWithCash(sessionIds, countedCash);
    }

    final orderIds = orders.map((o) => o.id).toList();
    final orderById = {for (final o in orders) o.id: o};

    final lines = await (_db.select(_db.orderProducts)
          ..where((p) => p.orderId.isIn(orderIds)))
        .get();

    final tickets = await (_db.select(_db.tickets)
          ..where((t) => t.sessionId.isIn(sessionIds)))
        .get();

    final refunds = await (_db.select(_db.refunds)
          ..where((r) => r.sessionId.isIn(sessionIds)))
        .get();

    final movements = await (_db.select(_db.cashMovements)
          ..where((m) => m.sessionId.isIn(sessionIds)))
        .get();

    final sessions = await (_db.select(_db.cashSessions)
          ..where((s) => s.id.isIn(sessionIds)))
        .get();

    // Catalogue lookups, one query each.
    final productIds = lines.map((l) => l.productId).toSet();
    final products = productIds.isEmpty
        ? const <Product>[]
        : await (_db.select(_db.products)
              ..where((p) => p.id.isIn(productIds)))
            .get();
    final productById = {for (final p in products) p.id: p};

    final categoryIds =
        products.map((p) => p.categoryId).whereType<int>().toSet();
    final categories = categoryIds.isEmpty
        ? const <Category>[]
        : await (_db.select(_db.categories)
              ..where((c) => c.id.isIn(categoryIds)))
            .get();
    final categoryNameById = {for (final c in categories) c.id: c.name};

    final stationIds = products.map((p) => p.stationId).whereType<int>().toSet();
    final stations = stationIds.isEmpty
        ? const <Station>[]
        : await (_db.select(_db.stations)
              ..where((s) => s.id.isIn(stationIds)))
            .get();
    final stationNameById = {for (final s in stations) s.id: s.name};

    // ---- §1 + §4 + §7 + §8, all derived from the lines -------------------
    var gross = 0.0;
    var discounts = 0.0;
    var cancelledLines = 0.0;
    var cancelledLineCount = 0;

    final vatByRate = <double, _VatAcc>{};
    final byCategory = <String, _RowAcc>{};
    final byArticle = <String, _RowAcc>{};
    final stationOrderIds = <String, Set<int>>{};

    for (final line in lines) {
      final order = orderById[line.orderId];
      if (order == null) continue;

      final lineGross = line.unitaryPrice * line.quantity;
      // Per-unit discount and the manual one are both per-unit figures; the
      // order-level percentage applies on top of what is left.
      final lineDiscount =
          (line.unitaryDiscount + line.manualDiscount) * line.quantity;
      final afterLine = lineGross - lineDiscount;
      final orderPct = order.discountPercentage;
      final orderLevel = orderPct > 0 ? afterLine * (orderPct / 100) : 0.0;
      final net = afterLine - orderLevel;

      final isCancelled = _isCancelledState(line.state);
      if (isCancelled) {
        cancelledLines += net;
        cancelledLineCount++;
        // A struck line is reported on its own §1 row, so it must not also
        // inflate gross, the VAT bands or the best-seller list.
        continue;
      }

      gross += lineGross;
      discounts += lineDiscount + orderLevel;

      // `unitaryTva` is a percentage; net is TTC, so the base is backed out.
      final rate = line.unitaryTva;
      final base = rate > 0 ? net / (1 + rate / 100) : net;
      final acc = vatByRate.putIfAbsent(rate, () => _VatAcc());
      acc.base += base;
      acc.vat += net - base;

      final product = productById[line.productId];
      final categoryName =
          categoryNameById[product?.categoryId] ?? _unclassified;
      final catAcc = byCategory.putIfAbsent(categoryName, () => _RowAcc());
      catAcc.qty += line.quantity;
      catAcc.amount += net;

      final articleName = product?.name ?? 'Article #${line.productId}';
      final artAcc = byArticle.putIfAbsent(articleName, () => _RowAcc());
      artAcc.qty += line.quantity;
      artAcc.amount += net;

      final stationName = stationNameById[product?.stationId];
      if (stationName != null) {
        stationOrderIds.putIfAbsent(stationName, () => <int>{}).add(order.id);
      }
    }

    // ---- §1 cancellations from tickets, and the refund total -------------
    final cancelledTicketRows = tickets.where((t) => t.isCancelled).toList();
    final cancelledTicketTotal =
        cancelledTicketRows.fold(0.0, (sum, t) => sum + t.amount);
    final refundTotal = refunds.fold(0.0, (sum, r) => sum + r.totalAmount);

    final general = GeneralSummary(
      grossSales: gross,
      discounts: discounts,
      cancelledTickets: cancelledTicketTotal,
      cancelledLines: cancelledLines,
      refunds: refundTotal,
    );

    // ---- §2 sales by order type ------------------------------------------
    // Built from live tickets so the split always adds up to what was taken,
    // rather than to what was rung.
    final liveTickets =
        tickets.where((t) => t.isPaid && !t.isCancelled).toList();

    // Delivery charges, attributed to the ticket that actually collected
    // them.
    //
    // A fee belongs to the ORDER and rides the FIRST settlement — see
    // `deliveryFeeToCollect` — so it is never on a ticket row: `ticket.amount`
    // is products-only, by design, to keep the fee out of sales figures. The
    // consequence nobody had accounted for is that the cash is in the drawer
    // and in no report, so a shift with deliveries always counted OVER and the
    // variance was written off as a miscount.
    //
    // Reconstructed here the same way a reprint reconstructs it: the earliest
    // live ticket on the order is the one that took the fee, and its method is
    // the method the fee arrived in.
    final feeByTicketId = <int, double>{};
    final ticketsByOrder = <int, List<dynamic>>{};
    for (final t in liveTickets) {
      ticketsByOrder.putIfAbsent(t.orderId, () => []).add(t);
    }
    ticketsByOrder.forEach((orderId, ts) {
      final fee = orderById[orderId]?.deliveryFee ?? 0.0;
      if (fee <= 0) return;
      // Lowest id = settled first. Matches `_ticketDeliveryFee` in the
      // tickets screen, so the report and the reprint agree.
      final first = ts.reduce((a, b) => a.id <= b.id ? a : b);
      feeByTicketId[first.id as int] = fee;
    });
    final salesByType = <String, double>{};
    for (final ticket in liveTickets) {
      final order = orderById[ticket.orderId];
      final type = order?.type ?? 'OTHER';
      // Built from live tickets so the split adds up to what was TAKEN — and
      // the delivery fee was taken, so leaving it out made the split disagree
      // with the drawer by exactly the fees.
      salesByType[type] = (salesByType[type] ?? 0) +
          ticket.amount +
          (feeByTicketId[ticket.id] ?? 0.0);
    }

    // ---- §3 is the existing payment rollup, §5 the drawer ------------------
    final cashDeliveryFees = liveTickets
        .where((t) => t.paymentMethod.toUpperCase() == 'CASH')
        .fold(0.0, (sum, t) => sum + (feeByTicketId[t.id] ?? 0.0));
    final cashSales = liveTickets
            .where((t) => t.paymentMethod.toUpperCase() == 'CASH')
            .fold(0.0, (sum, t) => sum + t.amount) +
        // In the drawer, so in the expected figure — otherwise every cash
        // delivery leaves the count over by its fee.
        cashDeliveryFees;

    var cashIn = 0.0;
    var cashOut = 0.0;
    for (final m in movements) {
      if (m.direction.toUpperCase() == 'IN') {
        cashIn += m.amount;
      } else {
        cashOut += m.amount;
      }
    }

    final openingFloat =
        sessions.fold(0.0, (sum, s) => sum + s.moneyAtStart);
    // Only a closed session has a counted figure. Summed across the set so a
    // multi-session Z reconciles as one drawer.
    final counted = countedCash ??
        (sessions.every((s) => s.moneyAtEnd != null)
            ? sessions.fold<double>(0.0, (sum, s) => sum + (s.moneyAtEnd ?? 0))
            : null);

    final cash = CashMovements(
      openingFloat: openingFloat,
      cashSales: cashSales,
      cashDeliveryFees: cashDeliveryFees,
      cashIn: cashIn,
      cashOut: cashOut,
      countedCash: counted,
    );

    // ---- §6 indicators ----------------------------------------------------
    final covers = orders.fold<int>(0, (sum, o) => sum + o.persons);

    final linesByOrder = <int, List<OrderProduct>>{};
    for (final line in lines) {
      (linesByOrder[line.orderId] ??= []).add(line);
    }
    var tablesClosed = 0;
    var tablesOpen = 0;
    for (final order in orders) {
      if (order.tableId == null) continue;
      final states =
          (linesByOrder[order.id] ?? const <OrderProduct>[]).map((l) => l.state);
      if (states.isEmpty) continue;
      if (isOrderSettled(states)) {
        tablesClosed++;
      } else {
        tablesOpen++;
      }
    }

    final netSales = liveTickets.fold(0.0, (sum, t) => sum + t.amount);

    final indicators = RestaurantIndicators(
      ticketCount: liveTickets.length,
      cancelledTicketCount: cancelledTicketRows.length,
      cancelledLineCount: cancelledLineCount,
      totalDiscounts: discounts,
      totalRefunds: refundTotal,
      covers: covers,
      tablesOpen: tablesOpen,
      tablesClosed: tablesClosed,
      ordersByStation: {
        for (final e in stationOrderIds.entries) e.key: e.value.length,
      },
      netSales: netSales,
    );

    // ---- §9 live snapshot -------------------------------------------------
    final live = await _liveStatuses();

    return CashReportSections(
      general: general,
      salesByType: salesByType,
      vatBands: _sortedBands(vatByRate),
      cash: cash,
      indicators: indicators,
      families: _sortedRows(byCategory),
      topArticles: _sortedRows(byArticle).take(topArticlesLimit).toList(),
      live: live,
      removedItems: await _removedItems(sessionIds),
    );
  }

  /// §9 asks what the floor looks like NOW, not what this shift sold, so it is
  /// deliberately unscoped by session.
  Future<LiveStatuses> _liveStatuses() async {
    final parked = await (_db.select(_db.orders)
          ..where((o) => o.status.equals('ONHOLD')))
        .get();

    final heldTables = await (_db.select(_db.areaTables)
          ..where((t) => t.orderId.isNotNull()))
        .get();

    final sent = await (_db.select(_db.orderProducts)
          ..where((p) =>
              p.state.isIn(['PENDING', 'PREPARING']) &
              p.kdsPrintedQuantity.isBiggerThanValue(0)))
        .get();

    final ready = await (_db.select(_db.orderProducts)
          ..where((p) => p.state.equals('COMPLETED') & p.ticketId.isNull()))
        .get();

    return LiveStatuses(
      parkedOrders: parked.length,
      openTables: heldTables.length,
      sentToKitchen: sent.length,
      readyNotServed: ready.length,
    );
  }

  Future<CashReportSections> _emptyWithCash(
      List<int> sessionIds, double? countedCash) async {
    final sessions = await (_db.select(_db.cashSessions)
          ..where((s) => s.id.isIn(sessionIds)))
        .get();
    final movements = await (_db.select(_db.cashMovements)
          ..where((m) => m.sessionId.isIn(sessionIds)))
        .get();
    var cashIn = 0.0;
    var cashOut = 0.0;
    for (final m in movements) {
      if (m.direction.toUpperCase() == 'IN') {
        cashIn += m.amount;
      } else {
        cashOut += m.amount;
      }
    }
    return CashReportSections(
      general: const GeneralSummary(),
      salesByType: const {},
      vatBands: const [],
      cash: CashMovements(
        openingFloat: sessions.fold(0.0, (sum, s) => sum + s.moneyAtStart),
        cashIn: cashIn,
        cashOut: cashOut,
        countedCash: countedCash ??
            (sessions.every((s) => s.moneyAtEnd != null)
                ? sessions.fold<double>(0.0, (sum, s) => sum + (s.moneyAtEnd ?? 0))
                : null),
      ),
      indicators: const RestaurantIndicators(),
      families: const [],
      topArticles: const [],
      live: await _liveStatuses(),
      // A period can have no surviving orders and still have annulments.
      removedItems: await _removedItems(sessionIds),
    );
  }

  /// Roll up the annulment tombstones for these sessions.
  ///
  /// Scoped by `sessionId` like every other section. Rows whose session is null
  /// (a removal on an order raised outside a session) are simply not in any
  /// report, which matches how orders themselves are scoped.
  Future<RemovedItemsSummary> _removedItems(List<int> sessionIds) async {
    final rows = await (_db.select(_db.removedOrderItems)
          ..where((r) => r.sessionId.isIn(sessionIds)))
        .get();
    if (rows.isEmpty) return const RemovedItemsSummary();

    var quantity = 0.0;
    var amount = 0.0;
    var afterKitchenQty = 0.0;
    var afterKitchenAmount = 0.0;
    final byArticle = <String, _RowAcc>{};

    for (final r in rows) {
      quantity += r.quantity;
      amount += r.amount;
      if (r.wasSentToKitchen) {
        afterKitchenQty += r.quantity;
        afterKitchenAmount += r.amount;
      }
      final label = r.variantName == null || r.variantName!.isEmpty
          ? r.productName
          : '${r.productName} (${r.variantName})';
      final acc = byArticle.putIfAbsent(label, () => _RowAcc());
      acc.qty += r.quantity;
      acc.amount += r.amount;
    }

    return RemovedItemsSummary(
      lineCount: rows.length,
      quantity: quantity,
      amount: amount,
      afterKitchenQuantity: afterKitchenQty,
      afterKitchenAmount: afterKitchenAmount,
      rows: _sortedRows(byArticle),
    );
  }

  static const String _unclassified = 'Divers';

  static bool _isCancelledState(String state) {
    final s = state.toUpperCase();
    return s == 'CANCELED' || s == 'CANCELLED';
  }

  static List<VatBand> _sortedBands(Map<double, _VatAcc> acc) {
    final bands = acc.entries
        .map((e) => VatBand(rate: e.key, baseHt: e.value.base, vat: e.value.vat))
        .where((b) => b.ttc.abs() > 0.005)
        .toList()
      ..sort((a, b) => b.rate.compareTo(a.rate));
    return bands;
  }

  static List<CategoryRow> _sortedRows(Map<String, _RowAcc> acc) {
    final rows = acc.entries
        .map((e) =>
            CategoryRow(name: e.key, quantity: e.value.qty, amount: e.value.amount))
        .where((r) => r.quantity.abs() > 0.0001)
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return rows;
  }
}

class _VatAcc {
  double base = 0;
  double vat = 0;
}

class _RowAcc {
  double qty = 0;
  double amount = 0;
}

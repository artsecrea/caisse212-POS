import 'package:drift/drift.dart';

import '../data/database/app_database.dart';

/// One line the cashier chose to refund, as selected in the UI.
class RefundLineDraft {
  /// Local `order_products.id`.
  final int orderProductId;

  /// How much of the line to give back. Real, so a weighed line can be
  /// partially refunded.
  final double quantity;

  /// Money to return. Null lets the server derive it from the order line's
  /// per-unit total × quantity, which is the normal case.
  final double? amount;

  /// True = goods come back into stock (a positive REFUND movement server
  /// side). False = waste; the customer is refunded but the stock is gone.
  final bool restock;

  final String? reason;

  const RefundLineDraft({
    required this.orderProductId,
    required this.quantity,
    this.amount,
    this.restock = true,
    this.reason,
  });
}

/// Creates and syncs refunds against paid orders.
///
/// Mirrors [SessionService] / [ZService]: a unique `code` that doubles as the
/// backend's idempotency key (re-sending is a documented no-op), and an
/// `isSynced` push flag so a refund taken offline survives and is pushed later.
/// One printed line of a refund slip.
class RefundSlipLine {
  final String name;
  final double quantity;
  final double amount;
  final bool restock;

  /// Set only for a serial-tracked line — the exact unit handed back.
  final String? serialNumber;

  const RefundSlipLine({
    required this.name,
    required this.quantity,
    required this.amount,
    required this.restock,
    this.serialNumber,
  });
}

/// Everything the refund slip prints.
///
/// Assembled by [RefundService.slipFor] rather than by the caller: the printer
/// must not go querying the database mid-render, and the slip has to survive
/// being reprinted later from stored rows alone.
class RefundSlipData {
  final String code;
  final String orderCode;
  final String method;
  final String? reason;
  final String? cashierName;
  final DateTime refundedAt;
  final double total;
  final List<RefundSlipLine> lines;

  const RefundSlipData({
    required this.code,
    required this.orderCode,
    required this.method,
    required this.refundedAt,
    required this.total,
    required this.lines,
    this.reason,
    this.cashierName,
  });
}

/// Raised when a refund would take a line past what was actually sold.
///
/// A distinct type rather than a bare ArgumentError so the dialog can show the
/// remaining quantity instead of a generic failure.
class RefundCapException implements Exception {
  final int orderProductId;
  final double ordered;
  final double alreadyRefunded;
  final double requested;
  final double remaining;

  RefundCapException({
    required this.orderProductId,
    required this.ordered,
    required this.alreadyRefunded,
    required this.requested,
    required this.remaining,
  });

  @override
  String toString() =>
      'Cannot refund $requested of line $orderProductId: $ordered sold, '
      '$alreadyRefunded already refunded, $remaining left';
}

/// Raised when a refund line asks for more money than the line is worth.
///
/// Separate from [RefundCapException] because the fix is different: that one is
/// "you have already refunded this", this one is "that number is too big".
class RefundAmountException implements Exception {
  final int orderProductId;
  final double requested;
  final double maximum;

  RefundAmountException({
    required this.orderProductId,
    required this.requested,
    required this.maximum,
  });

  @override
  String toString() =>
      'Refund amount $requested exceeds the value of line $orderProductId '
      '(max $maximum)';
}

class RefundService {
  final AppDatabase _database;

  RefundService(this._database);

  /// `RF-<pos>-YYYYMMDD-HHMMSS-XXX`. The POS name is folded in so two terminals
  /// refunding in the same second can't collide on the server's unique code.
  /// `RF-<terminal>-<yyyymmdd>-<hhmmss>-<nnn>`, unique per terminal.
  ///
  /// The sequence is resolved against the REFUNDS TABLE, not a counter in
  /// memory: the contract requires codes to survive a reinstall mid-batch, and
  /// a code that changes on retry creates a duplicate refund and double-restocks
  /// inventory.
  ///
  /// It also has to be collision-proof within a single second. The previous
  /// version used `DateTime.now().microsecond`, which on Windows is reported as
  /// 0 — so the suffix was permanently "000" and two refunds in the same second
  /// produced the SAME code. The second then failed the UNIQUE constraint after
  /// the cash had already been handed back.
  Future<String> _generateCode(String? posName) async {
    final now = DateTime.now();
    final d = '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final t = '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final pos = (posName == null || posName.trim().isEmpty)
        ? ''
        : '${posName.trim().replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}-';
    final base = 'RF-$pos$d-$t';

    // Everything already issued in this same second on this terminal.
    final taken = await (_database.select(_database.refunds)
          ..where((r) => r.code.like('$base%')))
        .get();
    var next = 0;
    for (final r in taken) {
      final parts = r.code.split('-');
      final n = int.tryParse(parts.last);
      if (n != null && n >= next) next = n + 1;
    }
    return '$base-${next.toString().padLeft(3, '0')}';
  }

  /// How much of [orderProductId] has already been refunded, so the UI can cap
  /// the next refund and never give back more than was sold.
  Future<Map<int, double>> refundedQuantitiesForOrder(int orderId) async {
    final rows = await (_database.select(_database.refunds)
          ..where((r) => r.orderId.equals(orderId)))
        .get();
    if (rows.isEmpty) return const {};
    final refundIds = rows.map((r) => r.id).toList();
    final lines = await (_database.select(_database.refundLines)
          ..where((l) => l.refundId.isIn(refundIds)))
        .get();
    final out = <int, double>{};
    for (final l in lines) {
      out[l.orderProductId] = (out[l.orderProductId] ?? 0) + l.quantity;
    }
    return out;
  }

  /// Persist a refund locally. Returns the new row.
  ///
  /// Nothing is sent here — the refund is written unsynced and picked up by
  /// [DataSyncService.syncRefundsBulk], exactly like a ticket or a session, so
  /// a refund can be issued with the network down.
  Future<Refund> createRefund({
    required Order order,
    required String method,
    required List<RefundLineDraft> lines,
    String? reason,
    int? refundedBy,
    int? sessionId,
    DateTime? zDay,
    String? posName,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('A refund needs at least one line');
    }

    // Per-unit line totals, so a null draft amount can still be totalled
    // locally for display. The server does its own derivation from the order.
    final opIds = lines.map((l) => l.orderProductId).toList();
    final ops = await (_database.select(_database.orderProducts)
          ..where((op) => op.id.isIn(opIds)))
        .get();
    final opById = {for (final op in ops) op.id: op};

    final components = opIds.isEmpty
        ? <OrderProductComponent>[]
        : await (_database.select(_database.orderProductComponents)
              ..where((c) => c.orderProductId.isIn(opIds)))
            .get();
    final compCostByOpId = <int, double>{};
    for (final c in components) {
      compCostByOpId[c.orderProductId] =
          (compCostByOpId[c.orderProductId] ?? 0) + c.price * c.quantity;
    }

    double perUnit(int opId) {
      final op = opById[opId];
      if (op == null) return 0.0;
      // Same arithmetic as the reports: unitaryDiscount is already baked into
      // unitaryPrice, so only manualDiscount comes off here.
      return (op.unitaryPrice - op.manualDiscount) + (compCostByOpId[opId] ?? 0);
    }

    // Over-refund cap, enforced HERE and not only in the dialog.
    //
    // The server rejects the whole batch when
    // `already refunded + this request > ordered quantity`, and an offline
    // refund that breaks the cap is accepted on screen and rejected days later
    // at sync, in front of nobody. This is the invariant point every caller
    // passes through, so a second entry point cannot bypass it.
    final alreadyRefunded = await refundedQuantitiesForOrder(order.id);
    for (final l in lines) {
      final op = opById[l.orderProductId];
      // Ownership, not just existence: loading lines by id alone would happily
      // accept another order's line, and the refund would then point at a line
      // this order never sold. The server rejects that, but only at sync time.
      if (op == null || op.orderId != order.id) {
        throw ArgumentError(
            'Order product ${l.orderProductId} is not part of order ${order.code}');
      }
      if (l.quantity <= 0) {
        throw ArgumentError('Refund quantity must be greater than zero');
      }
      final prior = alreadyRefunded[l.orderProductId] ?? 0;
      // Tolerance for the usual binary-fraction noise on weighed lines, so a
      // full refund of a 0.3kg line is not rejected by a 1e-15 overshoot.
      if (prior + l.quantity > op.quantity + 0.0001) {
        final remaining = op.quantity - prior;
        throw RefundCapException(
          orderProductId: l.orderProductId,
          ordered: op.quantity,
          alreadyRefunded: prior,
          requested: l.quantity,
          remaining: remaining < 0 ? 0 : remaining,
        );
      }
    }

    // Amount ceiling. The server enforces `0 <= amount <= derived + 0.01`, the
    // one centime absorbing rounding disagreements and nothing more. Checked
    // here so an over-amount is refused BEFORE the drawer opens, rather than
    // 400-ing at sync time with the money already handed over.
    for (final l in lines) {
      final amount = l.amount;
      if (amount == null) continue;
      if (amount < 0) {
        throw ArgumentError('A refund amount cannot be negative');
      }
      final derived = perUnit(l.orderProductId) * l.quantity;
      if (amount > derived + 0.01) {
        throw RefundAmountException(
          orderProductId: l.orderProductId,
          requested: amount,
          maximum: derived,
        );
      }
    }

    var total = 0.0;
    for (final l in lines) {
      total += l.amount ?? perUnit(l.orderProductId) * l.quantity;
    }

    final now = DateTime.now();
    return _database.transaction(() async {
      final refundId = await _database.into(_database.refunds).insert(
            RefundsCompanion.insert(
              code: await _generateCode(posName),
              orderId: order.id,
              orderCode: order.code,
              method: Value(method),
              totalAmount: Value(double.parse(total.toStringAsFixed(2))),
              reason: Value(reason),
              refundedBy: Value(refundedBy),
              refundedAt: Value(now),
              sessionId: Value(sessionId),
              zDay: Value(zDay),
              updatedAt: Value(now),
            ),
          );

      for (final l in lines) {
        final op = opById[l.orderProductId];
        await _database.into(_database.refundLines).insert(
              RefundLinesCompanion.insert(
                refundId: refundId,
                orderProductId: l.orderProductId,
                // Captured now when known; resolved at sync time otherwise.
                orderProductServerId: Value(op?.serverId),
                quantity: Value(l.quantity),
                // Always store a figure so the slip can print a per-line
                // amount; remember whether it was typed or derived, because
                // only a typed one is sent to the server.
                amount: Value(l.amount ?? perUnit(l.orderProductId) * l.quantity),
                amountOverridden: Value(l.amount != null),
                restock: Value(l.restock),
                reason: Value(l.reason),
              ),
            );
      }

      return (await (_database.select(_database.refunds)
                ..where((r) => r.id.equals(refundId)))
              .getSingle());
    });
  }

  Future<List<Refund>> refundsForOrder(int orderId) =>
      (_database.select(_database.refunds)
            ..where((r) => r.orderId.equals(orderId))
            ..orderBy([(r) => OrderingTerm.desc(r.refundedAt)]))
          .get();

  Future<List<RefundLine>> linesForRefund(int refundId) =>
      (_database.select(_database.refundLines)
            ..where((l) => l.refundId.equals(refundId)))
          .get();

  /// Total refunded across a cash session — feeds the Z report's
  /// `refundsTotal`, which was hardcoded to 0 before refunds existed.
  Future<double> totalForSession(int sessionId) async {
    final rows = await (_database.select(_database.refunds)
          ..where((r) => r.sessionId.equals(sessionId)))
        .get();
    return rows.fold<double>(0, (s, r) => s + r.totalAmount);
  }

  /// Total refunded across every session of a z-day.
  Future<double> totalForSessions(List<int> sessionIds) async {
    if (sessionIds.isEmpty) return 0;
    final rows = await (_database.select(_database.refunds)
          ..where((r) => r.sessionId.isIn(sessionIds)))
        .get();
    return rows.fold<double>(0, (s, r) => s + r.totalAmount);
  }

  /// Assemble the printable slip for [refund], resolving product names, serial
  /// numbers and the cashier from the database.
  ///
  /// Works entirely from stored rows, so a reprint days later produces exactly
  /// the same paper as the original — the slip is the customer's proof and must
  /// not drift as the catalogue changes.
  Future<RefundSlipData> slipFor(Refund refund) async {
    final lines = await linesForRefund(refund.id);

    final opIds = lines.map((l) => l.orderProductId).toSet().toList();
    final ops = opIds.isEmpty
        ? <OrderProduct>[]
        : await (_database.select(_database.orderProducts)
              ..where((op) => op.id.isIn(opIds)))
            .get();
    final opById = {for (final op in ops) op.id: op};

    final productIds = ops.map((op) => op.productId).toSet().toList();
    final products = productIds.isEmpty
        ? <Product>[]
        : await (_database.select(_database.products)
              ..where((p) => p.id.isIn(productIds)))
            .get();
    final nameById = {for (final p in products) p.id: p.name};

    final serialIds = ops.map((op) => op.serialId).whereType<int>().toSet();
    final serialById = <int?, String?>{};
    if (serialIds.isNotEmpty) {
      final rows = await (_database.select(_database.serials)
            ..where((t) => t.id.isIn(serialIds)))
          .get();
      for (final r in rows) {
        serialById[r.id] = r.serialNumber;
      }
    }

    String? cashierName;
    if (refund.refundedBy != null) {
      final u = await (_database.select(_database.users)
            ..where((t) => t.id.equals(refund.refundedBy!))
            ..limit(1))
          .getSingleOrNull();
      if (u != null) {
        final full = '${u.firstName} ${u.lastName}'.trim();
        cashierName = full.isEmpty ? u.username : full;
      }
    }

    final slipLines = <RefundSlipLine>[];
    for (final l in lines) {
      final op = opById[l.orderProductId];
      slipLines.add(RefundSlipLine(
        // Falls back to the line id rather than printing an empty name: a slip
        // with a blank line is worse than one naming a row number.
        name: op == null
            ? '#${l.orderProductId}'
            : (nameById[op.productId] ?? '#${op.productId}'),
        quantity: l.quantity,
        amount: l.amount ?? 0,
        restock: l.restock,
        serialNumber: op == null ? null : serialById[op.serialId],
      ));
    }

    return RefundSlipData(
      code: refund.code,
      orderCode: refund.orderCode,
      method: refund.method,
      reason: refund.reason,
      cashierName: cashierName,
      refundedAt: refund.refundedAt,
      total: refund.totalAmount,
      lines: slipLines,
    );
  }

  /// Refunds paid out **in cash**, which are the only ones that physically
  /// leave the drawer.
  ///
  /// Kept separate from [totalForSession] because the two answer different
  /// questions: the total belongs on the report as a revenue line, but only the
  /// cash part may be subtracted from the expected drawer count. Refunding a
  /// card sale by card moves no notes, so counting it would invent a surplus.
  Future<double> cashTotalForSession(int sessionId) =>
      cashTotalForSessions([sessionId]);

  Future<double> cashTotalForSessions(List<int> sessionIds) async {
    if (sessionIds.isEmpty) return 0;
    final rows = await (_database.select(_database.refunds)
          ..where((r) => r.sessionId.isIn(sessionIds)))
        .get();
    return rows
        .where((r) => r.method.toUpperCase() == 'CASH')
        .fold<double>(0, (s, r) => s + r.totalAmount);
  }
}

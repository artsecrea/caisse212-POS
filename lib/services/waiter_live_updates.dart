import 'dart:async';

import 'package:drift/drift.dart' hide Component;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../providers/database_providers.dart';
import 'lan_notification_hub.dart';
import 'waiter_order_money.dart';

/// What the waiter app shows of one order, reduced to what a change is
/// judged by.
class _OrderSnap {
  final int? waiterId;
  final String code;
  final String status;
  final int? tableId;
  final double discountPct;
  final double lineDiscount;
  final String lines; // "id:productId:qty" per line, sorted
  final String paidLines; // ids of lines a ticket carries, sorted
  final double total;
  final double balance;
  final bool allPaid;

  _OrderSnap({
    required this.waiterId,
    required this.code,
    required this.status,
    required this.tableId,
    required this.discountPct,
    required this.lineDiscount,
    required this.lines,
    required this.paidLines,
    required this.total,
    required this.balance,
    required this.allPaid,
  });

  /// Why this order changed, most telling first; null when it didn't.
  String? reasonSince(_OrderSnap old) {
    if (status != old.status && status == 'CANCELED') return 'canceled';
    // Payment is per line, so only a change in which lines are paid is one —
    // a discount also lowers the balance and must not read as money taken.
    if (paidLines != old.paidLines) {
      return allPaid ? 'paid' : 'partial-payment';
    }
    if (tableId != old.tableId) return 'table';
    if (discountPct != old.discountPct || lineDiscount != old.lineDiscount) {
      return 'discount';
    }
    if (lines != old.lines) return 'lines';
    if (status != old.status) return 'status';
    if (total != old.total || balance != old.balance) return 'lines';
    return null;
  }
}

double _r2(double v) => (v * 100).roundToDouble() / 100;

/// Live nudges to waiter phones when an order or a table changes behind them:
///
///  * `order-updated` → the order's waiter, whenever the order's money,
///    lines, discount, table or status moves (a payment at the till, a line
///    added by the cashier…). A hint to re-GET; never stored in the inbox or
///    replayed.
///  * `tables-changed` → every waiter, when a table's occupancy or balance
///    changes, from anyone.
///
/// Rather than hooking every screen that can take a payment or edit an order
/// (there are several, and the next one would be forgotten), it watches the
/// tables those screens write, debounced, and diffs a snapshot. Writes from
/// the waiter's own endpoints trip it too; for them the event just causes a
/// re-GET the app was about to do anyway.
class WaiterLiveUpdateService {
  final Ref _ref;
  final Duration debounce;
  final _uuid = const Uuid();

  StreamSubscription<Set<TableUpdate>>? _sub;
  Timer? _timer;
  bool _scanning = false;
  bool _rescan = false;

  Map<int, _OrderSnap>? _orders;
  Map<int, String>? _tables; // tableId → "orderId|balance"

  WaiterLiveUpdateService(this._ref,
      {this.debounce = const Duration(seconds: 1)});

  AppDatabase get _db => _ref.read(databaseProvider);

  void start() {
    if (_sub != null) return;
    _sub = _db
        .tableUpdates(TableUpdateQuery.onAllTables([
          _db.orders,
          _db.orderProducts,
          _db.orderProductComponents,
          _db.tickets,
          _db.areaTables,
        ]))
        .listen((_) => _schedule());
    // Baseline, so the first real change has something to be compared to.
    _schedule(immediate: true);
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _timer?.cancel();
    _timer = null;
    _orders = null;
    _tables = null;
  }

  void _schedule({bool immediate = false}) {
    _timer?.cancel();
    _timer = Timer(immediate ? Duration.zero : debounce, () {
      // ignore: unawaited_futures
      scan();
    });
  }

  /// Compares the current state with the last snapshot and publishes the
  /// differences. Exposed for tests.
  @visibleForTesting
  Future<void> scan() async {
    if (_scanning) {
      _rescan = true;
      return;
    }
    _scanning = true;
    try {
      do {
        _rescan = false;
        await _scanOnce();
      } while (_rescan);
    } catch (e) {
      Logger.instance.error('WaiterLiveUpdateService: scan failed: $e');
    } finally {
      _scanning = false;
    }
  }

  Future<void> _scanOnce() async {
    final session = _ref.read(currentSessionProvider);
    final tables = await _db.select(_db.areaTables).get();
    final tableOrderIds = {
      for (final t in tables)
        if (t.orderId != null) t.orderId!,
    };

    final orders = await (_db.select(_db.orders)
          ..where((o) {
            final inSession = session == null
                ? const Constant(false)
                : (o.sessionId.equals(session.id) &
                    o.waiterId.isNotNull() &
                    o.status.equals('ONHOLD').not());
            return inSession | o.id.isIn(tableOrderIds);
          }))
        .get();
    final orderIds = orders.map((o) => o.id).toList();
    final lines = orderIds.isEmpty
        ? <OrderProduct>[]
        : await (_db.select(_db.orderProducts)
              ..where((l) => l.orderId.isIn(orderIds)))
            .get();
    final lineIds = lines.map((l) => l.id).toList();
    final comps = lineIds.isEmpty
        ? <OrderProductComponent>[]
        : await (_db.select(_db.orderProductComponents)
              ..where((c) => c.orderProductId.isIn(lineIds)))
            .get();
    final linesByOrder = <int, List<OrderProduct>>{};
    for (final l in lines) {
      (linesByOrder[l.orderId] ??= []).add(l);
    }
    final compsByLine = <int, List<OrderProductComponent>>{};
    for (final c in comps) {
      (compsByLine[c.orderProductId] ??= []).add(c);
    }

    final orderById = {for (final o in orders) o.id: o};
    final moneyById = <int, WaiterOrderMoney>{};
    final snaps = <int, _OrderSnap>{};
    for (final o in orders) {
      final ls = linesByOrder[o.id] ?? const <OrderProduct>[];
      final money = WaiterOrderMoney.of(o, ls, compsByLine);
      moneyById[o.id] = money;
      if (o.waiterId == null) continue;
      var lineDiscount = 0.0;
      for (final l in ls) {
        lineDiscount += WaiterLineMoney.of(l, compsByLine[l.id] ?? const [])
            .discount;
      }
      final sig = [for (final l in ls) '${l.id}:${l.productId}:${l.quantity}']
        ..sort();
      final paidSig = [
        for (final l in ls)
          if (l.ticketId != null) l.id
      ]..sort();
      snaps[o.id] = _OrderSnap(
        waiterId: o.waiterId,
        code: o.code,
        status: o.status,
        tableId: o.tableId,
        discountPct: o.discountPercentage,
        lineDiscount: _r2(lineDiscount),
        lines: sig.join(','),
        paidLines: paidSig.join(','),
        total: _r2(money.total),
        balance: _r2(money.balance),
        allPaid: money.allPaid,
      );
    }

    final tableSnaps = <int, String>{
      for (final t in tables)
        t.id: t.orderId == null
            ? '-'
            : '${t.orderId}|${_r2(moneyById[t.orderId!]?.balance ?? 0)}',
    };

    final oldOrders = _orders;
    final oldTables = _tables;
    _orders = snaps;
    _tables = tableSnaps;
    if (oldOrders == null || oldTables == null) return; // baseline

    final hub = _ref.read(lanNotificationHubProvider);
    final tableNames = {for (final t in tables) t.id: t.name};
    final now = DateTime.now().toIso8601String();

    for (final e in snaps.entries) {
      final old = oldOrders[e.key];
      if (old == null) continue; // new orders show up through the tables/journal
      final reason = e.value.reasonSince(old);
      if (reason == null) continue;
      final o = orderById[e.key]!;
      final money = moneyById[e.key]!;
      hub.publish(
        'waiter:${e.value.waiterId}',
        LanEvent('order-updated', {
          'eventId': _uuid.v4(),
          'orderId': o.id,
          'orderCode': o.code,
          'tableId': o.tableId,
          'tableName': o.tableId == null ? null : tableNames[o.tableId],
          'at': now,
          'reason': reason,
          'allPaid': money.allPaid,
          'totalAmount': _r2(money.total),
          'balanceAmount': _r2(money.balance),
        }),
      );
    }

    final changedTables = <int>{
      for (final e in tableSnaps.entries)
        if (oldTables[e.key] != e.value) e.key,
      for (final id in oldTables.keys)
        if (!tableSnaps.containsKey(id)) id,
    };
    if (changedTables.isNotEmpty) {
      hub.publish(
        'waiter:*',
        LanEvent('tables-changed', {
          'eventId': _uuid.v4(),
          'tableIds': changedTables.toList()..sort(),
          'at': now,
        }),
      );
    }
  }
}

final waiterLiveUpdateServiceProvider = Provider<WaiterLiveUpdateService>((ref) {
  final service = WaiterLiveUpdateService(ref);
  ref.onDispose(service.stop);
  return service;
});

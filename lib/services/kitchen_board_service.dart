import 'package:drift/drift.dart';

import '../data/database/app_database.dart';
import 'kitchen_timing.dart';

/// Kitchen states the KDS reports back; everything past PREPARING means the
/// kitchen is done with the line.
const _doneStates = {'READY', 'COMPLETED', 'DELIVERED', 'SERVED', 'PAID'};

/// One order line as the kitchen sees it.
class KitchenBoardLine {
  final int id;
  final String name;
  final double quantity;
  final String state;
  final String? station;
  final String? note;

  /// When the line reached the kitchen.
  final DateTime kitchenAt;
  final DateTime? preparingAt;

  /// When the kitchen finished it (ready, or served when it skipped READY).
  final DateTime? doneAt;

  const KitchenBoardLine({
    required this.id,
    required this.name,
    required this.quantity,
    required this.state,
    this.station,
    this.note,
    required this.kitchenAt,
    this.preparingAt,
    this.doneAt,
  });

  bool get isDone => _doneStates.contains(state.toUpperCase());
  bool get isPreparing => state.toUpperCase() == 'PREPARING';
  bool get isPending => !isDone && !isPreparing;
}

/// Where an order stands in the kitchen.
enum KitchenStage { pending, preparing, done }

/// How an order's clock compares with the service target.
enum KitchenLevel { ok, warn, late }

class KitchenBoardOrder {
  final int id;
  final String code;
  final int? number;
  final String? table;
  final String type;
  final List<KitchenBoardLine> lines;

  /// The till asked the kitchen to hurry this one (`orders.priority` > 0).
  final bool rush;

  /// Take-away / delivery reference.
  final String? reference;

  const KitchenBoardOrder({
    required this.id,
    required this.code,
    this.number,
    this.table,
    required this.type,
    required this.lines,
    this.rush = false,
    this.reference,
  });

  Iterable<KitchenBoardLine> get _open => lines.where((l) => !l.isDone);

  /// Waiting on any line → pending; else cooking → preparing; else done.
  KitchenStage get stage {
    if (lines.any((l) => l.isPending)) return KitchenStage.pending;
    if (lines.any((l) => l.isPreparing)) return KitchenStage.preparing;
    return KitchenStage.done;
  }

  /// The clock start: the oldest line the kitchen still owes, or — once all
  /// is done — the oldest line of the order.
  DateTime get since {
    final source = _open.isEmpty ? lines : _open;
    return source
        .map((l) => l.kitchenAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// When the last line was finished; null while anything is open.
  DateTime? get doneAt {
    if (_open.isNotEmpty) return null;
    DateTime? last;
    for (final l in lines) {
      final d = l.doneAt;
      if (d != null && (last == null || d.isAfter(last))) last = d;
    }
    return last;
  }

  /// Time the customer has been (or was) waiting on the kitchen.
  Duration age(DateTime now) {
    final end = doneAt ?? now;
    final d = end.difference(since);
    return d.isNegative ? Duration.zero : d;
  }

  KitchenLevel level(DateTime now, int targetMinutes) =>
      kitchenLevel(age(now), targetMinutes);
}

/// Late at [targetMinutes], warned from three quarters of it. 0 = no target.
KitchenLevel kitchenLevel(Duration age, int targetMinutes) {
  if (targetMinutes <= 0) return KitchenLevel.ok;
  final target = Duration(minutes: targetMinutes);
  if (age >= target) return KitchenLevel.late;
  if (age * 4 >= target * 3) return KitchenLevel.warn;
  return KitchenLevel.ok;
}

/// What the board shows at [now]: every order the kitchen still owes, plus
/// the ones finished in the last [keepDone] — the "ready, go and serve it"
/// window. Open orders first, oldest clock first; finished ones after, most
/// recent first.
List<KitchenBoardOrder> kitchenBoardView(
  List<KitchenBoardOrder> orders,
  DateTime now, {
  Duration keepDone = const Duration(minutes: 10),
}) {
  final open = <KitchenBoardOrder>[];
  final done = <KitchenBoardOrder>[];
  for (final o in orders) {
    if (o.stage != KitchenStage.done) {
      open.add(o);
    } else {
      final at = o.doneAt;
      if (at != null && now.difference(at) <= keepDone) done.add(o);
    }
  }
  open.sort((a, b) {
    if (a.rush != b.rush) return a.rush ? -1 : 1;
    return a.since.compareTo(b.since);
  });
  done.sort((a, b) => b.doneAt!.compareTo(a.doneAt!));
  return [...open, ...done];
}

/// Live kitchen picture of one cash session, read from the till's own
/// database — the same rows the KDS reads and writes over the LAN.
class KitchenBoardService {
  final AppDatabase _db;

  KitchenBoardService(this._db);

  Stream<List<KitchenBoardOrder>> watch(int sessionId) {
    final op = _db.orderProducts;
    final o = _db.orders;
    final query = _db.select(op).join([
      innerJoin(o, o.id.equalsExp(op.orderId)),
      leftOuterJoin(_db.products, _db.products.id.equalsExp(op.productId)),
      leftOuterJoin(
          _db.productVariants, _db.productVariants.id.equalsExp(op.variantId)),
      leftOuterJoin(
          _db.stations, _db.stations.id.equalsExp(_db.products.stationId)),
      leftOuterJoin(_db.areaTables, _db.areaTables.id.equalsExp(o.tableId)),
    ])
      ..where(o.sessionId.equals(sessionId) &
          o.status.isNotIn(const ['ONHOLD', 'CANCELED', 'CANCELLED']) &
          op.state.isNotIn(const ['ONHOLD', 'CANCELED', 'CANCELLED']));

    return query.watch().asyncMap((rows) async {
      // A shop with stations only sends station products to the kitchen; a
      // drink with no station would otherwise sit "pending" forever here.
      final hasStations =
          (await (_db.selectOnly(_db.stations)
                    ..addColumns([_db.stations.id.count()]))
                  .map((r) => r.read(_db.stations.id.count()) ?? 0)
                  .getSingle()) >
              0;
      final extraStation = hasStations
          ? {
              for (final r in await _db.select(_db.productStations).get())
                r.productId
            }
          : const <int>{};

      final byOrder = <int, List<KitchenBoardLine>>{};
      final orders = <int, Order>{};
      final tables = <int, String?>{};
      for (final row in rows) {
        final line = row.readTable(op);
        final order = row.readTable(o);
        final product = row.readTableOrNull(_db.products);
        if (hasStations &&
            product?.stationId == null &&
            !extraStation.contains(line.productId)) {
          continue;
        }
        final variant = row.readTableOrNull(_db.productVariants);
        final name = product?.name ?? '#${line.productId}';
        orders[order.id] = order;
        tables[order.id] = row.readTableOrNull(_db.areaTables)?.name;
        byOrder.putIfAbsent(order.id, () => []).add(KitchenBoardLine(
              id: line.id,
              name: variant == null ? name : '$name (${variant.name})',
              quantity: line.quantity,
              state: line.state,
              station: row.readTableOrNull(_db.stations)?.name,
              note: line.note,
              kitchenAt: kitchenSince(line, fallback: order.createdAt),
              preparingAt: line.preparingAt,
              doneAt: line.readyAt ?? line.servedAt,
            ));
      }
      return [
        for (final e in byOrder.entries)
          KitchenBoardOrder(
            id: e.key,
            code: orders[e.key]!.code,
            number: orders[e.key]!.sessionOrderNo,
            table: tables[e.key],
            type: orders[e.key]!.type,
            rush: orders[e.key]!.priority > 0,
            reference: orders[e.key]!.reference,
            lines: e.value..sort((a, b) => a.kitchenAt.compareTo(b.kitchenAt)),
          ),
      ];
    });
  }
}

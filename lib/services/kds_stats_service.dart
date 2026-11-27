import '../data/database/app_database.dart';
import '../domain/services/kds_stats_queries.dart';

/// Per-station kitchen throughput for the current shift.
class StationThroughput {
  final String stationName;
  final int itemsServed; // distinct order-product lines that reached served
  final double quantityServed; // summed quantity (weighted items count once each)

  const StationThroughput({
    required this.stationName,
    required this.itemsServed,
    required this.quantityServed,
  });
}

/// LOCAL, LAN-only kitchen analytics for a single cash session.
///
/// Everything here is derived from the stage timestamps stamped by the KDS
/// endpoints (`preparingAt`/`readyAt`/`servedAt` on `order_products`). Nothing
/// is synced to the cloud — the KDS micro-state machine lives entirely on the
/// POS (see [KdsStatsService] and the server_service KDS handlers).
class KdsSessionStats {
  final int? sessionId;

  /// prep time = readyAt − preparingAt, over items that passed both stages.
  final Duration? avgPrepTime;
  final Duration? medianPrepTime;
  final int prepSampleCount;

  /// pickup wait = servedAt − readyAt, over served (non-cancelled) items.
  final Duration? avgPickupWait;
  final int pickupSampleCount;

  /// Items sent to the kitchen (kdsPrintedAt set) but not yet ready/served.
  final int liveBacklog;

  /// Items cancelled after having been sent to the kitchen.
  final int kitchenCancels;

  final int itemsServed;
  final List<StationThroughput> throughputByStation;

  const KdsSessionStats({
    required this.sessionId,
    required this.avgPrepTime,
    required this.medianPrepTime,
    required this.prepSampleCount,
    required this.avgPickupWait,
    required this.pickupSampleCount,
    required this.liveBacklog,
    required this.kitchenCancels,
    required this.itemsServed,
    required this.throughputByStation,
  });

  static const empty = KdsSessionStats(
    sessionId: null,
    avgPrepTime: null,
    medianPrepTime: null,
    prepSampleCount: 0,
    avgPickupWait: null,
    pickupSampleCount: 0,
    liveBacklog: 0,
    kitchenCancels: 0,
    itemsServed: 0,
    throughputByStation: [],
  );

  bool get hasData =>
      prepSampleCount > 0 ||
      itemsServed > 0 ||
      liveBacklog > 0 ||
      kitchenCancels > 0;
}

/// Computes kitchen stats from the local DB, scoped to one cash session.
///
/// Matches the KDS endpoint scoping: stats belong to the open shift. Pass the
/// session id from `currentSessionProvider`; a null id yields [KdsSessionStats.empty].
class KdsStatsService implements KdsStatsQueries {
  final AppDatabase _db;
  KdsStatsService(this._db);

  static const _terminalDelivered = {'COMPLETED', 'DELIVERED'};
  static const _readyOrTerminal = {'READY', 'COMPLETED', 'DELIVERED', 'CANCELED'};

  @override
  Future<KdsSessionStats> forSession(int? sessionId) async {
    if (sessionId == null) return KdsSessionStats.empty;

    // Order ids in this session.
    final orders = await (_db.select(_db.orders)
          ..where((o) => o.sessionId.equals(sessionId)))
        .get();
    final orderIds = orders.map((o) => o.id).toList();
    if (orderIds.isEmpty) return KdsSessionStats.empty;

    final items = await (_db.select(_db.orderProducts)
          ..where((p) => p.orderId.isIn(orderIds)))
        .get();

    // Station name lookup for throughput grouping.
    final products = await _db.select(_db.products).get();
    final stationIdByProduct = {for (final p in products) p.id: p.stationId};
    final stations = await _db.select(_db.stations).get();
    final stationNameById = {for (final s in stations) s.id: s.name};

    final prepDurations = <Duration>[];
    final pickupDurations = <Duration>[];
    var liveBacklog = 0;
    var kitchenCancels = 0;
    var itemsServed = 0;
    final servedByStation = <String, _StationAcc>{};

    for (final it in items) {
      final state = it.state.toUpperCase();

      if (it.preparingAt != null && it.readyAt != null) {
        final d = it.readyAt!.difference(it.preparingAt!);
        if (!d.isNegative) prepDurations.add(d);
      }
      if (it.readyAt != null &&
          it.servedAt != null &&
          _terminalDelivered.contains(state)) {
        final d = it.servedAt!.difference(it.readyAt!);
        if (!d.isNegative) pickupDurations.add(d);
      }

      // Backlog: sent to kitchen, not yet ready or finished.
      if (it.kdsPrintedAt != null && !_readyOrTerminal.contains(state)) {
        liveBacklog++;
      }

      if (state == 'CANCELED' && it.kdsPrintedAt != null) kitchenCancels++;

      if (_terminalDelivered.contains(state)) {
        itemsServed++;
        final stationId = stationIdByProduct[it.productId];
        final name = (stationId != null ? stationNameById[stationId] : null) ??
            'Unassigned';
        final acc = servedByStation.putIfAbsent(name, () => _StationAcc());
        acc.items++;
        acc.quantity += it.quantity;
      }
    }

    final throughput = servedByStation.entries
        .map((e) => StationThroughput(
              stationName: e.key,
              itemsServed: e.value.items,
              quantityServed: e.value.quantity,
            ))
        .toList()
      ..sort((a, b) => b.itemsServed.compareTo(a.itemsServed));

    return KdsSessionStats(
      sessionId: sessionId,
      avgPrepTime: _avg(prepDurations),
      medianPrepTime: _median(prepDurations),
      prepSampleCount: prepDurations.length,
      avgPickupWait: _avg(pickupDurations),
      pickupSampleCount: pickupDurations.length,
      liveBacklog: liveBacklog,
      kitchenCancels: kitchenCancels,
      itemsServed: itemsServed,
      throughputByStation: throughput,
    );
  }

  static Duration? _avg(List<Duration> ds) {
    if (ds.isEmpty) return null;
    final totalMs =
        ds.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
    return Duration(milliseconds: totalMs ~/ ds.length);
  }

  static Duration? _median(List<Duration> ds) {
    if (ds.isEmpty) return null;
    final sorted = [...ds]..sort((a, b) => a.compareTo(b));
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return Duration(
      milliseconds:
          (sorted[mid - 1].inMilliseconds + sorted[mid].inMilliseconds) ~/ 2,
    );
  }
}

class _StationAcc {
  int items = 0;
  double quantity = 0;
}

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart';
import 'database_providers.dart';

/// Delivery states we set ourselves. The column also carries states the server
/// pushes down (`ACCEPTED`, `PICKED_UP`, `DELIVERED`), which are the platform's
/// to advance — we only ever claim [ready].
class DeliveryStatus {
  static const String ready = 'READY';
  static const String pickedUp = 'PICKED_UP';
  static const String delivered = 'DELIVERED';

  /// True once the kitchen has told the platform this order is waiting.
  static bool isSignalled(String? status) {
    final s = status?.toUpperCase();
    return s == ready || s == pickedUp || s == delivered;
  }
}

/// An order that came from an external platform, with everything the counter
/// needs to hand it over.
class LiveExternalOrder {
  final Order order;
  final List<OrderProduct> lines;
  final Map<int, String> productNames;
  final Customer? customer;

  const LiveExternalOrder({
    required this.order,
    required this.lines,
    required this.productNames,
    this.customer,
  });

  bool get isReadySignalled => DeliveryStatus.isSignalled(order.deliveryStatus);
  bool get isCancelled => order.status == 'CANCELED';

  int get itemCount => lines.fold<int>(0, (sum, l) => sum + l.quantity.round());

  double get total => lines.fold<double>(
      0,
      (sum, l) =>
          sum + (l.unitaryPrice - l.manualDiscount) * l.quantity);
}

/// Orders already accepted into the POS from an external platform.
///
/// Read from the local database, not the queue endpoint: once an order is
/// confirmed the POS owns its content, and the counter needs to see what it
/// actually contains — including any edit made here — rather than the
/// platform's original message. It also keeps working with the connection down,
/// which matters most exactly when a courier is standing there.
///
/// "External" is `source` set to anything but POS. Orders rung up on this
/// terminal are stamped `POS`; the queue stamps the platform (GLOVO, DEALUP,
/// WEB, KOOUL), so a platform added later appears here without a code change.
final liveExternalOrdersProvider =
    StreamProvider.autoDispose<List<LiveExternalOrder>>((ref) {
  final db = ref.watch(databaseProvider);

  // Yesterday, not today: a late-night order handed over after midnight is
  // still the order in front of you.
  final since = DateTime.now().subtract(const Duration(hours: 24));

  final query = db.select(db.orders)
    ..where((o) =>
        o.source.isNotNull() &
        o.source.equals('POS').not() &
        o.date.isBiggerOrEqualValue(since))
    ..orderBy([(o) => OrderingTerm.desc(o.date)]);

  return query.watch().asyncMap((orders) async {
    if (orders.isEmpty) return const <LiveExternalOrder>[];

    final orderIds = orders.map((o) => o.id).toList();
    final lines = await (db.select(db.orderProducts)
          ..where((p) => p.orderId.isIn(orderIds)))
        .get();

    final productIds = lines.map((l) => l.productId).toSet().toList();
    final products = productIds.isEmpty
        ? const <Product>[]
        : await (db.select(db.products)..where((p) => p.id.isIn(productIds)))
            .get();
    final names = {for (final p in products) p.id: p.name};

    final clientIds =
        orders.map((o) => o.clientId).whereType<int>().toSet().toList();
    final customers = clientIds.isEmpty
        ? const <Customer>[]
        : await (db.select(db.customers)..where((c) => c.id.isIn(clientIds)))
            .get();
    final byClient = {for (final c in customers) c.id: c};

    final byOrder = <int, List<OrderProduct>>{};
    for (final l in lines) {
      byOrder.putIfAbsent(l.orderId, () => []).add(l);
    }

    return [
      for (final o in orders)
        LiveExternalOrder(
          order: o,
          lines: byOrder[o.id] ?? const [],
          productNames: names,
          customer: o.clientId == null ? null : byClient[o.clientId!],
        ),
    ];
  });
});

/// Tell the platform an order is waiting on the counter.
///
/// `POST /pos/orders/{code}/ready` is a **signal, not a state change**: the
/// order's own status is untouched and only `deliveryStatus` advances. It has
/// deliberately no offline queue — the platform only cares in the moment, and a
/// "ready" delivered an hour late, after the courier has gone, is worse than
/// none. So a failure here is reported, never queued.
///
/// Returns true when the platform was signalled. False means the order has not
/// reached the backend yet (sync it, then signal) or the network is down.
final signalReadyProvider =
    Provider<Future<bool> Function(Order)>((ref) => (order) async {
          final api = ref.read(apiServiceProvider);
          final db = ref.read(databaseProvider);

          final signalled = await api.signalOrderReady(order.code);
          if (!signalled) return false;

          await (db.update(db.orders)..where((o) => o.id.equals(order.id)))
              .write(OrdersCompanion(
            deliveryStatus: const Value(DeliveryStatus.ready),
            updatedAt: Value(DateTime.now()),
          ));
          Logger.instance
              .info('Signalled ready for pickup: order ${order.code}');
          return true;
        });

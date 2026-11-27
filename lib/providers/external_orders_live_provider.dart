import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/models/live_external_order.dart';
import 'external_order_provider.dart' show externalOrderQueueServiceProvider;

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
    StreamProvider.autoDispose<List<LiveExternalOrder>>((ref) =>
        ref.watch(externalOrderQueueServiceProvider).watchLiveOrders());

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
final signalReadyProvider = Provider<Future<bool> Function(Order)>(
    (ref) => ref.read(externalOrderQueueServiceProvider).signalReady);

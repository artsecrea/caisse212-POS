import '../../data/database/app_database.dart' show Order;
import '../models/external_order_models.dart';
import '../models/live_external_order.dart';

/// Orders from the delivery platforms (DealUp, WhatsApp, Glovo…): the queue
/// waiting to be accepted, and the accepted ones on the counter. An
/// interface because, linked to a hub, the hub takes them in once for every
/// till: standalone, this till does (`ExternalOrderQueueService`).
abstract interface class ExternalOrderService {
  /// Paged browse with optional source/status filters.
  ///
  /// Falls back to the flat `/pending` list when the paged endpoint isn't
  /// available (an older backend), so a terminal pointed at an out-of-date
  /// server still shows its actionable orders instead of an error screen. The
  /// fallback is synthesised into a single page and only makes sense for the
  /// PENDING view, which is what `/pending` returns.
  Future<QueuePage> browse({
    int page = 0,
    int size = 20,
    String? source,
    String? status,
  });

  Future<QueueCounts> counts({String? status});

  /// Confirms [item] on the server (state PENDING→CONFIRMED, DealUp
  /// notified), then writes the order + products to local SQLite.
  ///
  /// Local row is inserted with `isSynced=false` and `status=PENDING`
  /// so the next sync push uploads it via the normal order endpoints.
  ///
  /// - [confirmedByUserId] is stored as `createdBy`.
  /// - [overrideClientId] short-circuits the phone-based customer upsert
  ///   when the cashier picked / modified the customer via the review
  ///   dialog. Otherwise the queue's name/phone goes through the upsert.
  ///
  /// Throws [QueueItemTakenException] when another POS terminal already
  /// confirmed or cancelled this item — the caller should drop it from
  /// the queue view and surface a "taken" toast.
  ///
  /// Returns the local order row id.
  Future<int> confirmAndSave(ExternalQueueItem item,
      {int? confirmedByUserId, int? overrideClientId});

  /// Cancels [item] on the server (state → CANCELLED, DealUp notified),
  /// then writes the order locally with `status=CANCELED` and
  /// `isSynced=false` so the cancellation propagates to the backend on
  /// the next sync push.
  ///
  /// 409 from the server (already cancelled) is treated as success —
  /// the desired end state is reached; we still save the local row for
  /// the audit trail.
  ///
  /// Returns the local order row id.
  Future<int> cancelAndSave(ExternalQueueItem item,
      {int? confirmedByUserId});

  /// Per-source tallies for the filter chips. Never throws — a missing badge
  /// must not take the screen down with it.
  /// Orders already accepted into the POS from an external platform, from
  /// the last 24 hours, newest first, as they change: read from the local
  /// database, not the queue endpoint, so the counter sees what the order
  /// holds now, edits included, and keeps working offline. "External" is
  /// `source` set to anything but POS.
  Stream<List<LiveExternalOrder>> watchLiveOrders();

  /// Tell the platform [order] is waiting on the counter: a signal, not a
  /// state change — only `deliveryStatus` advances, and a failure is
  /// reported, never queued (a late "ready" is worse than none). False
  /// when the order has not reached the backend yet or the network is down.
  Future<bool> signalReady(Order order);
}

import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:uuid/uuid.dart';

import '../data/database/app_database.dart';
import '../domain/models/order_course.dart';
import '../providers/database_providers.dart';
import '../providers/settings_provider.dart';
import 'lan_notification_hub.dart';
import 'waiter_notification_inbox.dart';

/// A line's kitchen progress as the waiter should read it.
///
/// Derived from the stage timestamps as much as from `state`, because `state`
/// can still read `PAID` on rows paid before payment stopped overwriting it,
/// which says nothing about whether the kitchen has sent it out. The timestamps are
/// write-once, so they survive that.
String kitchenStateOf({
  required String state,
  DateTime? preparingAt,
  DateTime? readyAt,
  DateTime? servedAt,
}) {
  final s = state.toUpperCase();
  if (s == 'CANCELED' || s == 'CANCELLED') return 'CANCELED';
  if (readyAt != null ||
      servedAt != null ||
      s == 'READY' ||
      s == 'COMPLETED' ||
      s == 'DELIVERED') {
    return 'READY';
  }
  if (preparingAt != null || s == 'PREPARING') return 'PREPARING';
  return 'PENDING';
}

/// The per-line kitchen fields of the waiter order payloads — empty when the
/// owner has not switched them on. Omitted, never defaulted: an app that sees
/// `PENDING` would believe the kitchen hasn't started.
Map<String, dynamic> waiterKitchenFields(OrderProduct p,
    {required bool enabled}) {
  if (!enabled) return const {};
  final kitchenState = kitchenStateOf(
    state: p.state,
    preparingAt: p.preparingAt,
    readyAt: p.readyAt,
    servedAt: p.servedAt,
  );
  return {
    'kitchenState': kitchenState,
    'readyAt': kitchenState == 'READY'
        ? (p.readyAt ?? p.servedAt)?.toIso8601String()
        : null,
  };
}

/// States in which the kitchen is done with a line — the moment the waiter
/// has food to carry. COMPLETED counts because a KDS without a READY stage
/// goes straight from PREPARING to COMPLETED.
bool isKitchenDoneState(String state) {
  final s = state.toUpperCase();
  return s == 'READY' || s == 'COMPLETED' || s == 'DELIVERED';
}

/// One line as named in a cancel notice. [lineId] is null when the row is
/// already gone (a removal deletes it).
class CanceledLine {
  final int? lineId;
  final String name;
  final num quantity;
  final int? courseNo;

  const CanceledLine({
    this.lineId,
    required this.name,
    required this.quantity,
    this.courseNo,
  });

  Map<String, dynamic> toJson() => {
        'lineId': lineId,
        'name': name,
        'quantity': quantity,
        'courseNo': normalizeCourseNo(courseNo),
      };
}

class _Sent {
  /// null = broadcast to every waiter.
  final int? waiterId;
  final LanEvent event;
  final DateTime at;
  _Sent(this.waiterId, this.event, this.at);
}

/// Kitchen feedback pushed to waiter phones over [LanNotificationHub]:
/// `kitchen-ready`, `kitchen-canceled` and `product-availability`.
///
/// Each is behind its own setting, checked at SEND time so a switch flipped
/// mid-shift takes effect on the next event. Sent events are kept for
/// [replayTtl] and replayed when that waiter's stream (re)connects — the
/// phone that was locked when the tajine came up still hears about it. The
/// app de-duplicates by `eventId`.
class WaiterKitchenEventService {
  static const Duration replayTtl = Duration(minutes: 10);

  /// "Bump whole ticket" on the KDS arrives as one PUT per line. Without a
  /// short window the waiter's phone would buzz once per dish.
  final Duration coalesceWindow;

  final Ref _ref;
  final _uuid = const Uuid();

  final Map<int, Set<int>> _readyByOrder = {};
  final Map<int, Timer> _readyTimers = {};
  final List<_Sent> _sent = [];

  WaiterKitchenEventService(this._ref,
      {this.coalesceWindow = const Duration(milliseconds: 1500)});

  AppDatabase get _db => _ref.read(databaseProvider);

  /// A KDS moved [lineId] of [orderId] into a done state for the first time.
  void lineReady({required int orderId, required int lineId}) {
    if (!_ref.read(settingsProvider).waiterNotifyReady) return;
    (_readyByOrder[orderId] ??= <int>{}).add(lineId);
    _readyTimers[orderId]?.cancel();
    _readyTimers[orderId] = Timer(coalesceWindow, () {
      // ignore: unawaited_futures
      _flushReady(orderId);
    });
  }

  /// Sends whatever is queued for [orderId] now. Exposed for tests.
  @visibleForTesting
  Future<void> flushReady(int orderId) {
    _readyTimers.remove(orderId)?.cancel();
    return _flushReady(orderId);
  }

  Future<void> _flushReady(int orderId) async {
    _readyTimers.remove(orderId);
    final lineIds = _readyByOrder.remove(orderId);
    if (lineIds == null || lineIds.isEmpty) return;
    if (!_ref.read(settingsProvider).waiterNotifyReady) return;
    try {
      final header = await _orderHeader(orderId);
      if (header == null) return;
      final lines = await (_db.select(_db.orderProducts)
            ..where((t) => t.id.isIn(lineIds)))
          .get();
      // A line pulled between the bump and the flush is no longer food to
      // carry — nothing to announce for it.
      final live = lines.where((l) =>
          kitchenStateOf(
              state: l.state,
              preparingAt: l.preparingAt,
              readyAt: l.readyAt,
              servedAt: l.servedAt) ==
          'READY');
      if (live.isEmpty) return;
      final names = await _productNames(live.map((l) => l.productId));
      _publish(
        header.waiterId,
        LanEvent('kitchen-ready', {
          'eventId': _uuid.v4(),
          ...header.toJson(),
          'at': DateTime.now().toIso8601String(),
          'lines': [
            for (final l in live)
              {
                'lineId': l.id,
                'name': names[l.productId] ?? 'Product #${l.productId}',
                'quantity': l.quantity,
                'courseNo': normalizeCourseNo(l.courseNo),
                'kitchenState': 'READY',
              }
          ],
        }),
      );
    } catch (e) {
      Logger.instance.error('WaiterKitchenEventService: ready flush failed: $e');
    }
  }

  /// The till pulled [lines] off [orderId], or cancelled it whole.
  ///
  /// Callers are the POS paths only. A waiter who removes a line from their
  /// own phone must not be told what they just did.
  Future<void> linesCanceled({
    required int orderId,
    List<CanceledLine> lines = const [],
    bool wholeOrder = false,
    String? reason,
  }) async {
    if (!_ref.read(settingsProvider).waiterNotifyCanceled) return;
    if (!wholeOrder && lines.isEmpty) return;
    try {
      final header = await _orderHeader(orderId);
      if (header == null) return;
      _publish(
        header.waiterId,
        LanEvent('kitchen-canceled', {
          'eventId': _uuid.v4(),
          ...header.toJson(),
          'at': DateTime.now().toIso8601String(),
          'wholeOrder': wholeOrder,
          'reason': (reason == null || reason.trim().isEmpty)
              ? null
              : reason.trim(),
          'lines': [for (final l in lines) l.toJson()],
        }),
      );
    } catch (e) {
      Logger.instance.error('WaiterKitchenEventService: cancel notice failed: $e');
    }
  }

  /// The till marked a product EN RUPTURE, or back in stock. Every waiter.
  void productAvailabilityChanged({
    required int productId,
    required String name,
    required bool isAvailable,
  }) {
    if (!_ref.read(settingsProvider).waiterNotifyRupture) return;
    _publish(
      null,
      LanEvent('product-availability', {
        'eventId': _uuid.v4(),
        'productId': productId,
        'name': name,
        'isAvailable': isAvailable,
        'at': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// Events still owed to [waiterId], oldest first, for the stream's replay.
  ///
  /// Skips what this waiter already marked read in their inbox — a dismissed
  /// alert must not come back after an app restart, same as an acknowledged
  /// call.
  List<LanEvent> replayEventsFor(int waiterId) {
    _purgeExpired();
    final inbox = _ref.read(waiterNotificationInboxProvider);
    return [
      for (final s in _sent)
        if ((s.waiterId == null || s.waiterId == waiterId) &&
            !inbox.isRead(waiterId, s.event.data['eventId'] as String))
          s.event
    ];
  }

  void _publish(int? waiterId, LanEvent event) {
    _purgeExpired();
    _sent.add(_Sent(waiterId, event, DateTime.now()));
    _ref.read(waiterNotificationInboxProvider).add(
          id: event.data['eventId'] as String,
          waiterId: waiterId,
          type: event.name,
          data: event.data,
        );
    final devices = _ref
        .read(lanNotificationHubProvider)
        .publish(waiterId == null ? 'waiter:*' : 'waiter:$waiterId', event);
    Logger.instance.info('WaiterKitchenEventService: ${event.name} → '
        '${waiterId == null ? 'all waiters' : 'waiter #$waiterId'} '
        '($devices device(s))');
  }

  void _purgeExpired() {
    final cutoff = DateTime.now().subtract(replayTtl);
    _sent.removeWhere((s) => s.at.isBefore(cutoff));
  }

  Future<_OrderHeader?> _orderHeader(int orderId) async {
    final order = await (_db.select(_db.orders)
          ..where((o) => o.id.equals(orderId)))
        .getSingleOrNull();
    // Counter orders have no waiter to tell.
    if (order == null || order.waiterId == null) return null;
    String? tableName;
    if (order.tableId != null) {
      final table = await (_db.select(_db.areaTables)
            ..where((t) => t.id.equals(order.tableId!)))
          .getSingleOrNull();
      tableName = table?.name;
    }
    return _OrderHeader(
      waiterId: order.waiterId!,
      orderId: order.id,
      orderCode: order.code,
      tableId: order.tableId,
      tableName: tableName,
    );
  }

  Future<Map<int, String>> _productNames(Iterable<int> ids) async {
    final set = ids.toSet();
    if (set.isEmpty) return const {};
    final rows = await (_db.select(_db.products)
          ..where((p) => p.id.isIn(set)))
        .get();
    return {for (final p in rows) p.id: p.name};
  }

  void dispose() {
    for (final t in _readyTimers.values) {
      t.cancel();
    }
    _readyTimers.clear();
    _readyByOrder.clear();
    _sent.clear();
  }
}

class _OrderHeader {
  final int waiterId;
  final int orderId;
  final String orderCode;
  final int? tableId;
  final String? tableName;

  _OrderHeader({
    required this.waiterId,
    required this.orderId,
    required this.orderCode,
    this.tableId,
    this.tableName,
  });

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'orderCode': orderCode,
        'tableId': tableId,
        'tableName': tableName,
      };
}

final waiterKitchenEventServiceProvider =
    Provider<WaiterKitchenEventService>((ref) {
  final service = WaiterKitchenEventService(ref);
  ref.onDispose(service.dispose);
  return service;
});


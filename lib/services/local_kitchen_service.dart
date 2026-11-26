import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart';
import '../domain/services/kitchen_service.dart';
import '../providers/database_providers.dart';
import '../providers/network_provider.dart' show lastKnownOnlineStatusProvider;
import '../providers/sync_manager_provider.dart' show kickOrderSync;
import 'kitchen_board_service.dart';
import 'kitchen_timing.dart' show isCloudTerminalState, kitchenStageStamps;
import 'order_log_service.dart';
import 'waiter_kitchen_events.dart';

/// [KitchenService] on this till's own database: the standalone till. The
/// line and rush writes are the ones the LAN server made for the KDS and the
/// POS kitchen board alike, moved here unchanged so both now call this.
class LocalKitchenService implements KitchenService {
  LocalKitchenService(this._ref);

  final Ref _ref;

  @override
  Stream<List<KitchenBoardOrder>> watchBoard(int sessionId) =>
      _ref.read(kitchenBoardServiceProvider).watch(sessionId);

  /// Move one order line to [newState] exactly as a KDS bump does: stage
  /// stamps, the waiter's "ready" event, the order rollup, and the change-log
  /// entry the KDS polls on. Shared by `PUT /orders/products/<id>` and the
  /// POS kitchen board, so a change made at the till reaches every screen.
  /// Returns false when the line does not exist.
  @override
  Future<bool> setLineState(int lineId, String newState,
      {String source = 'POS'}) async {
    final database = _ref.read(databaseProvider);
    final logService = OrderLogService(database);
    final now = DateTime.now();

    // Read the current row first: needed to stamp each KDS stage timestamp
    // only the FIRST time the item enters that stage (a remake bouncing back
    // to PREPARING must not overwrite the original prep start).
    final existing = await (database.select(database.orderProducts)
          ..where((tbl) => tbl.id.equals(lineId)))
        .getSingleOrNull();
    if (existing == null) return false;

    await (database.update(database.orderProducts)
          ..where((tbl) => tbl.id.equals(lineId)))
        .write(kitchenStageStamps(existing, newState, now).copyWith(
          state: drift.Value(newState),
          updatedAt: drift.Value(now),
        ));

    final orderId = existing.orderId;
    // First time the kitchen is done with this line → the waiter has food
    // to carry. Stage timestamps are write-once, so a remake bounced back
    // and re-bumped does not ring twice.
    if (isKitchenDoneState(newState) &&
        existing.readyAt == null &&
        existing.servedAt == null) {
      _ref
          .read(waiterKitchenEventServiceProvider)
          .lineReady(orderId: orderId, lineId: lineId);
    }
    final allProducts = await (database.select(database.orderProducts)
          ..where((tbl) => tbl.orderId.equals(orderId)))
        .get();
    final allSameStatus = allProducts.every((p) => p.state == newState);
    // Whole order finished in the kitchen → tell the delivery platform.
    // Fired on READY and on any terminal rollup, because a station that goes
    // straight from PREPARING to COMPLETED never passes through READY.
    if (allSameStatus &&
        (newState == 'READY' || isCloudTerminalState(newState))) {
      // ignore: unawaited_futures
      signalOrderReady(orderId);
    }
    if (allSameStatus) {
      final terminal = isCloudTerminalState(newState);
      // Orders are born COMPLETED (cloud-terminal); the kitchen flow lives on
      // the PRODUCTS. So a KDS micro-state rollup (PENDING/PREPARING/READY)
      // must NOT drag order.status back down — that would un-complete a
      // cloud-terminal order. Only a genuinely terminal rollup
      // (COMPLETED/CANCELED/DELIVERED) writes order.status, and only a
      // non-COMPLETED terminal (CANCELED/DELIVERED) is a real change worth
      // re-syncing.
      if (terminal) {
        await (database.update(database.orders)
              ..where((tbl) => tbl.id.equals(orderId)))
            .write(OrdersCompanion(
          status: drift.Value(newState),
          updatedAt: drift.Value(now),
          isSynced: const drift.Value(false),
        ));
        kickOrderSync(_ref, orderId, 'kds-terminal');
      } else {
        // Micro-state rollup: bump updatedAt only, so the change-log cursor
        // still surfaces the order to the KDS on the next poll.
        await (database.update(database.orders)
              ..where((tbl) => tbl.id.equals(orderId)))
            .write(OrdersCompanion(updatedAt: drift.Value(now)));
      }
    }
    await logService.logOrderUpdated(
        orderId, 'Product status updated via $source to $newState');
    return true;
  }

  /// Flag (or unflag) [orderId] as a rush for the kitchen: the KDS shows it
  /// first, flashing, with the alarm. Rides the order's existing `priority`
  /// (> 0 = rush) and the change log, so the KDS picks it up on its next poll.
  @override
  Future<void> setRush(int orderId, bool rush) async {
    final database = _ref.read(databaseProvider);
    await (database.update(database.orders)
          ..where((tbl) => tbl.id.equals(orderId)))
        .write(OrdersCompanion(
      priority: drift.Value(rush ? 1 : 0),
      updatedAt: drift.Value(DateTime.now()),
    ));
    await OrderLogService(database).logOrderUpdated(
        orderId, rush ? 'Kitchen rush requested' : 'Kitchen rush cleared');
  }

  /// Fire-and-forget "kitchen finished" signal for a delivery order, so the
  /// platform (Glovo / Kooul) gets its ready call.
  ///
  /// Deliberately narrow:
  ///   - only orders that came from, or go out on, a delivery platform;
  ///   - only once per order (`readySignalAt` guards it — the endpoint is
  ///     idempotent anyway, this just avoids a pointless round-trip);
  ///   - only while online, and only after the order exists server-side, since
  ///     the endpoint 404s on an unsynced order. There is no offline queue by
  ///     design: a ready signal delivered an hour late is worse than none.
  /// Not awaited by [setLineState] — a KDS bump must not wait on a
  /// delivery-platform round-trip.
  @override
  Future<void> signalOrderReady(int orderId) async {
    {
      try {
        if (!_ref.read(lastKnownOnlineStatusProvider)) return;
        final database = _ref.read(databaseProvider);
        final order = await (database.select(database.orders)
              ..where((o) => o.id.equals(orderId)))
            .getSingleOrNull();
        if (order == null) return;
        if (order.readySignalAt != null) return; // already signalled
        if (order.status == 'CANCELED') return;

        final isPlatform =
            order.externalOrderId != null || order.type == 'DELIVERY';
        if (!isPlatform) return;

        // The signal 404s until the order exists server-side. Push it first,
        // then signal — that's the documented order of operations.
        if (!order.isSynced) {
          final synced = await _ref
              .read(dataSyncServiceProvider)
              .syncSingleOrder(orderId);
          if (!synced) return;
        }

        final ok = await _ref.read(apiServiceProvider).signalOrderReady(order.code);
        if (!ok) return;
        await (database.update(database.orders)
              ..where((o) => o.id.equals(orderId)))
            .write(OrdersCompanion(readySignalAt: drift.Value(DateTime.now())));
      } catch (e) {
        Logger.instance.warning('ready-signal failed for order #$orderId: $e');
      }
    }
  }
}

/// The kitchen's actions for the screens and the LAN server. A hub-linked
/// till overrides this one provider; nothing else changes.
final kitchenServiceProvider =
    Provider<KitchenService>((ref) => LocalKitchenService(ref));

import 'package:drift/drift.dart';

import '../data/database/app_database.dart';

/// Kitchen state of an order line, as `updateOrder` re-inserts it.
class KitchenProgress {
  final String state;
  final DateTime? preparingAt;
  final DateTime? readyAt;
  final DateTime? servedAt;
  final DateTime kitchenAt;

  const KitchenProgress({
    required this.state,
    this.preparingAt,
    this.readyAt,
    this.servedAt,
    required this.kitchenAt,
  });
}

const _finishedStates = {'READY', 'COMPLETED', 'DELIVERED', 'SERVED'};

/// What a line keeps of the kitchen's work when `updateOrder` deletes and
/// re-inserts it. [before] is the row it replaces (null for a new line).
///
/// * new line, or one coming off hold → PENDING, its kitchen clock starts now;
/// * a finished line whose quantity grew → PENDING again from now: the extra
///   units are food nobody has made;
/// * anything else keeps its state, stage times and kitchen clock — a line
///   still cooking just has more to cook.
KitchenProgress carriedKitchenProgress({
  required OrderProduct? before,
  required double quantity,
  required DateTime now,
  DateTime? orderCreatedAt,
}) {
  if (before == null || before.state == 'ONHOLD') {
    return KitchenProgress(state: 'PENDING', kitchenAt: now);
  }
  final grew = quantity > before.quantity + 1e-9;
  if (grew && _finishedStates.contains(before.state.toUpperCase())) {
    return KitchenProgress(state: 'PENDING', kitchenAt: now);
  }
  return KitchenProgress(
    state: before.state,
    preparingAt: before.preparingAt,
    readyAt: before.readyAt,
    servedAt: before.servedAt,
    kitchenAt: kitchenSince(before, fallback: orderCreatedAt ?? now),
  );
}

/// The stage stamps a KDS move of [existing] to [newState] writes.
///
/// Moving forward stamps each stage the first time it is reached (kept for the
/// kitchen stats). Moving back to PENDING is the kitchen reopening the line:
/// it is food to make again, so its stage stamps are cleared and its waiting
/// clock restarts now — otherwise the next poll hands the KDS the old start
/// time and a just-reopened line reads as late at once.
OrderProductsCompanion kitchenStageStamps(
    OrderProduct existing, String newState, DateTime now) {
  if (newState == 'PENDING') {
    if (existing.state.toUpperCase() == 'PENDING') {
      return const OrderProductsCompanion();
    }
    return OrderProductsCompanion(
      preparingAt: const Value(null),
      readyAt: const Value(null),
      servedAt: const Value(null),
      kitchenAt: Value(now),
    );
  }
  const terminal = {'COMPLETED', 'CANCELED', 'CANCELLED', 'DELIVERED'};
  return OrderProductsCompanion(
    preparingAt: newState == 'PREPARING' && existing.preparingAt == null
        ? Value(now)
        : const Value.absent(),
    readyAt: newState == 'READY' && existing.readyAt == null
        ? Value(now)
        : const Value.absent(),
    servedAt: terminal.contains(newState) && existing.servedAt == null
        ? Value(now)
        : const Value.absent(),
  );
}

/// When [line] reached the kitchen. Rows older than schema v61 have no
/// `kitchenAt`; the kitchen ticket's print time is the next best, then the
/// order's own creation ([fallback]).
DateTime kitchenSince(OrderProduct line, {required DateTime fallback}) =>
    line.kitchenAt ?? line.kdsPrintedAt ?? fallback;

/// Finishes, in the kitchen, the lines [ticketId] has just paid for — for a
/// till set to treat payment as the end of the kitchen's work
/// (`AppSettings.paymentCompletesKitchen`). Lines already finished or voided
/// keep their state; payment itself never writes `state`.
Future<void> completeKitchenForTicket(AppDatabase db, int ticketId) async {
  final now = DateTime.now();
  final lines = await (db.select(db.orderProducts)
        ..where((p) =>
            p.ticketId.equals(ticketId) &
            p.state.isIn(const ['PENDING', 'PREPARING', 'READY'])))
      .get();
  for (final line in lines) {
    await (db.update(db.orderProducts)..where((p) => p.id.equals(line.id)))
        .write(kitchenStageStamps(line, 'COMPLETED', now).copyWith(
      state: const Value('COMPLETED'),
      updatedAt: Value(now),
    ));
  }
}

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../domain/models/order_models.dart';
import 'database_providers.dart';

/// Cancellations already recorded on an order, newest first: lines taken off
/// it after it was saved, by the cashier or the waiter. Live, so a waiter's
/// removal shows up on an open panel without a reload.
final orderCancellationsProvider =
    StreamProvider.family<List<RemovedOrderItem>, int>((ref, orderId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.removedOrderItems)
        ..where((r) => r.orderId.equals(orderId))
        ..orderBy([(r) => OrderingTerm.desc(r.removedAt)]))
      .watch();
});

/// A saved line of an order, with its product's name.
class SavedOrderLine {
  final OrderProduct row;
  final String name;
  const SavedOrderLine(this.row, this.name);
}

/// The order's lines as the database holds them right now — what the cart's
/// unsaved removals are measured against.
final savedOrderLinesProvider =
    StreamProvider.family<List<SavedOrderLine>, int>((ref, orderId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.orderProducts).join([
    leftOuterJoin(
        db.products, db.products.id.equalsExp(db.orderProducts.productId)),
  ])
    ..where(db.orderProducts.orderId.equals(orderId));
  return query.watch().map((rows) => [
        for (final r in rows)
          SavedOrderLine(
            r.readTable(db.orderProducts),
            r.readTableOrNull(db.products)?.name ??
                'item #${r.readTable(db.orderProducts).productId}',
          ),
      ]);
});

/// A cancellation the cashier has made in the panel but not saved yet.
class PendingCancellation {
  final String name;
  final double quantity;
  final double unitPrice;
  final bool wasSentToKitchen;
  const PendingCancellation({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.wasSentToKitchen,
  });
  double get amount => quantity * unitPrice;
}

/// What [cart] takes off the saved order when it is saved: lines it loaded and
/// no longer holds, and lines whose quantity it lowered.
///
/// A line that is not in [CurrentOrder.loadedLineIds] was never in this cart —
/// a waiter added it after the load — so its absence is not a removal. Paid
/// lines are never cancelled from the panel.
List<PendingCancellation> pendingCancellations(
    CurrentOrder cart, List<SavedOrderLine> saved) {
  final loaded = cart.loadedLineIds;
  if (cart.orderId == null || loaded == null) return const [];
  final cartById = {
    for (final i in cart.items)
      if (i.id != null) i.id!: i,
  };
  final out = <PendingCancellation>[];
  for (final line in saved) {
    final row = line.row;
    if (row.ticketId != null || !loaded.contains(row.id)) continue;
    final item = cartById[row.id];
    final gone = item == null ? row.quantity : row.quantity - item.quantity;
    if (gone <= 1e-9) continue;
    out.add(PendingCancellation(
      name: item?.productName ?? line.name,
      quantity: gone,
      unitPrice: row.unitaryPrice,
      wasSentToKitchen: row.kdsPrintedQuantity > 0,
    ));
  }
  return out;
}

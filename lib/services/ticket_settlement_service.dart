import 'package:drift/drift.dart';
import 'package:loggecrea/loggecrea.dart';

import '../data/database/app_database.dart';
import '../domain/models/split_bill.dart' show nextTicketNumber;
import 'kitchen_timing.dart' show completeKitchenForTicket;

/// Which order lines a new paid ticket settles.
sealed class SettledLines {
  const SettledLines();
}

/// None: a part paid by amount, whose lines stay open until the last part.
class NoLines extends SettledLines {
  const NoLines();
}

/// Every line of the order that no ticket carries yet.
class UnpaidLinesOf extends SettledLines {
  const UnpaidLinesOf(this.orderId);
  final int orderId;
}

/// These rows, whole.
class WholeRows extends SettledLines {
  const WholeRows(this.rowIds);
  final List<int> rowIds;
}

/// Quantities claimed per row. A row claimed in full is attached; a row
/// claimed in part keeps its id on the unpaid remainder and the paid
/// portion is cut onto a row of its own.
class ClaimedQuantities extends SettledLines {
  const ClaimedQuantities(this.claims);
  final Map<int, double> claims;
}

/// Cuts paid tickets and settles their lines — the one write path behind the
/// payment screen, quick pay, the waiter settlement and the close-time
/// "pay everything as cash".
class TicketSettlementService {
  TicketSettlementService(this._db);

  final AppDatabase _db;
  final _logger = Logger.instance;

  static const double _qtyEpsilon = 0.0001;

  /// One past the highest number on this order, here or on the server.
  Future<String> nextTicketNum(
    int orderId, {
    Iterable<String> serverNums = const [],
  }) async {
    final local = await (_db.select(_db.tickets)
          ..where((t) => t.orderId.equals(orderId)))
        .get();
    return nextTicketNumber(local.map((t) => t.num), serverNums);
  }

  /// Inserts a paid ticket and settles [lines] in one transaction, so a crash
  /// can never leave a paid ticket over lines that still read unpaid.
  ///
  /// [num] null mints the next local number inside the transaction.
  /// [splitFromSettled] decides the ticket's `splitDetails` once the lines
  /// are settled, from the rows that now carry the paid quantities; null
  /// leaves [splitDetails] as it is.
  Future<({int ticketId, String num, Map<int, int> settledRows})>
      createPaidTicket({
    required int orderId,
    String? num,
    required String paymentMethod,
    required double amount,
    int? sessionId,
    DateTime? zDay,
    String? splitDetails,
    SettledLines lines = const NoLines(),
    bool completeKitchen = false,
    String? Function(Map<int, int> settledRows)? splitFromSettled,
  }) async {
    late final int ticketId;
    late final String ticketNum;
    var settled = const <int, int>{};
    await _db.transaction(() async {
      ticketNum = num ?? await nextTicketNum(orderId);
      ticketId = await _db.into(_db.tickets).insert(
            TicketsCompanion.insert(
              num: ticketNum,
              orderId: orderId,
              paymentMethod: paymentMethod,
              amount: amount,
              splitDetails: Value(splitDetails),
              sessionId: Value(sessionId),
              zDay: Value(zDay),
              isPaid: const Value(true),
              printCount: const Value(0),
              date: Value(DateTime.now()),
            ),
          );
      settled = await _settle(lines, ticketId);
      final split = splitFromSettled?.call(settled);
      if (split != null) {
        await (_db.update(_db.tickets)..where((t) => t.id.equals(ticketId)))
            .write(TicketsCompanion(splitDetails: Value(split)));
      }
      if (completeKitchen) await completeKitchenForTicket(_db, ticketId);
    });
    return (ticketId: ticketId, num: ticketNum, settledRows: settled);
  }

  Future<Map<int, int>> _settle(SettledLines lines, int ticketId) async {
    switch (lines) {
      case NoLines():
        return const {};
      case UnpaidLinesOf(:final orderId):
        // Already-paid lines (partials) stay untouched. `state` is the
        // kitchen's and stays as it is.
        await (_db.update(_db.orderProducts)
              ..where((p) =>
                  p.orderId.equals(orderId) &
                  p.ticketId.isNull() &
                  p.state.isNotValue('PAID')))
            .write(OrderProductsCompanion(
          ticketId: Value(ticketId),
          updatedAt: Value(DateTime.now()),
        ));
        return const {};
      case WholeRows(:final rowIds):
        for (final id in rowIds) {
          await (_db.update(_db.orderProducts)..where((t) => t.id.equals(id)))
              .write(OrderProductsCompanion(
            ticketId: Value(ticketId),
            updatedAt: Value(DateTime.now()),
          ));
        }
        return const {};
      case ClaimedQuantities(:final claims):
        return _materializeClaims(claims, ticketId);
    }
  }

  /// Returns, per claimed row, the row that now carries the paid quantity:
  /// the row itself when claimed whole, the new slice otherwise.
  Future<Map<int, int>> _materializeClaims(
    Map<int, double> claims,
    int ticketId,
  ) async {
    final settledRow = <int, int>{};
    for (final entry in claims.entries) {
      final row = await (_db.select(_db.orderProducts)
            ..where((t) => t.id.equals(entry.key)))
          .getSingleOrNull();
      // Gone, or already settled on an earlier ticket — either way this
      // ticket has no claim left to press.
      if (row == null || row.ticketId != null) continue;

      final claimed = entry.value;
      final remainder = row.quantity - claimed;

      if (remainder <= _qtyEpsilon) {
        await (_db.update(_db.orderProducts)..where((t) => t.id.equals(row.id)))
            .write(OrderProductsCompanion(
          ticketId: Value(ticketId),
          updatedAt: Value(DateTime.now()),
        ));
        settledRow[row.id] = row.id;
        continue;
      }

      // Kitchen credit follows the food: the paid slice takes as much of the
      // already-sent quantity as it covers, so the remainder can still fire a
      // modifications-only ticket for what genuinely has not gone through.
      final printedForSlice = row.kdsPrintedQuantity < claimed
          ? row.kdsPrintedQuantity
          : claimed;
      // Same rule for the customer slip: credit follows the units.
      final slippedForSlice = row.orderTicketPrintedQuantity < claimed
          ? row.orderTicketPrintedQuantity
          : claimed;

      await (_db.update(_db.orderProducts)..where((t) => t.id.equals(row.id)))
          .write(OrderProductsCompanion(
        quantity: Value(remainder),
        kdsPrintedQuantity: Value(row.kdsPrintedQuantity - printedForSlice),
        orderTicketPrintedQuantity: Value(
          row.orderTicketPrintedQuantity - slippedForSlice,
        ),
        updatedAt: Value(DateTime.now()),
      ));

      final sliceId = await _db.into(_db.orderProducts).insert(
            OrderProductsCompanion.insert(
              orderId: row.orderId,
              productId: row.productId,
              variantId: Value(row.variantId),
              ticketId: Value(ticketId),
              quantity: Value(claimed),
              unitaryPrice: row.unitaryPrice,
              cost: Value(row.cost),
              unitaryDiscount: Value(row.unitaryDiscount),
              unitaryTva: Value(row.unitaryTva),
              manualDiscount: Value(row.manualDiscount),
              manualDiscountReason: Value(row.manualDiscountReason),
              // serverId is deliberately not carried: the backend knows that
              // id as the original line, and two local rows answering to it
              // would corrupt the delta push and any refund keyed on it.
              saleUomId: Value(row.saleUomId),
              note: Value(row.note),
              // The paid slice keeps the kitchen's progress; the ticket is
              // what makes it paid.
              state: Value(row.state),
              kdsPrintedAt: Value(row.kdsPrintedAt),
              kdsPrintedQuantity: Value(printedForSlice),
              orderTicketPrintedQuantity: Value(slippedForSlice),
              preparingAt: Value(row.preparingAt),
              readyAt: Value(row.readyAt),
              servedAt: Value(row.servedAt),
              zDay: Value(row.zDay),
            ),
          );

      final components = await (_db.select(_db.orderProductComponents)
            ..where((c) => c.orderProductId.equals(row.id)))
          .get();
      for (final component in components) {
        await _db.into(_db.orderProductComponents).insert(
              OrderProductComponentsCompanion.insert(
                componentId: component.componentId,
                orderProductId: sliceId,
                quantity: Value(component.quantity),
                price: Value(component.price),
                isSpecial: Value(component.isSpecial),
                // Carry the snapshot across the split, not the live name.
                name: Value(component.name),
              ),
            );
      }

      settledRow[row.id] = sliceId;
      _logger.info(
        'Settled $claimed of order_product #${row.id} on ticket #$ticketId '
        '(new row #$sliceId, ${remainder.toStringAsFixed(3)} left unpaid)',
      );
    }
    return settledRow;
  }
}

import '../data/database/app_database.dart';
import '../domain/models/order_money.dart';
import '../domain/models/order_money_rows.dart';

double _r2(double v) => (v * 100).roundToDouble() / 100;

double _atLeastZero(double v) => v < 0 ? 0.0 : v;

/// One line's money as the waiter app shows it.
///
/// `unitaryPrice` already has the per-unit pre-discount (`unitaryDiscount`,
/// promotions) taken off, so [net] matches the till's `OrderItem.totalPrice`
/// and [gross] adds that discount back to show what it would have cost.
class WaiterLineMoney {
  final double gross;
  final double discount;
  final double net;

  const WaiterLineMoney(
      {required this.gross, required this.discount, required this.net});

  factory WaiterLineMoney.of(
      OrderProduct p, Iterable<OrderProductComponent> comps) {
    final money = p.amounts(componentsPerUnit: componentsPerUnitOf(comps));
    final net = money.net;
    final discount = money.lineDiscount;
    return WaiterLineMoney(gross: net + discount, discount: discount, net: net);
  }
}

/// An order's money as the waiter app shows it — the same arithmetic as the
/// till's `CurrentOrder.total`: line totals, minus the order-level percentage.
///
/// Payment is per line (a line is paid once a ticket carries it), so the
/// balance is the unpaid lines with the same percentage off.
class WaiterOrderMoney {
  final double subtotal;
  final double discount;
  final double total;
  final double balance;
  final bool allPaid;
  final double discountPercentage;
  final String? discountReason;

  const WaiterOrderMoney({
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.balance,
    required this.allPaid,
    required this.discountPercentage,
    this.discountReason,
  });

  double get paid => total - balance;

  /// [credit] is money already taken on open split-by-amount parts (tickets
  /// that claim no line, see `OrderRepository.moneySplitParts`). It pays
  /// towards the bill without settling any line, so it comes off [balance]
  /// and leaves [allPaid] alone — the same as the till's quick pay.
  factory WaiterOrderMoney.of(Order order, Iterable<OrderProduct> lines,
      Map<int, List<OrderProductComponent>> componentsByLine,
      {double credit = 0}) {
    final pct = order.discountPercentage.clamp(0.0, 100.0).toDouble();
    var gross = 0.0, lineDiscount = 0.0, net = 0.0, unpaidNet = 0.0;
    var owesSomething = false, paidSomething = false;
    for (final p in lines) {
      final paid = p.ticketId != null;
      if (!lineCountsInTotal(p.state, paid: paid)) continue;
      final m = WaiterLineMoney.of(p, componentsByLine[p.id] ?? const []);
      gross += m.gross;
      lineDiscount += m.discount;
      net += m.net;
      if (paid) {
        paidSomething = true;
      } else {
        owesSomething = true;
        unpaidNet += m.net;
      }
    }
    // Nothing owed is not the same as paid: an order whose every line was
    // cancelled before anyone paid was never settled. An order with no lines
    // at all reads as paid, as it always did.
    final allPaid =
        !owesSomething && (paidSomething || lines.isEmpty);
    final orderDiscount = orderDiscountAmount(net, pct);
    return WaiterOrderMoney(
      subtotal: gross,
      discount: lineDiscount + orderDiscount,
      total: applyOrderDiscount(net, pct),
      balance: _atLeastZero(applyOrderDiscount(unpaidNet, pct) - credit),
      allPaid: allPaid,
      discountPercentage: pct,
      discountReason: order.discountReason,
    );
  }

  /// "-10%" for an order-level discount, null when there is none.
  String? get discountLabel {
    if (discountPercentage <= 0) return null;
    final n = discountPercentage == discountPercentage.roundToDouble()
        ? discountPercentage.toInt().toString()
        : discountPercentage.toStringAsFixed(1);
    return '-$n%';
  }

  Map<String, dynamic> toJson() => {
        'subtotalAmount': _r2(subtotal),
        'discountAmount': _r2(discount),
        'totalAmount': _r2(total),
        'paidAmount': _r2(paid),
        'balanceAmount': _r2(balance),
        'allPaid': allPaid,
        'discountLabel': discountLabel,
        'discountReason': (discountReason == null || discountReason!.trim().isEmpty)
            ? null
            : discountReason!.trim(),
      };
}

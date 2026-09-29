import '../data/database/app_database.dart';

double _r2(double v) => (v * 100).roundToDouble() / 100;

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
    var componentTotal = 0.0;
    for (final c in comps) {
      componentTotal += c.price * c.quantity;
    }
    final net = (p.unitaryPrice + componentTotal - p.manualDiscount) * p.quantity;
    final discount = (p.unitaryDiscount + p.manualDiscount) * p.quantity;
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

  factory WaiterOrderMoney.of(Order order, Iterable<OrderProduct> lines,
      Map<int, List<OrderProductComponent>> componentsByLine) {
    final pct = order.discountPercentage.clamp(0.0, 100.0).toDouble();
    var gross = 0.0, lineDiscount = 0.0, net = 0.0, unpaidNet = 0.0;
    var allPaid = true;
    for (final p in lines) {
      final m = WaiterLineMoney.of(p, componentsByLine[p.id] ?? const []);
      gross += m.gross;
      lineDiscount += m.discount;
      net += m.net;
      if (p.ticketId == null) {
        allPaid = false;
        unpaidNet += m.net;
      }
    }
    final orderDiscount = net * pct / 100;
    return WaiterOrderMoney(
      subtotal: gross,
      discount: lineDiscount + orderDiscount,
      total: net - orderDiscount,
      balance: unpaidNet * (1 - pct / 100),
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

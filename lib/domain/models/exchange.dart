/// Exchange: goods brought back, other goods taken in their place.
///
/// It is a refund whose money is not handed back but spent on a new order.
/// The refund keeps everything a refund has (lines, restock, policy, approval,
/// the Z it lands in); the new order is a normal sale, paid partly by an
/// EXCHANGE credit ticket and partly by the customer. Only the difference ever
/// moves real money, in whichever direction it falls.
library;

import '../../data/database/app_database.dart' show Order;
import 'refund_policy.dart';

/// One returned line, as chosen in the refund dialog.
class ExchangeReturnLine {
  final int orderProductId;
  final String name;
  final double quantity;

  /// Money value of the returned quantity (what the credit is made of).
  final double amount;
  final bool restock;

  /// Typed by the cashier rather than derived — sent to the server only then.
  final bool amountOverridden;

  const ExchangeReturnLine({
    required this.orderProductId,
    required this.name,
    required this.quantity,
    required this.amount,
    required this.restock,
    this.amountOverridden = false,
  });
}

/// The exchange under way: returned goods chosen, new goods being rung up.
class ExchangeDraft {
  /// The order the goods came from.
  final Order order;
  final List<ExchangeReturnLine> lines;
  final String? reason;
  final String? reasonCode;
  final int? approvedBy;
  final List<RefundPolicyFlag> policyFlags;
  final bool earlierSale;

  /// Quantities already refunded on other tills (the cap).
  final Map<int, double> refundedElsewhere;

  const ExchangeDraft({
    required this.order,
    required this.lines,
    this.reason,
    this.reasonCode,
    this.approvedBy,
    this.policyFlags = const [],
    this.earlierSale = false,
    this.refundedElsewhere = const {},
  });

  /// Value of the goods brought back.
  double get credit =>
      double.parse(lines.fold<double>(0, (s, l) => s + l.amount).toStringAsFixed(2));
}

/// How an exchange settles once the new order's total is known.
class ExchangeSettlement {
  /// Credit spent on the new order (the EXCHANGE ticket).
  final double creditUsed;

  /// What the customer still pays (new goods cost more).
  final double customerPays;

  /// What goes back to the customer (new goods cost less).
  final double paidBack;

  const ExchangeSettlement({
    required this.creditUsed,
    required this.customerPays,
    required this.paidBack,
  });
}

/// Pure: credit [credit] against a new order worth [newTotal].
ExchangeSettlement settleExchange(double credit, double newTotal) {
  double r(double v) => double.parse(v.toStringAsFixed(2));
  final c = r(credit < 0 ? 0 : credit);
  final n = r(newTotal < 0 ? 0 : newTotal);
  final used = c < n ? c : n;
  return ExchangeSettlement(
    creditUsed: used,
    customerPays: r(n - used),
    paidBack: r(c - used),
  );
}

/// What the exchange section of the new order's receipt prints.
class ExchangeReceipt {
  final String originalOrderCode;
  final String refundCode;
  final List<ExchangeReturnLine> returned;
  final double credit;
  final ExchangeSettlement settlement;

  /// How the customer paid the difference, or how it was given back.
  final String? differenceMethod;

  const ExchangeReceipt({
    required this.originalOrderCode,
    required this.refundCode,
    required this.returned,
    required this.credit,
    required this.settlement,
    this.differenceMethod,
  });
}

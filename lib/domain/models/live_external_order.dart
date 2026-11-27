import '../../data/database/app_database.dart'
    show Customer, Order, OrderProduct;
import 'order_money.dart';
import 'order_money_rows.dart';

/// Delivery states we set ourselves. The column also carries states the server
/// pushes down (`ACCEPTED`, `PICKED_UP`, `DELIVERED`), which are the platform's
/// to advance — we only ever claim [ready].
class DeliveryStatus {
  static const String ready = 'READY';
  static const String pickedUp = 'PICKED_UP';
  static const String delivered = 'DELIVERED';

  /// True once the kitchen has told the platform this order is waiting.
  static bool isSignalled(String? status) {
    final s = status?.toUpperCase();
    return s == ready || s == pickedUp || s == delivered;
  }
}

/// An order that came from an external platform, with everything the counter
/// needs to hand it over.
class LiveExternalOrder {
  final Order order;
  final List<OrderProduct> lines;
  final Map<int, String> productNames;
  final Customer? customer;

  /// What each line's options add to one unit of it, by line id.
  final Map<int, double> componentsPerUnit;

  const LiveExternalOrder({
    required this.order,
    required this.lines,
    required this.productNames,
    this.componentsPerUnit = const {},
    this.customer,
  });

  bool get isReadySignalled => DeliveryStatus.isSignalled(order.deliveryStatus);
  bool get isCancelled => order.status == 'CANCELED';

  int get itemCount => lines.fold<int>(0, (sum, l) => sum + l.quantity.round());

  /// Same figure as the till's order total: owed lines with their options,
  /// less the order percentage.
  double get total => applyOrderDiscount(
      lines
          .where((l) => lineCountsInTotal(l.state, paid: l.ticketId != null))
          .fold<double>(
          0,
          (sum, l) =>
              sum +
              l.amounts(componentsPerUnit: componentsPerUnit[l.id] ?? 0).net),
      order.discountPercentage);
}

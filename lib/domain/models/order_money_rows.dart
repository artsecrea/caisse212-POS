import '../../data/database/app_database.dart';
import 'order_money.dart';

/// Reads [LineAmounts] off stored rows. Kept apart from `order_money.dart` so
/// the formula itself stays free of the database.
extension OrderProductMoney on OrderProduct {
  LineAmounts amounts({double componentsPerUnit = 0}) => LineAmounts(
        unitPrice: unitaryPrice,
        quantity: quantity,
        componentsPerUnit: componentsPerUnit,
        manualDiscount: manualDiscount,
        unitDiscount: unitaryDiscount,
        unitTva: unitaryTva,
      );
}

/// What a line's options add to one unit of it.
double componentsPerUnitOf(Iterable<OrderProductComponent> comps) {
  var total = 0.0;
  for (final c in comps) {
    total += c.price * c.quantity;
  }
  return total;
}

/// The till's money formula, in one place.
///
/// Plain Dart with no imports on purpose: the waiter API, the reports and a
/// future hub must all compute the same figure, and this is the file they
/// share. Every amount is per unit unless the name says otherwise.
///
/// `unitPrice` is the catalogue `finalPrice`: TTC, with the catalogue
/// discount (`unitDiscount`) ALREADY taken off and the tax AMOUNT
/// (`unitTva`) inside it. Options are added on top, per unit of the line.
class LineAmounts {
  const LineAmounts({
    required this.unitPrice,
    required this.quantity,
    this.componentsPerUnit = 0,
    this.manualDiscount = 0,
    this.unitDiscount = 0,
    this.unitTva = 0,
  });

  final double unitPrice;
  final double quantity;
  final double componentsPerUnit;
  final double manualDiscount;
  final double unitDiscount;
  final double unitTva;

  /// What the customer pays for the line, before the order-level percentage.
  double get net => ((unitPrice + componentsPerUnit) - manualDiscount) * quantity;

  /// Catalogue price plus options, before anything came off.
  double get gross => (unitPrice + unitDiscount + componentsPerUnit) * quantity;

  /// Catalogue + manual discount for the whole line.
  double get lineDiscount => (unitDiscount + manualDiscount) * quantity;

  double get tva => unitTva * quantity;

  /// One unit, tax-exclusive, before any discount, options included.
  double get unitSubtotalHt => ((unitPrice - unitTva) + unitDiscount) + componentsPerUnit;
}

/// Whether a line is still owed. A cancelled line stays on the order, so the
/// kitchen and the cloud can see it, but nobody pays for it.
bool lineIsOwed(String state) => state != 'CANCELED' && state != 'CANCELLED';

/// The order-level remise on a total of line nets.
double orderDiscountAmount(double linesNet, double percentage) =>
    linesNet * (percentage / 100);

/// A total of line nets with the order-level percentage taken off.
double applyOrderDiscount(double linesNet, double percentage) =>
    linesNet - orderDiscountAmount(linesNet, percentage);

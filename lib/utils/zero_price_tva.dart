/// Per-unit TVA for a line, filling the gap the catalogue leaves on
/// open-price products.
///
/// TVA is synced as a fixed AMOUNT per unit, so a product the catalogue sells
/// at 0 (the cashier types the price at the till) always arrives with 0 TVA,
/// whatever it ends up sold for. When the admin has set [zeroPriceRate] (a
/// percentage, 20 = 20%), such a line gets the TVA contained in the price the
/// cashier typed. Prices are TTC, so the tax is backed out of the price, not
/// added on top.
///
/// Anything the catalogue priced itself, or gave its own TVA, is left alone.
double lineUnitTva({
  required double catalogPrice,
  required double catalogTva,
  required double unitPrice,
  required double zeroPriceRate,
}) {
  if (catalogPrice > 0 || catalogTva > 0) return catalogTva;
  if (zeroPriceRate <= 0 || unitPrice <= 0) return catalogTva;
  final tva = unitPrice * zeroPriceRate / (100 + zeroPriceRate);
  return (tva * 100).roundToDouble() / 100;
}

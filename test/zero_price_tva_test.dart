import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/utils/zero_price_tva.dart';

void main() {
  test('an open-price product gets the TVA inside the typed price', () {
    // 120 TTC at 20% = 100 HT + 20 TVA.
    expect(
      lineUnitTva(
          catalogPrice: 0, catalogTva: 0, unitPrice: 120, zeroPriceRate: 20),
      20,
    );
  });

  test('rounds to the cent', () {
    // 10 at 10% -> 0.909..
    expect(
      lineUnitTva(
          catalogPrice: 0, catalogTva: 0, unitPrice: 10, zeroPriceRate: 10),
      0.91,
    );
  });

  test('a product with its own price keeps the catalogue TVA', () {
    expect(
      lineUnitTva(
          catalogPrice: 50, catalogTva: 0, unitPrice: 60, zeroPriceRate: 20),
      0,
    );
    expect(
      lineUnitTva(
          catalogPrice: 50, catalogTva: 8.33, unitPrice: 60, zeroPriceRate: 20),
      8.33,
    );
  });

  test('a TVA the catalogue set on a 0-price product is not overwritten', () {
    expect(
      lineUnitTva(
          catalogPrice: 0, catalogTva: 1.5, unitPrice: 30, zeroPriceRate: 20),
      1.5,
    );
  });

  test('rate 0 is off, and a price still at 0 carries no TVA', () {
    expect(
      lineUnitTva(
          catalogPrice: 0, catalogTva: 0, unitPrice: 120, zeroPriceRate: 0),
      0,
    );
    expect(
      lineUnitTva(
          catalogPrice: 0, catalogTva: 0, unitPrice: 0, zeroPriceRate: 20),
      0,
    );
  });
}

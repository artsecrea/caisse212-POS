import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/services/printing_service.dart';

/// The paid receipt had no reduction row at all: a discounted sale printed only
/// its reduced total, so the customer could not see what came off and neither
/// could anyone auditing the till. The order ticket had the row; the payment
/// ticket did not.
///
/// These pin the two things that decide whether it reaches the paper — the
/// field being in the paid-receipt catalogs, and it defaulting ON so an
/// existing till starts printing it without anyone touching settings.

void main() {
  group('the reduction row exists on the paid receipts', () {
    test('customer copy carries the field', () {
      expect(PrinterConfig.fieldCatalog['customer'], contains('discount'));
    });

    test('store copy carries it too', () {
      expect(PrinterConfig.fieldCatalog['store'], contains('discount'));
    });

    test('it sits with the other totals, above VAT', () {
      for (final ticket in ['customer', 'store']) {
        final fields = PrinterConfig.fieldCatalog[ticket]!;
        expect(fields.indexOf('discount'), lessThan(fields.indexOf('tva')),
            reason: 'on $ticket the reduction is read before the tax line');
      }
    });

    test('the order ticket still has it — both documents agree', () {
      expect(PrinterConfig.fieldCatalog['order'], contains('discount'));
    });
  });

  group('it prints without anyone changing settings', () {
    test('defaults ON for both paid receipts', () {
      for (final ticket in ['customer', 'store']) {
        expect(PrinterConfig.fieldDefaultOn('discount', ticket), isTrue,
            reason: 'a till that upgrades must start showing the reduction on '
                '$ticket, not wait to be configured');
      }
    });

    test('VAT now defaults ON — a receipt handed over shows its tax', () {
      for (final ticket in ['customer', 'store']) {
        expect(PrinterConfig.fieldDefaultOn('tva', ticket), isTrue,
            reason: 'being opt-in read as broken, not as a choice');
      }
    });

    test('cash given and change stay opt-in', () {
      for (final field in ['amountGiven', 'change']) {
        expect(PrinterConfig.fieldDefaultOn(field, 'customer'), isFalse,
            reason: '$field is a counter-shop habit, not a legal line');
      }
    });

    test('and it is still on for the order ticket', () {
      expect(PrinterConfig.fieldDefaultOn('discount', 'order'), isTrue);
    });
  });
}

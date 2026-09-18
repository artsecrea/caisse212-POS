import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/services/printing_service.dart';

/// Ticket row ordering.
///
/// The order a band's rows come back in is what the printer emits, so these
/// pin the two things that decide it: that an operator's arrangement is
/// honoured, and that a saved arrangement written by an older build still
/// prints every row a newer build knows about.
void main() {
  PrinterConfig withOrder(Map<String, List<String>> order) =>
      PrinterConfig(ticketFieldOrder: order);

  group('orderedFields', () {
    test('an untouched config prints the catalogue order', () {
      const config = PrinterConfig();
      expect(
        config.orderedFields('customer', 'info'),
        ['orderCode', 'date', 'cashier', 'waiter', 'orderType', 'table',
         'persons', 'customerName', 'customerPhone', 'deliveryAddress',
         'paymentMethod'],
      );
    });

    test('the operator arrangement is honoured', () {
      final config = withOrder({
        'customer': ['table', 'orderCode', 'date'],
      });
      final info = config.orderedFields('customer', 'info');
      expect(info.take(3), ['table', 'orderCode', 'date']);
    });

    test('fields the saved order never mentioned still print', () {
      // What an order saved before a field existed has to survive: the row is
      // absent from the list, and dropping it would silently stop printing it.
      final config = withOrder({
        'customer': ['table', 'orderCode'],
      });
      final info = config.orderedFields('customer', 'info');
      expect(info.toSet(),
          PrinterConfig().orderedFields('customer', 'info').toSet());
      expect(info.length, info.toSet().length, reason: 'no duplicates');
    });

    test('a band never leaks a field belonging to another', () {
      // The saved list is flat across every band, so the filter is the only
      // thing stopping a total from being emitted in the letterhead.
      final config = withOrder({
        'customer': ['tva', 'table', 'storeAddress', 'barcode', 'orderCode'],
      });
      expect(config.orderedFields('customer', 'header'), ['storeAddress',
        'storePhone']);
      expect(config.orderedFields('customer', 'trailer'), ['barcode']);
      expect(config.orderedFields('customer', 'info').contains('tva'), isFalse);
      expect(config.orderedFields('customer', 'totals').first, 'tva');
    });

    test('an id the catalogue does not know is ignored', () {
      final config = withOrder({
        'kds': ['nonsense', 'table', 'orderCode'],
      });
      final info = config.orderedFields('kds', 'info');
      expect(info.contains('nonsense'), isFalse);
      expect(info.take(2), ['table', 'orderCode']);
    });

    test('a repeated id is only printed once', () {
      final config = withOrder({
        'order': ['table', 'table', 'orderCode'],
      });
      final info = config.orderedFields('order', 'info');
      expect(info.where((f) => f == 'table').length, 1);
    });

    test('every catalogued field belongs to a band', () {
      // A field with no zone entry falls back to 'info'. That is a safe
      // default but a silent one, so the mapping is checked rather than
      // trusted: a new field added to the catalogue and forgotten here would
      // otherwise turn up in the middle of the order info with no warning.
      for (final entry in PrinterConfig.fieldCatalog.entries) {
        for (final field in entry.value) {
          expect(PrinterConfig.fieldZone.containsKey(field), isTrue,
              reason: '${entry.key}.$field has no band');
        }
      }
    });

    test('the flat form round-trips every band in print order', () {
      const config = PrinterConfig();
      final flat = config.orderedFieldsFlat('order');
      expect(flat.first, 'storeAddress', reason: 'letterhead leads');
      expect(flat.last, 'barcode', reason: 'barcode trails');
      expect(flat.toSet(), PrinterConfig.fieldCatalog['order']!.toSet());
    });
  });

  group('parseTicketFieldOrder', () {
    test('junk does not take the printer config down with it', () {
      expect(PrinterConfig.parseTicketFieldOrder('{not json'), isEmpty);
      expect(PrinterConfig.parseTicketFieldOrder(null), isEmpty);
      expect(PrinterConfig.parseTicketFieldOrder(42), isEmpty);
    });

    test('non-string entries are dropped, the rest survive', () {
      final parsed = PrinterConfig.parseTicketFieldOrder({
        'customer': ['table', 7, null, 'date'],
      });
      expect(parsed['customer'], ['table', 'date']);
    });

    test('a JSON string decodes the same as a map', () {
      expect(
        PrinterConfig.parseTicketFieldOrder('{"kds":["table","time"]}'),
        {'kds': ['table', 'time']},
      );
    });
  });

  group('waiter field', () {
    test('is offered on every ticket type, including the kitchen ticket', () {
      for (final ticket in ['order', 'customer', 'store', 'kds']) {
        expect(PrinterConfig.fieldCatalog[ticket], contains('waiter'),
            reason: '$ticket should offer the waiter row');
      }
    });

    test('prints in the info band, next to the cashier', () {
      expect(PrinterConfig.zoneOf('waiter'), 'info');
      const config = PrinterConfig();
      final info = config.orderedFields('order', 'info');
      expect(info.indexOf('waiter'), info.indexOf('cashier') + 1);
    });

    test('defaults to on — it is not one of the opt-in extras', () {
      for (final ticket in ['order', 'customer', 'store', 'kds']) {
        expect(PrinterConfig.fieldDefaultOn('waiter', ticket), isTrue,
            reason: '$ticket waiter row should print without being enabled');
      }
    });

    test('a layout saved before it existed still gets it, at the band end', () {
      // The operator arranged their receipt on an older build; the new row has
      // to appear without them re-saving.
      final config = PrinterConfig(ticketFieldOrder: {
        'customer': ['table', 'orderCode', 'date', 'cashier'],
      });
      final info = config.orderedFields('customer', 'info');
      expect(info.take(4), ['table', 'orderCode', 'date', 'cashier']);
      expect(info, contains('waiter'));
    });
  });
}

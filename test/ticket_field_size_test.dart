import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/services/printing_service.dart';

/// Per-field ticket sizing.
///
/// The thing that must not break here is the *absence* of a choice. A till
/// that has never opened this screen has an empty size map, and every line on
/// its paper has to keep resolving to exactly the size it resolved to before
/// the feature existed — otherwise an update silently reformats every receipt
/// in every shop. Most of these tests are about that, not about the sizes.

Future<PrintingService> serviceWith(PrinterConfig config) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final service = PrintingService();
  await service.saveConfig(prefs, config);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tier mapping', () {
    test('height grows before width does', () {
      // Width costs columns on a receipt; height costs nothing but paper.
      expect(PrinterConfig.tierSize(1),
          (width: PosTextSize.size1, height: PosTextSize.size1));
      expect(PrinterConfig.tierSize(2),
          (width: PosTextSize.size1, height: PosTextSize.size2));
      expect(PrinterConfig.tierSize(3),
          (width: PosTextSize.size2, height: PosTextSize.size2));
      expect(PrinterConfig.tierSize(4),
          (width: PosTextSize.size2, height: PosTextSize.size3));
    });

    test('nothing goes wider than double', () {
      for (final tier in PrinterConfig.textTiers.keys) {
        expect(PrinterConfig.tierSize(tier).width.value, lessThanOrEqualTo(2),
            reason: 'tier $tier would wrap into the column beside it');
      }
    });
  });

  group('resolving a field', () {
    test('an untouched field follows the global text size', () async {
      // The three global sizes land on tiers 1-3, and a header line sits one
      // tier above its body — exactly what the old resolvers did.
      for (final global in const [1, 2, 3]) {
        final service = await serviceWith(PrinterConfig(textSize: global));
        expect(service.debugFieldSize('customer', 'table'),
            PrinterConfig.tierSize(global),
            reason: 'body at global $global');
        expect(service.debugFieldSize('customer', 'total', isHeader: true),
            PrinterConfig.tierSize(global == 3 ? 3 : global + 1),
            reason: 'header at global $global');
      }
    });

    test('a pinned field ignores the global size', () async {
      final service = await serviceWith(const PrinterConfig(
        textSize: 1,
        ticketFieldSizes: {
          'customer': {'table': 4}
        },
      ));
      expect(service.debugFieldSize('customer', 'table'),
          (width: PosTextSize.size2, height: PosTextSize.size3));
    });

    test('a pin overrides the header tier too', () async {
      final service = await serviceWith(const PrinterConfig(
        textSize: 3,
        ticketFieldSizes: {
          'customer': {'total': 1}
        },
      ));
      expect(service.debugFieldSize('customer', 'total', isHeader: true),
          (width: PosTextSize.size1, height: PosTextSize.size1));
    });

    test('a pin on one ticket type does not leak into another', () async {
      final service = await serviceWith(const PrinterConfig(
        ticketFieldSizes: {
          'kds': {'table': 4}
        },
      ));
      expect(service.debugFieldSize('kds', 'table').height, PosTextSize.size3);
      expect(service.debugFieldSize('customer', 'table').height,
          isNot(PosTextSize.size3));
    });
  });

  group('what prints by default', () {
    test('the order ticket keeps printing VAT until it is turned off', () {
      // It always has. Adding a switch must not remove a line from paper that
      // is already coming out of tills in the field.
      expect(PrinterConfig.fieldDefaultOn('tva', 'order'), isTrue);
      expect(PrinterConfig.fieldDefaultOn('subtotal', 'order'), isTrue);
      expect(PrinterConfig.fieldDefaultOn('discount', 'order'), isTrue);
    });

    test('the paid receipts show VAT and keep the cash block off', () {
      for (final ticket in const ['customer', 'store']) {
        // VAT used to be opt-in here, on the reasoning that turning it on
        // would silently add a line to every receipt in the field. That does
        // not hold for a document handed to a customer: a receipt with no tax
        // line reads as broken rather than as a choice.
        expect(PrinterConfig.fieldDefaultOn('tva', ticket), isTrue);
        // Cash given and change stay opt-in — a counter-shop habit, not a
        // legal line.
        expect(PrinterConfig.fieldDefaultOn('amountGiven', ticket), isFalse);
        expect(PrinterConfig.fieldDefaultOn('change', ticket), isFalse);
        expect(PrinterConfig.fieldDefaultOn('table', ticket), isTrue);
      }
    });

    test('the ticketless form of the question still answers as it did', () {
      expect(PrinterConfig.fieldDefaultOn('tva'), isFalse);
      expect(PrinterConfig.fieldDefaultOn('cashier'), isTrue);
    });
  });

  group('persistence', () {
    test('sizes survive a JSON round trip', () {
      const config = PrinterConfig(ticketFieldSizes: {
        'order': {'total': 3, 'items': 2}
      });
      final back = PrinterConfig.fromJson(config.toJson());
      expect(back.fieldSize('order', 'total'), 3);
      expect(back.fieldSize('order', 'items'), 2);
      expect(back.fieldSize('order', 'table'), 0);
    });

    test('an unknown tier is dropped, not clamped', () {
      // Written by a build that knows more sizes than this one. Falling back
      // to the global size is honest; guessing at a neighbouring tier is not.
      final parsed = PrinterConfig.parseTicketFieldSizes({
        'order': {'total': 9, 'items': 2}
      });
      expect(parsed['order']!.containsKey('total'), isFalse);
      expect(parsed['order']!['items'], 2);
    });

    test('junk in the stored map does not take the config down', () {
      expect(PrinterConfig.parseTicketFieldSizes(null), isEmpty);
      expect(PrinterConfig.parseTicketFieldSizes('not json at all'), isEmpty);
      expect(
          PrinterConfig.parseTicketFieldSizes({
            'order': {'total': 'large'}
          })['order'],
          isEmpty);
    });
  });

  group('the settings list', () {
    test('every ticket type offers sizes, toggles first', () {
      for (final ticket in const ['order', 'customer', 'store', 'kds']) {
        final all = PrinterConfig.sizableFields(ticket);
        expect(all, isNotEmpty);
        expect(all.toSet().length, all.length, reason: '$ticket has a dupe');
        expect(all.first, PrinterConfig.fieldCatalog[ticket]!.first);
        expect(all.last, PrinterConfig.sizeOnlyCatalog[ticket]!.last);
      }
    });

    test('the parts that carry the document have no off switch', () {
      // Turning off the total, or the product lines, only ever produces a
      // broken receipt — so they get a size input and nothing else.
      for (final ticket in const ['order', 'customer', 'store']) {
        expect(PrinterConfig.sizeOnlyCatalog[ticket], contains('total'));
        expect(PrinterConfig.fieldCatalog[ticket], isNot(contains('total')));
        expect(PrinterConfig.fieldCatalog[ticket], isNot(contains('items')));
      }
    });
  });
}

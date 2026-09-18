import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/services/printing_service.dart';

/// Whole-order KDS mode.
///
/// For a kitchen with no stations that wants two or three identical tickets.
/// The thing to protect is that turning it on cannot change what an existing
/// station-based kitchen prints, and that the copy count can never reach the
/// printer as a number that would spool forever or print nothing.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('defaults', () {
    test('off, one copy — an existing kitchen is untouched', () {
      const config = PrinterConfig();
      expect(config.kdsFullOrderMode, isFalse);
      expect(config.kdsCopies, 1);
      // The station machinery it overrides keeps its own defaults.
      expect(config.splitKdsByStation, isTrue);
      expect(config.printKdsUnassigned, isTrue);
    });
  });

  group('copy count', () {
    test('survives a round trip', () {
      const config = PrinterConfig(kdsFullOrderMode: true, kdsCopies: 3);
      final back = PrinterConfig.fromJson(config.toJson());
      expect(back.kdsFullOrderMode, isTrue);
      expect(back.kdsCopies, 3);
    });

    test('a stored count outside the range is clamped, not honoured', () {
      // Hand-edited prefs, or a newer build. Zero would print nothing at all
      // and leave the kitchen waiting; a huge number would spool the roll.
      final json = const PrinterConfig().toJson()
        ..['kdsCopies'] = 0;
      expect(PrinterConfig.fromJson(json).kdsCopies, 1);

      final tooMany = const PrinterConfig().toJson()
        ..['kdsCopies'] = 500;
      expect(PrinterConfig.fromJson(tooMany).kdsCopies, 9);
    });

    test('a missing count reads as one', () {
      final json = const PrinterConfig().toJson()..remove('kdsCopies');
      expect(PrinterConfig.fromJson(json).kdsCopies, 1);
    });
  });

  group('linked options', () {
    test('on by default, under the name the customer chose', () {
      const config = PrinterConfig();
      expect(config.printLinkedComponents, isTrue);
      expect(config.linkedComponentLabel, LinkedComponentLabel.component);
    });

    test('both settings survive a round trip', () {
      const config = PrinterConfig(
        printLinkedComponents: false,
        linkedComponentLabel: LinkedComponentLabel.product,
      );
      final back = PrinterConfig.fromJson(config.toJson());
      expect(back.printLinkedComponents, isFalse);
      expect(back.linkedComponentLabel, LinkedComponentLabel.product);
    });

    test('an unknown label index is clamped, not crashed on', () {
      // A config written by a build that knows more label styles than this
      // one. An unclamped index would throw out of the constructor and take
      // the whole printer config down.
      final json = const PrinterConfig().toJson()
        ..['linkedComponentLabel'] = 99;
      expect(PrinterConfig.fromJson(json).linkedComponentLabel,
          LinkedComponentLabel.product);

      final negative = const PrinterConfig().toJson()
        ..['linkedComponentLabel'] = -3;
      expect(PrinterConfig.fromJson(negative).linkedComponentLabel,
          LinkedComponentLabel.component);
    });

    test('a config saved before these existed keeps the feature on', () {
      final json = const PrinterConfig().toJson()
        ..remove('printLinkedComponents')
        ..remove('linkedComponentLabel');
      final back = PrinterConfig.fromJson(json);
      expect(back.printLinkedComponents, isTrue);
      expect(back.linkedComponentLabel, LinkedComponentLabel.component);
    });
  });

  group('persistence', () {
    test('the mode and its count reach prefs and come back', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = PrintingService();

      await service.saveConfig(
        prefs,
        const PrinterConfig(kdsFullOrderMode: true, kdsCopies: 4),
      );

      expect(prefs.getBool('printer_kds_full_order_mode'), isTrue);
      expect(prefs.getInt('printer_kds_copies'), 4);
      expect(service.config.kdsCopies, 4);
    });

    test('the linked-option settings reach prefs too', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = PrintingService();

      await service.saveConfig(
        prefs,
        const PrinterConfig(
          printLinkedComponents: false,
          linkedComponentLabel: LinkedComponentLabel.product,
        ),
      );

      expect(prefs.getBool('printer_print_linked_components'), isFalse);
      expect(prefs.getInt('printer_linked_component_label'),
          LinkedComponentLabel.product.index);
      expect(service.config.linkedComponentLabel,
          LinkedComponentLabel.product);
    });
  });
}

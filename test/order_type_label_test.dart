import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/services/printing_service.dart';

/// The "Type:" line every ticket carries.
///
/// DELIVERY used to fall through to the take-away branch, so a delivery order
/// printed "À emporter" in French: the kitchen bagged it for the counter and
/// the customer read the wrong thing. Each of the three types has to name
/// itself, in every language a ticket can be printed in.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late PrintingService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = PrintingService();
  });

  Future<void> printingIn(String language) => service.saveConfig(
      prefs, service.config.copyWith(printingLanguage: language));

  group('the bug this protects', () {
    test('French delivery says livraison, not à emporter', () async {
      await printingIn('fr');

      final label = service.debugOrderTypeText('DELIVERY').toLowerCase();
      expect(label, contains('livraison'));
      expect(label, isNot(contains('emporter')));
    });

    test('the uppercase variant the KDS ticket uses is fixed too', () async {
      await printingIn('fr');

      final label =
          service.debugOrderTypeText('DELIVERY', uppercase: true).toLowerCase();
      expect(label, contains('livraison'));
      expect(label, isNot(contains('emporter')));
    });
  });

  group('every type names itself', () {
    // Arabic prints its "upper" labels in latin on purpose — that line goes
    // through the plain code-table path, which can't render Arabic.
    for (final language in const ['en', 'fr', 'es', 'ar']) {
      test('in $language, no two types share a label', () async {
        await printingIn(language);

        for (final uppercase in const [false, true]) {
          final labels = [
            for (final type in const ['DINE_IN', 'TAKE_AWAY', 'DELIVERY'])
              service.debugOrderTypeText(type, uppercase: uppercase)
          ];
          expect(labels.every((l) => l.isNotEmpty), isTrue,
              reason: 'an untranslated key would print as the key name');
          expect(labels.toSet().length, 3,
              reason: 'got $labels (uppercase: $uppercase)');
        }
      });
    }
  });

  group('fallback', () {
    test('an unknown or absent type reads as take away', () async {
      await printingIn('en');

      // What the POS defaults a new order to, so it is the safe fallback for
      // a type a newer server sent that this build doesn't know.
      final takeAway = service.debugOrderTypeText('TAKE_AWAY');
      expect(service.debugOrderTypeText(null), takeAway);
      expect(service.debugOrderTypeText('SOMETHING_NEW'), takeAway);
    });
  });
}

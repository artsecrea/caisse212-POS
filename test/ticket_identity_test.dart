import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/services/printing_service.dart';

/// The same order printed two different tickets depending on which button
/// asked for it: the main screen's print button passed `storeName: ""` — not
/// null, so the header emitted an EMPTY bold line and the shop's name never
/// appeared — while the automatic path passed the configured name. Resolution
/// now lives in the service, and blank counts as "not supplied".

void main() {
  late PrintingService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'business_name': 'Chez Amina',
      'business_address': '12 Rue Centrale',
      'business_phone': '0555 00 11 22',
    });
    service = PrintingService();
    // initialize() wants a Ref and a live printer stream; the field resolver
    // only needs prefs, which saveConfig sets on the same singleton.
    await service.saveConfig(
        await SharedPreferences.getInstance(), const PrinterConfig());
  });

  group('falling back to the configured identity', () {
    test('an empty string is not a store name — this was the bug', () {
      expect(service.debugStoreField('', 'business_name'), 'Chez Amina');
    });

    test('whitespace is not one either', () {
      expect(service.debugStoreField('   ', 'business_name'), 'Chez Amina');
    });

    test('null falls back, which is what the auto path always relied on', () {
      expect(service.debugStoreField(null, 'business_name'), 'Chez Amina');
      expect(
          service.debugStoreField(null, 'business_address'), '12 Rue Centrale');
      expect(service.debugStoreField(null, 'business_phone'), '0555 00 11 22');
    });

    test('a real value from the caller still wins', () {
      expect(service.debugStoreField('Pop-up stall', 'business_name'),
          'Pop-up stall');
    });
  });

  group('when there is nothing to print', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({'business_name': '   '});
      await service.saveConfig(
          await SharedPreferences.getInstance(), const PrinterConfig());
    });

    test('a blank setting yields null, not a blank line', () async {
      // The layout omits the line on null and emits an empty bold line on '',
      // so this distinction is the whole point.
      expect(service.debugStoreField(null, 'business_name'), isNull);
      expect(service.debugStoreField('', 'business_name'), isNull);
    });

    test('an unset key yields null', () async {
      expect(service.debugStoreField(null, 'business_address'), isNull);
    });
  });
}

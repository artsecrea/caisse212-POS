import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/services/printing_service.dart';

/// The station name is the one line the kitchen reads at a glance, and it was
/// the one string on the KDS ticket that did not take the Arabic raster path —
/// `_safe()` maps everything outside Latin-1 to '?', so an Arabic station
/// printed `*** ?????? ***`. These pin the banner text and the sanitiser that
/// exposed the problem.

void main() {
  late PrintingService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = PrintingService();
    await service.saveConfig(
        await SharedPreferences.getInstance(), const PrinterConfig());
  });

  group('the banner text', () {
    test('a normal name is used as it stands', () {
      expect(service.debugStationBanner('Bar'), 'Bar');
    });

    test('an Arabic name survives intact — it must reach the raster path', () {
      expect(service.debugStationBanner('المطبخ'), 'المطبخ');
    });

    test('a blank name falls back instead of printing "***  ***"', () {
      expect(service.debugStationBanner(''), 'General');
      expect(service.debugStationBanner('   '), 'General');
    });

    test('surrounding whitespace is trimmed, not printed', () {
      expect(service.debugStationBanner('  Grill  '), 'Grill');
    });
  });

  group('why the raster path is not optional', () {
    test('the thermal sanitiser destroys Arabic', () {
      // Not a complaint about the sanitiser — mapping unencodable bytes to '?'
      // is what stops a ticket hanging the printer mid-stream. It is why the
      // banner has to render Arabic as a bitmap instead of feeding it here.
      expect(PrintingService.sanitizeForThermalTest('المطبخ'), '??????');
    });

    test('Latin names pass through it unharmed', () {
      expect(PrintingService.sanitizeForThermalTest('Bar'), 'Bar');
      expect(PrintingService.sanitizeForThermalTest('Café'), 'Café');
    });

    test('a French name still uppercases safely for the Latin branch', () {
      expect(PrintingService.sanitizeForThermalTest('Café').toUpperCase(),
          'CAFÉ');
    });
  });
}

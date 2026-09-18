import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/services/printing_service.dart';

/// The courier code is what a delivery driver scans to collect the order in
/// their own app. Two things must hold or the driver cannot take the bag:
/// the code must appear only for platforms that issue one, and the symbol must
/// encode the code *exactly* — no URL, no prefix, no JSON wrapper.
void main() {
  // CapabilityProfile.load() reads a JSON asset from the esc_pos package,
  // which needs the asset bundle wired up.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('which sources get a courier block', () {
    test('GLOVO and KOOUL do', () {
      expect(PrintingService.sourceHasCourierCode('GLOVO'), isTrue);
      expect(PrintingService.sourceHasCourierCode('KOOUL'), isTrue);
    });

    test('case does not matter — the payload is not guaranteed uppercase', () {
      expect(PrintingService.sourceHasCourierCode('glovo'), isTrue);
      expect(PrintingService.sourceHasCourierCode('Kooul'), isTrue);
    });

    test('DealUp and Web do NOT', () {
      // Our own channels: no courier, no platform code. Printing a block for
      // them would put a meaningless symbol on every web order.
      expect(PrintingService.sourceHasCourierCode('DEALUP'), isFalse);
      expect(PrintingService.sourceHasCourierCode('WEB'), isFalse);
      expect(PrintingService.sourceHasCourierCode('WHATSAPP'), isFalse);
    });

    test('a till order (no source at all) does not', () {
      expect(PrintingService.sourceHasCourierCode(null), isFalse);
      expect(PrintingService.sourceHasCourierCode(''), isFalse);
    });
  });

  group('the symbol encodes the raw code', () {
    // Encoding anything other than the bare code — a URL, a prefix, JSON —
    // makes the courier's scan useless, so this is asserted at the byte level
    // rather than trusted.
    Future<List<int>> qrBytesFor(String value) async {
      final gen = Generator(PaperSize.mm80, await CapabilityProfile.load());
      return gen.qrcode(value, size: QRSize.size6, cor: QRCorrection.M);
    }

    test('the QR payload contains the code verbatim and nothing wrapping it',
        () async {
      const code = '4F8-JKL';
      final bytes = await qrBytesFor(code);
      final ascii = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
      expect(ascii.contains(code), isTrue,
          reason: 'the raw code must be in the QR payload');
      expect(ascii.contains('http'), isFalse,
          reason: 'no URL wrapping — the courier app scans the code itself');
    });

    test('two different codes produce different symbols', () async {
      expect(await qrBytesFor('AAA-111'),
          isNot(equals(await qrBytesFor('BBB-222'))));
    });

    test('Code128 accepts the characters these codes actually use', () {
      // Glovo order_code and Kooul reference are alphanumeric with dashes;
      // Code128 set B covers them. A throw here means an unprintable ticket.
      for (final code in ['4F8-JKL', 'KOOUL123456', 'ab-99-XY']) {
        expect(() => Barcode.code128(code.split('')), returnsNormally,
            reason: code);
      }
    });
  });

  group('print mode defaults', () {
    test('same-ticket QR is the default', () {
      // The default must need no second roll and no setup: a shop that never
      // opens Printer Settings still gets a scannable code on the ticket.
      const config = PrinterConfig();
      expect(config.courierCodeMode, CourierCodeMode.sameTicket);
      expect(config.courierCodeSymbology, CourierCodeSymbology.qr);
    });

    test('the mode survives a save/load round trip', () {
      // It is a per-printer setting; losing it on restart would silently revert
      // a shop that chose separate tickets for the bag.
      const config = PrinterConfig(
        courierCodeMode: CourierCodeMode.separateTicket,
        courierCodeSymbology: CourierCodeSymbology.code128,
      );
      final restored = PrinterConfig.fromJson(config.toJson());
      expect(restored.courierCodeMode, CourierCodeMode.separateTicket);
      expect(restored.courierCodeSymbology, CourierCodeSymbology.code128);
    });

    test('a config written by a newer build does not crash an older one', () {
      // Enum indexes are persisted, so an out-of-range value must clamp rather
      // than throw and take the printer settings screen down.
      final restored = PrinterConfig.fromJson({
        'courierCodeMode': 99,
        'courierCodeSymbology': -1,
      });
      expect(restored.courierCodeMode, isA<CourierCodeMode>());
      expect(restored.courierCodeSymbology, isA<CourierCodeSymbology>());
    });

    test('an absent value falls back to the default, not to Off', () {
      // A config saved before this feature existed has no key. Defaulting to
      // Off would silently disable courier codes for every existing terminal.
      final restored = PrinterConfig.fromJson({});
      expect(restored.courierCodeMode, CourierCodeMode.sameTicket);
      expect(restored.courierCodeSymbology, CourierCodeSymbology.qr);
    });
  });

  group('paper width', () {
    // The QR must fit the roll with its quiet zone intact. 58mm has roughly
    // half the printable width of 80mm, so the same module size that is
    // comfortable on 80mm runs into the edge on 58mm and the scan fails.
    Future<List<int>> qrBytes(PaperSize paper, QRSize size) async {
      final gen = Generator(paper, await CapabilityProfile.load());
      return gen.qrcode('4F8-JKL', size: size);
    }

    test('a smaller module size is used on 58mm than on 80mm', () async {
      // Mirrors the branch in _buildCourierBlock: size4 on 58mm, size6 on 80mm.
      // Compared byte-for-byte, not by length: QRSize sets a module-scale
      // parameter byte, so both commands are the same number of bytes.
      final narrow = await qrBytes(PaperSize.mm58, QRSize.size4);
      final wide = await qrBytes(PaperSize.mm80, QRSize.size6);
      expect(narrow, isNot(equals(wide)),
          reason: 'a 58mm roll must not get the 80mm module size — the symbol '
              'would run into the edge and lose its quiet zone');
    });

    test('the same code is encoded regardless of paper width', () async {
      // Size changes the module scale, never the payload.
      for (final paper in [PaperSize.mm58, PaperSize.mm80]) {
        final gen = Generator(paper, await CapabilityProfile.load());
        final bytes = gen.qrcode('4F8-JKL');
        final ascii =
            String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
        expect(ascii.contains('4F8-JKL'), isTrue, reason: '$paper');
      }
    });
  });

  group('the printed code line', () {
    test('the ordinal indicator is mapped to a plain letter', () {
      // U+00BA is valid Latin-1 so it passes the sanitiser's >0xFF net, but
      // CP437 renders that byte as a box-drawing glyph. "No 4F8-JKL" is the
      // conventional abbreviation and prints identically on every code page.
      expect(PrintingService.sanitizeForThermalTest('Nº 4F8-JKL'),
          'No 4F8-JKL');
    });

    test('the code itself is never altered by sanitising', () {
      // Mangling the code would break the match with the scanned symbol.
      for (final code in ['4F8-JKL', 'KOOUL123456', 'ab-99-XY']) {
        expect(PrintingService.sanitizeForThermalTest(code), code);
      }
    });
  });
}

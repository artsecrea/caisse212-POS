import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/services/printing_service.dart';
import 'package:caisse212/services/refund_sandbox.dart';
import 'package:caisse212/utils/escpos_text.dart';

/// The Test-mode refund sandbox is itself a test: it must pass end to end, and
/// the X it exports must come out of the real report bytes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the refund sandbox passes every check and exports the X', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final result =
        await RefundSandbox.run(printing: PrintingService(), prefs: prefs);
    for (final c in result.checks) {
      // ignore: avoid_print
      print('${c.ok ? 'PASS' : 'FAIL'}  ${c.label}  —  ${c.detail}');
    }
    // ignore: avoid_print
    print('\n${result.exchangeTicketText}\n\n${result.xText}');
    expect(result.exchangeTicketText, contains('T-shirt L'));
    expect(result.checks, isNotEmpty);
    expect(result.allOk, isTrue,
        reason: result.checks.where((c) => !c.ok).map((c) => c.label).join('; '));
  });

  test('ESC/POS decoding keeps the words and the columns', () async {
    final profile = await CapabilityProfile.load();
    final g = Generator(PaperSize.mm80, profile);
    final bytes = <int>[
      ...g.reset(),
      ...g.text('RAPPORT X', styles: const PosStyles(bold: true, align: PosAlign.center)),
      ...g.row([
        PosColumn(text: 'Remboursements', width: 7),
        PosColumn(text: '-110.00', width: 5, styles: const PosStyles(align: PosAlign.right)),
      ]),
      ...g.feed(2),
      ...g.cut(),
    ];
    final text = escPosToText(bytes);
    expect(text, contains('RAPPORT X'));
    final row = text.split('\n').firstWhere((l) => l.contains('Remboursements'));
    expect(row, contains('-110.00'));
    expect(row.indexOf('-110.00'), greaterThan('Remboursements'.length),
        reason: 'columns stay apart');
  });
}

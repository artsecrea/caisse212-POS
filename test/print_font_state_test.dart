import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/services/printing_service.dart';

/// Thin, narrow receipts: a note line is printed in font B, and nothing ever
/// switched the printer back, so the totals after it — and, with no reset at
/// the start of a job, the whole next ticket — came out in font B laid out
/// for font A's 48 columns.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PrintingService service;
  final captured = <int>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    service = PrintingService();
    await service.saveConfig(
        await SharedPreferences.getInstance(), const PrinterConfig());
    db = AppDatabase.forTesting(NativeDatabase.memory());
    captured.clear();
    service.dispatchForTesting = (_, bytes) => captured.addAll(bytes);
    service.databaseForTesting = db;
  });
  tearDown(() async {
    service.dispatchForTesting = null;
    service.databaseForTesting = null;
    await db.close();
  });

  int lastIndexOf(List<int> haystack, List<int> needle, [int? end]) {
    for (var i = (end ?? haystack.length) - needle.length; i >= 0; i--) {
      var hit = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return i;
    }
    return -1;
  }

  const fontA = [0x1B, 0x4D, 0x00];
  const fontB = [0x1B, 0x4D, 0x01];

  test('a receipt starts from the printer\'s power-on state', () async {
    final ok = await service.printOrderReceipt(
      order: CurrentOrder(items: [
        OrderItem(productId: 1, productName: 'Burger', finalPrice: 80, quantity: 1),
      ]),
      cashierName: 'Test',
    );

    expect(ok, isTrue);
    expect(captured.take(2), PrintingService.escInit);
  });

  test('the text after a font B note goes back to font A', () async {
    final ok = await service.printOrderReceipt(
      order: CurrentOrder(items: [
        OrderItem(
            productId: 1,
            productName: 'Burger',
            finalPrice: 80,
            quantity: 1,
            note: 'sans oignon'),
      ]),
      cashierName: 'Test',
    );
    expect(ok, isTrue);

    final note = lastIndexOf(captured, 'sans oignon'.codeUnits);
    final total = lastIndexOf(captured, '80'.codeUnits);
    expect(note, isNonNegative);
    expect(total, greaterThan(note));

    // The note itself is font B…
    expect(lastIndexOf(captured, fontB, note), isNonNegative);
    // …and font A is selected again before the totals print.
    final backToA = lastIndexOf(captured, fontA, total);
    expect(backToA, greaterThan(note));
  });
}

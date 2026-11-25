import 'package:caisse212/services/data_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('positivePrepMinutes', () {
    test('keeps a configured time', () {
      expect(positivePrepMinutes(12), 12);
      expect(positivePrepMinutes(12.0), 12);
      expect(positivePrepMinutes('12'), 12);
    });

    test('missing or null key is not configured', () {
      expect(positivePrepMinutes(null), isNull);
      expect(positivePrepMinutes(<String, dynamic>{}['preparingDuration']),
          isNull);
    });

    test('zero and negatives count as not configured', () {
      expect(positivePrepMinutes(0), isNull);
      expect(positivePrepMinutes(-5), isNull);
    });

    test('garbage never throws', () {
      expect(positivePrepMinutes('abc'), isNull);
      expect(positivePrepMinutes(double.nan), isNull);
      expect(positivePrepMinutes(true), isNull);
    });
  });
}

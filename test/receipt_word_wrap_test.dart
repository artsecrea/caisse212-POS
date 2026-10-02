import 'package:flutter_test/flutter_test.dart';
import 'package:caisse212/services/printing_service.dart';

void main() {
  group('PrintingService.wordWrap', () {
    test('breaks at spaces, never inside a word', () {
      final lines = PrintingService.wordWrap(
          '12 Boulevard Mohammed V, Quartier Maarif, Casablanca', 32);
      expect(lines, ['12 Boulevard Mohammed V,', 'Quartier Maarif, Casablanca']);
      for (final l in lines) {
        expect(l.length, lessThanOrEqualTo(32));
      }
    });

    test('short text stays on one line', () {
      expect(PrintingService.wordWrap('Rue 5', 48), ['Rue 5']);
    });

    test('a word longer than the line is split as a last resort', () {
      expect(PrintingService.wordWrap('ab abcdefghij', 4),
          ['ab', 'abcd', 'efgh', 'ij']);
    });
  });
}

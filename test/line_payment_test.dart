import 'package:caisse212/domain/models/line_payment.dart';
import 'package:caisse212/domain/models/table_occupancy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isLinePaid', () {
    test('a ticket makes a line paid whatever its kitchen state', () {
      expect(isLinePaid('PENDING', 7), isTrue);
      expect(isLinePaid('PREPARING', 7), isTrue);
      expect(isLinePaid('COMPLETED', 7), isTrue);
    });

    test('no ticket and a kitchen state is unpaid', () {
      expect(isLinePaid('PENDING', null), isFalse);
      expect(isLinePaid('COMPLETED', null), isFalse);
    });

    test('legacy PAID rows still count as paid', () {
      expect(isLinePaid('PAID', null), isTrue);
    });
  });

  group('settlement with the kitchen state kept', () {
    test('paid lines still cooking settle the order', () {
      final states = [
        settlementState('PENDING', 1),
        settlementState('PREPARING', 1),
      ];
      expect(isOrderSettled(states), isTrue);
    });

    test('an unpaid line keeps the order open', () {
      final states = [
        settlementState('COMPLETED', 1),
        settlementState('COMPLETED', null),
      ];
      expect(isOrderSettled(states), isFalse);
    });
  });
}

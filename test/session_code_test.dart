import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/session_service.dart';

/// Session codes ended in the clock's milliseconds, so two sessions opened in
/// the same millisecond collided on the UNIQUE code and the second failed.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('sessions opened back to back get distinct codes in the same shape',
      () async {
    final service = SessionService(db);
    final codes = <String>{};
    for (var cashier = 1; cashier <= 40; cashier++) {
      final s = await service.startSession(cashierId: cashier, moneyAtStart: 0);
      expect(s.code, matches(RegExp(r'^CS-\d{8}-\d{6}-\d{3}$')));
      codes.add(s.code);
    }
    expect(codes, hasLength(40));
  });
}

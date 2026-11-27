import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/session_service.dart';

/// A double-fired login opened two sessions for one cashier 1 ms apart, and
/// every later login then failed with "Bad state: Too many elements".
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('two concurrent starts open one session, the other is refused',
      () async {
    final service = SessionService(db);
    final results = await Future.wait([
      service
          .startSession(cashierId: 161, moneyAtStart: 0)
          .then<Object>((s) => s, onError: (Object e) => e),
      service
          .startSession(cashierId: 161, moneyAtStart: 0)
          .then<Object>((s) => s, onError: (Object e) => e),
    ]);

    expect(results.whereType<CashSession>(), hasLength(1));
    expect(results.whereType<Exception>(), hasLength(1));
    expect(await db.select(db.cashSessions).get(), hasLength(1));
  });

  test('a till already holding two open sessions still finds the newest',
      () async {
    Future<int> open(DateTime at, String code) =>
        db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
              code: code,
              cashierId: 161,
              moneyAtStart: 0,
              status: const Value('active'),
              startedAt: Value(at),
            ));
    final at = DateTime(2026, 11, 26, 13, 25, 3);
    await open(at, 'CS-A');
    final newer = await open(at.add(const Duration(milliseconds: 1)), 'CS-B');

    final found = await SessionService(db).getActiveSession(161);
    expect(found?.id, newer);
  });
}

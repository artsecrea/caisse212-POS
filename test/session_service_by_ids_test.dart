import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/session_service.dart';

/// [SessionService.getSessionsByIds] backs the session-reports day scope
/// (any order) and the settle-unpaid "chosen day" target (oldest first).
void main() {
  late AppDatabase db;
  late SessionService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = SessionService(db);
  });
  tearDown(() => db.close());

  Future<int> session(String code, DateTime startedAt) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: code,
            cashierId: 1,
            moneyAtStart: 0,
            startedAt: Value(startedAt),
          ));

  test('returns just the listed sessions', () async {
    final a = await session('A', DateTime(2026, 3, 4, 8));
    final b = await session('B', DateTime(2026, 3, 4, 12));
    await session('C', DateTime(2026, 3, 4, 16));
    expect({for (final s in await service.getSessionsByIds([a, b])) s.id},
        {a, b});
  });

  test('oldestFirst orders by start time, not by id', () async {
    final late = await session('LATE', DateTime(2026, 3, 4, 17));
    final early = await session('EARLY', DateTime(2026, 3, 4, 8));
    final mid = await session('MID', DateTime(2026, 3, 4, 12));
    expect(
        [
          for (final s in await service
              .getSessionsByIds([late, early, mid], oldestFirst: true))
            s.id
        ],
        [early, mid, late]);
  });

  test('no ids, no sessions', () async {
    await session('A', DateTime(2026, 3, 4, 8));
    expect(await service.getSessionsByIds(const <int>[]), isEmpty);
  });
}

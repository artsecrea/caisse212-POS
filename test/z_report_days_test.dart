import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/presentation/widgets/z_report_dialog.dart';

/// The Z report is offered for any trading day, whether or not the terminal
/// was ever switched into Z tracking — so its day list is built from cash
/// sessions, and a Z row only decorates a day it happens to cover.

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> session(String code, DateTime startedAt) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: code,
            cashierId: 1,
            moneyAtStart: 0,
            startedAt: Value(startedAt),
          ));

  test('no sessions means nothing to report on', () async {
    expect(await loadZDayOptions(db), isEmpty);
  });

  test('sessions on the same day collapse into one entry', () async {
    await session('S1', DateTime(2026, 3, 4, 8));
    await session('S2', DateTime(2026, 3, 4, 17));

    final days = await loadZDayOptions(db);
    expect(days, hasLength(1));
    expect(days.single.sessionIds, hasLength(2));
    expect(days.single.sessionCodes, containsAll(['S1', 'S2']));
    expect(days.single.label, '2026-03-04',
        reason: 'no Z row, so the day speaks for itself');
  });

  test('days come back newest first', () async {
    await session('older', DateTime(2026, 3, 1, 9));
    await session('newer', DateTime(2026, 3, 9, 9));

    final days = await loadZDayOptions(db);
    expect([for (final d in days) d.day.day], [9, 1]);
  });

  test('a Z covering the day lends it its number', () async {
    await session('S1', DateTime(2026, 3, 4, 8));
    await db.into(db.zs).insert(ZsCompanion.insert(
          code: 'Z-20260304-080000-001',
          createdBy: 1,
          startedAt: Value(DateTime(2026, 3, 4, 8)),
          details: const Value('{"number":17,"businessDay":"2026-03-04"}'),
        ));

    final day = (await loadZDayOptions(db)).single;
    expect(day.zNumber, 17);
    expect(day.zCode, 'Z-20260304-080000-001');
    expect(day.label, contains('Z17'));
  });

  test('a day with no Z is still reportable, just unlabelled', () async {
    await session('S1', DateTime(2026, 3, 4, 8));
    await session('S2', DateTime(2026, 3, 5, 8));
    await db.into(db.zs).insert(ZsCompanion.insert(
          code: 'Z1',
          createdBy: 1,
          startedAt: Value(DateTime(2026, 3, 5, 8)),
          details: const Value('{"number":2}'),
        ));

    final days = await loadZDayOptions(db);
    expect(days, hasLength(2));
    expect(days[0].zNumber, 2, reason: 'the 5th has a Z');
    expect(days[1].zNumber, isNull, reason: 'the 4th does not, and is fine');
    expect(days[1].sessionIds, hasLength(1));
  });

  group('zDetailNumber', () {
    test('reads the number out of the details blob', () {
      final z = Z(
        id: 1,
        code: 'Z1',
        createdBy: 1,
        status: 'closed',
        startedAt: DateTime(2026),
        isSynced: false,
        updatedAt: DateTime(2026),
        details: '{"number":42,"businessDay":"2026-01-01"}',
      );
      expect(zDetailNumber(z), 42);
    });

    test('tolerates a missing, empty or malformed blob', () {
      Z withDetails(String? d) => Z(
            id: 1,
            code: 'Z1',
            createdBy: 1,
            status: 'closed',
            startedAt: DateTime(2026),
            isSynced: false,
            updatedAt: DateTime(2026),
            details: d,
          );
      expect(zDetailNumber(null), isNull);
      expect(zDetailNumber(withDetails(null)), isNull);
      expect(zDetailNumber(withDetails('')), isNull);
      expect(zDetailNumber(withDetails('not json')), isNull);
      expect(zDetailNumber(withDetails('{"businessDay":"2026-01-01"}')), isNull);
    });
  });
}

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

  Future<int> session(String code, DateTime startedAt,
          {String status = 'ended', int? zId}) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: code,
            cashierId: 1,
            moneyAtStart: 0,
            startedAt: Value(startedAt),
            status: Value(status),
            zId: Value(zId),
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

  test('a Z covering the day lends it its sequence', () async {
    await session('S1', DateTime(2026, 3, 4, 8));
    await db.into(db.zs).insert(ZsCompanion.insert(
          code: 'Z-20260304-1-080000001',
          createdBy: 1,
          startedAt: Value(DateTime(2026, 3, 4, 8)),
          zDay: const Value('2026-03-04'),
          zSeq: const Value(1),
          status: const Value('closed'),
        ));

    final day = (await loadZDayOptions(db)).single;
    expect(day.zNumber, 1);
    expect(day.zCode, 'Z-20260304-1-080000001');
    expect(day.label, contains('Z1'));
  });

  test('the Z is matched by its business day, not its opening clock', () async {
    // Opened at 02:00 on the 5th inside the 4th's business day (start 05:00).
    await session('S1', DateTime(2026, 3, 4, 20));
    await db.into(db.zs).insert(ZsCompanion.insert(
          code: 'Z-late',
          createdBy: 1,
          startedAt: Value(DateTime(2026, 3, 5, 2)),
          zDay: const Value('2026-03-04'),
          zSeq: const Value(2),
          status: const Value('closed'),
        ));

    final day = (await loadZDayOptions(db)).single;
    expect(day.day, DateTime(2026, 3, 4));
    expect(day.zNumber, 2);
  });

  test('a day with no Z is still reportable, just unlabelled', () async {
    await session('S1', DateTime(2026, 3, 4, 8));
    await session('S2', DateTime(2026, 3, 5, 8));
    await db.into(db.zs).insert(ZsCompanion.insert(
          code: 'Z1',
          createdBy: 1,
          startedAt: Value(DateTime(2026, 3, 5, 8)),
          zDay: const Value('2026-03-05'),
          zSeq: const Value(2),
          status: const Value('closed'),
        ));

    final days = await loadZDayOptions(db);
    expect(days, hasLength(2));
    expect(days[0].zNumber, 2, reason: 'the 5th has a Z');
    expect(days[1].zNumber, isNull, reason: 'the 4th does not, and is fine');
    expect(days[1].sessionIds, hasLength(1));
  });

  group('a Z is only offered once its day is closed', () {
    test('a day with a session still open is not offered', () async {
      await session('S1', DateTime(2026, 3, 4, 8));
      await session('S2', DateTime(2026, 3, 4, 17), status: 'active');
      await session('S3', DateTime(2026, 3, 3, 9));
      final days = await loadZDayOptions(db);
      expect([for (final d in days) d.day], [DateTime(2026, 3, 3)]);
    });

    test('a paused session blocks the day too', () async {
      await session('S1', DateTime(2026, 3, 4, 8), status: 'paused');
      expect(await loadZDayOptions(db), isEmpty);
    });

    test('a day whose Z is still open is not offered, even with every '
        'session ended', () async {
      final zId = await db.into(db.zs).insert(ZsCompanion.insert(
            code: 'Z-open',
            createdBy: 1,
            startedAt: Value(DateTime(2026, 3, 4, 8)),
            zDay: const Value('2026-03-04'),
          ));
      await session('S1', DateTime(2026, 3, 4, 8), zId: zId);
      expect(await loadZDayOptions(db), isEmpty);
    });
  });
}

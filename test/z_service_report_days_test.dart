import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/z_day_option.dart';
import 'package:caisse212/presentation/widgets/z_report_dialog.dart'
    show loadZDayOptions, zReportBlockedByOpenShift;
import 'package:caisse212/services/z_service.dart';

/// [ZService.zDayOptions] and [ZService.reportBlockedByOpenShift] are the Z
/// report dialog's helpers moved out of the UI. Same cases as
/// z_report_days_test / z_report_blocked_test, plus a check that both
/// still agree with the UI functions until those become wrappers.
void main() {
  late AppDatabase db;
  late ZService z;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    z = ZService(db);
  });
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

  Future<int> zRow(String code, DateTime startedAt,
          {required String zDay, int zSeq = 1, String status = 'closed'}) =>
      db.into(db.zs).insert(ZsCompanion.insert(
            code: code,
            createdBy: 1,
            startedAt: Value(startedAt),
            zDay: Value(zDay),
            zSeq: Value(zSeq),
            status: Value(status),
          ));

  group('zDayOptions', () {
    test('no sessions means nothing to report on', () async {
      expect(await z.zDayOptions(), isEmpty);
    });

    test('sessions on the same day collapse into one entry', () async {
      await session('S1', DateTime(2026, 3, 4, 8));
      await session('S2', DateTime(2026, 3, 4, 17));
      final day = (await z.zDayOptions()).single;
      expect(day.sessionCodes, ['S2', 'S1'], reason: 'newest session first');
      expect(day.label, '2026-03-04');
    });

    test('days come back newest first, capped at limitDays', () async {
      await session('older', DateTime(2026, 3, 1, 9));
      await session('mid', DateTime(2026, 3, 5, 9));
      await session('newer', DateTime(2026, 3, 9, 9));
      expect([for (final d in await z.zDayOptions()) d.day.day], [9, 5, 1]);
      expect([for (final d in await z.zDayOptions(limitDays: 2)) d.day.day],
          [9, 5]);
    });

    test('a Z is matched by its business day and lends its lowest seq',
        () async {
      await session('S1', DateTime(2026, 3, 4, 20));
      await zRow('Z-late', DateTime(2026, 3, 5, 2), zDay: '2026-03-04', zSeq: 3);
      await zRow('Z-first', DateTime(2026, 3, 4, 8), zDay: '2026-03-04', zSeq: 2);
      final day = (await z.zDayOptions()).single;
      expect(day.day, DateTime(2026, 3, 4));
      expect(day.zNumber, 2);
      expect(day.zCode, 'Z-first');
      expect(day.label, contains('Z2'));
    });

    test('a day with an open or paused session is not offered', () async {
      await session('S1', DateTime(2026, 3, 4, 8));
      await session('S2', DateTime(2026, 3, 4, 17), status: 'active');
      await session('S3', DateTime(2026, 3, 3, 9), status: 'paused');
      await session('S4', DateTime(2026, 3, 2, 9));
      expect([for (final d in await z.zDayOptions()) d.day],
          [DateTime(2026, 3, 2)]);
    });

    test('a day whose Z is still open is not offered', () async {
      final zId = await zRow('Z-open', DateTime(2026, 3, 4, 8),
          zDay: '2026-03-04', status: 'open');
      await session('S1', DateTime(2026, 3, 4, 8), zId: zId);
      expect(await z.zDayOptions(), isEmpty);
    });

    test('agrees with loadZDayOptions', () async {
      final zId = await zRow('Z1', DateTime(2026, 3, 5, 8), zDay: '2026-03-05');
      await session('S1', DateTime(2026, 3, 4, 8));
      await session('S2', DateTime(2026, 3, 5, 8), zId: zId);
      await session('S3', DateTime(2026, 3, 5, 14), zId: zId);
      await session('S4', DateTime(2026, 3, 6, 9), status: 'active');

      String flat(List<ZDayOption> days) => [
            for (final d in days)
              '${d.day}|${d.sessionIds}|${d.sessionCodes}|${d.zCode}|${d.zNumber}'
          ].join('\n');
      expect(flat(await z.zDayOptions()), flat(await loadZDayOptions(db)));
    });
  });

  group('reportBlockedByOpenShift', () {
    Future<void> bare(String status) =>
        db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
              code: 'S-$status',
              cashierId: 1,
              moneyAtStart: 0,
              status: Value(status),
            ));

    Future<void> bareZ(String status) => db.into(db.zs).insert(
        ZsCompanion.insert(code: 'Z-$status', createdBy: 1, status: Value(status)));

    Future<void> expectBlocked(bool blocked) async {
      expect(await z.reportBlockedByOpenShift(), blocked);
      expect(await zReportBlockedByOpenShift(db), blocked);
    }

    test('nothing open: allowed', () async {
      await bare('ended');
      await bareZ('closed');
      await expectBlocked(false);
    });

    test('an open Z blocks it', () async {
      await bareZ('open');
      await expectBlocked(true);
    });

    test('a running session blocks it, even with every Z closed', () async {
      await bareZ('closed');
      await bare('active');
      await expectBlocked(true);
    });

    test('a paused session blocks it', () async {
      await bare('paused');
      await expectBlocked(true);
    });

    test('two open Zs still just block, never throw', () async {
      await bareZ('open');
      await db.into(db.zs).insert(ZsCompanion.insert(
          code: 'Z-open-2', createdBy: 1, status: const Value('open')));
      await expectBlocked(true);
    });
  });
}

import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/session_rules.dart';
import 'package:caisse212/services/cash_movement_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/session_service.dart';
import 'package:caisse212/services/session_z_details.dart';
import 'package:caisse212/services/z_rules.dart';
import 'package:caisse212/services/z_service.dart';

/// Z contract v3 (bms docs/POS_Z_CONTRACT.md): a Z is a (zDay, zSeq) label on
/// cash sessions, the till owns the counter, and the server learns the Z from
/// the session push alone.
void main() {
  group('business day and rule times', () {
    test('before the start hour belongs to the previous business day', () {
      expect(zDayKeyOf(DateTime(2026, 9, 25, 2), 5), '2026-09-24');
      expect(zDayKeyOf(DateTime(2026, 9, 25, 5), 5), '2026-09-25');
    });

    test('rule times are relative to the business day, like the server', () {
      // Start 05:00: "23:00" is that same night, "02:00" the next morning.
      expect(ruleInstant('2026-09-24', 5, '23:00'), DateTime(2026, 9, 24, 23));
      expect(ruleInstant('2026-09-24', 5, '02:00'), DateTime(2026, 9, 25, 2));
      expect(ruleInstant('2026-09-24', 5, '05:00'), DateTime(2026, 9, 24, 5),
          reason: 'the start hour is the day start itself');
      expect(ruleInstant('2026-09-24', 0, '00:00'), DateTime(2026, 9, 24));
    });

    test('only strict HH:mm is a rule; anything else is no limit', () {
      expect(parseHhmm('09:30'), 570);
      expect(parseHhmm('9:30'), isNull);
      expect(parseHhmm('24:00'), isNull);
      expect(parseHhmm('09:30:00'), isNull);
      expect(ruleInstant('2026-09-24', 5, null), isNull);
    });
  });

  group('planZ', () {
    const today = '2026-09-25';

    test('an open Z of today is continued', () {
      final plan = planZ(
          currentZDay: today, localOpen: const ZLabel(today, 1));
      expect(plan.action, ZPlanAction.continueOpen);
      expect(plan.next, const ZLabel(today, 1));
    });

    test('an open Z from an earlier day is continued, never closed by the clock',
        () {
      final plan = planZ(
        currentZDay: today,
        localOpen: const ZLabel('2026-09-24', 1),
        localLatest: const ZSnapshot(ZLabel('2026-09-24', 1), closed: false),
      );
      expect(plan.action, ZPlanAction.continueOpen);
      expect(plan.next, const ZLabel('2026-09-24', 1));
    });

    test('after today\'s Z closed, the next one is zSeq + 1', () {
      final plan = planZ(
        currentZDay: today,
        localLatest: const ZSnapshot(ZLabel(today, 1), closed: true),
      );
      expect(plan.action, ZPlanAction.openNew);
      expect(plan.next, const ZLabel(today, 2));
    });

    test('a new day starts at 1', () {
      final plan = planZ(
        currentZDay: today,
        localLatest: const ZSnapshot(ZLabel('2026-09-24', 3), closed: true),
      );
      expect(plan.next, const ZLabel(today, 1));
    });

    test('a reinstall adopts the server Z still open today', () {
      final plan = planZ(
        currentZDay: today,
        server: const ZSnapshot(ZLabel(today, 2), closed: false),
      );
      expect(plan.action, ZPlanAction.adoptServer);
      expect(plan.next, const ZLabel(today, 2));
    });

    test('a reinstall continues the counter past a server Z closed today', () {
      final plan = planZ(
        currentZDay: today,
        server: const ZSnapshot(ZLabel(today, 2), closed: true),
      );
      expect(plan.action, ZPlanAction.openNew);
      expect(plan.next, const ZLabel(today, 3),
          reason: 'never a blind (today, 1): that label is closed');
    });

    test('offline, the till resumes from its own latest Z', () {
      final plan = planZ(
        currentZDay: today,
        localLatest: const ZSnapshot(ZLabel(today, 2), closed: true),
      );
      expect(plan.next, const ZLabel(today, 3));
    });

    test('a local open Z the server already closed is closed locally first',
        () {
      final plan = planZ(
        currentZDay: today,
        localOpen: const ZLabel(today, 1),
        server: const ZSnapshot(ZLabel(today, 1), closed: true),
      );
      expect(plan.closeLocalAsServerClosed, isTrue);
      expect(plan.next, const ZLabel(today, 2));
    });
  });

  group('open rules', () {
    ZRuleBlock? open({
      String? mode,
      String? cantOpenAfter,
      bool explicit = false,
      bool perm = false,
      bool override = false,
      DateTime? now,
    }) =>
        checkZOpen(
          now: now ?? DateTime(2026, 9, 25, 12),
          zDay: '2026-09-25',
          startHour: 5,
          openMode: mode,
          cantOpenAfter: cantOpenAfter,
          explicitOpen: explicit,
          hasOpenPermission: perm,
          hasOverride: override,
        );

    test('AUTO (or unset) opens with the first session', () {
      expect(open(), isNull);
      expect(open(mode: 'AUTO'), isNull);
    });

    test('MANUAL needs someone with pos:z:open to open it explicitly', () {
      expect(open(mode: 'MANUAL'), ZRuleBlock.manualOpenRequired);
      expect(open(mode: 'MANUAL', perm: true), ZRuleBlock.manualOpenRequired,
          reason: 'not by itself, even for a permitted user');
      expect(open(mode: 'MANUAL', explicit: true, perm: true), isNull);
    });

    test('zCantOpenAfter blocks unless the user has pos:z:override', () {
      final late = DateTime(2026, 9, 25, 23);
      expect(open(cantOpenAfter: '22:00', now: late), ZRuleBlock.tooLateToOpen);
      expect(open(cantOpenAfter: '22:00', now: late, override: true), isNull);
      expect(open(cantOpenAfter: '22:00'), isNull, reason: 'noon is fine');
    });
  });

  group('close rules', () {
    ZRuleBlock? close({
      bool perm = true,
      bool override = false,
      String? earliest,
      DateTime? now,
    }) =>
        checkZClose(
          now: now ?? DateTime(2026, 9, 25, 23),
          zDay: '2026-09-25',
          startHour: 5,
          earliestCloseTime: earliest,
          hasClosePermission: perm,
          hasOverride: override,
        );

    test('closing needs pos:z:close', () {
      expect(close(perm: false), ZRuleBlock.noClosePermission);
      expect(close(), isNull);
    });

    test('zEarliestCloseTime blocks, pos:z:override passes', () {
      final early = DateTime(2026, 9, 25, 15);
      expect(close(earliest: '22:00', now: early), ZRuleBlock.tooEarlyToClose);
      expect(close(earliest: '22:00', now: early, override: true), isNull);
      // 01:00 the next morning is after 22:00 of the same business day.
      expect(close(earliest: '22:00', now: DateTime(2026, 9, 26, 1)), isNull);
    });

    test('AUTO_AFTER_HOUR asks from zAutoCloseAfter on, MANUAL never', () {
      bool due(String? mode, DateTime now) => zAutoCloseDue(
            now: now,
            zDay: '2026-09-25',
            startHour: 5,
            closeMode: mode,
            autoCloseAfter: '02:00',
          );
      expect(due('AUTO_AFTER_HOUR', DateTime(2026, 9, 26, 1, 59)), isFalse);
      expect(due('AUTO_AFTER_HOUR', DateTime(2026, 9, 26, 2)), isTrue);
      expect(due(null, DateTime(2026, 9, 26, 3)), isFalse);
      expect(due('MANUAL', DateTime(2026, 9, 26, 3)), isFalse);
    });

    test('BY_SESSION closes the Z with its last open session only', () {
      expect(
          zClosesWithSession(closeMode: 'BY_SESSION', otherOpenSessions: 0),
          isTrue);
      expect(
          zClosesWithSession(closeMode: 'by_session', otherOpenSessions: 0),
          isTrue);
      expect(
          zClosesWithSession(closeMode: 'BY_SESSION', otherOpenSessions: 1),
          isFalse);
      expect(
          zClosesWithSession(
              closeMode: 'BY_SESSION', otherOpenSessions: 0, tooEarly: true),
          isFalse);
      expect(zClosesWithSession(closeMode: null, otherOpenSessions: 0),
          isFalse);
      expect(
          zClosesWithSession(
              closeMode: 'AUTO_AFTER_HOUR', otherOpenSessions: 0),
          isFalse);
    });

    test('a lone session prints only the Z, several add the closing X', () {
      expect(printSessionXWithZ(1), isFalse);
      expect(printSessionXWithZ(2), isTrue);
    });
  });

  group('ZService and the session push', () {
    late AppDatabase db;
    late ZService zService;
    late SessionService sessions;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      zService = ZService(db);
      sessions = SessionService(db);
    });
    tearDown(() => db.close());

    Future<CashSession> reload(int id) async =>
        (await sessions.getSessionById(id))!;

    test('only the Z\'s first session carries its open mode', () async {
      final z = await zService.openZ(
          label: const ZLabel('2026-09-25', 1),
          createdBy: 1,
          openMode: ZService.openAuto);
      final a = await sessions.startSession(cashierId: 1, moneyAtStart: 100);
      await zService.attachSession(a.id, z.id);
      final b = await sessions.startSession(cashierId: 2, moneyAtStart: 50);
      await zService.attachSession(b.id, z.id);

      expect((await reload(a.id)).zOpenMode, 'AUTO');
      expect((await reload(b.id)).zOpenMode, isNull);
    });

    test('an adopted server Z sends no open mode', () async {
      final z = await zService.openZ(
          label: const ZLabel('2026-09-25', 2), createdBy: 1);
      final a = await sessions.startSession(cashierId: 1, moneyAtStart: 0);
      await zService.attachSession(a.id, z.id);
      expect((await reload(a.id)).zOpenMode, isNull);
    });

    test('closing flags the LAST session and re-queues it for the push',
        () async {
      final z = await zService.openZ(
          label: const ZLabel('2026-09-25', 1),
          createdBy: 1,
          openMode: ZService.openAuto);
      final a = await sessions.startSession(cashierId: 1, moneyAtStart: 0);
      await zService.attachSession(a.id, z.id);
      await sessions.endSession(sessionId: a.id, countedCash: 0);
      final b = await sessions.startSession(cashierId: 2, moneyAtStart: 0);
      await zService.attachSession(b.id, z.id);
      await sessions.endSession(sessionId: b.id, countedCash: 0);
      // Pretend both already reached the server.
      await (db.update(db.cashSessions))
          .write(const CashSessionsCompanion(isSynced: Value(true)));

      await zService.closeZ(
          zId: z.id,
          closeMode: ZService.closeManual,
          sessionService: sessions,
          endedBy: 7);

      final closedZ = (await zService.getById(z.id))!;
      expect(closedZ.status, 'closed');
      expect(closedZ.closeMode, 'MANUAL');
      expect((await reload(a.id)).isClosingSession, isFalse);
      final last = await reload(b.id);
      expect(last.isClosingSession, isTrue);
      expect(last.isSynced, isFalse,
          reason: 'the server fills the close fields on a re-push');

      final payload = DataSyncService.sessionSyncPayload(last, closedZ);
      expect(payload['zDay'], '2026-09-25');
      expect(payload['zSeq'], 1);
      expect(payload['isClosingSession'], isTrue);
      expect(payload['zCloseMode'], 'MANUAL');
      expect(payload['zClosedBy'], 7);
      expect(payload['zClosedAt'], isNotNull);
      expect(payload.containsKey('zCode'), isFalse,
          reason: 'v3 has no Z code');
    });

    test('any close ends every open session — autoClosed — and the last '
        'one ended closes the Z', () async {
      final z = await zService.openZ(
          label: const ZLabel('2026-09-25', 1),
          createdBy: 1,
          openMode: ZService.openAuto);
      final mine = await sessions.startSession(cashierId: 1, moneyAtStart: 0);
      await zService.attachSession(mine.id, z.id);
      final other = await sessions.startSession(cashierId: 2, moneyAtStart: 0);
      await zService.attachSession(other.id, z.id);
      await sessions.pauseSession(other.id);
      await sessions.endSession(sessionId: mine.id, countedCash: 0);

      await zService.closeZ(
          zId: z.id,
          closeMode: ZService.closeManual,
          sessionService: sessions,
          endedBy: 1,
          closeOverride: true);

      final a = await reload(mine.id);
      final b = await reload(other.id);
      expect(a.autoClosed, isFalse, reason: 'its cashier closed it');
      expect(b.status, 'ended');
      expect(b.autoClosed, isTrue);
      expect(b.isClosingSession, isTrue, reason: 'ended last');
      expect(a.isClosingSession, isFalse);
      final payload = DataSyncService.sessionSyncPayload(
          b, (await zService.getById(z.id))!);
      expect(payload['autoClosed'], isTrue);
      expect(payload['zOverride'], isTrue);
      expect(payload['zClosedBy'], 1);
    });

    test('an override at open rides the opening session', () async {
      final z = await zService.openZ(
          label: const ZLabel('2026-09-25', 1),
          createdBy: 1,
          openMode: ZService.openAuto,
          openOverride: true);
      final a = await sessions.startSession(cashierId: 1, moneyAtStart: 0);
      await zService.attachSession(a.id, z.id);
      expect((await reload(a.id)).zOverride, isTrue);
    });

    test('money goes out rounded to the cent', () async {
      final a = await sessions.startSession(
          cashierId: 1, moneyAtStart: 10.004999, moneyEntered: 0.1 + 0.2);
      final payload = DataSyncService.sessionSyncPayload(await reload(a.id), null);
      expect(payload['moneyAtStart'], 10.0);
      expect(payload['moneyEntered'], 0.3);
    });

    test('a closed session cannot be deleted', () async {
      final a = await sessions.startSession(cashierId: 1, moneyAtStart: 0);
      await sessions.endSession(sessionId: a.id);
      expect(() => sessions.deleteSession(a.id), throwsException);
    });

    test('FORCED ends whatever is still open', () async {
      final z = await zService.openZ(
          label: const ZLabel('2026-09-24', 1), createdBy: 1);
      final a = await sessions.startSession(cashierId: 1, moneyAtStart: 0);
      await zService.attachSession(a.id, z.id);

      await zService.closeZ(
          zId: z.id,
          closeMode: ZService.closeForced,
          sessionService: sessions);

      final s = await reload(a.id);
      expect(s.status, 'ended');
      expect(s.autoClosed, isTrue);
      expect(s.isClosingSession, isTrue);
      expect((await zService.getById(z.id))!.closeMode, 'FORCED');
    });

    test('a session that did not close its Z sends no close fields',
        () async {
      final z = await zService.openZ(
          label: const ZLabel('2026-09-25', 1),
          createdBy: 1,
          openMode: ZService.openManual);
      final a = await sessions.startSession(
          cashierId: 1, moneyAtStart: 80, moneyEntered: 80);
      await zService.attachSession(a.id, z.id);
      final payload =
          DataSyncService.sessionSyncPayload(await reload(a.id), z);
      expect(payload['zOpenMode'], 'MANUAL');
      expect(payload['moneyEntered'], 80);
      expect(payload.containsKey('moneyCarriedOver'), isFalse);
      expect(payload.containsKey('isClosingSession'), isFalse);
      expect(payload.containsKey('zCloseMode'), isFalse);
    });

    test('cash movements push as PAY_IN / PAY_OUT with their session code',
        () async {
      final a = await sessions.startSession(cashierId: 1, moneyAtStart: 0);
      final m = await CashMovementService(db).record(
        direction: CashMovementService.directionOut,
        amount: 50,
        reason: 'fournisseur pain',
        sessionId: a.id,
        zDay: DateTime(2026, 9, 24),
        createdBy: 12,
      );
      expect(m.code, startsWith('CM-'));
      expect(m.isSynced, isFalse);
      final payload = DataSyncService.cashMovementSyncPayload(m, a.code);
      expect(payload['type'], 'PAY_OUT');
      expect(payload['amount'], 50);
      expect(payload['zDay'], '2026-09-24');
      expect(payload['sessionCode'], a.code);
      expect(payload.containsKey('zCode'), isFalse);
    });
  });

  group('effective session rules', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('maxOpenSessionsPerTerminal counts open and paused sessions',
        () async {
      final sessions = SessionService(db);
      const rules = SessionRules(maxOpenSessionsPerTerminal: 1);
      await sessions.checkOpenRules(rules, isAdmin: false, cashierId: 1);
      final a = await sessions.startSession(cashierId: 1, moneyAtStart: 0);
      await sessions.pauseSession(a.id);
      expect(
          () => sessions.checkOpenRules(rules, isAdmin: false, cashierId: 2),
          throwsA(isA<SessionRuleViolation>()));
      await sessions.checkOpenRules(rules, isAdmin: true, cashierId: 2);
    });

    test('requireOpeningFloat refuses a zero float', () async {
      final sessions = SessionService(db);
      const rules = SessionRules(requireOpeningFloat: true);
      expect(
          () => sessions.checkOpenRules(rules,
              isAdmin: false, cashierId: 1, moneyAtStart: 0),
          throwsA(isA<SessionRuleViolation>()));
      await sessions.checkOpenRules(rules,
          isAdmin: false, cashierId: 1, moneyAtStart: 100);
    });

    test('the new fields are read from /session-rules', () {
      final r = SessionRules.fromJson(
          {'maxOpenSessionsPerTerminal': 2, 'requireOpeningFloat': true});
      expect(r.maxOpenSessionsPerTerminal, 2);
      expect(r.requireOpeningFloat, isTrue);
      expect(r.hasAnyRule, isTrue);
    });
  });

  group('session details are additive only', () {
    test('no drawer balances, payment keys canonical', () {
      final session = CashSession(
        id: 1,
        code: 'CS-1',
        cashierId: 1,
        startedAt: DateTime(2026, 9, 25, 8),
        moneyAtStart: 200,
        status: 'ended',
        isSynced: false,
        updatedAt: DateTime(2026, 9, 25, 8),
        isClosingSession: false,
        autoClosed: false,
        zOverride: false,
      );
      final details = buildSessionDetails(
        SessionSummary(
          session: session,
          breakdown: const PaymentBreakdown(cash: 300, card: 120, paidCount: 4),
          ticketCount: 4,
          cashPaidIn: 20,
          cashPaidOut: 50,
        ),
        variance: -5,
      );
      final text = jsonEncode(details);
      for (final balance in ['openingFloat', 'expected', 'moneyAtStart', 'counted']) {
        expect(text.contains('"$balance'), isFalse,
            reason: '$balance would be double-counted across sessions');
      }
      final methods = (details['payments'] as Map)['byMethod'] as List;
      expect(methods.map((m) => m['method']), ['CASH', 'CARD']);
      expect((details['cash'] as Map)['variance'], -5);
      expect((details['cash'] as Map)['payOuts'], 50);
    });
  });
}

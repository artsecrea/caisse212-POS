import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/services/cash_session_service.dart';
import 'package:caisse212/domain/models/session_rules.dart'
    show SessionRuleViolation;

/// What a [CashSessionService] must do, whoever implements it: the local
/// service runs these on the till's database, a hub-backed one will run them
/// against the hub with its own harness.
abstract class CashSessionHarness {
  CashSessionService get sessions;

  /// A session in [status] (`active`, `paused` or `ended`), of cashier 1.
  Future<int> session(String status);

  /// A Z open on this terminal.
  Future<int> openZ();
  Future<int?> zOf(int sessionId);

  /// The terminal requires an opening float on a new session.
  Future<void> requireOpeningFloat();
  Future<String?> statusOf(int sessionId);

  /// An order of [sessionId] seated at a new table; returns the table.
  Future<int> seatedOrderIn(int sessionId);
  Future<int?> holderOf(int tableId);
  Future<double?> countedCashOf(int sessionId);

  Future<void> dispose();
}

void cashSessionServiceContract(
    String name, Future<CashSessionHarness> Function() make) {
  group('$name honours the CashSessionService contract', () {
    late CashSessionHarness h;

    setUp(() async => h = await make());
    tearDown(() => h.dispose());

    const cashier = (userId: 1, username: 'Amina');

    test('a cashier with no session gets a new one, counted in the Z',
        () async {
      final z = await h.openZ();

      final opened = await h.sessions
          .openForCashier(cashier: cashier, moneyAtStart: 50, isAdmin: false, zId: z);

      expect(opened.how, SessionOpening.started);
      expect(opened.session.status, 'active');
      expect(opened.session.moneyAtStart, 50);
      expect(await h.zOf(opened.session.id), z);

      final again = await h.sessions
          .openForCashier(cashier: cashier, moneyAtStart: 0, isAdmin: false);
      expect(again.how, SessionOpening.continued);
      expect(again.session.id, opened.session.id);
    });

    test('a cashier with a paused session gets it back, resumed', () async {
      final s = await h.session('paused');

      final opened = await h.sessions
          .openForCashier(cashier: cashier, moneyAtStart: 0, isAdmin: false);

      expect(opened.how, SessionOpening.resumed);
      expect(opened.session.id, s);
      expect(opened.session.status, 'active');
    });

    test('the open rules refuse a new session, except to an admin', () async {
      await h.requireOpeningFloat();

      await expectLater(
          h.sessions.openForCashier(
              cashier: cashier, moneyAtStart: 0, isAdmin: false),
          throwsA(isA<SessionRuleViolation>()));

      final admin = await h.sessions
          .openForCashier(cashier: cashier, moneyAtStart: 0, isAdmin: true);
      expect(admin.how, SessionOpening.started);
    });

    test('an open session pauses, then resumes, once each', () async {
      final s = await h.session('active');

      expect(await h.sessions.pause(s), isTrue);
      expect(await h.statusOf(s), 'paused');
      expect(await h.sessions.pause(s), isFalse,
          reason: 'already paused: nothing changes');

      expect(await h.sessions.resume(s, notifyAdmins: false), isNotNull,
          reason: 'it was paused, and says since when');
      expect(await h.statusOf(s), 'active');
      expect(await h.sessions.resume(s), isNull,
          reason: 'not paused: nothing changes');
    });

    test('a close ends the session with the cash counted', () async {
      final s = await h.session('active');

      await h.sessions.close(s,
          countedCash: 120, closedBy: (userId: 1, username: 'Amina'));

      expect(await h.statusOf(s), 'ended');
      expect(await h.countedCashOf(s), 120);
    });

    test('a close frees the session\u2019s tables only when asked', () async {
      final kept = await h.session('active');
      final freed = await h.session('active');
      final t1 = await h.seatedOrderIn(kept);
      final t2 = await h.seatedOrderIn(freed);

      await h.sessions.close(kept, countedCash: 0);
      await h.sessions.close(freed, countedCash: 0, freeTables: true);

      expect(await h.holderOf(t1), isNotNull);
      expect(await h.holderOf(t2), isNull);
    });

    test('publishing a close offline neither throws nor reopens it', () async {
      final s = await h.session('active');
      await h.sessions.close(s, countedCash: 0);

      await h.sessions.publishClose(s);

      expect(await h.statusOf(s), 'ended');
    });

    test('a closed session is not deleted', () async {
      final s = await h.session('ended');
      await expectLater(h.sessions.delete(s), throwsA(anything));
      expect(await h.statusOf(s), 'ended');
    });

    test('an open session can be deleted', () async {
      final s = await h.session('active');
      await h.sessions.delete(s);
      expect(await h.statusOf(s), isNull);
    });

    test('cash in and out are recorded unsigned, listed, and deleted',
        () async {
      final s = await h.session('active');

      final cashIn = await h.sessions.recordMovement(
          direction: 'IN', amount: 50, reason: 'float', sessionId: s);
      await h.sessions.recordMovement(
          direction: 'OUT', amount: -20, reason: 'supplier', sessionId: s);

      final listed = await h.sessions.movementsOf(s);
      expect(listed.map((m) => (m.direction, m.amount)),
          [('IN', 50.0), ('OUT', 20.0)]);

      await h.sessions.deleteMovement(cashIn.id);
      expect((await h.sessions.movementsOf(s)).map((m) => m.direction),
          ['OUT']);
    });
  });
}

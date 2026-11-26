import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/services/cash_session_service.dart';

/// What a [CashSessionService] must do, whoever implements it: the local
/// service runs these on the till's database, a hub-backed one will run them
/// against the hub with its own harness.
abstract class CashSessionHarness {
  CashSessionService get sessions;

  /// A session in [status] (`active`, `paused` or `ended`).
  Future<int> session(String status);
  Future<String?> statusOf(int sessionId);

  Future<void> dispose();
}

void cashSessionServiceContract(
    String name, Future<CashSessionHarness> Function() make) {
  group('$name honours the CashSessionService contract', () {
    late CashSessionHarness h;

    setUp(() async => h = await make());
    tearDown(() => h.dispose());

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

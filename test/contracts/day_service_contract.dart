import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart' show User;
import 'package:caisse212/domain/services/day_service.dart';
import 'package:caisse212/services/z_rules.dart' show ZRuleBlock;

/// What a [DayService] must do, whoever implements it: the local service
/// runs these on the till's database, a hub-backed one will run them against
/// the hub with its own harness.
abstract class DayHarness {
  DayService get days;

  /// A cashier with no Z permission.
  Future<User> cashier();

  /// The terminal's Z rules (`AUTO`/`MANUAL` open, `MANUAL`/`BY_SESSION`/
  /// `AUTO_AFTER_HOUR` close). Unset, a Z opens by itself and closes by hand.
  Future<void> rules({String? openMode, String? closeMode});

  /// An open session counted in Z [zId].
  Future<int> openSessionIn(int zId);

  Future<int?> openZId();
  Future<String?> zStatus(int zId);
  Future<String?> sessionStatus(int sessionId);
  Future<void> endSession(int sessionId);

  Future<void> dispose();
}

void dayServiceContract(String name, Future<DayHarness> Function() make) {
  group('$name honours the DayService contract', () {
    late DayHarness h;

    setUp(() async => h = await make());
    tearDown(() => h.dispose());

    test('with no Z open, the first session opens one, and the next reuses it',
        () async {
      final user = await h.cashier();

      final z = await h.days.ensureForSession(user: user);
      expect(z.status, 'open');
      expect(await h.openZId(), z.id);

      expect((await h.days.ensureForSession(user: user)).id, z.id);
    });

    test('in MANUAL open mode a new Z waits for a person to open it', () async {
      await h.rules(openMode: 'MANUAL');
      final user = await h.cashier();

      await expectLater(
          h.days.ensureForSession(user: user),
          throwsA(isA<ZRuleViolation>().having(
              (v) => v.block, 'block', ZRuleBlock.manualOpenRequired)));
      expect(await h.openZId(), isNull, reason: 'a refusal opens nothing');

      final z = await h.days.openManually(
          userId: user.id, hasOpenPermission: true, hasOverride: false);
      expect(await h.openZId(), z.id);
      expect(
          (await h.days.openManually(
                  userId: user.id, hasOpenPermission: true, hasOverride: false))
              .id,
          z.id,
          reason: 'already open: the same Z');
    });

    test('closing a Z needs the close permission', () async {
      final z = await h.days.ensureForSession(user: await h.cashier());

      final refused = await h.days
          .closeBlock(z, hasClosePermission: false, hasOverride: false);
      expect(refused?.block, ZRuleBlock.noClosePermission);
      expect(
          await h.days
              .closeBlock(z, hasClosePermission: true, hasOverride: false),
          isNull);
    });

    test('a close ends the Z and every session still open in it', () async {
      final z = await h.days.ensureForSession(user: await h.cashier());
      final s1 = await h.openSessionIn(z.id);
      final s2 = await h.openSessionIn(z.id);

      await h.days.close(z, closeMode: 'MANUAL');

      expect(await h.zStatus(z.id), 'closed');
      expect(await h.openZId(), isNull);
      expect(await h.sessionStatus(s1), 'ended');
      expect(await h.sessionStatus(s2), 'ended');
    });

    test('BY_SESSION: only the last open session takes the Z with it',
        () async {
      await h.rules(closeMode: 'BY_SESSION');
      final z = await h.days.ensureForSession(user: await h.cashier());
      final s1 = await h.openSessionIn(z.id);
      final s2 = await h.openSessionIn(z.id);

      expect(await h.days.closesWithSession(z, s1), isFalse,
          reason: 'another session of the Z is still open');

      await h.endSession(s2);
      expect(await h.days.closesWithSession(z, s1), isTrue);
    });

    test('closing by hand never asks to close the Z with a session', () async {
      final z = await h.days.ensureForSession(user: await h.cashier());
      final s = await h.openSessionIn(z.id);

      expect(await h.days.closesWithSession(z, s), isFalse);
      expect(await h.days.autoCloseDue(z), isFalse);
    });

    test('a report sums a Z that has sessions; one without has none',
        () async {
      final z = await h.days.ensureForSession(user: await h.cashier());
      expect(await h.days.report(z.id, isX: true), isNull);

      await h.openSessionIn(z.id);
      final x = await h.days.report(z.id, isX: true);
      expect(x, isNotNull);
      expect(x!.zLabel, isNotNull);
      expect(x.report.sessions, hasLength(1));
    });
  });
}

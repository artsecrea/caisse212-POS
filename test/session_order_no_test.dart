import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> session(String code, {int? zId}) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: code,
            cashierId: 1,
            moneyAtStart: 0,
            zId: Value(zId),
          ));

  group('session mode (default)', () {
    test('numbers count up from 1 within a session', () async {
      final s = await session('S1');
      expect(await db.nextSessionOrderNo(s), 1);
      expect(await db.nextSessionOrderNo(s), 2);
      expect(await db.nextSessionOrderNo(s), 3);
    });

    test('each session has its own sequence', () async {
      final a = await session('S1');
      final b = await session('S2');
      await db.nextSessionOrderNo(a);
      await db.nextSessionOrderNo(a);
      expect(await db.nextSessionOrderNo(b), 1);
      expect(await db.nextSessionOrderNo(a), 3);
    });

    test('reset restarts the session at 1', () async {
      final s = await session('S1');
      await db.nextSessionOrderNo(s);
      await db.nextSessionOrderNo(s);
      await db.resetOrderNumber(s);
      expect(await db.nextSessionOrderNo(s), 1);
    });
  });

  group('z mode', () {
    test('sessions of one Z share a sequence; a new Z restarts', () async {
      final a = await session('S1', zId: 7);
      final b = await session('S2', zId: 7);
      final c = await session('S3', zId: 8);
      expect(await db.nextSessionOrderNo(a, mode: 'z'), 1);
      expect(await db.nextSessionOrderNo(b, mode: 'z'), 2);
      expect(await db.nextSessionOrderNo(c, mode: 'z'), 1);
    });

    test('a session with no Z counts on its own', () async {
      final a = await session('S1');
      final b = await session('S2');
      await db.nextSessionOrderNo(a, mode: 'z');
      expect(await db.nextSessionOrderNo(b, mode: 'z'), 1);
    });

    test('reset restarts the whole Z', () async {
      final a = await session('S1', zId: 7);
      final b = await session('S2', zId: 7);
      await db.nextSessionOrderNo(a, mode: 'z');
      await db.resetOrderNumber(b, mode: 'z');
      expect(await db.nextSessionOrderNo(a, mode: 'z'), 1);
    });
  });

  group('manual mode', () {
    test('keeps counting across sessions and Zs', () async {
      final a = await session('S1', zId: 1);
      final b = await session('S2', zId: 2);
      await db.nextSessionOrderNo(a, mode: 'manual');
      expect(await db.nextSessionOrderNo(b, mode: 'manual'), 2);
    });

    test('only a reset restarts it, and needs no session', () async {
      final a = await session('S1');
      await db.nextSessionOrderNo(a, mode: 'manual');
      await db.resetOrderNumber(null, mode: 'manual');
      expect(await db.nextSessionOrderNo(a, mode: 'manual'), 1);
    });
  });

  test('switching mode does not disturb the other counters', () async {
    final s = await session('S1', zId: 3);
    await db.nextSessionOrderNo(s); // session:1 → 1
    await db.nextSessionOrderNo(s, mode: 'z'); // z:3 → 1
    expect(await db.nextSessionOrderNo(s), 2);
  });

  test('no session, or an unknown one, gives no number', () async {
    expect(await db.nextSessionOrderNo(null), isNull);
    expect(await db.nextSessionOrderNo(999), isNull);
  });

  test('concurrent callers never share a number', () async {
    final s = await session('S1');
    final got = await Future.wait(
        List.generate(20, (_) => db.nextSessionOrderNo(s)));
    expect(got.toSet(), {for (var i = 1; i <= 20; i++) i});
  });
}

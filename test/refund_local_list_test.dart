import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/refund_service.dart';

/// The refunds screen's local list: one session, or everything since a day.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late RefundService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    service = container.read(refundServiceProvider);
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<int> refund(String code, DateTime at, {int? sessionId}) =>
      db.into(db.refunds).insert(RefundsCompanion.insert(
          code: code,
          orderId: 1,
          orderCode: 'O1',
          refundedAt: Value(at),
          sessionId: Value(sessionId)));

  final day = DateTime(2026, 11, 20);

  test('since: from that instant on, no upper bound, newest first', () async {
    await refund('old', day.subtract(const Duration(minutes: 1)));
    await refund('edge', day);
    await refund('late', day.add(const Duration(days: 30)));
    await refund('mid', day.add(const Duration(hours: 3)));
    final rows = await service.localRefunds(since: day);
    expect(rows.map((r) => r.code), ['late', 'mid', 'edge']);
  });

  test('session: only that session, newest first', () async {
    await refund('a', day, sessionId: 1);
    await refund('b', day.add(const Duration(hours: 1)), sessionId: 1);
    await refund('other', day, sessionId: 2);
    await refund('none', day);
    final rows = await service.localRefunds(sessionId: 1);
    expect(rows.map((r) => r.code), ['b', 'a']);
  });

  test('no session and no since: nothing, not every refund', () async {
    await refund('a', day, sessionId: 1);
    await refund('none', day);
    expect(await service.localRefunds(), isEmpty);
  });

  test('since wins over a session id', () async {
    await refund('a', day, sessionId: 1);
    await refund('b', day, sessionId: 2);
    final rows = await service.localRefunds(sessionId: 1, since: day);
    expect(rows.map((r) => r.code).toSet(), {'a', 'b'});
  });
}

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/z_day_resolver.dart';
import 'package:caisse212/services/z_rules.dart' show formatZDay;

/// A refund is reported on the shift that gave the money back.
///
/// The push used to send `refundedAt` and nothing else, leaving the server to
/// derive a day from that timestamp. For a shift running 20:00 → 02:00 that
/// put every refund taken after midnight on the following day — money out on
/// one Z and the sale it reverses on another, so both were wrong.

void main() {
  late AppDatabase db;
  late DataSyncService sync;

  final shiftOpenedAt = DateTime(2026, 9, 20, 20, 0);
  final shiftDay = DateTime(2026, 9, 20);
  final afterMidnight = DateTime(2026, 9, 21, 0, 30);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sync = DataSyncService(db, ApiService(prefs), prefs);
  });
  tearDown(() => db.close());

  Future<int> openSession() =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: 'S1',
            cashierId: 1,
            moneyAtStart: 0,
            status: const Value('active'),
            startedAt: Value(shiftOpenedAt),
          ));

  Future<Refund> seedRefund({int? sessionId, DateTime? zDay}) async {
    final id = await db.into(db.refunds).insert(RefundsCompanion.insert(
          code: 'R-1',
          orderId: 1,
          orderCode: 'ORD1',
          method: const Value('CASH'),
          totalAmount: const Value(10),
          // Given after midnight — the timestamp the server would otherwise
          // derive the day from.
          refundedAt: Value(afterMidnight),
          sessionId: Value(sessionId),
          zDay: Value(zDay),
        ));
    return (db.select(db.refunds)..where((r) => r.id.equals(id))).getSingle();
  }

  Future<Map<String, dynamic>> payloadFor(Refund refund) =>
      sync.buildRefundPayload(refund, const [], ZDayResolver(db));

  test('carries the shift day, not the day it was given', () async {
    final refund = await seedRefund(zDay: shiftDay);
    final payload = await payloadFor(refund);

    expect(payload['zDay'], formatZDay(shiftDay));
    expect(payload['refundedAt'], afterMidnight.toUtc().toIso8601String(),
        reason: 'the timestamp still goes up unchanged — zDay is what says '
            'which shift owns it');
  });

  test('falls back to the session when the column is null', () async {
    final sessionId = await openSession();
    final refund = await seedRefund(sessionId: sessionId);

    expect((await payloadFor(refund))['zDay'], formatZDay(shiftDay),
        reason: 'refunds written before the column existed still know their '
            'session');
  });

  test('omits the field rather than sending null', () async {
    final refund = await seedRefund();

    expect((await payloadFor(refund)).containsKey('zDay'), isFalse,
        reason: 'a missing field leaves the server deriving its own day, '
            'which is the old behaviour — an explicit null asserts a guess');
  });
}

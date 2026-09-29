import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/z_day_resolver.dart';

/// Where `z_day` comes from: the cash session, and nothing else.
///
/// A shift that opens at 20:00 and runs past midnight is ONE Z day. Every row
/// it produces — the order typed at 00:30 included — belongs to the day the
/// shift opened. Two sources kept overriding that:
///
///   * the wall clock, wherever no session was loaded in memory, which put
///     anything after midnight on the next day; and
///   * the order's own `date`, which the delta pull re-derived `z_day` from
///     on every pass, moving an already-correct order to the following day
///     and then re-pushing it there.
///
/// These pin both, plus the rows that used to carry no `z_day` at all and so
/// left the backend to guess from a timestamp.

void main() {
  late AppDatabase db;
  late DataSyncService sync;

  // 20:00 the day before yesterday's boundary matters more than the exact
  // date: what is being tested is that the SHIFT's day wins over the day the
  // row was written, so the two have to differ.
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

  Future<int> openSession({DateTime? startedAt, String status = 'active'}) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: 'S1',
            cashierId: 1,
            moneyAtStart: 0,
            status: Value(status),
            startedAt: Value(startedAt ?? shiftOpenedAt),
          ));

  group('ZDayResolver', () {
    test('takes the day the SESSION opened, not the day it is asked', () async {
      final id = await openSession();
      expect(await ZDayResolver(db).forSession(id), shiftDay);
    });

    test('a session inside a Z takes the Z\'s opening day', () async {
      final zId = await db.into(db.zs).insert(ZsCompanion.insert(
            code: 'Z-1',
            createdBy: 1,
            startedAt: Value(DateTime(2026, 9, 19, 18, 0)),
          ));
      final sessionId = await openSession();
      await (db.update(db.cashSessions)
            ..where((s) => s.id.equals(sessionId)))
          .write(CashSessionsCompanion(zId: Value(zId)));

      expect(await ZDayResolver(db).forSession(sessionId),
          DateTime(2026, 9, 19),
          reason: 'every session in one shift shares the shift\'s day');
    });

    test('finds the active session without any in-memory state', () async {
      await openSession();
      expect(await ZDayResolver(db).current(), shiftDay,
          reason: 'a terminal restarted mid-shift still knows its shift');
    });

    test('a paused session is not the active one', () async {
      await openSession(status: 'paused');
      expect(await ZDayResolver(db).current(), equals(null));
    });

    test('no session open resolves to nothing, not to today', () async {
      expect(await ZDayResolver(db).current(), equals(null));
    });

    test('an ended session still reports the day it collected on', () async {
      final id = await openSession(status: 'ended');
      expect(await ZDayResolver(db).forSession(id), shiftDay,
          reason: 'closing a shift does not move what it took');
    });
  });

  group('order delta pull', () {
    Future<int> seedOrder({DateTime? zDay, int? sessionId}) async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(1),
            name: 'P1',
            price: 10,
            finalPrice: 10,
          ));
      return db.into(db.orders).insert(OrdersCompanion.insert(
            code: 'ORD1',
            // Typed after midnight — the calendar day the pull used to
            // re-derive from.
            date: Value(afterMidnight),
            createdAt: Value(afterMidnight),
            sessionId: Value(sessionId),
            zDay: Value(zDay),
          ));
    }

    Future<DateTime?> zDayOf(int id) async =>
        (await (db.select(db.orders)..where((o) => o.id.equals(id)))
                .getSingle())
            .zDay;

    test('a pull carrying no zDay leaves a correct one alone', () async {
      final orderId = await seedOrder(zDay: shiftDay);

      await sync.applyOrderDeltaForTesting({
        'code': 'ORD1',
        'status': 'COMPLETED',
        'date': afterMidnight.toIso8601String(),
      });

      expect(await zDayOf(orderId), shiftDay,
          reason: 'the order was rung up on the 20th shift and stays there; '
              're-deriving from its 00:30 timestamp moved it to the 21st');
    });

    test('an order with no zDay takes its session\'s, not its date\'s',
        () async {
      final sessionId = await openSession();
      final orderId = await seedOrder(sessionId: sessionId);

      await sync.applyOrderDeltaForTesting({
        'code': 'ORD1',
        'status': 'COMPLETED',
        'date': afterMidnight.toIso8601String(),
      });

      expect(await zDayOf(orderId), shiftDay);
    });

    test('the server\'s own zDay still wins when it sends one', () async {
      final orderId = await seedOrder(zDay: shiftDay);

      await sync.applyOrderDeltaForTesting({
        'code': 'ORD1',
        'status': 'COMPLETED',
        'zDay': DateTime(2026, 9, 18).toIso8601String(),
        'date': afterMidnight.toIso8601String(),
      });

      expect(await zDayOf(orderId), DateTime(2026, 9, 18));
    });

    test(
        'a remote order naming no session we know still falls back to its date',
        () async {
      await sync.applyOrderDeltaForTesting({
        'code': 'REMOTE1',
        'status': 'COMPLETED',
        'date': afterMidnight.toIso8601String(),
      });

      final row = await (db.select(db.orders)
            ..where((o) => o.code.equals('REMOTE1')))
          .getSingle();
      expect(row.zDay, DateTime(2026, 9, 21),
          reason: 'nothing better exists for an order from another terminal; '
              'a backfill must not land on this terminal\'s open shift');
    });
  });
}

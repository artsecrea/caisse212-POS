import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/daily_summary_service.dart';

/// The session Reports panel: the options-sold report and the whole-day scope.
void main() {
  late AppDatabase db;
  late DailySummaryService summaries;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    summaries = DailySummaryService(db);
  });
  tearDown(() => db.close());

  Future<int> session(String code, DateTime startedAt) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: code,
            cashierId: 1,
            moneyAtStart: 0,
            startedAt: Value(startedAt),
          ));

  Future<int> order(int sessionId, String code, {String status = 'COMPLETED'}) =>
      db.into(db.orders).insert(OrdersCompanion.insert(
            code: code,
            sessionId: Value(sessionId),
            status: Value(status),
          ));

  Future<int> line(int orderId, {double qty = 1}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            quantity: Value(qty),
            unitaryPrice: 50,
          ));

  Future<void> option(int lineId, int componentId,
          {String? name, int qty = 1, double price = 5, bool removal = false}) =>
      db.into(db.orderProductComponents).insert(
          OrderProductComponentsCompanion.insert(
            componentId: componentId,
            orderProductId: lineId,
            quantity: Value(qty),
            price: Value(price),
            name: Value(name),
            removalCharge: Value(removal),
          ));

  group('options sold', () {
    test('counts units served: option qty times line qty', () async {
      final s = await session('S1', DateTime(2026, 10, 16, 9));
      final o = await order(s, 'A');
      final l = await line(o, qty: 2);
      await option(l, 7, name: 'Cheese', qty: 2, price: 5);

      final r = await summaries.generateOptionsSummary(
          sessionIds: [s], scopeLabel: 'S1');

      expect(r.rows.single.quantity, 4,
          reason: 'double cheese on two burgers is four cheeses');
      expect(r.rows.single.amount, 20);
    });

    test('a charged removal never adds to the option it removes', () async {
      final s = await session('S1', DateTime(2026, 10, 16, 9));
      final o = await order(s, 'A');
      final l = await line(o);
      await option(l, 7, name: 'Cheese');
      await option(l, 7, name: 'Cheese', removal: true);

      final r = await summaries.generateOptionsSummary(
          sessionIds: [s], scopeLabel: 'S1');

      expect(r.rows, hasLength(2));
      expect(r.rows.where((x) => x.removal).single.quantity, 1);
      expect(r.rows.where((x) => !x.removal).single.quantity, 1);
    });

    test('cancelled orders are left out, as on the products report', () async {
      final s = await session('S1', DateTime(2026, 10, 16, 9));
      final live = await line(await order(s, 'A'));
      final dead = await line(await order(s, 'B', status: 'CANCELED'));
      await option(live, 7, name: 'Cheese');
      await option(dead, 7, name: 'Cheese');

      final r = await summaries.generateOptionsSummary(
          sessionIds: [s], scopeLabel: 'S1');

      expect(r.totalQuantity, 1);
    });

    test('falls back to the catalogue name when none was captured', () async {
      final s = await session('S1', DateTime(2026, 10, 16, 9));
      await db.into(db.components).insert(
          ComponentsCompanion.insert(id: const Value(9), name: 'Bacon'));
      await option(await line(await order(s, 'A')), 9);

      final r = await summaries.generateOptionsSummary(
          sessionIds: [s], scopeLabel: 'S1');

      expect(r.rows.single.name, 'Bacon');
    });
  });

  group('whole-day scope', () {
    test('without a Z: every session that started that day', () async {
      final a = await session('S1', DateTime(2026, 10, 16, 8));
      final b = await session('S2', DateTime(2026, 10, 16, 15));
      await session('S0', DateTime(2026, 10, 15, 20));

      final cs = await (db.select(db.cashSessions)
            ..where((s) => s.id.equals(b)))
          .getSingle();
      final scope = await summaries.dayScopeFor(cs);

      expect(scope.sessionIds.toSet(), {a, b});
      expect(scope.zCode, isNull);
      expect(scope.label, '2026-10-16');
    });
  });
}

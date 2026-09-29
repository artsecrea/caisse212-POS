import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/daily_summary_service.dart';

void main() {
  late AppDatabase db;
  late DailySummaryService svc;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    svc = DailySummaryService(db);
  });
  tearDown(() => db.close());

  Future<int> session(DateTime startedAt, {int? zId, String status = 'ended'}) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: 'S-${startedAt.toIso8601String()}',
            cashierId: 1,
            moneyAtStart: 0,
            startedAt: Value(startedAt),
            zId: Value(zId),
            status: Value(status),
          ));

  group('sessionIdsForPeriod', () {
    test('keeps the sessions whose day is inside the range, ends included',
        () async {
      final before = await session(DateTime(2026, 9, 1, 10));
      final first = await session(DateTime(2026, 9, 2, 10));
      final last = await session(DateTime(2026, 9, 4, 23));
      final after = await session(DateTime(2026, 9, 5, 0, 30));
      final ids = await svc.sessionIdsForPeriod(
          DateTime(2026, 9, 2), DateTime(2026, 9, 4));
      expect(ids, containsAll([first, last]));
      expect(ids, isNot(contains(before)));
      expect(ids, isNot(contains(after)));
    });

    test('an open session counts — the report is read mid-day', () async {
      final open = await session(DateTime(2026, 9, 28, 9), status: 'active');
      expect(
          await svc.sessionIdsForPeriod(
              DateTime(2026, 9, 28), DateTime(2026, 9, 28)),
          [open]);
    });

    test('a session past midnight belongs to its Z day', () async {
      final zId = await db.into(db.zs).insert(ZsCompanion.insert(
            code: 'Z-1',
            createdBy: 1,
            zDay: const Value('2026-09-10'),
            startedAt: Value(DateTime(2026, 9, 10, 18)),
          ));
      final late = await session(DateTime(2026, 9, 11, 0, 30), zId: zId);
      expect(
          await svc.sessionIdsForPeriod(
              DateTime(2026, 9, 10), DateTime(2026, 9, 10)),
          [late]);
      expect(
          await svc.sessionIdsForPeriod(
              DateTime(2026, 9, 11), DateTime(2026, 9, 11)),
          isEmpty);
    });
  });

  group('sortProductRows', () {
    ProductSummaryEntry row(String name, double qty, double net) =>
        ProductSummaryEntry(
          productId: name.hashCode,
          name: name,
          quantity: qty,
          gross: net,
          discount: 0,
          net: net,
        );
    final rows = [row('Tacos', 3, 90), row('Burger', 5, 50), row('Pizza', 5, 100)];

    test('quantity, ties broken by name', () {
      expect(sortProductRows(rows, ProductsSort.quantity).map((r) => r.name),
          ['Burger', 'Pizza', 'Tacos']);
    });
    test('amount', () {
      expect(sortProductRows(rows, ProductsSort.amount).map((r) => r.name),
          ['Pizza', 'Tacos', 'Burger']);
    });
    test('name', () {
      expect(sortProductRows(rows, ProductsSort.name).map((r) => r.name),
          ['Burger', 'Pizza', 'Tacos']);
    });
  });
}

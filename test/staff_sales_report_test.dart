import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/daily_summary_service.dart';

/// "Print this waiter's ticket" and "print this cashier's ticket" are the same
/// report read down a different column. These pin the split, and the one
/// judgement call in it: an order with nobody on the grouping field is kept
/// under an "unassigned" row rather than dropped, so the ticket's total still
/// reconciles with the Z.

void main() {
  late AppDatabase db;
  late DailySummaryService svc;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    svc = DailySummaryService(db);
  });
  tearDown(() => db.close());

  Future<void> session(int id) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            id: Value(id),
            code: 'S$id',
            cashierId: 1,
            moneyAtStart: 0,
          ));

  Future<void> waiter(int id, String first) =>
      db.into(db.waiters).insert(WaitersCompanion.insert(
            id: Value(id),
            firstName: first,
          ));

  Future<void> user(int id, String first) =>
      db.into(db.users).insert(UsersCompanion.insert(
            id: Value(id),
            username: 'u$id',
            password: 'x',
            firstName: first,
            lastName: '',
            type: 'cashier',
          ));

  Future<int> order({
    required String code,
    int sessionId = 1,
    int? waiterId,
    int? takenBy,
    double price = 100,
    double quantity = 1,
    double discountPercentage = 0,
    double paid = 0,
    String status = 'COMPLETED',
    String lineState = 'PENDING',
  }) async {
    final id = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: code,
          sessionId: Value(sessionId),
          waiterId: Value(waiterId),
          takenBy: Value(takenBy),
          status: Value(status),
          discountPercentage: Value(discountPercentage),
        ));
    await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
          orderId: id,
          productId: 1,
          quantity: Value(quantity),
          unitaryPrice: price,
          state: Value(lineState),
        ));
    if (paid > 0) {
      await db.into(db.tickets).insert(TicketsCompanion.insert(
            num: 'T$code',
            orderId: id,
            paymentMethod: 'CASH',
            amount: paid,
            sessionId: const Value(1),
            isPaid: const Value(true),
          ));
    }
    return id;
  }

  Future<StaffSalesReport> report(
    StaffGrouping grouping, {
    int? onlyStaffId,
  }) =>
      svc.generateStaffSales(
        sessionIds: [1],
        scopeLabel: 'day',
        grouping: grouping,
        onlyStaffId: onlyStaffId,
      );

  group('by waiter', () {
    test('one row per waiter, biggest seller first', () async {
      await session(1);
      await waiter(1, 'Amina');
      await waiter(2, 'Bilal');
      await order(code: 'A', waiterId: 1, price: 50);
      await order(code: 'B', waiterId: 2, price: 300);
      await order(code: 'C', waiterId: 1, price: 40);

      final r = await report(StaffGrouping.waiter);
      expect(r.rows.map((e) => e.name), ['Bilal', 'Amina']);
      expect(r.rows.first.net, 300);
      expect(r.rows.last.net, 90);
      expect(r.rows.last.orderCount, 2);
      expect(r.totalNet, 390);
    });

    test('carries what has actually been collected, and what has not',
        () async {
      await session(1);
      await waiter(1, 'Amina');
      await order(code: 'A', waiterId: 1, price: 100, paid: 60);

      final r = await report(StaffGrouping.waiter);
      expect(r.rows.single.paid, 60);
      expect(r.rows.single.due, 40,
          reason: 'the gap is why a waiter ticket gets printed at all');
    });

    test('narrowing to one waiter drops everyone else', () async {
      await session(1);
      await waiter(1, 'Amina');
      await waiter(2, 'Bilal');
      await order(code: 'A', waiterId: 1, price: 50);
      await order(code: 'B', waiterId: 2, price: 300);

      final r = await report(StaffGrouping.waiter, onlyStaffId: 2);
      expect(r.rows, hasLength(1));
      expect(r.rows.single.name, 'Bilal');
      expect(r.totalNet, 300);
      expect(r.onlyStaffName, 'Bilal');
    });

    test('orders with no waiter land in one unassigned row, not the bin',
        () async {
      await session(1);
      await waiter(1, 'Amina');
      await order(code: 'A', waiterId: 1, price: 100);
      await order(code: 'B', price: 70);
      await order(code: 'C', price: 30);

      final r = await report(StaffGrouping.waiter);
      expect(r.rows, hasLength(2));
      final unassigned = r.rows.firstWhere((e) => e.staffId == null);
      expect(unassigned.net, 100);
      expect(unassigned.orderCount, 2);
      expect(r.totalNet, 200, reason: 'must still reconcile with the Z');
    });
  });

  group('by cashier', () {
    test('groups on takenBy', () async {
      await session(1);
      await user(7, 'Karim');
      await order(code: 'A', takenBy: 7, price: 120);

      final r = await report(StaffGrouping.cashier);
      expect(r.rows.single.name, 'Karim');
      expect(r.rows.single.net, 120);
    });

    test('falls back to createdBy for rows written before takenBy existed',
        () async {
      await session(1);
      await user(7, 'Karim');
      final id = await order(code: 'A', price: 80);
      await (db.update(db.orders)..where((o) => o.id.equals(id)))
          .write(const OrdersCompanion(createdBy: Value(7)));

      final r = await report(StaffGrouping.cashier);
      expect(r.rows.single.name, 'Karim');
    });

    test('the same day reads differently down each column', () async {
      // One waiter, two cashiers — the two tickets must not agree on shape
      // but must agree on the total.
      await session(1);
      await waiter(1, 'Amina');
      await user(7, 'Karim');
      await user(8, 'Nadia');
      await order(code: 'A', waiterId: 1, takenBy: 7, price: 100);
      await order(code: 'B', waiterId: 1, takenBy: 8, price: 100);

      final byWaiter = await report(StaffGrouping.waiter);
      final byCashier = await report(StaffGrouping.cashier);
      expect(byWaiter.rows, hasLength(1));
      expect(byCashier.rows, hasLength(2));
      expect(byWaiter.totalNet, byCashier.totalNet);
    });
  });

  group('what is excluded', () {
    test('a cancelled order is not a sale', () async {
      await session(1);
      await waiter(1, 'Amina');
      await order(code: 'A', waiterId: 1, price: 100);
      await order(code: 'B', waiterId: 1, price: 999, status: 'CANCELED');

      final r = await report(StaffGrouping.waiter);
      expect(r.totalNet, 100);
      expect(r.orderCount, 1);
    });

    test('a voided line is dropped but its order still counts', () async {
      await session(1);
      await waiter(1, 'Amina');
      await order(code: 'A', waiterId: 1, price: 100, lineState: 'CANCELED');

      final r = await report(StaffGrouping.waiter);
      expect(r.rows.single.net, 0);
      expect(r.rows.single.orderCount, 1);
    });

    test('the order-level discount comes off the staff total too', () async {
      await session(1);
      await waiter(1, 'Amina');
      await order(
          code: 'A', waiterId: 1, price: 200, discountPercentage: 10);
      expect((await report(StaffGrouping.waiter)).totalNet, 180);
    });

    test('a day with no orders is an empty report, not a crash', () async {
      await session(1);
      final r = await report(StaffGrouping.waiter);
      expect(r.rows, isEmpty);
      expect(r.totalNet, 0);
    });
  });
}

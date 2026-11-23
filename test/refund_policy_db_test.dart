import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/refund_policy.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/refund_policy_store.dart';
import 'package:caisse212/services/refund_service.dart';
import 'package:caisse212/services/session_service.dart';
import 'package:caisse212/services/session_z_details.dart';
import 'package:caisse212/services/z_day_resolver.dart';

/// A refund lands in the Z it is paid out in, whatever Z the sale was in; the
/// till works out which sales are "earlier" from its own session/Z rows, and
/// the Z reports refunds with their split, earlier-sales part and waste.
void main() {
  late AppDatabase db;
  late RefundService refunds;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    refunds = RefundService(db);
  });
  tearDown(() => db.close());

  Future<int> z(String day, {String status = 'open'}) =>
      db.into(db.zs).insert(ZsCompanion.insert(
            code: 'Z-$day-$status',
            createdBy: 1,
            zDay: Value(day),
            status: Value(status),
          ));

  Future<int> session(String code, {int? zId, String status = 'active'}) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: code,
            cashierId: 1,
            moneyAtStart: 0,
            status: Value(status),
            zId: Value(zId),
          ));

  Future<Order> order(String code,
      {int? sessionId, DateTime? zDay, String pay = 'CASH'}) async {
    final id = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: code,
          status: const Value('COMPLETED'),
          sessionId: Value(sessionId),
          zDay: Value(zDay),
          isSynced: const Value(true),
        ));
    await db.into(db.tickets).insert(TicketsCompanion.insert(
          num: '0001',
          orderId: id,
          paymentMethod: pay,
          amount: 100,
          isPaid: const Value(true),
        ));
    return (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();
  }

  Future<int> line(int orderId, {int productId = 5, double price = 50}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: productId,
            quantity: const Value(2),
            unitaryPrice: price,
            state: const Value('PENDING'),
          ));

  group('closed-Z detection', () {
    test('sale in the current Z: not earlier', () async {
      final zNow = await z('2026-10-07');
      final s = await session('S-NOW', zId: zNow);
      final o = await order('O1', sessionId: s, zDay: DateTime(2026, 10, 7));
      final ctx = await refunds.policyContextFor(o,
          currentZId: zNow, currentZDay: DateTime(2026, 10, 7));
      expect(ctx.saleZClosed, isFalse);
      expect(ctx.paidMethods, {'CASH'});
    });

    test('sale in a closed Z of the same day (zSeq 2 now): earlier', () async {
      final zOld = await z('2026-10-07', status: 'closed');
      final zNow = await z('2026-10-07');
      final s = await session('S-OLD', zId: zOld, status: 'ended');
      final o = await order('O2', sessionId: s, zDay: DateTime(2026, 10, 7));
      final ctx = await refunds.policyContextFor(o,
          currentZId: zNow, currentZDay: DateTime(2026, 10, 7));
      expect(ctx.saleZClosed, isTrue,
          reason: 'decided from the Z row, not the calendar');
    });

    test('order imported from another till: earlier only if an earlier day',
        () async {
      final yesterday =
          await order('O3', zDay: DateTime(2026, 10, 6), pay: 'CARD');
      final sameDay = await order('O4', zDay: DateTime(2026, 10, 7));
      final today = DateTime(2026, 10, 7);
      expect(
          (await refunds.policyContextFor(yesterday,
                  currentZId: null, currentZDay: today))
              .saleZClosed,
          isTrue);
      expect(
          (await refunds.policyContextFor(sameDay,
                  currentZId: null, currentZDay: today))
              .saleZClosed,
          isFalse);
    });

    test('non-refundable products are reported per line', () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(7),
            name: 'Tajine',
            price: 50,
            finalPrice: 50,
            refundable: const Value(false),
          ));
      final o = await order('O5');
      final served = await line(o.id, productId: 7);
      final bottled = await line(o.id, productId: 5);
      final ctx = await refunds.policyContextFor(o,
          currentZId: null, currentZDay: DateTime(2026, 10, 7));
      expect(ctx.nonRefundableLineIds, {served});
      expect(ctx.nonRefundableLineIds.contains(bottled), isFalse);
    });
  });

  test('audit fields are stored, the Z breakdown adds them up, and both '
      'reach the server', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final zNow = await z('2026-10-07');
    final today = await session('S-TODAY', zId: zNow);

    final old = await order('OLD', zDay: DateTime(2026, 10, 1));
    final oldLine = await line(old.id);
    final fresh = await order('NEW', sessionId: today);
    final freshLine = await line(fresh.id);

    final r1 = await refunds.createRefund(
      order: old,
      method: 'CASH',
      lines: [RefundLineDraft(orderProductId: oldLine, quantity: 1, restock: false)],
      sessionId: today,
      reason: 'Produit défectueux',
      reasonCode: 'DEFECTIVE',
      approvedBy: 3,
      policyFlags: const [RefundPolicyFlag.closedZ, RefundPolicyFlag.window],
      earlierSale: true,
    );
    await refunds.createRefund(
      order: fresh,
      method: 'CARD',
      lines: [RefundLineDraft(orderProductId: freshLine, quantity: 2)],
      sessionId: today,
    );

    expect(r1.policyFlags, 'CLOSED_Z,WINDOW');
    expect(r1.reasonCode, 'DEFECTIVE');
    expect(r1.approvedBy, 3);

    final b = await refunds.breakdownForSessions([today]);
    expect(b.count, 2);
    expect(b.total, 150);
    expect(b.cash, 50);
    expect(b.earlierSales, 50);
    expect(b.waste, 50, reason: 'only the line not returned to stock');
    expect(b.byMethod['CASH'], (count: 1, amount: 50.0));
    expect(b.byMethod['CARD'], (count: 1, amount: 100.0));

    // Session details: numbers, so the server's Z merger sums them.
    final summary = await SessionService(db).getSessionSummary(today);
    final details = buildSessionDetails(summary);
    final rd = details['refunds'] as Map<String, dynamic>;
    expect(rd['count'], 2);
    expect(rd['earlierSales'], isA<num>());
    expect(rd['waste'], 50.0);
    expect((rd['byMethod'] as List).every((m) => (m as Map)['amount'] is num),
        isTrue);

    // Payload: today's session code, the preset, the approver and the flags.
    final sync = DataSyncService(db, ApiService(prefs), prefs);
    final payload = await sync.buildRefundPayload(r1, const [], ZDayResolver(db));
    expect(payload['sessionCode'], 'S-TODAY');
    expect(payload['reasonCode'], 'DEFECTIVE');
    expect(payload['approvedBy'], 3);
    expect(payload['policyFlags'], ['CLOSED_Z', 'WINDOW']);
  });

  test('a plain refund sends none of the policy fields', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final o = await order('PLAIN');
    final l = await line(o.id);
    final r = await refunds.createRefund(
        order: o,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: l, quantity: 1)]);
    final payload = await DataSyncService(db, ApiService(prefs), prefs)
        .buildRefundPayload(r, const [], ZDayResolver(db));
    for (final k in ['sessionCode', 'reasonCode', 'approvedBy', 'policyFlags']) {
      expect(payload.containsKey(k), isFalse, reason: k);
    }
  });

  test('the cached policy survives, and 204 resets to the defaults', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = RefundPolicyStore(prefs);
    expect(store.current.windowDays, isNull);
    await store.apply({'windowDays': 14, 'allowedMethods': ['CASH']});
    expect(RefundPolicyStore(prefs).current.windowDays, 14);
    await store.apply(null);
    expect(store.current.allowedMethods, kRefundMethods);
  });
}

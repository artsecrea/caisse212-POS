import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/database/app_database.dart';
import '../domain/models/refund_policy.dart';
import '../utils/escpos_text.dart';
import 'api_service.dart';
import 'daily_summary_service.dart';
import 'data_sync_service.dart';
import 'printing_service.dart';
import 'refund_service.dart';
import 'session_service.dart';
import 'session_z_details.dart';
import 'exchange_service.dart';
import '../domain/models/exchange.dart';
import 'z_day_resolver.dart';

/// One verified step of the refund sandbox.
class SandboxCheck {
  final String label;
  final bool ok;
  final String detail;
  const SandboxCheck(this.label, this.ok, this.detail);
}

class SandboxResult {
  final List<SandboxCheck> checks;

  /// The X of the sandbox session, decoded from the exact printer bytes.
  final String xText;

  /// The receipt of the first exchange (old + new goods), same decoding.
  final String exchangeTicketText;
  const SandboxResult(this.checks, this.xText, [this.exchangeTicketText = '']);

  bool get allOk => checks.every((c) => c.ok);
}

/// A full refund scenario run through the REAL code — policy check, refund
/// service, session summary, Z details, sync payload and the X report bytes —
/// on a throwaway in-memory database.
///
/// In-memory on purpose: this till's real database syncs to the server, and a
/// test refund written there would be pushed to BMS as real money out. Nothing
/// here touches the till's data or the network. Debug builds only (Test mode).
///
/// The scenario (figures are checked, not just printed):
///   * yesterday, closed Z: order A = 2 × Coca 15 + 1 × Tajine 80 (non-
///     refundable), paid CARD 110;
///   * today, open session (float 200): order B = 3 × Coca 15, paid CASH 45;
///   * policy: 7-day window, approval above 50, closed Z needs a permission,
///     method must match the payment, preset reasons.
///   1. 1 Coca from B, cash, by a cashier → plain refund, no approval.
///   2. 1 Coca from A, CASH although paid by card → CLOSED_Z + METHOD → approved.
///   3. the Tajine from A, card, not returned to stock → CLOSED_Z + AMOUNT +
///      NON_REFUNDABLE → approved; counted as waste.
///   4. 3 more Coca from B (2 left) → refused by the cap.
///   5. another till already refunded 1 Coca of B → only 1 left here.
///   6. EXCHANGE: T-shirt M (120, paid cash) swapped for T-shirt L (150) →
///      credit 120, the customer pays 30 cash.
///   7. EXCHANGE: Jean (200, paid card) swapped for a belt (80) → credit 80
///      spent, 120 given back in cash.
///   Then the Z: refunds 430 (cash 150, exchanged 200), payments include
///   200 of exchange credit, drawer 200 + 195 − 150 = 245, and the X.
class RefundSandbox {
  static const policy = RefundPolicy(
    windowDays: 7,
    approvalAbove: 50,
    closedZNeedsPermission: true,
    requireReason: true,
    reasons: [
      RefundReason('DEFECTIVE', 'Produit défectueux'),
      RefundReason('OTHER', 'Autre'),
    ],
    allowedMethods: ['CASH', 'CARD'],
    methodMustMatchPayment: true,
  );

  /// [prefs] are the till's own and are only READ here (the payload builder
  /// needs an ApiService); the sandbox writes nothing outside its database.
  static Future<SandboxResult> run({
    required PrintingService printing,
    required SharedPreferences prefs,
  }) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final checks = <SandboxCheck>[];
    void check(String label, bool ok, String detail) =>
        checks.add(SandboxCheck(label, ok, detail));

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      String day(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      // ── Catalogue, Zs, sessions ────────────────────────────────────────
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value(1), name: 'Coca 33cl', price: 15, finalPrice: 15));
      for (final (id, name, price) in const [
        (3, 'T-shirt M', 120.0),
        (4, 'T-shirt L', 150.0),
        (5, 'Jean', 200.0),
        (6, 'Ceinture', 80.0),
      ]) {
        await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id), name: name, price: price, finalPrice: price));
      }
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: const Value(2),
          name: 'Tajine',
          price: 80,
          finalPrice: 80,
          refundable: const Value(false)));

      final zOld = await db.into(db.zs).insert(ZsCompanion.insert(
          code: 'Z-OLD',
          createdBy: 1,
          zDay: Value(day(yesterday)),
          status: const Value('closed'),
          startedAt: Value(yesterday.add(const Duration(hours: 9)))));
      final zNow = await db.into(db.zs).insert(ZsCompanion.insert(
          code: 'Z-NOW',
          createdBy: 1,
          zDay: Value(day(today)),
          startedAt: Value(today.add(const Duration(hours: 8)))));

      final sOld = await db.into(db.cashSessions).insert(
          CashSessionsCompanion.insert(
              code: 'CS-SANDBOX-OLD',
              cashierId: 1,
              moneyAtStart: 0,
              status: const Value('ended'),
              zId: Value(zOld),
              startedAt: Value(yesterday.add(const Duration(hours: 9)))));
      final sNow = await db.into(db.cashSessions).insert(
          CashSessionsCompanion.insert(
              code: 'CS-SANDBOX-NOW',
              cashierId: 1,
              moneyAtStart: 200,
              status: const Value('active'),
              zId: Value(zNow),
              startedAt: Value(today.add(const Duration(hours: 8)))));

      // ── Sales ──────────────────────────────────────────────────────────
      Future<Order> sale(String code, int session, DateTime zDay,
          String method, double amount) async {
        final id = await db.into(db.orders).insert(OrdersCompanion.insert(
              code: code,
              status: const Value('COMPLETED'),
              sessionId: Value(session),
              zDay: Value(zDay),
              date: Value(zDay.add(const Duration(hours: 12))),
              isSynced: const Value(true),
            ));
        await db.into(db.tickets).insert(TicketsCompanion.insert(
              num: '0001',
              orderId: id,
              paymentMethod: method,
              amount: amount,
              isPaid: const Value(true),
              sessionId: Value(session),
              zDay: Value(zDay),
              isSynced: const Value(true),
            ));
        return (db.select(db.orders)..where((o) => o.id.equals(id)))
            .getSingle();
      }

      Future<int> line(int orderId, int productId, double qty, double price,
              int serverId) =>
          db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
                orderId: orderId,
                productId: productId,
                quantity: Value(qty),
                unitaryPrice: price,
                state: const Value('SERVED'),
                serverId: Value(serverId),
              ));

      final orderA = await sale('SANDBOX-A', sOld, yesterday, 'CARD', 110);
      final aCoca = await line(orderA.id, 1, 2, 15, 9001);
      final aTajine = await line(orderA.id, 2, 1, 80, 9002);
      final orderB = await sale('SANDBOX-B', sNow, today, 'CASH', 45);
      final bCoca = await line(orderB.id, 1, 3, 15, 9003);

      final refunds = RefundService(db);
      // A cashier: holds neither policy token.
      bool cashier(String _) => false;

      Future<List<RefundPolicyIssue>> issuesFor(
          Order o, double total, String method,
          {required bool full, bool nonRefundable = false}) async {
        final ctx = await refunds.policyContextFor(o,
            currentZId: zNow, currentZDay: today);
        return refundPolicyIssues(
            policy,
            RefundAttempt(
              saleZDay: ctx.saleZDay,
              currentZDay: today,
              saleZClosed: ctx.saleZClosed,
              total: total,
              method: method,
              paidMethods: ctx.paidMethods,
              includesNonRefundable: nonRefundable,
              isFullRefund: full,
            ));
      }

      String wires(List<RefundPolicyIssue> i) =>
          i.isEmpty ? 'none' : i.map((e) => e.flag.wire).join(', ');

      // ── 1. Plain refund ────────────────────────────────────────────────
      final i1 = await issuesFor(orderB, 15, 'CASH', full: false);
      check('1. Same-session refund needs no approval', i1.isEmpty,
          'policy issues: ${wires(i1)}');
      final r1 = await refunds.createRefund(
        order: orderB,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: bCoca, quantity: 1)],
        reason: 'Produit défectueux',
        reasonCode: 'DEFECTIVE',
        sessionId: sNow,
        zDay: today,
        posName: 'SANDBOX',
      );
      check('1. Recorded: 15.00 cash', r1.totalAmount == 15 && r1.method == 'CASH',
          '${r1.code} · ${r1.totalAmount.toStringAsFixed(2)} ${r1.method}');

      // ── 2. Earlier Z, wrong method ─────────────────────────────────────
      final ctxA = await refunds.policyContextFor(orderA,
          currentZId: zNow, currentZDay: today);
      check('2. Order A detected as sold in a closed Z', ctxA.saleZClosed,
          'paid with: ${ctxA.paidMethods.join(', ')}');
      final i2 = await issuesFor(orderA, 15, 'CASH', full: false);
      final open2 = unapprovedIssues(i2, cashier);
      check(
          '2. Cash refund of a card sale from a closed Z needs approval',
          i2.map((e) => e.flag).toSet().containsAll(
                  {RefundPolicyFlag.closedZ, RefundPolicyFlag.method}) &&
              permissionsNeeded(open2)
                  .containsAll({kRefundClosedZPermission, kRefundOverridePermission}),
          'issues: ${wires(i2)} · approver needs: ${permissionsNeeded(open2).join(', ')}');
      final r2 = await refunds.createRefund(
        order: orderA,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: aCoca, quantity: 1)],
        reason: 'Autre: client pressé',
        reasonCode: 'OTHER',
        approvedBy: 2,
        policyFlags: [for (final i in i2) i.flag],
        earlierSale: true,
        sessionId: sNow,
        zDay: today,
        posName: 'SANDBOX',
      );
      check('2. Booked into TODAY\'s session, not the closed one',
          r2.sessionId == sNow && r2.earlierSale && r2.approvedBy == 2,
          'session ${r2.sessionId == sNow ? 'CS-SANDBOX-NOW' : r2.sessionId} · '
              'flags ${r2.policyFlags}');

      // ── 3. Non-refundable, above the threshold, waste ─────────────────
      final i3 = await issuesFor(orderA, 80, 'CARD',
          full: false, nonRefundable: true);
      check(
          '3. Tajine: closed Z + amount + non-refundable',
          i3.map((e) => e.flag).toSet().containsAll({
            RefundPolicyFlag.closedZ,
            RefundPolicyFlag.amount,
            RefundPolicyFlag.nonRefundable
          }),
          'issues: ${wires(i3)}');
      check('3. Non-refundable line detected',
          ctxA.nonRefundableLineIds.contains(aTajine), 'line #$aTajine');
      final r3 = await refunds.createRefund(
        order: orderA,
        method: 'CARD',
        lines: [
          RefundLineDraft(orderProductId: aTajine, quantity: 1, restock: false)
        ],
        reason: 'Produit défectueux',
        reasonCode: 'DEFECTIVE',
        approvedBy: 2,
        policyFlags: [for (final i in i3) i.flag],
        earlierSale: true,
        sessionId: sNow,
        zDay: today,
        posName: 'SANDBOX',
      );
      check('3. Recorded: 80.00 card, not returned to stock',
          r3.totalAmount == 80, r3.code);

      // ── 4. Over-refund cap ─────────────────────────────────────────────
      try {
        await refunds.createRefund(
          order: orderB,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: bCoca, quantity: 3)],
          sessionId: sNow,
        );
        check('4. Refunding 3 more Coca (2 left) is refused', false,
            'it was accepted — the cap did not hold');
      } on RefundCapException catch (e) {
        check('4. Refunding 3 more Coca (2 left) is refused', e.remaining == 2,
            'refused: ${e.remaining.toStringAsFixed(0)} left');
      }

      // ── 5. Another till's refund counts ───────────────────────────────
      final elsewhere = otherTillsRefunded(
        serverRefunds: [
          {
            'code': 'RF-T2-SANDBOX',
            'lines': [
              {'orderProductId': 9003, 'quantity': 1}
            ]
          },
          // This till's own refund, as the server would list it too.
          {
            'code': r1.code,
            'lines': [
              {'orderProductId': 9003, 'quantity': 1}
            ]
          },
        ],
        localCodes: await refunds.localRefundCodes(orderB.id),
        localIdByServerId: await refunds.localIdsByServerId(orderB.id),
      );
      try {
        await refunds.createRefund(
          order: orderB,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: bCoca, quantity: 2)],
          sessionId: sNow,
          refundedElsewhere: elsewhere,
        );
        check('5. A refund made on another till is counted', false,
            'accepted 2 although only 1 is left');
      } on RefundCapException catch (e) {
        check('5. A refund made on another till is counted',
            e.remaining == 1 && (elsewhere[bCoca] ?? 0) == 1,
            'other tills: ${elsewhere[bCoca] ?? 0} · left here: ${e.remaining.toStringAsFixed(0)}');
      }

      // ── 6 & 7. Exchanges ───────────────────────────────────────────────
      final orderC = await sale('SANDBOX-C', sNow, today, 'CASH', 120);
      final cShirt = await line(orderC.id, 3, 1, 120, 9004);
      final orderD = await sale('SANDBOX-D', sNow, today, 'CARD', 200);
      final dJean = await line(orderD.id, 5, 1, 200, 9005);

      // The new goods, saved but unpaid — what the till does on Pay.
      Future<int> newOrder(String code, int productId, double price) async {
        final id = await db.into(db.orders).insert(OrdersCompanion.insert(
              code: code,
              status: const Value('PENDING'),
              sessionId: Value(sNow),
              zDay: Value(today),
            ));
        await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
              orderId: id,
              productId: productId,
              quantity: const Value(1),
              unitaryPrice: price,
              state: const Value('PENDING'),
            ));
        return id;
      }

      final exchanges = ExchangeService(db);
      final n1 = await newOrder('SANDBOX-N1', 4, 150);
      final draft6 = ExchangeDraft(order: orderC, lines: [
        ExchangeReturnLine(
            orderProductId: cShirt,
            name: 'T-shirt M',
            quantity: 1,
            amount: 120,
            restock: true),
      ], reason: 'Taille', reasonCode: 'OTHER');
      final ex6 = await exchanges.settle(
        draft: draft6,
        newOrderId: n1,
        newOrderCode: 'SANDBOX-N1',
        newTotal: 150,
        payMethod: 'CASH',
        backMethod: 'CASH',
        sessionId: sNow,
        zDay: today,
        posName: 'SANDBOX',
      );
      final n1Tickets = await (db.select(db.tickets)
            ..where((t) => t.orderId.equals(n1)))
          .get();
      check(
          '6. Exchange T-shirt M → L: credit 120, customer pays 30',
          ex6.settlement.creditUsed == 120 &&
              ex6.settlement.customerPays == 30 &&
              ex6.refund.exchangeAmount == 120 &&
              ex6.refund.exchangeOrderCode == 'SANDBOX-N1',
          'refund ${ex6.refund.code} · exchanged ${ex6.refund.exchangeAmount.toStringAsFixed(2)} · '
              'tickets ${n1Tickets.map((t) => '${t.paymentMethod} ${t.amount.toStringAsFixed(2)}').join(' + ')}');
      check(
          '6. New order paid by EXCHANGE 120 + CASH 30, lines settled',
          n1Tickets.length == 2 &&
              n1Tickets.any((t) =>
                  t.paymentMethod == 'EXCHANGE' &&
                  t.amount == 120 &&
                  t.exchangeRefundCode == ex6.refund.code) &&
              n1Tickets.any((t) => t.paymentMethod == 'CASH' && t.amount == 30) &&
              (await (db.select(db.orderProducts)
                        ..where((p) => p.orderId.equals(n1) & p.ticketId.isNull()))
                      .get())
                  .isEmpty,
          '${n1Tickets.length} tickets');

      final n2 = await newOrder('SANDBOX-N2', 6, 80);
      final draft7 = ExchangeDraft(order: orderD, lines: [
        ExchangeReturnLine(
            orderProductId: dJean,
            name: 'Jean',
            quantity: 1,
            amount: 200,
            restock: true),
      ]);
      final ex7 = await exchanges.settle(
        draft: draft7,
        newOrderId: n2,
        newOrderCode: 'SANDBOX-N2',
        newTotal: 80,
        payMethod: 'CASH',
        backMethod: 'CASH',
        sessionId: sNow,
        zDay: today,
        posName: 'SANDBOX',
      );
      check(
          '7. Exchange Jean → belt: 80 credit used, 120 given back in cash',
          ex7.settlement.creditUsed == 80 &&
              ex7.settlement.paidBack == 120 &&
              refundCashPaidBack(ex7.refund) == 120,
          'refund ${ex7.refund.code} · method ${ex7.refund.method} · '
              'cash back ${refundCashPaidBack(ex7.refund).toStringAsFixed(2)}');

      // ── Z / drawer ─────────────────────────────────────────────────────
      final summary = await SessionService(db).getSessionSummary(sNow);
      final b = summary.refunds;
      check('Z: refunds total 430.00 (cash 150.00, exchanged 200.00)',
          (summary.refundsTotal - 430).abs() < .001 &&
              (summary.refundsCash - 150).abs() < .001 &&
              (b.exchange - 200).abs() < .001,
          'total ${summary.refundsTotal.toStringAsFixed(2)} · cash ${summary.refundsCash.toStringAsFixed(2)} · '
              'exchanged ${b.exchange.toStringAsFixed(2)}');
      check('Z: 5 refunds, 95.00 for earlier sales, 80.00 waste',
          b.count == 5 &&
              (b.earlierSales - 95).abs() < .001 &&
              (b.waste - 80).abs() < .001,
          'count ${b.count} · earlier ${b.earlierSales.toStringAsFixed(2)} · waste ${b.waste.toStringAsFixed(2)} · '
              '${b.byMethod.entries.map((e) => '${e.key} ${e.value.count}×${e.value.amount.toStringAsFixed(2)}').join(', ')}');
      check('Payments: cash 195.00, card 200.00, exchange credit 200.00',
          (summary.breakdown.cash - 195).abs() < .001 &&
              (summary.breakdown.card - 200).abs() < .001 &&
              (summary.breakdown.exchange - 200).abs() < .001,
          'cash ${summary.breakdown.cash.toStringAsFixed(2)} · card ${summary.breakdown.card.toStringAsFixed(2)} · '
              'exchange ${summary.breakdown.exchange.toStringAsFixed(2)}');
      check('Drawer: expected cash 245.00 (200 float + 195 cash in − 150 cash out)',
          (summary.expectedCashAtEnd - 245).abs() < .001,
          'expected ${summary.expectedCashAtEnd.toStringAsFixed(2)}');

      final details = buildSessionDetails(summary);
      final rd = details['refunds'] as Map<String, dynamic>;
      check('Server Z details carry numbers',
          rd['total'] is num &&
              rd['earlierSales'] is num &&
              rd['exchange'] == 200.0 &&
              rd['count'] == 5,
          '$rd');

      // ── Sync payload ───────────────────────────────────────────────────
      // The payload builder is test-visible by design; this debug sandbox is
      // a test that runs inside the app.
      final sync = DataSyncService(db, ApiService(prefs), prefs);
      final payload = await sync
          // ignore: invalid_use_of_visible_for_testing_member
          .buildRefundPayload(r2, const [], ZDayResolver(db));
      check(
          'Payload: today\'s session, approver, flags',
          payload['sessionCode'] == 'CS-SANDBOX-NOW' &&
              payload['approvedBy'] == 2 &&
              (payload['policyFlags'] as List).contains('CLOSED_Z'),
          'sessionCode ${payload['sessionCode']} · approvedBy ${payload['approvedBy']} · '
              'policyFlags ${payload['policyFlags']} · reasonCode ${payload['reasonCode']}');
      final exPayload = await sync
          // ignore: invalid_use_of_visible_for_testing_member
          .buildRefundPayload(ex6.refund, const [], ZDayResolver(db));
      check(
          'Payload: exchange credit and the new order it went to',
          exPayload['exchangeAmount'] == 120.0 &&
              exPayload['exchangeOrderCode'] == 'SANDBOX-N1',
          'exchangeAmount ${exPayload['exchangeAmount']} · exchangeOrderCode ${exPayload['exchangeOrderCode']}');

      // ── The exchange ticket, from the exact printer bytes ─────────────
      final ticketBytes = await printing.buildTicketReceiptBytes(
        ticketId: ex6.lastTicketId,
        ticketNumber: ex6.lastTicketNum,
        amount: 150,
        paymentMethod: 'CASH',
        createdAt: DateTime.now(),
        items: const [
          {'name': 'T-shirt L', 'quantity': 1, 'price': 150.0, 'components': []},
        ],
        orderType: 'TAKEAWAY',
        orderCode: 'SANDBOX-N1',
        storeName: 'SANDBOX',
        exchange: ExchangeReceipt(
          originalOrderCode: orderC.code,
          refundCode: ex6.refund.code,
          returned: draft6.lines,
          credit: draft6.credit,
          settlement: ex6.settlement,
          differenceMethod: 'CASH',
        ),
      );
      final ticketText = escPosToText(ticketBytes);
      check(
          'Exchange ticket shows the returned AND the new goods',
          ticketText.contains('T-shirt M') &&
              ticketText.contains('T-shirt L') &&
              ticketText.contains(ex6.refund.code) &&
              RegExp(r'-120[.,]00').hasMatch(ticketText) &&
              RegExp(r'30[.,]00').hasMatch(ticketText),
          '${ticketText.split('\n').length} lines');

      // ── The X, from the exact printer bytes ────────────────────────────
      final report = await DailySummaryService(db).generateSessionReport(sNow);
      final bytes = await printing.buildDailySummaryReportBytes(
        report: report,
        reportType: 'X',
        businessName: 'SANDBOX',
      );
      final x = escPosToText(bytes);
      check('X report printed with the refunds section',
          x.isNotEmpty && RegExp(r'430[.,]00').hasMatch(x),
          '${x.split('\n').length} lines');
      // The paper's expected cash must agree with the till's drawer figure
      // (it used to leave cash refunds out). Matched on the figures, not the
      // label, so it holds in every printing language.
      final expectedLine = x.split('\n').firstWhere(
          (l) => RegExp(r'(245|395)[.,]00').hasMatch(l),
          orElse: () => '');
      check('X: expected cash on paper = 245.00 (matches the drawer)',
          RegExp(r'245[.,]00').hasMatch(expectedLine),
          expectedLine.trim().isEmpty ? 'line not found' : expectedLine.trim());
      return SandboxResult(checks, x, ticketText);
    } catch (e, st) {
      check('Sandbox crashed', false, '$e\n$st');
      return SandboxResult(checks, '');
    } finally {
      await db.close();
    }
  }
}

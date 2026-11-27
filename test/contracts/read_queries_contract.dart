import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/services/floor_queries.dart';
import 'package:caisse212/domain/services/kds_stats_queries.dart';
import 'package:caisse212/domain/services/order_queries.dart';
import 'package:caisse212/domain/services/report_queries.dart';
import 'package:caisse212/domain/services/session_queries.dart';
import 'package:caisse212/domain/services/ticket_queries.dart';
import 'package:caisse212/domain/services/unpaid_queries.dart';
import 'package:caisse212/domain/services/z_queries.dart';

/// What the read interfaces must answer, whoever implements them: the local
/// repositories run these on the till's database, a hub-backed till will run
/// them against the hub with its own harness. The seeding is in business
/// terms so a hub harness can do it through the hub's own API.
abstract class ReadHarness {
  OrderQueries get orders;
  TicketQueries get tickets;
  SessionQueries get sessions;
  ZQueries get zs;
  UnpaidQueries get unpaid;
  FloorQueries get floor;
  ReportQueries get reports;
  KdsStatsQueries get kdsStats;

  Future<int> z({bool open = true});
  Future<int> session(
      {int cashierId = 1, String status = 'active', int? zId});
  Future<int> product(String name, double price);
  Future<int> order(String code,
      {int? sessionId, int? tableId, int? waiterId, double discountPercent = 0});
  Future<int> line(int orderId,
      {required int productId,
      required double price,
      double quantity = 1,
      String state = 'PENDING',
      int? ticketId});
  Future<int> ticket(int orderId,
      {required double amount,
      String method = 'CASH',
      int? sessionId,
      bool paid = true});
  Future<int> area(String name);
  Future<int> table(String name, {int? areaId, int? orderId});
  Future<int> waiter(String name, {List<int> areas = const []});

  Future<void> dispose();
}

void readQueriesContract(String name, Future<ReadHarness> Function() make) {
  late ReadHarness h;

  setUp(() async => h = await make());
  tearDown(() => h.dispose());

  group('$name honours OrderQueries', () {
    test('an order is found by id and by code, with its lines', () async {
      final p = await h.product('Tea', 10);
      final o = await h.order('A-1');
      await h.line(o, productId: p, price: 10, quantity: 2);
      await h.line(o, productId: p, price: 10);

      expect((await h.orders.getOrderRow(o))?.code, 'A-1');
      expect((await h.orders.findOrderRowByCode('A-1'))?.id, o);
      final cart = (await h.orders.getOrderById(o))!;
      expect(cart.items.map((i) => i.quantity), unorderedEquals([2, 1]));
      expect(await h.orders.linesOfOrder(o), hasLength(2));
      expect(await h.orders.linesForOrders([o]), hasLength(2));
      expect(await h.orders.findOrderRowByCode('nope'), isNull);
    });

    test('a total counts what is owed, less the order discount', () async {
      final p = await h.product('Tea', 10);
      final o = await h.order('A-2', discountPercent: 10);
      await h.line(o, productId: p, price: 10, quantity: 2);
      await h.line(o, productId: p, price: 5);
      await h.line(o, productId: p, price: 100, state: 'CANCELED');

      expect(await h.orders.getOrderTotals([o]), {o: closeTo(22.5, 1e-9)});
    });

    test('the resume list holds what is still owed, not what is paid',
        () async {
      final p = await h.product('Tea', 10);
      final owed = await h.order('A-3');
      await h.line(owed, productId: p, price: 10);
      final paid = await h.order('A-4');
      final t = await h.ticket(paid, amount: 10);
      await h.line(paid, productId: p, price: 10, ticketId: t);

      final ids = (await h.orders.getUnpaidOrdersForResume()).map((o) => o.id);
      expect(ids, contains(owed));
      expect(ids, isNot(contains(paid)));
    });

    test('an order row is watched as it is', () async {
      final o = await h.order('A-5');
      expect((await h.orders.watchOrderRow(o).first)?.code, 'A-5');
    });
  });

  group('$name honours TicketQueries', () {
    test('an order’s tickets, a ticket and the lines it paid', () async {
      final p = await h.product('Tea', 10);
      final o = await h.order('T-1');
      final t1 = await h.ticket(o, amount: 10);
      final t2 = await h.ticket(o, amount: 5, paid: false);
      await h.line(o, productId: p, price: 10, ticketId: t1);

      expect((await h.tickets.getTicketsByOrderId(o)).map((t) => t.id),
          unorderedEquals([t1, t2]));
      expect((await h.tickets.getTicketById(t1))?.amount, 10);
      expect(await h.tickets.linesOfTicket(t1), hasLength(1));
      expect((await h.tickets.paidTicketsForOrders([o])).map((t) => t.id),
          [t1]);
    });
  });

  group('$name honours SessionQueries', () {
    test('a paused session is the cashier’s, not the one taking money',
        () async {
      final paused = await h.session(cashierId: 1, status: 'paused');
      final active = await h.session(cashierId: 2);
      await h.session(cashierId: 3, status: 'ended');

      expect((await h.sessions.getActiveSession(1))?.id, paused);
      expect((await h.sessions.getActiveSession(3)), isNull);
      expect((await h.sessions.activeSessionOnTill())?.id, active);
      expect((await h.sessions.openSessionsOnTill()).map((s) => s.id),
          unorderedEquals([paused, active]));
      expect((await h.sessions.getSessionsByIds([active])).single.id, active);
      expect((await h.sessions.getSessionById(paused))?.status, 'paused');
    });
  });

  group('$name honours ZQueries', () {
    test('the open Z and its sessions, open ones apart', () async {
      final z = await h.z();
      final a = await h.session(zId: z);
      final b = await h.session(zId: z, cashierId: 2);
      final ended = await h.session(zId: z, cashierId: 3, status: 'ended');

      expect((await h.zs.getOpenZ())?.id, z);
      expect((await h.zs.watchOpenZ().first)?.id, z);
      expect((await h.zs.getById(z))?.status, 'open');
      expect((await h.zs.sessionsForZ(z)).map((s) => s.id),
          unorderedEquals([a, b, ended]));
      expect((await h.zs.openSessionsOf(z, except: a)).map((s) => s.id), [b]);
    });

    test('no Z open, none to show', () async {
      await h.z(open: false);
      expect(await h.zs.getOpenZ(), isNull);
    });
  });

  group('$name honours UnpaidQueries', () {
    test('what the floor still owes, part-payments counted', () async {
      final p = await h.product('Tea', 10);
      final t1 = await h.table('T1');
      final seated = await h.order('U-1', tableId: t1);
      await h.table('T1b', orderId: seated);
      await h.line(seated, productId: p, price: 10, quantity: 3);
      await h.ticket(seated, amount: 10);
      final parked = await h.order('U-2');
      await h.line(parked, productId: p, price: 5);
      final settled = await h.order('U-3');
      final t = await h.ticket(settled, amount: 10);
      await h.line(settled, productId: p, price: 10, ticketId: t);

      final all = await h.unpaid.summary();
      expect(all.entries.map((e) => e.order.id),
          unorderedEquals([seated, parked]));
      expect(all.totalValue, closeTo(35, 1e-9));
      expect(all.totalPaid, closeTo(10, 1e-9));
      expect(all.totalDue, closeTo(25, 1e-9));

      final tables = await h.unpaid.summary(tablesOnly: true);
      expect(tables.entries.map((e) => e.order.id), [seated]);
      expect((await h.unpaid.watchSummary().first).count, 2);
    });
  });

  group('$name honours FloorQueries', () {
    test('an area is served by its waiters and by those with no area',
        () async {
      final terrace = await h.area('Terrace');
      final hall = await h.area('Hall');
      final ali = await h.waiter('Ali', areas: [terrace]);
      final sara = await h.waiter('Sara');
      final omar = await h.waiter('Omar', areas: [hall]);

      expect((await h.floor.waitersForArea(terrace)).map((w) => w.id),
          unorderedEquals([ali, sara]));
      expect((await h.floor.waitersForArea(null)).map((w) => w.id),
          unorderedEquals([ali, sara, omar]));
      expect(await h.floor.areasOfWaiter(omar), [hall]);
      expect((await h.floor.watchAreas().first).map((a) => a.id),
          unorderedEquals([terrace, hall]));
    });

    test('a waiter’s open orders and what is left to collect', () async {
      final p = await h.product('Tea', 10);
      final ali = await h.waiter('Ali');
      final o = await h.order('W-1', waiterId: ali);
      await h.line(o, productId: p, price: 10, quantity: 2);
      await h.ticket(o, amount: 5);

      final stats = await h.floor.waiterStats(ali);
      expect(stats['totalOrders'], 1);
      expect(stats['unpaidTotal'] as double, closeTo(15, 1e-9));
    });
  });

  group('$name honours ReportQueries', () {
    test('a session report sums its tickets by method', () async {
      final p = await h.product('Tea', 10);
      final s = await h.session();
      final o = await h.order('R-1', sessionId: s);
      final cash = await h.ticket(o, amount: 20, sessionId: s);
      final card =
          await h.ticket(o, amount: 15, method: 'CARD', sessionId: s);
      await h.line(o, productId: p, price: 20, ticketId: cash);
      await h.line(o, productId: p, price: 15, ticketId: card);

      final report = await h.reports.generateSessionReport(s);
      expect(report.totalPaidByCash, closeTo(20, 1e-9));
      expect(report.totalPaidByCard, closeTo(15, 1e-9));
      expect(report.totalTickets, 2);
      expect(report.sessions.single.sessionId, s);
    });
  });

  group('$name honours KdsStatsQueries', () {
    test('a session with nothing cooked reports nothing', () async {
      final s = await h.session();
      final stats = await h.kdsStats.forSession(s);
      expect(stats.itemsServed, 0);
      expect(stats.liveBacklog, 0);
      expect(stats.avgPrepTime, isNull);
    });
  });
}

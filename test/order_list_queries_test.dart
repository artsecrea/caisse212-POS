import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/order_provider.dart';

/// The orders screen and the resume picker filter, count and page in SQL.
/// These pin that SQL to the Dart formulas it replaced: [getOrderTotals]
/// against paid tickets for "unpaid", and the row builder's money.

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late OrderRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    repo = OrderRepository(db, container.read(_refProvider));
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  var seq = 0;
  Future<int> order({
    String status = 'COMPLETED',
    double pct = 0,
    String? tags,
    int? clientId,
    int? takenBy,
    int? sessionId,
    String? code,
    DateTime? at,
  }) =>
      db.into(db.orders).insert(OrdersCompanion.insert(
            code: code ?? 'ORD${++seq}',
            status: Value(status),
            discountPercentage: Value(pct),
            tagIds: Value(tags),
            clientId: Value(clientId),
            takenBy: Value(takenBy),
            sessionId: Value(sessionId),
            createdAt: Value(at ?? DateTime(2026, 10, 1).add(Duration(minutes: seq))),
            isSynced: const Value(false),
          ));

  Future<int> line(int orderId, double price,
          {double qty = 1, double manual = 0, int? ticketId}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            quantity: Value(qty),
            unitaryPrice: price,
            manualDiscount: Value(manual),
            ticketId: Value(ticketId),
          ));

  Future<void> comp(int lineId, double price, {int qty = 1}) =>
      db.into(db.orderProductComponents).insert(
          OrderProductComponentsCompanion.insert(
              componentId: 1,
              orderProductId: lineId,
              price: Value(price),
              quantity: Value(qty)));

  Future<int> ticket(int orderId, double amount,
          {bool paid = true, bool cancelled = false}) =>
      db.into(db.tickets).insert(TicketsCompanion.insert(
            num: 'T${++seq}',
            orderId: orderId,
            paymentMethod: 'CASH',
            amount: amount,
            isPaid: Value(paid),
            isCancelled: Value(cancelled),
          ));

  /// The rule the SQL replaced, computed the old way.
  Future<Set<int>> unpaidTheDartWay() async {
    final orders = await db.select(db.orders).get();
    final totals = await repo.getOrderTotals([for (final o in orders) o.id]);
    final out = <int>{};
    for (final o in orders) {
      if (o.status == 'CANCELED') continue;
      final total = totals[o.id] ?? 0;
      if (total <= 0) continue;
      final paid = (await (db.select(db.tickets)
                ..where((t) =>
                    t.orderId.equals(o.id) &
                    t.isPaid.equals(true) &
                    t.isCancelled.equals(false)))
              .get())
          .fold<double>(0, (s, t) => s + t.amount);
      if (paid + 0.005 < total) out.add(o.id);
    }
    return out;
  }

  /// Returns the orders that are unpaid by construction.
  Future<Set<int>> seedMixedBook() async {
    // Unpaid, with components, a manual discount and an order discount.
    final a = await order(pct: 10);
    final la = await line(a, 30, qty: 2, manual: 2);
    await comp(la, 5, qty: 2);
    // Paid in full, in two tickets.
    final b = await order();
    await line(b, 40);
    await ticket(b, 25);
    await ticket(b, 15);
    // Paid a cent short of the epsilon — counts as paid.
    final c = await order();
    await line(c, 10);
    await ticket(c, 9.996);
    // Partly paid.
    final d = await order();
    await line(d, 50);
    await ticket(d, 20);
    // Its only ticket is cancelled / not paid.
    final e = await order();
    await line(e, 12);
    await ticket(e, 12, cancelled: true);
    await ticket(e, 12, paid: false);
    // CANCELED, empty, and fully discounted orders are never unpaid.
    final f = await order(status: 'CANCELED');
    await line(f, 99);
    await order();
    final h = await order(pct: 100);
    await line(h, 20);
    // ONHOLD with a line and nothing paid.
    final i = await order(status: 'ONHOLD');
    await line(i, 7.5, qty: 3);
    return {a, d, e, i};
  }

  test('orders screen and resume picker list exactly the unpaid orders',
      () async {
    final expected = await seedMixedBook();
    expect(await unpaidTheDartWay(), expected);

    final page = await repo.getPaginatedOrdersWithFullDetails(
        page: 0, pageSize: 100, unpaidOnly: true);
    expect({for (final o in page.orders) o.order.id}, expected);
    expect(page.totalCount, expected.length);

    final resume = await repo.getUnpaidOrdersForResume();
    expect({for (final o in resume) o.id}, expected);
  });

  test('pages are counted and sliced by the database, newest first', () async {
    for (var n = 0; n < 25; n++) {
      await line(await order(), 10);
    }
    final p0 = await repo.getPaginatedOrdersWithFullDetails(
        page: 0, pageSize: 10);
    final p2 = await repo.getPaginatedOrdersWithFullDetails(
        page: 2, pageSize: 10);
    expect(p0.totalCount, 25);
    expect(p0.totalPages, 3);
    expect(p0.orders, hasLength(10));
    expect(p2.orders, hasLength(5));

    final all = <int>[];
    for (var p = 0; p < 3; p++) {
      all.addAll((await repo.getPaginatedOrdersWithFullDetails(
              page: p, pageSize: 10))
          .orders
          .map((o) => o.order.id));
    }
    final byDate = await (db.select(db.orders)
          ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]))
        .map((o) => o.id)
        .get();
    expect(all, byDate);
  });

  test('a tag filter matches whole ids in the comma list', () async {
    final one = await order(tags: '1,12');
    final twelve = await order(tags: '12');
    final none = await order();
    await order(tags: '2');

    Future<Set<int>> ids({Set<int> tags = const {}, bool untagged = false}) async =>
        {
          for (final o in (await repo.getPaginatedOrdersWithFullDetails(
                  page: 0, pageSize: 50, tagIds: tags, untagged: untagged))
              .orders)
            o.order.id
        };
    expect(await ids(tags: {1}), {one});
    expect(await ids(tags: {12}), {one, twelve});
    expect(await ids(untagged: true), {none});
    expect(await ids(tags: {1}, untagged: true), {one, none});
  });

  test('search matches code, cashier and customer label; % is literal',
      () async {
    await db.into(db.customers).insert(CustomersCompanion.insert(
        id: const Value(7), firstName: const Value('Salma'), lastName: const Value('Idrissi')));
    await db.into(db.customers).insert(CustomersCompanion.insert(
        id: const Value(8), phone: const Value('0611223344')));
    await db.into(db.users).insert(UsersCompanion.insert(
        id: const Value(3),
        username: 'karim',
        password: 'x',
        firstName: 'K',
        lastName: '',
        type: 'CASHIER'));
    final byCode = await order(code: 'TAB-0042');
    final byCustomer = await order(clientId: 7);
    final byPhoneLabel = await order(clientId: 8);
    final byCashier = await order(takenBy: 3);

    Future<Set<int>> search(String q) async => {
          for (final o in (await repo.getPaginatedOrdersWithFullDetails(
                  page: 0, pageSize: 50, searchQuery: q))
              .orders)
            o.order.id
        };
    expect(await search('tab-00'), {byCode});
    expect(await search('IDRISSI'), {byCustomer});
    expect(await search('112233'), {byPhoneLabel});
    expect(await search('kar'), {byCashier});
    expect(await search('%'), isEmpty);
  });

  test('a page row carries the same money as the single-order view',
      () async {
    final a = await order(pct: 10);
    final la = await line(a, 30, qty: 2, manual: 2);
    await comp(la, 5, qty: 2);
    final t = await ticket(a, 20);
    await line(a, 20, ticketId: t);
    final b = await order();
    await line(b, 9);

    final page = await repo.getPaginatedOrdersWithFullDetails(
        page: 0, pageSize: 10);
    for (final row in page.orders) {
      final single = await repo.getOrderFullDetails(row.order.id);
      expect(row.total, closeTo(single.total, 1e-9));
      expect(row.totalPaid, single.totalPaid);
      expect(row.items.length, single.items.length);
      expect(row.items.map((i) => i.totalPrice),
          single.items.map((i) => i.totalPrice));
    }
    final rowA = page.orders.firstWhere((o) => o.order.id == a);
    expect(rowA.total, closeTo((await repo.getOrderTotals([a]))[a]!, 1e-9));
    expect(rowA.totalPaid, 20);
  });
}

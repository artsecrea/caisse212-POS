import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/order_provider.dart';

/// Ownership follows the work: whoever pays or modifies an unpaid order
/// becomes its owner, so a shift change needs no separate handover step. These
/// pin the claim itself — when it fires, when it declines to, and the two
/// fields it must never move.

/// Exposes a real `Ref` to the test, which `OrderRepository` requires and a
/// `ProviderContainer` is not.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late OrderRepository repo;

  Future<void> boot({CurrentUser? user, CashSession? session}) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    if (user != null) {
      container.read(currentUserProvider.notifier).state = user;
    }
    if (session != null) {
      container.read(currentSessionProvider.notifier).state = session;
    }
    // The repository wants a Ref, which only a provider can hand out.
    repo = OrderRepository(db, container.read(_refProvider));
  }

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() {
    container.dispose();
    return db.close();
  });

  CurrentUser cashier(int id) => CurrentUser(
        id,
        'u$id',
        'x',
        'User$id',
        '',
        'cashier',
        null,
        null,
        null,
        '',
        DateTime(2026),
        DateTime(2026),
        null,
      );

  Future<CashSession> session(int id, {DateTime? startedAt}) async {
    await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
          id: Value(id),
          code: 'S$id',
          cashierId: 1,
          moneyAtStart: 0,
          startedAt: Value(startedAt ?? DateTime.now()),
        ));
    return (db.select(db.cashSessions)..where((s) => s.id.equals(id)))
        .getSingle();
  }

  Future<int> order({
    int? takenBy,
    int? sessionId,
    DateTime? zDay,
    int? waiterId,
    String? source,
    bool synced = true,
  }) async {
    final id = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'ORD1',
          takenBy: Value(takenBy),
          sessionId: Value(sessionId),
          zDay: Value(zDay),
          waiterId: Value(waiterId),
          source: Value(source),
          isSynced: Value(synced),
        ));
    return id;
  }

  Future<Order> read(int id) =>
      (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();

  group('when it fires', () {
    test("another cashier's order becomes the one at the till's", () async {
      await boot(user: cashier(2));
      final id = await order(takenBy: 1);

      expect(await repo.claimOrderForCurrentUser(id), isTrue);
      expect((await read(id)).takenBy, 2);
    });

    test('an order nobody owned gets an owner', () async {
      await boot(user: cashier(2));
      final id = await order();
      await repo.claimOrderForCurrentUser(id);
      expect((await read(id)).takenBy, 2);
    });

    test('the session moves with it, so the money is counted here', () async {
      final s = await session(10);
      await boot(user: cashier(2), session: s);
      final id = await order(takenBy: 1, sessionId: 9);

      await repo.claimOrderForCurrentUser(id);
      final row = await read(id);
      expect(row.takenBy, 2);
      expect(row.sessionId, 10);
    });

    test('the claim has to reach the backend', () async {
      await boot(user: cashier(2));
      final id = await order(takenBy: 1, synced: true);
      await repo.claimOrderForCurrentUser(id);
      expect((await read(id)).isSynced, isFalse);
    });

    test('the z-day moves with the session, so both reports agree', () async {
      // The X / Z print scopes by sessionId; generateZDayReport scopes by
      // date. Moving one without the other put this order in the new shift's
      // Z and the old shift's day at once.
      final s = await session(10, startedAt: DateTime(2026, 3, 14, 9));
      await boot(user: cashier(2), session: s);
      final id = await order(
          takenBy: 1, sessionId: 9, zDay: DateTime(2026, 3, 13));

      await repo.claimOrderForCurrentUser(id);
      final row = await read(id);
      expect(row.sessionId, 10);
      expect(row.zDay, DateTime(2026, 3, 14),
          reason: "the receiving session's day, not the order's old one");
    });

    test('a session opened before midnight keeps its own day', () async {
      // Read from the session, not the clock: a shift that opened at 23:00
      // still belongs to the 14th when an order is claimed into it at 01:00.
      final s = await session(10, startedAt: DateTime(2026, 3, 14, 23));
      await boot(user: cashier(2), session: s);
      final id = await order(
          takenBy: 1, sessionId: 9, zDay: DateTime(2026, 3, 1));

      await repo.claimOrderForCurrentUser(id);
      expect((await read(id)).zDay, DateTime(2026, 3, 14));
    });

    test('an order already theirs still moves to their open session', () async {
      // Same cashier, new shift: the order is theirs but its session is last
      // night's, which is exactly the case that used to strand it.
      final s = await session(10);
      await boot(user: cashier(2), session: s);
      final id = await order(takenBy: 2, sessionId: 9);

      expect(await repo.claimOrderForCurrentUser(id), isTrue);
      expect((await read(id)).sessionId, 10);
    });
  });

  group('when it declines', () {
    test('already theirs, same session — nothing to write', () async {
      final s = await session(10);
      await boot(user: cashier(2), session: s);
      final id = await order(takenBy: 2, sessionId: 10, synced: true);

      expect(await repo.claimOrderForCurrentUser(id), isFalse);
      expect((await read(id)).isSynced, isTrue,
          reason: 'a no-op claim must not spuriously queue a sync');
    });

    test('nobody logged in', () async {
      await boot();
      final id = await order(takenBy: 1);
      expect(await repo.claimOrderForCurrentUser(id), isFalse);
      expect((await read(id)).takenBy, 1);
    });

    test('the order is gone — a payment must not fail on this', () async {
      await boot(user: cashier(2));
      expect(await repo.claimOrderForCurrentUser(9999), isFalse);
    });

    test('no open session leaves the session stamp alone', () async {
      await boot(user: cashier(2));
      final id = await order(takenBy: 1, sessionId: 9);

      await repo.claimOrderForCurrentUser(id);
      final row = await read(id);
      expect(row.takenBy, 2, reason: 'ownership still moves');
      expect(row.sessionId, 9,
          reason: 'and follows when they open one and it is next paid');
    });
  });

  group('what it must never move', () {
    test('the waiter who served it', () async {
      await boot(user: cashier(2));
      final id = await order(takenBy: 1, waiterId: 7);
      await repo.claimOrderForCurrentUser(id);
      expect((await read(id)).waiterId, 7);
    });

    test('the source, so the waiter edit lock keeps applying', () async {
      await boot(user: cashier(2));
      final id = await order(takenBy: 1, source: 'WAITER');
      await repo.claimOrderForCurrentUser(id);
      expect((await read(id)).source, 'WAITER');
    });
  });

  group('modifying an order claims it', () {
    test('updateOrder hands the order to whoever edited it', () async {
      await boot(user: cashier(2));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(1),
            name: 'P',
            price: 10,
            finalPrice: 10,
          ));
      final id = await order(takenBy: 1);
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: id,
            productId: 1,
            quantity: const Value(1),
            unitaryPrice: 10,
          ));

      final loaded = (await repo.getOrderById(id))!;
      await repo.updateOrder(loaded, queueSyncOperation: false);

      expect((await read(id)).takenBy, 2);
    });
  });

  group('an order inherited from a closed shift can still be worked', () {
    /// The guard used to throw outright: "cannot modify an order from a
    /// closed Z-report session". Correct as bookkeeping, useless as
    /// behaviour — the order is a real table with real people at it, and the
    /// cashier who inherited it could not touch it at all.
    Future<int> closedSessionOrder() async {
      await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            id: const Value(9),
            code: 'S9',
            cashierId: 1,
            moneyAtStart: 0,
            status: const Value('ended'),
          ));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(1),
            name: 'P',
            price: 10,
            finalPrice: 10,
          ));
      final id = await order(takenBy: 1, sessionId: 9);
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: id,
            productId: 1,
            quantity: const Value(1),
            unitaryPrice: 10,
          ));
      return id;
    }

    test('it moves onto the open session instead of being refused', () async {
      final s = await session(10);
      await boot(user: cashier(2), session: s);
      final id = await closedSessionOrder();

      final loaded = (await repo.getOrderById(id))!;
      await repo.updateOrder(loaded, queueSyncOperation: false);

      final row = await read(id);
      expect(row.sessionId, 10, reason: 'the shift now collecting it');
      expect(row.takenBy, 2);
    });

    test('its lines are stamped with the new z-day, not the reported one',
        () async {
      final s = await session(10);
      await boot(user: cashier(2), session: s);
      final id = await closedSessionOrder();
      await (db.update(db.orders)..where((o) => o.id.equals(id)))
          .write(OrdersCompanion(zDay: Value(DateTime(2020, 1, 1))));

      final loaded = (await repo.getOrderById(id))!;
      await repo.updateOrder(loaded, queueSyncOperation: false);

      final lines = await (db.select(db.orderProducts)
            ..where((p) => p.orderId.equals(id)))
          .get();
      expect(lines.single.zDay, isNot(DateTime(2020, 1, 1)),
          reason: 'the money arrives now, not on a day already reported');
      expect((await read(id)).zDay, isNot(DateTime(2020, 1, 1)));
    });

    test('with no session open there is nowhere to move it, so it still '
        'refuses', () async {
      // Honest: there is no shift to account the change to.
      await boot(user: cashier(2));
      final id = await closedSessionOrder();
      final loaded = (await repo.getOrderById(id))!;

      expect(
        () => repo.updateOrder(loaded, queueSyncOperation: false),
        throwsA(isA<Exception>()),
      );
    });

    test('a status change re-homes it too', () async {
      final s = await session(10);
      await boot(user: cashier(2), session: s);
      final id = await closedSessionOrder();

      await repo.updateOrderStatus(id, 'PREPARING', queueSyncOperation: false);
      expect((await read(id)).sessionId, 10);
    });

    test('a live-session claim moves the day onto the receiving session',
        () async {
      final s = await session(10);
      await boot(user: cashier(2), session: s);
      await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            id: const Value(11),
            code: 'S11',
            cashierId: 1,
            moneyAtStart: 0,
          ));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(1),
            name: 'P',
            price: 10,
            finalPrice: 10,
          ));
      final id = await order(takenBy: 1, sessionId: 11);
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: id,
            productId: 1,
            quantity: const Value(1),
            unitaryPrice: 10,
          ));
      await (db.update(db.orders)..where((o) => o.id.equals(id)))
          .write(OrdersCompanion(zDay: Value(DateTime(2020, 1, 1))));

      final loaded = (await repo.getOrderById(id))!;
      await repo.updateOrder(loaded, queueSyncOperation: false);

      // CHANGED RULE. This used to assert the z-day was left alone unless the
      // old shift had been CLOSED, which let an order sit in one session while
      // carrying another's day — the X / Z print (scoped by sessionId) and
      // generateZDayReport (scoped by date) then disagreed about which day its
      // money belonged to.
      //
      // The original worry was rewriting the day off the CLOCK, which would
      // shunt an order into tomorrow whenever a claim happened after midnight.
      // That is still not done: the day is read from the session being moved
      // into, via `_zDayForSessionId`, so it follows the shift and not the
      // time of day. See 'a session opened before midnight keeps its own day'.
      final row = await read(id);
      expect(row.sessionId, 10);
      expect(row.zDay, isNot(DateTime(2020, 1, 1)),
          reason: "the day follows the session the order moved into");
      expect(row.zDay, (await read(id)).zDay);
    });
  });

  group('a junk course in the column reads as untagged', () {
    /// Normalisation runs on the way OUT of the database as well as on the
    /// way in over the wire — a hand-edited row, or one written by a build
    /// that knew about a fourth course, must not hand the rest of the app a
    /// value it has to remember to ignore.
    Future<int?> readBackCourse(int stored) async {
      await boot(user: cashier(2));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(1),
            name: 'P',
            price: 10,
            finalPrice: 10,
          ));
      final id = await order(takenBy: 1);
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: id,
            productId: 1,
            quantity: const Value(1),
            unitaryPrice: 10,
            courseNo: Value(stored),
          ));
      return (await repo.getOrderById(id))!.items.single.courseNo;
    }

    test('a real course survives', () async {
      expect(await readBackCourse(2), 2);
    });

    test('an out-of-range number comes back as no course', () async {
      expect(await readBackCourse(9), isNull);
    });

    test('zero comes back as no course', () async {
      expect(await readBackCourse(0), isNull);
    });
  });

  group('what the kitchen has been told is kept honest', () {
    /// `kdsPrintedQuantity` is what the kitchen was asked to cook. When a line
    /// is cut below it, the surplus is cancelled — and the counter has to come
    /// down with it, or the delta bookkeeping goes on believing food was
    /// requested that has since been voided.
    Future<OrderProduct> lineAfterUpdate({
      required double sent,
      required double newQuantity,
    }) async {
      await boot(user: cashier(2));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(1),
            name: 'Steak',
            price: 10,
            finalPrice: 10,
          ));
      final id = await order(takenBy: 1);
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: id,
            productId: 1,
            quantity: Value(sent),
            unitaryPrice: 10,
            kdsPrintedQuantity: Value(sent),
          ));

      final loaded = (await repo.getOrderById(id))!;
      await repo.updateOrder(
        loaded.copyWith(items: [
          loaded.items.single.copyWith(quantity: newQuantity),
        ]),
        queueSyncOperation: false,
      );
      return (await (db.select(db.orderProducts)
                ..where((p) => p.orderId.equals(id)))
              .get())
          .single;
    }

    test('cutting 3 to 1 brings the sent counter down to 1', () async {
      final line = await lineAfterUpdate(sent: 3, newQuantity: 1);
      expect(line.quantity, 1);
      expect(line.kdsPrintedQuantity, 1,
          reason: 'two were voided, so only one is still asked for');
    });

    test('raising it back afterwards sends the difference again', () async {
      // The bug this prevents: cut 3 to 1, put it back to 3, and a stale
      // counter of 3 means the kitchen is told nothing — the customer waits
      // for food nobody is making.
      await boot(user: cashier(2));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(1),
            name: 'Steak',
            price: 10,
            finalPrice: 10,
          ));
      final id = await order(takenBy: 1);
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: id,
            productId: 1,
            quantity: const Value(3),
            unitaryPrice: 10,
            kdsPrintedQuantity: const Value(3),
          ));

      var loaded = (await repo.getOrderById(id))!;
      await repo.updateOrder(
        loaded.copyWith(items: [loaded.items.single.copyWith(quantity: 1)]),
        queueSyncOperation: false,
      );
      loaded = (await repo.getOrderById(id))!;
      await repo.updateOrder(
        loaded.copyWith(items: [loaded.items.single.copyWith(quantity: 3)]),
        queueSyncOperation: false,
      );

      final line = (await (db.select(db.orderProducts)
                ..where((p) => p.orderId.equals(id)))
              .get())
          .single;
      expect(line.quantity, 3);
      expect(line.kdsPrintedQuantity, 1,
          reason: 'two units are owed to the kitchen and will be sent');
    });

    test('a line that only grew is left alone', () async {
      final line = await lineAfterUpdate(sent: 2, newQuantity: 5);
      expect(line.kdsPrintedQuantity, 2,
          reason: 'nothing was cancelled, so nothing is clamped');
    });

    test('a line never sent is untouched', () async {
      await boot(user: cashier(2));
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: const Value(1),
            name: 'Steak',
            price: 10,
            finalPrice: 10,
          ));
      final id = await order(takenBy: 1);
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: id,
            productId: 1,
            quantity: const Value(3),
            unitaryPrice: 10,
          ));

      final loaded = (await repo.getOrderById(id))!;
      await repo.updateOrder(
        loaded.copyWith(items: [loaded.items.single.copyWith(quantity: 1)]),
        queueSyncOperation: false,
      );
      final line = (await (db.select(db.orderProducts)
                ..where((p) => p.orderId.equals(id)))
              .get())
          .single;
      expect(line.kdsPrintedQuantity, 0);
    });
  });
}

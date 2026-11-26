import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';

/// [OrderRepository.deletePaidLine] is the order panel's paid-line delete
/// moved out of the widget. These pin its exact behaviour, the quirks the
/// panel always had included: no cascade to components, and a ticket amount
/// rewritten without marking the ticket unsynced.
void main() {
  late AppDatabase db;
  late OrderRepository repo;
  late _RecordingApi api;
  final stamp = DateTime(2026, 1, 1);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    api = _RecordingApi(prefs);
    repo = OrderRepository(db)
      // The callback must not matter: the caller's isOnline decides.
      ..setSyncService(DataSyncService(db, api, prefs), () => true);
  });
  tearDown(() => db.close());

  Future<int> order() => db.into(db.orders).insert(OrdersCompanion.insert(
        code: 'ORD1',
        isSynced: const Value(true),
        updatedAt: Value(stamp),
      ));

  Future<int> ticket(int orderId, {bool synced = true}) =>
      db.into(db.tickets).insert(TicketsCompanion.insert(
            num: '0007',
            orderId: orderId,
            paymentMethod: 'CASH',
            amount: 50,
            isPaid: const Value(true),
            isSynced: Value(synced),
            updatedAt: Value(stamp),
          ));

  Future<int> line(int orderId, int ticketId, double price, double qty) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: 1,
            unitaryPrice: price,
            quantity: Value(qty),
            ticketId: Value(ticketId),
          ));

  Future<void> component(int lineId) => db
      .into(db.orderProductComponents)
      .insert(OrderProductComponentsCompanion.insert(
          orderProductId: lineId, componentId: 1));

  Future<Ticket?> ticketRow(int id) =>
      (db.select(db.tickets)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<OrderProductComponent>> componentsOf(int lineId) =>
      (db.select(db.orderProductComponents)
            ..where((c) => c.orderProductId.equals(lineId)))
          .get();

  Future<List<PendingSyncOperation>> pending() =>
      db.select(db.pendingSyncOperations).get();

  group('a ticket holding other lines', () {
    late int o, t, gone, kept;

    setUp(() async {
      o = await order();
      t = await ticket(o);
      gone = await line(o, t, 20, 1);
      kept = await line(o, t, 15, 2);
      await component(gone);
    });

    test('keeps the ticket and rewrites its amount from what is left',
        () async {
      final ticketDeleted = await repo.deletePaidLine(
          orderProductId: gone, ticketId: t, isOnline: false);

      expect(ticketDeleted, isFalse);
      final lines = await db.select(db.orderProducts).get();
      expect([for (final l in lines) l.id], [kept]);
      final row = (await ticketRow(t))!;
      expect(row.amount, 30, reason: '15 x 2 left on the ticket');
      expect(row.isSynced, isTrue, reason: 'the write never marks it unsynced');
      expect(row.updatedAt, stamp, reason: 'nor touches updatedAt');
    });

    test("takes the deleted line's options with it", () async {
      await repo.deletePaidLine(
          orderProductId: gone, ticketId: t, isOnline: false);
      expect(await componentsOf(gone), isEmpty);
    });

    test('does not mark the order unsynced', () async {
      await repo.deletePaidLine(
          orderProductId: gone, ticketId: t, isOnline: false);
      final row = await (db.select(db.orders)..where((x) => x.id.equals(o)))
          .getSingle();
      expect(row.isSynced, isTrue);
      expect(row.updatedAt, stamp);
    });

    test('offline: queues a ticket UPDATE with the new amount', () async {
      await repo.deletePaidLine(
          orderProductId: gone, ticketId: t, isOnline: false);
      final ops = await pending();
      expect(ops, hasLength(1));
      expect(ops.single.operationType, 'UPDATE');
      expect(ops.single.entityType, 'TICKET');
      expect(ops.single.entityId, t);
      final data = jsonDecode(ops.single.updateData!) as Map<String, dynamic>;
      expect(data['amount'], 30);
      expect(data['_orderCode'], 'ORD1');
      expect(data['_ticketNum'], '0007');
      expect(api.updates, isEmpty);
    });

    test('online: pushes the new amount straight away', () async {
      await repo.deletePaidLine(
          orderProductId: gone, ticketId: t, isOnline: true);
      expect(api.updates, hasLength(1));
      final (code, num, data) = api.updates.single;
      expect((code, num), ('ORD1', '0007'));
      expect(data, {'amount': 30.0});
      expect(await pending(), isEmpty);
    });
  });

  test('the new amount counts options and the order percentage', () async {
    final o = await db.into(db.orders).insert(OrdersCompanion.insert(
        code: 'PCT', discountPercentage: const Value(10)));
    final t = await ticket(o);
    final gone = await line(o, t, 40, 1);
    final kept = await line(o, t, 20, 2);
    await db.into(db.orderProductComponents).insert(
        OrderProductComponentsCompanion.insert(
            orderProductId: kept, componentId: 1, price: const Value(5)));

    await repo.deletePaidLine(orderProductId: gone, ticketId: t, isOnline: false);

    // (20 + 5) x 2 = 50, less 10% = 45: what the payment screen charged.
    expect((await ticketRow(t))!.amount, closeTo(45, 1e-9));
  });

  group('the last line of its ticket', () {
    late int o, t, only;

    setUp(() async {
      o = await order();
      t = await ticket(o);
      only = await line(o, t, 20, 1);
      await component(only);
    });

    test('takes the ticket with it', () async {
      final ticketDeleted = await repo.deletePaidLine(
          orderProductId: only, ticketId: t, isOnline: false);

      expect(ticketDeleted, isTrue);
      expect(await db.select(db.orderProducts).get(), isEmpty);
      expect(await ticketRow(t), isNull);
      expect(await componentsOf(only), isEmpty,
          reason: 'the line goes with its options');
    });

    test('offline: queues a ticket DELETE', () async {
      await repo.deletePaidLine(
          orderProductId: only, ticketId: t, isOnline: false);
      final ops = await pending();
      expect(ops, hasLength(1));
      expect(ops.single.operationType, 'DELETE');
      expect(ops.single.entityType, 'TICKET');
      expect(ops.single.entityId, t);
      expect(api.deletes, isEmpty);
    });

    test('online: deletes it on the server straight away', () async {
      await repo.deletePaidLine(
          orderProductId: only, ticketId: t, isOnline: true);
      expect(api.deletes, [('ORD1', '0007')]);
      expect(await pending(), isEmpty);
    });
  });

  test('an unsynced ticket tells the server nothing', () async {
    final o = await order();
    final t = await ticket(o, synced: false);
    final a = await line(o, t, 20, 1);
    await line(o, t, 15, 1);
    final t2 = await ticket(o, synced: false);
    final b = await line(o, t2, 10, 1);

    await repo.deletePaidLine(orderProductId: a, ticketId: t, isOnline: true);
    await repo.deletePaidLine(orderProductId: b, ticketId: t2, isOnline: true);

    expect((await ticketRow(t))!.amount, 15);
    expect(await ticketRow(t2), isNull);
    expect(api.updates, isEmpty);
    expect(api.deletes, isEmpty);
    expect(await pending(), isEmpty);
  });

  test('without a sync service the local delete still happens', () async {
    final bare = OrderRepository(db);
    final o = await order();
    final t = await ticket(o);
    final a = await line(o, t, 20, 1);

    expect(
        await bare.deletePaidLine(orderProductId: a, ticketId: t, isOnline: true),
        isTrue);
    expect(await ticketRow(t), isNull);
    expect(await pending(), isEmpty);
  });
}

class _RecordingApi extends ApiService {
  _RecordingApi(super.prefs);
  final deletes = <(String, String)>[];
  final updates = <(String, String, Map<String, dynamic>)>[];

  @override
  Future<void> deleteTicket(String orderCode, String ticketNum) async {
    deletes.add((orderCode, ticketNum));
  }

  @override
  Future<void> updateTicket(String orderCode, String ticketNum,
      Map<String, dynamic> updateData) async {
    updates.add((orderCode, ticketNum, updateData));
  }
}

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/data_sync_service.dart';

/// What a pull is allowed to take off an open order: only what the server
/// explicitly says to remove.
///
/// Orders are validated on the till and the backend receives them. It is not
/// an authority that can subtract a line — but the reconciler used to INFER
/// removal from "this line is not in the snapshot", and the push times out
/// constantly in the field, so the snapshot is routinely behind what the
/// waiter already sent to the kitchen. The next pull then silently deleted
/// food that had already printed. The `deletedAt` flag the server actually
/// sends per line was never read.
///
/// Matching was positional within (productId, variantId) too. An order holding
/// two lines of the same product — routine, since the waiter app's add-product
/// route never merges — could bind a server line to the wrong row, stamp that
/// row with the other's server id, and orphan the row the id belonged to.

void main() {
  late AppDatabase db;
  late DataSyncService sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sync = DataSyncService(db, ApiService(prefs), prefs);
  });
  tearDown(() => db.close());

  Future<int> seedOrder() async {
    for (final id in [1, 2]) {
      await db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: 'P$id',
            price: 10,
            finalPrice: 10,
          ));
    }
    return db.into(db.orders).insert(OrdersCompanion.insert(code: 'ORD1'));
  }

  Future<int> line(
    int orderId, {
    int productId = 1,
    int? serverId,
    double quantity = 1,
    double kdsPrinted = 0,
    int? ticketId,
  }) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: productId,
            quantity: Value(quantity),
            unitaryPrice: 10,
            serverId: Value(serverId),
            kdsPrintedQuantity: Value(kdsPrinted),
            ticketId: Value(ticketId),
          ));

  Map<String, dynamic> delta(List<Map<String, dynamic>> products) => {
        'code': 'ORD1',
        'products': products,
      };

  Map<String, dynamic> serverLine(int id,
          {int productId = 1, double quantity = 1}) =>
      {
        'id': id,
        'productId': productId,
        'quantity': quantity,
        'price': 10.0,
      };

  Future<List<OrderProduct>> rows(int orderId) => (db.select(db.orderProducts)
        ..where((t) => t.orderId.equals(orderId))
        ..orderBy([(t) => OrderingTerm(expression: t.id)]))
      .get();

  test('a line already sent to the kitchen survives a snapshot without it',
      () async {
    final orderId = await seedOrder();
    final printedId =
        await line(orderId, productId: 2, serverId: 77, kdsPrinted: 1);
    await line(orderId, serverId: 55);

    // The server lists only the other line — the waiter's push had not landed.
    await sync.applyOrderDeltaForTesting(delta([serverLine(55)]));

    final survived = await (db.select(db.orderProducts)
          ..where((t) => t.id.equals(printedId)))
        .getSingleOrNull();
    expect(survived != null, isTrue,
        reason: 'the kitchen is cooking it; an unbilled plate is the worse '
            'error');
    expect(survived!.kdsPrintedQuantity, 1.0);
  });

  test('a paid line survives a snapshot without it', () async {
    final orderId = await seedOrder();
    final ticketId = await db.into(db.tickets).insert(
          TicketsCompanion.insert(
              orderId: orderId, num: 'T1', paymentMethod: 'CASH', amount: 10),
        );
    final paidId =
        await line(orderId, productId: 2, serverId: 77, ticketId: ticketId);
    await line(orderId, serverId: 55);

    await sync.applyOrderDeltaForTesting(delta([serverLine(55)]));

    expect(
      (await rows(orderId)).map((r) => r.id).contains(paidId),
      isTrue,
      reason: 'it is on a printed ticket and inside a reported Z',
    );
  });

  test('a line merely missing from the snapshot is kept, not inferred away',
      () async {
    final orderId = await seedOrder();
    final missingId = await line(orderId, productId: 2, serverId: 77);
    await line(orderId, serverId: 55);

    await sync.applyOrderDeltaForTesting(delta([serverLine(55)]));

    expect(
      (await rows(orderId)).map((r) => r.id).contains(missingId),
      isTrue,
      reason: 'the POS owns the order; a backend that is behind is not a '
          'backend asserting a removal',
    );
  });

  test('a line the server explicitly marks deletedAt IS removed', () async {
    final orderId = await seedOrder();
    final goneId = await line(orderId, productId: 2, serverId: 77);
    await line(orderId, serverId: 55);

    await sync.applyOrderDeltaForTesting(delta([
      serverLine(55),
      {...serverLine(77, productId: 2), 'deletedAt': '2026-09-18T12:00:00Z'},
    ]));

    expect((await rows(orderId)).map((r) => r.id).contains(goneId), isFalse,
        reason: 'an explicit statement from the server is obeyed');
  });

  test('a deleted line the till never had is not resurrected', () async {
    final orderId = await seedOrder();
    await line(orderId, serverId: 55);

    await sync.applyOrderDeltaForTesting(delta([
      serverLine(55),
      {...serverLine(77, productId: 2), 'deletedAt': '2026-09-18T12:00:00Z'},
    ]));

    expect(await rows(orderId), hasLength(1),
        reason: 'a line that arrives already deleted must not be inserted');
  });

  test('an explicit delete still cannot rewrite a paid line', () async {
    final orderId = await seedOrder();
    final ticketId = await db.into(db.tickets).insert(
          TicketsCompanion.insert(
              orderId: orderId, num: 'T1', paymentMethod: 'CASH', amount: 10),
        );
    final paidId =
        await line(orderId, productId: 2, serverId: 77, ticketId: ticketId);

    await sync.applyOrderDeltaForTesting(delta([
      {...serverLine(77, productId: 2), 'deletedAt': '2026-09-18T12:00:00Z'},
    ]));

    expect((await rows(orderId)).map((r) => r.id).contains(paidId), isTrue,
        reason: 'it is inside a Z that has already been reported');
  });

  test('a never-pushed line is left alone, as before', () async {
    final orderId = await seedOrder();
    final localOnlyId = await line(orderId, productId: 2);
    await line(orderId, serverId: 55);

    await sync.applyOrderDeltaForTesting(delta([serverLine(55)]));

    expect((await rows(orderId)).map((r) => r.id).contains(localOnlyId), isTrue,
        reason: 'no server id means the backend has never seen it');
  });

  test('two lines of one product bind to their own server ids', () async {
    final orderId = await seedOrder();
    // Same product twice — what the waiter app produces, since add-product
    // never merges into an existing line.
    final first = await line(orderId, serverId: 101, quantity: 1);
    final second = await line(orderId, serverId: 102, quantity: 1);

    // The snapshot lists them in the opposite order and with new quantities.
    await sync.applyOrderDeltaForTesting(delta([
      serverLine(102, quantity: 5),
      serverLine(101, quantity: 3),
    ]));

    final byId = {for (final r in await rows(orderId)) r.id: r};
    expect(byId, hasLength(2), reason: 'neither row is a leftover');
    expect(byId[first]!.quantity, 3.0,
        reason: 'row bound to server line 101 takes 101 quantity');
    expect(byId[second]!.quantity, 5.0);
    expect(byId[first]!.serverId, 101, reason: 'ids must not be swapped');
    expect(byId[second]!.serverId, 102);
  });

  test('a re-keyed line is re-matched, not duplicated', () async {
    final orderId = await seedOrder();
    // The kitchen has this one. Its server id is 101.
    final printed = await line(orderId, serverId: 101, kdsPrinted: 1);

    // The snapshot carries the same product under a DIFFERENT id, and never
    // mentions 101 — so the backend re-keyed the line rather than adding one.
    await sync.applyOrderDeltaForTesting(delta([serverLine(999, quantity: 4)]));

    final all = await rows(orderId);
    expect(all, hasLength(1),
        reason: 'inserting here is what put the same food on the panel twice — '
            'once under "already sent", once as though still owed');
    expect(all.single.id, printed, reason: 'it is the same row, re-keyed');
    expect(all.single.serverId, 999);
    expect(all.single.quantity, 4.0, reason: 'and it took the new quantity');
    expect(all.single.kdsPrintedQuantity, 1.0,
        reason: 'the kitchen was told about it and still has been');
  });

  test('a genuinely new server line still inserts', () async {
    final orderId = await seedOrder();
    final printed = await line(orderId, serverId: 101, kdsPrinted: 1);

    // This snapshot names BOTH: 101 is still live, 999 is a real second line.
    await sync.applyOrderDeltaForTesting(
        delta([serverLine(101), serverLine(999, quantity: 2)]));

    final byId = {for (final r in await rows(orderId)) r.id: r};
    expect(byId, hasLength(2), reason: 'two server lines, two local rows');
    expect(byId[printed]!.serverId, 101,
        reason: 'its own line claimed it — no theft');
    expect(byId[printed]!.kdsPrintedQuantity, 1.0);
    expect(byId.values.where((r) => r.serverId == 999), hasLength(1));
  });

  test('a header-only delta still removes nothing', () async {
    final orderId = await seedOrder();
    await line(orderId, serverId: 55);
    await line(orderId, productId: 2, serverId: 77);

    await sync.applyOrderDeltaForTesting({'code': 'ORD1'});

    expect(await rows(orderId), hasLength(2));
  });
}

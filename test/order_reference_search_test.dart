import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/utils/order_reference.dart';

/// The resume panel finds an open order by its #number, its code, the
/// take-away / delivery reference typed on it, or its customer; and that
/// reference survives the cart's save and reload.
void main() {
  late AppDatabase db;
  late OrderRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OrderRepository(db);
  });
  tearDown(() => db.close());

  Order row({
    String code = 'ABC123',
    int? number,
    String? reference,
  }) =>
      Order(
        id: 1,
        code: code,
        status: 'PENDING',
        type: 'TAKE_AWAY',
        priority: 0,
        persons: 1,
        date: DateTime(2026),
        sessionOrderNo: number,
        reference: reference,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isSynced: false,
        tagsSynced: true,
        discountPercentage: 0,
      );

  group('orderMatchesSearch', () {
    test('#number and bare number match the session order number exactly',
        () {
      final o = row(number: 12);
      expect(orderMatchesSearch(o, '#12'), isTrue);
      expect(orderMatchesSearch(o, '12'), isTrue);
      expect(orderMatchesSearch(o, '#1'), isFalse);
    });

    test('code and reference match on any part, any case', () {
      final o = row(code: 'RGH7IE3H3LR', reference: 'Glovo 4471 Sara');
      expect(orderMatchesSearch(o, 'ie3h'), isTrue);
      expect(orderMatchesSearch(o, 'glovo'), isTrue);
      expect(orderMatchesSearch(o, '4471'), isTrue);
      expect(orderMatchesSearch(o, 'sara'), isTrue);
      expect(orderMatchesSearch(o, 'karim'), isFalse);
    });

    test('the customer name and phone match', () async {
      final cid = await db.into(db.customers).insert(CustomersCompanion.insert(
            firstName: const Value('Karim'),
            lastName: const Value('Alaoui'),
            phone: const Value('0612345678'),
          ));
      final customer = await (db.select(db.customers)
            ..where((c) => c.id.equals(cid)))
          .getSingle();
      final o = row();
      expect(orderMatchesSearch(o, 'alaoui', customer: customer), isTrue);
      expect(orderMatchesSearch(o, '345678', customer: customer), isTrue);
    });

    test('a blank search matches everything', () {
      expect(orderMatchesSearch(row(), '  '), isTrue);
    });
  });

  Future<int> seedOrder(String code, {int? number, String? reference}) async {
    await db.into(db.products).insertOnConflictUpdate(ProductsCompanion.insert(
        id: const Value(1), name: 'P', price: 10, finalPrice: 10));
    final id = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: code,
          type: const Value('TAKE_AWAY'),
          sessionOrderNo: Value(number),
          reference: Value(reference),
        ));
    await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
        orderId: id, productId: 1, unitaryPrice: 10));
    return id;
  }

  test('the resume query narrows to the search', () async {
    await seedOrder('AAA111', number: 3);
    await seedOrder('BBB222', number: 4, reference: 'Uber 9001');
    await seedOrder('CCC333', number: 5);

    Future<List<String>> codes(String search) async => [
          for (final o in await repo.getUnpaidOrdersForResume(search: search))
            o.code
        ];

    expect(await codes('#4'), ['BBB222']);
    expect(await codes('uber'), ['BBB222']);
    expect(await codes('ccc'), ['CCC333']);
    expect((await codes('')).length, 3);
  });

  test('the reference survives a reload and an update', () async {
    final id = await seedOrder('REF1', reference: 'Sara pickup');
    final loaded = (await repo.getOrderById(id))!;
    expect(loaded.reference, 'Sara pickup');

    await repo.updateOrder(loaded.copyWith(reference: 'Sara 2'),
        queueSyncOperation: false);
    expect((await repo.getOrderById(id))!.reference, 'Sara 2');

    // Cleared from the panel = stored as nothing, not as an empty string.
    await repo.updateOrder((await repo.getOrderById(id))!.copyWith(reference: ''),
        queueSyncOperation: false);
    final row = await (db.select(db.orders)..where((o) => o.id.equals(id)))
        .getSingle();
    expect(row.reference, isNull);
  });

  test('the push sends the reference trimmed and capped, or not at all', () {
    expect(referenceForSync(null), isNull);
    expect(referenceForSync('   '), isNull);
    expect(referenceForSync('  Glovo 4471 '), 'Glovo 4471');
    expect(referenceForSync('x' * 150)!.length, kOrderReferenceMaxLength);
  });
}

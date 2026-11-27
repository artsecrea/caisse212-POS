import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/services/data_sync_service.dart';
import 'package:caisse212/services/serial_service.dart';

/// Serial-managed products. The backend rejects the WHOLE order on any serial
/// mistake, so every rule here is one that would otherwise surface as a 400 at
/// sync time — long after the customer has left with the goods.
void main() {
  late AppDatabase db;
  late LocalSerialService serials;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    serials = LocalSerialService(db);
  });
  tearDown(() => db.close());

  Future<void> product(int id,
          {bool tracked = false, String name = 'iPhone'}) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: name,
            price: 8999,
            finalPrice: 8999,
            isSerialTracked: Value(tracked),
          ));

  Future<void> variant(int id, int productId, {bool tracked = false}) =>
      db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
            id: Value(id),
            productId: productId,
            name: 'V$id',
            price: 9999,
            isSerialTracked: Value(tracked),
          ));

  Future<void> serial(int id, int productId, String number,
          {bool available = true, String? batch}) =>
      db.into(db.serials).insert(SerialsCompanion.insert(
            id: Value(id),
            serialNumber: number,
            productId: productId,
            isAvailable: Value(available),
            batchCode: Value(batch),
          ));

  group('is the product serial-tracked', () {
    test('the product flag alone is enough', () async {
      await product(1, tracked: true);
      expect(await serials.isTracked(productId: 1), isTrue);
    });

    test('an untracked product is not tracked', () async {
      await product(1);
      expect(await serials.isTracked(productId: 1), isFalse);
    });

    test('a tracked VARIANT of an untracked product is tracked', () async {
      // Either side can turn it on — reading only the product flag here would
      // let a tracked variant through with no serial.
      await product(1);
      await variant(10, 1, tracked: true);
      expect(await serials.isTracked(productId: 1, variantId: 10), isTrue);
    });

    test('an untracked variant of a TRACKED product is still tracked',
        () async {
      await product(1, tracked: true);
      await variant(10, 1);
      expect(await serials.isTracked(productId: 1, variantId: 10), isTrue);
    });

    test('a product that does not exist is not tracked, and does not throw',
        () async {
      expect(await serials.isTracked(productId: 999), isFalse);
    });
  });

  group('what the picker may offer', () {
    test('only available units of the right product, oldest first', () async {
      await product(1, tracked: true);
      await product(2, tracked: true);
      await serial(103, 1, 'SN-C');
      await serial(101, 1, 'SN-A');
      await serial(102, 1, 'SN-B', available: false); // sold
      await serial(201, 2, 'SN-OTHER');

      final list = await serials.availableFor(1);
      expect(list.map((s) => s.serialNumber), ['SN-A', 'SN-C'],
          reason: 'sold units and other products must not be offered, '
              'and stock should rotate FIFO by id');
    });

    test('units already in the basket are excluded', () async {
      await product(1, tracked: true);
      await serial(101, 1, 'SN-A');
      await serial(102, 1, 'SN-B');
      final list = await serials.availableFor(1, excludeIds: {101});
      expect(list.map((s) => s.serialNumber), ['SN-B']);
    });

    test('availableCount ignores sold units', () async {
      await product(1, tracked: true);
      await serial(101, 1, 'SN-A');
      await serial(102, 1, 'SN-B', available: false);
      expect(await serials.availableCount(1), 1);
    });
  });

  group('reserve / release', () {
    test('reserving hides the unit; releasing brings it back', () async {
      await product(1, tracked: true);
      await serial(101, 1, 'SN-A');

      await serials.reserve(101);
      expect(await serials.availableCount(1), 0,
          reason: 'a unit in a basket must not be offerable to a second line');

      await serials.release(101);
      expect(await serials.availableCount(1), 1);
    });

    test('a server pull overrides a stale local reservation', () async {
      // The crash-recovery path: a reservation orphaned by a crash is fixed by
      // the server re-asserting isAvailable, not by any local cleanup.
      await product(1, tracked: true);
      await serial(101, 1, 'SN-A');
      await serials.reserve(101);
      expect(await serials.availableCount(1), 0);

      await db.into(db.serials).insertOnConflictUpdate(
            SerialsCompanion.insert(
              id: const Value(101),
              serialNumber: 'SN-A',
              productId: 1,
              isAvailable: const Value(true),
            ),
          );
      expect(await serials.availableCount(1), 1);
    });
  });

  group('scan lookup', () {
    test('matches case-insensitively and ignores surrounding whitespace',
        () async {
      // A scanner routinely appends whitespace, and a cashier typing by hand
      // will not match case.
      await product(1, tracked: true);
      await serial(101, 1, 'SN-2024-0001');
      expect((await serials.byNumber('  sn-2024-0001 '))?.id, 101);
    });

    test('an unknown number returns null rather than throwing', () async {
      await product(1, tracked: true);
      expect(await serials.byNumber('NOPE'), null);
    });

    test('a blank scan does not match the first row', () async {
      await product(1, tracked: true);
      await serial(101, 1, 'SN-A');
      expect(await serials.byNumber('   '), null);
    });
  });

  group('the cart never merges serial lines', () {
    OrderItem item({int? serialId}) => OrderItem(
          productId: 1,
          productName: 'iPhone',
          finalPrice: 8999,
          quantity: 1,
          serialId: serialId,
          serialNumber: serialId == null ? null : 'SN-$serialId',
        );

    test('isSerialLine reflects the serial', () {
      expect(item(serialId: 1).isSerialLine, isTrue);
      expect(item().isSerialLine, isFalse);
    });

    test('copyWith keeps the serial', () {
      // The cart copies items constantly; dropping the serial on any of those
      // copies would send a tracked line with no unit.
      final copy = item(serialId: 7).copyWith(quantity: 1);
      expect(copy.serialId, 7);
      expect(copy.serialNumber, 'SN-7');
    });
  });

  group('serial rejection detection', () {
    test('every documented serial 400 is recognised', () {
      // Matched on message text because the backend returns all six as a plain
      // 400 with no code to switch on.
      const messages = [
        "Product 'X' is serial-tracked — each line must carry a serialId",
        "Serial line for product 'X' must have quantity 1",
        "Serial 'SN' is not available (already sold, or its reception is not "
            "validated yet)",
        "Serial 'SN' belongs to product A, not B",
        'Serial 12 appears on more than one line',
        'Product X is not serial-tracked — remove serialId from the line',
      ];
      for (final m in messages) {
        expect(DataSyncService.isSerialRejection(Exception(m)), isTrue,
            reason: m);
      }
    });

    test('an unrelated failure is NOT treated as a serial problem', () {
      // A false positive here would trigger a pointless catalogue re-pull on
      // every ordinary network blip.
      for (final m in [
        'Network error: connection closed',
        'Order code already exists',
        'Product not found',
      ]) {
        expect(DataSyncService.isSerialRejection(Exception(m)), isFalse,
            reason: m);
      }
    });
  });
}

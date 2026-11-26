import 'package:drift/drift.dart' hide isNull, Component;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/catalogue_repository.dart';
import 'package:caisse212/providers/database_providers.dart';

/// The catalogue reads the screens used to make straight on the database.
/// Each test pins what the replaced call returned, so the rewire to the
/// repository cannot change a filter, an order or a written column.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late CatalogueRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    repo = container.read(catalogueRepositoryProvider);
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<int> product(int id,
          {String? barcode, String? reference, bool isActive = true}) =>
      db.into(db.products).insert(ProductsCompanion.insert(
          id: Value(id),
          name: 'P$id',
          price: 10,
          finalPrice: 12,
          barcode: Value(barcode),
          reference: Value(reference),
          isActive: Value(isActive)));

  group('findActiveByBarcodeOrReference', () {
    test('matches barcode or reference, both hits returned', () async {
      await product(1, reference: '123');
      await product(2, barcode: '123');
      await product(3, barcode: '999');
      final ids = (await repo.findActiveByBarcodeOrReference('123'))
          .map((p) => p.id)
          .toSet();
      expect(ids, {1, 2});
    });

    test('inactive products are never matched', () async {
      await product(1, barcode: '123', isActive: false);
      expect(await repo.findActiveByBarcodeOrReference('123'), isEmpty);
    });
  });

  test('productById, variantById, componentById: row or null', () async {
    await product(1);
    await db.into(db.productVariants).insert(ProductVariantsCompanion.insert(
        id: const Value(5), productId: 1, name: 'Large', price: 15));
    await db.into(db.components).insert(ComponentsCompanion.insert(
        id: const Value(7), name: 'Cheese', price: const Value(2)));

    expect((await repo.productById(1))?.finalPrice, 12);
    expect(await repo.productById(2), isNull);
    expect((await repo.variantById(5))?.price, 15);
    expect(await repo.variantById(6), isNull);
    expect((await repo.componentById(7))?.name, 'Cheese');
    expect(await repo.componentById(8), isNull);
  });

  test('productsByIds: only the asked ids, empty in → empty out', () async {
    await product(1);
    await product(2);
    await product(3);
    final rows = await repo.productsByIds({1, 3, 42});
    expect(rows.map((p) => p.id).toSet(), {1, 3});
    expect(await repo.productsByIds(const <int>[]), isEmpty);
  });

  test('allProducts includes inactive ones', () async {
    await product(1);
    await product(2, isActive: false);
    expect((await repo.allProducts()).map((p) => p.id).toSet(), {1, 2});
  });

  test('categoryNamesById includes inactive categories', () async {
    await db.into(db.categories).insert(
        CategoriesCompanion.insert(id: const Value(1), name: 'Hair'));
    await db.into(db.categories).insert(CategoriesCompanion.insert(
        id: const Value(2), name: 'Old', isActive: const Value(false)));
    expect(await repo.categoryNamesById(), {1: 'Hair', 2: 'Old'});
  });

  test('setProductAvailability writes isAvailable and nothing else', () async {
    await product(1);
    await product(2);
    final before = (await repo.productById(1))!;

    await repo.setProductAvailability(1, false);
    final after = (await repo.productById(1))!;
    expect(after.isAvailable, isFalse);
    expect(after.updatedAt, before.updatedAt);
    expect((await repo.productById(2))!.isAvailable, isTrue);

    await repo.setProductAvailability(1, true);
    expect((await repo.productById(1))!.isAvailable, isTrue);
  });
}

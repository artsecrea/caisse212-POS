import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart' as db;
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/api_service.dart';

/// Per-terminal category scope (`posTerminal.categoryIds` from POS login and
/// token refresh): which categories a till is allowed to put on its grid.
///
/// The catalogue endpoint keeps returning every category on purpose — hiding
/// is a display filter, never a delete — so the whole feature rests on this
/// list being parsed, persisted and applied correctly.

db.Product prod(int id, String name, {int? categoryId}) => db.Product(
      id: id,
      name: name,
      categoryId: categoryId,
      price: 10,
      uom: 'U',
      tvaAmount: 0,
      discountAmount: 0,
      finalPrice: 10,
      isActive: true,
      isAvailable: true,
      isVariant: false,
      isSerialTracked: false,
      isPlannable: false,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

db.Category cat(int id, String name, {int displayOrder = 0}) => db.Category(
      id: id,
      name: name,
      displayOrder: displayOrder,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

Future<ApiService> apiWith(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  return ApiService(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parsing posTerminal.categoryIds', () {
    test('a scope is stored and read back in the order the server sent', () async {
      final api = await apiWith({});
      // The real POSTerminalInfo shape: ids are numbers here even though the
      // terminal's own id/businessId are strings (legacy, mixed on purpose).
      await api.applyCategoryScope({
        'id': '2',
        'name': 'test',
        'businessId': '1',
        'warehouseId': null,
        'categoryIds': [41, 5, 60, 76, 2, 1, 4],
      });
      expect(api.categoryScope, [41, 5, 60, 76, 2, 1, 4]);
    });

    test('null means show everything, and clears a previous scope', () async {
      final api = await apiWith({});
      await api.applyCategoryScope({'categoryIds': [41, 5]});
      await api.applyCategoryScope({'categoryIds': null});
      expect(api.categoryScope, isNull);
    });

    test('no terminal object at all leaves the scope alone', () async {
      final api = await apiWith({});
      await api.applyCategoryScope({'categoryIds': [41, 5]});
      // What refresh returns when the request carried no X-POS-Name, or when
      // the terminal was renamed / unassigned server-side.
      await api.applyCategoryScope(null);
      expect(api.categoryScope, [41, 5],
          reason: 'a missing terminal says nothing about the scope; it must '
              'not silently unhide categories mid-shift');
    });

    test('a terminal without the field means the server has no scope feature',
        () async {
      final api = await apiWith({});
      await api.applyCategoryScope({'categoryIds': [41, 5]});
      await api.applyCategoryScope({'id': '2', 'businessId': '1'});
      expect(api.categoryScope, isNull,
          reason: 'the server serializes nulls explicitly, so an absent field '
              'is an older/rolled-back build — keeping a scope it can no '
              'longer clear would hide categories forever');
    });

    test('an empty list is treated as no scope, never as an empty grid', () async {
      final api = await apiWith({});
      await api.applyCategoryScope({'categoryIds': <int>[]});
      expect(api.categoryScope, isNull);
    });

    test('ids arriving as strings still parse', () async {
      final api = await apiWith({});
      await api.applyCategoryScope({'categoryIds': ['41', '5']});
      expect(api.categoryScope, [41, 5]);
    });

    test('a new scope replaces the old one rather than merging', () async {
      final api = await apiWith({});
      await api.applyCategoryScope({'categoryIds': [41, 5, 60]});
      await api.applyCategoryScope({'categoryIds': [2, 1]});
      expect(api.categoryScope, [2, 1]);
    });

    test('the stream announces every change to listeners', () async {
      final api = await apiWith({});
      final seen = <List<int>?>[];
      final sub = api.categoryScopeStream.listen(seen.add);
      await api.applyCategoryScope({'categoryIds': [41, 5]});
      await api.applyCategoryScope({'categoryIds': null});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen, [
        [41, 5],
        null
      ]);
    });
  });

  group('applying the scope to the grid', () {
    // test8 / terminal "test" (id 2) / business 1: nine live categories,
    // scope {41,5,60,76,2,1,4} — Drinks (3) and Starters (16) must vanish.
    final business = [
      cat(1, 'Plats', displayOrder: 0),
      cat(2, 'Sandwichs', displayOrder: 1),
      cat(3, 'Drinks', displayOrder: 2),
      cat(4, 'Desserts', displayOrder: 3),
      cat(5, 'Pizzas', displayOrder: 4),
      cat(16, 'Starters', displayOrder: 5),
      cat(41, 'Menus', displayOrder: 6),
      cat(60, 'Salades', displayOrder: 7),
      cat(76, 'Tacos', displayOrder: 8),
    ];

    test('out-of-scope categories disappear', () {
      final shown = scopedCategories(business, [41, 5, 60, 76, 2, 1, 4]);
      expect(shown.map((c) => c.name), isNot(contains('Drinks')));
      expect(shown.map((c) => c.name), isNot(contains('Starters')));
      expect(shown, hasLength(7));
    });

    test('the scope order wins over displayOrder', () {
      final shown = scopedCategories(business, [41, 5, 60, 76, 2, 1, 4]);
      expect(shown.map((c) => c.id), [41, 5, 60, 76, 2, 1, 4]);
    });

    test('no scope leaves the list exactly as the database gave it', () {
      expect(scopedCategories(business, null).map((c) => c.id),
          business.map((c) => c.id));
    });

    test('an id the till has not synced yet is simply skipped', () {
      final shown = scopedCategories(business, [41, 999, 5]);
      expect(shown.map((c) => c.id), [41, 5]);
    });
  });

  group('products of hidden categories', () {
    // This filter is also what the LAN server applies to /waiters/products.
    // The waiter app's search reads every product it was given and never
    // consults the category list, so a product that reaches the tablet at all
    // is orderable — scoping the category route alone would enforce the scope
    // in the grid and bypass it in the search box beside it.
    final catalogue = [
      prod(1, 'Cheeseburger', categoryId: 1),
      prod(2, 'Coca', categoryId: 3), // Drinks — hidden
      prod(3, 'Soupe du jour', categoryId: 41),
      prod(4, 'Olives', categoryId: 16), // Starters — hidden
      prod(5, 'Sac plastique'), // no category at all
    ];

    test('a hidden category takes its products with it', () {
      final shown = scopedProducts(catalogue, [41, 5, 60, 76, 2, 1, 4]);
      expect(shown.map((p) => p.name),
          isNot(anyElement(isIn(['Coca', 'Olives']))));
    });

    test('a product with no category is not in a hidden one, so it stays', () {
      final shown = scopedProducts(catalogue, [41, 5, 60, 76, 2, 1, 4]);
      expect(shown.map((p) => p.id), [1, 3, 5]);
    });

    test('no scope changes nothing', () {
      expect(scopedProducts(catalogue, null), same(catalogue));
    });
  });
}

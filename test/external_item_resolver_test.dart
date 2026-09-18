import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/external_order_models.dart';
import 'package:caisse212/services/external_item_resolver.dart';

/// Automatic resolution of Glovo/Kooul order lines to local products.
///
/// There is no mapping screen on the till: an order arrives mid-service and the
/// cashier confirms it. Every line therefore has to resolve from data the
/// terminal already holds, or the order cannot be taken at all.
void main() {
  late AppDatabase db;
  late ExternalItemResolver resolver;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    resolver = ExternalItemResolver(db);
  });
  tearDown(() => db.close());

  Future<void> product(int id, String name, {String? reference}) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: name,
            price: 50,
            finalPrice: 50,
            reference: Value(reference),
          ));

  Future<void> mapping(int id, String provider, String externalId,
          {int? productId, int? componentId}) =>
      db.into(db.integrationMappings).insert(
            IntegrationMappingsCompanion.insert(
              id: Value(id),
              provider: provider,
              externalId: externalId,
              productId: Value(productId),
              componentId: Value(componentId),
              mapped: const Value(true),
            ),
          );

  ExternalQueueOrder order(List<ExternalQueueOrderItem> items) =>
      ExternalQueueOrder(
          type: 'DELIVERY', items: items, hasUnmappedItems: true);

  ExternalQueueOrderItem line({
    int productId = 0,
    String? externalProductId,
    List<ExternalQueueComponent> components = const [],
  }) =>
      ExternalQueueOrderItem(
        productId: productId,
        quantity: 1,
        components: components,
        externalProductId: externalProductId,
        mapped: productId > 0,
      );

  group('id patterns we minted ourselves', () {
    test('p42 is product 42', () {
      expect(ExternalItemResolver.glovoProductIdFrom('p42'), 42);
      expect(ExternalItemResolver.glovoProductIdFrom(' p7 '), 7);
    });

    test('a42-7 is product 42, component 7', () {
      final r = ExternalItemResolver.glovoAddonIdsFrom('a42-7');
      expect(r?.productId, 42);
      expect(r?.componentId, 7);
    });

    test("an opaque platform id is not mistaken for one of ours", () {
      // A Glovo dashboard id must NOT accidentally parse as p{id} — resolving
      // it to a wrong product is worse than not resolving it.
      for (final id in ['abc-123', 'p', 'p4x', 'product42', '42', 'a42', 'a-1-2']) {
        expect(ExternalItemResolver.glovoProductIdFrom(id), null, reason: id);
        expect(ExternalItemResolver.glovoAddonIdsFrom(id), null, reason: id);
      }
    });

    test('resolves offline, with no mapping row and no catalogue match',
        () async {
      await product(42, 'Cheese Burger');
      final out = await resolver
          .resolveOrder(order([line(externalProductId: 'p42')]), source: 'GLOVO');
      expect(out.items.single.productId, 42);
      expect(out.hasUnmappedItems, isFalse);
    });
  });

  group('SKU match on products.reference', () {
    test('a Kooul SKU resolves to the product carrying that reference',
        () async {
      await product(9, 'Tajine', reference: 'BRG-001');
      final out = await resolver.resolveOrder(
          order([line(externalProductId: 'BRG-001')]),
          source: 'KOOUL');
      expect(out.items.single.productId, 9);
    });

    test('matching ignores case and surrounding whitespace', () async {
      await product(9, 'Tajine', reference: 'brg-001');
      final out = await resolver.resolveOrder(
          order([line(externalProductId: ' BRG-001 ')]),
          source: 'KOOUL');
      expect(out.items.single.productId, 9);
    });

    test('an AMBIGUOUS reference is refused, not guessed', () async {
      // Nothing stops two products sharing a reference. Picking one would sell
      // the wrong item and nobody would know why.
      await product(1, 'Small Burger', reference: 'DUP');
      await product(2, 'Large Burger', reference: 'DUP');
      final out = await resolver
          .resolveOrder(order([line(externalProductId: 'DUP')]), source: 'KOOUL');
      expect(out.items.single.productId, 0);
      expect(out.hasUnmappedItems, isTrue);
    });

    test('a product with no reference is never matched by accident', () async {
      await product(9, 'Tajine');
      final out = await resolver
          .resolveOrder(order([line(externalProductId: 'BRG-001')]), source: 'KOOUL');
      expect(out.items.single.productId, 0);
    });
  });

  group('the cached mapping table', () {
    test('an opaque platform id resolves through it', () async {
      await product(5, 'Pizza');
      await mapping(1, 'GLOVO', 'glv-item-7', productId: 5);
      final out = await resolver.resolveOrder(
          order([line(externalProductId: 'glv-item-7')]),
          source: 'GLOVO');
      expect(out.items.single.productId, 5);
    });

    test('components resolve through it too', () async {
      await product(5, 'Pizza');
      await mapping(2, 'GLOVO', 'glv-addon-1', componentId: 12);
      final out = await resolver.resolveOrder(
        order([
          line(productId: 5, components: [
            const ExternalQueueComponent(
                componentId: 0,
                quantity: 1,
                externalComponentId: 'glv-addon-1',
                mapped: false)
          ])
        ]),
        source: 'GLOVO',
      );
      expect(out.items.single.components.single.componentId, 12);
      expect(out.hasUnmappedItems, isFalse);
    });

    test('an unlinked placeholder row does not count as resolved', () async {
      // The server auto-creates an empty row the first time it sees an id.
      // Treating that as a match would map the line to nothing.
      await db.into(db.integrationMappings).insert(
            IntegrationMappingsCompanion.insert(
              id: const Value(3),
              provider: 'GLOVO',
              externalId: 'unlinked',
              mapped: const Value(false),
            ),
          );
      final out = await resolver
          .resolveOrder(order([line(externalProductId: 'unlinked')]), source: 'GLOVO');
      expect(out.items.single.productId, 0);
    });
  });

  group('precedence and safety', () {
    test("the server's own answer is never second-guessed", () async {
      // Even with a reference that would match something else.
      await product(1, 'Right', reference: 'p99');
      final out = await resolver.resolveOrder(
          order([line(productId: 77, externalProductId: 'p99')]),
          source: 'GLOVO');
      expect(out.items.single.productId, 77);
    });

    test('a mapping row beats a coincidental SKU match', () async {
      await product(1, 'By reference', reference: 'shared');
      await product(2, 'By mapping');
      await mapping(1, 'KOOUL', 'shared', productId: 2);
      final out = await resolver
          .resolveOrder(order([line(externalProductId: 'shared')]), source: 'KOOUL');
      expect(out.items.single.productId, 2);
    });

    test('a line with no external id at all stays unresolved', () async {
      final out = await resolver.resolveOrder(order([line()]), source: 'GLOVO');
      expect(out.items.single.productId, 0);
      expect(out.hasUnmappedItems, isTrue);
    });

    test('one unresolved line keeps the whole order flagged', () async {
      await product(42, 'Burger');
      final out = await resolver.resolveOrder(
        order([
          line(externalProductId: 'p42'),
          line(externalProductId: 'mystery-item'),
        ]),
        source: 'GLOVO',
      );
      expect(out.items.first.productId, 42);
      expect(out.items.last.productId, 0);
      expect(out.hasUnmappedItems, isTrue,
          reason: 'confirm must stay blocked while any line is unresolved');
    });

    test('an order the server already resolved is returned untouched',
        () async {
      final ok = ExternalQueueOrder(
        type: 'DELIVERY',
        items: [line(productId: 5)],
        hasUnmappedItems: false,
      );
      final out = await resolver.resolveOrder(ok, source: 'GLOVO');
      expect(out.hasUnmappedItems, isFalse);
      expect(out.items.single.productId, 5);
    });
  });
}

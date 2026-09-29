import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/models/component_rules.dart';
import 'package:caisse212/domain/models/order_models.dart';
import 'package:caisse212/services/printing_service.dart';

/// Kitchen option lines carry a count only where the count means something.
/// A SINGLE or MULTIPLE pick is always one, so "+ Saignant x1" was noise; a
/// QUANTITY stepper shows its count only past one ("+ Extra cheese x2").
/// The mode is the one the modifier picker uses: the product's override row
/// when there is one, else the group's default, and QUANTITY for no group.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the label', () {
    test('SINGLE and MULTIPLE never show a count', () {
      expect(optionLineLabel('Saignant', 1, ComponentSelectionType.single),
          'Saignant');
      expect(
          optionLineLabel('Lait avoine', 1, ComponentSelectionType.multiple),
          'Lait avoine');
      // Even a malformed count on a pick group stays silent.
      expect(
          optionLineLabel('Truffe', 2, ComponentSelectionType.multiple),
          'Truffe');
    });

    test('QUANTITY shows the count only past one', () {
      expect(
          optionLineLabel('Extra cheese', 1, ComponentSelectionType.quantity),
          'Extra cheese');
      expect(
          optionLineLabel('Extra cheese', 2, ComponentSelectionType.quantity),
          'Extra cheese x2');
    });
  });

  group('the rendered tickets', () {
    late AppDatabase db;
    late PrintingService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      service = PrintingService();
      await service.saveConfig(
          await SharedPreferences.getInstance(), const PrinterConfig());
      db = AppDatabase.forTesting(NativeDatabase.memory());

      // Group 10 is QUANTITY in the catalogue, but product 1 overrides it to
      // SINGLE — the override is what must win.
      await db.into(db.componentGroups).insert(ComponentGroupsCompanion.insert(
          id: const Value(10), name: 'Cuisson', selectionType: const Value('QUANTITY')));
      await db.into(db.componentGroups).insert(ComponentGroupsCompanion.insert(
          id: const Value(20), name: 'Lait', selectionType: const Value('MULTIPLE')));
      await db.into(db.componentGroups).insert(ComponentGroupsCompanion.insert(
          id: const Value(30), name: 'Extras', selectionType: const Value('QUANTITY')));
      await db.into(db.productComponentGroups).insert(
          ProductComponentGroupsCompanion.insert(
              productId: 1, groupId: 10, selectionType: const Value('SINGLE')));

      Future<void> component(int id, String name, int? groupId) =>
          db.into(db.components).insert(ComponentsCompanion.insert(
              id: Value(id), name: name, componentGroupId: Value(groupId)));
      await component(101, 'Saignant', 10);
      await component(201, 'Lait avoine', 20);
      await component(301, 'Extra cheese', 30);
      await component(302, 'Extra bacon', 30);
      await component(401, 'Sauce maison', null);
    });
    tearDown(() async {
      service.dispatchForTesting = null;
      service.databaseForTesting = null;
      await db.close();
    });

    List<String> optionLines(List<int> bytes) => String.fromCharCodes(bytes)
        .split('\n')
        .where((l) => l.contains('+ '))
        .map((l) => l.substring(l.indexOf('+ ')).trimRight())
        .toList();

    test('the KDS ticket prints each mode as the kitchen should read it',
        () async {
      // The pick-group options carry 2 on purpose: at 1 every mode prints the
      // same, so only a count past one proves the mode was resolved (and the
      // product override honoured) rather than defaulted.
      final item = OrderItem(
        productId: 1,
        productName: 'Burger',
        finalPrice: 80.0,
        quantity: 1,
        components: [
          OrderItemComponent(componentId: 101, name: 'Saignant', quantity: 2, price: 0),
          OrderItemComponent(componentId: 201, name: 'Lait avoine', quantity: 2, price: 0),
          OrderItemComponent(componentId: 301, name: 'Extra cheese', quantity: 1, price: 5),
          OrderItemComponent(componentId: 302, name: 'Extra bacon', quantity: 2, price: 5),
          OrderItemComponent(componentId: 401, name: 'Sauce maison', quantity: 3, price: 0),
        ],
      );

      final bytes = await service.kdsTicketBytesForTesting(
        order: CurrentOrder(items: [item]),
        items: [item],
        generator: Generator(PaperSize.mm80, await CapabilityProfile.load()),
        database: db,
      );
      final lines = String.fromCharCodes(bytes)
          .split('\n')
          .where((l) => l.contains('+ '))
          .map((l) => l.substring(l.indexOf('+ ')).trimRight())
          .toList();

      // Printed for the peer review: one line per mode.
      // ignore: avoid_print
      print(lines.join('\n'));

      expect(lines, [
        '+ Saignant', // SINGLE via product override
        '+ Lait avoine', // MULTIPLE group default
        '+ Extra cheese', // QUANTITY, qty 1
        '+ Extra bacon x2', // QUANTITY, qty 2
        '+ Sauce maison x3', // no group → QUANTITY
      ]);
    });

    test('the order receipt applies the same rule', () async {
      final item = OrderItem(
        productId: 1,
        productName: 'Burger',
        finalPrice: 80.0,
        quantity: 1,
        components: [
          OrderItemComponent(componentId: 101, name: 'Saignant', quantity: 2, price: 0),
          OrderItemComponent(componentId: 201, name: 'Lait avoine', quantity: 2, price: 3),
          OrderItemComponent(componentId: 301, name: 'Extra cheese', quantity: 1, price: 5),
          OrderItemComponent(componentId: 302, name: 'Extra bacon', quantity: 2, price: 5),
        ],
      );
      final captured = <int>[];
      service.dispatchForTesting = (_, bytes) => captured.addAll(bytes);
      service.databaseForTesting = db;

      final ok = await service.printOrderReceipt(
          order: CurrentOrder(items: [item]), cashierName: 'Test');

      expect(ok, isTrue);
      expect(optionLines(captured), [
        '+ Saignant',
        '+ Lait avoine',
        '+ Extra cheese',
        '+ Extra bacon x2',
      ]);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/domain/services/customer_service.dart';

/// What a [CustomerService] must do, whoever implements it: the local
/// repository runs these on the till's database, a hub-backed one will run
/// them against the hub with its own harness.
abstract class CustomerHarness {
  CustomerService get customers;
  Future<void> dispose();
}

void customerServiceContract(
    String name, Future<CustomerHarness> Function() make) {
  group('$name honours the CustomerService contract', () {
    late CustomerHarness h;

    setUp(() async => h = await make());
    tearDown(() => h.dispose());

    test('a new phone adds a customer', () async {
      final id = await h.customers.upsertByPhone(
          phoneRaw: '0600000001', firstName: 'Ali', lastName: 'B');

      final c = await h.customers.getById(id!);
      expect((c!.firstName, c.lastName, c.phone), ('Ali', 'B', '0600000001'));
      expect(c.phoneNormalized, '212600000001');
    });

    test('a known phone, however written, updates that customer', () async {
      final id = await h.customers.upsertByPhone(
          phoneRaw: '0600000002', firstName: 'Ali', email: 'a@x.ma');

      final again = await h.customers.upsertByPhone(
          phoneRaw: '+212 600 000 002', lastName: 'Bennani');

      expect(again, id);
      expect(await h.customers.getAll(), hasLength(1));
      final c = (await h.customers.getById(id!))!;
      expect(c.firstName, 'Ali', reason: 'a blank field never wipes one');
      expect(c.lastName, 'Bennani');
      expect(c.email, 'a@x.ma');
      expect(c.phone, '+212 600 000 002');
    });

    test('a blank phone saves nothing', () async {
      expect(await h.customers.upsertByPhone(phoneRaw: '  ', firstName: 'X'),
          isNull);
      expect(await h.customers.upsertByPhone(phoneRaw: null), isNull);
      expect(await h.customers.getAll(), isEmpty);
    });

    test('a customer is found by phone and by name', () async {
      final id = await h.customers
          .upsertByPhone(phoneRaw: '0600000003', firstName: 'Salma');

      expect((await h.customers.findByPhoneNormalized('212600000003'))?.id, id);
      expect((await h.customers.searchByNameOrPhone('salm')).map((c) => c.id),
          [id]);
      expect((await h.customers.getByIds([id!])).map((c) => c.id), [id]);
    });
  });
}

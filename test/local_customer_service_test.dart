import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/services/customer_service.dart';
import 'package:caisse212/providers/database_providers.dart';

import 'contracts/customer_service_contract.dart';

/// The till's own customer table behind [CustomerService], driven by the
/// shared contract a hub-backed service will have to pass too.
class _LocalCustomerHarness implements CustomerHarness {
  _LocalCustomerHarness(this.db)
      : container = ProviderContainer(
            overrides: [databaseProvider.overrideWithValue(db)]);

  final AppDatabase db;
  final ProviderContainer container;

  @override
  CustomerService get customers => container.read(customerServiceProvider);

  @override
  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  customerServiceContract('CustomerRepository',
      () async => _LocalCustomerHarness(AppDatabase.forTesting(NativeDatabase.memory())));
}

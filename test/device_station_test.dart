import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/device_providers.dart';

/// Stations created and read from the devices screen.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late DeviceRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    repo = container.read(deviceRepositoryProvider);
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('addStation: first id is 1, then max + 1 even across gaps', () async {
    expect(await repo.addStation(name: 'Grill'), 1);
    await db.into(db.stations).insert(
        StationsCompanion.insert(id: const Value(7), name: 'Synced'));
    expect(await repo.addStation(name: 'Bar', description: 'Drinks'), 8);

    final bar = (await repo.getStationById(8))!;
    expect(bar.name, 'Bar');
    expect(bar.description, 'Drinks');
  });

  test('addStation stores an empty description as null, name as given',
      () async {
    final id = await repo.addStation(name: ' Pizza ', description: '');
    final row = (await repo.getStationById(id))!;
    expect(row.name, ' Pizza ');
    expect(row.description, isNull);
  });

  test('getStationById: null when missing', () async {
    expect(await repo.getStationById(3), isNull);
  });
}

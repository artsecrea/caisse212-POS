import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/services/device_service.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/device_providers.dart';

/// Stations read from the devices screen. They come from the back office
/// with the catalogue sync; the till never creates one.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late DeviceService repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    repo = container.read(deviceServiceProvider);
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('getStationById: the synced row', () async {
    await db.into(db.stations).insert(StationsCompanion.insert(
        id: const Value(7), name: 'Bar', description: const Value('Drinks')));
    final bar = (await repo.getStationById(7))!;
    expect(bar.name, 'Bar');
    expect(bar.description, 'Drinks');
  });

  test('getStationById: null when missing', () async {
    expect(await repo.getStationById(3), isNull);
  });
}

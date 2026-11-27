import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/domain/services/serial_service.dart';

/// Serial lookups for the refund slip and the double-sale alert.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late SerialService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    service = container.read(serialServiceProvider);
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  test('serialNumbersByIds: known ids only, empty in → empty out', () async {
    for (final (id, sn) in [(1, 'SN-1'), (2, 'SN-2'), (3, 'SN-3')]) {
      await db.into(db.serials).insert(SerialsCompanion.insert(
          id: Value(id), serialNumber: sn, productId: 10));
    }
    expect(await service.serialNumbersByIds({1, 3, 99}),
        {1: 'SN-1', 3: 'SN-3'});
    expect(await service.serialNumbersByIds(const <int>[]), isEmpty);
  });

  Future<int> conflict(DateTime detectedAt, {DateTime? acknowledgedAt}) =>
      db.into(db.serialConflicts).insert(SerialConflictsCompanion.insert(
          orderCode: 'O1',
          productId: 10,
          serialId: 1,
          detectedAt: Value(detectedAt),
          acknowledgedAt: Value(acknowledgedAt)));

  test('unacknowledged conflicts, newest first; acknowledging keeps the row',
      () async {
    final t0 = DateTime(2026, 11, 20, 10);
    final older = await conflict(t0);
    final newer = await conflict(t0.add(const Duration(hours: 1)));
    await conflict(t0, acknowledgedAt: t0);

    final stream = service.watchUnacknowledgedConflicts();
    expect((await stream.first).map((c) => c.id), [newer, older]);

    final at = DateTime(2026, 11, 21, 9);
    await service.acknowledgeConflicts([older, newer], at);
    expect(await stream.first, isEmpty);

    final rows = await db.select(db.serialConflicts).get();
    expect(rows.length, 3);
    for (final r in rows.where((r) => r.id == older || r.id == newer)) {
      expect(r.acknowledgedAt, at);
    }
  });
}

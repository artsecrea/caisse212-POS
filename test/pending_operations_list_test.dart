import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/pending_operations_service.dart';

/// The orders screen's pending-operations dialog shows the whole queue.
void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late PendingOperationsService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
    ]);
    service = container.read(pendingOperationsServiceProvider);
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<int> op(int entityId, DateTime createdAt, {int retries = 0}) =>
      db.into(db.pendingSyncOperations).insert(
          PendingSyncOperationsCompanion.insert(
              operationType: 'UPDATE',
              entityType: 'ORDER',
              entityId: entityId,
              createdAt: Value(createdAt),
              retryCount: Value(retries)));

  test('newest first, dead-lettered ops included', () async {
    final t0 = DateTime(2026, 11, 20, 10);
    await op(1, t0);
    await op(2, t0.add(const Duration(minutes: 2)),
        retries: PendingOperationsService.maxRetries);
    await op(3, t0.add(const Duration(minutes: 1)));

    final all = await service.getAllOperationsNewestFirst();
    expect(all.map((o) => o.entityId), [2, 3, 1]);
    // The retry queue, by contrast, skips the dead-lettered one.
    expect((await service.getPendingOperations()).map((o) => o.entityId),
        [1, 3]);
  });
}

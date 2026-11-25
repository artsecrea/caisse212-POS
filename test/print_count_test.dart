import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/ticket_provider.dart';

/// A print only counts: it must not look like an edit, or the row would be
/// re-pushed to the cloud as changed.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> order() => db.into(db.orders).insert(OrdersCompanion.insert(
        code: 'ORD1',
        isSynced: const Value(true),
        updatedAt: Value(DateTime(2026, 1, 1)),
      ));

  test('ticket print count goes up by one and nothing else changes', () async {
    final o = await order();
    final id = await db.into(db.tickets).insert(TicketsCompanion.insert(
          num: '0001',
          orderId: o,
          paymentMethod: 'CASH',
          amount: 10,
          isSynced: const Value(true),
          updatedAt: Value(DateTime(2026, 1, 1)),
        ));
    final repo = TicketRepository(db);

    await repo.incrementPrintCount(id);
    await repo.incrementPrintCount(id);

    final t = await (db.select(db.tickets)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(t.printCount, 2);
    expect(t.isSynced, isTrue);
    expect(t.updatedAt, DateTime(2026, 1, 1));
  });

  test('an unknown id is a no-op', () async {
    await TicketRepository(db).incrementPrintCount(999);
  });
}

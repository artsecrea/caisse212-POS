import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/cash_movement_service.dart';

/// Database-backed tests over a real in-memory SQLite, so these exercise the
/// actual drift statements rather than a mock. They cover the two behaviours a
/// regression would be most expensive in: the sync no longer destroying local
/// state, and cash movements totalling correctly.

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insertProduct(int id, String name,
          {bool isAvailable = true}) =>
      db.into(db.products).insert(ProductsCompanion.insert(
            id: Value(id),
            name: name,
            price: 10,
            finalPrice: 10,
            isAvailable: Value(isAvailable),
          ));

  group('upsert preserves locally-owned columns', () {
    test('a catalogue refresh does NOT clear an 86 flag', () async {
      // This is the whole reason the sync was moved off INSERT OR REPLACE.
      await insertProduct(1, 'Salmon');
      await (db.update(db.products)..where((p) => p.id.equals(1)))
          .write(const ProductsCompanion(isAvailable: Value(false)));

      // Simulate exactly what _persistProducts does: upsert WITHOUT mentioning
      // isAvailable. An omitted column must keep its local value.
      await db.into(db.products).insertOnConflictUpdate(
            ProductsCompanion.insert(
              id: const Value(1),
              name: 'Salmon Fillet', // renamed on the backend
              price: 12,
              finalPrice: 12,
            ),
          );

      final p = await (db.select(db.products)..where((t) => t.id.equals(1)))
          .getSingle();
      expect(p.name, 'Salmon Fillet', reason: 'server fields must update');
      expect(p.price, 12);
      expect(p.isAvailable, isFalse,
          reason: 'the local 86 must survive a catalogue sync');
    });

    test('INSERT OR REPLACE would have destroyed it (documents the old bug)',
        () async {
      await insertProduct(1, 'Salmon', isAvailable: false);

      await db.into(db.products).insert(
            ProductsCompanion.insert(
                id: const Value(1),
                name: 'Salmon Fillet',
                price: 12,
                finalPrice: 12),
            mode: InsertMode.insertOrReplace,
          );

      final p = await (db.select(db.products)..where((t) => t.id.equals(1)))
          .getSingle();
      // Row deleted and recreated → the omitted column fell back to its default.
      expect(p.isAvailable, isTrue,
          reason: 'proves why the sync must upsert, not replace');
    });
  });

  group('reconcile deletes only what the payload omitted', () {
    test('keeps ids present in the payload, removes the rest', () async {
      await insertProduct(1, 'A');
      await insertProduct(2, 'B');
      await insertProduct(3, 'C');

      // Server now knows about 1 and 3 only.
      const serverIds = {1, 3};
      final local = await db.select(db.products).get();
      final stale = local
          .map((p) => p.id)
          .where((id) => !serverIds.contains(id))
          .toList();
      await (db.delete(db.products)..where((p) => p.id.isIn(stale))).go();

      final remaining =
          (await db.select(db.products).get()).map((p) => p.id).toSet();
      expect(remaining, {1, 3});
    });
  });

  group('CashMovementService', () {
    test('IN adds and OUT subtracts, amount always stored unsigned', () async {
      final svc = CashMovementService(db);
      await svc.record(
          direction: CashMovementService.directionOut,
          amount: 60,
          reason: 'petty cash',
          sessionId: 1);
      await svc.record(
          direction: CashMovementService.directionIn,
          amount: 100,
          reason: 'float top-up',
          sessionId: 1);

      final rows = await svc.forSession(1);
      expect(rows.every((r) => r.amount > 0), isTrue,
          reason: 'direction carries the sign, never the amount');
      expect(await svc.netForSession(1), 40);

      final totals = await svc.totalsForSessions([1]);
      expect(totals.paidIn, 100);
      expect(totals.paidOut, 60);
    });

    test('a negative amount is normalised, not double-negated', () async {
      final svc = CashMovementService(db);
      // A caller passing -60 for an OUT must not produce +60 on the drawer.
      await svc.record(
          direction: CashMovementService.directionOut,
          amount: -60,
          reason: 'typo guard',
          sessionId: 1);
      expect(await svc.netForSession(1), -60);
    });

    test('rejects a zero amount and a blank reason', () async {
      final svc = CashMovementService(db);
      expect(
        () => svc.record(
            direction: CashMovementService.directionOut,
            amount: 0,
            reason: 'x',
            sessionId: 1),
        throwsArgumentError,
      );
      expect(
        () => svc.record(
            direction: CashMovementService.directionOut,
            amount: 10,
            reason: '   ',
            sessionId: 1),
        throwsArgumentError,
      );
    });

    test('movements are scoped per session', () async {
      final svc = CashMovementService(db);
      await svc.record(
          direction: CashMovementService.directionOut,
          amount: 50,
          reason: 'session 1',
          sessionId: 1);
      await svc.record(
          direction: CashMovementService.directionOut,
          amount: 70,
          reason: 'session 2',
          sessionId: 2);

      expect(await svc.netForSession(1), -50);
      expect(await svc.netForSession(2), -70);
      // A z-day rollup across both sessions.
      expect(await svc.netForSessions([1, 2]), -120);
    });

    test('no movements is zero, not null or an error', () async {
      final svc = CashMovementService(db);
      expect(await svc.netForSession(99), 0);
      expect(await svc.netForSessions(const []), 0);
      final t = await svc.totalsForSessions(const []);
      expect(t.paidIn, 0);
      expect(t.paidOut, 0);
    });

    test('delete removes a movement from the total', () async {
      final svc = CashMovementService(db);
      final m = await svc.record(
          direction: CashMovementService.directionOut,
          amount: 25,
          reason: 'to be undone',
          sessionId: 1);
      expect(await svc.netForSession(1), -25);
      await svc.delete(m.id);
      expect(await svc.netForSession(1), 0);
    });
  });

  group('migrations', () {
    test('a fresh database is created at the current schema version', () async {
      // Touching every new table proves createAll() covered them — a table
      // registered in @DriftDatabase but missing from the migration would only
      // surface at runtime otherwise.
      await db.customStatement('SELECT COUNT(*) FROM cash_movements');
      await db.customStatement('SELECT COUNT(*) FROM refunds');
      await db.customStatement('SELECT COUNT(*) FROM refund_lines');
      await db.customStatement('SELECT COUNT(*) FROM product_units');
      await db.customStatement('SELECT COUNT(*) FROM zs');
      // And the columns added by ALTER in later migrations.
      await db.customStatement('SELECT is_available FROM products LIMIT 0');
      await db.customStatement('SELECT cost FROM products LIMIT 0');
      await db.customStatement('SELECT cost FROM order_products LIMIT 0');
      await db.customStatement('SELECT COUNT(*) FROM serials');
      await db.customStatement('SELECT COUNT(*) FROM integration_mappings');
      await db.customStatement(
          'SELECT external_order_code FROM orders LIMIT 0');
      await db.customStatement(
          'SELECT is_serial_tracked FROM products LIMIT 0');
      await db.customStatement(
          'SELECT is_serial_tracked FROM product_variants LIMIT 0');
      await db.customStatement('SELECT serial_id FROM order_products LIMIT 0');
      await db.customStatement('SELECT sync_error FROM refunds LIMIT 0');
      await db.customStatement(
          'SELECT amount_overridden FROM refund_lines LIMIT 0');
      await db.customStatement('SELECT discount_reason, note FROM orders LIMIT 0');
      await db.customStatement(
          'SELECT server_id, sale_uom_id, manual_discount_reason FROM order_products LIMIT 0');
      await db.customStatement(
          'SELECT name FROM order_product_components LIMIT 0');
      await db.customStatement('SELECT delivery_fee FROM orders LIMIT 0');
      // Appointment booking: bookable staff, the cached diary, and the
      // backend-tracked payment position a part-paid service order needs.
      await db.customStatement('SELECT pin, is_active FROM providers LIMIT 0');
      await db.customStatement(
          'SELECT plan_start_at, plan_waiter_id, fetched_at, value, '
          'plan_resource_type FROM agenda_bookings LIMIT 0');
      await db.customStatement(
          'SELECT amount_paid, balance_due, payment_status FROM orders LIMIT 0');
      // Component group selection rules, the 86 switch, and the per-product
      // rule overrides.
      await db.customStatement(
          'SELECT color, selection_type, min_selection, max_selection, '
          'free_quantity FROM component_groups LIMIT 0');
      await db.customStatement(
          'SELECT is_active, display_order, linked_product_id, '
          'linked_variant_id FROM components LIMIT 0');
      await db.customStatement(
          'SELECT product_id, group_id, selection_type, min_selection, '
          'max_selection, free_quantity, is_required, display_order '
          'FROM product_component_groups LIMIT 0');
      await db.customStatement(
          'SELECT charge_on_removal FROM product_components LIMIT 0');
      await db.customStatement(
          'SELECT removal_charge FROM order_product_components LIMIT 0');
      await db.customStatement(
          'SELECT order_code, serial_id, winning_order_code, acknowledged_at '
          'FROM serial_conflicts LIMIT 0');
      // The payment screen's draft ticket-split arrangement — local only,
      // never synced.
      await db.customStatement(
          'SELECT order_id, order_product_id, draft_index, quantity '
          'FROM ticket_draft_splits LIMIT 0');
      // Delta printing for the customer order ticket.
      await db.customStatement(
          'SELECT order_ticket_printed_quantity FROM order_products LIMIT 0');
      // Courses on an order line.
      await db.customStatement(
          'SELECT course_no FROM order_products LIMIT 0');
      // Annulment tombstones, so the Z can total lines pulled off saved
      // orders after their order_products rows are gone.
      await db.customStatement(
          'SELECT order_id, product_name, quantity, amount, '
          'was_sent_to_kitchen, session_id FROM removed_order_items LIMIT 0');
      expect(db.schemaVersion, 57);
    });
  });
}

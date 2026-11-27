import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/services/returns_service.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/local_returns_service.dart';

import 'contracts/returns_service_contract.dart';

/// The till's own database behind [ReturnsService], offline, driven by the
/// shared contract a hub-backed service will have to pass too.
class _LocalReturnsHarness implements ReturnsHarness {
  _LocalReturnsHarness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;
  var _seq = 0;

  static Future<_LocalReturnsHarness> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    return _LocalReturnsHarness(db, container);
  }

  @override
  ReturnsService get returns => container.read(returnsServiceProvider);

  @override
  Future<({int zId, int sessionId})> zWithSession({bool closed = false}) async {
    final n = ++_seq;
    final zId = await db.into(db.zs).insert(ZsCompanion.insert(
          code: 'Z$n',
          createdBy: 1,
          zDay: Value('2026-11-${10 + n}'),
          status: Value(closed ? 'closed' : 'open'),
        ));
    final sessionId = await db.into(db.cashSessions).insert(
        CashSessionsCompanion.insert(
            code: 'S$n',
            cashierId: 1,
            moneyAtStart: 0,
            status: Value(closed ? 'ended' : 'active'),
            zId: Value(zId)));
    return (zId: zId, sessionId: sessionId);
  }

  @override
  Future<({Order order, int lineId})> sale(int sessionId) async {
    final id = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'SALE${++_seq}',
          status: const Value('COMPLETED'),
          sessionId: Value(sessionId),
          isSynced: const Value(true),
        ));
    final ticket = await db.into(db.tickets).insert(TicketsCompanion.insert(
          num: '0001',
          orderId: id,
          paymentMethod: 'CASH',
          amount: 100,
          isPaid: const Value(true),
        ));
    final lineId = await db.into(db.orderProducts).insert(
        OrderProductsCompanion.insert(
            orderId: id,
            productId: 5,
            quantity: const Value(2),
            unitaryPrice: 50,
            ticketId: Value(ticket)));
    final order =
        await (db.select(db.orders)..where((o) => o.id.equals(id))).getSingle();
    return (order: order, lineId: lineId);
  }

  @override
  Future<({int orderId, String code})> newOrder(double total) async {
    final code = 'NEW${++_seq}';
    final id = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: code,
          status: const Value('COMPLETED'),
        ));
    await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
        orderId: id, productId: 6, unitaryPrice: total));
    return (orderId: id, code: code);
  }

  @override
  Future<bool> linesPaid(int orderId) async =>
      (await (db.select(db.orderProducts)
                ..where((l) => l.orderId.equals(orderId)))
              .get())
          .every((l) => l.ticketId != null);

  @override
  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Offline: completing the exchange's order and publishing ask the platform
  // whether the till is online.
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  returnsServiceContract('LocalReturnsService', _LocalReturnsHarness.create);
}

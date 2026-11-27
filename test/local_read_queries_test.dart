import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/domain/services/floor_queries.dart';
import 'package:caisse212/domain/services/kds_stats_queries.dart';
import 'package:caisse212/domain/services/order_queries.dart';
import 'package:caisse212/domain/services/report_queries.dart';
import 'package:caisse212/domain/services/session_queries.dart';
import 'package:caisse212/domain/services/ticket_queries.dart';
import 'package:caisse212/domain/services/unpaid_queries.dart';
import 'package:caisse212/domain/services/z_queries.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/floor_repository.dart';
import 'package:caisse212/providers/kds_stats_provider.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/providers/ticket_provider.dart';

import 'contracts/read_queries_contract.dart';

/// The till's own database behind the read interfaces, read through the
/// providers the screens use, driven by the shared contract a hub-backed
/// till will have to pass too.
class _LocalReadHarness implements ReadHarness {
  _LocalReadHarness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;
  var _seq = 0;

  static Future<_LocalReadHarness> create() async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    return _LocalReadHarness(db, container);
  }

  @override
  OrderQueries get orders => container.read(orderQueriesProvider);
  @override
  TicketQueries get tickets => container.read(ticketQueriesProvider);
  @override
  SessionQueries get sessions => container.read(sessionQueriesProvider);
  @override
  ZQueries get zs => container.read(zQueriesProvider);
  @override
  UnpaidQueries get unpaid => container.read(unpaidQueriesProvider);
  @override
  FloorQueries get floor => container.read(floorQueriesProvider);
  @override
  ReportQueries get reports => container.read(reportQueriesProvider);
  @override
  KdsStatsQueries get kdsStats => container.read(kdsStatsServiceProvider);

  @override
  Future<int> z({bool open = true}) => db.into(db.zs).insert(ZsCompanion.insert(
        code: 'Z${++_seq}',
        createdBy: 1,
        zDay: const Value('2026-11-27'),
        status: Value(open ? 'open' : 'closed'),
      ));

  @override
  Future<int> session(
          {int cashierId = 1, String status = 'active', int? zId}) =>
      db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
            code: 'S${++_seq}',
            cashierId: cashierId,
            moneyAtStart: 0,
            status: Value(status),
            zId: Value(zId),
            // Distinct start times, so "newest" is never a tie.
            startedAt: Value(DateTime(2026, 11, 27, 8).add(Duration(minutes: _seq))),
          ));

  @override
  Future<int> product(String name, double price) =>
      db.into(db.products).insert(ProductsCompanion.insert(
          id: Value(++_seq), name: name, price: price, finalPrice: price));

  @override
  Future<int> order(String code,
          {int? sessionId,
          int? tableId,
          int? waiterId,
          double discountPercent = 0}) =>
      db.into(db.orders).insert(OrdersCompanion.insert(
            code: code,
            status: const Value('COMPLETED'),
            sessionId: Value(sessionId),
            tableId: Value(tableId),
            waiterId: Value(waiterId),
            discountPercentage: Value(discountPercent),
          ));

  @override
  Future<int> line(int orderId,
          {required int productId,
          required double price,
          double quantity = 1,
          String state = 'PENDING',
          int? ticketId}) =>
      db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: orderId,
            productId: productId,
            unitaryPrice: price,
            quantity: Value(quantity),
            state: Value(state),
            ticketId: Value(ticketId),
          ));

  @override
  Future<int> ticket(int orderId,
          {required double amount,
          String method = 'CASH',
          int? sessionId,
          bool paid = true}) =>
      db.into(db.tickets).insert(TicketsCompanion.insert(
            num: '${++_seq}'.padLeft(4, '0'),
            orderId: orderId,
            paymentMethod: method,
            amount: amount,
            sessionId: Value(sessionId),
            isPaid: Value(paid),
          ));

  @override
  Future<int> area(String name) =>
      db.into(db.areas).insert(AreasCompanion.insert(id: Value(++_seq), name: name));

  @override
  Future<int> table(String name, {int? areaId, int? orderId}) =>
      db.into(db.areaTables).insert(AreaTablesCompanion.insert(
            name: name,
            areaId: Value(areaId),
            orderId: Value(orderId),
          ));

  @override
  Future<int> waiter(String name, {List<int> areas = const []}) async {
    final id = await db
        .into(db.waiters)
        .insert(WaitersCompanion.insert(id: Value(++_seq), firstName: name));
    for (final a in areas) {
      await db
          .into(db.waiterAreas)
          .insert(WaiterAreasCompanion.insert(waiterId: id, areaId: a));
    }
    return id;
  }

  @override
  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  readQueriesContract('The local repositories', _LocalReadHarness.create);
}

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/settings_provider.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/refund_service.dart';

/// Refunds are online-only: the order and every refund already given on it —
/// on ANY till — come from the server, and "could not ask" must never read as
/// "nothing refunded yet".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The BMS read shape (GET /pos/refunds?orderCode=), trimmed.
  Map<String, dynamic> serverRefund(String code, List<List<num>> lines) => {
        'code': code,
        'orderCode': 'O1',
        'method': 'CASH',
        'totalAmount': 10,
        'lines': [
          for (final l in lines)
            {'id': 1, 'orderProductId': l[0], 'quantity': l[1], 'restock': true}
        ],
        'posTerminalName': 'T2',
      };

  group('other tills', () {
    test('server lines map back to local lines; own refunds are not counted '
        'twice', () {
      final out = otherTillsRefunded(
        serverRefunds: [
          serverRefund('RF-T2-1', [[900, 1], [901, 0.5]]),
          serverRefund('RF-T1-MINE', [[900, 1]]), // already held locally
          serverRefund('RF-T3-1', [[900, 1], [999, 4]]), // 999: not on this order
        ],
        localCodes: {'RF-T1-MINE'},
        localIdByServerId: {900: 10, 901: 11},
      );
      expect(out, {10: 2.0, 11: 0.5});
    });

    test('the cap holds across tills', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final orderId = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'O1', status: const Value('COMPLETED')));
      final order =
          await (db.select(db.orders)..where((o) => o.id.equals(orderId)))
              .getSingle();
      final lineId = await db.into(db.orderProducts).insert(
          OrderProductsCompanion.insert(
              orderId: orderId,
              productId: 5,
              quantity: const Value(2),
              unitaryPrice: 10,
              state: const Value('PENDING')));

      final refunds = RefundService(db);
      // Another till already took one of the two back.
      expect(
        () => refunds.createRefund(
          order: order,
          method: 'CASH',
          lines: [RefundLineDraft(orderProductId: lineId, quantity: 2)],
          refundedElsewhere: {lineId: 1},
        ),
        throwsA(isA<RefundCapException>()
            .having((e) => e.remaining, 'remaining', 1)),
      );
      final ok = await refunds.createRefund(
        order: order,
        method: 'CASH',
        lines: [RefundLineDraft(orderProductId: lineId, quantity: 1)],
        refundedElsewhere: {lineId: 1},
      );
      expect(ok.totalAmount, 10);
    });
  });

  group('strict lookups over HTTP', () {
    late HttpServer server;
    late String mode; // ok | missing | boom
    setUp(() async {
      HttpOverrides.global = null;
      mode = 'ok';
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final res = req.response..headers.contentType = ContentType.json;
        final path = req.uri.path;
        if (mode == 'boom') {
          res.statusCode = 500;
        } else if (path.endsWith('/pos/orders/O1')) {
          if (mode == 'missing') {
            res.statusCode = 404;
          } else {
            res.write(jsonEncode({'code': 'O1', 'products': []}));
          }
        } else if (path.endsWith('/pos/refunds')) {
          final q = req.uri.queryParameters;
          if (q.containsKey('orderCode')) {
            res.write(jsonEncode(mode == 'missing'
                ? []
                : [serverRefund('RF-T2-1', [[900, 1]])]));
          } else if (q.containsKey('from')) {
            res.write(jsonEncode({
              'content': [serverRefund('RF-T2-1', [[900, 1]])],
              'totalElements': 1,
              'totalPages': 1,
            }));
          } else {
            res.statusCode = 400;
          }
        } else {
          res.statusCode = 404;
        }
        await res.close();
      });
    });
    tearDown(() => server.close(force: true));

    Future<ApiService> api({int? port}) async {
      SharedPreferences.setMockInitialValues({
        'api_base_url': 'http://127.0.0.1:${port ?? server.port}',
        'pos_name': 'T1',
      });
      return ApiService(await SharedPreferences.getInstance());
    }

    test('order and refunds come back', () async {
      final a = await api();
      expect((await a.fetchOrderForRefund('O1'))['code'], 'O1');
      expect((await a.fetchRefundsForRefund('O1')).single['code'], 'RF-T2-1');
    });

    test('unknown order is notFound; no refunds is an empty list', () async {
      mode = 'missing';
      final a = await api();
      await expectLater(
          a.fetchOrderForRefund('O1'),
          throwsA(isA<RefundLookupException>().having(
              (e) => e.failure, 'failure', RefundLookupFailure.notFound)));
      expect(await a.fetchRefundsForRefund('O1'), isEmpty);
    });

    test('server error or no network is "offline", never "nothing found"',
        () async {
      mode = 'boom';
      final a = await api();
      await expectLater(
          a.fetchRefundsForRefund('O1'),
          throwsA(isA<RefundLookupException>().having(
              (e) => e.failure, 'failure', RefundLookupFailure.offline)));

      final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = dead.port;
      await dead.close();
      final b = await api(port: port);
      await expectLater(
          b.fetchOrderForRefund('O1'),
          throwsA(isA<RefundLookupException>().having(
              (e) => e.failure, 'failure', RefundLookupFailure.offline)));
    });

    test('the business-wide listing is read; an older server says so', () async {
      final a = await api();
      final page = await a.fetchRefundsPage(
          from: DateTime(2026, 10, 1), to: DateTime(2026, 10, 8));
      expect((page!['content'] as List).single['posTerminalName'], 'T2');
    });
  });

  test('existing tills get the Refund button in their saved order', () async {
    SharedPreferences.setMockInitialValues({
      'button_order': ['persons', 'cancelOrder', 'pay', 'proceed'],
    });
    final prefs = await SharedPreferences.getInstance();
    final s = SettingsNotifier(prefs).state;
    expect(s.showRefundButton, isTrue);
    expect(s.buttonOrder.indexOf('refund'),
        s.buttonOrder.indexOf('cancelOrder') + 1);
  });
}

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/services/notification_outbox.dart';
import 'package:caisse212/services/notification_params.dart';

/// Notifications are queued in the DB, deleted once delivered, and kept when
/// the network is down — so a till offline at a session close, a discount or
/// a cancellation still reports it later, exactly once.
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  DioException httpError(int status) => DioException(
        requestOptions: RequestOptions(path: '/pos/notify'),
        response: Response(
            requestOptions: RequestOptions(path: '/pos/notify'),
            statusCode: status),
        type: DioExceptionType.badResponse,
      );
  DioException offline() => DioException(
        requestOptions: RequestOptions(path: '/pos/notify'),
        type: DioExceptionType.connectionError,
      );

  Future<List<PendingNotification>> queued() =>
      db.select(db.pendingNotifications).get();

  test('a delivered notification leaves nothing behind', () async {
    final sent = <String>[];
    final outbox = NotificationOutbox.withSender(db,
        ({required type, required params, refId, required clientRequestId}) async {
      sent.add(type);
    });
    await outbox.send('POS_SESSION_OPENED', {'v': '1'}, refId: '7');
    expect(sent, ['POS_SESSION_OPENED']);
    expect(await queued(), isEmpty);
  });

  test('offline it is kept, and the next flush delivers it with the same '
      'idempotency key', () async {
    var online = false;
    final keys = <String>[];
    final outbox = NotificationOutbox.withSender(db,
        ({required type, required params, refId, required clientRequestId}) async {
      keys.add(clientRequestId);
      if (!online) throw offline();
    });
    await outbox.send('POS_CANCELLATION', {'v': '1', 'kind': 'ORDER'});
    expect(await queued(), hasLength(1));
    expect(await outbox.pendingCount(), 1);

    online = true;
    expect(await outbox.flush(), 1);
    expect(await queued(), isEmpty);
    expect(keys, hasLength(2));
    expect(keys[0], keys[1], reason: 'a retry must be deduplicated server-side');
  });

  test('flush stops at the first network failure, oldest first', () async {
    final order = <String>[];
    var fail = true;
    final outbox = NotificationOutbox.withSender(db,
        ({required type, required params, refId, required clientRequestId}) async {
      order.add(type);
      if (fail) throw offline();
    });
    await outbox.send('A', {});
    await outbox.send('B', {});
    order.clear();
    await outbox.flush();
    expect(order, ['A'], reason: 'B would fail the same way');
    fail = false;
    order.clear();
    expect(await outbox.flush(), 2);
    expect(order, ['A', 'B']);
  });

  test('a payload the server keeps refusing is dropped after 5 tries', () async {
    final outbox = NotificationOutbox.withSender(db,
        ({required type, required params, refId, required clientRequestId}) async {
      throw httpError(400);
    });
    await outbox.send('BAD', {});
    for (var i = 0; i < 3; i++) {
      await outbox.flush();
    }
    final row = (await queued()).single;
    expect(row.attempts, 4);
    expect(row.lastError, 'HTTP 400');
    await outbox.flush();
    expect(await queued(), isEmpty);
  });

  test('a 5xx or a 429 is not a refusal — it waits for the next sync',
      () async {
    final outbox = NotificationOutbox.withSender(db,
        ({required type, required params, refId, required clientRequestId}) async {
      throw httpError(503);
    });
    await outbox.send('X', {});
    for (var i = 0; i < 10; i++) {
      await outbox.flush();
    }
    expect((await queued()).single.attempts, 0);
  });

  group('payloads', () {
    test('discount: optional keys omitted, strings only', () {
      final p = NotificationParams.discountApplied(
        terminalName: 'Caisse 1',
        scope: 'ORDER',
        orderCode: 'ABC',
        amount: 12.345,
        percent: 10,
        at: DateTime(2026, 9, 25, 20, 5),
        currency: 'MAD',
      );
      expect(p['amount'], '12.35');
      expect(p['percent'], '10.00');
      expect(p.containsKey('productName'), isFalse);
      expect(p.containsKey('reason'), isFalse);
      expect(p['at'], '2026-09-25T20:05:00.000');
    });

    test('cancellation: weighed quantity keeps 3 decimals', () {
      final p = NotificationParams.cancellation(
        terminalName: 'Caisse 1',
        kind: 'LINE',
        orderCode: 'ABC',
        amount: 30,
        productName: 'Viande',
        quantity: 0.25,
        afterKitchen: true,
        at: DateTime(2026, 9, 25),
        currency: 'MAD',
      );
      expect(p['quantity'], '0.250');
      expect(p['afterKitchen'], 'true');
      expect(p['kind'], 'LINE');
    });
  });
}

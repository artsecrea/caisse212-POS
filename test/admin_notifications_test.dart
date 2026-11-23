import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/order_provider.dart';
import 'package:caisse212/services/notification_outbox.dart';
import 'package:caisse212/services/pos_notifications.dart';
import 'package:caisse212/services/session_service.dart';

/// Deleting a saved order takes it off the books just like cancelling it, so
/// the admin hears about it: one POS_CANCELLATION marked `deleted`.

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late OrderRepository repo;
  final sent = <({String type, Map<String, String> params, String? refId})>[];

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sent.clear();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      notificationOutboxProvider.overrideWithValue(NotificationOutbox.withSender(
        db,
        ({required type, required params, refId, required clientRequestId}) async =>
            sent.add((type: type, params: params, refId: refId)),
      )),
    ]);
    repo = OrderRepository(db, container.read(_refProvider));
  });
  tearDown(() {
    container.dispose();
    return db.close();
  });

  Future<int> order({String status = 'PENDING', bool withLine = true}) async {
    final id = await db.into(db.orders).insert(OrdersCompanion.insert(
          code: 'ORD1',
          status: Value(status),
          isSynced: const Value(false),
        ));
    if (withLine) {
      await db.into(db.orderProducts).insert(OrderProductsCompanion.insert(
            orderId: id,
            productId: 1,
            quantity: const Value(2),
            unitaryPrice: 25,
          ));
    }
    return id;
  }

  // The outbox send is fire-and-forget; let it land.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

  test('a deleted order is notified as a deleted ORDER cancellation', () async {
    await repo.deleteOrder(await order());
    await settle();

    expect(sent, hasLength(1));
    final n = sent.single;
    expect(n.type, 'POS_CANCELLATION');
    expect(n.refId, 'ORD1');
    expect(n.params['kind'], 'ORDER');
    expect(n.params['deleted'], 'true');
    expect(n.params['orderCode'], 'ORD1');
    expect(n.params['amount'], '50.00');
  });

  test('an empty order is deleted silently', () async {
    await repo.deleteOrder(await order(withLine: false));
    await settle();
    expect(sent, isEmpty);
  });

  // closeZNow notifies each session the Z close ended for its cashier.
  test('a session the Z close ended gets its own card, marked autoClosed',
      () async {
    final id = await db.into(db.cashSessions).insert(
        CashSessionsCompanion.insert(
          code: 'S1',
          cashierId: 1,
          moneyAtStart: 100,
          startedAt: Value(DateTime.now().subtract(const Duration(hours: 3))),
        ));
    final sessions = SessionService(db);
    await sessions.endSession(sessionId: id, autoClosed: true);

    await notifySessionClosed(container.read, id);
    await settle();

    expect(sent, hasLength(1));
    final n = sent.single;
    expect(n.type, 'POS_SESSION_CLOSED');
    expect(n.refId, '$id');
    expect(n.params['sessionCode'], 'S1');
    expect(n.params['autoClosed'], 'true');
    expect(n.params['moneyAtStart'], '100.00');
    expect(n.params.containsKey('countedCash'), isFalse);
  });

  group('pause / resume', () {
    Future<int> openSession() => db.into(db.cashSessions).insert(
        CashSessionsCompanion.insert(
          code: 'S2',
          cashierId: 7,
          moneyAtStart: 0,
          status: const Value('active'),
        ));

    test('a pause and a resume each send their card', () async {
      final id = await openSession();
      final sessions = SessionService(db);

      expect(await sessions.pauseSession(id), isTrue);
      await notifySessionPauseChange(container.read, id);
      final pausedAt = await sessions.resumeSession(id);
      expect(pausedAt, isNotNull);
      await notifySessionPauseChange(container.read, id, pausedAt: pausedAt);
      await settle();

      expect(sent.map((n) => n.type),
          ['POS_SESSION_PAUSED', 'POS_SESSION_RESUMED']);
      final paused = sent.first.params;
      expect(paused['sessionCode'], 'S2');
      expect(paused['cashierId'], '7');
      expect(paused['cashierName'], 'Cashier #7');
      expect(paused.containsKey('pausedAt'), isFalse);
      final resumed = sent.last.params;
      expect(resumed['pausedAt'], isNotNull);
      expect(resumed['pausedMinutes'], '0');
      expect(sent.last.refId, '$id');
    });

    test('no change, no card: pausing twice or resuming an active session',
        () async {
      final id = await openSession();
      final sessions = SessionService(db);
      expect(await sessions.resumeSession(id), isNull);
      expect(await sessions.pauseSession(id), isTrue);
      expect(await sessions.pauseSession(id), isFalse);
    });
  });

  test('an order already cancelled is not notified twice', () async {
    await repo.deleteOrder(await order(status: 'CANCELED'));
    await settle();
    expect(sent, isEmpty);
  });
}

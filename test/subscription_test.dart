import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/domain/models/subscription_info.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/pos_command_handler.dart';
import 'package:caisse212/services/subscription_store.dart';
import 'package:caisse212/presentation/widgets/subscription_notice.dart';
import 'package:flutter/material.dart';

/// Subscription warning on the login screen: two weeks ahead, re-checked once
/// a day inside that window, cleared as soon as a renewal reaches the till.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('sign-in lock', lockTests);

  final now = DateTime(2026, 10, 6, 10);
  SubscriptionInfo endingIn(Duration d) => SubscriptionInfo(endsAt: now.add(d));

  group('level', () {
    test('silent with nothing known or no end date', () {
      expect(subscriptionLevel(null, now), SubscriptionLevel.none);
      expect(subscriptionLevel(const SubscriptionInfo(status: 'ACTIVE'), now),
          SubscriptionLevel.none);
    });

    test('silent until exactly two weeks out, then ending', () {
      expect(subscriptionLevel(endingIn(const Duration(days: 15)), now),
          SubscriptionLevel.none);
      expect(subscriptionLevel(endingIn(const Duration(days: 14)), now),
          SubscriptionLevel.ending);
      expect(subscriptionLevel(endingIn(const Duration(hours: 1)), now),
          SubscriptionLevel.ending);
    });

    test('expired past the end date, or when the server says so', () {
      expect(subscriptionLevel(endingIn(const Duration(minutes: -1)), now),
          SubscriptionLevel.expired);
      expect(
          subscriptionLevel(
              SubscriptionInfo(
                  endsAt: now.add(const Duration(days: 300)),
                  status: 'EXPIRED'),
              now),
          SubscriptionLevel.expired);
    });
  });

  group('days left (calendar)', () {
    test('tonight is today, tomorrow morning is tomorrow', () {
      expect(subscriptionDaysLeft(DateTime(2026, 10, 6, 23, 59), now), 0);
      expect(subscriptionDaysLeft(DateTime(2026, 10, 7, 1), now), 1);
      expect(subscriptionDaysLeft(DateTime(2026, 10, 20, 0, 1), now), 14);
    });

    test('a bare date ends at the end of that day', () {
      final end = parseSubscriptionEnd('2026-10-06')!;
      expect(subscriptionLevel(SubscriptionInfo(endsAt: end), now),
          SubscriptionLevel.ending,
          reason: '"valid until the 6th" is still valid on the 6th');
    });

    test('garbage dates are silence, not a crash', () {
      expect(parseSubscriptionEnd('soon'), isNull);
      expect(SubscriptionInfo.fromJson({'endsAt': 42.5}).endsAt, isNull);
    });
  });

  group('daily check', () {
    test('never outside the window', () {
      expect(subscriptionCheckDue(endingIn(const Duration(days: 40)), null, now),
          isFalse);
      expect(subscriptionCheckDue(null, null, now), isFalse);
    });

    test('once per calendar day inside it', () {
      final info = endingIn(const Duration(days: 10));
      expect(subscriptionCheckDue(info, null, now), isTrue);
      expect(subscriptionCheckDue(info, DateTime(2026, 10, 6, 0, 5), now),
          isFalse);
      expect(subscriptionCheckDue(info, DateTime(2026, 10, 5, 23, 55), now),
          isTrue,
          reason: 'yesterday 23:55 is a different day even if <24h ago');
    });

    test('also keeps checking after expiry (a late renewal must clear it)', () {
      expect(
          subscriptionCheckDue(endingIn(const Duration(days: -3)),
              DateTime(2026, 10, 5), now),
          isTrue);
    });
  });

  group('store', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('posTerminal.subscription wins, round-trips, and stamps the check',
        () async {
      final store = SubscriptionStore(prefs);
      await store.applyResponse({
        'posTerminal': {
          'subscription': {
            'status': 'active',
            'endsAt': '2026-10-15T23:59:59Z',
            'planName': 'Pro',
            'contact': '+212 600 000 000',
          }
        },
        'subscription': {'endsAt': '2030-01-01'},
      });
      final info = store.current!;
      expect(info.status, 'ACTIVE');
      expect(info.endsAt!.toUtc(), DateTime.utc(2026, 10, 15, 23, 59, 59));
      expect(info.contact, '+212 600 000 000');
      expect(store.lastCheckedAt, isNotNull);
    });

    test('absent key keeps what we had; explicit null clears it', () async {
      final store = SubscriptionStore(prefs);
      await store.apply({'endsAt': '2026-10-15'});
      await store.applyResponse({'posTerminal': {'id': 2}});
      expect(store.current, isNotNull,
          reason: 'an older server says nothing — no reason to forget');
      await store.applyResponse({'posTerminal': {'subscription': null}});
      expect(store.current, isNull);
    });

    test('a renewal pushed over the old one clears the warning', () async {
      final store = SubscriptionStore(prefs);
      await store.apply({'endsAt': now.add(const Duration(days: 5)).toIso8601String()});
      expect(subscriptionLevel(store.current, now), SubscriptionLevel.ending);
      await store.apply({'endsAt': now.add(const Duration(days: 370)).toIso8601String()});
      expect(subscriptionLevel(store.current, now), SubscriptionLevel.none);
    });
  });

  group('over HTTP', () {
    late HttpServer server;
    late List<String> hits;
    late Map<String, dynamic> subscriptionBody;

    setUp(() async {
      HttpOverrides.global = null;
      hits = [];
      subscriptionBody = {'status': 'ACTIVE', 'endsAt': '2027-10-01T00:00:00Z'};
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        hits.add('${req.method} ${req.uri.path}');
        final res = req.response..headers.contentType = ContentType.json;
        if (req.uri.path.endsWith('/pos/refresh')) {
          res.write(jsonEncode({
            'accessToken': 'a.b.c',
            'refreshToken': 'r.s.t',
            'expiresIn': 900000,
            'posTerminal': {'id': '2', 'subscription': subscriptionBody},
          }));
        } else if (req.uri.path.endsWith('/pos/subscription')) {
          res.write(jsonEncode(subscriptionBody));
        } else {
          res.statusCode = 404;
        }
        await res.close();
      });
    });

    tearDown(() => server.close(force: true));

    Future<SharedPreferences> prefsFor(Map<String, Object> extra) async {
      SharedPreferences.setMockInitialValues({
        'api_base_url': 'http://127.0.0.1:${server.port}',
        'server_access_token': 'old',
        'server_refresh_token': 'old-refresh',
        ...extra,
      });
      return SharedPreferences.getInstance();
    }

    test('SSE refresh_token rotates the pair and re-reads the subscription',
        () async {
      final prefs = await prefsFor({});
      final container = ProviderContainer(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      addTearDown(container.dispose);
      final handler = container.read(Provider((ref) => PosCommandHandler(ref)));

      final type = await handler.handle({'type': 'refresh_token'})
          .catchError((_) => 'refresh_token'); // activity log needs the DB
      expect(type, 'refresh_token');
      expect(hits, contains('POST /api/pos/refresh'));
      expect(prefs.getString('server_refresh_token'), 'r.s.t');
      expect(container.read(subscriptionProvider)?.status, 'ACTIVE');
    });

    test('daily check runs only when due, and a renewal clears the banner',
        () async {
      final ending = DateTime.now().add(const Duration(days: 5));
      final prefs = await prefsFor({
        'pos_subscription_json': jsonEncode({'endsAt': ending.toUtc().toIso8601String()}),
      });
      final api = ApiService(prefs);

      expect(await api.refreshSubscription(onlyIfDue: true), isTrue);
      expect(hits, ['GET /api/pos/subscription']);
      expect(subscriptionLevel(api.subscription, DateTime.now()),
          SubscriptionLevel.none,
          reason: 'server says renewed until 2027 — forget the warning');

      // Checked today and no longer in the window: no second call.
      await api.refreshSubscription(onlyIfDue: true);
      expect(hits.length, 1);
    });

    test('BMS shape: always 200, wrapped; null clears; CANCELED is expired',
        () async {
      final prefs = await prefsFor({
        'pos_subscription_json': jsonEncode({'endsAt': '2026-10-10'}),
      });
      final responses = <Object>[
        // CANCELED: endsAt is the cancellation moment, already past.
        {
          'subscription': {
            'status': 'CANCELED',
            'endsAt': DateTime.now()
                .subtract(const Duration(minutes: 5))
                .toUtc()
                .toIso8601String(),
            'planName': 'Pro',
            'contact': null,
          }
        },
        {'subscription': null},
      ];
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(responses.removeAt(0)));
        await req.response.close();
      });
      await prefs.setString('api_base_url', 'http://127.0.0.1:${server.port}');
      final api = ApiService(prefs);

      expect(await api.refreshSubscription(), isTrue);
      expect(api.subscription?.status, 'CANCELED');
      expect(api.subscription?.contact, isNull);
      expect(subscriptionLevel(api.subscription, DateTime.now()),
          SubscriptionLevel.expired);

      expect(await api.refreshSubscription(), isTrue);
      expect(api.subscription, isNull,
          reason: 'tenant without a subscription row → nothing to warn about');
    });

    test('an older server without the endpoint keeps the stored copy',
        () async {
      final prefs = await prefsFor({
        'pos_subscription_json': jsonEncode({'endsAt': '2026-10-10'}),
      });
      await server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.statusCode = 404;
        await req.response.close();
      });
      await prefs.setString('api_base_url', 'http://127.0.0.1:${server.port}');
      final api = ApiService(prefs);
      expect(await api.refreshSubscription(), isFalse);
      expect(api.subscription?.endsAt, isNotNull);
    });
  });

  test('stream reaches listeners', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final got = <SubscriptionInfo?>[];
    final sub = SubscriptionStore.changes.listen(got.add);
    await SubscriptionStore(prefs).apply({'endsAt': '2026-10-15'});
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(got.single?.endsAt, isNotNull);
  });
}

// Sign-in lock (user ruling 2026-10-08): an expired subscription shows the
// locked card with "Check again"; one that is only ending does not.
Future<void> _pumpNotice(WidgetTester tester, Map<String, Object> prefsValues) async {
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const MaterialApp(home: Scaffold(body: SubscriptionNotice())),
  ));
  await tester.pump();
}

void lockTests() {
  testWidgets('expired: locked card with Check again', (tester) async {
    await _pumpNotice(tester, {
      'pos_subscription_json': jsonEncode({'status': 'EXPIRED', 'endsAt': '2026-01-01'}),
    });
    expect(find.text('Check again'), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // stop the notice's ticker
  });

  testWidgets('ending soon: warning only, no Check again', (tester) async {
    await _pumpNotice(tester, {
      'pos_subscription_json': jsonEncode({
        'endsAt': DateTime.now().add(const Duration(days: 5)).toUtc().toIso8601String()
      }),
    });
    expect(find.text('Check again'), findsNothing);
    expect(find.byType(SubscriptionNotice), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}

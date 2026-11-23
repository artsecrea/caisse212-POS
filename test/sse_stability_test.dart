import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/sse_service.dart';

/// The SSE pipe against a local server that speaks like the backend
/// (`connected`, then a `heartbeat` every few seconds — scaled down here).
///
/// The till used to drop a healthy stream every 60s on a quiet day: the
/// watchdog was fed only by business events, never by heartbeats.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null; // the binding fakes HTTP; this needs a real socket

  late HttpServer server;
  late List<String> subscribeAuth; // Authorization of each subscribe
  late String mode; // 'heartbeat' | 'silent' | 'expired'
  final open = <HttpResponse>[];

  setUp(() async {
    subscribeAuth = [];
    mode = 'heartbeat';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final res = req.response;
      if (req.uri.path == '/api/pos/refresh') {
        res.headers.contentType = ContentType.json;
        res.write(jsonEncode({
          'accessToken': 'fresh',
          'refreshToken': 'r2',
          'expiresIn': 3600000,
        }));
        await res.close();
        return;
      }
      final auth = req.headers.value(HttpHeaders.authorizationHeader) ?? '';
      subscribeAuth.add(auth);
      if (mode == 'expired' && auth == 'Bearer stale') {
        res.statusCode = 401;
        await res.close();
        return;
      }
      res.headers.contentType = ContentType('text', 'event-stream');
      res.bufferOutput = false;
      open.add(res);
      res.write('event:connected\ndata:{"businessId":1}\n\n');
      await res.flush();
      if (mode == 'silent') return;
      Timer.periodic(const Duration(milliseconds: 150), (t) async {
        try {
          res.write('event:heartbeat\ndata:{"ts":1}\n\n');
          await res.flush();
        } catch (_) {
          t.cancel();
        }
      });
    });
  });

  tearDown(() async {
    for (final r in open) {
      try {
        await r.close();
      } catch (_) {}
    }
    open.clear();
    await server.close(force: true);
  });

  Future<SseService> start({String token = 'good'}) async {
    SharedPreferences.setMockInitialValues({
      'api_base_url': 'http://127.0.0.1:${server.port}',
      'server_access_token': token,
      'server_refresh_token': 'r1',
      'pos_name': 'test',
      'business_id': 1,
    });
    final api = ApiService(await SharedPreferences.getInstance());
    final sse = SseService(api,
        livenessTimeout: const Duration(milliseconds: 600));
    sse.start();
    return sse;
  }

  test('heartbeats alone keep a quiet stream up', () async {
    final sse = await start();
    final events = <SseEventType>[];
    final sub = sse.events.listen((e) => events.add(e.type));

    // Four watchdog periods with nothing but heartbeats.
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    expect(subscribeAuth, hasLength(1), reason: 'no reconnect');
    expect(sse.status.value.state, SseConnectionState.live);
    expect(events, [SseEventType.connected],
        reason: 'heartbeats are not delivered as events');
    await sub.cancel();
    sse.stop();
  });

  test('a silent stream is dropped and reconnected exactly once', () async {
    mode = 'silent';
    final sse = await start();

    // Watchdog at 0.6s, reconnect after the 3s backoff, second watchdog at
    // ~4.2s whose reconnect is 6s away.
    await Future<void>.delayed(const Duration(milliseconds: 4600));

    expect(subscribeAuth, hasLength(2));
    sse.stop();
  });

  test('a 401 refreshes the token and comes back up', () async {
    mode = 'expired';
    final sse = await start(token: 'stale');

    await Future<void>.delayed(const Duration(milliseconds: 4000));

    expect(subscribeAuth, ['Bearer stale', 'Bearer fresh']);
    expect(sse.status.value.state, SseConnectionState.live);
    sse.stop();
  });

  test('back online reconnects without waiting out the backoff', () async {
    mode = 'silent';
    final sse = await start();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(sse.status.value.state, SseConnectionState.retrying);

    mode = 'heartbeat';
    sse.reconnectNow();
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(subscribeAuth, hasLength(2));
    expect(sse.status.value.state, SseConnectionState.live);
    sse.stop();
  });
}

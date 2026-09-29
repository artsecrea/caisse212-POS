import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/data/database/app_database.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/server_provider.dart';
import 'package:caisse212/services/server_service.dart';
import 'package:caisse212/services/waiter_call_service.dart';

/// `GET /waiters/events` over a real socket.
///
/// The unit tests cover the fan-out; this covers the parts only an actual HTTP
/// server can get wrong, and both have burned this codebase before on the
/// *client* side of SSE: a response that is buffered until it "finishes" (so
/// the phone sees nothing for minutes), and a stream that opens and closes
/// immediately (so the phone reconnect-loops forever). Neither shows up in a
/// handler test.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  const MethodChannel('dev.fluttercommunity.plus/connectivity')
      .setMockMethodCallHandler((call) async {
    if (call.method == 'check') return <String>['none'];
    return null;
  });

  late AppDatabase db;
  late ProviderContainer container;
  late ServerService server;
  const port = 18117;
  final base = Uri.parse('http://127.0.0.1:$port');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    SharedPreferences.setMockInitialValues({'waiter_call_enabled': true});
    final prefs = await SharedPreferences.getInstance();

    container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);

    await db.into(db.waiters).insert(WaitersCompanion.insert(
        id: const Value(1), firstName: 'Amina', lastName: const Value('B')));
    await db.into(db.waiters).insert(WaitersCompanion.insert(
        id: const Value(2),
        firstName: 'Retired',
        isActive: const Value(false)));

    server = container.read(serverServiceProvider);
    await server.start(port: port);
  });

  tearDown(() async {
    await server.stop();
    container.dispose();
    await db.close();
  });

  /// Opens the stream and collects decoded frames until [until] is satisfied
  /// (or the test times out). Returns the frames and closes the socket.
  Future<List<({String name, Map<String, dynamic> data})>> listen(
    int waiterId, {
    required FutureOr<void> Function() after,
    required bool Function(List<({String name, Map<String, dynamic> data})>)
        until,
  }) async {
    final client = HttpClient();
    final request = await client
        .getUrl(base.replace(path: '/waiters/events', queryParameters: {
      'waiterId': '$waiterId',
    }));
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final response = await request.close();

    expect(response.statusCode, 200);
    expect(response.headers.contentType?.mimeType, 'text/event-stream');

    final frames = <({String name, Map<String, dynamic> data})>[];
    final done = Completer<void>();
    String? pendingName;
    final sub = response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.startsWith('event:')) pendingName = line.substring(6).trim();
      if (line.startsWith('data:') && pendingName != null) {
        frames.add((
          name: pendingName!,
          data: jsonDecode(line.substring(5).trim()) as Map<String, dynamic>,
        ));
        pendingName = null;
        if (until(frames) && !done.isCompleted) done.complete();
      }
    });

    await after();
    await done.future.timeout(const Duration(seconds: 5));
    await sub.cancel();
    client.close(force: true);
    return frames;
  }

  test('the stream opens, stays open, and says so', () async {
    final frames = await listen(
      1,
      after: () {},
      until: (f) => f.isNotEmpty,
    );

    // A `connected` frame arriving over the wire is the whole point: it proves
    // the response was flushed rather than buffered, which is the failure that
    // looks exactly like "the feature does not work".
    expect(frames.single.name, 'connected');
    expect(frames.single.data['waiterId'], 1);
    expect(frames.single.data['callsEnabled'], isTrue);
  });

  test('a call placed after the phone connected arrives on it', () async {
    final frames = await listen(
      1,
      after: () async {
        // Let the subscription register before publishing into it.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await container.read(waiterCallServiceProvider).call(
              waiterId: 1,
              waiterName: 'Amina B',
              message: 'Customer waiting',
              tableId: 7,
              tableName: 'T7',
              fromUser: 'Sam',
            );
      },
      until: (f) => f.any((e) => e.name == 'waiter-call'),
    );

    final call = frames.firstWhere((e) => e.name == 'waiter-call').data;
    expect(call['message'], 'Customer waiting');
    expect(call['tableName'], 'T7');
    expect(call['from'], 'Sam');
    expect(call['ringUntilDismissed'], isTrue);
    expect(call['callId'], isA<String>());
  });

  test('a call placed while the phone was away is waiting when it connects',
      () async {
    await container.read(waiterCallServiceProvider).call(
          waiterId: 1,
          waiterName: 'Amina B',
          message: 'Table 3 is asking for you',
          fromUser: 'Sam',
        );

    final frames = await listen(
      1,
      after: () {},
      until: (f) => f.any((e) => e.name == 'waiter-call'),
    );

    expect(frames.map((e) => e.name), ['connected', 'waiter-call']);
    expect(frames.last.data['message'], 'Table 3 is asking for you');
  });

  test('acknowledging over HTTP stops the ringing and clears the queue',
      () async {
    final calls = container.read(waiterCallServiceProvider);
    final placed = await calls
        .call(waiterId: 1, waiterName: 'Amina B', fromUser: 'Sam');

    final frames = await listen(
      1,
      after: () async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final res = await http.post(
          base.replace(path: '/waiters/calls/${placed.call.id}/ack'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'by': 'Amina'}),
        );
        expect(res.statusCode, 200);
        expect(jsonDecode(res.body)['acknowledged'], isTrue);
      },
      until: (f) => f.any((e) => e.name == 'waiter-call-cancelled'),
    );

    final cancel =
        frames.firstWhere((e) => e.name == 'waiter-call-cancelled').data;
    expect(cancel['callId'], placed.call.id);
    expect(cancel['reason'], 'acknowledged');
    expect(cancel['by'], 'Amina');
    // A reconnect must not re-ring a call that was already answered.
    expect(calls.pendingFor(1), isEmpty);
  });

  test('acking a call that already expired is a 404, not a 500', () async {
    final res = await http.post(
        base.replace(path: '/waiters/calls/does-not-exist/ack'));
    expect(res.statusCode, 404);
    expect(jsonDecode(res.body)['error'], 'unknown_call');
  });

  test('a deactivated waiter is refused at connect, not left reconnecting',
      () async {
    // 403 rather than a stream that opens and dies: a phone whose identity was
    // revoked has to fail in a way it can show the user, instead of spinning
    // against an endpoint that keeps answering.
    final res =
        await http.get(base.replace(path: '/waiters/events', queryParameters: {
      'waiterId': '2',
    }));
    expect(res.statusCode, 403);
    expect(jsonDecode(res.body)['error'], 'unknown_waiter');
  });

  test('a missing waiterId is rejected', () async {
    final res = await http.get(base.replace(path: '/waiters/events'));
    expect(res.statusCode, 400);
  });

  test('/health advertises whether calls are switched on', () async {
    final res = await http.get(base.replace(path: '/health'));
    expect(jsonDecode(res.body)['waiterCallsEnabled'], isTrue);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/domain/models/session_expiry.dart';
import 'package:caisse212/services/api_service.dart';

/// Test-mode simulation of the sign-in running out: it must move only the
/// till's idea of the expiry, drive the notice and the gate exactly like the
/// real date would, and always be undoable from the real refresh JWT.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String jwt(DateTime exp) {
    String seg(Map<String, dynamic> m) =>
        base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');
    return '${seg({'alg': 'HS256'})}.'
        '${seg({'exp': exp.millisecondsSinceEpoch ~/ 1000, 'username': 'shop'})}.sig';
  }

  final realExp = DateTime.now().add(const Duration(days: 60));

  Future<ApiService> api() async {
    SharedPreferences.setMockInitialValues({
      'server_access_token': 'a.b.c',
      'server_refresh_token': jwt(realExp),
    });
    return ApiService(await SharedPreferences.getInstance());
  }

  test('6 days → notice, no gate', () async {
    final a = await api();
    await a.debugSetRefreshExpiry(DateTime.now().add(const Duration(days: 6)));
    expect(sessionExpiryLevel(a.getRefreshExpiresAt(), DateTime.now()),
        SessionExpiryLevel.notice);
    expect(a.isReauthDue(), isFalse);
  });

  test('20 h and already-expired both raise the gate', () async {
    final a = await api();
    await a.debugSetRefreshExpiry(DateTime.now().add(const Duration(hours: 20)));
    expect(a.isReauthDue(), isTrue);
    await a.debugSetRefreshExpiry(
        DateTime.now().subtract(const Duration(minutes: 5)));
    expect(a.isReauthDue(), isTrue);
  });

  test('restore puts back the expiry from the real refresh JWT', () async {
    final a = await api();
    await a.debugSetRefreshExpiry(DateTime.now());
    await a.debugSetRefreshExpiry(null);
    expect(a.getRefreshExpiresAt()!.millisecondsSinceEpoch ~/ 1000,
        realExp.millisecondsSinceEpoch ~/ 1000);
    expect(a.isReauthDue(), isFalse);
    // And a fresh instance (app restart) reads the restored value too.
    final again = ApiService(await SharedPreferences.getInstance());
    expect(again.isReauthDue(), isFalse);
  });

  test('simulated rejection raises the force-logout signal but keeps tokens',
      () async {
    final a = await api();
    var fired = 0;
    final sub = a.forceLogoutStream.listen((_) => fired++);
    a.debugSimulateRefreshRejected();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(fired, 1);
    expect(a.getAccessToken(), 'a.b.c');
  });

  test('a failed refresh is reported, never left as an unhandled error',
      () async {
    HttpOverrides.global = null;
    // Bind then close: a port that refuses, like a dev box that is down.
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close();
    SharedPreferences.setMockInitialValues({
      'api_base_url': 'http://127.0.0.1:$port',
      'server_access_token': 'a.b.c',
      'server_refresh_token': jwt(realExp),
    });
    final a = ApiService(await SharedPreferences.getInstance());

    // Alone: false, and (the regression) no unhandled exception in the zone,
    // which would fail this test on its own.
    expect(await a.ensureFreshToken(force: true), isFalse);

    // Concurrent: both callers still learn it failed.
    final r = await Future.wait(
        [a.ensureFreshToken(force: true), a.ensureFreshToken(force: true)]);
    expect(r, [false, false]);
    expect(a.getRefreshToken(), jwt(realExp), reason: 'nothing rotated');
  });

  test('expiry changes are announced', () async {
    final a = await api();
    var n = 0;
    final sub = a.expiryChanges.listen((_) => n++);
    await a.debugSetAccessExpiry(DateTime.now());
    await a.debugSetRefreshExpiry(null);
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(n, 2);
  });
}

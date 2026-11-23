import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';

import '../providers/database_providers.dart';
import 'remote_support_service.dart';

/// Tells the back office how to reach this till over remote support:
/// `PUT /pos/remote-access {rustdeskId, rustdeskVersion, serviceRunning,
/// password?}`.
///
/// Sent once per app run (on the first SSE connect, so the terminal is signed
/// in) and again whenever the ID changes. The password goes only when the
/// installer just set one; the local copy is dropped after a 2xx, so a till
/// never holds it longer than one successful push.
class RemoteAccessReporter {
  final Ref _ref;
  RemoteAccessReporter(this._ref);

  static const _lastIdKey = 'remote_access_last_id';
  bool _sentThisRun = false;
  Future<void>? _inFlight;

  Future<Map<String, dynamic>> status() async {
    final id = await RemoteSupportService.readId();
    return {
      'rustdeskId': id,
      'serviceRunning': await RemoteSupportService.serviceRunning(),
      'installed': RemoteSupportService.installed,
    };
  }

  Future<void> report({bool force = false}) =>
      _inFlight ??= _report(force).whenComplete(() => _inFlight = null);

  Future<void> _report(bool force) async {
    if (!Platform.isWindows) return;
    try {
      await RemoteSupportService.ensureServiceStarted();
      final id = await RemoteSupportService.readId();
      if (id == null) return;
      final password = await RemoteSupportService.readPendingPassword();
      final prefs = _ref.read(sharedPreferencesProvider);
      final unchanged = prefs.getString(_lastIdKey) == id;
      if (!force && _sentThisRun && unchanged && password == null) return;

      final ok = await _ref.read(apiServiceProvider).putRemoteAccess({
        'rustdeskId': id,
        'rustdeskVersion': await RemoteSupportService.version(),
        'serviceRunning': await RemoteSupportService.serviceRunning(),
        if (password != null) 'password': password,
      });
      if (!ok) return;
      _sentThisRun = true;
      await prefs.setString(_lastIdKey, id);
      if (password != null) RemoteSupportService.dropPendingPassword();
      Logger.instance.info('RemoteAccess: reported id=$id'
          '${password != null ? ' (with a new password)' : ''}');
    } catch (e) {
      Logger.instance.warning('RemoteAccess: report failed: $e');
    }
  }

  /// `remote_access_open`: make sure the tool is up, then answer with its ID.
  /// With no service installed the portable copy is started, which shows its
  /// own one-time password on the till's screen.
  Future<Map<String, dynamic>> open() async {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    if (RemoteSupportService.installed) {
      await RemoteSupportService.ensureServiceStarted();
    } else if (!await RemoteSupportService.launch()) {
      throw StateError('remote support is not installed on this till');
    }
    var st = await status();
    // A freshly started tool needs a moment before it has an ID.
    for (var i = 0; i < 5 && st['rustdeskId'] == null; i++) {
      await Future.delayed(const Duration(seconds: 2));
      st = await status();
    }
    unawaited(report(force: true));
    return st;
  }
}

final remoteAccessReporterProvider = Provider<RemoteAccessReporter>((ref) {
  return RemoteAccessReporter(ref);
});

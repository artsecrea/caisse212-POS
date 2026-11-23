import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/database/app_database.dart';
import '../providers/database_providers.dart';
import '../providers/network_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sse_provider.dart';
import 'activity_log_service.dart';
import 'diagnostics_service.dart';
import 'remote_access_reporter.dart';
import 'remote_config_service.dart';
import 'remote_sql_service.dart';

/// The remote console: answers a `pos-command` that carries a `requestId`.
///
/// Every such command gets exactly ONE reply on
/// `POST /pos/remote/{requestId}/result` — the read-only types here
/// ([handles]) are answered with their data, everything else is run by
/// `PosCommandHandler` as before and answered with [replyForCommand].
/// A command without a requestId never comes through here.
///
/// [capabilities] is sent on SSE subscribe (`X-POS-Capabilities`) so the back
/// office only offers what this build answers.
class RemoteCommandService {
  final Ref _ref;
  final _logger = Logger.instance;

  RemoteCommandService(this._ref);

  /// Set by main() once file logging is up; `get_logs` tails it.
  static String? logFilePath;

  static const capabilities = [
    'remote_sql',
    'app_info',
    'pending_sync',
    'get_logs',
    'diagnostics',
    'get_config',
    'set_config',
    'get_printers',
    'set_printers',
    'test_print',
    'remote_access_open',
    'ping',
  ];
  static final _readTypes = capabilities.toSet();

  /// version+build, for the reply to `ping` and the SSE header.
  static Future<String?> appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 5));
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return null;
    }
  }

  static String? requestIdOf(Map<String, dynamic> command) {
    final id = command['requestId']?.toString().trim();
    return id == null || id.isEmpty ? null : id;
  }

  static String typeOf(Map<String, dynamic> command) =>
      (command['type'] as String? ?? '').trim().toLowerCase();

  /// True for the types this service answers itself.
  bool handles(Map<String, dynamic> command) =>
      _readTypes.contains(typeOf(command));

  /// Runs a read-only type and replies.
  Future<void> answer(Map<String, dynamic> command, String requestId) async {
    final type = typeOf(command);
    final sw = Stopwatch()..start();
    Map<String, dynamic> reply;
    try {
      final data = switch (type) {
        'remote_sql' => await _remoteSql(command),
        'app_info' => await _appInfo(),
        'pending_sync' => await _pendingSync(command),
        'get_logs' => await _logs(command),
        'diagnostics' => await _diagnostics(),
        'get_config' => _config.getConfig(command),
        'set_config' => await _setConfig(command, requestId),
        'get_printers' => await _config.getPrinters(),
        'set_printers' => await _config.setPrinters(command),
        'test_print' => await _config.testPrint(command),
        'remote_access_open' => await _ref.read(remoteAccessReporterProvider).open(),
        'ping' => {'pong': true, 'version': await appVersion()},
        _ => throw StateError('unsupported: $type'),
      };
      reply = {'ok': true, 'data': data, 'durationMs': sw.elapsedMilliseconds};
    } catch (e) {
      reply = {'ok': false, 'error': '$e', 'durationMs': sw.elapsedMilliseconds};
    }
    await _send(type, requestId, reply);
  }

  /// The reply for a command `PosCommandHandler` ran. [handledType] null
  /// means it did not know the type.
  Future<void> replyForCommand(
    Map<String, dynamic> command,
    String requestId, {
    required String? handledType,
    Object? error,
    required Duration took,
  }) {
    final type = typeOf(command);
    final Map<String, dynamic> reply;
    if (error != null) {
      reply = {'ok': false, 'error': '$error'};
    } else if (handledType == null) {
      reply = {'ok': false, 'error': 'unsupported: $type'};
    } else {
      reply = {
        'ok': true,
        'data': {'type': handledType},
        'durationMs': took.inMilliseconds,
      };
    }
    return _send(type, requestId, reply);
  }

  Future<void> _send(
      String type, String requestId, Map<String, dynamic> reply) async {
    // The error text too: "ok=false" alone sends support to the back office
    // to learn why a till refused.
    _logger.info('RemoteCommand: $type $requestId → ok=${reply['ok']}'
        '${reply['error'] != null ? ' error=${reply['error']}' : ''}');
    await _ref.read(apiServiceProvider).postRemoteResult(requestId, reply);
    // Type and id only — a query result has no place in the audit trail.
    await _ref.read(activityLogServiceProvider).logPosCommand('remote:$type',
        details: 'requestId=$requestId ${reply['ok'] == true ? 'ok' : 'failed'}');
  }

  RemoteConfigService get _config => _ref.read(remoteConfigServiceProvider);

  Future<Map<String, dynamic>> _setConfig(
      Map<String, dynamic> command, String requestId) async {
    final result = await _config.setConfig(command);
    // Key names only: values can be ticket text a customer will read.
    await _ref.read(activityLogServiceProvider).logPosCommand('remote:set_config',
        details: 'requestId=$requestId keys=${(result['applied'] as List).join(',')}');
    return result;
  }

  // ── remote_sql ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _remoteSql(Map<String, dynamic> command) async {
    final sql = command['sql'] as String?;
    if (sql == null || sql.trim().isEmpty) throw ArgumentError('sql is required');
    final file = AppDatabase.openedFile;
    if (file == null) throw StateError('database not open yet');
    final params = command['params'];
    return RemoteSqlService.run(
      path: file.path,
      sql: sql,
      params: params is List ? params.cast<Object?>() : const [],
      maxRows: (command['maxRows'] as num?)?.toInt(),
      timeoutMs: (command['timeoutMs'] as num?)?.toInt(),
      schemaVersion: _ref.read(databaseProvider).schemaVersion,
    );
  }

  // ── app_info ────────────────────────────────────────────────────────────

  static final _secretKey =
      RegExp(r'pass|token|secret|pin$|api_?key|hash', caseSensitive: false);

  Future<Map<String, dynamic>> _appInfo() async {
    final api = _ref.read(apiServiceProvider);
    PackageInfo? info;
    try {
      info = await PackageInfo.fromPlatform()
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
    final file = AppDatabase.openedFile;
    int? dbBytes;
    try {
      if (file != null) dbBytes = await file.length();
    } catch (_) {}
    final settings = Map<String, dynamic>.from(_ref.read(settingsProvider).toJson())
      ..removeWhere((k, _) => _secretKey.hasMatch(k));
    return {
      'version': info?.version,
      'build': info?.buildNumber,
      'os': Platform.operatingSystem,
      'osVersion': Platform.operatingSystemVersion,
      'hostname': Platform.localHostname,
      'schemaVersion': _ref.read(databaseProvider).schemaVersion,
      'dbPath': file?.path,
      'dbBytes': dbBytes,
      'posName': api.getPosName(),
      'posId': api.getPosId(),
      'businessId': api.getBusinessId(),
      'tenantId': api.getTenantId(),
      'baseUrl': api.getBaseUrl(),
      'cashierSignedIn': _ref.read(currentUserProvider) != null,
      'now': DateTime.now().toIso8601String(),
      'timeZone': DateTime.now().timeZoneName,
      'settings': settings,
    };
  }

  // ── pending_sync ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _pendingSync(Map<String, dynamic> command) async {
    final limit = ((command['limit'] as num?)?.toInt() ?? 50).clamp(1, 500);
    final db = _ref.read(databaseProvider);
    final count = await db
        .customSelect('SELECT count(*) AS c FROM pending_sync_operations')
        .getSingle();
    final rows = await db.customSelect(
      'SELECT id, operation_type, entity_type, entity_id, server_id, '
      'order_code, ticket_num, created_at, retry_count, last_error, '
      'substr(update_data, 1, 2000) AS update_data '
      'FROM pending_sync_operations ORDER BY id DESC LIMIT ?',
      variables: [Variable.withInt(limit)],
    ).get();
    return {
      'count': count.data['c'],
      'rows': rows.map((r) => r.data).toList(),
    };
  }

  // ── get_logs ────────────────────────────────────────────────────────────

  // Lines the file logger writes carry tokens now and then (a masked one on
  // SSE connect, raw ones in an old Dio dump). Scrub them on the way out.
  static final _bearer = RegExp(r'Bearer\s+[A-Za-z0-9\-_.=]+');
  static final _jwt =
      RegExp(r'eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+');
  static final _secretField = RegExp(
      r'("?(?:password|refreshToken|accessToken|token)"?\s*[:=]\s*)"?[^",\s}]+"?',
      caseSensitive: false);

  static String _clean(String line) => line
      .replaceAll(_bearer, 'Bearer ***')
      .replaceAll(_jwt, '<jwt>')
      .replaceAllMapped(_secretField, (m) => '${m.group(1)}***');

  /// `{limit, level?, source?}` — source `file` (default) tails the app log,
  /// `activity` reads the audit table. `level` filters file lines
  /// (debug / info / warning / error).
  Future<Map<String, dynamic>> _logs(Map<String, dynamic> command) async {
    final limit = ((command['limit'] as num?)?.toInt() ?? 100).clamp(1, 1000);
    final source = (command['source'] as String? ?? 'file').toLowerCase();

    if (source == 'activity') {
      final db = _ref.read(databaseProvider);
      final rows = await db.customSelect(
        'SELECT id, timestamp, user_id, username, action_type, phrase '
        'FROM activity_logs ORDER BY id DESC LIMIT ?',
        variables: [Variable.withInt(limit)],
      ).get();
      return {'source': 'activity', 'rows': rows.map((r) => r.data).toList()};
    }

    final path = logFilePath;
    if (path == null) throw StateError('file logging is not enabled');
    final file = File(path);
    if (!await file.exists()) return {'source': 'file', 'path': path, 'lines': []};

    // Tail only: the file rotates at a few MB, reading all of it for 100
    // lines is waste.
    final length = await file.length();
    const window = 512 * 1024;
    final raf = await file.open();
    List<int> bytes;
    try {
      await raf.setPosition(length > window ? length - window : 0);
      bytes = await raf.read(window);
    } finally {
      await raf.close();
    }
    var lines = const LineSplitter()
        .convert(utf8.decode(bytes, allowMalformed: true));
    if (length > window && lines.isNotEmpty) lines = lines.sublist(1);

    final level = (command['level'] as String?)?.toLowerCase();
    if (level != null && level.isNotEmpty) {
      lines = lines.where((l) => l.toLowerCase().contains('[$level]')).toList();
    }
    if (lines.length > limit) lines = lines.sublist(lines.length - limit);
    return {
      'source': 'file',
      'path': path,
      'lines': lines.map(_clean).toList(),
    };
  }

  // ── diagnostics ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _diagnostics() async {
    final snap = await DiagnosticsService.snapshot()
        .timeout(const Duration(seconds: 10));
    String iso(DateTime? d) => d?.toIso8601String() ?? '';
    return {
      'hostname': snap.hostname,
      'os': snap.os,
      'bootTime': iso(snap.bootTime),
      'tzId': snap.tzId,
      'tzName': snap.tzName,
      'timeServiceRunning': snap.timeServiceRunning,
      'ntpSource': snap.ntpSource,
      'spoolerRunning': snap.spoolerRunning,
      'addresses': snap.addresses,
      'gateways': snap.gateways,
      'dns': snap.dns,
      'adapters': [
        for (final a in snap.adapters)
          {
            'name': a.name,
            'description': a.description,
            'up': a.up,
            'status': a.status,
            'linkSpeed': a.linkSpeed,
            'wireless': a.wireless,
            'virtual': a.virtual,
          }
      ],
      'disks': [
        for (final d in snap.disks)
          {'name': d.name, 'freeBytes': d.freeBytes, 'sizeBytes': d.sizeBytes}
      ],
      'printers': [
        for (final p in snap.printers)
          {
            'name': p.name,
            'port': p.port,
            'jobs': p.jobs,
            'statusFlags': p.statusFlags,
            'driver': p.driver,
          }
      ],
      'wifi': snap.wifi == null
          ? null
          : {
              'connected': snap.wifi!.connected,
              'ssid': snap.wifi!.ssid,
              'signalPercent': snap.wifi!.signalPercent,
              'band': snap.wifi!.band,
              'channel': snap.wifi!.channel,
            },
      'online': _ref.read(isOnlineProvider).valueOrNull,
      'sse': _sseStatus(),
    };
  }
}

extension on RemoteCommandService {
  Map<String, dynamic> _sseStatus() {
    final st = _ref.read(sseServiceProvider).status.value;
    return {
      'state': st.state.name,
      'connectedAt': st.connectedAt?.toIso8601String(),
      'lastFrameAt': st.lastFrameAt?.toIso8601String(),
      'eventCount': st.eventCount,
      'attempts': st.attempts,
      'detail': st.detail,
    };
  }
}

final remoteCommandServiceProvider = Provider<RemoteCommandService>((ref) {
  return RemoteCommandService(ref);
});

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:loggecrea/loggecrea.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../providers/database_providers.dart';
import '../providers/localization_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/app_localizations.dart';
import '../utils/snackbar_helper.dart';
import 'diagnostics_service.dart';
import 'notification_params.dart';

enum WatchKind { internet, backend, router, printer }

class WatchEvent {
  final WatchKind kind;
  final String label;
  final String address;
  final DateTime down;
  final DateTime? up;
  const WatchEvent({
    required this.kind,
    required this.label,
    required this.address,
    required this.down,
    this.up,
  });

  String get id => '${kind.name}|$address';
  Duration duration([DateTime? now]) => (up ?? now ?? DateTime.now()).difference(down);

  WatchEvent closed(DateTime at) =>
      WatchEvent(kind: kind, label: label, address: address, down: down, up: at);

  Map<String, dynamic> toJson() => {
        'k': kind.name,
        'l': label,
        'a': address,
        'd': down.toIso8601String(),
        if (up != null) 'u': up!.toIso8601String(),
      };

  static WatchEvent? fromJson(Map<String, dynamic> j) {
    final kind = WatchKind.values.where((k) => k.name == j['k']).firstOrNull;
    final down = DateTime.tryParse('${j['d']}');
    if (kind == null || down == null) return null;
    return WatchEvent(
      kind: kind,
      label: '${j['l'] ?? ''}',
      address: '${j['a'] ?? ''}',
      down: down,
      up: DateTime.tryParse('${j['u'] ?? ''}'),
    );
  }
}

class WatchSettings {
  final bool enabled;
  final int intervalMinutes;
  final bool notifyOwner;
  final bool alertOnTill;
  const WatchSettings({
    this.enabled = true,
    this.intervalMinutes = 2,
    this.notifyOwner = false,
    this.alertOnTill = true,
  });

  WatchSettings copyWith(
          {bool? enabled, int? intervalMinutes, bool? notifyOwner, bool? alertOnTill}) =>
      WatchSettings(
        enabled: enabled ?? this.enabled,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
        notifyOwner: notifyOwner ?? this.notifyOwner,
        alertOnTill: alertOnTill ?? this.alertOnTill,
      );
}

/// A target checked on every round.
class _Target {
  final WatchKind kind;
  final String label;
  final String address;
  final Future<bool> Function() probe;
  _Target(this.kind, this.label, this.address, this.probe);
  String get id => '${kind.name}|$address';
}

/// Checks the internet, the cloud server, the router and the network
/// printers every few minutes for as long as the app runs, and keeps a
/// 30-day history of every outage — the answer to "the till was slow
/// yesterday at one o'clock".
///
/// An outage counts after two failed checks in a row, so one lost packet
/// is not an alert. The owner hears about internet and router outages once
/// they are over (nothing can leave the shop while they last); printer
/// outages are reported as they start.
class NetworkWatchService extends ChangeNotifier {
  NetworkWatchService(this._ref);

  final Ref _ref;
  Timer? _timer;
  bool _started = false;
  bool _checking = false;
  WatchSettings _settings = const WatchSettings();
  final List<WatchEvent> _events = [];
  final Map<String, int> _fails = {};
  final Map<String, DateTime> _firstFail = {};
  final Map<String, bool> _status = {};
  final Map<String, String> _labels = {};
  DateTime? _lastCheck;
  String? _gateway;
  DateTime? _gatewayAt;

  static const _kEnabled = 'diag_watch_enabled';
  static const _kInterval = 'diag_watch_interval_min';
  static const _kNotify = 'diag_watch_notify_owner';
  static const _kToast = 'diag_watch_toast';
  static const retentionDays = 30;

  WatchSettings get settings => _settings;
  List<WatchEvent> get events => List.unmodifiable(_events.reversed);
  DateTime? get lastCheck => _lastCheck;
  bool get checking => _checking;

  /// Target id → up (true) / down (false); absent until first checked.
  Map<String, bool> get status => Map.unmodifiable(_status);
  String labelOf(String id) => _labels[id] ?? id;

  bool get supported => DiagnosticsService.supported;

  Future<void> start() async {
    if (_started || !supported) return;
    _started = true;
    final prefs = _ref.read(sharedPreferencesProvider);
    _settings = WatchSettings(
      enabled: prefs.getBool(_kEnabled) ?? true,
      intervalMinutes: prefs.getInt(_kInterval) ?? 2,
      notifyOwner: prefs.getBool(_kNotify) ?? false,
      alertOnTill: prefs.getBool(_kToast) ?? true,
    );
    await _load();
    _schedule(firstIn: const Duration(seconds: 30));
  }

  Future<void> updateSettings(WatchSettings s) async {
    final prefs = _ref.read(sharedPreferencesProvider);
    await prefs.setBool(_kEnabled, s.enabled);
    await prefs.setInt(_kInterval, s.intervalMinutes);
    await prefs.setBool(_kNotify, s.notifyOwner);
    await prefs.setBool(_kToast, s.alertOnTill);
    _settings = s;
    _schedule(firstIn: const Duration(seconds: 2));
    notifyListeners();
  }

  void _schedule({required Duration firstIn}) {
    _timer?.cancel();
    if (!_settings.enabled) return;
    _timer = Timer(firstIn, () async {
      await checkNow();
      _timer = Timer.periodic(
          Duration(minutes: _settings.intervalMinutes), (_) => checkNow());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  AppLocalizations get _tillL10n =>
      _ref.read(localizationProvider) ??
      AppLocalizations(Locale(_ref.read(settingsProvider).language));

  AppLocalizations get _ownerL10n =>
      AppLocalizations(Locale(_ref.read(settingsProvider).loggingLanguage));

  Future<List<_Target>> _targets() async {
    final l = _tillL10n;
    final out = <_Target>[
      _Target(WatchKind.internet, l.translate('diag_internet'), 'internet', () async {
        for (final (host, port) in const [('1.1.1.1', 443), ('8.8.8.8', 53)]) {
          final r = await DiagnosticsService.checkTcp(EndpointKind.internet, host, port);
          if (r.ok) return true;
        }
        return false;
      }),
    ];

    if (_gateway == null ||
        _gatewayAt == null ||
        DateTime.now().difference(_gatewayAt!) > const Duration(minutes: 10)) {
      _gateway = await DiagnosticsService.defaultGateway() ?? _gateway;
      _gatewayAt = DateTime.now();
    }
    final gw = _gateway;
    if (gw != null) {
      out.add(_Target(WatchKind.router, l.translate('diag_gateway'), gw,
          () async => await DiagnosticsService.pingOnce(gw) != null));
    }

    final raw = _ref.read(sharedPreferencesProvider).getString('api_base_url');
    final uri = raw == null ? null : Uri.tryParse(raw.trim());
    if (uri != null && uri.hasScheme) {
      final url = '${uri.origin}/';
      out.add(_Target(WatchKind.backend, l.translate('diag_backend'), uri.host,
          () async => (await DiagnosticsService.checkHttp(EndpointKind.backend, url)).ok));
    }

    final printing = _ref.read(printingServiceProvider);
    final c = printing.config;
    final seen = <String>{};
    void printer(String label, String? address, ConnectionType? type) {
      final a = (address ?? '').trim();
      if (type != ConnectionType.NETWORK || a.isEmpty || !seen.add(a)) return;
      final parts = a.split(':');
      final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 9100 : 9100;
      out.add(_Target(WatchKind.printer, label, a, () async {
        final r = await DiagnosticsService.checkTcp(EndpointKind.custom, parts[0], port);
        return r.ok;
      }));
    }

    printer(l.translate('diag_receipt_printer'), c.receiptPrinterAddress,
        c.receiptConnectionType);
    if (c.kdsEnabled) {
      printer(l.translate('diag_kitchen_printer'), c.kdsPrinterAddress, c.kdsConnectionType);
    }
    for (final pp in printing.printerPool) {
      printer(pp.label.isNotEmpty ? pp.label : pp.name, pp.address, pp.connectionType);
    }
    return out;
  }

  Future<void> checkNow() async {
    if (_checking || !supported) return;
    _checking = true;
    notifyListeners();
    try {
      final targets = await _targets();
      final results = <String, bool>{};
      // Internet first: when it is down the cloud server is down too, and
      // one alert says it all.
      final internet = targets.firstWhere((t) => t.kind == WatchKind.internet);
      results[internet.id] = await internet.probe();
      await Future.wait([
        for (final t in targets)
          if (t.kind != WatchKind.internet &&
              !(t.kind == WatchKind.backend && results[internet.id] == false))
            () async {
              results[t.id] = await t.probe();
            }(),
      ]);

      final now = DateTime.now();
      for (final t in targets) {
        _labels[t.id] = t.label;
        final ok = results[t.id];
        if (ok == null) continue;
        if (ok) {
          _fails.remove(t.id);
          _firstFail.remove(t.id);
          if (_status[t.id] == false) _recovered(t, now);
          _status[t.id] = true;
        } else {
          _firstFail.putIfAbsent(t.id, () => now);
          final n = (_fails[t.id] ?? 0) + 1;
          _fails[t.id] = n;
          if (n >= 2 && _status[t.id] != false) {
            _status[t.id] = false;
            _wentDown(t, _firstFail[t.id]!, internetUp: results[internet.id] == true);
          }
        }
      }
      // Targets no longer configured must not stay "down" forever.
      final ids = {for (final t in targets) t.id};
      for (var i = 0; i < _events.length; i++) {
        final e = _events[i];
        if (e.up == null && !ids.contains(e.id)) _events[i] = e.closed(now);
      }
      _status.removeWhere((id, _) => !ids.contains(id));
      _lastCheck = now;
      await _save();
    } catch (e) {
      Logger.instance.warning('network watch check failed: $e');
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  void _wentDown(_Target t, DateTime since, {required bool internetUp}) {
    _events.add(WatchEvent(kind: t.kind, label: t.label, address: t.address, down: since));
    final l = _tillL10n;
    if (_settings.alertOnTill) {
      SnackBarHelper.showToast(
        l.translate('watch_down').replaceAll('{name}', _name(t)),
        kind: ToastKind.error,
        duration: const Duration(seconds: 8),
      );
    }
    if (t.kind == WatchKind.printer && internetUp) {
      final o = _ownerL10n;
      _notifyOwner(
        o.translate('watch_owner_printer_down').replaceAll('{name}', _name(t, o)),
        o.translate('watch_owner_since').replaceAll('{time}', _hm(since)),
      );
    }
  }

  void _recovered(_Target t, DateTime at) {
    final i = _events.lastIndexWhere((e) => e.id == t.id && e.up == null);
    if (i < 0) return;
    final e = _events[i].closed(at);
    _events[i] = e;
    final minutes = e.duration().inMinutes;
    if (_settings.alertOnTill) {
      SnackBarHelper.showToast(
        _tillL10n
            .translate('watch_back')
            .replaceAll('{name}', _name(t))
            .replaceAll('{minutes}', '$minutes'),
        kind: ToastKind.success,
      );
    }
    final o = _ownerL10n;
    _notifyOwner(
      o.translate('watch_owner_outage').replaceAll('{name}', _name(t, o)),
      o
          .translate('watch_owner_outage_body')
          .replaceAll('{from}', _hm(e.down))
          .replaceAll('{to}', _hm(at))
          .replaceAll('{minutes}', '$minutes'),
    );
  }

  String _name(_Target t, [AppLocalizations? l]) => t.kind == WatchKind.printer
      ? '${t.label} (${t.address})'
      : (l == null
          ? t.label
          : l.translate(switch (t.kind) {
              WatchKind.internet => 'diag_internet',
              WatchKind.backend => 'diag_backend',
              WatchKind.router => 'diag_gateway',
              WatchKind.printer => 'diag_printers',
            }));

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Sent straight, like every GENERAL message: a stale alert is noise.
  void _notifyOwner(String title, String body) {
    if (!_settings.notifyOwner) return;
    unawaited(() async {
      try {
        final api = _ref.read(apiServiceProvider);
        await api.postNotification(
          type: 'GENERAL',
          params: NotificationParams.general(
            terminalName: api.getPosName() ?? '',
            title: title,
            body: body,
          ),
        );
      } catch (e) {
        Logger.instance.warning('network watch notification failed: $e');
      }
    }());
  }

  /// Total downtime and outage count for [kind] over the last [window].
  (Duration, int) downtime(WatchKind kind, Duration window) {
    final now = DateTime.now();
    final from = now.subtract(window);
    var total = Duration.zero;
    var count = 0;
    for (final e in _events) {
      if (e.kind != kind) continue;
      final end = e.up ?? now;
      if (end.isBefore(from)) continue;
      final start = e.down.isBefore(from) ? from : e.down;
      total += end.difference(start);
      count++;
    }
    return (total, count);
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'network_watch.json'));
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final list = jsonDecode(await f.readAsString()) as List;
      _events
        ..clear()
        ..addAll(list
            .whereType<Map<String, dynamic>>()
            .map(WatchEvent.fromJson)
            .whereType<WatchEvent>());
      // An outage still open at shutdown is closed at the last check that
      // saved the file; the first check opens a fresh one if it goes on.
      final lastSeen = f.lastModifiedSync();
      for (var i = 0; i < _events.length; i++) {
        final e = _events[i];
        if (e.up == null) {
          _events[i] = e.closed(lastSeen.isAfter(e.down) ? lastSeen : e.down);
        }
      }
    } catch (e) {
      Logger.instance.warning('network watch history unreadable: $e');
    }
  }

  Future<void> _save() async {
    try {
      final cutoff = DateTime.now().subtract(const Duration(days: retentionDays));
      _events.removeWhere((e) => e.up != null && e.up!.isBefore(cutoff));
      final f = await _file();
      await f.writeAsString(jsonEncode([for (final e in _events) e.toJson()]));
    } catch (e) {
      Logger.instance.warning('network watch history not saved: $e');
    }
  }

  Future<void> clearHistory() async {
    _events.removeWhere((e) => e.up != null);
    await _save();
    notifyListeners();
  }
}

final networkWatchProvider = Provider<NetworkWatchService>((ref) {
  final s = NetworkWatchService(ref);
  ref.onDispose(s.dispose);
  if (!kIsWeb) unawaited(s.start());
  return s;
});

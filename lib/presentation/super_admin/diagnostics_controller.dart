import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_thermal_printer/utils/printer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/diagnostics_service.dart';
import '../../services/printing_service.dart';
import '../../utils/app_localizations.dart';

/// The pages of the diagnostics tab, in menu order.
enum DiagPage { overview, system, network, wifi, devices, cameras, printers, traffic, tools, watch }

enum Severity { error, warning }

/// Something that repairs a problem, offered as a button next to it.
class DiagAction {
  final String labelKey;
  final Future<void> Function() run;
  const DiagAction(this.labelKey, this.run);
}

class DiagIssue {
  final Severity severity;
  final DiagPage page;
  final String titleKey;
  final String detail;
  final DiagAction? action;
  const DiagIssue(this.severity, this.page, this.titleKey, this.detail, [this.action]);
}

/// A printer the POS is configured to use, checked against reality.
class PrinterCheck {
  final String label;
  final String address;
  final ConnectionType type;
  final PrinterPurpose? purpose;
  final NamedPrinter? pooled;
  final NetworkPrinterStatus? network;
  final OsPrinter? spooler;
  const PrinterCheck({
    required this.label,
    required this.address,
    required this.type,
    this.purpose,
    this.pooled,
    this.network,
    this.spooler,
  });

  String get host => address.split(':').first.trim();
  int get port {
    final parts = address.split(':');
    return parts.length > 1 ? int.tryParse(parts[1]) ?? 9100 : 9100;
  }

  /// Localization keys of what is wrong; empty when it looks fine.
  List<String> get problems {
    if (type == ConnectionType.NETWORK) {
      final n = network;
      if (n == null) return const [];
      return [
        if (!n.reachable) 'diag_printer_unreachable',
        if (n.offline) 'diag_printer_offline',
        if (n.paperOut) 'diag_paper_out',
        if (!n.paperOut && n.paperLow) 'diag_paper_low',
      ];
    }
    if (type == ConnectionType.USB && Platform.isWindows) {
      final s = spooler;
      if (s == null) return const ['diag_printer_not_installed'];
      return [...s.problems, if (s.jobs >= stuckJobs) 'diag_jobs_stuck'];
    }
    return const [];
  }
}

/// Queued jobs at which a receipt printer's queue counts as stuck: a till
/// prints in a second, so a handful waiting means nothing is coming out.
const stuckJobs = 3;

/// A configured network printer now answering at another address: same MAC,
/// new IP — what DHCP does to printers left without a fixed address.
class PrinterMove {
  final PrinterCheck printer;
  final String newIp;
  const PrinterMove(this.printer, this.newIp);
}

/// An address whose device changed between two scans.
class IpChange {
  final String ip;
  final String before;
  final String now;
  const IpChange(this.ip, this.before, this.now);
}

/// State and actions shared by every diagnostics page, so a scan done on
/// one page feeds the printer helper, the camera list and the report.
class DiagnosticsController extends ChangeNotifier {
  DiagnosticsController({
    required this.prefs,
    required this.printing,
    required this.lanPort,
  }) {
    _vendors.addAll(_readMap(_kVendorCache));
    _macHistory.addAll(_readMap(_kMacHistory));
  }

  final SharedPreferences prefs;
  final PrintingService printing;
  final int lanPort;

  static const _kVendorCache = 'diag_mac_vendors_v1';
  static const _kLastScan = 'diag_last_scan_v1';
  static const _kMacHistory = 'diag_mac_history_v1';

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    cancelScan = true;
    super.dispose();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  String? get backendUrl {
    final raw = prefs.getString('api_base_url');
    if (raw == null || raw.trim().isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasScheme) return null;
    return '${uri.origin}/';
  }

  // ------------------------------------------------------------ full check

  bool running = false;
  DateTime? ranAt;
  SystemSnapshot? snap;
  List<EndpointResult> endpoints = const [];
  ClockCheck? clock;
  bool clockChecked = false;
  List<PrinterCheck> printers = const [];
  List<IpConflictEvent> conflictEvents = const [];
  String? fixing;

  String? get gateway => snap?.gateways.firstOrNull;

  Future<void> runAll(AppLocalizations l) async {
    if (running) return;
    running = true;
    _changed();
    try {
      final s = await DiagnosticsService.snapshot();
      snap = s;
      _changed();
      final backend = backendUrl;
      final gw = s.gateways.firstOrNull;
      final results = await Future.wait<Object?>([
        Future.wait([
          if (gw != null) DiagnosticsService.checkPing(EndpointKind.gateway, gw),
          DiagnosticsService.checkDns(),
          DiagnosticsService.checkHttp(
              EndpointKind.internet, 'https://speed.cloudflare.com/cdn-cgi/trace'),
          if (backend != null) DiagnosticsService.checkHttp(EndpointKind.backend, backend),
          DiagnosticsService.checkHttp(EndpointKind.updates, 'https://updates.caisse212.com/'),
          DiagnosticsService.checkTcp(EndpointKind.lanServer, '127.0.0.1', lanPort),
        ]),
        DiagnosticsService.checkClock(fallbackUrl: backend),
        checkPrinters(l, s),
        DiagnosticsService.ipConflictEvents(),
      ]);
      endpoints = results[0] as List<EndpointResult>;
      clock = results[1] as ClockCheck?;
      clockChecked = true;
      printers = results[2] as List<PrinterCheck>;
      conflictEvents = results[3] as List<IpConflictEvent>;
      ranAt = DateTime.now();
    } finally {
      running = false;
      _changed();
    }
  }

  Future<List<PrinterCheck>> checkPrinters(AppLocalizations l, SystemSnapshot s) async {
    final c = printing.config;
    final targets = <PrinterCheck>[];
    final seen = <String>{};
    void add(String label, String? address, String? name, ConnectionType? type,
        {PrinterPurpose? purpose, NamedPrinter? pooled}) {
      final addr =
          (address ?? '').trim().isNotEmpty ? address!.trim() : (name ?? '').trim();
      if (addr.isEmpty || type == null) return;
      if (!seen.add('${type.name}|${addr.toLowerCase()}')) return;
      targets.add(PrinterCheck(
          label: label, address: addr, type: type, purpose: purpose, pooled: pooled));
    }

    add(l.translate('diag_receipt_printer'), c.receiptPrinterAddress, c.receiptPrinterName,
        c.receiptConnectionType,
        purpose: PrinterPurpose.receipt);
    if (c.kdsEnabled) {
      add(l.translate('diag_kitchen_printer'), c.kdsPrinterAddress, c.kdsPrinterName,
          c.kdsConnectionType,
          purpose: PrinterPurpose.kds);
    }
    for (final p in printing.printerPool) {
      add(p.label.isNotEmpty ? p.label : p.name, p.address, p.name, p.connectionType,
          pooled: p);
    }

    return Future.wait([
      for (final t in targets)
        () async {
          if (t.type == ConnectionType.NETWORK) {
            return PrinterCheck(
              label: t.label,
              address: t.address,
              type: t.type,
              purpose: t.purpose,
              pooled: t.pooled,
              network: await DiagnosticsService.probeNetworkPrinter(t.address),
            );
          }
          final key = t.address.toLowerCase();
          return PrinterCheck(
            label: t.label,
            address: t.address,
            type: t.type,
            purpose: t.purpose,
            pooled: t.pooled,
            spooler: s.printers.where((p) => p.name.toLowerCase() == key).firstOrNull,
          );
        }(),
    ]);
  }

  /// Runs a repair, then checks everything again.
  Future<void> fix(String key, Future<void> Function() run, AppLocalizations l) async {
    if (fixing != null) return;
    fixing = key;
    _changed();
    try {
      await run();
      await runAll(l);
    } finally {
      fixing = null;
      _changed();
    }
  }

  // ------------------------------------------------------------- speed test

  SpeedResult? speed;
  String? speedPhase;
  double? speedLive;

  Future<void> runSpeedTest() async {
    speed = null;
    speedPhase = 'latency';
    speedLive = null;
    _changed();
    final r = await DiagnosticsService.speedTest(onProgress: (phase, mbps) {
      speedPhase = phase;
      speedLive = mbps;
      _changed();
    });
    speed = r;
    speedPhase = null;
    _changed();
  }

  // ------------------------------------------------------------------- scan

  List<ScanTarget> scanTargets = const [];
  ScanTarget? scanTarget;
  bool scanning = false;
  bool identifying = false;
  bool cancelScan = false;
  int scanDone = 0;
  int scanTotal = 0;
  List<LanHost>? hosts;
  DateTime? scannedAt;
  Set<String> newDevices = const {};
  List<IpChange> ipChanges = const [];
  final Map<String, String> _vendors = {};
  final Map<String, String> _macHistory = {};

  static const portNames = {
    9100: 'printer',
    515: 'LPD',
    631: 'IPP',
    80: 'HTTP',
    443: 'HTTPS',
    8080: 'HTTP',
    22: 'SSH',
    139: 'NetBIOS',
    445: 'SMB',
    3389: 'RDP',
    554: 'RTSP',
    8000: 'camera',
    37777: 'Dahua',
    34567: 'DVR',
    8899: 'ONVIF',
    62078: 'iOS',
    7000: 'AirPlay',
    8009: 'Cast',
  };

  Map<String, String> _readMap(String key) {
    try {
      final raw = prefs.getString(key);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  Future<void> loadScanTargets() async {
    scanTargets = await DiagnosticsService.scanTargets();
    pickDefaultTarget();
  }

  void pickDefaultTarget() {
    // Never swap the subnet under a scan, or under results already shown.
    if (scanning || hosts != null) return;
    final gw = gateway;
    String net(String ip) => ip.substring(0, ip.lastIndexOf('.'));
    final match =
        gw == null ? null : scanTargets.where((t) => net(t.address) == net(gw)).firstOrNull;
    scanTarget = match ?? scanTarget ?? scanTargets.firstOrNull;
    _changed();
  }

  void selectTarget(ScanTarget? t) {
    scanTarget = t;
    _changed();
  }

  String keyOf(LanHost h) => h.mac ?? h.ip;

  String get subnetPrefix {
    final a = scanTarget!.address;
    return a.substring(0, a.lastIndexOf('.') + 1);
  }

  LanHost _withVendor(LanHost h) {
    final m = h.mac;
    if (m == null || m.length < 8) return h;
    final v = _vendors[m.substring(0, 8).toUpperCase()];
    return v == null || v.isEmpty ? h : h.copyWith(vendor: v);
  }

  Future<void> scan() async {
    final t = scanTarget;
    if (t == null || scanning) return;
    scanning = true;
    cancelScan = false;
    scanDone = 0;
    scanTotal = 254;
    _changed();
    try {
      var found = await DiagnosticsService.scanLan(
        self: t.address,
        ports: {...portNames.keys, lanPort}.toList(),
        gateway: gateway,
        cancelled: () => cancelScan,
        onProgress: (d, total) {
          if (d % 8 == 0 || d == total) {
            scanDone = d;
            scanTotal = total;
            _changed();
          }
        },
      );
      hosts = [for (final h in found) _withVendor(h)];
      scanning = false;
      identifying = true;
      _changed();
      found = await DiagnosticsService.identifyHosts(hosts!, lanPort);
      hosts = found;
      scannedAt = DateTime.now();
      _compareWithHistory(found, t.subnet);
    } finally {
      scanning = false;
      identifying = false;
      _changed();
    }

    await DiagnosticsService.lookupVendors(
      hosts!.map((h) => h.mac).whereType<String>(),
      _vendors,
      cancelled: () => cancelScan || _disposed,
      onFound: (_, __) {
        hosts = [for (final h in hosts!) _withVendor(h)];
        _changed();
      },
    );
    await prefs.setString(_kVendorCache, jsonEncode(_vendors));
  }

  /// NEW devices (absent from every earlier scan of the subnet) and
  /// addresses now answered by a different device than before.
  void _compareWithHistory(List<LanHost> found, String subnet) {
    Map<String, dynamic> all = {};
    try {
      all = jsonDecode(prefs.getString(_kLastScan) ?? '{}') as Map<String, dynamic>;
    } catch (_) {}
    final before = (all[subnet] as List?)?.map((e) => '$e').toSet();
    final now = {for (final h in found) keyOf(h)};
    newDevices = before == null ? const {} : now.difference(before);
    all[subnet] = [...{...?before, ...now}];
    prefs.setString(_kLastScan, jsonEncode(all));

    final changes = <IpChange>[];
    for (final h in found) {
      final mac = h.mac;
      if (mac == null || h.isSelf) continue;
      final old = _macHistory[h.ip];
      if (old != null && old != mac) changes.add(IpChange(h.ip, old, mac));
      _macHistory[h.ip] = mac;
    }
    // Remember where each MAC was last seen too, to follow moved printers.
    ipChanges = changes;
    prefs.setString(_kMacHistory, jsonEncode(_macHistory));
  }

  /// Configured network printers whose MAC now answers at another IP.
  List<PrinterMove> get printerMoves {
    final hs = hosts;
    if (hs == null) return const [];
    final out = <PrinterMove>[];
    for (final p in printers.where((p) => p.type == ConnectionType.NETWORK)) {
      final atOld = hs.where((h) => h.ip == p.host).firstOrNull;
      if (atOld != null && atOld.openPorts.contains(p.port)) continue;
      final mac = _previousMacOf(p.host);
      if (mac == null) continue;
      final moved = hs.where((h) => h.mac == mac && h.ip != p.host).firstOrNull;
      if (moved != null) out.add(PrinterMove(p, moved.ip));
    }
    return out;
  }

  /// The MAC this address had before the latest scan overwrote it.
  String? _previousMacOf(String ip) {
    final change = ipChanges.where((c) => c.ip == ip).firstOrNull;
    return change?.before ?? _macHistory[ip];
  }

  /// Configured printer addresses now held by something that is not a
  /// printer: an address conflict, or the printer moved and another device
  /// took its old address.
  List<(PrinterCheck, LanHost)> get printerAddressTaken {
    final hs = hosts;
    if (hs == null) return const [];
    return [
      for (final p in printers.where((p) => p.type == ConnectionType.NETWORK))
        if (hs.where((h) => h.ip == p.host).firstOrNull case final h?)
          if (!h.openPorts.contains(p.port) && h.kind != DeviceKind.printer && !h.isSelf)
            (p, h),
    ];
  }

  /// Points every POS printer using [oldHost] at [newIp], keeping the port.
  Future<void> retargetPrinter(String oldHost, String newIp) async {
    String moved(String a) {
      final parts = a.split(':');
      return parts.length > 1 ? '$newIp:${parts[1]}' : newIp;
    }

    bool matches(String? a) => a != null && a.split(':').first.trim() == oldHost;
    var c = printing.config;
    if (matches(c.receiptPrinterAddress) && c.receiptConnectionType == ConnectionType.NETWORK) {
      c = c.copyWith(receiptPrinterAddress: moved(c.receiptPrinterAddress!));
    }
    if (matches(c.kdsPrinterAddress) && c.kdsConnectionType == ConnectionType.NETWORK) {
      c = c.copyWith(kdsPrinterAddress: moved(c.kdsPrinterAddress!));
    }
    await printing.saveConfig(prefs, c);
    final pool = [
      for (final p in printing.printerPool)
        p.connectionType == ConnectionType.NETWORK && matches(p.address)
            ? p.copyWith(address: moved(p.address))
            : p,
    ];
    await printing.savePrinterPool(prefs, pool);
  }

  /// Makes a printer found on the network the POS receipt or kitchen printer.
  Future<void> usePrinter(String ip, PrinterPurpose purpose, String name) =>
      printing.setPrinter(
        prefs,
        Printer(
          name: name,
          address: '$ip:${DiagnosticsService.printerPort}',
          connectionType: ConnectionType.NETWORK,
          isConnected: false,
        ),
        purpose,
      );

  /// Unused addresses near the top of the range: routers usually hand out
  /// DHCP leases from the bottom, so the top is the safest place for a
  /// fixed IP.
  List<String> freeForStatic([int count = 6]) {
    final hs = hosts;
    if (hs == null || scanTarget == null) return const [];
    final used = {for (final h in hs) h.ip};
    return [
      for (var i = 250; i >= 200; i--)
        if (!used.contains('$subnetPrefix$i')) '$subnetPrefix$i'
    ].take(count).toList();
  }

  // ---------------------------------------------------------------- issues

  List<DiagIssue> issues(AppLocalizations l) {
    final s = snap;
    if (s == null) return const [];
    final out = <DiagIssue>[];
    EndpointResult? ep(EndpointKind k) => endpoints.where((e) => e.kind == k).firstOrNull;
    DiagAction act(String key, Future<void> Function() run) =>
        DiagAction(key, () => fix(key, run, l));

    final physical = s.physicalAdapters;
    if (physical.isNotEmpty && !physical.any((a) => a.up)) {
      out.add(DiagIssue(Severity.error, DiagPage.network, 'diag_issue_no_network',
          l.translate('diag_issue_no_network_hint')));
    }
    final wifi = s.wifi;
    if (wifi != null && wifi.connected && (wifi.signalPercent ?? 100) < 50) {
      out.add(DiagIssue(
          (wifi.signalPercent ?? 100) < 30 ? Severity.error : Severity.warning,
          DiagPage.network,
          'diag_issue_weak_wifi',
          '${wifi.ssid} — ${wifi.signalPercent}% · ${l.translate('diag_issue_weak_wifi_hint')}'));
    }
    if (s.gateways.isEmpty && physical.any((a) => a.up)) {
      out.add(DiagIssue(Severity.error, DiagPage.network, 'diag_issue_no_gateway',
          l.translate('diag_issue_no_gateway_hint'),
          act('diag_renew_ip', DiagnosticsService.renewIp)));
    }
    final gw = ep(EndpointKind.gateway);
    if (gw != null && !gw.ok) {
      out.add(DiagIssue(Severity.warning, DiagPage.network, 'diag_issue_gateway_silent',
          '${gw.target} · ${l.translate('diag_issue_gateway_silent_hint')}'));
    }
    final dns = ep(EndpointKind.dns);
    final internet = ep(EndpointKind.internet);
    if (internet != null && !internet.ok) {
      out.add(DiagIssue(Severity.error, DiagPage.network, 'diag_issue_no_internet',
          internet.detail,
          dns != null && !dns.ok ? act('diag_flush_dns', DiagnosticsService.flushDns) : null));
    } else if (dns != null && !dns.ok) {
      out.add(DiagIssue(Severity.error, DiagPage.network, 'diag_issue_dns', dns.detail,
          act('diag_flush_dns', DiagnosticsService.flushDns)));
    }
    final backend = ep(EndpointKind.backend);
    if (backend != null && !backend.ok) {
      out.add(DiagIssue(Severity.error, DiagPage.network, 'diag_issue_backend',
          '${backend.target} · ${backend.detail}'));
    } else if (backend != null && (backend.latencyMs ?? 0) > 1500) {
      out.add(DiagIssue(Severity.warning, DiagPage.network, 'diag_issue_backend_slow',
          '${backend.target} · ${backend.latencyMs} ms'));
    }
    final lan = ep(EndpointKind.lanServer);
    if (lan != null && !lan.ok) {
      out.add(DiagIssue(Severity.warning, DiagPage.network, 'diag_issue_lan_server',
          l.translate('diag_issue_lan_server_hint').replaceAll('{port}', '$lanPort')));
    }

    final c = clock;
    if (c != null && c.skew.abs() > const Duration(seconds: 30)) {
      out.add(DiagIssue(
          c.skew.abs() > const Duration(minutes: 2) ? Severity.error : Severity.warning,
          DiagPage.system,
          'diag_issue_clock',
          '${formatSkew(c.skew)} · ${l.translate('diag_issue_clock_hint')}',
          act('diag_sync_clock', DiagnosticsService.syncClock)));
    }
    if (s.timeServiceRunning == false) {
      out.add(DiagIssue(Severity.warning, DiagPage.system, 'diag_issue_time_service',
          l.translate('diag_issue_time_service_hint'),
          act('diag_sync_clock', DiagnosticsService.syncClock)));
    }
    for (final d in s.disks) {
      if (d.sizeBytes > 0 && (d.freeBytes < 2 * 1024 * 1024 * 1024 || d.freeFraction < 0.05)) {
        out.add(DiagIssue(Severity.warning, DiagPage.system, 'diag_issue_disk',
            '${d.name} · ${formatBytes(d.freeBytes)} / ${formatBytes(d.sizeBytes)}'));
      }
    }

    if (s.spoolerRunning == false) {
      out.add(DiagIssue(Severity.error, DiagPage.printers, 'diag_issue_spooler',
          l.translate('diag_issue_spooler_hint'),
          act('diag_restart_spooler', DiagnosticsService.restartSpooler)));
    }
    final moves = printerMoves;
    for (final p in printers) {
      final problems = p.problems;
      if (problems.isEmpty) continue;
      final move = moves.where((m) => m.printer.address == p.address).firstOrNull;
      out.add(DiagIssue(
          Severity.error,
          DiagPage.printers,
          move != null ? 'diag_issue_printer_moved' : 'diag_issue_printer',
          move != null
              ? '${p.label}: ${p.host} → ${move.newIp}'
              : '${p.label} (${p.address}) · ${problems.map(l.translate).join(', ')}',
          move != null
              ? act('diag_update_pos_printer', () => retargetPrinter(p.host, move.newIp))
              : problems.contains('diag_jobs_stuck')
                  ? act('diag_clear_queues', DiagnosticsService.clearPrintQueues)
                  : null));
    }
    for (final (p, h) in printerAddressTaken) {
      out.add(DiagIssue(Severity.error, DiagPage.devices, 'diag_issue_printer_ip_taken',
          '${p.label} (${p.host}) → ${kindName(l, h)}${h.vendor != null ? ' · ${h.vendor}' : ''}'));
    }
    final stuck = s.printers
        .where((p) =>
            !p.isVirtual &&
            p.jobs >= stuckJobs &&
            !printers.any((c) => c.spooler?.name == p.name))
        .toList();
    if (stuck.isNotEmpty) {
      out.add(DiagIssue(Severity.warning, DiagPage.printers, 'diag_issue_stuck_queues',
          stuck.map((p) => '${p.name}: ${p.jobs}').join(' · '),
          act('diag_clear_queues', DiagnosticsService.clearPrintQueues)));
    }

    final recent = conflictEvents
        .where((e) => DateTime.now().difference(e.at) < const Duration(days: 7))
        .toList();
    if (recent.isNotEmpty) {
      out.add(DiagIssue(Severity.error, DiagPage.devices, 'diag_issue_ip_conflict',
          '${formatDateTime(recent.first.at)} · ${recent.first.message}'));
    }
    if (ipChanges.isNotEmpty) {
      out.add(DiagIssue(Severity.warning, DiagPage.devices, 'diag_issue_ip_changed',
          ipChanges.map((c) => '${c.ip}: ${c.before} → ${c.now}').join(' · ')));
    }
    out.sort((a, b) => a.severity.index.compareTo(b.severity.index));
    return out;
  }

  // ---------------------------------------------------------------- report

  String report(AppLocalizations l, {String? watchSummary}) {
    final s = snap;
    final b = StringBuffer()
      ..writeln('caisse212 — ${l.translate('diagnostics')}')
      ..writeln(formatDateTime(DateTime.now()));
    if (s != null) {
      b
        ..writeln()
        ..writeln('# ${l.translate('diag_system')}')
        ..writeln('${l.translate('diag_hostname')}: ${s.hostname}')
        ..writeln('${l.translate('diag_os')}: ${s.os}')
        ..writeln('${l.translate('diag_timezone')}: ${s.tzId} '
            '(UTC${formatOffset(DateTime.now().timeZoneOffset)})');
      if (clock != null) {
        b.writeln('${l.translate('diag_clock_offset')}: ${formatSkew(clock!.skew)} (${clock!.source})');
      }
      for (final d in s.disks) {
        b.writeln('${l.translate('diag_disk')} ${d.name}: ${formatBytes(d.freeBytes)} / ${formatBytes(d.sizeBytes)}');
      }
      b
        ..writeln()
        ..writeln('# ${l.translate('diag_network')}');
      for (final a in s.physicalAdapters) {
        b.writeln('${a.name}: ${a.status} ${a.linkSpeed} ${a.mac} '
            '${(s.addresses[a.name] ?? const []).join(', ')}');
      }
      b
        ..writeln('${l.translate('diag_gateway')}: ${s.gateways.join(', ')}')
        ..writeln('DNS: ${s.dns.join(', ')}');
      final w = s.wifi;
      if (w != null && w.connected) {
        b.writeln('Wi-Fi: ${w.ssid} ${w.signalPercent}% ${w.band} ch${w.channel ?? '?'} '
            '${w.receiveMbps ?? '?'}/${w.transmitMbps ?? '?'} Mbps ${w.radio}');
      }
    }
    for (final e in endpoints) {
      b.writeln('${l.translate(endpointKey(e.kind))} ${e.target}: '
          '${e.ok ? 'OK ${e.latencyMs} ms' : 'FAIL ${e.detail}'}');
    }
    if (speed != null && speed!.error == null) {
      b.writeln('${l.translate('diag_speed_test')}: '
          '↓ ${speed!.downloadMbps?.toStringAsFixed(1)} Mbps '
          '↑ ${speed!.uploadMbps?.toStringAsFixed(1)} Mbps ${speed!.latencyMs} ms');
    }
    if (printers.isNotEmpty) {
      b
        ..writeln()
        ..writeln('# ${l.translate('diag_printers')}');
      for (final p in printers) {
        final probs = p.problems;
        b.writeln('${p.label} (${p.address}): '
            '${probs.isEmpty ? 'OK' : probs.map(l.translate).join(', ')}');
      }
    }
    final hs = hosts;
    if (hs != null) {
      b
        ..writeln()
        ..writeln('# ${l.translate('diag_lan_scan')} (${scanTarget?.subnet})')
        ..writeln('${l.translate('diag_ips_used')}: ${hs.length} / 254');
      for (final h in hs) {
        b.writeln('${h.ip}  ${kindName(l, h)}  ${h.mac ?? ''}  ${h.vendor ?? ''}  '
            '${h.hostname ?? ''}  ${h.openPorts.join(',')}');
      }
    }
    if (watchSummary != null) {
      b
        ..writeln()
        ..writeln('# ${l.translate('diag_watch')}')
        ..writeln(watchSummary);
    }
    final iss = issues(l);
    b
      ..writeln()
      ..writeln('# ${l.translate('diag_problems')}: ${iss.length}');
    for (final i in iss) {
      b.writeln('- ${l.translate(i.titleKey)}: ${i.detail}');
    }
    return b.toString();
  }
}

// ------------------------------------------------------------ formatting

String endpointKey(EndpointKind k) => switch (k) {
      EndpointKind.gateway => 'diag_gateway',
      EndpointKind.dns => 'diag_dns',
      EndpointKind.internet => 'diag_internet',
      EndpointKind.backend => 'diag_backend',
      EndpointKind.updates => 'diag_updates_server',
      EndpointKind.lanServer => 'diag_lan_server',
      EndpointKind.custom => 'diag_tools',
    };

String kindName(AppLocalizations l, LanHost h) => l.translate('diag_kind_${h.kind.name}');

String formatSkew(Duration d) {
  final sign = d.isNegative ? '−' : '+';
  final s = d.abs().inSeconds;
  if (s < 60) return '$sign$s s';
  if (s < 3600) return '$sign${s ~/ 60} min ${s % 60} s';
  return '$sign${s ~/ 3600} h ${(s % 3600) ~/ 60} min';
}

String formatOffset(Duration d) {
  final sign = d.isNegative ? '-' : '+';
  final m = d.abs().inMinutes;
  return '$sign${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

String formatUptime(Duration d) {
  if (d.inDays > 0) return '${d.inDays} d ${d.inHours % 24} h';
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inMinutes} min';
}

String formatDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

String formatDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}

/// Bytes per second as a network speed: 12.3 Mbps.
String formatRate(double bytesPerSecond) {
  final bits = bytesPerSecond * 8;
  if (bits >= 1e6) return '${(bits / 1e6).toStringAsFixed(1)} Mbps';
  if (bits >= 1e3) return '${(bits / 1e3).toStringAsFixed(0)} kbps';
  return '${bits.toStringAsFixed(0)} bps';
}

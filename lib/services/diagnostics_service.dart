import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

/// Machine, network and printer checks for the super admin screen.
///
/// Everything here reads the OS through its own tools (PowerShell / netsh on
/// Windows, ip / nmcli / timedatectl on Linux) because Dart's `dart:io` sees
/// neither Wi-Fi, routes, the clock service nor the print spooler.
class DiagnosticsService {
  DiagnosticsService._();

  static bool get supported => Platform.isWindows || Platform.isLinux;

  /// Host names and IPs typed by a person go on a command line.
  static final RegExp hostPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9.\-:]{0,252}$');

  // ---------------------------------------------------------------- snapshot

  static Future<SystemSnapshot> snapshot() async {
    final results = await Future.wait([
      Platform.isWindows ? _windowsSnapshot() : _linuxSnapshot(),
      _interfaceAddresses(),
      wifi(),
    ]);
    final snap = results[0] as SystemSnapshot;
    return snap.copyWith(
      addresses: results[1] as Map<String, List<String>>,
      wifi: results[2] as WifiInfo?,
    );
  }

  static Future<Map<String, List<String>>> _interfaceAddresses() async {
    final out = <String, List<String>>{};
    try {
      for (final i in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false)) {
        out[i.name] = [for (final a in i.addresses) a.address];
      }
    } catch (_) {}
    return out;
  }

  static const _windowsSnapshotScript = r'''
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$os = Get-CimInstance Win32_OperatingSystem
$tz = Get-TimeZone
$r = [ordered]@{
  os = "$($os.Caption) $($os.Version)"
  bootTime = if ($os.LastBootUpTime) { $os.LastBootUpTime.ToUniversalTime().ToString('o') } else { $null }
  tzId = $tz.Id
  tzName = $tz.DisplayName
  timeService = "$((Get-Service w32time).Status)"
  ntpSource = ((w32tm /query /source) | Out-String).Trim()
  spooler = "$((Get-Service Spooler).Status)"
  adapters = @(Get-NetAdapter | Where-Object { "$($_.Status)" -ne 'Not Present' } | ForEach-Object {
    [ordered]@{ name = $_.Name; desc = $_.InterfaceDescription; status = "$($_.Status)";
      speed = "$($_.LinkSpeed)"; mac = "$($_.MacAddress)"; media = "$($_.MediaType)"; virtual = [bool]$_.Virtual } })
  gateways = @(Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | ForEach-Object { $_.NextHop } | Select-Object -Unique)
  dns = @(Get-DnsClientServerAddress -AddressFamily IPv4 | ForEach-Object { $_.ServerAddresses } | Select-Object -Unique)
  disks = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [ordered]@{ name = $_.DeviceID; free = [int64]$_.FreeSpace; size = [int64]$_.Size } })
  printers = @(Get-Printer | ForEach-Object {
    [ordered]@{ name = $_.Name; status = [int64]$_.PrinterStatus; port = "$($_.PortName)"; jobs = [int]$_.JobCount; driver = "$($_.DriverName)" } })
}
$r | ConvertTo-Json -Depth 4 -Compress
''';

  static Future<SystemSnapshot> _windowsSnapshot() async {
    final raw = await _powershell(_windowsSnapshotScript,
        timeout: const Duration(seconds: 40));
    final Map<String, dynamic> j;
    try {
      j = jsonDecode(raw.trim().replaceFirst('﻿', '')) as Map<String, dynamic>;
    } catch (_) {
      return SystemSnapshot.basic();
    }
    List<Map> maps(Object? v) =>
        v is List ? v.whereType<Map>().toList() : (v is Map ? [v] : const []);
    List<String> strings(Object? v) => v is List
        ? [for (final x in v) if ('$x'.isNotEmpty) '$x']
        : (v == null ? const [] : ['$v']);
    return SystemSnapshot.basic().copyWith(
      os: '${j['os'] ?? ''}'.trim(),
      bootTime: DateTime.tryParse('${j['bootTime'] ?? ''}')?.toLocal(),
      tzId: '${j['tzId'] ?? ''}',
      tzName: '${j['tzName'] ?? ''}',
      timeServiceRunning: _serviceRunning(j['timeService']),
      ntpSource: '${j['ntpSource'] ?? ''}',
      spoolerRunning: _serviceRunning(j['spooler']),
      adapters: [
        for (final a in maps(j['adapters']))
          AdapterInfo(
            name: '${a['name'] ?? ''}',
            description: '${a['desc'] ?? ''}',
            up: '${a['status']}' == 'Up',
            status: '${a['status'] ?? ''}',
            linkSpeed: '${a['speed'] ?? ''}',
            mac: '${a['mac'] ?? ''}',
            wireless: '${a['media']}'.contains('802.11'),
            virtual: a['virtual'] == true,
          ),
      ],
      gateways: strings(j['gateways']).where((g) => g != '0.0.0.0').toList(),
      dns: strings(j['dns']),
      disks: [
        for (final d in maps(j['disks']))
          DiskInfo('${d['name']}', _int(d['free']), _int(d['size'])),
      ],
      printers: [
        for (final p in maps(j['printers']))
          OsPrinter(
            name: '${p['name'] ?? ''}',
            port: '${p['port'] ?? ''}',
            jobs: _int(p['jobs']),
            statusFlags: _int(p['status']),
            driver: '${p['driver'] ?? ''}',
          ),
      ],
    );
  }

  static bool? _serviceRunning(Object? status) {
    final s = '${status ?? ''}';
    if (s.isEmpty) return null;
    return s == 'Running';
  }

  static int _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

  static Future<SystemSnapshot> _linuxSnapshot() async {
    var snap = SystemSnapshot.basic();
    String read(String path) {
      try {
        return File(path).readAsStringSync().trim();
      } catch (_) {
        return '';
      }
    }

    final osRelease = read('/etc/os-release');
    final pretty =
        RegExp(r'^PRETTY_NAME="?([^"\n]*)', multiLine: true).firstMatch(osRelease);
    final uptime = double.tryParse(read('/proc/uptime').split(' ').first);

    final adapters = <AdapterInfo>[];
    try {
      for (final e in Directory('/sys/class/net').listSync()) {
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name == 'lo') continue;
        final state = read('${e.path}/operstate');
        final speed = int.tryParse(read('${e.path}/speed'));
        adapters.add(AdapterInfo(
          name: name,
          description: '',
          up: state == 'up',
          status: state,
          linkSpeed: speed != null && speed > 0 ? '$speed Mbps' : '',
          mac: read('${e.path}/address'),
          wireless: Directory('${e.path}/wireless').existsSync(),
          virtual: !File('${e.path}/device').existsSync() &&
              !Directory('${e.path}/device').existsSync(),
        ));
      }
    } catch (_) {}

    final route = await _run('ip', ['route', 'show', 'default']);
    final gateways = [
      for (final m in RegExp(r'default via (\S+)').allMatches(route)) m.group(1)!
    ];
    final dns = [
      for (final m in RegExp(r'^nameserver\s+(\S+)', multiLine: true)
          .allMatches(read('/etc/resolv.conf')))
        m.group(1)!
    ];
    final tz = (await _run('timedatectl', ['show', '-p', 'Timezone', '--value'])).trim();
    final ntp =
        (await _run('timedatectl', ['show', '-p', 'NTPSynchronized', '--value'])).trim();

    final disks = <DiskInfo>[];
    final df = await _run('df', ['-B1', '--output=target,avail,size', '/']);
    for (final line in const LineSplitter().convert(df).skip(1)) {
      final f = line.trim().split(RegExp(r'\s+'));
      if (f.length >= 3) disks.add(DiskInfo(f[0], _int(f[1]), _int(f[2])));
    }

    final printers = <OsPrinter>[];
    final lp = await _run('lpstat', ['-p']);
    final jobs = await _run('lpstat', ['-o']);
    for (final m in RegExp(r'^printer (\S+) (.*)$', multiLine: true).allMatches(lp)) {
      final name = m.group(1)!;
      final rest = m.group(2)!;
      final count = RegExp('^${RegExp.escape(name)}-\\d+', multiLine: true)
          .allMatches(jobs)
          .length;
      printers.add(OsPrinter(
        name: name,
        port: '',
        jobs: count,
        // CUPS says "disabled" for a stopped queue; treat it as offline.
        statusFlags: rest.contains('disabled') ? OsPrinter.offline : 0,
        driver: '',
      ));
    }

    snap = snap.copyWith(
      os: pretty?.group(1) ?? Platform.operatingSystemVersion,
      bootTime: uptime == null
          ? null
          : DateTime.now().subtract(Duration(seconds: uptime.round())),
      tzId: tz,
      tzName: tz,
      timeServiceRunning: ntp.isEmpty ? null : ntp == 'yes',
      ntpSource: '',
      spoolerRunning: null,
      adapters: adapters,
      gateways: gateways,
      dns: dns,
      disks: disks,
      printers: printers,
    );
    return snap;
  }

  // -------------------------------------------------------------------- wifi

  static Future<WifiInfo?> wifi() async {
    if (Platform.isWindows) {
      return parseNetshWlan(await _run('netsh', ['wlan', 'show', 'interfaces']));
    }
    if (Platform.isLinux) {
      return parseNmcli(await _run('nmcli', [
        '-t',
        '-f',
        'IN-USE,SSID,BSSID,SIGNAL,RATE,CHAN,SECURITY',
        'dev',
        'wifi',
        'list',
        '--rescan',
        'no'
      ]));
    }
    return null;
  }

  /// `netsh wlan show interfaces`, in whatever language Windows speaks: the
  /// labels are translated, so fields are told apart by their values.
  static WifiInfo? parseNetshWlan(String out) {
    if (out.trim().isEmpty) return null;
    String? ssid, bssid, radio, auth, band, adapter;
    int? signal, channel;
    final rates = <double>[];
    for (final line in const LineSplitter().convert(out)) {
      final i = line.indexOf(' : ');
      if (i < 0) continue;
      final key = line.substring(0, i).trim();
      final value = line.substring(i + 3).trim();
      final lower = key.toLowerCase();
      if (key == 'SSID') {
        ssid ??= value;
      } else if (lower.contains('bssid')) {
        bssid ??= value;
      } else if (adapter == null &&
          (lower == 'name' || lower == 'nom' || lower == 'nombre')) {
        adapter = value;
      } else if (value.startsWith('802.11')) {
        radio ??= value;
      } else if (RegExp(r'^\d{1,3}\s*%$').hasMatch(value)) {
        signal ??= int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
      } else if (lower.contains('mbps') || lower.contains('mbit')) {
        final v = double.tryParse(value.replaceAll(',', '.'));
        if (v != null) rates.add(v);
      } else if (RegExp(r'GHz', caseSensitive: false).hasMatch(value)) {
        band ??= value;
      } else if (RegExp(r'^(WPA|WEP|Open|Ouvert|Abierta)', caseSensitive: false)
          .hasMatch(value)) {
        auth ??= value;
      } else if ((lower.contains('channel') || lower.contains('canal')) &&
          int.tryParse(value) != null) {
        channel ??= int.tryParse(value);
      }
    }
    return WifiInfo(
      connected: ssid != null && ssid.isNotEmpty,
      adapter: adapter ?? '',
      ssid: ssid ?? '',
      bssid: bssid ?? '',
      signalPercent: signal,
      receiveMbps: rates.isNotEmpty ? rates[0] : null,
      transmitMbps: rates.length > 1 ? rates[1] : null,
      channel: channel,
      band: band ?? (channel == null ? '' : (channel > 14 ? '5 GHz' : '2.4 GHz')),
      radio: radio ?? '',
      security: auth ?? '',
    );
  }

  static WifiInfo? parseNmcli(String out) {
    for (final line in const LineSplitter().convert(out)) {
      // nmcli -t escapes ':' inside values as '\:'.
      final f = line
          .replaceAll(r'\:', '\u0000')
          .split(':')
          .map((s) => s.replaceAll('\u0000', ':'))
          .toList();
      if (f.length < 7 || f[0] != '*') continue;
      final channel = int.tryParse(f[5]);
      return WifiInfo(
        connected: true,
        adapter: '',
        ssid: f[1],
        bssid: f[2],
        signalPercent: int.tryParse(f[3]),
        receiveMbps: double.tryParse(f[4].split(' ').first),
        transmitMbps: null,
        channel: channel,
        band: channel == null ? '' : (channel > 14 ? '5 GHz' : '2.4 GHz'),
        radio: '',
        security: f[6],
      );
    }
    return out.trim().isEmpty ? null : const WifiInfo.disconnected();
  }

  // ------------------------------------------------------ connectivity / time

  /// One reachability check: DNS, internet, the cloud backend, etc.
  static Future<EndpointResult> checkDns([String host = 'www.google.com']) =>
      _timed(EndpointKind.dns, host, () async {
        final r = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 5));
        return r.isEmpty ? null : r.first.address;
      });

  static Future<EndpointResult> checkHttp(EndpointKind kind, String url) =>
      _timed(kind, url, () async {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 6)
          ..badCertificateCallback = (_, __, ___) => false;
        try {
          final req = await client
              .getUrl(Uri.parse(url))
              .timeout(const Duration(seconds: 8));
          final res = await req.close().timeout(const Duration(seconds: 8));
          await res.drain<void>().timeout(const Duration(seconds: 5),
              onTimeout: () {});
          // Any HTTP answer means the server is there; a 404 on its root is fine.
          return 'HTTP ${res.statusCode}';
        } finally {
          client.close(force: true);
        }
      });

  static Future<EndpointResult> checkTcp(
          EndpointKind kind, String host, int port) =>
      _timed(kind, '$host:$port', () async {
        final s = await Socket.connect(host, port,
            timeout: const Duration(seconds: 3));
        s.destroy();
        return 'TCP $port';
      });

  static Future<EndpointResult> checkPing(EndpointKind kind, String host) =>
      _timed(kind, host, () async {
        final r = await pingOnce(host);
        if (r == null) throw const SocketException('no reply');
        return '${r.toStringAsFixed(0)} ms';
      });

  static Future<EndpointResult> _timed(
      EndpointKind kind, String target, Future<String?> Function() probe) async {
    final sw = Stopwatch()..start();
    try {
      final detail = await probe();
      sw.stop();
      return EndpointResult(
          kind: kind,
          target: target,
          ok: detail != null,
          latencyMs: sw.elapsedMilliseconds,
          detail: detail ?? '');
    } catch (e) {
      sw.stop();
      return EndpointResult(
          kind: kind,
          target: target,
          ok: false,
          latencyMs: null,
          detail: _short(e));
    }
  }

  static String _short(Object e) {
    if (e is TimeoutException) return 'timeout';
    if (e is SocketException) {
      return e.osError?.message.trim().isNotEmpty == true
          ? e.osError!.message.trim()
          : e.message;
    }
    if (e is HandshakeException) return 'TLS: ${e.message}';
    final s = '$e';
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  /// The real time, from Cloudflare (`ts=` in its trace) or else from a
  /// server's `Date` header. Positive skew = this machine is ahead.
  static Future<ClockCheck?> checkClock({String? fallbackUrl}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      Future<ClockCheck?> attempt(String url, bool trace) async {
        final before = DateTime.now();
        final req = await client.getUrl(Uri.parse(url));
        final res = await req.close().timeout(const Duration(seconds: 8));
        final body = await res
            .transform(utf8.decoder)
            .join()
            .timeout(const Duration(seconds: 8));
        final after = DateTime.now();
        final mid = before.add(after.difference(before) ~/ 2);
        DateTime? real;
        if (trace) {
          final ts = RegExp(r'^ts=([\d.]+)', multiLine: true).firstMatch(body);
          final secs = double.tryParse(ts?.group(1) ?? '');
          if (secs != null) {
            real = DateTime.fromMillisecondsSinceEpoch((secs * 1000).round());
          }
        } else {
          final date = res.headers.value(HttpHeaders.dateHeader);
          if (date != null) real = HttpDate.parse(date).toLocal();
        }
        if (real == null) return null;
        return ClockCheck(
            source: Uri.parse(url).host,
            reference: real,
            skew: mid.difference(real));
      }

      try {
        final c = await attempt('https://speed.cloudflare.com/cdn-cgi/trace', true);
        if (c != null) return c;
      } catch (_) {}
      if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
        try {
          return await attempt(fallbackUrl, false);
        } catch (_) {}
      }
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // --------------------------------------------------------------- speed test

  static const _speedHost = 'https://speed.cloudflare.com';

  static Future<SpeedResult> speedTest(
      {void Function(String phase, double? mbps)? onProgress}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      onProgress?.call('latency', null);
      final pings = <int>[];
      for (var i = 0; i < 5; i++) {
        final sw = Stopwatch()..start();
        final req = await client.getUrl(Uri.parse('$_speedHost/__down?bytes=0'));
        final res = await req.close().timeout(const Duration(seconds: 8));
        await res.drain<void>();
        pings.add(sw.elapsedMilliseconds);
      }
      pings.sort();
      final latency = pings[pings.length ~/ 2];

      onProgress?.call('download', null);
      final down = await _download(client, (m) => onProgress?.call('download', m));
      onProgress?.call('upload', null);
      final up = await _upload(client);
      return SpeedResult(
          latencyMs: latency, downloadMbps: down, uploadMbps: up, error: null);
    } catch (e) {
      return SpeedResult(
          latencyMs: null, downloadMbps: null, uploadMbps: null, error: _short(e));
    } finally {
      client.close(force: true);
    }
  }

  static Future<double> _download(
      HttpClient client, void Function(double) progress) async {
    const limit = Duration(seconds: 8);
    final req =
        await client.getUrl(Uri.parse('$_speedHost/__down?bytes=100000000'));
    final res = await req.close().timeout(const Duration(seconds: 10));
    final sw = Stopwatch()..start();
    var bytes = 0;
    var lastReport = 0;
    final done = Completer<void>();
    late StreamSubscription<List<int>> sub;
    sub = res.listen((chunk) {
      bytes += chunk.length;
      if (sw.elapsedMilliseconds - lastReport > 400) {
        lastReport = sw.elapsedMilliseconds;
        progress(_mbps(bytes, sw.elapsed));
      }
      if (sw.elapsed > limit) {
        sub.cancel();
        if (!done.isCompleted) done.complete();
      }
    }, onDone: () {
      if (!done.isCompleted) done.complete();
    }, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    }, cancelOnError: true);
    await done.future.timeout(limit + const Duration(seconds: 4),
        onTimeout: () => sub.cancel());
    sw.stop();
    return _mbps(bytes, sw.elapsed);
  }

  static Future<double> _upload(HttpClient client) async {
    const size = 8 * 1024 * 1024;
    final chunk = List<int>.filled(64 * 1024, 0x61);
    final req = await client.postUrl(Uri.parse('$_speedHost/__up'));
    req.contentLength = size;
    req.headers.contentType = ContentType.binary;
    final sw = Stopwatch()..start();
    for (var sent = 0; sent < size; sent += chunk.length) {
      req.add(chunk);
      await req.flush();
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    sw.stop();
    await res.drain<void>();
    return _mbps(size, sw.elapsed);
  }

  static double _mbps(int bytes, Duration d) =>
      d.inMicroseconds == 0 ? 0 : bytes * 8 / d.inMicroseconds;

  // ---------------------------------------------------------- ping / console

  /// One echo; the round trip in ms, or null when nothing answered.
  static Future<double?> pingOnce(String host) async {
    if (!hostPattern.hasMatch(host)) return null;
    final out = Platform.isWindows
        ? await _run('ping', ['-n', '1', '-w', '1500', host])
        : await _run('ping', ['-c', '1', '-W', '2', host]);
    return parsePingTimes(out).firstOrNull;
  }

  /// Round-trip times (ms) in ping output: `time=12ms`, `temps=12 ms`,
  /// `time<1ms`. Only echo replies carry `TTL=`, in every language Windows
  /// ships, which keeps the min/max/average summary out.
  static List<double> parsePingTimes(String out) => [
        for (final line in const LineSplitter().convert(out))
          if (line.toLowerCase().contains('ttl='))
            for (final m in RegExp(r'[=<]\s*(\d+(?:[.,]\d+)?)\s*ms',
                    caseSensitive: false)
                .allMatches(line).take(1))
              double.parse(m.group(1)!.replaceAll(',', '.')),
      ];

  /// Starts a console tool (ping, traceroute); lines arrive on [onLine].
  static Future<ConsoleRun> startConsole(
      ConsoleTool tool, String host, int count, void Function(String) onLine) async {
    final List<String> cmd;
    if (Platform.isWindows) {
      // chcp 65001 makes the tool print UTF-8 so accented labels survive.
      final inner = switch (tool) {
        ConsoleTool.ping => 'ping -n $count -w 1500 $host',
        ConsoleTool.traceroute => 'tracert -d -w 800 -h 20 $host',
      };
      cmd = ['cmd', '/c', 'chcp 65001>nul & $inner'];
    } else {
      cmd = switch (tool) {
        ConsoleTool.ping => ['ping', '-c', '$count', '-W', '2', host],
        ConsoleTool.traceroute => await _which('traceroute') != null
            ? ['traceroute', '-n', '-w', '1', '-m', '20', host]
            : ['tracepath', '-n', host],
      };
    }
    final process = await Process.start(cmd.first, cmd.sublist(1));
    final decoder = Utf8Decoder(allowMalformed: true);
    void pipe(Stream<List<int>> s) => s
        .transform(decoder)
        .transform(const LineSplitter())
        .where((l) => l.trim().isNotEmpty)
        .listen(onLine);
    pipe(process.stdout);
    pipe(process.stderr);
    return ConsoleRun(process);
  }

  static Future<String?> _which(String bin) async {
    final r = await _run('which', [bin]);
    return r.trim().isEmpty ? null : r.trim();
  }

  // ----------------------------------------------------------------- LAN scan

  static const int printerPort = 9100;

  /// IPv4 addresses this machine holds, keyed by adapter; scan candidates.
  static Future<List<ScanTarget>> scanTargets() async {
    final out = <ScanTarget>[];
    try {
      for (final i in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false)) {
        for (final a in i.addresses) {
          if (a.address.startsWith('169.254.')) continue;
          out.add(ScanTarget(i.name, a.address));
        }
      }
    } catch (_) {}
    // Hyper-V, VM, WSL and VPN adapters hold private subnets with nothing
    // on them; the shop network goes first.
    final virtual = RegExp(
        r'vethernet|hyper-v|virtualbox|vmware|vmnet|wsl|docker|br-|virbr|tailscale|zerotier|wireguard|tap|tun|vpn',
        caseSensitive: false);
    out.sort((a, b) {
      final va = virtual.hasMatch(a.adapter) ? 1 : 0;
      final vb = virtual.hasMatch(b.adapter) ? 1 : 0;
      return va - vb;
    });
    return out;
  }

  /// Finds devices on the /24 around [self]. A host counts as present when a
  /// probed TCP port answers, or when the probes left it in the ARP table —
  /// which also catches devices that firewall every port.
  static Future<List<LanHost>> scanLan({
    required String self,
    required List<int> ports,
    String? gateway,
    void Function(int done, int total)? onProgress,
    bool Function()? cancelled,
  }) async {
    final prefix = self.substring(0, self.lastIndexOf('.') + 1);
    final ips = [for (var i = 1; i < 255; i++) '$prefix$i'];
    final found = <String, LanHost>{};
    var done = 0;
    var next = 0;

    Future<void> worker() async {
      while (next < ips.length && !(cancelled?.call() ?? false)) {
        final ip = ips[next++];
        final open = <int>{};
        int? best;
        await Future.wait([
          for (final port in ports)
            () async {
              final sw = Stopwatch()..start();
              try {
                final s = await Socket.connect(ip, port,
                    timeout: const Duration(milliseconds: 700));
                s.destroy();
                open.add(port);
                final ms = sw.elapsedMilliseconds;
                if (best == null || ms < best!) best = ms;
              } catch (_) {}
            }(),
        ]);
        if (open.isNotEmpty) {
          found[ip] = LanHost(ip: ip, openPorts: open, latencyMs: best);
        }
        done++;
        onProgress?.call(done, ips.length);
      }
    }

    await Future.wait([for (var i = 0; i < 48; i++) worker()]);

    for (final e in (await arpTable()).entries) {
      if (!e.key.startsWith(prefix)) continue;
      final last = int.tryParse(e.key.substring(prefix.length));
      if (last == null || last == 0 || last == 255) continue;
      final h = found[e.key];
      found[e.key] = h == null
          ? LanHost(ip: e.key, openPorts: const {}, mac: e.value)
          : h.copyWith(mac: e.value);
    }
    found.putIfAbsent(self, () => LanHost(ip: self, openPorts: const {}));

    final hosts = found.values.toList();
    await Future.wait([
      for (var i = 0; i < hosts.length; i++)
        () async {
          try {
            final r = await InternetAddress(hosts[i].ip)
                .reverse()
                .timeout(const Duration(milliseconds: 1500));
            if (r.host != hosts[i].ip) {
              hosts[i] = hosts[i].copyWith(hostname: r.host);
            }
          } catch (_) {}
        }(),
    ]);
    for (var i = 0; i < hosts.length; i++) {
      hosts[i] = hosts[i].copyWith(
          isSelf: hosts[i].ip == self, isGateway: hosts[i].ip == gateway);
    }
    hosts.sort((a, b) => _ipKey(a.ip).compareTo(_ipKey(b.ip)));
    return hosts;
  }

  static int _ipKey(String ip) =>
      ip.split('.').fold(0, (acc, p) => acc * 256 + (int.tryParse(p) ?? 0));

  /// IPv4 → MAC, from the OS neighbour table (unicast entries only).
  static Future<Map<String, String>> arpTable() async {
    final out = <String, String>{};
    final text = Platform.isWindows
        ? await _run('arp', ['-a'])
        : await _run('ip', ['neigh', 'show']);
    final re = RegExp(
        r'(\d{1,3}(?:\.\d{1,3}){3})\D+?([0-9a-fA-F]{2}(?:[-:][0-9a-fA-F]{2}){5})');
    for (final line in const LineSplitter().convert(text)) {
      if (line.contains('FAILED') || line.contains('INCOMPLETE')) continue;
      final m = re.firstMatch(line);
      if (m == null) continue;
      final mac = m.group(2)!.toUpperCase().replaceAll('-', ':');
      final first = int.parse(mac.substring(0, 2), radix: 16);
      // Broadcast and multicast entries are not devices.
      if (mac == 'FF:FF:FF:FF:FF:FF' || first & 1 == 1) continue;
      out[m.group(1)!] = mac;
    }
    return out;
  }

  /// Asks each device that runs a web page what it is, and each one with the
  /// POS port open whether it is a caisse212 till.
  static Future<List<LanHost>> identifyHosts(List<LanHost> hosts, int lanPort) async {
    final out = [...hosts];
    await Future.wait([
      for (var i = 0; i < out.length; i++)
        () async {
          final h = out[i];
          if (h.isSelf) return;
          if (h.openPorts.contains(lanPort) && await _isCaisse(h.ip, lanPort)) {
            out[i] = out[i].copyWith(isCaisse: true);
            return;
          }
          for (final port in const [80, 8080, 8000]) {
            if (!h.openPorts.contains(port) || port == lanPort) continue;
            final b = await _banner(h.ip, port);
            if (b != null) {
              out[i] = out[i].copyWith(banner: b);
              return;
            }
          }
        }(),
    ]);
    return out;
  }

  static Future<bool> _isCaisse(String ip, int port) async {
    final body = await _httpGet('http://$ip:$port/health');
    return body != null && body.contains('"status"') && body.contains('"port"');
  }

  static Future<String?> _banner(String ip, int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client
          .getUrl(Uri.parse('http://$ip:$port/'))
          .timeout(const Duration(seconds: 3));
      req.followRedirects = true;
      final res = await req.close().timeout(const Duration(seconds: 3));
      final server = res.headers.value('server');
      final body = await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 3), onTimeout: () => '');
      final title = RegExp(r'<title[^>]*>([^<]{1,80})</title>', caseSensitive: false)
          .firstMatch(body)
          ?.group(1)
          ?.trim();
      final parts = [
        if (title != null && title.isNotEmpty) title,
        if (server != null && server.isNotEmpty) server,
      ];
      return parts.isEmpty ? null : parts.join(' · ');
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _httpGet(String url) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 3));
      final res = await req.close().timeout(const Duration(seconds: 3));
      return await res
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Manufacturer names for MAC prefixes, from api.macvendors.com. Only the
  /// first three bytes leave the machine. The free API allows one request
  /// per second, so lookups are spaced and [cache] (prefix → name, '' for
  /// unknown) is meant to be kept by the caller.
  static Future<void> lookupVendors(
    Iterable<String> macs,
    Map<String, String> cache, {
    void Function(String prefix, String vendor)? onFound,
    bool Function()? cancelled,
  }) async {
    final prefixes = {
      for (final m in macs)
        if (m.length >= 8) m.substring(0, 8).toUpperCase()
    }.where((p) {
      final first = int.tryParse(p.substring(0, 2), radix: 16) ?? 0;
      return first & 0x02 == 0 && !cache.containsKey(p);
    }).toList();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      for (final p in prefixes) {
        if (cancelled?.call() ?? false) return;
        try {
          final req = await client.getUrl(Uri.parse('https://api.macvendors.com/$p'));
          final res = await req.close().timeout(const Duration(seconds: 5));
          final body = await res.transform(utf8.decoder).join();
          if (res.statusCode == 200) {
            cache[p] = body.trim();
            onFound?.call(p, body.trim());
          } else if (res.statusCode == 404) {
            cache[p] = '';
          }
        } catch (_) {
          return; // Offline: try again on the next scan.
        }
        await Future<void>.delayed(const Duration(milliseconds: 1100));
      }
    } finally {
      client.close(force: true);
    }
  }

  // ------------------------------------------------------------- connections

  /// Established TCP connections grouped by program: who is using the
  /// network on this machine.
  static Future<List<ProcessConnections>> connectionsByProcess() async {
    final byPid = <int, List<String>>{};
    final names = <int, String>{};
    if (Platform.isWindows) {
      final raw = await _powershell(r'''
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$c = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
  Where-Object { $_.RemoteAddress -ne '127.0.0.1' -and $_.RemoteAddress -ne '::1' } |
  ForEach-Object { [ordered]@{ p = $_.OwningProcess; r = "$($_.RemoteAddress):$($_.RemotePort)" } })
$ids = $c | ForEach-Object { $_.p } | Select-Object -Unique
$n = @{}
foreach ($i in $ids) { $pr = Get-Process -Id $i -ErrorAction SilentlyContinue; $n["$i"] = if ($pr) { $pr.ProcessName } else { "pid $i" } }
ConvertTo-Json -InputObject ([ordered]@{ c = $c; n = $n }) -Depth 4 -Compress
''');
      try {
        final j = jsonDecode(raw.trim()) as Map<String, dynamic>;
        final c = j['c'];
        for (final m in (c is List ? c : [c]).whereType<Map>()) {
          byPid.putIfAbsent(_int(m['p']), () => []).add('${m['r']}');
        }
        (j['n'] as Map? ?? {}).forEach((k, v) => names[int.parse('$k')] = '$v');
      } catch (_) {}
    } else {
      final out = await _run('ss', ['-tnpH', 'state', 'established']);
      for (final line in const LineSplitter().convert(out)) {
        final f = line.trim().split(RegExp(r'\s+'));
        if (f.length < 4) continue;
        final remote = f[3];
        if (remote.startsWith('127.') || remote.startsWith('[::1]')) continue;
        final m = RegExp(r'users:\(\("([^"]+)",pid=(\d+)').firstMatch(line);
        final pid = int.tryParse(m?.group(2) ?? '') ?? 0;
        names[pid] = m?.group(1) ?? '?';
        byPid.putIfAbsent(pid, () => []).add(remote);
      }
    }
    return [
      for (final e in byPid.entries)
        ProcessConnections(
          names[e.key] ?? 'pid ${e.key}',
          e.key,
          e.value.length,
          {for (final r in e.value) r.substring(0, r.lastIndexOf(':'))},
        ),
    ]..sort((a, b) => b.connections.compareTo(a.connections));
  }

  // ------------------------------------------------------------ nearby Wi-Fi

  static Future<List<WifiNeighbour>> nearbyWifi() async {
    if (Platform.isWindows) {
      return parseNetshNetworks(
          await _run('netsh', ['wlan', 'show', 'networks', 'mode=bssid']));
    }
    final out = await _run('nmcli', [
      '-t', '-f', 'SSID,BSSID,SIGNAL,CHAN,SECURITY', 'dev', 'wifi', 'list'
    ]);
    return [
      for (final line in const LineSplitter().convert(out))
        if (_nmcliFields(line) case final f when f.length >= 5)
          WifiNeighbour(
            ssid: f[0],
            bssid: f[1],
            signalPercent: int.tryParse(f[2]) ?? 0,
            channel: int.tryParse(f[3]),
            security: f[4],
          ),
    ];
  }

  static List<String> _nmcliFields(String line) => line
      .replaceAll(r'\:', '\u0000')
      .split(':')
      .map((s) => s.replaceAll('\u0000', ':'))
      .toList();

  /// `netsh wlan show networks mode=bssid`: one entry per access point.
  /// Labels are translated, so lines are told apart by their shape.
  static List<WifiNeighbour> parseNetshNetworks(String out) {
    final result = <WifiNeighbour>[];
    String ssid = '', security = '';
    String? bssid;
    int? signal, channel;
    void flush() {
      if (bssid != null) {
        result.add(WifiNeighbour(
            ssid: ssid,
            bssid: bssid!,
            signalPercent: signal ?? 0,
            channel: channel,
            security: security));
      }
      bssid = null;
      signal = null;
      channel = null;
    }

    for (final line in const LineSplitter().convert(out)) {
      // A hidden network's line is "SSID 2 :" with nothing after the colon.
      final header = RegExp(r'^SSID \d+\s*:\s?(.*)$').firstMatch(line.trim());
      if (header != null) {
        flush();
        ssid = header.group(1)!.trim();
        security = '';
        continue;
      }
      final i = line.indexOf(' : ');
      if (i < 0) continue;
      final key = line.substring(0, i).trim();
      final value = line.substring(i + 3).trim();
      final lower = key.toLowerCase();
      if (RegExp(r'^BSSID \d+$').hasMatch(key)) {
        flush();
        bssid = value;
      } else if (RegExp(r'^(WPA|WEP|Open|Ouvert|Abierta)', caseSensitive: false)
              .hasMatch(value) &&
          security.isEmpty) {
        security = value;
      } else if (RegExp(r'^\d{1,3}\s*%$').hasMatch(value)) {
        signal = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
      } else if ((lower.contains('channel') || lower.contains('canal')) &&
          int.tryParse(value) != null) {
        channel = int.tryParse(value);
      }
    }
    flush();
    return result;
  }

  /// 2.4 GHz channels bleed four channels either side, which is why only
  /// 1, 6 and 11 never overlap; 5 GHz channels are counted on their own.
  static ChannelAdvice channelAdvice(List<WifiNeighbour> nets, {required bool fiveGHz,
      String? ownBssid}) {
    final others = nets.where((n) =>
        n.channel != null &&
        n.is5GHz == fiveGHz &&
        n.bssid.toLowerCase() != (ownBssid ?? '').toLowerCase());
    final load = <int, double>{};
    if (!fiveGHz) {
      for (var c = 1; c <= 13; c++) {
        load[c] = 0;
        for (final n in others) {
          final d = (n.channel! - c).abs();
          if (d <= 4) load[c] = load[c]! + n.signalPercent * (1 - d / 5);
        }
      }
      final best = [1, 6, 11].reduce((a, b) => load[a]! <= load[b]! ? a : b);
      return ChannelAdvice(load, best);
    }
    const common = [36, 40, 44, 48, 149, 153, 157, 161];
    for (final c in common) {
      load[c] = 0;
    }
    for (final n in others) {
      load[n.channel!] = (load[n.channel!] ?? 0) + n.signalPercent.toDouble();
    }
    final best = common.reduce((a, b) => load[a]! <= load[b]! ? a : b);
    return ChannelAdvice(Map.fromEntries(load.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key))), best);
  }

  // ---------------------------------------------------------------- printers

  /// Opens the printer's raw port and asks for its real-time status
  /// (DLE EOT 1 and 4). Nothing prints; printers that ignore the query are
  /// reported as reachable with no status.
  static Future<NetworkPrinterStatus> probeNetworkPrinter(String address) async {
    final parts = address.split(':');
    final host = parts.first.trim();
    final port = parts.length > 1 ? int.tryParse(parts[1]) ?? printerPort : printerPort;
    final sw = Stopwatch()..start();
    Socket socket;
    try {
      socket = await Socket.connect(host, port,
          timeout: const Duration(seconds: 3));
    } catch (e) {
      return NetworkPrinterStatus(
          reachable: false, latencyMs: null, error: _short(e));
    }
    final latency = sw.elapsedMilliseconds;
    final reply = <int>[];
    final sub = socket.listen(reply.addAll, onError: (_) {}, cancelOnError: true);
    try {
      socket.add(const [0x10, 0x04, 0x01, 0x10, 0x04, 0x04]);
      await socket.flush();
      final until = DateTime.now().add(const Duration(milliseconds: 1200));
      while (reply.length < 2 && DateTime.now().isBefore(until)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    } catch (_) {}
    await sub.cancel();
    socket.destroy();
    if (reply.length < 2) {
      return NetworkPrinterStatus(reachable: true, latencyMs: latency);
    }
    final printer = reply[0], paper = reply[1];
    return NetworkPrinterStatus(
      reachable: true,
      latencyMs: latency,
      statusKnown: true,
      offline: printer & 0x08 != 0,
      paperOut: paper & 0x60 != 0,
      paperLow: paper & 0x0C != 0,
    );
  }

  /// Prints a slip saying where the printer lives, straight over its raw
  /// port, so the address can be taped to the printer.
  static Future<bool> printAddressLabel(String ip, int port, List<String> lines) async {
    try {
      final s = await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
      final bytes = <int>[
        0x1B, 0x40, // ESC @ reset
        0x1B, 0x61, 0x01, // centre
        0x1D, 0x21, 0x11, // double size
        ...latin1.encode('$ip\n'),
        0x1D, 0x21, 0x00,
        for (final l in lines) ...latin1.encode('${_ascii(l)}\n'),
        0x0A, 0x0A, 0x0A,
        0x1D, 0x56, 0x42, 0x00, // cut
      ];
      s.add(bytes);
      await s.flush();
      await s.close();
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Printers default to their own code page; keep the slip to plain ASCII.
  static String _ascii(String s) => String.fromCharCodes(
      s.runes.map((r) => r < 128 ? r : 0x3F));

  // ------------------------------------------------------------ IP conflicts

  /// Address conflicts Windows itself noticed for this PC (System log,
  /// Tcpip event 4199) over the last 30 days. Linux keeps no such record.
  static Future<List<IpConflictEvent>> ipConflictEvents() async {
    if (!Platform.isWindows) return const [];
    final raw = await _powershell(r'''
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$e = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Tcpip'; Id = 4199; StartTime = (Get-Date).AddDays(-30) } -MaxEvents 20 -ErrorAction SilentlyContinue |
  ForEach-Object { [ordered]@{ at = $_.TimeCreated.ToUniversalTime().ToString('o'); msg = $_.Message } })
ConvertTo-Json -InputObject $e -Compress
''');
    try {
      final j = jsonDecode(raw.trim());
      return [
        for (final m in (j is List ? j : [j]).whereType<Map>())
          IpConflictEvent(
            at: DateTime.tryParse('${m['at']}')?.toLocal() ?? DateTime.now(),
            message: '${m['msg'] ?? ''}'.replaceAll(RegExp(r'\s+'), ' ').trim(),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  // ------------------------------------------------- factory-default printers

  /// Addresses printers ship with. Xprinter / Rongta and most Chinese
  /// thermal printers use 192.168.123.100; Epson and Star use
  /// 192.168.192.168.
  static const factoryPrinterAddresses = [
    '192.168.123.100',
    '192.168.192.168',
    '192.168.1.87',
    '192.168.0.87',
    '192.168.1.100',
  ];

  /// The spare address this PC borrows on a factory subnet: .250 rarely
  /// collides with anything.
  static String borrowedAddress(String factoryIp) =>
      '${factoryIp.substring(0, factoryIp.lastIndexOf('.'))}.250';

  /// Gives [adapter] an extra address on each factory subnet so a printer
  /// still on its factory IP can be reached and re-addressed. Needs admin.
  static Future<void> addTemporaryAddresses(String adapter, List<String> factoryIps) async {
    final borrowed = {for (final ip in factoryIps) borrowedAddress(ip)};
    if (Platform.isWindows) {
      final alias = adapter.replaceAll("'", "''");
      await _powershellElevated([
        for (final b in borrowed)
          "New-NetIPAddress -InterfaceAlias '$alias' -IPAddress $b -PrefixLength 24 "
              "-SkipAsSource \$true -ErrorAction SilentlyContinue | Out-Null",
      ].join('\n'));
    } else {
      await _checked('pkexec', [
        'sh',
        '-c',
        [for (final b in borrowed) 'ip addr add $b/24 dev $adapter'].join('; '),
      ]);
    }
  }

  static Future<void> removeTemporaryAddresses(String adapter, List<String> factoryIps) async {
    final borrowed = {for (final ip in factoryIps) borrowedAddress(ip)};
    if (Platform.isWindows) {
      await _powershellElevated([
        for (final b in borrowed)
          'Remove-NetIPAddress -IPAddress $b -Confirm:\$false -ErrorAction SilentlyContinue',
      ].join('\n'));
    } else {
      await _checked('pkexec', [
        'sh',
        '-c',
        [for (final b in borrowed) 'ip addr del $b/24 dev $adapter'].join('; '),
      ]);
    }
  }

  /// Which factory addresses answer on the printer port or a web page.
  static Future<List<String>> probeFactoryPrinters() async {
    final found = <String>[];
    await Future.wait([
      for (final ip in factoryPrinterAddresses)
        () async {
          for (final port in const [printerPort, 80]) {
            try {
              final s = await Socket.connect(ip, port,
                  timeout: const Duration(milliseconds: 1500));
              s.destroy();
              found.add(ip);
              return;
            } catch (_) {}
          }
        }(),
    ]);
    return found;
  }

  // ----------------------------------------------------------------- cameras

  /// A still picture from the camera, refreshed by the caller for a
  /// near-live view. Digest and Basic auth both work.
  static Future<List<int>> cameraSnapshot(CameraSettings c) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    client.authenticate = (uri, scheme, realm) async {
      client.addCredentials(
          uri,
          realm ?? '',
          scheme.toLowerCase() == 'digest'
              ? HttpClientDigestCredentials(c.user, c.password)
              : HttpClientBasicCredentials(c.user, c.password));
      return true;
    };
    try {
      final req = await client
          .getUrl(Uri.parse(c.snapshotUrl))
          .timeout(const Duration(seconds: 5));
      final res = await req.close().timeout(const Duration(seconds: 6));
      final bytes = <int>[];
      await res.forEach(bytes.addAll).timeout(const Duration(seconds: 8));
      if (res.statusCode == 401) throw const DiagnosticsException('401');
      if (res.statusCode != 200) {
        throw DiagnosticsException('HTTP ${res.statusCode}');
      }
      final type = res.headers.contentType?.primaryType ?? '';
      if (type.isNotEmpty && type != 'image') {
        throw DiagnosticsException('${res.headers.contentType}');
      }
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  /// VLC plays the camera's RTSP stream when it is installed.
  static Future<String?> findVlc() async {
    if (Platform.isWindows) {
      for (final base in [
        Platform.environment['ProgramFiles'],
        Platform.environment['ProgramFiles(x86)'],
      ]) {
        if (base == null) continue;
        final f = File('$base\\VideoLAN\\VLC\\vlc.exe');
        if (f.existsSync()) return f.path;
      }
      return null;
    }
    return _which('vlc');
  }

  static Future<void> openInVlc(String vlc, String url) =>
      Process.start(vlc, [url], mode: ProcessStartMode.detached);

  // ------------------------------------------------------------------- misc

  static Future<void> openUrl(String url) async {
    if (Platform.isWindows) {
      await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
    }
  }

  /// The router address, cheaply enough to ask every few minutes.
  static Future<String?> defaultGateway() async {
    if (Platform.isWindows) {
      final out = await _run('route', ['print', '-4', '0.0.0.0']);
      final m = RegExp(r'^\s*0\.0\.0\.0\s+0\.0\.0\.0\s+(\d{1,3}(?:\.\d{1,3}){3})',
              multiLine: true)
          .firstMatch(out);
      return m?.group(1);
    }
    final m = RegExp(r'default via (\S+)').firstMatch(await _run('ip', ['route', 'show', 'default']));
    return m?.group(1);
  }

  // --------------------------------------------------------------- fixes

  /// Restarts the Windows time service and pulls the time from the internet.
  static Future<void> syncClock() async {
    if (Platform.isWindows) {
      await _powershellElevated(r'''
Set-Service w32time -StartupType Automatic
Start-Service w32time
w32tm /config /manualpeerlist:"time.windows.com,0x9 pool.ntp.org,0x9" /syncfromflags:manual /update
Restart-Service w32time
w32tm /resync /force
''');
    } else {
      await _checked('pkexec', ['timedatectl', 'set-ntp', 'true']);
    }
  }

  /// Empties every print queue: stops the spooler, drops its job files,
  /// starts it again. The classic cure for a queue stuck on a dead job.
  static Future<void> clearPrintQueues() async {
    if (Platform.isWindows) {
      await _powershellElevated(r'''
Stop-Service Spooler -Force
Remove-Item "$env:SystemRoot\System32\spool\PRINTERS\*" -Force -ErrorAction SilentlyContinue
Start-Service Spooler
''');
    } else {
      await _checked('cancel', ['-a']);
    }
  }

  static Future<void> restartSpooler() async {
    if (Platform.isWindows) {
      await _powershellElevated('Restart-Service Spooler -Force');
    } else {
      await _checked('pkexec', ['systemctl', 'restart', 'cups']);
    }
  }

  static Future<void> flushDns() async {
    if (Platform.isWindows) {
      await _checked('ipconfig', ['/flushdns']);
    } else {
      await _checked('resolvectl', ['flush-caches']);
    }
  }

  /// Asks the router for a fresh address. The connection drops for a moment.
  static Future<void> renewIp() async {
    if (Platform.isWindows) {
      await _powershellElevated('ipconfig /release; ipconfig /renew');
    } else {
      await _checked('pkexec',
          ['sh', '-c', 'nmcli networking off && sleep 2 && nmcli networking on']);
    }
  }

  static Future<void> openSettings(SettingsPage page) async {
    if (Platform.isWindows) {
      final target = switch (page) {
        SettingsPage.network => 'ms-settings:network-status',
        SettingsPage.time => 'ms-settings:dateandtime',
        SettingsPage.printers => 'ms-settings:printers',
      };
      await Process.run('explorer', [target]);
    } else {
      final panel = switch (page) {
        SettingsPage.network => 'network',
        SettingsPage.time => 'datetime',
        SettingsPage.printers => 'printers',
      };
      await Process.start('gnome-control-center', [panel],
          mode: ProcessStartMode.detached);
    }
  }

  // ---------------------------------------------------------------- plumbing

  static Future<String> _run(String exe, List<String> args,
      {Duration timeout = const Duration(seconds: 20)}) async {
    try {
      final r = await Process.run(exe, args,
              stdoutEncoding: Platform.isWindows ? systemEncoding : utf8)
          .timeout(timeout);
      return '${r.stdout}';
    } catch (_) {
      return '';
    }
  }

  static Future<void> _checked(String exe, List<String> args) async {
    final r = await Process.run(exe, args);
    if (r.exitCode != 0) {
      final msg = '${r.stderr}'.trim();
      throw DiagnosticsException(
          msg.isEmpty ? '$exe exited with ${r.exitCode}' : msg,
          cancelled: exe == 'pkexec' && (r.exitCode == 126 || r.exitCode == 127));
    }
  }

  static String _encode(String script) =>
      base64.encode([for (final u in script.codeUnits) ...[u & 0xff, u >> 8]]);

  static Future<String> _powershell(String script,
      {Duration timeout = const Duration(seconds: 30)}) async {
    try {
      final r = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        _encode(script),
      ], stdoutEncoding: utf8).timeout(timeout);
      return '${r.stdout}';
    } catch (_) {
      return '';
    }
  }

  static bool? _elevated;

  static Future<bool> _isElevated() async =>
      _elevated ??= (await Process.run('net', ['session'])).exitCode == 0;

  /// Runs [script] as administrator, asking through UAC when the POS itself
  /// is not elevated.
  static Future<void> _powershellElevated(String script) async {
    final encoded = _encode('\$ErrorActionPreference = "Continue"\n$script');
    if (await _isElevated()) {
      final r = await Process.run('powershell',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', encoded]);
      if (r.exitCode != 0) {
        throw DiagnosticsException('${r.stderr}'.trim().isEmpty
            ? 'exit ${r.exitCode}'
            : '${r.stderr}'.trim());
      }
      return;
    }
    final r = await Process.run('powershell', [
      '-NoProfile',
      '-Command',
      "Start-Process powershell -Verb RunAs -Wait -WindowStyle Hidden "
          "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-EncodedCommand','$encoded'",
    ]);
    if (r.exitCode != 0) {
      throw const DiagnosticsException('Administrator rights were refused',
          cancelled: true);
    }
  }
}

// ------------------------------------------------------------------- models

class DiagnosticsException implements Exception {
  final String message;
  final bool cancelled;
  const DiagnosticsException(this.message, {this.cancelled = false});
  @override
  String toString() => message;
}

enum SettingsPage { network, time, printers }

enum ConsoleTool { ping, traceroute }

class ConsoleRun {
  final Process process;
  ConsoleRun(this.process);

  Future<int> get exitCode => process.exitCode;

  void stop() {
    if (Platform.isWindows) {
      // The tool runs under cmd.exe; killing cmd alone would orphan it.
      Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
    } else {
      process.kill();
    }
  }
}

class AdapterInfo {
  final String name;
  final String description;
  final bool up;
  final String status;
  final String linkSpeed;
  final String mac;
  final bool wireless;
  final bool virtual;
  const AdapterInfo({
    required this.name,
    required this.description,
    required this.up,
    required this.status,
    required this.linkSpeed,
    required this.mac,
    required this.wireless,
    required this.virtual,
  });
}

class DiskInfo {
  final String name;
  final int freeBytes;
  final int sizeBytes;
  const DiskInfo(this.name, this.freeBytes, this.sizeBytes);
  double get freeFraction => sizeBytes == 0 ? 1 : freeBytes / sizeBytes;
}

/// A printer as the OS spooler sees it.
class OsPrinter {
  final String name;
  final String port;
  final int jobs;

  /// Windows `PrinterStatus` bit flags (see [problems]).
  final int statusFlags;
  final String driver;

  static const paused = 1, error = 2, paperJam = 8, paperOut = 16,
      paperProblem = 64, offline = 128, notAvailable = 4096,
      userIntervention = 1048576, doorOpen = 4194304, noToner = 262144;

  const OsPrinter({
    required this.name,
    required this.port,
    required this.jobs,
    required this.statusFlags,
    required this.driver,
  });

  /// Localization keys of what is wrong; empty when the printer is fine.
  List<String> get problems => [
        if (statusFlags & offline != 0 || statusFlags & notAvailable != 0)
          'diag_printer_offline',
        if (statusFlags & error != 0) 'diag_printer_error',
        if (statusFlags & paused != 0) 'diag_printer_paused',
        if (statusFlags & (paperOut | paperProblem) != 0) 'diag_paper_out',
        if (statusFlags & paperJam != 0) 'diag_paper_jam',
        if (statusFlags & doorOpen != 0) 'diag_door_open',
        if (statusFlags & userIntervention != 0) 'diag_printer_error',
      ];

  /// Software printers that are never a till's problem.
  bool get isVirtual {
    final n = '$name $port'.toLowerCase();
    return n.contains('pdf') ||
        n.contains('xps') ||
        n.contains('onenote') ||
        n.contains('fax') ||
        port == 'PORTPROMPT:' ||
        port.startsWith('SHRFAX');
  }
}

class WifiInfo {
  final bool connected;
  final String adapter;
  final String ssid;
  final String bssid;
  final int? signalPercent;
  final double? receiveMbps;
  final double? transmitMbps;
  final int? channel;
  final String band;
  final String radio;
  final String security;

  const WifiInfo({
    required this.connected,
    required this.adapter,
    required this.ssid,
    required this.bssid,
    required this.signalPercent,
    required this.receiveMbps,
    required this.transmitMbps,
    required this.channel,
    required this.band,
    required this.radio,
    required this.security,
  });

  const WifiInfo.disconnected()
      : connected = false,
        adapter = '',
        ssid = '',
        bssid = '',
        signalPercent = null,
        receiveMbps = null,
        transmitMbps = null,
        channel = null,
        band = '',
        radio = '',
        security = '';
}

class SystemSnapshot {
  final String hostname;
  final String os;
  final DateTime? bootTime;
  final String tzId;
  final String tzName;
  final bool? timeServiceRunning;
  final String ntpSource;
  final bool? spoolerRunning;
  final List<AdapterInfo> adapters;
  final Map<String, List<String>> addresses;
  final List<String> gateways;
  final List<String> dns;
  final List<DiskInfo> disks;
  final List<OsPrinter> printers;
  final WifiInfo? wifi;

  const SystemSnapshot({
    required this.hostname,
    required this.os,
    required this.bootTime,
    required this.tzId,
    required this.tzName,
    required this.timeServiceRunning,
    required this.ntpSource,
    required this.spoolerRunning,
    required this.adapters,
    required this.addresses,
    required this.gateways,
    required this.dns,
    required this.disks,
    required this.printers,
    required this.wifi,
  });

  factory SystemSnapshot.basic() => SystemSnapshot(
        hostname: Platform.localHostname,
        os: Platform.operatingSystemVersion,
        bootTime: null,
        tzId: DateTime.now().timeZoneName,
        tzName: DateTime.now().timeZoneName,
        timeServiceRunning: null,
        ntpSource: '',
        spoolerRunning: null,
        adapters: const [],
        addresses: const {},
        gateways: const [],
        dns: const [],
        disks: const [],
        printers: const [],
        wifi: null,
      );

  SystemSnapshot copyWith({
    String? os,
    DateTime? bootTime,
    String? tzId,
    String? tzName,
    bool? timeServiceRunning,
    String? ntpSource,
    bool? spoolerRunning,
    List<AdapterInfo>? adapters,
    Map<String, List<String>>? addresses,
    List<String>? gateways,
    List<String>? dns,
    List<DiskInfo>? disks,
    List<OsPrinter>? printers,
    WifiInfo? wifi,
  }) =>
      SystemSnapshot(
        hostname: hostname,
        os: os ?? this.os,
        bootTime: bootTime ?? this.bootTime,
        tzId: tzId ?? this.tzId,
        tzName: tzName ?? this.tzName,
        timeServiceRunning: timeServiceRunning ?? this.timeServiceRunning,
        ntpSource: ntpSource ?? this.ntpSource,
        spoolerRunning: spoolerRunning ?? this.spoolerRunning,
        adapters: adapters ?? this.adapters,
        addresses: addresses ?? this.addresses,
        gateways: gateways ?? this.gateways,
        dns: dns ?? this.dns,
        disks: disks ?? this.disks,
        printers: printers ?? this.printers,
        wifi: wifi ?? this.wifi,
      );

  /// Physical adapters only; Hyper-V / VPN / docker bridges are noise here.
  List<AdapterInfo> get physicalAdapters =>
      adapters.where((a) => !a.virtual).toList();
}

enum EndpointKind { gateway, dns, internet, backend, updates, lanServer, custom }

class EndpointResult {
  final EndpointKind kind;
  final String target;
  final bool ok;
  final int? latencyMs;
  final String detail;
  const EndpointResult({
    required this.kind,
    required this.target,
    required this.ok,
    required this.latencyMs,
    required this.detail,
  });
}

class ClockCheck {
  final String source;
  final DateTime reference;

  /// Local minus real; positive when this machine runs ahead.
  final Duration skew;
  const ClockCheck(
      {required this.source, required this.reference, required this.skew});
}

class SpeedResult {
  final int? latencyMs;
  final double? downloadMbps;
  final double? uploadMbps;
  final String? error;
  const SpeedResult({
    required this.latencyMs,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.error,
  });
}

class ScanTarget {
  final String adapter;
  final String address;
  const ScanTarget(this.adapter, this.address);
  String get subnet => '${address.substring(0, address.lastIndexOf('.'))}.0/24';
}

enum DeviceKind { thisPos, router, caisse, printer, camera, computer, phone, media, unknown }

class LanHost {
  final String ip;
  final String? mac;
  final String? hostname;
  final Set<int> openPorts;
  final int? latencyMs;
  final bool isSelf;
  final bool isGateway;

  /// Manufacturer from the MAC prefix, when known.
  final String? vendor;

  /// What the device's web page calls itself (`Server` header / `<title>`).
  final String? banner;

  /// Answers `/health` like a caisse212 till does.
  final bool isCaisse;

  const LanHost({
    required this.ip,
    required this.openPorts,
    this.mac,
    this.hostname,
    this.latencyMs,
    this.isSelf = false,
    this.isGateway = false,
    this.vendor,
    this.banner,
    this.isCaisse = false,
  });

  bool get looksLikePrinter => kind == DeviceKind.printer;

  /// Phones and tablets hide behind a random MAC per network: the
  /// "locally administered" bit is set on the first byte.
  bool get privateMac {
    final m = mac;
    if (m == null || m.length < 2) return false;
    final first = int.tryParse(m.substring(0, 2), radix: 16) ?? 0;
    return first & 0x02 != 0;
  }

  static const cameraPorts = {554, 8000, 37777, 34567, 8899};
  static const _cameraWords = [
    'hikvision', 'dahua', 'ezviz', 'imou', 'uniview', 'xiongmai', 'reolink',
    'axis', 'hanwha', 'tvt', 'tiandy', 'camera', 'ipcam', 'nvr', 'dvr', 'webcam',
  ];
  static const _printerWords = [
    'epson', 'xprinter', 'star micronics', 'bixolon', 'rongta', 'citizen',
    'zebra', 'sewoo', 'gprinter', 'printer', 'imprimante', 'brother', 'canon',
    'kyocera', 'ricoh', 'lexmark',
  ];
  static const _phoneWords = [
    'apple', 'samsung', 'xiaomi', 'huawei device', 'oppo', 'vivo', 'realme',
    'oneplus', 'motorola', 'honor', 'infinix', 'tecno', 'itel', 'nokia',
  ];
  static const _mediaWords = [
    'lg electronics', 'sony', 'tcl', 'hisense', 'roku', 'chromecast',
    'google', 'amazon', 'philips', 'vestel',
  ];
  static const _computerWords = [
    'intel', 'dell', 'lenovo', 'hewlett', 'asus', 'acer', 'micro-star',
    'gigabyte', 'realtek', 'liteon', 'azurewave', 'raspberry', 'microsoft',
  ];

  DeviceKind get kind {
    if (isSelf) return DeviceKind.thisPos;
    if (isGateway) return DeviceKind.router;
    if (isCaisse) return DeviceKind.caisse;
    final text = '${vendor ?? ''} ${banner ?? ''} ${hostname ?? ''}'.toLowerCase();
    bool any(List<String> words) => words.any(text.contains);
    if (openPorts.contains(DiagnosticsService.printerPort) ||
        openPorts.contains(515) ||
        any(_printerWords)) {
      return DeviceKind.printer;
    }
    if (openPorts.any(cameraPorts.contains) || any(_cameraWords)) {
      return DeviceKind.camera;
    }
    // iPhones and iPads listen on 62078 for syncing.
    if (openPorts.contains(62078) || any(_phoneWords)) return DeviceKind.phone;
    if (openPorts.contains(8009) || openPorts.contains(7000) || any(_mediaWords)) {
      return DeviceKind.media;
    }
    if (openPorts.contains(445) ||
        openPorts.contains(139) ||
        openPorts.contains(3389) ||
        any(_computerWords)) {
      return DeviceKind.computer;
    }
    if (privateMac) return DeviceKind.phone;
    return DeviceKind.unknown;
  }

  LanHost copyWith({
    String? mac,
    String? hostname,
    bool? isSelf,
    bool? isGateway,
    String? vendor,
    String? banner,
    bool? isCaisse,
  }) =>
      LanHost(
        ip: ip,
        openPorts: openPorts,
        latencyMs: latencyMs,
        mac: mac ?? this.mac,
        hostname: hostname ?? this.hostname,
        isSelf: isSelf ?? this.isSelf,
        isGateway: isGateway ?? this.isGateway,
        vendor: vendor ?? this.vendor,
        banner: banner ?? this.banner,
        isCaisse: isCaisse ?? this.isCaisse,
      );
}

class IpConflictEvent {
  final DateTime at;
  final String message;
  const IpConflictEvent({required this.at, required this.message});
}

enum CameraBrand { hikvision, dahua, reolink, xiongmai, custom }

/// How to reach one camera. Never persisted with its password.
class CameraSettings {
  final String ip;
  final CameraBrand brand;
  final String user;
  final String password;
  final int channel;

  /// Path after the host for [CameraBrand.custom], e.g. `/snapshot.jpg`.
  final String customPath;

  const CameraSettings({
    required this.ip,
    required this.brand,
    required this.user,
    required this.password,
    this.channel = 1,
    this.customPath = '',
  });

  static CameraBrand guessBrand(String text) {
    final t = text.toLowerCase();
    if (t.contains('hikvision') || t.contains('ezviz')) return CameraBrand.hikvision;
    if (t.contains('dahua') || t.contains('imou')) return CameraBrand.dahua;
    if (t.contains('reolink')) return CameraBrand.reolink;
    if (t.contains('xiongmai')) return CameraBrand.xiongmai;
    return CameraBrand.custom;
  }

  String get snapshotUrl {
    final u = Uri.encodeQueryComponent(user);
    final p = Uri.encodeQueryComponent(password);
    return switch (brand) {
      CameraBrand.hikvision =>
        'http://$ip/ISAPI/Streaming/channels/${channel}01/picture',
      CameraBrand.dahua => 'http://$ip/cgi-bin/snapshot.cgi?channel=$channel',
      CameraBrand.reolink =>
        'http://$ip/cgi-bin/api.cgi?cmd=Snap&channel=${channel - 1}&rs=c212&user=$u&password=$p',
      CameraBrand.xiongmai =>
        'http://$ip/webcapture.jpg?command=snap&channel=${channel - 1}&user=$u&password=$p',
      CameraBrand.custom =>
        'http://$ip${customPath.startsWith('/') ? '' : '/'}$customPath',
    };
  }

  String get rtspUrl {
    final auth = user.isEmpty
        ? ''
        : '${Uri.encodeComponent(user)}:${Uri.encodeComponent(password)}@';
    return switch (brand) {
      CameraBrand.hikvision => 'rtsp://$auth$ip:554/Streaming/Channels/${channel}01',
      CameraBrand.dahua =>
        'rtsp://$auth$ip:554/cam/realmonitor?channel=$channel&subtype=0',
      CameraBrand.reolink =>
        'rtsp://$auth$ip:554/h264Preview_${channel.toString().padLeft(2, '0')}_main',
      CameraBrand.xiongmai =>
        'rtsp://$ip:554/user=$user&password=$password&channel=$channel&stream=0.sdp',
      CameraBrand.custom => 'rtsp://$auth$ip:554/',
    };
  }
}

/// One nearby Wi-Fi access point.
class WifiNeighbour {
  final String ssid;
  final String bssid;
  final int signalPercent;
  final int? channel;
  final String security;
  const WifiNeighbour({
    required this.ssid,
    required this.bssid,
    required this.signalPercent,
    required this.channel,
    required this.security,
  });
  bool get is5GHz => (channel ?? 0) > 14;
}

/// How crowded each channel is, and the one to move the router to.
class ChannelAdvice {
  /// channel → interference score (sum of overlapping neighbours' signal).
  final Map<int, double> load;
  final int? best;
  const ChannelAdvice(this.load, this.best);
}

class TrafficSample {
  final String adapter;
  final int rxBytes;
  final int txBytes;
  final int errors;
  final int discards;
  const TrafficSample(this.adapter, this.rxBytes, this.txBytes, this.errors, this.discards);
}

class ProcessConnections {
  final String process;
  final int pid;
  final int connections;
  final Set<String> remotes;
  const ProcessConnections(this.process, this.pid, this.connections, this.remotes);
}

/// Streams this machine's per-adapter byte counters about once a second.
class TrafficMonitor {
  Process? _process;
  Timer? _timer;
  bool _stopped = false;

  static const _windowsLoop = r'''
[Console]::OutputEncoding = [Text.Encoding]::UTF8
while ($true) {
  $s = @(Get-NetAdapterStatistics -ErrorAction SilentlyContinue | ForEach-Object {
    [ordered]@{ n = $_.Name; r = [int64]$_.ReceivedBytes; t = [int64]$_.SentBytes;
      e = [int64]$_.ReceivedPacketErrors + [int64]$_.OutboundPacketErrors;
      d = [int64]$_.ReceivedDiscardedPackets + [int64]$_.OutboundDiscardedPackets } })
  [Console]::Out.WriteLine((ConvertTo-Json -InputObject $s -Compress))
  [Console]::Out.Flush()
  Start-Sleep -Milliseconds 1000
}
''';

  Future<void> start(void Function(DateTime at, List<TrafficSample>) onSample) async {
    if (Platform.isWindows) {
      final p = await Process.start('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-EncodedCommand',
        DiagnosticsService._encode(_windowsLoop),
      ]);
      _process = p;
      p.stderr.drain<void>();
      p.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        if (_stopped) return;
        try {
          final j = jsonDecode(line.trim());
          final list = j is List ? j : [j];
          onSample(DateTime.now(), [
            for (final m in list.whereType<Map>())
              TrafficSample(
                '${m['n']}',
                DiagnosticsService._int(m['r']),
                DiagnosticsService._int(m['t']),
                DiagnosticsService._int(m['e']),
                DiagnosticsService._int(m['d']),
              ),
          ]);
        } catch (_) {}
      });
    } else {
      int read(String path) {
        try {
          return int.parse(File(path).readAsStringSync().trim());
        } catch (_) {
          return 0;
        }
      }

      void tick() {
        if (_stopped) return;
        final out = <TrafficSample>[];
        try {
          for (final e in Directory('/sys/class/net').listSync()) {
            final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
            if (name == 'lo') continue;
            final st = '${e.path}/statistics';
            out.add(TrafficSample(
              name,
              read('$st/rx_bytes'),
              read('$st/tx_bytes'),
              read('$st/rx_errors') + read('$st/tx_errors'),
              read('$st/rx_dropped') + read('$st/tx_dropped'),
            ));
          }
        } catch (_) {}
        onSample(DateTime.now(), out);
      }

      tick();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
    }
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _process?.kill();
    _process = null;
  }
}

class NetworkPrinterStatus {
  final bool reachable;
  final int? latencyMs;
  final String? error;
  final bool statusKnown;
  final bool offline;
  final bool paperOut;
  final bool paperLow;
  const NetworkPrinterStatus({
    required this.reachable,
    required this.latencyMs,
    this.error,
    this.statusKnown = false,
    this.offline = false,
    this.paperOut = false,
    this.paperLow = false,
  });
}

/// Formats a byte count for people: 12.3 GB.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = math.min(units.length - 1, (math.log(bytes) / math.log(1024)).floor());
  final v = bytes / math.pow(1024, i);
  return '${v.toStringAsFixed(v >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

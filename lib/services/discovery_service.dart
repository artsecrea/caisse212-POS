import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  return DiscoveryService();
});


class DiscoveryService {
  static BonsoirBroadcast? _broadcast;
  static bool _isSupported = true;

  // Check if discovery is supported on this platform
  static bool get isSupported => _isSupported && !kIsWeb;

  /// Best-effort LAN IPv4 for advertising the server to other devices
  /// (waiter app, KDS, kiosk) and for showing the "Server URL" in settings.
  ///
  /// Returning the *first* interface address (the old behavior) is wrong on
  /// typical Windows machines: they expose several adapters — Wi-Fi, Ethernet,
  /// plus virtual ones from VirtualBox / VMware / Hyper-V / WSL / Docker — and
  /// the first one is often a loopback (`127.x`), a link-local (`169.254.x`),
  /// or a host-only virtual address that phones on the real Wi-Fi can't reach.
  ///
  /// So we collect every IPv4 candidate and score it: real private LAN ranges
  /// win over everything, and physical adapters win over virtual ones. The
  /// highest score is the address most likely reachable from the LAN.
  static Future<String> getLocalIp() async {
    // 1) Ask the OS which interface it ACTUALLY uses to reach the network. This
    //    is the single most reliable signal — it returns the real LAN adapter,
    //    not a VirtualBox/WSL/Hyper-V host-only one — and sidesteps the guessing
    //    the scoring below has to do. Only trusted when it yields a private LAN
    //    address (a phone/KDS on the same LAN can only reach a private IP).
    final routed = await _localIpViaRoute();
    if (routed != null && _isPrivateLan(routed)) return routed;

    // 2) Offline / no route: fall back to scoring every candidate.
    final candidates = await _rankedCandidates();
    if (candidates.isNotEmpty) return candidates.first;

    // 3) Last resort: whatever the route trick gave (may be a public IP), else
    //    the routed value or 'unknown'.
    return routed ?? 'unknown';
  }

  /// Every usable LAN IPv4 on this machine, best-first. Lets the settings UI
  /// offer a picker when auto-detection guesses wrong (dual-NIC machines, etc.).
  static Future<List<String>> getLocalIpCandidates() async {
    final list = <String>[];
    final routed = await _localIpViaRoute();
    if (routed != null && _isPrivateLan(routed)) list.add(routed);
    for (final ip in await _rankedCandidates()) {
      if (!list.contains(ip)) list.add(ip);
    }
    return list;
  }

  /// The local address of the interface the OS routes outbound traffic through.
  /// Opens a short-lived socket to a public resolver; `socket.address` is the
  /// LOCAL endpoint the OS bound — i.e. this machine's real LAN IP. No data is
  /// exchanged with the resolver beyond the TCP handshake, and it fails fast
  /// (returns null) when the box is offline.
  static Future<String?> _localIpViaRoute() async {
    for (final target in const ['8.8.8.8', '1.1.1.1']) {
      Socket? socket;
      try {
        socket = await Socket.connect(target, 53,
            timeout: const Duration(milliseconds: 600));
        final ip = socket.address.address;
        if (ip.isNotEmpty &&
            !ip.startsWith('127.') &&
            !ip.startsWith('169.254.')) {
          return ip;
        }
      } catch (_) {
        // offline / blocked — try the next target, then fall back to scoring.
      } finally {
        socket?.destroy();
      }
    }
    return null;
  }

  /// All non-loopback IPv4 addresses, sorted by how likely they are to be the
  /// reachable LAN address (best first).
  static Future<List<String>> _rankedCandidates() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      // Interface-name hints that mark a virtual / non-physical adapter.
      const virtualHints = [
        'virtual', 'vbox', 'virtualbox', 'vmware', 'hyper-v', 'vethernet',
        'wsl', 'docker', 'loopback', 'bluetooth', 'tap', 'tun', 'zerotier',
        'radmin', 'hamachi', 'npcap',
      ];

      final scored = <MapEntry<String, int>>[];

      for (final interface in interfaces) {
        final name = interface.name.toLowerCase();
        final isVirtual = virtualHints.any((h) => name.contains(h));
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (addr.isLoopback ||
              ip.startsWith('127.') ||
              ip.startsWith('169.254.')) {
            continue;
          }

          var score = 0;
          if (ip.startsWith('192.168.')) {
            score += 100; // the overwhelmingly common home/office LAN range
          } else if (ip.startsWith('10.')) {
            score += 80;
          } else if (_is172Private(ip)) {
            score += 60; // 172.16–31.x (also where WSL/Hyper-V often live)
          } else {
            score += 20; // some other routable address
          }
          if (!isVirtual) score += 50; // prefer physical adapters

          // Explicit penalties for subnets that are almost always a virtual /
          // host-only adapter unreachable from the real LAN — these are the
          // usual culprits behind a "wrong IP that nothing can connect to".
          if (ip.startsWith('192.168.56.')) score -= 90; // VirtualBox host-only
          if (ip.startsWith('192.168.99.')) score -= 90; // docker-machine
          if (ip.startsWith('172.17.') ||
              ip.startsWith('172.18.') ||
              ip.startsWith('172.19.')) {
            score -= 70; // Docker / WSL2 / Hyper-V default switch
          }

          scored.add(MapEntry(ip, score));
        }
      }

      scored.sort((a, b) => b.value.compareTo(a.value));
      return scored.map((e) => e.key).toList();
    } catch (e) {
      debugPrint('Failed to enumerate interfaces: $e');
      return const [];
    }
  }

  /// True for RFC-1918 private ranges (10/8, 172.16–31/12, 192.168/16).
  static bool _isPrivateLan(String ip) =>
      ip.startsWith('192.168.') || ip.startsWith('10.') || _is172Private(ip);

  /// True for the private block 172.16.0.0 – 172.31.255.255.
  static bool _is172Private(String ip) {
    if (!ip.startsWith('172.')) return false;
    final parts = ip.split('.');
    if (parts.length < 2) return false;
    final second = int.tryParse(parts[1]);
    return second != null && second >= 16 && second <= 31;
  }

  // 1️⃣ Just announce
  Future<void> announce(String deviceName, String? ip, int? port) async {
    // Skip on unsupported platforms or if previously failed
    if (!_isSupported) {
      debugPrint('Discovery service not supported, skipping announce');
      return;
    }

    // On Windows, Bonjour service may not be available - add extra safety
    if (Platform.isWindows) {
      try {
        await _doAnnounce(deviceName, ip, port).timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('⚠️ Discovery announce timed out on Windows');
            _isSupported = false;
          },
        );
      } catch (e) {
        debugPrint('❌ Discovery announce failed on Windows: $e');
        _isSupported = false;
      }
      return;
    }

    await _doAnnounce(deviceName, ip, port);
  }

  Future<void> _doAnnounce(String deviceName, String? ip, int? port) async {
    try {
      await _broadcast?.stop();

      final localIp = ip ?? await getLocalIp();

      final service = BonsoirService(
        type: '_caisse212._tcp',
        name: deviceName,
        port: 12345,
        attributes: {
          'name': deviceName,
          'ip': localIp,
          'port': port.toString(),
        },
      );

      _broadcast = BonsoirBroadcast(service: service);
      await _broadcast?.ready;
      await _broadcast?.start();

      debugPrint('✅ Announcing: $deviceName ($localIp) on port $port');
    } catch (e) {
      debugPrint('❌ Discovery announce failed: $e');
      // Mark as unsupported to avoid future crashes
      _isSupported = false;
    }
  }

  // 2️⃣ Just discover - returns devices
  Future<List<Map<String, String>>> discover(Duration duration) async {
    final devices = <Map<String, String>>[];

    // Skip if not supported
    if (!_isSupported) {
      debugPrint('Discovery service not supported, returning empty list');
      return devices;
    }

    try {
      final completer = Completer<List<Map<String, String>>>();

      final discovery = BonsoirDiscovery(type: '_caisse212._tcp');

      discovery.eventStream!.listen((event) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          final service = event.service!;

          // Get IP from attributes
          final ip = service.attributes['ip'] ?? 'unknown';
          final name = service.attributes['name'] ?? service.name;
          final port = service.attributes['port'] ?? 'unknown';

          devices.add({
            'name': name,
            'ip': ip,
            "port": port,
          });

          debugPrint('📱 Found: $name at $ip');
        }
      });

      await discovery.ready;
      await discovery.start();

      Timer(duration, () async {
        await discovery.stop();
        completer.complete(devices);
      });

      return completer.future;
    } catch (e) {
      debugPrint('❌ Discovery failed: $e');
      _isSupported = false;
      return devices;
    }
  }

  Future<void> stopAnnounce() async {
    try {
      await _broadcast?.stop();
    } catch (e) {
      debugPrint('Failed to stop announce: $e');
    }
  }
}
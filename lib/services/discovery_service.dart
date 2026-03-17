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

  // Get local IP (public)
  static Future<String> getLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to get local IP: $e');
    }
    return 'unknown';
  }

  // 1️⃣ Just announce
  Future<void> announce(String deviceName, String? ip, int? port) async {
    // Skip on unsupported platforms or if previously failed
    if (!_isSupported) {
      debugPrint('Discovery service not supported, skipping announce');
      return;
    }

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
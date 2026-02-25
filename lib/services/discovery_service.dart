import 'dart:async';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final discoveryServiceProvider = Provider<DiscoveryService>((ref) {
  return DiscoveryService();
});


class DiscoveryService {
  static BonsoirBroadcast? _broadcast;

  // Get local IP
  static Future<String> _getLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {}
    return 'unknown';
  }

  // 1️⃣ Just announce
   Future<void> announce(String deviceName, String? ip, int? port) async {
    await _broadcast?.stop();

    final localIp = ip ?? await _getLocalIp();

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

    print('✅ Announcing: $deviceName ($localIp) on port $port');
  }

  // 2️⃣ Just discover - returns devices
   Future<List<Map<String, String>>> discover(Duration duration) async {
    final devices = <Map<String, String>>[];
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

        print('📱 Found: $name at $ip');
      }
    });

    await discovery.ready;
    await discovery.start();

    Timer(duration, () async {
      await discovery.stop();
      completer.complete(devices);
    });

    return completer.future;
  }

   Future<void> stopAnnounce() async {
    await _broadcast?.stop();
  }
}
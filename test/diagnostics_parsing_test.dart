import 'package:flutter_test/flutter_test.dart';
import 'package:caisse212/services/diagnostics_service.dart';
import 'package:caisse212/services/network_watch_service.dart';

void main() {
  group('netsh wlan show interfaces', () {
    test('English', () {
      const out = '''
There is 1 interface on the system:

    Name                   : Wi-Fi
    Description            : Intel(R) Wi-Fi 6 AX200 160MHz
    Physical address       : a4:b1:c1:dd:1e:f9
    State                  : connected
    SSID                   : La_Fibre_dOrange_FCCC
    BSSID                  : 58:d3:12:50:fc:cd
    Network type           : Infrastructure
    Radio type             : 802.11ax
    Authentication         : WPA3-Personal  (H2E)
    Channel                : 60
    Receive rate (Mbps)    : 1201
    Transmit rate (Mbps)   : 866.7
    Signal                 : 97%
    Profile                : La_Fibre_dOrange_FCCC
''';
      final w = DiagnosticsService.parseNetshWlan(out)!;
      expect(w.connected, isTrue);
      expect(w.adapter, 'Wi-Fi');
      expect(w.ssid, 'La_Fibre_dOrange_FCCC');
      expect(w.bssid, '58:d3:12:50:fc:cd');
      expect(w.signalPercent, 97);
      expect(w.receiveMbps, 1201);
      expect(w.transmitMbps, 866.7);
      expect(w.channel, 60);
      expect(w.band, '5 GHz');
      expect(w.radio, '802.11ax');
      expect(w.security, startsWith('WPA3'));
    });

    test('French', () {
      const out = '''
    Nom                    : Wi-Fi
    État                   : connecté
    SSID                   : Caisse
    BSSID                  : 11:22:33:44:55:66
    Type de radio          : 802.11n
    Authentification       : WPA2 - Personnel
    Canal                  : 6
    Réception (Mbits/s)    : 72,2
    Transmission (Mbits/s) : 65
    Signal                 : 41 %
''';
      final w = DiagnosticsService.parseNetshWlan(out)!;
      expect(w.ssid, 'Caisse');
      expect(w.signalPercent, 41);
      expect(w.receiveMbps, 72.2);
      expect(w.transmitMbps, 65);
      expect(w.channel, 6);
      expect(w.band, '2.4 GHz');
    });

    test('disconnected interface has no SSID', () {
      const out = '''
    Name                   : Wi-Fi
    State                  : disconnected
''';
      expect(DiagnosticsService.parseNetshWlan(out)!.connected, isFalse);
    });

    test('no Wi-Fi adapter', () {
      expect(DiagnosticsService.parseNetshWlan(''), isNull);
    });
  });

  group('ping times', () {
    test('Windows English, summary ignored', () {
      const out = '''
Pinging 192.168.1.1 with 32 bytes of data:
Reply from 192.168.1.1: bytes=32 time=3ms TTL=64
Reply from 192.168.1.1: bytes=32 time<1ms TTL=64
Request timed out.

Ping statistics for 192.168.1.1:
    Packets: Sent = 3, Received = 2, Lost = 1 (33% loss),
Approximate round trip times in milli-seconds:
    Minimum = 0ms, Maximum = 3ms, Average = 1ms
''';
      expect(DiagnosticsService.parsePingTimes(out), [3, 1]);
    });

    test('Windows French and Spanish', () {
      const fr = 'Réponse de 10.0.0.1 : octets=32 temps=12 ms TTL=128\n'
          '    Minimum = 12ms, Maximum = 12ms, Moyenne = 12ms';
      const es = 'Respuesta desde 10.0.0.1: bytes=32 tiempo=7ms TTL=128\n'
          '    Mínimo = 7ms, Máximo = 7ms, Media = 7ms';
      expect(DiagnosticsService.parsePingTimes(fr), [12]);
      expect(DiagnosticsService.parsePingTimes(es), [7]);
    });

    test('Linux', () {
      const out = '64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=14.2 ms\n'
          'rtt min/avg/max/mdev = 14.2/14.2/14.2/0.000 ms';
      expect(DiagnosticsService.parsePingTimes(out), [14.2]);
    });
  });

  test('nmcli active network, escaped colons in BSSID', () {
    const out = ' :Neighbour:AA\\:BB\\:CC\\:DD\\:EE\\:FF:30:54 Mbit/s:1:WPA2\n'
        '*:Caisse:11\\:22\\:33\\:44\\:55\\:66:78:270 Mbit/s:36:WPA2\n';
    final w = DiagnosticsService.parseNmcli(out)!;
    expect(w.ssid, 'Caisse');
    expect(w.bssid, '11:22:33:44:55:66');
    expect(w.signalPercent, 78);
    expect(w.receiveMbps, 270);
    expect(w.band, '5 GHz');
  });

  test('printer status flags', () {
    const p = OsPrinter(
        name: 'EPSON', port: 'ESDPRT001', jobs: 17, statusFlags: 4224, driver: '');
    expect(p.problems, contains('diag_printer_offline'));
    expect(const OsPrinter(
            name: 'Microsoft Print to PDF',
            port: 'PORTPROMPT:',
            jobs: 0,
            statusFlags: 0,
            driver: '')
        .isVirtual, isTrue);
  });

  test('netsh nearby networks, one entry per access point', () {
    const out = """
SSID 1 : HUAWEI-2.4G-U5b4
    Network type            : Infrastructure
    Authentication          : WPA2-Personal
    Encryption              : CCMP
    BSSID 1                 : 2e:0b:ab:d6:b7:bc
         Signal             : 26%
         Radio type         : 802.11ax
         Channel            : 11
         Basic rates (Mbps) : 1 2 5.5 11
    BSSID 2                 : 2e:0b:ab:d6:b7:bd
         Signal             : 61%
         Channel            : 44

SSID 2 :
    Authentication          : Open
    BSSID 1                 : be:bd:84:13:6c:80
         Signal             : 40%
         Channel            : 4
""";
    final n = DiagnosticsService.parseNetshNetworks(out);
    expect(n, hasLength(3));
    expect(n[0].ssid, 'HUAWEI-2.4G-U5b4');
    expect(n[0].signalPercent, 26);
    expect(n[0].channel, 11);
    expect(n[1].channel, 44);
    expect(n[1].is5GHz, isTrue);
    expect(n[2].ssid, '');
    expect(n[2].security, 'Open');
  });

  test('channel advice avoids the crowded 2.4 GHz channel', () {
    WifiNeighbour net(int ch, int signal) => WifiNeighbour(
        ssid: 'x', bssid: 'b$ch$signal', signalPercent: signal, channel: ch, security: '');
    final a = DiagnosticsService.channelAdvice(
        [net(1, 80), net(2, 70), net(11, 60), net(10, 50)],
        fiveGHz: false);
    expect(a.best, 6);
  });

  test('device kinds', () {
    expect(const LanHost(ip: '1', openPorts: {9100}).kind, DeviceKind.printer);
    expect(const LanHost(ip: '1', openPorts: {554}).kind, DeviceKind.camera);
    expect(const LanHost(ip: '1', openPorts: {}, vendor: 'Hangzhou Hikvision Digital Technology Co.,Ltd.').kind,
        DeviceKind.camera);
    expect(const LanHost(ip: '1', openPorts: {62078}).kind, DeviceKind.phone);
    expect(const LanHost(ip: '1', openPorts: {}, mac: 'DA:11:22:33:44:55').kind,
        DeviceKind.phone);
    expect(const LanHost(ip: '1', openPorts: {445}).kind, DeviceKind.computer);
    expect(const LanHost(ip: '1', openPorts: {8080}, isCaisse: true).kind,
        DeviceKind.caisse);
    expect(const LanHost(ip: '1', openPorts: {}).kind, DeviceKind.unknown);
  });

  group('camera links', () {
    test('Hikvision channel 2', () {
      const c = CameraSettings(
          ip: '192.168.1.64', brand: CameraBrand.hikvision, user: 'admin', password: 'p@ss', channel: 2);
      expect(c.snapshotUrl, 'http://192.168.1.64/ISAPI/Streaming/channels/201/picture');
      expect(c.rtspUrl, 'rtsp://admin:p%40ss@192.168.1.64:554/Streaming/Channels/201');
    });
    test('Dahua', () {
      const c = CameraSettings(
          ip: '10.0.0.5', brand: CameraBrand.dahua, user: 'admin', password: 'x');
      expect(c.snapshotUrl, 'http://10.0.0.5/cgi-bin/snapshot.cgi?channel=1');
      expect(c.rtspUrl, contains('/cam/realmonitor?channel=1&subtype=0'));
    });
    test('brand from vendor', () {
      expect(CameraSettings.guessBrand('Hangzhou Hikvision Digital Technology'),
          CameraBrand.hikvision);
      expect(CameraSettings.guessBrand('Zhejiang Dahua Technology'), CameraBrand.dahua);
      expect(CameraSettings.guessBrand('Acme'), CameraBrand.custom);
    });
  });

  test('watch events survive a save and reload', () {
    final e = WatchEvent(
        kind: WatchKind.printer,
        label: 'Kitchen',
        address: '192.168.1.50:9100',
        down: DateTime(2026, 10, 28, 13, 2),
        up: DateTime(2026, 10, 28, 13, 15));
    final back = WatchEvent.fromJson(e.toJson())!;
    expect(back.kind, WatchKind.printer);
    expect(back.address, '192.168.1.50:9100');
    expect(back.duration(), const Duration(minutes: 13));
    expect(WatchEvent.fromJson({'k': 'nope', 'd': 'x'}), isNull);
  });
}

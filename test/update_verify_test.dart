import 'dart:convert';

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:caisse212/services/api_service.dart';
import 'package:caisse212/services/update_config.dart';
import 'package:caisse212/services/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SimpleKeyPair keyPair;
  late UpdateService service;
  final platform = UpdateService.currentPlatform;

  Map<String, dynamic> manifest({
    String app = 'pos',
    String? plat,
    int build = 8,
  }) =>
      {
        'app': app,
        'platform': plat ?? platform,
        'version': '1.1.9',
        'buildNumber': build,
        'downloadUrl': 'https://dl.example.com/pos/$platform/$build/pos.zip',
        'sha256': 'ab' * 32,
        'sizeBytes': 1234,
        'mandatory': false,
      };

  Future<Map<String, dynamic>> signed(Map<String, dynamic> m,
      {String kid = 'test', SimpleKeyPair? signer}) async {
    final bytes = utf8.encode(jsonEncode(m));
    final sig = await Ed25519().sign(bytes, keyPair: signer ?? keyPair);
    return {
      // Unsigned body fields deliberately disagree with the manifest.
      'version': '9.9.9',
      'buildNumber': 999,
      'downloadUrl': 'https://evil.example.com/x.zip',
      'sha256': '00',
      'releaseNotes': 'notes',
      'app': m['app'],
      'manifest': base64.encode(bytes),
      'signature': base64.encode(sig.bytes),
      'kid': kid,
    };
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    keyPair = await Ed25519().newKeyPair();
    final pub = await keyPair.extractPublicKey();
    service = UpdateService(ApiService(prefs), prefs,
        pinnedKeys: {'test': base64.encode(pub.bytes)});
  });

  test('accepts a valid release and takes values only from the manifest',
      () async {
    final info = await service.verify(await signed(manifest()), 7);
    expect(info, isNotNull);
    expect(info!.buildNumber, 8);
    expect(info.version, '1.1.9');
    expect(info.downloadUrl, startsWith('https://dl.example.com/'));
    expect(info.checksum, 'ab' * 32);
    expect(info.sizeBytes, 1234);
    expect(info.releaseNotes, 'notes');
  });

  test('accepts an unsigned release (empty kid and signature)', () async {
    final body = await signed(manifest())
      ..['kid'] = ''
      ..['signature'] = '';
    final info = await service.verify(body, 7);
    expect(info?.buildNumber, 8);
    expect(info?.downloadUrl, startsWith('https://dl.example.com/'));
  });

  test('an unknown kid is treated as unsigned, not rejected', () async {
    expect(await service.verify(await signed(manifest(), kid: 'other'), 7),
        isNotNull);
  });

  test('unsigned releases still enforce app, platform and build', () async {
    Future<UpdateInfo?> unsigned(Map<String, dynamic> m) async =>
        service.verify(
            (await signed(m))
              ..['kid'] = ''
              ..['signature'] = '',
            7);
    expect(await unsigned(manifest(app: 'kds')), isNull);
    expect(await unsigned(manifest(build: 7)), isNull);
    final other = platform == 'windows' ? 'linux' : 'windows';
    expect(await unsigned(manifest(plat: other)), isNull);
  });

  test('rejects a signature from another key', () async {
    final stranger = await Ed25519().newKeyPair();
    expect(await service.verify(await signed(manifest(), signer: stranger), 7),
        isNull);
  });

  test('rejects a tampered manifest', () async {
    final body = await signed(manifest());
    final m = manifest()..['downloadUrl'] = 'https://evil.example.com/x.zip';
    body['manifest'] = base64.encode(utf8.encode(jsonEncode(m)));
    expect(await service.verify(body, 7), isNull);
  });

  test('rejects another app or platform', () async {
    expect(await service.verify(await signed(manifest(app: 'kds')), 7), isNull);
    final other = platform == 'windows' ? 'linux' : 'windows';
    expect(await service.verify(await signed(manifest(plat: other)), 7),
        isNull);
  });

  test('follows the configured app name', () async {
    await service.setAppSlug(' KDS ');
    expect(service.appSlug, 'kds');
    expect(await service.verify(await signed(manifest(app: 'kds')), 7),
        isNotNull);
    expect(await service.verify(await signed(manifest()), 7), isNull);

    await service.setAppSlug('');
    expect(service.appSlug, 'pos');
  });

  test('never downgrades or reinstalls the installed build', () async {
    expect(await service.verify(await signed(manifest(build: 7)), 7), isNull);
    expect(await service.verify(await signed(manifest(build: 6)), 7), isNull);
  });

  test('rejects a body with no manifest', () async {
    expect(await service.verify(manifest(), 7), isNull);
  });

  test('every pinned key is a raw 32-byte ed25519 key', () {
    for (final key in UpdateConfig.pinnedKeys.values) {
      expect(base64.decode(key).length, 32);
    }
  });
}

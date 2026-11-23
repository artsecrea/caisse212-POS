import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:caisse212/services/prefs_recovery_service.dart';

/// A power cut mid-save leaves shared_preferences.json broken and the till
/// failing every launch with "FormatException … Please restart".
void main() {
  late Directory dir;
  File prefs() => File(p.join(dir.path, PrefsRecoveryService.fileName));
  File lastGood() => File(p.join(dir.path, PrefsRecoveryService.lastGoodName));
  List<FileSystemEntity> corrupt() => dir
      .listSync()
      .where((f) => p.basename(f.path).contains('.corrupt-'))
      .toList();

  setUp(() => dir = Directory.systemTemp.createTempSync('prefs_recovery'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a healthy file is left alone and copied aside', () {
    prefs().writeAsStringSync('{"flutter.api_base_url":"https://x"}');

    expect(PrefsRecoveryService.repairIn(dir), isNull);
    expect(prefs().readAsStringSync(), '{"flutter.api_base_url":"https://x"}');
    expect(lastGood().readAsStringSync(), '{"flutter.api_base_url":"https://x"}');
  });

  test('a half-written file is replaced by the last good copy', () {
    prefs().writeAsStringSync('{"flutter.api_base_url":"https://x"}');
    PrefsRecoveryService.repairIn(dir);

    prefs().writeAsStringSync('{"flutter.api_base_url":"htt');
    expect(PrefsRecoveryService.repairIn(dir), contains('restored'));
    expect(prefs().readAsStringSync(), '{"flutter.api_base_url":"https://x"}');
    expect(corrupt(), hasLength(1));
  });

  test('a file of NUL bytes is treated as broken', () {
    prefs().writeAsStringSync('{"a":1}');
    PrefsRecoveryService.repairIn(dir);

    prefs().writeAsBytesSync(List.filled(8000, 0));
    expect(PrefsRecoveryService.repairIn(dir), contains('restored'));
    expect(prefs().readAsStringSync(), '{"a":1}');
  });

  test('a zero-byte file is a crash, not a clear', () {
    prefs().writeAsStringSync('{"a":1}');
    PrefsRecoveryService.repairIn(dir);

    prefs().writeAsStringSync('');
    expect(PrefsRecoveryService.repairIn(dir), contains('restored'));
    expect(prefs().readAsStringSync(), '{"a":1}');
  });

  test('a deliberate clear is not undone', () {
    prefs().writeAsStringSync('{"a":1}');
    PrefsRecoveryService.repairIn(dir);

    prefs().writeAsStringSync('{}');
    expect(PrefsRecoveryService.repairIn(dir), isNull);
    expect(prefs().readAsStringSync(), '{}');
  });

  test('broken with no good copy: moved aside so the app can still start', () {
    prefs().writeAsStringSync('{"a":');

    expect(PrefsRecoveryService.repairIn(dir), contains('empty settings'));
    expect(prefs().existsSync(), isFalse);
    expect(corrupt(), hasLength(1));
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences_platform_interface/types.dart';

import 'package:caisse212/services/prefs_recovery_service.dart';
import 'package:caisse212/services/safe_prefs_store.dart';

/// Settings that "reset by themselves": half-written saves restored from the
/// launch-time copy, and two tills on one machine undoing each other.
void main() {
  late Directory dir;
  File prefs() => File(p.join(dir.path, PrefsRecoveryService.fileName));
  Map<String, dynamic> onDisk() =>
      json.decode(prefs().readAsStringSync()) as Map<String, dynamic>;
  Future<Map<String, Object>> all(SafePrefsStore s) => s.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));

  setUp(() => dir = Directory.systemTemp.createTempSync('safe_prefs'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('reads what the plugin wrote, string lists included', () async {
    prefs().writeAsStringSync(
        '{"flutter.printer_kds_name":"Kitchen","flutter.order":["a","b"]}');
    final values = await all(SafePrefsStore(dir.path));
    expect(values['flutter.printer_kds_name'], 'Kitchen');
    expect(values['flutter.order'], isA<List<String>>());
  });

  test('a save leaves a whole file and no temp behind', () async {
    final store = SafePrefsStore(dir.path);
    await store.setValue('String', 'flutter.printer_kds_name', 'Kitchen');
    await store.setValue('Int', 'flutter.printer_paper_size', 3);
    expect(onDisk(), {
      'flutter.printer_kds_name': 'Kitchen',
      'flutter.printer_paper_size': 3,
    });
    expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
  });

  test('two processes on one file keep each other\'s changes', () async {
    prefs().writeAsStringSync('{"flutter.language":"fr"}');
    final till = SafePrefsStore(dir.path);
    final other = SafePrefsStore(dir.path);
    await all(till);
    await all(other);

    await till.setValue('String', 'flutter.printer_kds_name', 'Kitchen');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await other.setValue('Bool', 'flutter.isDarkMode', true);

    expect(onDisk(), {
      'flutter.language': 'fr',
      'flutter.printer_kds_name': 'Kitchen',
      'flutter.isDarkMode': true,
    });
  });

  test('remove and clear only touch what they name', () async {
    prefs().writeAsStringSync(
        '{"flutter.a":1,"flutter.b":2,"other.c":3}');
    final store = SafePrefsStore(dir.path);
    await store.remove('flutter.a');
    expect(onDisk(), {'flutter.b': 2, 'other.c': 3});
    await store.clear();
    expect(onDisk(), {'other.c': 3});
  });

  test('back-to-back saves without awaiting all land', () async {
    final store = SafePrefsStore(dir.path);
    await Future.wait([
      for (var i = 0; i < 30; i++) store.setValue('Int', 'flutter.k$i', i),
    ]);
    expect(onDisk(), hasLength(30));
  });
}

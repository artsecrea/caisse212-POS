@TestOn('windows')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Compiles windows/updater/caisse212_updater.cs the way build_windows.ps1
/// does and runs it detached against a throwaway install. --test-relaunch
/// swaps the relaunch for a line in a file so no app starts.
void main() {
  late Directory root;
  late String appDir, extract, tmp, updater;
  final ping = r'C:\Windows\System32\PING.EXE';
  final csc = p.join(Platform.environment['WINDIR'] ?? r'C:\Windows',
      r'Microsoft.NET\Framework64\v4.0.30319\csc.exe');

  void write(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  String read(String path) => File(path).readAsStringSync();

  setUpAll(() {
    final out = Directory.systemTemp.createTempSync('upd_exe_build_');
    updater = p.join(out.path, 'caisse212-updater.exe');
    final r = Process.runSync(csc, [
      '-nologo',
      '-target:winexe',
      '-codepage:65001',
      '-out:$updater',
      '-r:System.Windows.Forms.dll',
      '-r:System.Drawing.dll',
      p.join('windows', 'updater', 'caisse212_updater.cs'),
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
  });

  setUp(() {
    root = Directory.systemTemp.createTempSync('upd_exe_');
    appDir = p.join(root.path, 'app');
    extract = p.join(root.path, 'tmp', 'caisse212-update-extracted');
    tmp = p.join(root.path, 'tmp');
    write(p.join(appDir, 'caisse212.exe'), 'old exe');
    write(p.join(appDir, 'data', 'app.so'), 'old so');
    write(p.join(appDir, 'keep.txt'), 'admin file');
    write(p.join(appDir, 'local.db'), 'live db');
    write(p.join(appDir, 'support', 'tool.dll'), 'old tool');
    write(p.join(extract, 'caisse212.exe'), 'new exe');
    write(p.join(extract, 'data', 'app.so'), 'new so');
    write(p.join(extract, 'local.db'), 'shipped db');
    write(p.join(extract, 'support', 'tool.dll'), 'new tool');
    write(p.join(tmp, 'caisse212-update.ready'), '{}');
  });

  tearDown(() async {
    for (var i = 0; i < 10; i++) {
      try {
        root.deleteSync(recursive: true);
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
  });

  Future<String> run(int waitPid) async {
    final relaunch = p.join(tmp, 'relaunch.txt');
    await Process.start(
        updater,
        [
          '--source', extract,
          '--app-dir', appDir,
          '--exe', p.join(appDir, 'caisse212.exe'),
          '--tmp', tmp,
          '--pid', '$waitPid',
          '--version', '9.9.9',
          '--lang', 'fr',
          '--test-relaunch', relaunch,
        ],
        mode: ProcessStartMode.detached);
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (!File(relaunch).existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        final log = File(p.join(tmp, 'caisse212-update.log'));
        fail('updater did not finish:\n'
            '${log.existsSync() ? log.readAsStringSync() : '(no log)'}');
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    await Future.delayed(const Duration(milliseconds: 300));
    return read(p.join(tmp, 'caisse212-update.log'));
  }

  test('waits for the app to exit, then installs and clears the marker',
      () async {
    final app = await Process.start(ping, ['-n', '5', '127.0.0.1']);
    final sw = Stopwatch()..start();
    final log = await run(app.pid);
    sw.stop();

    expect(sw.elapsed.inSeconds, greaterThanOrEqualTo(4),
        reason: 'must not copy while the old process is alive');
    expect(log, contains('ok'));
    expect(read(p.join(appDir, 'caisse212.exe')), 'new exe');
    expect(read(p.join(appDir, 'data', 'app.so')), 'new so');
    expect(read(p.join(appDir, 'keep.txt')), 'admin file');
    expect(read(p.join(appDir, 'local.db')), 'live db');
    expect(read(p.join(appDir, 'support', 'tool.dll')), 'new tool');
    expect(File(p.join(tmp, 'caisse212-update.ready')).existsSync(), isFalse);
    expect(Directory(extract).existsSync(), isFalse);
    expect(read(p.join(tmp, 'relaunch.txt')),
        contains(p.join(appDir, 'caisse212.exe')));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a running support tool is left alone and does not roll back the POS',
      () async {
    final tool = p.join(appDir, 'support', 'caisse212-support.exe');
    File(ping).copySync(tool);
    write(p.join(extract, 'support', 'caisse212-support.exe'), 'new tool exe');
    final running = await Process.start(tool, ['-n', '60', '127.0.0.1']);
    try {
      final log = await run(999999);
      expect(log, contains('support tool running'));
      expect(log, contains('ok'));
      expect(read(p.join(appDir, 'caisse212.exe')), 'new exe');
      expect(read(p.join(appDir, 'support', 'tool.dll')), 'old tool');
    } finally {
      running.kill();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a locked app file rolls back and keeps the marker for a retry',
      () async {
    final locked = p.join(appDir, 'locked.exe');
    File(ping).copySync(locked);
    write(p.join(extract, 'locked.exe'), 'replacement');
    final running = await Process.start(locked, ['-n', '120', '127.0.0.1']);
    try {
      final log = await run(999999);
      expect(log, contains('rolling back'));
      expect(read(p.join(appDir, 'caisse212.exe')), 'old exe');
      expect(read(p.join(appDir, 'data', 'app.so')), 'old so');
      expect(File(p.join(tmp, 'caisse212-update.ready')).existsSync(), isTrue);
      expect(read(p.join(tmp, 'relaunch.txt')),
          contains(p.join(appDir, 'caisse212.exe')));
    } finally {
      running.kill();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}

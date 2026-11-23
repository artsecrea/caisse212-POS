@TestOn('windows')
library;

import 'dart:io';

import 'package:caisse212/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Runs the real updater .bat against a throwaway install. The relaunch is
/// swapped for an echo so no app starts.
void main() {
  late Directory root;
  late String appDir, extract, tmp;
  final ping = r'C:\Windows\System32\PING.EXE';

  void write(String path, String content) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  String read(String path) => File(path).readAsStringSync();

  setUp(() {
    root = Directory.systemTemp.createTempSync('upd_bat_');
    appDir = p.join(root.path, 'app');
    extract = p.join(root.path, 'tmp', 'caisse212-update-extracted');
    tmp = p.join(root.path, 'tmp');
    write(p.join(appDir, 'caisse212.exe'), 'old exe');
    write(p.join(appDir, 'data', 'app.so'), 'old so');
    write(p.join(appDir, 'keep.txt'), 'admin file');
    write(p.join(appDir, 'support', 'tool.dll'), 'old tool');
    write(p.join(extract, 'caisse212.exe'), 'new exe');
    write(p.join(extract, 'data', 'app.so'), 'new so');
    write(p.join(extract, 'support', 'tool.dll'), 'new tool');
    write(p.join(tmp, 'caisse212-update.ready'), '{}');
  });

  tearDown(() async {
    // Processes started by a test may still hold files for a moment.
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
    final script = UpdateService.windowsUpdaterScript(
            extract, appDir, p.join(appDir, 'caisse212.exe'), tmp, waitPid)
        .replaceAll('explorer.exe "!RELAUNCH!"',
            'echo RELAUNCH=!RELAUNCH!>>"${p.join(tmp, 'relaunch.txt')}"')
        // Self-delete would race the assertions on the log; keep the file.
        .replaceAll('(goto) 2>nul & del "%~f0"', 'goto :eof');
    final bat = p.join(tmp, 'u.bat');
    File(bat).writeAsStringSync(script);
    // Detached, exactly as the app launches it: with no console a piped
    // `| find` never ends, which a console-attached run does not show.
    await Process.start('cmd', ['/c', bat],
        mode: ProcessStartMode.detached, runInShell: false);
    // Every path ends in a relaunch, so its echo marks the script done.
    final done = File(p.join(tmp, 'relaunch.txt'));
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (!done.existsSync()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('updater did not finish:\n'
            '${File(p.join(tmp, 'caisse212-update.log')).existsSync() ? read(p.join(tmp, 'caisse212-update.log')) : '(no log)'}');
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

import 'dart:io';

import 'package:bcrypt/bcrypt.dart';
import 'package:caisse212/services/os_accounts/linux_os_accounts.dart';
import 'package:caisse212/services/os_accounts/os_account_service.dart';
import 'package:caisse212/services/os_accounts/windows_os_accounts.dart';
import 'package:caisse212/services/remote_support_service.dart';
import 'package:caisse212/services/shared_storage.dart';
import 'package:caisse212/utils/super_admin_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('super admin code', () {
    final today = DateTime(2026, 10, 10, 15, 30);

    test('date key is yyyy-MM-dd of the local date', () {
      expect(superAdminDateKey(today), '2026-10-10');
      expect(superAdminDateKey(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('accepts any fresh bcrypt hash of today', () {
      final hash = BCrypt.hashpw('2026-10-10', BCrypt.gensalt(logRounds: 4));
      expect(superAdminCodeAccepted(hash, now: today), isTrue);
      expect(superAdminCodeAccepted('  $hash \n', now: today), isTrue);
    });

    test('accepts the \$2b and \$2y prefixes other tools emit', () {
      final hash = BCrypt.hashpw('2026-10-10', BCrypt.gensalt(logRounds: 4));
      for (final pre in [r'$2b$', r'$2y$']) {
        expect(superAdminCodeAccepted(pre + hash.substring(4), now: today),
            isTrue, reason: pre);
      }
    });

    test('rejects yesterday, the plain date, and garbage', () {
      final yesterday =
          BCrypt.hashpw('2026-10-09', BCrypt.gensalt(logRounds: 4));
      expect(superAdminCodeAccepted(yesterday, now: today), isFalse);
      expect(superAdminCodeAccepted('2026-10-10', now: today), isFalse);
      expect(superAdminCodeAccepted('', now: today), isFalse);
      expect(superAdminCodeAccepted(r'$2a$10$short', now: today), isFalse);
    });

    test('rejects a cost that would freeze the till', () {
      final hash = BCrypt.hashpw('2026-10-10', BCrypt.gensalt(logRounds: 4));
      final costly = r'$2a$15$' + hash.substring(7);
      expect(superAdminCodeAccepted(costly, now: today), isFalse);
    });
  });

  group('shared storage migration', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('c212-share-'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Directory dir(String name) =>
        Directory(p.join(tmp.path, name))..createSync(recursive: true);
    void write(Directory d, String name, String body) =>
        File(p.join(d.path, name)).writeAsStringSync(body);
    String read(Directory d, String name) =>
        File(p.join(d.path, name)).readAsStringSync();

    test('the first account brings its settings and database across', () {
      final oldSupport = dir('old/support');
      final oldDocs = dir('old/docs');
      write(oldSupport, 'shared_preferences.json', '{"a":1}');
      write(dir('old/support/sub'), 'x.txt', 'x');
      write(oldDocs, 'sqd.db', 'DB');
      write(oldDocs, 'sqd.db-wal', 'WAL');
      write(oldDocs, 'unrelated.pdf', 'no');

      final newSupport = Directory(p.join(tmp.path, 'shared/support'));
      final newData = Directory(p.join(tmp.path, 'shared/data'));
      final copied = SharedStorage.migrateInto(
          oldSupport: oldSupport,
          oldDocs: oldDocs,
          newSupport: newSupport,
          newData: newData);

      expect(copied, ['settings', 'database']);
      expect(read(newSupport, 'shared_preferences.json'), '{"a":1}');
      expect(read(Directory(p.join(newSupport.path, 'sub')), 'x.txt'), 'x');
      expect(read(newData, 'sqd.db'), 'DB');
      expect(read(newData, 'sqd.db-wal'), 'WAL');
      expect(File(p.join(newData.path, 'unrelated.pdf')).existsSync(), isFalse);
      // Originals stay for a rollback to an older build.
      expect(read(oldDocs, 'sqd.db'), 'DB');
    });

    test('a later account joins the till instead of overwriting it', () {
      final newSupport = dir('shared/support');
      final newData = dir('shared/data');
      write(newSupport, 'shared_preferences.json', '{"till":"A"}');
      write(newData, 'sqd.db', 'TILL-A');
      final oldSupport = dir('b/support');
      final oldDocs = dir('b/docs');
      write(oldSupport, 'shared_preferences.json', '{"till":"B"}');
      write(oldDocs, 'sqd.db', 'TILL-B');

      final copied = SharedStorage.migrateInto(
          oldSupport: oldSupport,
          oldDocs: oldDocs,
          newSupport: newSupport,
          newData: newData);

      expect(copied, isEmpty);
      expect(read(newSupport, 'shared_preferences.json'), '{"till":"A"}');
      expect(read(newData, 'sqd.db'), 'TILL-A');
    });

    test('a fresh machine just gets empty shared folders', () {
      final newSupport = Directory(p.join(tmp.path, 's'));
      final newData = Directory(p.join(tmp.path, 'd'));
      expect(
          SharedStorage.migrateInto(
              oldSupport: null,
              oldDocs: Directory(p.join(tmp.path, 'missing')),
              newSupport: newSupport,
              newData: newData),
          isEmpty);
      expect(newSupport.existsSync() && newData.existsSync(), isTrue);
    });
  });

  group('restrictions', () {
    test('survive the record file round trip', () {
      final r = OsRestrictions.lockedDown(['chrome.exe']);
      final back = OsRestrictions.fromJson(r.toJson());
      expect(back.toJson(), r.toJson());
      expect(back.count, 8);
    });

    test('the POS is always allowed, without duplicates', () {
      const r = OsRestrictions(
          onlyAllowedApps: true, allowedApps: ['Caisse212.exe', 'chrome.exe']);
      expect(r.effectiveAllowedApps(['caisse212.exe']),
          ['caisse212.exe', 'chrome.exe']);
    });

    test('windows payload: allowed apps only when the list is on', () {
      Map<String, dynamic> payload(OsRestrictions r) => windowsChangePayload(
            action: 'update',
            name: 'caisse',
            admin: false,
            restrictions: r,
            posApps: ['caisse212.exe'],
            record: {},
            recordPath: 'x',
            invoker: 'Owner',
          );
      expect(payload(const OsRestrictions(onlyAllowedApps: true))
          ['restrictions']['allowedApps'], ['caisse212.exe']);
      expect(payload(const OsRestrictions(allowedApps: ['chrome.exe']))
          ['restrictions']['allowedApps'], isEmpty);
    });

    test('windows payload: time zone is locked while any account asks', () {
      Map<String, dynamic> payload(Map<String, dynamic> record) =>
          windowsChangePayload(
            action: 'update',
            name: 'caisse',
            admin: false,
            restrictions: OsRestrictions.none,
            posApps: const [],
            record: record,
            recordPath: 'x',
            invoker: 'Owner',
          );
      expect(payload({})['anyTimeBlock'], isFalse);
      expect(
          payload({
            'other': const OsRestrictions(time: true).toJson(),
          })['anyTimeBlock'],
          isTrue);
    });

    test('linux denies only what was ticked', () {
      expect(linuxDeniedActions(OsRestrictions.none), isEmpty);
      final denied = linuxDeniedActions(const OsRestrictions(time: true));
      expect(denied, ['org.freedesktop.timedate1.']);
      expect(linuxDeniedActions(const OsRestrictions(install: true)),
          contains('org.freedesktop.packagekit.'));
    });
  });

  test('linux accounts: humans only, admins from sudo', () {
    const passwd = 'root:x:0:0:root:/root:/bin/bash\n'
        'daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin\n'
        'owner:x:1000:1000:Shop Owner,,,:/home/owner:/bin/bash\n'
        'caisse:x:1001:1001:Caisse 1:/home/caisse:/bin/bash\n'
        'old:x:1002:1002::/home/old:/usr/sbin/nologin\n'
        'nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin\n';
    const group = 'sudo:x:27:owner\nlpadmin:x:120:owner\n';
    final accounts =
        parseLinuxAccounts(passwd, group, currentUser: 'owner');
    expect(accounts.map((a) => a.name), ['caisse', 'old', 'owner']);
    final owner = accounts.firstWhere((a) => a.name == 'owner');
    expect(owner.isAdmin && owner.isCurrent, isTrue);
    expect(owner.label, 'Shop Owner');
    expect(accounts.firstWhere((a) => a.name == 'old').enabled, isFalse);
    expect(accounts.firstWhere((a) => a.name == 'caisse').isAdmin, isFalse);
  });

  test('windows: lists the real accounts, current one included', () async {
    final accounts = await WindowsOsAccounts().listAccounts();
    final me = Platform.environment['USERNAME']!.toLowerCase();
    expect(accounts.where((a) => a.isCurrent).map((a) => a.name.toLowerCase()),
        [me]);
    expect(accounts.any((a) => a.isAdmin), isTrue);
  }, skip: !Platform.isWindows);

  group('remote support config', () {
    test('empty means the built-in server', () {
      expect(const RemoteSupportConfig().isDefault, isTrue);
      expect(const RemoteSupportConfig(host: '  ').isDefault, isTrue);
      expect(const RemoteSupportConfig(key: 'k').isDefault, isFalse);
    });

    test('round-trips through server.json, trimmed', () {
      const c = RemoteSupportConfig(host: ' support.example.com ', key: 'K=');
      final back = RemoteSupportConfig.fromJson(c.toJson());
      expect(back.host, 'support.example.com');
      expect(back.key, 'K=');
      expect(back.api, '');
    });

    test('server.json lives beside the tool, in the install folder', () {
      expect(RemoteSupportService.configFile.parent.path,
          RemoteSupportService.folder.path);
      expect(p.basename(RemoteSupportService.configFile.path), 'server.json');
    });
  });
}

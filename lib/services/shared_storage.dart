// The shared_preferences store keeps its path provider in a field meant for
// tests; swapping it is the only way to move the settings file.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider_linux/path_provider_linux.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_linux/shared_preferences_linux.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';

/// One till, whichever OS account opens it.
///
/// path_provider resolves the database (Documents) and the settings file
/// (AppData / ~/.local/share) per OS account, so a cashier's restricted
/// Windows account used to open an empty POS: no tenant, no catalogue, its own
/// Z counter. [install] points both at a machine-wide folder instead —
/// `C:\ProgramData\caisse212` or `/var/lib/caisse212` — before anything reads
/// them, so every account shares one database and one set of settings.
class SharedStorage {
  static const folderName = 'caisse212';
  static const linuxRoot = '/var/lib/caisse212';

  /// Where the shared folder lives on this OS, or null when not supported.
  static String? get root {
    if (Platform.isWindows) {
      final programData = Platform.environment['ProgramData'];
      return p.join(
          (programData == null || programData.isEmpty)
              ? r'C:\ProgramData'
              : programData,
          folderName);
    }
    if (Platform.isLinux) return linuxRoot;
    return null;
  }

  /// The shared folder in use this run, or null when this run stayed per-user.
  static String? active;

  /// Redirects path_provider and shared_preferences to the shared folder,
  /// copying this account's data across the first time. Must run before the
  /// first SharedPreferences / database access.
  ///
  /// Never throws: a till that cannot reach the shared folder still opens on
  /// its per-user data, as it always did, and returns why.
  static Future<String> install() async {
    final r = root;
    if (r == null) return 'shared storage: not supported on this OS';
    try {
      final dir = Directory(r);
      if (!dir.existsSync()) {
        // /var/lib needs root: super admin mode creates it on Linux.
        if (!Platform.isWindows) return 'shared storage: $r missing';
        dir.createSync(recursive: true);
        // ProgramData only lets other accounts read what one account wrote.
        // Whoever creates the folder owns it and may widen it; the installer
        // does the same when it runs first.
        await Process.run('icacls', [r, '/grant', '*S-1-5-32-545:(OI)(CI)M']);
      }
      if (!_writable(dir)) return 'shared storage: $r not writable';
      // A run as administrator (the updater relaunches the till elevated)
      // leaves files only admins may change: the cashier's account then
      // loses every setting it saves, silently, at the next restart. Re-grant
      // on every start; it only succeeds when this run has the right to, and
      // a till must never wait on it.
      if (Platform.isWindows) {
        unawaited(Process.run(
                'icacls', [r, '/grant', '*S-1-5-32-545:(OI)(CI)M', '/T', '/C', '/Q'])
            .catchError((_) => ProcessResult(0, 1, '', '')));
      }

      final support = p.join(r, 'support');
      final data = p.join(r, 'data');
      final String? oldSupport;
      final String? oldDocs;
      if (Platform.isWindows) {
        final win = PathProviderWindows();
        oldSupport = await win.getApplicationSupportPath();
        oldDocs = await win.getApplicationDocumentsPath();
      } else {
        final lin = PathProviderLinux();
        oldSupport = await lin.getApplicationSupportPath();
        oldDocs = await lin.getApplicationDocumentsPath();
      }
      final copied = migrateInto(
        oldSupport: oldSupport == null ? null : Directory(oldSupport),
        oldDocs: oldDocs == null ? null : Directory(oldDocs),
        newSupport: Directory(support),
        newData: Directory(data),
      );

      if (Platform.isWindows) {
        final provider = _SharedPathProviderWindows(support, data);
        PathProviderPlatform.instance = provider;
        final store = SharedPreferencesStorePlatform.instance;
        if (store is SharedPreferencesWindows) store.pathProvider = provider;
      } else {
        final provider = _SharedPathProviderLinux(support, data);
        PathProviderPlatform.instance = provider;
        final store = SharedPreferencesStorePlatform.instance;
        if (store is SharedPreferencesLinux) store.pathProvider = provider;
      }
      active = r;
      return 'shared storage: $r'
          '${copied.isEmpty ? '' : ' (copied ${copied.join(', ')})'}';
    } catch (e) {
      return 'shared storage: failed, staying per-user: $e';
    }
  }

  /// The database files path_provider's Documents folder holds for this app.
  static const dbFiles = ['sqd.db', 'sqd.db-wal', 'sqd.db-shm'];

  /// Seeds the shared folders from this account's per-user ones.
  ///
  /// Only into an empty target: the first account to launch the new build
  /// brings its till across, and later accounts join it rather than
  /// overwrite it. The per-user originals are left in place, so going back
  /// to an older build finds them untouched. Returns what was copied.
  static List<String> migrateInto({
    required Directory? oldSupport,
    required Directory? oldDocs,
    required Directory newSupport,
    required Directory newData,
  }) {
    final copied = <String>[];
    newSupport.createSync(recursive: true);
    newData.createSync(recursive: true);

    final hasPrefs =
        File(p.join(newSupport.path, 'shared_preferences.json')).existsSync();
    if (!hasPrefs && oldSupport != null && oldSupport.existsSync() &&
        !p.equals(oldSupport.path, newSupport.path)) {
      _copyTree(oldSupport, newSupport);
      copied.add('settings');
    }

    final hasDb = File(p.join(newData.path, dbFiles.first)).existsSync();
    if (!hasDb && oldDocs != null &&
        File(p.join(oldDocs.path, dbFiles.first)).existsSync()) {
      for (final name in dbFiles) {
        final f = File(p.join(oldDocs.path, name));
        if (f.existsSync()) f.copySync(p.join(newData.path, name));
      }
      copied.add('database');
    }
    return copied;
  }

  static void _copyTree(Directory from, Directory to) {
    for (final e in from.listSync(followLinks: false)) {
      final target = p.join(to.path, p.basename(e.path));
      if (e is File) {
        e.copySync(target);
      } else if (e is Directory) {
        final d = Directory(target)..createSync(recursive: true);
        _copyTree(e, d);
      }
    }
  }

  static bool _writable(Directory dir) {
    try {
      final probe = File(p.join(dir.path, '.write-probe-$pid'));
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }
}

class _SharedPathProviderWindows extends PathProviderWindows {
  final String support;
  final String data;
  _SharedPathProviderWindows(this.support, this.data);

  @override
  Future<String?> getApplicationSupportPath() async => support;

  @override
  Future<String?> getApplicationDocumentsPath() async => data;
}

class _SharedPathProviderLinux extends PathProviderLinux {
  final String support;
  final String data;
  _SharedPathProviderLinux(this.support, this.data);

  @override
  Future<String?> getApplicationSupportPath() async => support;

  @override
  Future<String?> getApplicationDocumentsPath() async => data;
}

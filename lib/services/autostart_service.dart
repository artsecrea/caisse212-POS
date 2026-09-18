import 'dart:io';

import 'package:flutter/foundation.dart';

/// Registers the POS to launch when the machine starts.
///
/// Hand-rolled per platform rather than pulled from a package: the three
/// mechanisms are a registry value, a text file and a plist, and each is a few
/// lines. Everything the OS actually sees is built by the pure functions at the
/// bottom of this file, which is what `test/autostart_test.dart` exercises —
/// the IO around them is deliberately thin.
///
/// Every entry point is best-effort. A till that cannot write its own autostart
/// entry must still open, so nothing here is allowed to throw at the caller.
class AutostartService {
  /// Registry value name (Windows) and file stem (Linux). Stable: changing it
  /// would orphan the entry already registered on every installed till.
  static const String entryName = 'caisse212';

  /// Reverse-DNS label for the macOS LaunchAgent.
  static const String macLabel = 'com.caisse212.pos';

  static const String _runKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  /// Whether this build can register itself at all. Mobile has no equivalent
  /// the app is allowed to set for itself, so the setting is hidden there.
  static bool get isSupported =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// The executable the OS should launch. On macOS this points inside the
  /// bundle, which is what a LaunchAgent wants.
  static String get _executable => Platform.resolvedExecutable;

  /// Turn autostart on or off. Returns whether the OS now reflects [enabled].
  static Future<bool> setEnabled(bool enabled) async {
    if (!isSupported) return false;
    try {
      if (Platform.isWindows) return await _setWindows(enabled);
      if (Platform.isLinux) {
        return _setFile(_linuxEntryFile(), enabled,
            () => buildDesktopEntry(_executable));
      }
      if (Platform.isMacOS) {
        return _setFile(_macEntryFile(), enabled,
            () => buildLaunchAgent(macLabel, _executable));
      }
      return false;
    } catch (e) {
      debugPrint('Autostart setEnabled($enabled) failed: $e');
      return false;
    }
  }

  /// Whether the OS currently has an entry for this app.
  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      if (Platform.isWindows) {
        final r = await Process.run(
            'reg', ['query', _runKey, '/v', entryName]);
        return r.exitCode == 0;
      }
      if (Platform.isLinux) return _linuxEntryFile().existsSync();
      if (Platform.isMacOS) return _macEntryFile().existsSync();
      return false;
    } catch (e) {
      debugPrint('Autostart isEnabled failed: $e');
      return false;
    }
  }

  /// Make the OS agree with [enabled], rewriting a stale entry.
  ///
  /// Called on boot because the registered path is absolute: a till that was
  /// updated into a new directory, or moved, still holds an entry pointing at
  /// an executable that is no longer there. Re-registering every launch is
  /// cheap and is the only thing that repairs that.
  static Future<void> reconcile(bool enabled) async {
    if (!isSupported) return;
    try {
      if (enabled) {
        await setEnabled(true);
      } else if (await isEnabled()) {
        await setEnabled(false);
      }
    } catch (e) {
      debugPrint('Autostart reconcile failed: $e');
    }
  }

  // ── platform IO ────────────────────────────────────────────────────────────

  static Future<bool> _setWindows(bool enabled) async {
    final args = enabled
        ? ['add', _runKey, '/v', entryName, '/t', 'REG_SZ', '/d',
            quoteWindowsPath(_executable), '/f']
        : ['delete', _runKey, '/v', entryName, '/f'];
    final r = await Process.run('reg', args);
    // Deleting an entry that was never there reports failure, which is the
    // state the caller asked for, so it is not one.
    if (!enabled && r.exitCode != 0) return true;
    return r.exitCode == 0;
  }

  static bool _setFile(File file, bool enabled, String Function() contents) {
    if (enabled) {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(contents());
    } else if (file.existsSync()) {
      file.deleteSync();
    }
    return true;
  }

  static String get _home =>
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '.';

  static File _linuxEntryFile() =>
      File('$_home/.config/autostart/$entryName.desktop');

  static File _macEntryFile() =>
      File('$_home/Library/LaunchAgents/$macLabel.plist');

  // ── what the OS is handed ──────────────────────────────────────────────────

  /// Wrap the path in quotes so a directory with a space in it (`Program
  /// Files`, or this project's own `caisse212 apps`) is launched as one
  /// argument rather than two.
  static String quoteWindowsPath(String path) => '"$path"';

  /// A freedesktop.org autostart entry.
  ///
  /// `Exec` is quoted for the same reason as Windows. `X-GNOME-Autostart-enabled`
  /// is what stops GNOME's own Startup Applications list from showing the entry
  /// as disabled after a user has toggled it there once.
  static String buildDesktopEntry(String executable) => '''
[Desktop Entry]
Type=Application
Name=caisse212
Comment=Point of sale
Exec="$executable"
Terminal=false
X-GNOME-Autostart-enabled=true
''';

  /// A per-user LaunchAgent. `RunAtLoad` is the whole point of it; `KeepAlive`
  /// is deliberately absent, because a cashier who quits the till should not
  /// have it reopen on them.
  static String buildLaunchAgent(String label, String executable) => '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$executable</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
''';
}

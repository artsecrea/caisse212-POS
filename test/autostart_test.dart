import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/services/autostart_service.dart';

/// What the OS is actually handed when "Open on startup" is switched on.
///
/// The IO around these is a registry call and two file writes; what can
/// silently go wrong is the *content* — an unquoted path with a space in it
/// launching nothing, or an entry name that drifts and orphans what is already
/// registered on installed tills.
void main() {
  // The real install path on this machine has a space in it, which is exactly
  // the case that breaks an unquoted entry.
  const spacey = r'C:\Users\Test\Desktop\caisse212 apps\pos\posecrea.exe';

  group('the Windows Run entry', () {
    test('a path with a space is one argument, not two', () {
      expect(AutostartService.quoteWindowsPath(spacey), '"$spacey"');
    });

    test('the entry name is stable', () {
      // Changing this orphans the entry on every till that already has one:
      // the old value keeps launching the old path and nothing removes it.
      expect(AutostartService.entryName, 'caisse212');
    });
  });

  group('the Linux autostart entry', () {
    final entry = AutostartService.buildDesktopEntry(spacey);

    test('it is a desktop entry an autostart directory will honour', () {
      expect(entry, startsWith('[Desktop Entry]'));
      expect(entry, contains('Type=Application'));
      expect(entry, contains('Terminal=false'));
    });

    test('Exec is quoted', () {
      expect(entry, contains('Exec="$spacey"'));
    });

    test('GNOME is told the entry is enabled', () {
      // Without this, GNOME's Startup Applications list can show a freshly
      // written entry as disabled.
      expect(entry, contains('X-GNOME-Autostart-enabled=true'));
    });
  });

  group('the macOS LaunchAgent', () {
    final plist =
        AutostartService.buildLaunchAgent(AutostartService.macLabel, spacey);

    test('it is a plist with the label and the executable', () {
      expect(plist, startsWith('<?xml version="1.0" encoding="UTF-8"?>'));
      expect(plist, contains('<string>${AutostartService.macLabel}</string>'));
      expect(plist, contains('<string>$spacey</string>'));
    });

    test('RunAtLoad is set', () {
      expect(plist, contains('<key>RunAtLoad</key>'));
      expect(plist, contains('<true/>'));
    });

    test('KeepAlive is absent', () {
      // A cashier who quits the till must not have it reopen on them.
      expect(plist.contains('KeepAlive'), isFalse);
    });

    test('the label is reverse-DNS', () {
      expect(AutostartService.macLabel, matches(r'^[\w-]+(\.[\w-]+)+$'));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/presentation/widgets/settings_lock_dialog.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/services/permission_service.dart';

/// What opens a locked Settings page.
///
/// Two ways in, and both matter: the 4-digit pin the admin set, and the
/// owner's master code for the day a pin is forgotten. The failure modes are
/// asymmetric — a master code that stops working strands the owner out of
/// their own till, and a pin check that is too loose hands the cashier the
/// settings page. Pin both ends.

void main() {
  final march = DateTime(2026, 3, 7);

  group('the master code', () {
    test('is the date as yyyymmdd, zero-padded', () {
      expect(settingsMasterCode(march), '20260307');
      expect(settingsMasterCode(DateTime(2026, 12, 25)), '20261225');
    });

    test('opens Settings whatever pin is configured', () {
      expect(
        settingsCodeAccepted('20260307', pin: '1234', now: march),
        isTrue,
      );
    });

    test('opens Settings even when no pin was ever set', () {
      // The recovery path has to work in the state that most needs it.
      expect(settingsCodeAccepted('20260307', pin: '', now: march), isTrue);
    });

    test('yesterday does not open today', () {
      // The point of tying it to the date: a code a cashier watched being
      // typed is dead by the next shift.
      expect(
        settingsCodeAccepted('20260306', pin: '1234', now: march),
        isFalse,
      );
    });
  });

  group('the configured pin', () {
    test('opens Settings', () {
      expect(settingsCodeAccepted('1234', pin: '1234', now: march), isTrue);
    });

    test('a wrong pin does not', () {
      expect(settingsCodeAccepted('4321', pin: '1234', now: march), isFalse);
    });

    test('surrounding whitespace is forgiven, not the digits', () {
      expect(settingsCodeAccepted('  1234 ', pin: '1234', now: march), isTrue);
      expect(settingsCodeAccepted('12 34', pin: '1234', now: march), isFalse);
    });
  });

  group('nothing else gets in', () {
    test('an empty entry never matches, even against an unset pin', () {
      // The dangerous case: with no pin stored, a bare `code == pin` test
      // would open Settings on an empty field.
      expect(settingsCodeAccepted('', pin: '', now: march), isFalse);
      expect(settingsCodeAccepted('   ', pin: '', now: march), isFalse);
    });

    test('a prefix of the master code does not match', () {
      expect(settingsCodeAccepted('2026', pin: '1234', now: march), isFalse);
    });
  });

  group('who may open printer setup', () {
    CurrentUser user(String type, String permissions) => CurrentUser(
          1,
          'u',
          'x',
          'U',
          '',
          type,
          null,
          null,
          null,
          permissions,
          DateTime(2026),
          DateTime(2026),
          null,
        );

    bool allowed(CurrentUser? u, {List<String> cashierDefaults = const []}) =>
        printerSetupAllowed(
            PermissionService(u, cashierDefaults: cashierDefaults));

    test('a settings holder gets in, as they already could', () {
      expect(allowed(user('cashier', Permissions.settingsView)), isTrue);
    });

    test('an admin gets in', () {
      expect(allowed(user('admin', '')), isTrue);
    });

    test('the dedicated permission gets a technician in without Settings', () {
      expect(allowed(user('cashier', Permissions.printersManage)), isTrue);
    });

    test('devicesView alone no longer opens it — this is the change', () {
      // It is held by anyone who can look at the KDS list, which meant a
      // cashier locked out of Settings could re-point the receipt printer.
      expect(allowed(user('cashier', Permissions.devicesView)), isFalse);
    });

    test('a plain cashier is out', () {
      expect(allowed(user('cashier', '')), isFalse);
    });

    test('nobody logged in is out', () {
      expect(allowed(null), isFalse);
    });

    test('a pos:* wildcard still covers it', () {
      expect(allowed(user('cashier', 'pos:*')), isTrue);
    });

    test('an admin-configured cashier default can grant it', () {
      expect(
        allowed(user('cashier', ''),
            cashierDefaults: [Permissions.printersManage]),
        isTrue,
      );
    });
  });
}

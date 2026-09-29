import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/presentation/widgets/settings_lock_dialog.dart';

/// The settings pin is 4 to 8 digits.
///
/// It was exactly 4, which on a till the whole floor can see is shoulder-surfed
/// in a shift. The ceiling is 8 because the unlock field is shared with the
/// master code (`yyyymmdd`).

void main() {
  group('isValidSettingsPin', () {
    test('accepts the whole 4-to-8 range', () {
      for (final pin in ['1234', '12345', '123456', '1234567', '12345678']) {
        expect(isValidSettingsPin(pin), isTrue, reason: pin);
      }
    });

    test('rejects shorter than four', () {
      for (final pin in ['', '1', '12', '123']) {
        expect(isValidSettingsPin(pin), isFalse, reason: '"$pin"');
      }
    });

    test('rejects longer than eight', () {
      expect(isValidSettingsPin('123456789'), isFalse);
    });

    test('rejects anything that is not a digit', () {
      for (final pin in ['12a4', '12 4', '1.23', '----']) {
        expect(isValidSettingsPin(pin), isFalse, reason: pin);
      }
    });

    test('trims surrounding whitespace before judging', () {
      expect(isValidSettingsPin('  1234  '), isTrue,
          reason: 'the dialog trims before saving, so the rule must agree');
    });

    test('the bounds are the documented ones', () {
      expect(kSettingsPinMinLength, 4);
      expect(kSettingsPinMaxLength, 8);
    });
  });

  group('settingsCodeAccepted still honours any pin length', () {
    final now = DateTime(2026, 9, 23);

    test('a six-digit pin opens settings', () {
      expect(settingsCodeAccepted('135790', pin: '135790', now: now), isTrue);
    });

    test('an eight-digit pin opens settings', () {
      expect(
          settingsCodeAccepted('13579024', pin: '13579024', now: now), isTrue);
    });

    test('the master code still works alongside a long pin', () {
      expect(settingsCodeAccepted('20260923', pin: '13579024', now: now),
          isTrue,
          reason: 'the owner must never be locked out of their own till');
    });

    test('a wrong code of the right length is still refused', () {
      expect(
          settingsCodeAccepted('999999', pin: '135790', now: now), isFalse);
    });

    test('an empty entry is refused even with no pin set', () {
      expect(settingsCodeAccepted('', pin: '', now: now), isFalse);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/providers/settings_provider.dart';

/// Note and delivery-fee presets.
///
/// These are typed into a free-text field by a shop owner, so the parsing has
/// to survive trailing commas, duplicates and blank entries without producing
/// a chip that says nothing or two chips that say the same thing.

Future<SettingsNotifier> notifierWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SettingsNotifier(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('note presets', () {
    test('an untouched till has none of its own', () async {
      // Empty is what makes the dialog fall back to the built-in translated
      // set, so this must not be pre-filled with anything.
      final n = await notifierWith({});
      expect(n.state.notePresets, isEmpty);
    });

    test('order is kept, not sorted', () async {
      // The cashier decides which note they reach for most; a list that
      // reshuffles itself is slower to use, not faster.
      final n = await notifierWith({});
      await n.setNotePresets(['Ring the bell', 'No onions', 'Extra hot']);
      expect(n.state.notePresets, ['Ring the bell', 'No onions', 'Extra hot']);
    });

    test('blanks and duplicates are dropped', () async {
      final n = await notifierWith({});
      await n.setNotePresets(['No onions', '  ', 'No onions', ' Extra hot ']);
      expect(n.state.notePresets, ['No onions', 'Extra hot']);
    });

    test('they survive a restart', () async {
      final n = await notifierWith({});
      await n.setNotePresets(['No onions']);
      final reopened =
          SettingsNotifier(await SharedPreferences.getInstance());
      expect(reopened.state.notePresets, ['No onions']);
    });

    test('clearing them all is allowed', () async {
      // And is how a shop gets the built-in set back.
      final n = await notifierWith({});
      await n.setNotePresets(['No onions']);
      await n.setNotePresets([]);
      expect(n.state.notePresets, isEmpty);
    });
  });

  group('delivery fee presets', () {
    test('an untouched till gets a starting set', () async {
      final n = await notifierWith({});
      expect(n.state.deliveryFeePresets, [10, 15, 20, 30]);
    });

    test('emptying them on purpose is respected, not overridden', () async {
      // "Never set" and "set to nothing" are different answers: the first
      // wants a suggestion, the second wants the chips gone.
      final n = await notifierWith({});
      await n.setDeliveryFeePresets([]);
      expect(n.state.deliveryFeePresets, isEmpty);
      final reopened =
          SettingsNotifier(await SharedPreferences.getInstance());
      expect(reopened.state.deliveryFeePresets, isEmpty);
    });

    test('cheapest first, whatever order they were typed', () async {
      final n = await notifierWith({});
      await n.setDeliveryFeePresets([30, 10, 20]);
      expect(n.state.deliveryFeePresets, [10, 20, 30]);
    });

    test('zero is a real fee and is kept', () async {
      // "Free delivery" is an amount to charge, and distinct from leaving the
      // fee unset — the two mean different things all the way to the server.
      final n = await notifierWith({});
      await n.setDeliveryFeePresets([0, 15]);
      expect(n.state.deliveryFeePresets, [0, 15]);
    });

    test('negatives and duplicates are dropped', () async {
      final n = await notifierWith({});
      await n.setDeliveryFeePresets([15, -5, 15, 10]);
      expect(n.state.deliveryFeePresets, [10, 15]);
    });

    test('decimals survive the round trip', () async {
      final n = await notifierWith({});
      await n.setDeliveryFeePresets([12.5]);
      final reopened =
          SettingsNotifier(await SharedPreferences.getInstance());
      expect(reopened.state.deliveryFeePresets, [12.5]);
    });
  });
}

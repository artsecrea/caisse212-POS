import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/settings_provider.dart';
import 'package:caisse212/utils/app_localizations.dart';

/// The shop's own header and footer.
///
/// These went missing off printed tickets. The read used to go through a
/// provider ref that the printing service — a singleton outliving the scope
/// that built it — had cached, and every failure to read it was caught and
/// swallowed, so the line simply vanished with nothing said. It now falls back
/// to the same SharedPreferences key the setting is written to.

Future<ProviderContainer> containerWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('reading the custom text', () {
    test('comes back from what the setting holds', () async {
      final container = await containerWith({
        'ticket_header': 'Cafe Central',
        'ticket_footer': 'Merci de votre visite',
      });
      addTearDown(container.dispose);
      final service = container.read(printingServiceProvider);

      expect(service.debugCustomTicketText(SettingsKeys.ticketHeader),
          'Cafe Central');
      expect(service.debugCustomTicketText(SettingsKeys.ticketFooter),
          'Merci de votre visite');
    });

    test('an unset header is empty, not the key name or a null', () async {
      final container = await containerWith({});
      addTearDown(container.dispose);
      final service = container.read(printingServiceProvider);

      expect(service.debugCustomTicketText(SettingsKeys.ticketHeader), '');
      expect(service.debugCustomTicketText(SettingsKeys.ticketFooter), '');
    });

    test('survives the provider scope it was built in being disposed',
        () async {
      // The exact shape of the bug: the service is a singleton, the container
      // that handed it a ref goes away, and the next ticket still has to carry
      // the shop's name.
      final container = await containerWith({'ticket_header': 'Cafe Central'});
      final service = container.read(printingServiceProvider);
      container.dispose();

      expect(service.debugCustomTicketText(SettingsKeys.ticketHeader),
          'Cafe Central');
    });
  });

  group('the drawer button says something in every language', () {
    test('all of its strings are translated', () {
      const keys = [
        'open_drawer_now',
        'open_drawer_now_subtitle',
        'open_drawer_now_action',
        'drawer_opened',
        'drawer_open_failed',
      ];
      for (final code in const ['en', 'ar', 'fr']) {
        final l10n = AppLocalizations(Locale(code));
        for (final key in keys) {
          // translate() returns the key itself when it is missing, which on
          // screen reads as a debug string next to a button a cashier presses.
          expect(l10n.translate(key), isNot(key), reason: '$key missing in $code');
        }
      }
    });
  });
}

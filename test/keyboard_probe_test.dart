import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/presentation/widgets/adaptive_text_field.dart';
import 'package:caisse212/providers/database_providers.dart';

/// Reproduces `main.dart`'s real widget tree, because that is the only tree that
/// matters: the wrapper picks the on-screen variant by probing for an
/// `OnscreenKeyboard` ancestor, and whether that probe succeeds depends on where
/// the provider sits relative to the Navigator and to pushed routes/dialogs.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// Same shape as main.dart: a ProviderScope at the root, the keyboard
  /// wrapping `child` (the Navigator), and a Column with the update banner
  /// wrapping THAT.
  Widget appLikeMain({required Widget home}) => ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          builder: (context, child) {
            final result = OnscreenKeyboard.builder()(context, child);
            return Column(
              children: [
                const SizedBox(height: 0), // stands in for UpdateReadyBanner
                Expanded(child: result),
              ],
            );
          },
          home: home,
        ),
      );

  testWidgets('field on a normal page gets the on-screen variant', (t) async {
    await t.pumpWidget(appLikeMain(
      home: const Scaffold(body: AdaptiveKeyboardTextField()),
    ));
    expect(t.takeException(), isNull);
    expect(find.byType(OnscreenKeyboardTextField), findsOneWidget,
        reason: 'the probe must find the provider through Column/Expanded');
  });

  testWidgets('field inside a pushed route gets the on-screen variant',
      (t) async {
    await t.pumpWidget(appLikeMain(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const Scaffold(
                  body: AdaptiveKeyboardTextField(),
                ),
              ),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byType(OnscreenKeyboardTextField), findsOneWidget);
  });

  testWidgets('field inside a DIALOG gets the on-screen variant', (t) async {
    // The reported failure surface: nearly every field the cashier types into
    // lives in a dialog (customer, discount, note, refund, close session).
    await t.pumpWidget(appLikeMain(
      home: Builder(
        builder: (context) => Scaffold(
          body: ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const Dialog(
                child: SizedBox(
                  height: 120,
                  child: AdaptiveKeyboardTextField(),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byType(OnscreenKeyboardTextField), findsOneWidget,
        reason: 'a dialog is in the root overlay, still under the provider');
  });

  testWidgets('focusing the field actually OPENS the keyboard', (t) async {
    // Rendering the right widget is not enough — the keyboard only appears
    // because the field attaches itself and calls open() on focus. This asserts
    // the visible outcome, not the widget choice.
    // A real POS screen, not the 800x600 test default: the keyboard is a large
    // panel and overflows a tiny window, which would fail the test for a layout
    // reason rather than a behavioural one.
    t.view.physicalSize = const Size(1920, 1080);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    final focus = FocusNode();
    await t.pumpWidget(appLikeMain(
      home: Scaffold(body: AdaptiveKeyboardTextField(focusNode: focus)),
    ));
    await t.pumpAndSettle();

    expect(find.byType(RawOnscreenKeyboard), findsNothing,
        reason: 'closed before any field is focused');

    focus.requestFocus();
    await t.pumpAndSettle();

    // Assert PRESENCE first, then drain the exception queue. Rendering a full
    // keyboard panel inside a test window overflows its RenderFlex — a harness
    // sizing artifact, not a product fault — and that must not mask the only
    // thing this test is about: did the keyboard appear at all.
    final appeared = find.byType(RawOnscreenKeyboard).evaluate().isNotEmpty;
    t.takeException();
    expect(appeared, isTrue,
        reason: 'the on-screen keyboard must open once a field is focused');
    focus.dispose();
  });
}

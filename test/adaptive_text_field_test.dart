import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_onscreen_keyboard/flutter_onscreen_keyboard.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/presentation/widgets/adaptive_text_field.dart';
import 'package:caisse212/presentation/widgets/keypad_field.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/settings_provider.dart';

/// Guards the crash behind "the customer dialog breaks the app".
///
/// `OnscreenKeyboardTextField` resolves the keyboard in `initState` via
/// `OnscreenKeyboard.of(context)`, which ends in `provider!.state`. With no
/// `OnscreenKeyboard` ancestor that throws *while the widget is being
/// inserted*, so the whole subtree — in practice the dialog — fails to build.
/// `main.dart` leaves that ancestor out whenever the on-screen keyboard setting
/// is off, or whenever its builder threw and the catch fell back to the bare
/// child. These tests pin both halves: the raw widget really does blow up, and
/// the wrapper really does survive.
void main() {
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  /// The field reads the keypad-beta setting, so it needs a scope — the app
  /// has one at its root, and tests have to say so too.
  Widget scoped(Widget child) => ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: child,
      );

  Widget bare(Widget child) => scoped(MaterialApp(home: Scaffold(body: child)));

  Widget withKeyboard(Widget child) => scoped(MaterialApp(
        builder: OnscreenKeyboard.builder(),
        home: Scaffold(body: child),
      ));

  group('the numeric keypad beta', () {
    Future<void> pumpField(WidgetTester t, TextInputType? type) async {
      await t.pumpWidget(bare(AdaptiveKeyboardTextField(
        controller: TextEditingController(),
        keyboardType: type,
      )));
      await t.pumpAndSettle();
    }

    testWidgets('is off by default, so nothing changes for anyone',
        (t) async {
      await pumpField(t, TextInputType.number);
      expect(find.byType(KeypadField), findsNothing);
    });

    testWidgets('takes over number fields once switched on', (t) async {
      await prefs.setBool(SettingsKeys.numericKeypadBeta, true);
      await pumpField(t, TextInputType.number);
      expect(find.byType(KeypadField), findsOneWidget);
    });

    testWidgets('leaves text fields alone even when on', (t) async {
      // The point of a narrow beta: a switch that only reaches the fields the
      // pad can actually serve.
      await prefs.setBool(SettingsKeys.numericKeypadBeta, true);
      await pumpField(t, TextInputType.text);
      expect(find.byType(KeypadField), findsNothing);
    });

    testWidgets('leaves a field with no declared type alone', (t) async {
      await prefs.setBool(SettingsKeys.numericKeypadBeta, true);
      await pumpField(t, null);
      expect(find.byType(KeypadField), findsNothing);
    });

    testWidgets('carries the decimal and sign options across', (t) async {
      await prefs.setBool(SettingsKeys.numericKeypadBeta, true);
      await pumpField(
          t, const TextInputType.numberWithOptions(decimal: true, signed: true));

      final pad = t.widget<KeypadField>(find.byType(KeypadField));
      expect(pad.allowDecimal, isTrue);
      expect(pad.allowNegative, isTrue);
    });

    testWidgets('leaves a disabled field alone', (t) async {
      await prefs.setBool(SettingsKeys.numericKeypadBeta, true);
      await t.pumpWidget(bare(AdaptiveKeyboardTextField(
        controller: TextEditingController(),
        keyboardType: TextInputType.number,
        enabled: false,
      )));
      await t.pumpAndSettle();
      expect(find.byType(KeypadField), findsNothing);
    });
  });

  group('without an OnscreenKeyboard ancestor', () {
    testWidgets('the raw package field throws — this is the bug', (t) async {
      await t.pumpWidget(bare(const OnscreenKeyboardTextField()));
      expect(t.takeException(), isNotNull,
          reason: 'if this ever stops throwing, the wrapper can be retired');
    });

    testWidgets('the wrapper renders a plain TextField instead', (t) async {
      await t.pumpWidget(bare(const AdaptiveKeyboardTextField()));
      expect(t.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(OnscreenKeyboardTextField), findsNothing);
    });

    testWidgets('typing still works in the fallback', (t) async {
      final c = TextEditingController();
      await t.pumpWidget(bare(AdaptiveKeyboardTextField(controller: c)));
      await t.enterText(find.byType(TextField), 'Ali');
      expect(c.text, 'Ali');
    });

    testWidgets('decoration and initial text survive the fallback', (t) async {
      // The add-customer form pre-fills from the queue payload, so losing the
      // controller's text here would silently blank the cashier's data.
      final c = TextEditingController(text: 'Sara');
      await t.pumpWidget(bare(AdaptiveKeyboardTextField(
        controller: c,
        decoration: const InputDecoration(labelText: 'First name'),
      )));
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text('First name'), findsOneWidget);
    });
  });

  group('with an OnscreenKeyboard ancestor', () {
    testWidgets('the wrapper uses the on-screen variant', (t) async {
      await t.pumpWidget(withKeyboard(const AdaptiveKeyboardTextField()));
      expect(t.takeException(), isNull);
      expect(find.byType(OnscreenKeyboardTextField), findsOneWidget);
    });
  });

  testWidgets('a dialog full of fields opens with no keyboard mounted',
      (t) async {
    // The reported symptom, reproduced at the shape that matters: the external
    // order confirm opens a dialog whose body is nothing but these fields.
    await t.pumpWidget(bare(Builder(builder: (context) {
      return ElevatedButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const Dialog(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AdaptiveKeyboardTextField(),
                AdaptiveKeyboardTextField(),
                AdaptiveKeyboardTextField(),
              ],
            ),
          ),
        ),
        child: const Text('open'),
      );
    })));

    await t.tap(find.text('open'));
    await t.pumpAndSettle();

    expect(t.takeException(), isNull);
    expect(find.byType(TextField), findsNWidgets(3));
  });
}

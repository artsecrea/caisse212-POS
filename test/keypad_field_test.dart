import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:caisse212/presentation/widgets/keypad_field.dart';

/// The keypad's job is to edit text without a keyboard, which sounds trivial
/// and is not: a caret in the middle of a value, a length cap, a decimal point
/// that must not appear twice. Getting any of them wrong on a till shows up as
/// a wrong PIN or a wrong price.

Future<void> _pump(
  WidgetTester tester,
  TextEditingController controller, {
  bool allowDecimal = false,
  bool allowNegative = false,
  int? maxLength,
  ValueChanged<String>? onSubmitted,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 300,
          child: KeypadField(
            controller: controller,
            allowDecimal: allowDecimal,
            allowNegative: allowNegative,
            maxLength: maxLength,
            onSubmitted: onSubmitted,
          ),
        ),
      ),
    ),
  ));
}

Future<void> _openPad(WidgetTester tester) async {
  await tester.tap(find.byType(TextField));
  await tester.pumpAndSettle();
}

/// Keys are ink-splashing [InkWell]s, and backspace is an icon rather than a
/// glyph — scoping to the key widget also keeps the pad's value readout, which
/// shows the same digits, from matching.
Finder _key(String key) => key == '⌫'
    ? find.byIcon(Icons.backspace_outlined)
    : find.widgetWithText(InkWell, key);

Future<void> _press(WidgetTester tester, String key) async {
  await tester.tap(_key(key));
  await tester.pump();
}

void main() {
  testWidgets('the pad opens on focus and closes on the barrier',
      (tester) async {
    final controller = TextEditingController();
    await _pump(tester, controller);

    expect(_key('7'), findsNothing);

    await _openPad(tester);
    expect(_key('7'), findsOneWidget);

    // A tap anywhere else puts it away.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(_key('7'), findsNothing);
  });

  testWidgets('focus opens the pad', (tester) async {
    // Focus, not tap, is the signal: `onTap` does not fire on every platform
    // for a read-only field, and when it did not the pad never opened and the
    // field was simply dead.
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: KeypadField(
              controller: TextEditingController(),
              focusNode: focusNode,
            ),
          ),
        ),
      ),
    ));

    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(_key('7'), findsOneWidget);

    focusNode.unfocus();
    await tester.pumpAndSettle();
    expect(_key('7'), findsNothing);
  });

  testWidgets('coming back to the app does not pop the pad open',
      (tester) async {
    // Windows hands focus back to the last-focused widget when its window is
    // re-activated. Without this guard, alt-tabbing to the till opened the
    // keypad over the screen with nobody having touched it.
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: KeypadField(
              controller: TextEditingController(),
              focusNode: focusNode,
            ),
          ),
        ),
      ),
    ));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    focusNode.requestFocus();
    await tester.pumpAndSettle();
    expect(_key('7'), findsNothing, reason: 'the window restored focus');

    // A real tap still opens it, immediately.
    await _openPad(tester);
    expect(_key('7'), findsOneWidget);
  });

  testWidgets('a window with no size does not open a pad', (tester) async {
    // A minimised Windows window reports a physical size of nothing. Every gap
    // measured from that came out negative, so the pad was placed against a
    // space that did not exist and came back broken on restore.
    final controller = TextEditingController();
    await _pump(tester, controller);

    tester.view.physicalSize = Size.zero;
    addTearDown(tester.view.reset);
    await tester.pump();

    // Focusing while there is nothing to place against must simply do nothing.
    await tester.tap(find.byType(TextField), warnIfMissed: false);
    await tester.pump();
    expect(_key('7'), findsNothing);

    // Restored, it opens normally again.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpAndSettle();
    await _openPad(tester);
    expect(_key('7'), findsOneWidget);
  });

  testWidgets('digits append in order', (tester) async {
    final controller = TextEditingController();
    await _pump(tester, controller);
    await _openPad(tester);

    for (final key in ['1', '9', '8', '4']) {
      await _press(tester, key);
    }
    expect(controller.text, '1984');
  });

  testWidgets('the pad survives being typed on', (tester) async {
    // The bug this pins: `TextField.onTapOutside` unfocuses the field when you
    // tap anywhere outside *the field*, and the pad is outside the field. So
    // the first key press closed the pad and you could enter exactly one
    // digit.
    final controller = TextEditingController();
    await _pump(tester, controller);
    await _openPad(tester);

    await _press(tester, '1');
    expect(_key('7'), findsOneWidget, reason: 'still open after one key');

    await _press(tester, '2');
    await _press(tester, '3');
    await _press(tester, '4');

    expect(controller.text, '1234');
    expect(_key('7'), findsOneWidget, reason: 'still open after four');
  });

  testWidgets('keys never steal focus from the field', (tester) async {
    // The field's focus is what holds the pad open, so a focusable key would
    // close the pad by being pressed.
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 300,
            child: KeypadField(
              controller: TextEditingController(),
              focusNode: focusNode,
            ),
          ),
        ),
      ),
    ));
    await _openPad(tester);
    expect(focusNode.hasFocus, isTrue);

    await _press(tester, '5');
    expect(focusNode.hasFocus, isTrue, reason: 'the key did not take focus');
  });

  testWidgets('backspace removes the last digit, and stops at empty',
      (tester) async {
    final controller = TextEditingController(text: '12');
    await _pump(tester, controller);
    await _openPad(tester);

    await _press(tester, '⌫');
    expect(controller.text, '1');
    await _press(tester, '⌫');
    expect(controller.text, '');
    // Pressing on past empty must not throw or produce a negative caret.
    await _press(tester, '⌫');
    expect(controller.text, '');
  });

  testWidgets('clear empties the field', (tester) async {
    final controller = TextEditingController(text: '4321');
    await _pump(tester, controller);
    await _openPad(tester);

    await _press(tester, 'C');
    expect(controller.text, '');
  });

  testWidgets('typing respects the caret rather than always appending',
      (tester) async {
    final controller = TextEditingController(text: '13');
    await _pump(tester, controller);
    await _openPad(tester);

    // Caret between the 1 and the 3.
    controller.selection = const TextSelection.collapsed(offset: 1);
    await _press(tester, '2');

    expect(controller.text, '123');
    expect(controller.selection.baseOffset, 2);
  });

  testWidgets('a selection is replaced, not appended to', (tester) async {
    final controller = TextEditingController(text: '999');
    await _pump(tester, controller);
    await _openPad(tester);

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 3);
    await _press(tester, '5');

    expect(controller.text, '5');
  });

  testWidgets('a value typed before the field was ever focused appends',
      (tester) async {
    // A controller seeded in code reports an invalid selection; the pad has to
    // treat that as "the end", not offset zero, or a PIN types in backwards.
    final controller = TextEditingController(text: '12');
    await _pump(tester, controller);
    await _openPad(tester);

    await _press(tester, '3');
    expect(controller.text, '123');
  });

  testWidgets('maxLength caps the value', (tester) async {
    final controller = TextEditingController();
    await _pump(tester, controller, maxLength: 4);
    await _openPad(tester);

    for (final key in ['1', '2', '3', '4', '5', '6']) {
      await _press(tester, key);
    }
    expect(controller.text, '1234');
  });

  group('decimal key', () {
    testWidgets('is absent unless asked for', (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller);
      await _openPad(tester);

      expect(_key('.'), findsNothing);
      // Its slot carries clear instead, so the pad is never a key short.
      expect(_key('C'), findsOneWidget);
    });

    testWidgets('appears and only ever produces one point', (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller, allowDecimal: true);
      await _openPad(tester);

      await _press(tester, '1');
      await _press(tester, '.');
      await _press(tester, '5');
      await _press(tester, '.');
      await _press(tester, '0');

      expect(controller.text, '1.50');
    });
  });

  testWidgets('the sign key toggles rather than stacking minuses',
      (tester) async {
    final controller = TextEditingController(text: '20');
    await _pump(tester, controller, allowNegative: true);
    await _openPad(tester);

    await _press(tester, '-');
    expect(controller.text, '-20');
    await _press(tester, '-');
    expect(controller.text, '20');
  });

  testWidgets('done submits the value and closes the pad', (tester) async {
    String? submitted;
    final controller = TextEditingController();
    await _pump(tester, controller, onSubmitted: (v) => submitted = v);
    await _openPad(tester);

    await _press(tester, '7');
    // `FilledButton.icon` builds a private subclass, so byType would miss
    // it — the label is the reliable handle.
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(submitted, '7');
    expect(_key('7'), findsNothing);
  });

  group('the readout', () {
    testWidgets('shows the value as it is typed', (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller);
      await _openPad(tester);

      await _press(tester, '4');
      await _press(tester, '2');

      // Twice on screen now: the field and the pad's own readout. That is the
      // point — the eye never has to travel back to the field.
      expect(find.text('42'), findsNWidgets(2));
    });

    testWidgets('masks an obscured value rather than exposing it',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: KeypadField(controller: controller, obscureText: true),
            ),
          ),
        ),
      ));
      await _openPad(tester);

      await _press(tester, '9');
      await _press(tester, '9');

      // The pad shows dots, not digits.
      expect(find.text('••'), findsOneWidget);
      // `EditableText` reports its raw value to finders even while rendering
      // it obscured, so the one match here is the field itself — what matters
      // is that the pad did not add a second, unmasked copy beside it.
      expect(find.text('99'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isTrue,
      );
    });
  });

  testWidgets('the pad stays on screen when no side has room for it',
      (tester) async {
    // The default 800x600 surface is smaller than the pad plus a field, so
    // every side falls short and the fallback has to shift it back inside.
    final controller = TextEditingController();
    await _pump(tester, controller);
    await _openPad(tester);

    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    final pad = tester.getRect(find.byKey(const Key('keypad-panel')));

    expect(pad.left, greaterThanOrEqualTo(0));
    expect(pad.top, greaterThanOrEqualTo(0));
    expect(pad.right, lessThanOrEqualTo(screen.width));
    expect(pad.bottom, lessThanOrEqualTo(screen.height));
  });

  group('placement', () {
    /// A surface with room to the right of the field, so the pad lands where
    /// it prefers to and nothing gets clamped.
    Future<Rect> pumpRoomy(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 300,
              child: KeypadField(controller: TextEditingController()),
            ),
          ),
        ),
      ));
      await _openPad(tester);
      return tester.getRect(find.byType(TextField));
    }

    testWidgets('the pad opens beside the field, centred on it',
        (tester) async {
      final field = await pumpRoomy(tester);
      final pad = tester.getRect(find.byKey(const Key('keypad-panel')));

      expect(pad.left, greaterThanOrEqualTo(field.right),
          reason: 'sits to the side, not over the field');
      // Centred on the field rather than hanging off its top corner.
      expect((pad.center.dy - field.center.dy).abs(), lessThan(1.0));
    });

    testWidgets('the pointer sits on the edge facing the field',
        (tester) async {
      final field = await pumpRoomy(tester);
      final pointer = tester.getRect(find.byKey(const Key('keypad-pointer')));
      final pad = tester.getRect(find.byKey(const Key('keypad-panel')));

      // Between the field and the panel, aimed along the field's centre line.
      expect(pointer.left, greaterThanOrEqualTo(field.right - 1));
      expect(pointer.right, lessThanOrEqualTo(pad.left + 2));
      expect((pointer.center.dy - field.center.dy).abs(), lessThan(1.0));
    });

    testWidgets('the pointer keeps aiming at the field after a clamp',
        (tester) async {
      // A field near the top: centring would hang half the pad off screen, so
      // it gets pushed down — and the arrow has to slide back up the pad's
      // edge to keep pointing at the field.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(top: 100),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: KeypadField(controller: TextEditingController()),
              ),
            ),
          ),
        ),
      ));
      await _openPad(tester);

      final field = tester.getRect(find.byType(TextField));
      final pad = tester.getRect(find.byKey(const Key('keypad-panel')));
      final pointer = tester.getRect(find.byKey(const Key('keypad-pointer')));

      expect(pad.top, greaterThanOrEqualTo(0), reason: 'pushed back on screen');
      // The pad is no longer centred on the field, but the arrow still is.
      expect((pad.center.dy - field.center.dy).abs(), greaterThan(1.0));
      expect((pointer.center.dy - field.center.dy).abs(), lessThan(1.0));
    });

    testWidgets('the pointer stays on the panel when the field is out of reach',
        (tester) async {
      // Hard against the top edge, the field ends up further from the pad's
      // centre than half the panel — the arrow cannot reach it without sliding
      // off the edge, so it stops at the corner rather than detaching.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 300,
              child: KeypadField(controller: TextEditingController()),
            ),
          ),
        ),
      ));
      await _openPad(tester);

      final pad = tester.getRect(find.byKey(const Key('keypad-panel')));
      final pointer = tester.getRect(find.byKey(const Key('keypad-pointer')));

      expect(pointer.top, greaterThanOrEqualTo(pad.top - 1));
      expect(pointer.bottom, lessThanOrEqualTo(pad.bottom + 1));
      // Still hard over toward the field rather than sitting at the middle.
      // Stated as a fraction of the panel so it survives a resize.
      expect(pointer.center.dy, lessThan(pad.top + pad.height / 3));
    });
  });

  testWidgets('the platform keyboard is suppressed but the caret shows',
      (tester) async {
    final controller = TextEditingController();
    await _pump(tester, controller);

    final field = tester.widget<TextField>(find.byType(TextField));
    // Both halves matter: readOnly stops a tablet raising its own keyboard over
    // this one, showCursor keeps the field looking editable.
    expect(field.readOnly, isTrue);
    expect(field.showCursor, isTrue);
  });

  testWidgets('disposing while the pad is open does not leave it behind',
      (tester) async {
    final controller = TextEditingController();
    await _pump(tester, controller);
    await _openPad(tester);
    expect(_key('7'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pumpAndSettle();

    expect(_key('7'), findsNothing);
  });
}

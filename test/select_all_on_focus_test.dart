import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/presentation/widgets/adaptive_text_field.dart';
import 'package:caisse212/providers/database_providers.dart';

/// Focusing a price or quantity box selects what is in it, so the next
/// keypress REPLACES the figure instead of appending to it.
///
/// Without this a cashier tapping "12.00" to make it 8 lands a caret wherever
/// their finger was and gets "128.00" or "12.008" — a wrong price that looks
/// deliberate. Selecting on focus is what makes retyping the natural action.

void main() {
  Future<TextEditingController> pump(
    WidgetTester tester, {
    required String initial,
    required bool selectAll,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = TextEditingController(text: initial);

    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: AdaptiveKeyboardTextField(
            controller: controller,
            selectAllOnFocus: selectAll,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('focusing selects the whole value', (tester) async {
    final controller = await pump(tester, initial: '12.00', selectAll: true);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, '12.00'.length,
        reason: 'the next keypress has to replace all of it');
  });

  testWidgets('so typing replaces rather than appends', (tester) async {
    final controller = await pump(tester, initial: '12.00', selectAll: true);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '8');
    await tester.pumpAndSettle();

    expect(controller.text, '8',
        reason: 'not 128.00, and not 12.008');
  });

  testWidgets('an empty field is left alone', (tester) async {
    final controller = await pump(tester, initial: '', selectAll: true);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(controller.text, isEmpty);
    expect(controller.selection.extentOffset, lessThanOrEqualTo(0),
        reason: 'selecting nothing must not produce an invalid range');
  });

  testWidgets('without the flag the old behaviour is untouched',
      (tester) async {
    final controller = await pump(tester, initial: '12.00', selectAll: false);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset == 0 &&
            controller.selection.extentOffset == '12.00'.length,
        isFalse,
        reason: 'every other field in the app keeps its caret behaviour');
  });

  testWidgets('re-focusing selects again, not just the first time',
      (tester) async {
    final controller = await pump(tester, initial: '12.00', selectAll: true);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '250');
    await tester.pumpAndSettle();

    // Away and back, the way a cashier moves between price and quantity.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();

    expect(controller.selection.baseOffset, 0);
    expect(controller.selection.extentOffset, '250'.length);
  });
}

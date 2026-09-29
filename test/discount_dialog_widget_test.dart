import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/presentation/widgets/manual_discount_dialog.dart';
import 'package:caisse212/providers/database_providers.dart';

/// Does the Amount mode actually appear on screen, and does using it hand back
/// the right percentage?
///
/// The conversion maths is unit-tested elsewhere; this pumps the real dialog,
/// because "the function is correct" and "the cashier can reach it" are
/// different claims and only the second one is what was asked for.

void main() {
  Future<void> open(
    WidgetTester tester, {
    double orderTotal = 500,
    double currentPercentage = 0,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: ManualDiscountDialog(
            orderTotal: orderTotal,
            currentPercentage: currentPercentage,
            currencySymbol: 'MAD',
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the Amount toggle is on screen', (tester) async {
    await open(tester);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Percentage'), findsOneWidget);
  });

  testWidgets('it opens on Percentage, as before', (tester) async {
    await open(tester);
    expect(find.text('Discount Percentage'), findsOneWidget);
    expect(find.text('Discount Amount'), findsNothing);
  });

  testWidgets('tapping Amount swaps the field', (tester) async {
    await open(tester);
    await tester.tap(find.text('Amount'));
    await tester.pumpAndSettle();

    expect(find.text('Discount Amount'), findsOneWidget);
    expect(find.text('Discount Percentage'), findsNothing);
  });

  testWidgets('typing an amount shows the percentage it works out to',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Amount'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '50');
    await tester.pumpAndSettle();

    // 50 off 500 is 10%, and the strip says so both ways round.
    expect(find.textContaining('10.0%'), findsOneWidget);
    expect(find.textContaining('450.00'), findsOneWidget);
  });

  testWidgets('applying an amount returns the converted percentage',
      (tester) async {
    Map<String, dynamic>? result;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => const ManualDiscountDialog(
                    orderTotal: 500,
                    currencySymbol: 'MAD',
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Amount'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '125');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!['percentage'], 25.0,
        reason: '125 off 500 — the order stores a percentage, so that is what '
            'has to come back');
  });

  testWidgets('more than the order total is refused, not silently capped',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Amount'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '600');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.textContaining('More than the order total'), findsOneWidget);
  });

  testWidgets('the title bar and the warning box are gone', (tester) async {
    await open(tester);

    // Both were height spent on things the cashier already knows: the dialog
    // is plainly a discount dialog, and the note about applying to every
    // product was never a warning anyone acted on.
    expect(find.text('Manual Discount'), findsNothing);
    expect(find.textContaining('applied to every ticket product'), findsNothing);
    expect(find.byIcon(Icons.close), findsNothing,
        reason: 'Cancel already leaves the dialog');
  });

  testWidgets('everything that does work is still reachable', (tester) async {
    await open(tester, currentPercentage: 10);

    expect(find.text('Percentage'), findsOneWidget);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('Apply'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget, reason: 'quick-select chips stay');
  });

  testWidgets('the actions sit above the fold, tappable without scrolling',
      (tester) async {
    await open(tester, currentPercentage: 10);

    // The whole reason they moved: on a 400px dialog the keypad and the chips
    // used to push Apply off the bottom, so the cashier had to scroll a
    // dialog that did not look scrollable.
    final applyBox = tester.getRect(find.text('Apply'));
    final screen = tester.getRect(find.byType(MaterialApp));
    expect(applyBox.bottom, lessThan(screen.bottom));
    expect(applyBox.top, lessThan(screen.height / 2),
        reason: 'they are at the TOP, not merely on screen');
  });

  testWidgets('an empty cart hides Amount rather than dividing by zero',
      (tester) async {
    await open(tester, orderTotal: 0);
    expect(find.text('Amount'), findsNothing);
    expect(find.text('Discount Percentage'), findsOneWidget,
        reason: 'percentage entry still works with no total');
  });
}

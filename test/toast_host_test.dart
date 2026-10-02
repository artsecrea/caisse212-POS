import 'package:caisse212/utils/snackbar_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app() => MaterialApp(
      builder: (context, child) =>
          Stack(children: [child!, const ToastHost()]),
      home: const Scaffold(body: SizedBox.expand()),
    );

void main() {
  tearDown(SnackBarHelper.dismissAllToasts);

  testWidgets('a toast shows top-right and closes with its button',
      (tester) async {
    await tester.pumpWidget(_app());
    SnackBarHelper.showToast('Saved', kind: ToastKind.success);
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.text('Saved'));
    final screen = tester.getSize(find.byType(MaterialApp));
    expect(rect.center.dx, greaterThan(screen.width / 2));
    expect(rect.center.dy, lessThan(screen.height / 2));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('expires after its duration', (tester) async {
    await tester.pumpWidget(_app());
    SnackBarHelper.showToast('Bye', duration: const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bye'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('Bye'), findsNothing);
  });

  testWidgets('keeps at most four, dropping the oldest', (tester) async {
    await tester.pumpWidget(_app());
    for (var i = 0; i < 6; i++) {
      SnackBarHelper.showToast('t$i', duration: const Duration(minutes: 1));
    }
    await tester.pumpAndSettle();
    expect(find.text('t0'), findsNothing);
    expect(find.text('t1'), findsNothing);
    expect(find.text('t5'), findsOneWidget);
    SnackBarHelper.dismissAllToasts();
    await tester.pump(const Duration(minutes: 2));
  });
}

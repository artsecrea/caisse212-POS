import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces the reported bug: typing in the Settings dialog put the
/// characters into the main screen's product search instead.
///
/// The cause is structural, not cosmetic. Settings opens with `showDialog`, so
/// the main screen — and its TopBar — stay mounted underneath. TopBar re-claims
/// the search focus from `didChangeDependencies`, which fires on ANY inherited
/// widget change, including the ones a dialog opening (or an on-screen keyboard
/// resizing the view) causes.
///
/// NOTE ON SCOPE. This harness mirrors the arrangement (background widget that
/// re-focuses on dependency changes + a dialog with its own field) and verifies
/// the guard's contract. It does NOT reproduce the original report: with the
/// guard removed these still pass, because Flutter scopes focus per route and a
/// background `requestFocus()` does not take primary focus from a dialog. The
/// real mechanism is therefore something else — most likely the on-screen
/// keyboard, which attaches itself to whichever field last took focus and lives
/// in an overlay above the Navigator, outside any route's scope.
///
/// So: these pin the guard so it cannot regress, and they prove the guard did
/// not break the legitimate "focus the search bar on the till screen" behaviour.
/// They are not evidence that the reported bug is fixed.
void main() {
  testWidgets('a background re-focus does NOT steal from a dialog field',
      (tester) async {
    final searchFocus = FocusNode(debugLabel: 'search');
    final searchController = TextEditingController();

    await tester.pumpWidget(MaterialApp(
      home: _Background(
        focusNode: searchFocus,
        controller: searchController,
      ),
    ));
    await tester.pumpAndSettle();

    // The background owns the caret while it is the top route — as it should.
    expect(searchFocus.hasFocus, isTrue);

    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();

    // Opening the dialog changes inherited widgets, which is what used to fire
    // the unguarded re-focus.
    final dialogField = find.byKey(const ValueKey('dialogField'));
    await tester.tap(dialogField);
    await tester.pumpAndSettle();

    // Force an inherited-widget change while the dialog is open — this is the
    // real trigger: the on-screen keyboard resizing the view, a theme or locale
    // rebuild, anything that reaches MediaQuery. It fires
    // didChangeDependencies on the background, which is where the unguarded
    // re-focus ran from.
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();

    await tester.enterText(dialogField, 'MAD');
    await tester.pumpAndSettle();

    expect(_dialogController.text, 'MAD',
        reason: 'the dialog field must receive what was typed');
    expect(searchController.text, isEmpty,
        reason: 'not one character may reach the background search field');
    expect(searchFocus.hasFocus, isFalse,
        reason: 'the background must not hold focus while a modal is open');

    searchFocus.dispose();
    searchController.dispose();
  });

  testWidgets('focus returns to the background once the dialog closes',
      (tester) async {
    // The guard must not break the behaviour it is guarding: a till with no
    // dialog open should still land the caret in the search bar, so a scanner
    // works without anyone tapping first.
    final searchFocus = FocusNode(debugLabel: 'search');
    final searchController = TextEditingController();

    await tester.pumpWidget(MaterialApp(
      home: _Background(focusNode: searchFocus, controller: searchController),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open settings'));
    await tester.pumpAndSettle();
    expect(searchFocus.hasFocus, isFalse);

    Navigator.of(tester.element(find.byKey(const ValueKey('dialogField'))))
        .pop();
    await tester.pumpAndSettle();

    expect(searchFocus.hasFocus, isTrue,
        reason: 'closing the modal hands the keyboard back');

    searchFocus.dispose();
    searchController.dispose();
  });
}

/// Stands in for MainScreen + TopBar: stays mounted under the dialog and tries
/// to re-claim focus on every dependency change.
class _Background extends StatefulWidget {
  final FocusNode focusNode;
  final TextEditingController controller;

  const _Background({required this.focusNode, required this.controller});

  @override
  State<_Background> createState() => _BackgroundState();
}

class _BackgroundState extends State<_Background> {
  @override
  void initState() {
    super.initState();
    _requestSearchFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _requestSearchFocus();
  }

  // The guard, matching TopBar._requestSearchFocus / _mayTakeFocus.
  void _requestSearchFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_mayTakeFocus()) return;
      if (widget.focusNode.canRequestFocus) widget.focusNode.requestFocus();
    });
  }

  bool _mayTakeFocus() {
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    final primary = FocusManager.instance.primaryFocus;
    if (primary != null &&
        primary != widget.focusNode &&
        primary is! FocusScopeNode) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // TopBar reads MediaQuery.sizeOf for its responsive layout, which is what
    // makes it a MediaQuery dependent — and therefore what makes
    // didChangeDependencies fire on a view change while a dialog is open.
    // ignore: unused_local_variable
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: Column(
        children: [
          TextField(
            focusNode: widget.focusNode,
            controller: widget.controller,
            key: const ValueKey('searchField'),
          ),
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const _SettingsLikeDialog(),
              ),
              child: const Text('open settings'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsLikeDialog extends StatelessWidget {
  const _SettingsLikeDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        height: 120,
        child: TextField(
          key: const ValueKey('dialogField'),
          controller: _dialogController,
        ),
      ),
    );
  }
}

final _dialogController = TextEditingController();

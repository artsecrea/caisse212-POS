import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:caisse212/domain/models/app_settings.dart';
import 'package:caisse212/providers/database_providers.dart';
import 'package:caisse212/providers/settings_provider.dart';

/// When the category bar above the grid is shown, and when the back tile is.
///
/// The two answers deliberately differ. The bar goes away for the whole mode;
/// the tile only appears once there is somewhere to go back to. Conflating
/// them left a button reading "All Categories" sitting above a page of
/// categories.

Future<ProviderContainer> containerWith({
  required bool backTile,
  required CategoryDisplayMode mode,
}) async {
  SharedPreferences.setMockInitialValues({
    'show_back_tile_in_product_grid': backTile,
    'category_display_mode': mode.name,
  });
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the mode really is on for these settings', () async {
    final c = await containerWith(
        backTile: true, mode: CategoryDisplayMode.fullPage);
    addTearDown(c.dispose);
    expect(c.read(settingsProvider).showBackTileInProductGrid, isTrue,
        reason: 'the prefs key must match what the notifier reads');
  });

  group('the bar', () {
    test('is hidden at the category page, not only inside a category',
        () async {
      final c = await containerWith(
          backTile: true, mode: CategoryDisplayMode.fullPage);
      addTearDown(c.dispose);
      // Nothing selected: this is the category page itself.
      expect(c.read(selectedCategoryProvider), isNull);
      expect(c.read(categoryBarHiddenProvider), isTrue);
    });

    test('stays hidden once a category is opened', () async {
      final c = await containerWith(
          backTile: true, mode: CategoryDisplayMode.fullPage);
      addTearDown(c.dispose);
      c.read(selectedCategoryProvider.notifier).state = 4;
      expect(c.read(categoryBarHiddenProvider), isTrue);
    });

    test('is untouched when the back tile is off', () async {
      final c = await containerWith(
          backTile: false, mode: CategoryDisplayMode.fullPage);
      addTearDown(c.dispose);
      expect(c.read(categoryBarHiddenProvider), isFalse);
    });

    test('is untouched in top-bar mode, where the bar IS the picker', () async {
      final c =
          await containerWith(backTile: true, mode: CategoryDisplayMode.topBar);
      addTearDown(c.dispose);
      expect(c.read(categoryBarHiddenProvider), isFalse);
    });
  });

  group('the back tile', () {
    test('does not appear on the category page', () async {
      // There is nothing to go back to from the top level.
      final c = await containerWith(
          backTile: true, mode: CategoryDisplayMode.fullPage);
      addTearDown(c.dispose);
      expect(c.read(productGridBackTileProvider), isFalse);
    });

    test('appears once a category is open', () async {
      final c = await containerWith(
          backTile: true, mode: CategoryDisplayMode.fullPage);
      addTearDown(c.dispose);
      c.read(selectedCategoryProvider.notifier).state = 4;
      expect(c.read(productGridBackTileProvider), isTrue);
    });

    test('never appears in top-bar mode', () async {
      final c =
          await containerWith(backTile: true, mode: CategoryDisplayMode.topBar);
      addTearDown(c.dispose);
      c.read(selectedCategoryProvider.notifier).state = 4;
      expect(c.read(productGridBackTileProvider), isFalse);
    });
  });
}

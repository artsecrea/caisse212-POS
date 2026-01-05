import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/app_settings.dart';
import 'database_providers.dart' show sharedPreferencesProvider;

// Keys for SharedPreferences
class SettingsKeys {
  static const String isDarkMode = 'is_dark_mode';
  static const String defaultOrderType = 'default_order_type';
  static const String showProductImages = 'show_product_images';
  static const String defaultOrderStatus = 'default_order_status';
  static const String categoryDisplayMode = 'category_display_mode';
}

// Settings Notifier
class SettingsNotifier extends StateNotifier<AppSettings> {
  final SharedPreferences _prefs;

  SettingsNotifier(this._prefs) : super(const AppSettings()) {
    _loadSettings();
  }

  void _loadSettings() {
    final categoryModeStr = _prefs.getString(SettingsKeys.categoryDisplayMode);
    final categoryMode = CategoryDisplayMode.values.firstWhere(
      (e) => e.name == categoryModeStr,
      orElse: () => CategoryDisplayMode.topBar,
    );

    state = AppSettings(
      isDarkMode: _prefs.getBool(SettingsKeys.isDarkMode) ?? false,
      defaultOrderType: _prefs.getString(SettingsKeys.defaultOrderType) ?? 'DINE_IN',
      showProductImages: _prefs.getBool(SettingsKeys.showProductImages) ?? true,
      defaultOrderStatus: _prefs.getString(SettingsKeys.defaultOrderStatus) ?? 'PENDING',
      categoryDisplayMode: categoryMode,
    );
  }

  Future<void> setDarkMode(bool value) async {
    await _prefs.setBool(SettingsKeys.isDarkMode, value);
    state = state.copyWith(isDarkMode: value);
  }

  Future<void> toggleDarkMode() async {
    await setDarkMode(!state.isDarkMode);
  }

  Future<void> setDefaultOrderType(String type) async {
    await _prefs.setString(SettingsKeys.defaultOrderType, type);
    state = state.copyWith(defaultOrderType: type);
  }

  Future<void> setShowProductImages(bool value) async {
    await _prefs.setBool(SettingsKeys.showProductImages, value);
    state = state.copyWith(showProductImages: value);
  }

  Future<void> toggleShowProductImages() async {
    await setShowProductImages(!state.showProductImages);
  }

  Future<void> setDefaultOrderStatus(String status) async {
    await _prefs.setString(SettingsKeys.defaultOrderStatus, status);
    state = state.copyWith(defaultOrderStatus: status);
  }

  Future<void> setCategoryDisplayMode(CategoryDisplayMode mode) async {
    await _prefs.setString(SettingsKeys.categoryDisplayMode, mode.name);
    state = state.copyWith(categoryDisplayMode: mode);
  }

  Future<void> resetToDefaults() async {
    await _prefs.remove(SettingsKeys.isDarkMode);
    await _prefs.remove(SettingsKeys.defaultOrderType);
    await _prefs.remove(SettingsKeys.showProductImages);
    await _prefs.remove(SettingsKeys.defaultOrderStatus);
    await _prefs.remove(SettingsKeys.categoryDisplayMode);
    state = const AppSettings();
  }
}

// Settings provider
final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(prefs);
});

// Convenience providers for specific settings
final isDarkModeProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).isDarkMode;
});

final defaultOrderTypeProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).defaultOrderType;
});

final showProductImagesProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).showProductImages;
});

final defaultOrderStatusProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).defaultOrderStatus;
});

final categoryDisplayModeProvider = Provider<CategoryDisplayMode>((ref) {
  return ref.watch(settingsProvider).categoryDisplayMode;
});


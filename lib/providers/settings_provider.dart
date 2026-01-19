import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/app_settings.dart';
import 'database_providers.dart' show sharedPreferencesProvider;

// Keys for SharedPreferences
class SettingsKeys {
  static const String isDarkMode = 'is_dark_mode';
  static const String language = 'language';
  static const String defaultOrderType = 'default_order_type';
  static const String showProductImages = 'show_product_images';
  static const String defaultOrderStatus = 'default_order_status';
  static const String categoryDisplayMode = 'category_display_mode';
  static const String currency = 'currency';
  static const String showTableButton = 'show_table_button';
  static const String showCustomerButton = 'show_customer_button';
  static const String showCommercialButton = 'show_commercial_button';
  static const String showCouponButton = 'show_coupon_button';
  static const String showDiscountButton = 'show_discount_button';
  static const String showPrintButton = 'show_print_button';
  static const String autoSyncOnline = 'auto_sync_online';
  static const String bulkSyncSize = 'bulk_sync_size';
  static const String dataRetentionDays = 'data_retention_days';
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
      language: _prefs.getString(SettingsKeys.language) ?? 'en',
      defaultOrderType: _prefs.getString(SettingsKeys.defaultOrderType) ?? 'DINE_IN',
      showProductImages: _prefs.getBool(SettingsKeys.showProductImages) ?? true,
      defaultOrderStatus: _prefs.getString(SettingsKeys.defaultOrderStatus) ?? 'PENDING',
      categoryDisplayMode: categoryMode,
      currency: _prefs.getString(SettingsKeys.currency) ?? '\$',
      showTableButton: _prefs.getBool(SettingsKeys.showTableButton) ?? true,
      showCustomerButton: _prefs.getBool(SettingsKeys.showCustomerButton) ?? true,
      showCommercialButton: _prefs.getBool(SettingsKeys.showCommercialButton) ?? true,
      showCouponButton: _prefs.getBool(SettingsKeys.showCouponButton) ?? true,
      showDiscountButton: _prefs.getBool(SettingsKeys.showDiscountButton) ?? true,
      showPrintButton: _prefs.getBool(SettingsKeys.showPrintButton) ?? true,
      autoSyncOnline: _prefs.getBool(SettingsKeys.autoSyncOnline) ?? true,
      bulkSyncSize: _prefs.getInt(SettingsKeys.bulkSyncSize) ?? 50,
      dataRetentionDays: _prefs.getInt(SettingsKeys.dataRetentionDays) ?? 7,
    );
  }

  Future<void> setDarkMode(bool value) async {
    await _prefs.setBool(SettingsKeys.isDarkMode, value);
    state = state.copyWith(isDarkMode: value);
  }

  Future<void> toggleDarkMode() async {
    await setDarkMode(!state.isDarkMode);
  }

  Future<void> setLanguage(String languageCode) async {
    await _prefs.setString(SettingsKeys.language, languageCode);
    state = state.copyWith(language: languageCode);
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

  Future<void> setCurrency(String currency) async {
    await _prefs.setString(SettingsKeys.currency, currency);
    state = state.copyWith(currency: currency);
  }

  Future<void> setShowTableButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showTableButton, value);
    state = state.copyWith(showTableButton: value);
  }

  Future<void> setShowCustomerButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showCustomerButton, value);
    state = state.copyWith(showCustomerButton: value);
  }

  Future<void> setShowCommercialButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showCommercialButton, value);
    state = state.copyWith(showCommercialButton: value);
  }

  Future<void> setShowCouponButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showCouponButton, value);
    state = state.copyWith(showCouponButton: value);
  }

  Future<void> setShowDiscountButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showDiscountButton, value);
    state = state.copyWith(showDiscountButton: value);
  }

  Future<void> setShowPrintButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showPrintButton, value);
    state = state.copyWith(showPrintButton: value);
  }

  Future<void> setAutoSyncOnline(bool value) async {
    await _prefs.setBool(SettingsKeys.autoSyncOnline, value);
    state = state.copyWith(autoSyncOnline: value);
  }

  Future<void> setBulkSyncSize(int value) async {
    await _prefs.setInt(SettingsKeys.bulkSyncSize, value);
    state = state.copyWith(bulkSyncSize: value);
  }

  Future<void> setDataRetentionDays(int value) async {
    await _prefs.setInt(SettingsKeys.dataRetentionDays, value);
    state = state.copyWith(dataRetentionDays: value);
  }

  Future<void> resetToDefaults() async {
    await _prefs.remove(SettingsKeys.isDarkMode);
    await _prefs.remove(SettingsKeys.language);
    await _prefs.remove(SettingsKeys.defaultOrderType);
    await _prefs.remove(SettingsKeys.showProductImages);
    await _prefs.remove(SettingsKeys.defaultOrderStatus);
    await _prefs.remove(SettingsKeys.categoryDisplayMode);
    await _prefs.remove(SettingsKeys.currency);
    await _prefs.remove(SettingsKeys.showTableButton);
    await _prefs.remove(SettingsKeys.showCustomerButton);
    await _prefs.remove(SettingsKeys.showCommercialButton);
    await _prefs.remove(SettingsKeys.showCouponButton);
    await _prefs.remove(SettingsKeys.showDiscountButton);
    await _prefs.remove(SettingsKeys.showPrintButton);
    await _prefs.remove(SettingsKeys.autoSyncOnline);
    await _prefs.remove(SettingsKeys.bulkSyncSize);
    await _prefs.remove(SettingsKeys.dataRetentionDays);
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


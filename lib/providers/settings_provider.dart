import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/app_settings.dart';
import 'database_providers.dart' show sharedPreferencesProvider;

// Keys for SharedPreferences
class SettingsKeys {
  static const String isDarkMode = 'is_dark_mode';
  static const String language = 'language';
  static const String loggingLanguage = 'logging_language';
  static const String cashierDefaultPermissions = 'cashier_default_permissions';
  static const String autoSyncOnline = 'auto_sync_online';
  static const String bulkSyncSize = 'bulk_sync_size';
  static const String dataRetentionDays = 'data_retention_days';
  static const String autoSyncDurationMinutes = 'auto_sync_duration_minutes';
  static const String defaultOrderType = 'default_order_type';
  static const String showProductImages = 'show_product_images';
  static const String defaultOrderStatus = 'default_order_status';
  static const String waiterOrderDefaultStatus = 'waiter_order_default_status';
  static const String waiterOrderDefaultPaid = 'waiter_order_default_paid';
  static const String printWaiterOrderTicket = 'print_waiter_order_ticket';
  static const String paidOrderDefaultStatus = 'paid_order_default_status';
  static const String categoryDisplayMode = 'category_display_mode';
  static const String currency = 'currency';
  static const String showTableButton = 'show_table_button';
  static const String showCustomerButton = 'show_customer_button';
  static const String showCommercialButton = 'show_commercial_button';
  static const String showWaiterButton = 'show_waiter_button';
  static const String showCouponButton = 'show_coupon_button';
  static const String showDiscountButton = 'show_discount_button';
  static const String showPrintButton = 'show_print_button';
  static const String showPersonsButton = 'show_persons_button';
  static const String showOrderTypeButton = 'show_order_type_button';
  static const String showConfirmOrderButton = 'show_confirm_order_button';
  static const String showPayButton = 'show_pay_button';
  static const String showDailySummaryButton = 'show_daily_summary_button';
  static const String buttonOrder = 'button_order';
  static const String autoClearSyncedData = 'auto_clear_synced_data';
  static const String lastDataClearDate = 'last_data_clear_date';
  static const String syncUnpaidOrders = 'sync_unpaid_orders';

  static const String orderPanelOnRight = 'order_panel_on_right';

  // On-screen keyboard
  static const String showOnscreenKeyboard = 'show_onscreen_keyboard';
  static const String onscreenKeyboardWidthFraction = 'onscreen_keyboard_width_fraction';

  // Server settings
  static const String serverPort = 'server_port';
  static const String serverPassword = 'server_password';
  static const String autoStartServer = 'auto_start_server';
  static const String waiterDashboardShowOwed = 'waiter_dashboard_show_owed';

  // UI settings
  static const String enableSnackBars = 'enable_snack_bars';
  static const String agendaTimeStep = 'agenda_time_step';

  // Customer Display settings
  static const String enableCustomerDisplay = 'enable_customer_display';

  // Order validation rules (admin-configurable)
  static const String requireTableForDineIn = 'require_table_for_dine_in';
  static const String requireWaiterForDineIn = 'require_waiter_for_dine_in';
  static const String requireCustomerForDelivery =
      'require_customer_for_delivery';
  static const String requireDeliveryAddress = 'require_delivery_address';
  static const String autoClearTableAfterPaying =
      'auto_clear_table_after_paying';

  // Payment settings
  static const String defaultPaymentMethod = 'default_payment_method';
  static const String showTipDialog = 'show_tip_dialog';
  static const String showTipButton = 'show_tip_button';

  // Product card size: 1=small, 2=medium, 3=large
  static const String productCardSize = 'product_card_size';

  // Ticket printing settings
  static const String ticketHeader = 'ticket_header';
  static const String ticketFooter = 'ticket_footer';

  // Favorites & sort
  static const String showFavoritesCategory = 'show_favorites_category';
  static const String sortByLastUsed = 'sort_by_last_used';
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

    // Get buttonOrder and ensure it includes all buttons (migration for new buttons)
    var buttonOrder = _prefs.getStringList(SettingsKeys.buttonOrder) ?? const [
      'persons',
      'orderType',
      'confirmOrder',
      'table',
      'waiter',
      'customer',
      'commercial',
      'coupon',
      'discount',
      'print',
      'dailySummary',
      'tip',
      'pay',
      'proceed',
    ];

    // Migration: Add 'tip' button if missing (for existing installations).
    // Insert it just before 'pay' so the cashier's mental model is
    // "set tip, then take payment" — left-to-right on the toolbar.
    if (!buttonOrder.contains('tip')) {
      final mutableList = List<String>.from(buttonOrder);
      final payIndex = mutableList.indexOf('pay');
      if (payIndex >= 0) {
        mutableList.insert(payIndex, 'tip');
      } else {
        mutableList.add('tip');
      }
      buttonOrder = mutableList;
      _prefs.setStringList(SettingsKeys.buttonOrder, buttonOrder);
    }

    // Migration: Add 'waiter' button if missing (for existing installations)
    if (!buttonOrder.contains('waiter')) {
      final mutableList = List<String>.from(buttonOrder);
      // Insert waiter after 'table' if table exists, otherwise add at index 4
      final tableIndex = mutableList.indexOf('table');
      if (tableIndex >= 0) {
        mutableList.insert(tableIndex + 1, 'waiter');
      } else {
        mutableList.insert(4, 'waiter');
      }
      buttonOrder = mutableList;
      // Save the updated buttonOrder
      _prefs.setStringList(SettingsKeys.buttonOrder, buttonOrder);
    }

    state = AppSettings(
      isDarkMode: _prefs.getBool(SettingsKeys.isDarkMode) ?? false,
      language: _prefs.getString(SettingsKeys.language) ?? 'en',
      loggingLanguage: _prefs.getString(SettingsKeys.loggingLanguage) ??
          _prefs.getString(SettingsKeys.language) ?? 'en',
      cashierDefaultPermissions:
          _prefs.getStringList(SettingsKeys.cashierDefaultPermissions) ??
              const [],
      autoSyncOnline: _prefs.getBool(SettingsKeys.autoSyncOnline) ?? true,
      bulkSyncSize: _prefs.getInt(SettingsKeys.bulkSyncSize) ?? 50,
      dataRetentionDays: _prefs.getInt(SettingsKeys.dataRetentionDays) ?? 7,
      autoSyncDurationMinutes: _prefs.getInt(SettingsKeys.autoSyncDurationMinutes) ?? 5,
      defaultOrderType: _prefs.getString(SettingsKeys.defaultOrderType) ?? 'DINE_IN',
      showProductImages: _prefs.getBool(SettingsKeys.showProductImages) ?? true,
      defaultOrderStatus: _prefs.getString(SettingsKeys.defaultOrderStatus) ?? 'PENDING',
      waiterOrderDefaultStatus:
          _prefs.getString(SettingsKeys.waiterOrderDefaultStatus) ?? 'PENDING',
      waiterOrderDefaultPaid:
          _prefs.getBool(SettingsKeys.waiterOrderDefaultPaid) ?? false,
      printWaiterOrderTicket:
          _prefs.getBool(SettingsKeys.printWaiterOrderTicket) ?? true,
      paidOrderDefaultStatus: _prefs.getString(SettingsKeys.paidOrderDefaultStatus) ?? 'COMPLETED',
      categoryDisplayMode: categoryMode,
      currency: _prefs.getString(SettingsKeys.currency) ?? '\$',
      showTableButton: _prefs.getBool(SettingsKeys.showTableButton) ?? true,
      showCustomerButton: _prefs.getBool(SettingsKeys.showCustomerButton) ?? true,
      showCommercialButton: _prefs.getBool(SettingsKeys.showCommercialButton) ?? true,
      showWaiterButton: _prefs.getBool(SettingsKeys.showWaiterButton) ?? true,
      showCouponButton: _prefs.getBool(SettingsKeys.showCouponButton) ?? true,
      showDiscountButton: _prefs.getBool(SettingsKeys.showDiscountButton) ?? true,
      showPrintButton: _prefs.getBool(SettingsKeys.showPrintButton) ?? true,
      showPersonsButton: _prefs.getBool(SettingsKeys.showPersonsButton) ?? true,
      showOrderTypeButton: _prefs.getBool(SettingsKeys.showOrderTypeButton) ?? true,
      showConfirmOrderButton: _prefs.getBool(SettingsKeys.showConfirmOrderButton) ?? true,
      showPayButton: _prefs.getBool(SettingsKeys.showPayButton) ?? true,
      showDailySummaryButton: _prefs.getBool(SettingsKeys.showDailySummaryButton) ?? true,
      buttonOrder: buttonOrder,
      autoClearSyncedData: _prefs.getBool(SettingsKeys.autoClearSyncedData) ?? true,
      syncUnpaidOrders: _prefs.getBool(SettingsKeys.syncUnpaidOrders) ?? true,
      orderPanelOnRight: _prefs.getBool(SettingsKeys.orderPanelOnRight) ?? false,
      serverPort: _prefs.getInt(SettingsKeys.serverPort) ?? 8080,
      serverPassword: _prefs.getString(SettingsKeys.serverPassword),
      autoStartServer: _prefs.getBool(SettingsKeys.autoStartServer) ?? false,
      waiterDashboardShowOwed:
          _prefs.getBool(SettingsKeys.waiterDashboardShowOwed) ?? true,
      enableSnackBars: _prefs.getBool(SettingsKeys.enableSnackBars) ?? false,
      enableCustomerDisplay: _prefs.getBool(SettingsKeys.enableCustomerDisplay) ?? false,
      requireTableForDineIn:
          _prefs.getBool(SettingsKeys.requireTableForDineIn) ?? false,
      requireWaiterForDineIn:
          _prefs.getBool(SettingsKeys.requireWaiterForDineIn) ?? false,
      requireCustomerForDelivery:
          _prefs.getBool(SettingsKeys.requireCustomerForDelivery) ?? false,
      requireDeliveryAddress:
          _prefs.getBool(SettingsKeys.requireDeliveryAddress) ?? false,
      autoClearTableAfterPaying:
          _prefs.getBool(SettingsKeys.autoClearTableAfterPaying) ?? false,
      defaultPaymentMethod: _prefs.getString(SettingsKeys.defaultPaymentMethod) ?? 'CASH',
      showTipDialog: _prefs.getBool(SettingsKeys.showTipDialog) ?? false,
      showTipButton: _prefs.getBool(SettingsKeys.showTipButton) ?? false,
      agendaTimeStep: _prefs.getInt(SettingsKeys.agendaTimeStep) ?? 60,
      showOnscreenKeyboard: _prefs.getBool(SettingsKeys.showOnscreenKeyboard) ?? true,
      onscreenKeyboardWidthFraction: _prefs.getDouble(SettingsKeys.onscreenKeyboardWidthFraction) ?? 0.5,
      productCardSize: _prefs.getInt(SettingsKeys.productCardSize) ?? 2,
      ticketHeader: _prefs.getString(SettingsKeys.ticketHeader) ?? '',
      ticketFooter: _prefs.getString(SettingsKeys.ticketFooter) ?? '',
      showFavoritesCategory: _prefs.getBool(SettingsKeys.showFavoritesCategory) ?? false,
      sortByLastUsed: _prefs.getBool(SettingsKeys.sortByLastUsed) ?? false,
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

  Future<void> setLoggingLanguage(String languageCode) async {
    await _prefs.setString(SettingsKeys.loggingLanguage, languageCode);
    state = state.copyWith(loggingLanguage: languageCode);
  }

  Future<void> setCashierDefaultPermissions(List<String> tokens) async {
    await _prefs.setStringList(SettingsKeys.cashierDefaultPermissions, tokens);
    state = state.copyWith(cashierDefaultPermissions: tokens);
  }

  Future<void> setOrderPanelOnRight(bool value) async {
    await _prefs.setBool(SettingsKeys.orderPanelOnRight, value);
    state = state.copyWith(orderPanelOnRight: value);
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

  Future<void> setAutoSyncDuration(int minutes) async {
    await _prefs.setInt(SettingsKeys.autoSyncDurationMinutes, minutes);
    state = state.copyWith(autoSyncDurationMinutes: minutes);
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

  Future<void> setWaiterOrderDefaultStatus(String status) async {
    await _prefs.setString(SettingsKeys.waiterOrderDefaultStatus, status);
    state = state.copyWith(waiterOrderDefaultStatus: status);
  }

  Future<void> setWaiterOrderDefaultPaid(bool value) async {
    await _prefs.setBool(SettingsKeys.waiterOrderDefaultPaid, value);
    state = state.copyWith(waiterOrderDefaultPaid: value);
  }

  Future<void> setPrintWaiterOrderTicket(bool value) async {
    await _prefs.setBool(SettingsKeys.printWaiterOrderTicket, value);
    state = state.copyWith(printWaiterOrderTicket: value);
  }

  Future<void> setPaidOrderDefaultStatus(String status) async {
    await _prefs.setString(SettingsKeys.paidOrderDefaultStatus, status);
    state = state.copyWith(paidOrderDefaultStatus: status);
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

  Future<void> setShowWaiterButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showWaiterButton, value);
    state = state.copyWith(showWaiterButton: value);
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

  Future<void> setShowPersonsButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showPersonsButton, value);
    state = state.copyWith(showPersonsButton: value);
  }

  Future<void> setShowOrderTypeButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showOrderTypeButton, value);
    state = state.copyWith(showOrderTypeButton: value);
  }

  Future<void> setShowConfirmOrderButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showConfirmOrderButton, value);
    state = state.copyWith(showConfirmOrderButton: value);
  }

  Future<void> setShowPayButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showPayButton, value);
    state = state.copyWith(showPayButton: value);
  }

  Future<void> setShowDailySummaryButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showDailySummaryButton, value);
    state = state.copyWith(showDailySummaryButton: value);
  }

  Future<void> setButtonOrder(List<String> order) async {
    await _prefs.setStringList(SettingsKeys.buttonOrder, order);
    state = state.copyWith(buttonOrder: order);
  }

  Future<void> setAutoClearSyncedData(bool value) async {
    await _prefs.setBool(SettingsKeys.autoClearSyncedData, value);
    state = state.copyWith(autoClearSyncedData: value);
  }

  Future<void> setSyncUnpaidOrders(bool value) async {
    await _prefs.setBool(SettingsKeys.syncUnpaidOrders, value);
    state = state.copyWith(syncUnpaidOrders: value);
  }

  // Server settings
  Future<void> setServerPort(int port) async {
    await _prefs.setInt(SettingsKeys.serverPort, port);
    state = state.copyWith(serverPort: port);
  }

  Future<void> setServerPassword(String? password) async {
    if (password == null || password.isEmpty) {
      await _prefs.remove(SettingsKeys.serverPassword);
    } else {
      await _prefs.setString(SettingsKeys.serverPassword, password);
    }
    state = state.copyWith(serverPassword: password);
  }

  Future<void> setAutoStartServer(bool value) async {
    await _prefs.setBool(SettingsKeys.autoStartServer, value);
    state = state.copyWith(autoStartServer: value);
  }

  Future<void> setWaiterDashboardShowOwed(bool value) async {
    await _prefs.setBool(SettingsKeys.waiterDashboardShowOwed, value);
    state = state.copyWith(waiterDashboardShowOwed: value);
  }

  Future<void> setEnableSnackBars(bool value) async {
    await _prefs.setBool(SettingsKeys.enableSnackBars, value);
    state = state.copyWith(enableSnackBars: value);
  }

  Future<void> setEnableCustomerDisplay(bool value) async {
    await _prefs.setBool(SettingsKeys.enableCustomerDisplay, value);
    state = state.copyWith(enableCustomerDisplay: value);
  }

  Future<void> setRequireTableForDineIn(bool value) async {
    await _prefs.setBool(SettingsKeys.requireTableForDineIn, value);
    state = state.copyWith(requireTableForDineIn: value);
  }

  Future<void> setRequireWaiterForDineIn(bool value) async {
    await _prefs.setBool(SettingsKeys.requireWaiterForDineIn, value);
    state = state.copyWith(requireWaiterForDineIn: value);
  }

  Future<void> setRequireCustomerForDelivery(bool value) async {
    await _prefs.setBool(SettingsKeys.requireCustomerForDelivery, value);
    state = state.copyWith(requireCustomerForDelivery: value);
  }

  Future<void> setRequireDeliveryAddress(bool value) async {
    await _prefs.setBool(SettingsKeys.requireDeliveryAddress, value);
    state = state.copyWith(requireDeliveryAddress: value);
  }

  Future<void> setAutoClearTableAfterPaying(bool value) async {
    await _prefs.setBool(SettingsKeys.autoClearTableAfterPaying, value);
    state = state.copyWith(autoClearTableAfterPaying: value);
  }

  Future<void> setDefaultPaymentMethod(String method) async {
    await _prefs.setString(SettingsKeys.defaultPaymentMethod, method);
    state = state.copyWith(defaultPaymentMethod: method);
  }

  Future<void> setShowTipDialog(bool value) async {
    await _prefs.setBool(SettingsKeys.showTipDialog, value);
    state = state.copyWith(showTipDialog: value);
  }

  Future<void> setShowTipButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showTipButton, value);
    state = state.copyWith(showTipButton: value);
  }

  Future<void> setAgendaTimeStep(int minutes) async {
    assert(minutes == 60 || minutes == 30 || minutes == 15);
    await _prefs.setInt(SettingsKeys.agendaTimeStep, minutes);
    state = state.copyWith(agendaTimeStep: minutes);
  }

  Future<void> setShowOnscreenKeyboard(bool value) async {
    await _prefs.setBool(SettingsKeys.showOnscreenKeyboard, value);
    state = state.copyWith(showOnscreenKeyboard: value);
  }

  Future<void> setOnscreenKeyboardWidthFraction(double value) async {
    final clamped = value.clamp(0.25, 1.0);
    await _prefs.setDouble(SettingsKeys.onscreenKeyboardWidthFraction, clamped);
    state = state.copyWith(onscreenKeyboardWidthFraction: clamped);
  }

  Future<void> setProductCardSize(int size) async {
    final clamped = size.clamp(1, 3);
    await _prefs.setInt(SettingsKeys.productCardSize, clamped);
    state = state.copyWith(productCardSize: clamped);
  }

  Future<void> setTicketHeader(String header) async {
    await _prefs.setString(SettingsKeys.ticketHeader, header);
    state = state.copyWith(ticketHeader: header);
  }

  Future<void> setTicketFooter(String footer) async {
    await _prefs.setString(SettingsKeys.ticketFooter, footer);
    state = state.copyWith(ticketFooter: footer);
  }

  Future<void> setShowFavoritesCategory(bool value) async {
    await _prefs.setBool(SettingsKeys.showFavoritesCategory, value);
    state = state.copyWith(showFavoritesCategory: value);
  }

  Future<void> setSortByLastUsed(bool value) async {
    await _prefs.setBool(SettingsKeys.sortByLastUsed, value);
    state = state.copyWith(sortByLastUsed: value);
  }

  /// Get the last data clear date
  DateTime? getLastDataClearDate() {
    final dateStr = _prefs.getString(SettingsKeys.lastDataClearDate);
    if (dateStr == null) return null;
    return DateTime.tryParse(dateStr);
  }

  /// Set the last data clear date to now
  Future<void> setLastDataClearDate() async {
    await _prefs.setString(SettingsKeys.lastDataClearDate, DateTime.now().toIso8601String());
  }

  /// Check if data should be cleared today
  bool shouldClearDataToday() {
    if (!state.autoClearSyncedData) return false;

    final lastClearDate = getLastDataClearDate();
    if (lastClearDate == null) return true;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastClearDay = DateTime(lastClearDate.year, lastClearDate.month, lastClearDate.day);

    return today.isAfter(lastClearDay);
  }

  Future<void> resetToDefaults() async {
    await _prefs.remove(SettingsKeys.isDarkMode);
    await _prefs.remove(SettingsKeys.language);
    await _prefs.remove(SettingsKeys.autoSyncOnline);
    await _prefs.remove(SettingsKeys.bulkSyncSize);
    await _prefs.remove(SettingsKeys.dataRetentionDays);
    await _prefs.remove(SettingsKeys.defaultOrderType);
    await _prefs.remove(SettingsKeys.showProductImages);
    await _prefs.remove(SettingsKeys.defaultOrderStatus);
    await _prefs.remove(SettingsKeys.paidOrderDefaultStatus);
    await _prefs.remove(SettingsKeys.categoryDisplayMode);
    await _prefs.remove(SettingsKeys.currency);
    await _prefs.remove(SettingsKeys.showTableButton);
    await _prefs.remove(SettingsKeys.showCustomerButton);
    await _prefs.remove(SettingsKeys.showCommercialButton);
    await _prefs.remove(SettingsKeys.showCouponButton);
    await _prefs.remove(SettingsKeys.showDiscountButton);
    await _prefs.remove(SettingsKeys.showPrintButton);
    await _prefs.remove(SettingsKeys.autoClearSyncedData);
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

final languageProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).language;
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

final currencyProvider = Provider<String>((ref) {
  return ref.watch(settingsProvider).currency;
});

final showOnscreenKeyboardProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).showOnscreenKeyboard;
});

final onscreenKeyboardWidthFractionProvider = Provider<double>((ref) {
  return ref.watch(settingsProvider).onscreenKeyboardWidthFraction;
});

final productCardSizeProvider = Provider<int>((ref) {
  return ref.watch(settingsProvider).productCardSize;
});


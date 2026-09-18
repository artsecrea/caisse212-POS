import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models/app_settings.dart';
import '../services/autostart_service.dart';
import 'database_providers.dart'
    show sharedPreferencesProvider, selectedCategoryProvider;
import 'z_day_provider.dart' show kZDayStateKey;

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
  static const String defaultKdsState = 'default_kds_state';
  static const String printWaiterOrderTicket = 'print_waiter_order_ticket';
  static const String printWaiterPaper = 'print_waiter_paper';
  static const String paidOrderDefaultStatus = 'paid_order_default_status';
  static const String categoryDisplayMode = 'category_display_mode';
  static const String componentGroupDisplayMode =
      'component_group_display_mode';
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
  static const String showProceedButton = 'show_proceed_button';
  static const String showDailySummaryButton = 'show_daily_summary_button';
  static const String buttonOrder = 'button_order';
  static const String showCashDrawerButton = 'show_cash_drawer_button';
  static const String showCancelOrderButton = 'show_cancel_order_button';
  static const String actionButtonAlignment = 'action_button_alignment';
  static const String autoClearSyncedData = 'auto_clear_synced_data';
  static const String lastDataClearDate = 'last_data_clear_date';
  static const String syncUnpaidOrders = 'sync_unpaid_orders';

  static const String orderPanelOnRight = 'order_panel_on_right';

  // Cash-given prompt + ticket division
  static const String payButtonAction = 'pay_button_action';
  static const String externalQueueGridView = 'external_queue_grid_view';
  static const String numericKeypadBeta = 'numeric_keypad_beta';
  static const String quickCashAmounts = 'quick_cash_amounts';
  static const String notePresets = 'note_presets';
  static const String deliveryFeePresets = 'delivery_fee_presets';
  static const String alwaysShowTicketSplit = 'always_show_ticket_split';
  static const String maxSplitTickets = 'max_split_tickets';

  // On-screen keyboard
  static const String showOnscreenKeyboard = 'show_onscreen_keyboard';
  static const String onscreenKeyboardWidthFraction = 'onscreen_keyboard_width_fraction';
  static const String autoFocusProductSearch = 'auto_focus_product_search';

  // Settings lock
  static const String settingsLockEnabled = 'settings_lock_enabled';
  static const String settingsPin = 'settings_pin';

  // Server settings
  static const String serverPort = 'server_port';
  static const String serverPassword = 'server_password';
  static const String autoStartServer = 'auto_start_server';
  static const String openOnStartup = 'open_on_startup';
  static const String waiterDashboardShowOwed = 'waiter_dashboard_show_owed';
  static const String sseEnabled = 'sse_enabled';

  // UI settings
  static const String enableSnackBars = 'enable_snack_bars';
  static const String agendaTimeStep = 'agenda_time_step';

  // Customer Display settings
  static const String enableCustomerDisplay = 'enable_customer_display';
  static const String autoUpdate = 'auto_update';

  // Order validation rules (admin-configurable)
  static const String requireTableForDineIn = 'require_table_for_dine_in';
  static const String requireWaiterForDineIn = 'require_waiter_for_dine_in';
  static const String requireCustomerForDelivery =
      'require_customer_for_delivery';
  static const String requireDeliveryAddress = 'require_delivery_address';
  static const String autoClearTableAfterPaying =
      'auto_clear_table_after_paying';
  static const String zTrackingEnabled = 'z_tracking_enabled';
  static const String zOpenMode = 'z_open_mode';
  static const String zCloseRequireManager = 'z_close_require_manager';
  static const String zCodePrefix = 'z_code_prefix';
  static const String zMaxHours = 'z_max_hours';
  static const String coursesEnabled = 'courses_enabled';
  static const String printKitchenCancellations =
      'print_kitchen_cancellations';
  static const String printProductsByCategoryOnClose =
      'print_products_by_category_on_close';
  static const String printUnpaidOnClose = 'print_unpaid_on_close';
  static const String printSalesByWaiterOnClose =
      'print_sales_by_waiter_on_close';
  static const String printSalesByCashierOnClose =
      'print_sales_by_cashier_on_close';
  static const String requireAdminToCloseUnbalanced =
      'require_admin_close_unbalanced';
  static const String printXOnSessionClose = 'print_x_on_session_close';
  static const String printZDayTotalOnClose = 'print_z_day_total_on_close';
  static const String printDiscountsOnClose = 'print_discounts_on_close';
  static const String zDayLockEnabled = 'z_day_lock_enabled';
  static const String zDayStartHour = 'z_day_start_hour';
  static const String printOrdersListOnClose = 'print_orders_list_on_close';
  static const String printProductSummaryOnClose =
      'print_product_summary_on_close';

  // Payment settings
  static const String defaultPaymentMethod = 'default_payment_method';
  static const String showTipDialog = 'show_tip_dialog';
  static const String showTipButton = 'show_tip_button';

  // Product card size: 1=small, 2=medium, 3=large
  static const String productCardSize = 'product_card_size';
  static const String productLabelOverlay = 'product_label_overlay';
  static const String showBackTileInProductGrid =
      'show_back_tile_in_product_grid';

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

    final componentGroupModeStr =
        _prefs.getString(SettingsKeys.componentGroupDisplayMode);
    final componentGroupMode = ComponentGroupDisplayMode.values.firstWhere(
      (e) => e.name == componentGroupModeStr,
      orElse: () => ComponentGroupDisplayMode.list,
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

    // Migration: DROP 'orderNote'. The note moved out of the action bar and
    // into the order panel's header, next to hold/clear, so the key is dead.
    // Left in a saved list it would render an empty, undraggable row in the
    // button-order editor — the editor skips keys it has no config for, but the
    // slot still counts towards the list's indices.
    if (buttonOrder.contains('orderNote')) {
      buttonOrder = buttonOrder.where((b) => b != 'orderNote').toList();
      _prefs.setStringList(SettingsKeys.buttonOrder, buttonOrder);
    }

    // Migration: Add 'cancelOrder' if missing, next to the other order
    // lifecycle actions. Same reasoning as 'cashDrawer' below — without this
    // it only ever appears on a fresh install.
    if (!buttonOrder.contains('cancelOrder')) {
      final mutableList = List<String>.from(buttonOrder);
      final confirmIndex = mutableList.indexOf('confirmOrder');
      if (confirmIndex >= 0) {
        mutableList.insert(confirmIndex + 1, 'cancelOrder');
      } else {
        mutableList.add('cancelOrder');
      }
      buttonOrder = mutableList;
      _prefs.setStringList(SettingsKeys.buttonOrder, buttonOrder);
    }

    // Migration: Add 'cashDrawer' if missing. Without this the button exists
    // only for fresh installs — every till with a saved button order would
    // silently never show it. Placed after 'print', where the other hardware
    // action already sits.
    if (!buttonOrder.contains('cashDrawer')) {
      final mutableList = List<String>.from(buttonOrder);
      final printIndex = mutableList.indexOf('print');
      if (printIndex >= 0) {
        mutableList.insert(printIndex + 1, 'cashDrawer');
      } else {
        mutableList.add('cashDrawer');
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
      defaultOrderStatus: _safeDefaultStatus(
          _prefs.getString(SettingsKeys.defaultOrderStatus)),
      defaultKdsState: _safeKdsState(
          _prefs.getString(SettingsKeys.defaultKdsState)),
      printWaiterOrderTicket:
          _prefs.getBool(SettingsKeys.printWaiterOrderTicket) ?? true,
      printWaiterPaper:
          _prefs.getBool(SettingsKeys.printWaiterPaper) ?? true,
      paidOrderDefaultStatus: _safeDefaultStatus(
          _prefs.getString(SettingsKeys.paidOrderDefaultStatus)),
      categoryDisplayMode: categoryMode,
      componentGroupDisplayMode: componentGroupMode,
      currency: _prefs.getString(SettingsKeys.currency) ?? '\$',
      showTableButton: _prefs.getBool(SettingsKeys.showTableButton) ?? true,
      showCustomerButton: _prefs.getBool(SettingsKeys.showCustomerButton) ?? false,
      showCommercialButton: _prefs.getBool(SettingsKeys.showCommercialButton) ?? false,
      showWaiterButton: _prefs.getBool(SettingsKeys.showWaiterButton) ?? false,
      showCouponButton: _prefs.getBool(SettingsKeys.showCouponButton) ?? false,
      showDiscountButton: _prefs.getBool(SettingsKeys.showDiscountButton) ?? false,
      showPrintButton: _prefs.getBool(SettingsKeys.showPrintButton) ?? false,
      showPersonsButton: _prefs.getBool(SettingsKeys.showPersonsButton) ?? false,
      showOrderTypeButton: _prefs.getBool(SettingsKeys.showOrderTypeButton) ?? true,
      showConfirmOrderButton: _prefs.getBool(SettingsKeys.showConfirmOrderButton) ?? false,
      showPayButton: _prefs.getBool(SettingsKeys.showPayButton) ?? true,
      showProceedButton: _prefs.getBool(SettingsKeys.showProceedButton) ?? true,
      showCashDrawerButton:
          _prefs.getBool(SettingsKeys.showCashDrawerButton) ?? false,
      showCancelOrderButton:
          _prefs.getBool(SettingsKeys.showCancelOrderButton) ?? false,
      showDailySummaryButton: _prefs.getBool(SettingsKeys.showDailySummaryButton) ?? false,
      buttonOrder: buttonOrder,
      actionButtonAlignment: ActionButtonAlignment.values.firstWhere(
        (e) =>
            e.name == _prefs.getString(SettingsKeys.actionButtonAlignment),
        orElse: () => ActionButtonAlignment.left,
      ),
      autoClearSyncedData: _prefs.getBool(SettingsKeys.autoClearSyncedData) ?? true,
      syncUnpaidOrders: _prefs.getBool(SettingsKeys.syncUnpaidOrders) ?? true,
      orderPanelOnRight: _prefs.getBool(SettingsKeys.orderPanelOnRight) ?? false,
      serverPort: _prefs.getInt(SettingsKeys.serverPort) ?? 8080,
      serverPassword: _prefs.getString(SettingsKeys.serverPassword),
      autoStartServer: _prefs.getBool(SettingsKeys.autoStartServer) ?? false,
      openOnStartup: _prefs.getBool(SettingsKeys.openOnStartup) ??
          _openOnStartupDefault(),
      waiterDashboardShowOwed:
          _prefs.getBool(SettingsKeys.waiterDashboardShowOwed) ?? true,
      sseEnabled: _prefs.getBool(SettingsKeys.sseEnabled) ?? false,
      enableSnackBars: _prefs.getBool(SettingsKeys.enableSnackBars) ?? false,
      enableCustomerDisplay: _prefs.getBool(SettingsKeys.enableCustomerDisplay) ?? false,
      autoUpdate: _prefs.getBool(SettingsKeys.autoUpdate) ?? true,
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
      zTrackingEnabled: _prefs.getBool(SettingsKeys.zTrackingEnabled) ?? false,
      zOpenMode: _prefs.getString(SettingsKeys.zOpenMode) ?? 'auto',
      zCloseRequireManager:
          _prefs.getBool(SettingsKeys.zCloseRequireManager) ?? false,
      zCodePrefix: _prefs.getString(SettingsKeys.zCodePrefix) ?? 'Z',
      zMaxHours: _prefs.getInt(SettingsKeys.zMaxHours) ?? 0,
      coursesEnabled: _prefs.getBool(SettingsKeys.coursesEnabled) ?? false,
      printKitchenCancellations:
          _prefs.getBool(SettingsKeys.printKitchenCancellations) ?? true,
      printProductsByCategoryOnClose:
          _prefs.getBool(SettingsKeys.printProductsByCategoryOnClose) ?? true,
      printUnpaidOnClose:
          _prefs.getBool(SettingsKeys.printUnpaidOnClose) ?? false,
      printSalesByWaiterOnClose:
          _prefs.getBool(SettingsKeys.printSalesByWaiterOnClose) ?? false,
      printSalesByCashierOnClose:
          _prefs.getBool(SettingsKeys.printSalesByCashierOnClose) ?? false,
      requireAdminToCloseUnbalanced:
          _prefs.getBool(SettingsKeys.requireAdminToCloseUnbalanced) ?? false,
      printXOnSessionClose:
          _prefs.getBool(SettingsKeys.printXOnSessionClose) ?? true,
      printZDayTotalOnClose:
          _prefs.getBool(SettingsKeys.printZDayTotalOnClose) ?? false,
      printDiscountsOnClose:
          _prefs.getBool(SettingsKeys.printDiscountsOnClose) ?? false,
      zDayLockEnabled: _prefs.getBool(SettingsKeys.zDayLockEnabled) ?? false,
      zDayStartHour:
          (_prefs.getInt(SettingsKeys.zDayStartHour) ?? 0).clamp(0, 23),
      printOrdersListOnClose:
          _prefs.getBool(SettingsKeys.printOrdersListOnClose) ?? false,
      printProductSummaryOnClose:
          _prefs.getBool(SettingsKeys.printProductSummaryOnClose) ?? false,
      defaultPaymentMethod: _prefs.getString(SettingsKeys.defaultPaymentMethod) ?? 'CASH',
      showTipDialog: _prefs.getBool(SettingsKeys.showTipDialog) ?? false,
      showTipButton: _prefs.getBool(SettingsKeys.showTipButton) ?? false,
      payButtonAction: PayButtonAction.values.firstWhere(
        (e) => e.name == _prefs.getString(SettingsKeys.payButtonAction),
        orElse: () => PayButtonAction.paymentScreen,
      ),
      externalQueueGridView:
          _prefs.getBool(SettingsKeys.externalQueueGridView) ?? false,
      numericKeypadBeta:
          _prefs.getBool(SettingsKeys.numericKeypadBeta) ?? false,
      quickCashAmounts: _readQuickCashAmounts(),
      notePresets: _readNotePresets(),
      deliveryFeePresets: _readDeliveryFeePresets(),
      alwaysShowTicketSplit:
          _prefs.getBool(SettingsKeys.alwaysShowTicketSplit) ?? false,
      maxSplitTickets:
          (_prefs.getInt(SettingsKeys.maxSplitTickets) ?? 10).clamp(2, 50),
      agendaTimeStep: _prefs.getInt(SettingsKeys.agendaTimeStep) ?? 60,
      showOnscreenKeyboard: _prefs.getBool(SettingsKeys.showOnscreenKeyboard) ?? true,
      autoFocusProductSearch:
          _prefs.getBool(SettingsKeys.autoFocusProductSearch) ?? true,
      settingsLockEnabled:
          _prefs.getBool(SettingsKeys.settingsLockEnabled) ?? false,
      settingsPin: _prefs.getString(SettingsKeys.settingsPin) ?? '',
      onscreenKeyboardWidthFraction: _prefs.getDouble(SettingsKeys.onscreenKeyboardWidthFraction) ?? 0.5,
      productCardSize: _prefs.getInt(SettingsKeys.productCardSize) ?? 2,
      productLabelOverlay:
          _prefs.getBool(SettingsKeys.productLabelOverlay) ?? false,
      showBackTileInProductGrid:
          _prefs.getBool(SettingsKeys.showBackTileInProductGrid) ?? false,
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

  // Non-terminal defaults (PENDING/PREPARING) are unsafe: KDS micro-states are
  // LAN-local, so a partially-completed order never fires the all-same-status
  // cloud sync and the backend would stay stuck on the intermediate state.
  // Coerce any legacy persisted value to a safe default. See kds_changes.md.
  static String _safeDefaultStatus(String? stored) {
    return (stored == 'ONHOLD' || stored == 'COMPLETED') ? stored! : 'COMPLETED';
  }

  Future<void> setDefaultOrderStatus(String status) async {
    await _prefs.setString(SettingsKeys.defaultOrderStatus, status);
    state = state.copyWith(defaultOrderStatus: status);
  }

  // The product-level kitchen default. Only the two states a kitchen order can
  // START in are valid; anything else coerces to PENDING.
  static String _safeKdsState(String? stored) {
    return (stored == 'PENDING' || stored == 'PREPARING') ? stored! : 'PENDING';
  }

  Future<void> setDefaultKdsState(String state_) async {
    await _prefs.setString(SettingsKeys.defaultKdsState, state_);
    state = state.copyWith(defaultKdsState: state_);
  }

  Future<void> setPrintWaiterOrderTicket(bool value) async {
    await _prefs.setBool(SettingsKeys.printWaiterOrderTicket, value);
    state = state.copyWith(printWaiterOrderTicket: value);
  }

  Future<void> setPrintWaiterPaper(bool value) async {
    await _prefs.setBool(SettingsKeys.printWaiterPaper, value);
    state = state.copyWith(printWaiterPaper: value);
  }

  Future<void> setPaidOrderDefaultStatus(String status) async {
    await _prefs.setString(SettingsKeys.paidOrderDefaultStatus, status);
    state = state.copyWith(paidOrderDefaultStatus: status);
  }

  Future<void> setCategoryDisplayMode(CategoryDisplayMode mode) async {
    await _prefs.setString(SettingsKeys.categoryDisplayMode, mode.name);
    state = state.copyWith(categoryDisplayMode: mode);
  }

  Future<void> setComponentGroupDisplayMode(
      ComponentGroupDisplayMode mode) async {
    await _prefs.setString(SettingsKeys.componentGroupDisplayMode, mode.name);
    state = state.copyWith(componentGroupDisplayMode: mode);
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

  Future<void> setShowProceedButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showProceedButton, value);
    state = state.copyWith(showProceedButton: value);
  }

  Future<void> setShowDailySummaryButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showDailySummaryButton, value);
    state = state.copyWith(showDailySummaryButton: value);
  }

  Future<void> setButtonOrder(List<String> order) async {
    await _prefs.setStringList(SettingsKeys.buttonOrder, order);
    state = state.copyWith(buttonOrder: order);
  }

  Future<void> setShowCancelOrderButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showCancelOrderButton, value);
    state = state.copyWith(showCancelOrderButton: value);
  }

  Future<void> setShowCashDrawerButton(bool value) async {
    await _prefs.setBool(SettingsKeys.showCashDrawerButton, value);
    state = state.copyWith(showCashDrawerButton: value);
  }

  Future<void> setActionButtonAlignment(ActionButtonAlignment value) async {
    await _prefs.setString(SettingsKeys.actionButtonAlignment, value.name);
    state = state.copyWith(actionButtonAlignment: value);
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

  /// Whether a till that has never been asked should launch on boot.
  ///
  /// A missing key means one of two things, and they want opposite
  /// answers: a brand-new install (say yes) or an update from a build that
  /// had no such setting (say no, and leave the machine as the operator
  /// set it up). `api_base_url` is written the first time a terminal is
  /// pointed at its tenant, so its presence is what tells them apart.
  bool _openOnStartupDefault() =>
      _prefs.getString('api_base_url') == null;

  Future<void> setAutoStartServer(bool value) async {
    await _prefs.setBool(SettingsKeys.autoStartServer, value);
    state = state.copyWith(autoStartServer: value);
  }

  /// Register or unregister the OS autostart entry, then remember the
  /// answer.
  ///
  /// The preference is stored either way. If the registry write or the
  /// autostart file fails - a locked-down till, a read-only home - the
  /// switch still reflects what the operator asked for, and
  /// AutostartService.reconcile on the next launch gets another go at it.
  Future<void> setOpenOnStartup(bool value) async {
    await AutostartService.setEnabled(value);
    await _prefs.setBool(SettingsKeys.openOnStartup, value);
    state = state.copyWith(openOnStartup: value);
  }

  Future<void> setSseEnabled(bool value) async {
    await _prefs.setBool(SettingsKeys.sseEnabled, value);
    state = state.copyWith(sseEnabled: value);
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

  Future<void> setAutoUpdate(bool value) async {
    await _prefs.setBool(SettingsKeys.autoUpdate, value);
    state = state.copyWith(autoUpdate: value);
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

  Future<void> setZTrackingEnabled(bool value) async {
    await _prefs.setBool(SettingsKeys.zTrackingEnabled, value);
    state = state.copyWith(zTrackingEnabled: value);
  }

  Future<void> setZOpenMode(String value) async {
    await _prefs.setString(SettingsKeys.zOpenMode, value);
    state = state.copyWith(zOpenMode: value);
  }

  Future<void> setZCloseRequireManager(bool value) async {
    await _prefs.setBool(SettingsKeys.zCloseRequireManager, value);
    state = state.copyWith(zCloseRequireManager: value);
  }

  Future<void> setZCodePrefix(String value) async {
    final v = value.trim().isEmpty ? 'Z' : value.trim();
    await _prefs.setString(SettingsKeys.zCodePrefix, v);
    state = state.copyWith(zCodePrefix: v);
  }

  Future<void> setZMaxHours(int value) async {
    await _prefs.setInt(SettingsKeys.zMaxHours, value < 0 ? 0 : value);
    state = state.copyWith(zMaxHours: value < 0 ? 0 : value);
  }

  Future<void> setPrintKitchenCancellations(bool value) async {
    await _prefs.setBool(SettingsKeys.printKitchenCancellations, value);
    state = state.copyWith(printKitchenCancellations: value);
  }

  Future<void> setCoursesEnabled(bool value) async {
    await _prefs.setBool(SettingsKeys.coursesEnabled, value);
    state = state.copyWith(coursesEnabled: value);
  }

  Future<void> setPrintProductsByCategoryOnClose(bool value) async {
    await _prefs.setBool(SettingsKeys.printProductsByCategoryOnClose, value);
    state = state.copyWith(printProductsByCategoryOnClose: value);
  }

  Future<void> setPrintUnpaidOnClose(bool value) async {
    await _prefs.setBool(SettingsKeys.printUnpaidOnClose, value);
    state = state.copyWith(printUnpaidOnClose: value);
  }

  Future<void> setPrintSalesByWaiterOnClose(bool value) async {
    await _prefs.setBool(SettingsKeys.printSalesByWaiterOnClose, value);
    state = state.copyWith(printSalesByWaiterOnClose: value);
  }

  Future<void> setPrintSalesByCashierOnClose(bool value) async {
    await _prefs.setBool(SettingsKeys.printSalesByCashierOnClose, value);
    state = state.copyWith(printSalesByCashierOnClose: value);
  }

  Future<void> setRequireAdminToCloseUnbalanced(bool value) async {
    await _prefs.setBool(SettingsKeys.requireAdminToCloseUnbalanced, value);
    state = state.copyWith(requireAdminToCloseUnbalanced: value);
  }

  Future<void> setPrintXOnSessionClose(bool value) async {
    await _prefs.setBool(SettingsKeys.printXOnSessionClose, value);
    state = state.copyWith(printXOnSessionClose: value);
  }

  Future<void> setPrintZDayTotalOnClose(bool value) async {
    await _prefs.setBool(SettingsKeys.printZDayTotalOnClose, value);
    state = state.copyWith(printZDayTotalOnClose: value);
  }

  Future<void> setPrintDiscountsOnClose(bool value) async {
    await _prefs.setBool(SettingsKeys.printDiscountsOnClose, value);
    state = state.copyWith(printDiscountsOnClose: value);
  }

  Future<void> setZDayLockEnabled(bool value) async {
    await _prefs.setBool(SettingsKeys.zDayLockEnabled, value);
    state = state.copyWith(zDayLockEnabled: value);
  }

  Future<void> setZDayStartHour(int value) async {
    final v = value.clamp(0, 23);
    await _prefs.setInt(SettingsKeys.zDayStartHour, v);
    state = state.copyWith(zDayStartHour: v);
  }

  Future<void> setPrintOrdersListOnClose(bool value) async {
    await _prefs.setBool(SettingsKeys.printOrdersListOnClose, value);
    state = state.copyWith(printOrdersListOnClose: value);
  }

  Future<void> setPrintProductSummaryOnClose(bool value) async {
    await _prefs.setBool(SettingsKeys.printProductSummaryOnClose, value);
    state = state.copyWith(printProductSummaryOnClose: value);
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

  /// Denominations persist as a string list because SharedPreferences has no
  /// int-list type. Garbage entries are dropped rather than throwing, so a
  /// hand-edited prefs file can't brick the payment flow.
  List<int> _readQuickCashAmounts() {
    final raw = _prefs.getStringList(SettingsKeys.quickCashAmounts);
    if (raw == null) return const [200, 100, 50, 20];
    final parsed = raw
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .where((e) => e > 0)
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return parsed.isEmpty ? const [200, 100, 50, 20] : parsed;
  }

  /// The shop's own one-tap notes, in the order they were written. Order is
  /// preserved rather than sorted: the cashier decides which note they reach
  /// for most, and a list that reshuffles itself is slower to use, not faster.
  List<String> _readNotePresets() {
    final raw = _prefs.getStringList(SettingsKeys.notePresets);
    if (raw == null) return const [];
    return raw.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  Future<void> setNotePresets(List<String> presets) async {
    final cleaned = <String>[];
    for (final p in presets) {
      final text = p.trim();
      if (text.isEmpty || cleaned.contains(text)) continue;
      cleaned.add(text);
    }
    await _prefs.setStringList(SettingsKeys.notePresets, cleaned);
    state = state.copyWith(notePresets: cleaned);
  }

  /// One-tap delivery fees, cheapest first. Zero is kept on purpose — "free
  /// delivery" is a real amount to charge, and distinct from clearing the fee.
  List<double> _readDeliveryFeePresets() {
    final raw = _prefs.getStringList(SettingsKeys.deliveryFeePresets);
    // Never set: offer a starting set rather than an empty row of chips.
    // Explicitly emptied is a different answer and is respected.
    if (raw == null) return const [10, 15, 20, 30];
    final parsed = raw
        .map((e) => double.tryParse(e.trim().replaceAll(',', '.')))
        .whereType<double>()
        .where((e) => e >= 0)
        .toList()
      ..sort();
    return parsed;
  }

  Future<void> setDeliveryFeePresets(List<double> fees) async {
    final cleaned = fees.where((e) => e >= 0).toSet().toList()..sort();
    await _prefs.setStringList(
      SettingsKeys.deliveryFeePresets,
      cleaned.map((e) => e.toString()).toList(),
    );
    state = state.copyWith(deliveryFeePresets: cleaned);
  }

  Future<void> setQuickCashAmounts(List<int> amounts) async {
    final cleaned = amounts.where((e) => e > 0).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
    final effective = cleaned.isEmpty ? const [200, 100, 50, 20] : cleaned;
    await _prefs.setStringList(
      SettingsKeys.quickCashAmounts,
      effective.map((e) => e.toString()).toList(),
    );
    state = state.copyWith(quickCashAmounts: effective);
  }

  Future<void> setPayButtonAction(PayButtonAction value) async {
    await _prefs.setString(SettingsKeys.payButtonAction, value.name);
    state = state.copyWith(payButtonAction: value);
  }

  Future<void> setNumericKeypadBeta(bool value) async {
    await _prefs.setBool(SettingsKeys.numericKeypadBeta, value);
    state = state.copyWith(numericKeypadBeta: value);
  }

  Future<void> setExternalQueueGridView(bool value) async {
    await _prefs.setBool(SettingsKeys.externalQueueGridView, value);
    state = state.copyWith(externalQueueGridView: value);
  }

  Future<void> setAlwaysShowTicketSplit(bool value) async {
    await _prefs.setBool(SettingsKeys.alwaysShowTicketSplit, value);
    state = state.copyWith(alwaysShowTicketSplit: value);
  }

  Future<void> setMaxSplitTickets(int value) async {
    final clamped = value.clamp(2, 50);
    await _prefs.setInt(SettingsKeys.maxSplitTickets, clamped);
    state = state.copyWith(maxSplitTickets: clamped);
  }

  Future<void> setAutoFocusProductSearch(bool value) async {
    await _prefs.setBool(SettingsKeys.autoFocusProductSearch, value);
    state = state.copyWith(autoFocusProductSearch: value);
  }

  /// Turn the Settings lock on or off, and set the code that opens it.
  ///
  /// A [pin] that is not exactly four digits is rejected rather than stored,
  /// because the unlock dialog only ever submits four — anything else would
  /// be a code nobody can type. Turning the lock OFF keeps the stored pin so
  /// switching it back on does not silently need a new one.
  Future<bool> setSettingsLock({required bool enabled, String? pin}) async {
    if (pin != null) {
      if (!RegExp(r'^\d{4}$').hasMatch(pin)) return false;
      await _prefs.setString(SettingsKeys.settingsPin, pin);
      state = state.copyWith(settingsPin: pin);
    }
    // Refuse to arm a lock with no code — see [AppSettings.settingsPin].
    if (enabled && state.settingsPin.isEmpty) return false;
    await _prefs.setBool(SettingsKeys.settingsLockEnabled, enabled);
    state = state.copyWith(settingsLockEnabled: enabled);
    return true;
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

  Future<void> setProductLabelOverlay(bool value) async {
    await _prefs.setBool(SettingsKeys.productLabelOverlay, value);
    state = state.copyWith(productLabelOverlay: value);
  }

  Future<void> setShowBackTileInProductGrid(bool value) async {
    await _prefs.setBool(SettingsKeys.showBackTileInProductGrid, value);
    state = state.copyWith(showBackTileInProductGrid: value);
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
    await _prefs.remove(SettingsKeys.componentGroupDisplayMode);
    await _prefs.remove(SettingsKeys.currency);
    await _prefs.remove(SettingsKeys.showTableButton);
    await _prefs.remove(SettingsKeys.showCustomerButton);
    await _prefs.remove(SettingsKeys.showCommercialButton);
    await _prefs.remove(SettingsKeys.showCouponButton);
    await _prefs.remove(SettingsKeys.showDiscountButton);
    await _prefs.remove(SettingsKeys.showPrintButton);
    await _prefs.remove(SettingsKeys.showWaiterButton);
    await _prefs.remove(SettingsKeys.showPersonsButton);
    await _prefs.remove(SettingsKeys.showOrderTypeButton);
    await _prefs.remove(SettingsKeys.showConfirmOrderButton);
    await _prefs.remove(SettingsKeys.showPayButton);
    await _prefs.remove(SettingsKeys.showProceedButton);
    await _prefs.remove(SettingsKeys.showDailySummaryButton);
    await _prefs.remove(SettingsKeys.showCashDrawerButton);
    await _prefs.remove(SettingsKeys.showCancelOrderButton);
    await _prefs.remove(SettingsKeys.showTipButton);
    await _prefs.remove(SettingsKeys.buttonOrder);
    await _prefs.remove(SettingsKeys.actionButtonAlignment);
    await _prefs.remove(SettingsKeys.openOnStartup);
    await _prefs.remove(SettingsKeys.autoClearSyncedData);
    await _prefs.remove(SettingsKeys.sseEnabled);
    await _prefs.remove(SettingsKeys.zDayLockEnabled);
    await _prefs.remove(SettingsKeys.zDayStartHour);
    await _prefs.remove(SettingsKeys.printOrdersListOnClose);
    await _prefs.remove(SettingsKeys.printProductSummaryOnClose);
    // The day/Z-number counter is not an AppSettings field, but a reset that
    // left a "day closed" lock behind would block login with no way to explain
    // it from the settings UI.
    await _prefs.remove(kZDayStateKey);
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

final componentGroupDisplayModeProvider =
    Provider<ComponentGroupDisplayMode>((ref) {
  return ref.watch(settingsProvider).componentGroupDisplayMode;
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

/// Whether the product grid is currently showing its "back to categories"
/// tile.
///
/// One definition, because two things depend on it and they must agree: the
/// grid draws the tile, and the main screen hides the category bar behind it.
/// If they ever disagreed a shop would get both controls or neither.
///
/// Needs all three: the setting on, full-page mode (in top-bar mode the
/// categories never leave the screen, so there is nothing to return to), and a
/// category actually open (on the unfiltered grid the tile would go nowhere).
final productGridBackTileProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider);
  return ref.watch(categoryBarHiddenProvider) &&
      // The tile only means anything once you are inside a category; at the
      // top level there is nothing to go back to.
      ref.watch(selectedCategoryProvider) != null &&
      settings.showBackTileInProductGrid;
});

/// Whether the category bar above the grid is suppressed entirely.
///
/// Deliberately NOT conditioned on a category being selected, unlike
/// [productGridBackTileProvider]. In this mode the category *grid* is the
/// picker and the back tile is the way out of it, so the bar has no job at
/// either level — at the top it was a button labelled "All Categories" sitting
/// above a page of categories, which says nothing the page does not.
final categoryBarHiddenProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.showBackTileInProductGrid &&
      settings.categoryDisplayMode == CategoryDisplayMode.fullPage;
});

/// BETA: numeric fields open a keypad beside them rather than the bottom bar.
final numericKeypadBetaProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).numericKeypadBeta;
});

/// Whether product labels sit on the image rather than beneath it.
final productLabelOverlayProvider = Provider<bool>((ref) {
  return ref.watch(settingsProvider).productLabelOverlay;
});

final productCardSizeProvider = Provider<int>((ref) {
  return ref.watch(settingsProvider).productCardSize;
});


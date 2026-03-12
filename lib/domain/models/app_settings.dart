// Category display mode enum
enum CategoryDisplayMode {
  topBar,    // Categories in top bar, products below (default)
  fullPage,  // Categories shown as full page grid, then products after selection
}

// App Settings Model
class AppSettings {
  final bool isDarkMode;
  final String language; // 'en', 'ar', 'fr'
  final String defaultOrderType; // 'DINE_IN' or 'TAKE_AWAY'
  final bool showProductImages;
  final String defaultOrderStatus; // 'PENDING', 'ONHOLD', etc.
  final CategoryDisplayMode categoryDisplayMode; // How to display categories
  final String currency; // Currency symbol (e.g., '$', '€', '£', 'DH')

  // Action button visibility
  final bool showTableButton;
  final bool showCustomerButton;
  final bool showCommercialButton;
  final bool showWaiterButton;
  final bool showCouponButton;
  final bool showDiscountButton;
  final bool showPrintButton;
  final bool showPersonsButton;
  final bool showOrderTypeButton;
  final bool showConfirmOrderButton;
  final bool showPayButton;
  final bool showDailySummaryButton;

  // Button order - list of button keys defining the order
  final List<String> buttonOrder;

  // Sync settings
  final bool autoSyncOnline; // Auto-sync orders when online
  final int bulkSyncSize; // Number of orders to sync at once when offline
  final int dataRetentionDays; // Days to keep synced data before deletion
  final int autoSyncDurationMinutes; // Auto-sync interval in minutes (default: 5)
  final bool autoClearSyncedData; // Clear synced data at start of each day
  final bool orderPanelOnRight;

  // Server settings
  final int? serverPort; // HTTP server port (default: 8080)
  final String? serverPassword; // Optional password for server authentication
  final bool autoStartServer; // Auto-start server on app startup

  // UI settings
  final bool enableSnackBars; // Enable/disable snack bar notifications globally

  const AppSettings({
    this.isDarkMode = false,
    this.language = 'en',
    this.defaultOrderType = 'DINE_IN',
    this.showProductImages = true,
    this.defaultOrderStatus = 'PENDING',
    this.categoryDisplayMode = CategoryDisplayMode.topBar,
    this.currency = 'DH',
    this.showTableButton = true,
    this.showCustomerButton = true,
    this.showCommercialButton = true,
    this.showWaiterButton = true,
    this.showCouponButton = true,
    this.showDiscountButton = true,
    this.showPrintButton = true,
    this.showPersonsButton = true,
    this.showOrderTypeButton = true,
    this.showConfirmOrderButton = true,
    this.showPayButton = true,
    this.showDailySummaryButton = true,
    this.buttonOrder = const [
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
      'pay',
      'proceed',
    ],
    this.autoSyncOnline = true,
    this.bulkSyncSize = 50,
    this.dataRetentionDays = 7,
    this.autoSyncDurationMinutes = 5,
    this.autoClearSyncedData = true,
    this.orderPanelOnRight = false,
    this.serverPort = 2004,
    this.serverPassword,
    this.autoStartServer = true,
    this.enableSnackBars = false,
  });

  AppSettings copyWith({
    bool? isDarkMode,
    String? language,
    String? defaultOrderType,
    bool? showProductImages,
    String? defaultOrderStatus,
    CategoryDisplayMode? categoryDisplayMode,
    String? currency,
    bool? showTableButton,
    bool? showCustomerButton,
    bool? showCommercialButton,
    bool? showWaiterButton,
    bool? showCouponButton,
    bool? showDiscountButton,
    bool? showPrintButton,
    bool? showPersonsButton,
    bool? showOrderTypeButton,
    bool? showConfirmOrderButton,
    bool? showPayButton,
    bool? showDailySummaryButton,
    List<String>? buttonOrder,
    bool? autoSyncOnline,
    int? bulkSyncSize,
    int? dataRetentionDays,
    int? autoSyncDurationMinutes,
    bool? autoClearSyncedData,
    bool? orderPanelOnRight,
    int? serverPort,
    String? serverPassword,
    bool? autoStartServer,
    bool? enableSnackBars,
  }) {
    return AppSettings(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      language: language ?? this.language,
      defaultOrderType: defaultOrderType ?? this.defaultOrderType,
      showProductImages: showProductImages ?? this.showProductImages,
      defaultOrderStatus: defaultOrderStatus ?? this.defaultOrderStatus,
      categoryDisplayMode: categoryDisplayMode ?? this.categoryDisplayMode,
      currency: currency ?? this.currency,
      showTableButton: showTableButton ?? this.showTableButton,
      showCustomerButton: showCustomerButton ?? this.showCustomerButton,
      showCommercialButton: showCommercialButton ?? this.showCommercialButton,
      showWaiterButton: showWaiterButton ?? this.showWaiterButton,
      showCouponButton: showCouponButton ?? this.showCouponButton,
      showDiscountButton: showDiscountButton ?? this.showDiscountButton,
      showPrintButton: showPrintButton ?? this.showPrintButton,
      showPersonsButton: showPersonsButton ?? this.showPersonsButton,
      showOrderTypeButton: showOrderTypeButton ?? this.showOrderTypeButton,
      showConfirmOrderButton: showConfirmOrderButton ?? this.showConfirmOrderButton,
      showPayButton: showPayButton ?? this.showPayButton,
      showDailySummaryButton: showDailySummaryButton ?? this.showDailySummaryButton,
      buttonOrder: buttonOrder ?? this.buttonOrder,
      autoSyncOnline: autoSyncOnline ?? this.autoSyncOnline,
      bulkSyncSize: bulkSyncSize ?? this.bulkSyncSize,
      dataRetentionDays: dataRetentionDays ?? this.dataRetentionDays,
      autoSyncDurationMinutes: autoSyncDurationMinutes ?? this.autoSyncDurationMinutes,
      autoClearSyncedData: autoClearSyncedData ?? this.autoClearSyncedData,
      orderPanelOnRight: orderPanelOnRight ?? this.orderPanelOnRight,
      serverPort: serverPort ?? this.serverPort,
      serverPassword: serverPassword ?? this.serverPassword,
      autoStartServer: autoStartServer ?? this.autoStartServer,
      enableSnackBars: enableSnackBars ?? this.enableSnackBars,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isDarkMode': isDarkMode,
      'language': language,
      'defaultOrderType': defaultOrderType,
      'showProductImages': showProductImages,
      'defaultOrderStatus': defaultOrderStatus,
      'categoryDisplayMode': categoryDisplayMode.name,
      'currency': currency,
      'showTableButton': showTableButton,
      'showCustomerButton': showCustomerButton,
      'showCommercialButton': showCommercialButton,
      'showWaiterButton': showWaiterButton,
      'showCouponButton': showCouponButton,
      'showDiscountButton': showDiscountButton,
      'showPrintButton': showPrintButton,
      'showPersonsButton': showPersonsButton,
      'showOrderTypeButton': showOrderTypeButton,
      'showConfirmOrderButton': showConfirmOrderButton,
      'showPayButton': showPayButton,
      'showDailySummaryButton': showDailySummaryButton,
      'buttonOrder': buttonOrder,
      'autoSyncOnline': autoSyncOnline,
      'bulkSyncSize': bulkSyncSize,
      'dataRetentionDays': dataRetentionDays,
      'autoSyncDurationMinutes': autoSyncDurationMinutes,
      'autoClearSyncedData': autoClearSyncedData,
      'orderPanelOnRight': orderPanelOnRight,
      'serverPort': serverPort,
      'serverPassword': serverPassword,
      'autoStartServer': autoStartServer,
      'enableSnackBars': enableSnackBars,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      isDarkMode: json['isDarkMode'] as bool? ?? false,
      defaultOrderType: json['defaultOrderType'] as String? ?? 'DINE_IN',
      showProductImages: json['showProductImages'] as bool? ?? true,
      defaultOrderStatus: json['defaultOrderStatus'] as String? ?? 'PENDING',
      categoryDisplayMode: CategoryDisplayMode.values.firstWhere(
        (e) => e.name == json['categoryDisplayMode'],
        orElse: () => CategoryDisplayMode.topBar,
      ),
      currency: json['currency'] as String? ?? '\$',
      showTableButton: json['showTableButton'] as bool? ?? true,
      showCustomerButton: json['showCustomerButton'] as bool? ?? true,
      showCommercialButton: json['showCommercialButton'] as bool? ?? true,
      showWaiterButton: json['showWaiterButton'] as bool? ?? true,
      showCouponButton: json['showCouponButton'] as bool? ?? true,
      showDiscountButton: json['showDiscountButton'] as bool? ?? true,
      showPrintButton: json['showPrintButton'] as bool? ?? true,
      showPersonsButton: json['showPersonsButton'] as bool? ?? true,
      showOrderTypeButton: json['showOrderTypeButton'] as bool? ?? true,
      showConfirmOrderButton: json['showConfirmOrderButton'] as bool? ?? true,
      showPayButton: json['showPayButton'] as bool? ?? true,
      showDailySummaryButton: json['showDailySummaryButton'] as bool? ?? true,
      buttonOrder: (json['buttonOrder'] as List<dynamic>?)?.cast<String>() ?? const [
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
        'pay',
        'proceed',
      ],
      autoSyncOnline: json['autoSyncOnline'] as bool? ?? true,
      bulkSyncSize: json['bulkSyncSize'] as int? ?? 50,
      dataRetentionDays: json['dataRetentionDays'] as int? ?? 7,
      autoSyncDurationMinutes: json['autoSyncDurationMinutes'] as int? ?? 5,
      autoClearSyncedData: json['autoClearSyncedData'] as bool? ?? true,
      orderPanelOnRight: json['orderPanelOnRight'] as bool? ?? false,
      serverPort: json['serverPort'] as int?,
      serverPassword: json['serverPassword'] as String?,
      autoStartServer: json['autoStartServer'] as bool? ?? true,
      enableSnackBars: json['enableSnackBars'] as bool? ?? true,
    );
  }

  @override
  String toString() {
    return 'AppSettings(isDarkMode: $isDarkMode, defaultOrderType: $defaultOrderType, showProductImages: $showProductImages, defaultOrderStatus: $defaultOrderStatus, categoryDisplayMode: $categoryDisplayMode, currency: $currency)';
  }
}

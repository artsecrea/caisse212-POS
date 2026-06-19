// Category display mode enum
enum CategoryDisplayMode {
  topBar,    // Categories in top bar, products below (default)
  fullPage,  // Categories shown as full page grid, then products after selection
}

// App Settings Model
class AppSettings {
  final bool isDarkMode;
  final String language; // 'en', 'ar', 'fr'
  final String loggingLanguage; // Language used for stored activity-log phrases
  final List<String> cashierDefaultPermissions; // Auto-granted to users where type == 'cashier'
  final String defaultOrderType; // 'DINE_IN' or 'TAKE_AWAY'
  final bool showProductImages;
  final String defaultOrderStatus; // 'PENDING', 'ONHOLD', etc.
  /// Status assigned to orders posted through `/waiters/orders` by the
  /// waiter app. Defaults to 'PENDING' (matches the legacy hard-coded
  /// behaviour). 'PREPARING' = skip the kitchen ACK step. 'COMPLETED' =
  /// pre-pay / dine-and-leave flow where the waiter takes payment.
  final String waiterOrderDefaultStatus;
  /// When true, orders posted through `/waiters/orders` arrive already
  /// paid: the server auto-creates a CASH ticket for the full amount,
  /// marks every product PAID, and bumps the order status to
  /// [paidOrderDefaultStatus]. Use this when the waiter collects cash at
  /// the table; leave off (default) when the cashier settles later via
  /// the waiter profile / settlement dialog.
  final bool waiterOrderDefaultPaid;
  /// When false, the order-ticket auto-print is skipped on waiter-created
  /// orders even when the source rule allows it. KDS prints still fire.
  /// Default true (current behavior preserved). Common reason to turn
  /// off: the waiter already has a handheld printer / the cashier doesn't
  /// need a paper copy of every waiter order.
  final bool printWaiterOrderTicket;
  final String paidOrderDefaultStatus; // Default status for paid orders: 'COMPLETED', 'DELIVERED', etc.
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
  final bool syncUnpaidOrders; // Whether to sync unpaid orders (default: true)
  final bool orderPanelOnRight;

  // Server settings
  final int? serverPort; // HTTP server port (default: 8080)
  final String? serverPassword; // Optional password for server authentication
  final bool autoStartServer; // Auto-start server on app startup
  /// When false, the `GET /waiters/dashboard` endpoint omits the financial
  /// fields (`expectedCash`, `totalCash`, `cancelledAmount`) from the
  /// response so the waiter app can't display amounts owed/collected.
  /// Defaults to true (current behavior preserved).
  final bool waiterDashboardShowOwed;

  // UI settings
  final bool enableSnackBars; // Enable/disable snack bar notifications globally

  // Customer Display settings
  final bool enableCustomerDisplay; // Enable/disable customer-facing second screen

  // Order validation rules — admin-configurable gates that block save/pay
  // until the required field is filled. Default OFF preserves legacy behavior.
  final bool requireTableForDineIn;
  final bool requireWaiterForDineIn;
  final bool requireCustomerForDelivery;
  final bool requireDeliveryAddress;

  /// When enabled, the table assignment is cleared as soon as every product
  /// on the order is marked PAID. Default OFF.
  final bool autoClearTableAfterPaying;

  // Payment settings
  final String defaultPaymentMethod; // Default payment method: 'CASH', 'CARD', 'MOBILE', 'OTHER'

  /// When enabled, clicking the "Pay" button (after any required table /
  /// waiter selection) shows the tip dialog before opening PaymentScreen.
  /// Tips go through `PATCH /api/orders/{id}/tip` — local-only-orders (no
  /// server id) skip the dialog automatically.
  final bool showTipDialog;

  /// Visibility of the dedicated "Tip" action button in the POS toolbar.
  /// Independent from [showTipDialog] — a cashier can want a button to
  /// edit the tip explicitly even if they don't want the auto-prompt on
  /// pay, or vice versa.
  final bool showTipButton;

  // Agenda settings
  final int agendaTimeStep; // Time grid interval in minutes: 60, 30, or 15

  // On-screen keyboard settings
  final bool showOnscreenKeyboard; // Show/hide the on-screen soft keyboard
  final double onscreenKeyboardWidthFraction; // Width as fraction of screen width (0.25–1.0)

  // Product card size: 1=small, 2=medium, 3=large
  final int productCardSize;

  // Ticket printing settings
  final String ticketHeader; // Header text to print at top of ticket
  final String ticketFooter; // Footer text to print at bottom of ticket

  const AppSettings({
    this.isDarkMode = false,
    this.language = 'en',
    this.loggingLanguage = 'en',
    this.cashierDefaultPermissions = const [],
    this.defaultOrderType = 'DINE_IN',
    this.showProductImages = true,
    this.defaultOrderStatus = 'PENDING',
    this.waiterOrderDefaultStatus = 'PENDING',
    this.waiterOrderDefaultPaid = false,
    this.printWaiterOrderTicket = true,
    this.paidOrderDefaultStatus = 'COMPLETED',
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
    this.syncUnpaidOrders = true,
    this.orderPanelOnRight = false,
    this.serverPort = 2004,
    this.serverPassword,
    this.autoStartServer = true,
    this.waiterDashboardShowOwed = true,
    this.enableSnackBars = false,
    this.enableCustomerDisplay = false,
    this.requireTableForDineIn = false,
    this.requireWaiterForDineIn = false,
    this.requireCustomerForDelivery = false,
    this.requireDeliveryAddress = false,
    this.autoClearTableAfterPaying = false,
    this.defaultPaymentMethod = 'CASH',
    this.showTipDialog = false,
    this.showTipButton = false,
    this.agendaTimeStep = 60,
    this.showOnscreenKeyboard = true,
    this.onscreenKeyboardWidthFraction = 0.5,
    this.productCardSize = 2,
    this.ticketHeader = '',
    this.ticketFooter = '',
  });

  AppSettings copyWith({
    bool? isDarkMode,
    String? language,
    String? loggingLanguage,
    List<String>? cashierDefaultPermissions,
    String? defaultOrderType,
    bool? showProductImages,
    String? defaultOrderStatus,
    String? waiterOrderDefaultStatus,
    bool? waiterOrderDefaultPaid,
    bool? printWaiterOrderTicket,
    String? paidOrderDefaultStatus,
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
    bool? syncUnpaidOrders,
    bool? orderPanelOnRight,
    int? serverPort,
    String? serverPassword,
    bool? autoStartServer,
    bool? waiterDashboardShowOwed,
    bool? enableSnackBars,
    bool? enableCustomerDisplay,
    bool? requireTableForDineIn,
    bool? requireWaiterForDineIn,
    bool? requireCustomerForDelivery,
    bool? requireDeliveryAddress,
    bool? autoClearTableAfterPaying,
    String? defaultPaymentMethod,
    bool? showTipDialog,
    bool? showTipButton,
    int? agendaTimeStep,
    bool? showOnscreenKeyboard,
    double? onscreenKeyboardWidthFraction,
    int? productCardSize,
    String? ticketHeader,
    String? ticketFooter,
  }) {
    return AppSettings(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      language: language ?? this.language,
      loggingLanguage: loggingLanguage ?? this.loggingLanguage,
      cashierDefaultPermissions:
          cashierDefaultPermissions ?? this.cashierDefaultPermissions,
      defaultOrderType: defaultOrderType ?? this.defaultOrderType,
      showProductImages: showProductImages ?? this.showProductImages,
      defaultOrderStatus: defaultOrderStatus ?? this.defaultOrderStatus,
      waiterOrderDefaultStatus:
          waiterOrderDefaultStatus ?? this.waiterOrderDefaultStatus,
      waiterOrderDefaultPaid:
          waiterOrderDefaultPaid ?? this.waiterOrderDefaultPaid,
      printWaiterOrderTicket:
          printWaiterOrderTicket ?? this.printWaiterOrderTicket,
      paidOrderDefaultStatus: paidOrderDefaultStatus ?? this.paidOrderDefaultStatus,
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
      syncUnpaidOrders: syncUnpaidOrders ?? this.syncUnpaidOrders,
      orderPanelOnRight: orderPanelOnRight ?? this.orderPanelOnRight,
      serverPort: serverPort ?? this.serverPort,
      serverPassword: serverPassword ?? this.serverPassword,
      autoStartServer: autoStartServer ?? this.autoStartServer,
      waiterDashboardShowOwed:
          waiterDashboardShowOwed ?? this.waiterDashboardShowOwed,
      enableSnackBars: enableSnackBars ?? this.enableSnackBars,
      enableCustomerDisplay: enableCustomerDisplay ?? this.enableCustomerDisplay,
      requireTableForDineIn:
          requireTableForDineIn ?? this.requireTableForDineIn,
      requireWaiterForDineIn:
          requireWaiterForDineIn ?? this.requireWaiterForDineIn,
      requireCustomerForDelivery:
          requireCustomerForDelivery ?? this.requireCustomerForDelivery,
      requireDeliveryAddress:
          requireDeliveryAddress ?? this.requireDeliveryAddress,
      autoClearTableAfterPaying:
          autoClearTableAfterPaying ?? this.autoClearTableAfterPaying,
      defaultPaymentMethod: defaultPaymentMethod ?? this.defaultPaymentMethod,
      showTipDialog: showTipDialog ?? this.showTipDialog,
      showTipButton: showTipButton ?? this.showTipButton,
      agendaTimeStep: agendaTimeStep ?? this.agendaTimeStep,
      showOnscreenKeyboard: showOnscreenKeyboard ?? this.showOnscreenKeyboard,
      onscreenKeyboardWidthFraction: onscreenKeyboardWidthFraction ?? this.onscreenKeyboardWidthFraction,
      productCardSize: productCardSize ?? this.productCardSize,
      ticketHeader: ticketHeader ?? this.ticketHeader,
      ticketFooter: ticketFooter ?? this.ticketFooter,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isDarkMode': isDarkMode,
      'language': language,
      'loggingLanguage': loggingLanguage,
      'cashierDefaultPermissions': cashierDefaultPermissions,
      'defaultOrderType': defaultOrderType,
      'showProductImages': showProductImages,
      'defaultOrderStatus': defaultOrderStatus,
      'waiterOrderDefaultStatus': waiterOrderDefaultStatus,
      'waiterOrderDefaultPaid': waiterOrderDefaultPaid,
      'printWaiterOrderTicket': printWaiterOrderTicket,
      'paidOrderDefaultStatus': paidOrderDefaultStatus,
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
      'syncUnpaidOrders': syncUnpaidOrders,
      'orderPanelOnRight': orderPanelOnRight,
      'serverPort': serverPort,
      'serverPassword': serverPassword,
      'autoStartServer': autoStartServer,
      'waiterDashboardShowOwed': waiterDashboardShowOwed,
      'enableSnackBars': enableSnackBars,
      'enableCustomerDisplay': enableCustomerDisplay,
      'requireTableForDineIn': requireTableForDineIn,
      'requireWaiterForDineIn': requireWaiterForDineIn,
      'requireCustomerForDelivery': requireCustomerForDelivery,
      'requireDeliveryAddress': requireDeliveryAddress,
      'autoClearTableAfterPaying': autoClearTableAfterPaying,
      'defaultPaymentMethod': defaultPaymentMethod,
      'showTipDialog': showTipDialog,
      'showTipButton': showTipButton,
      'agendaTimeStep': agendaTimeStep,
      'showOnscreenKeyboard': showOnscreenKeyboard,
      'onscreenKeyboardWidthFraction': onscreenKeyboardWidthFraction,
      'productCardSize': productCardSize,
      'ticketHeader': ticketHeader,
      'ticketFooter': ticketFooter,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      isDarkMode: json['isDarkMode'] as bool? ?? false,
      language: json['language'] as String? ?? 'en',
      loggingLanguage: json['loggingLanguage'] as String? ?? (json['language'] as String? ?? 'en'),
      cashierDefaultPermissions: (json['cashierDefaultPermissions'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      defaultOrderType: json['defaultOrderType'] as String? ?? 'DINE_IN',
      showProductImages: json['showProductImages'] as bool? ?? true,
      defaultOrderStatus: json['defaultOrderStatus'] as String? ?? 'PENDING',
      paidOrderDefaultStatus: json['paidOrderDefaultStatus'] as String? ?? 'COMPLETED',
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
      syncUnpaidOrders: json['syncUnpaidOrders'] as bool? ?? true,
      orderPanelOnRight: json['orderPanelOnRight'] as bool? ?? false,
      serverPort: json['serverPort'] as int?,
      serverPassword: json['serverPassword'] as String?,
      autoStartServer: json['autoStartServer'] as bool? ?? true,
      waiterDashboardShowOwed:
          json['waiterDashboardShowOwed'] as bool? ?? true,
      enableSnackBars: json['enableSnackBars'] as bool? ?? true,
      enableCustomerDisplay: json['enableCustomerDisplay'] as bool? ?? false,
      requireTableForDineIn:
          json['requireTableForDineIn'] as bool? ?? false,
      requireWaiterForDineIn:
          json['requireWaiterForDineIn'] as bool? ?? false,
      requireCustomerForDelivery:
          json['requireCustomerForDelivery'] as bool? ?? false,
      requireDeliveryAddress:
          json['requireDeliveryAddress'] as bool? ?? false,
      autoClearTableAfterPaying:
          json['autoClearTableAfterPaying'] as bool? ?? false,
      defaultPaymentMethod: json['defaultPaymentMethod'] as String? ?? 'CASH',
      showTipDialog: json['showTipDialog'] as bool? ?? false,
      showTipButton: json['showTipButton'] as bool? ?? false,
      agendaTimeStep: json['agendaTimeStep'] as int? ?? 60,
      showOnscreenKeyboard: json['showOnscreenKeyboard'] as bool? ?? true,
      onscreenKeyboardWidthFraction: (json['onscreenKeyboardWidthFraction'] as num?)?.toDouble() ?? 0.5,
      productCardSize: json['productCardSize'] as int? ?? 2,
      ticketHeader: json['ticketHeader'] as String? ?? '',
      ticketFooter: json['ticketFooter'] as String? ?? '',
    );
  }

  @override
  String toString() {
    return 'AppSettings(isDarkMode: $isDarkMode, defaultOrderType: $defaultOrderType, showProductImages: $showProductImages, defaultOrderStatus: $defaultOrderStatus, categoryDisplayMode: $categoryDisplayMode, currency: $currency)';
  }
}

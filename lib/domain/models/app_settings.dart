// Category display mode enum
enum CategoryDisplayMode {
  topBar,    // Categories in top bar, products below (default)
  fullPage,  // Categories shown as full page grid, then products after selection
}

/// How the option groups are laid out inside the product modification
/// dialog.
enum ComponentGroupDisplayMode {
  /// Every group stacked in one scrolling list, each behind its own header.
  /// The default, and what the dialog has always done.
  list,

  /// One group on screen at a time, walked through with Back / Next. Long
  /// option sets stop being a scroll, and a required group can no longer be
  /// scrolled past without being seen.
  step,
}

/// Horizontal placement of the POS action-button bar at the bottom of the
/// main screen. Only takes effect while the buttons fit the screen — once
/// they overflow the bar scrolls and alignment is moot.
enum ActionButtonAlignment { left, center, right }

/// What a single tap on the POS "Pay" button does. The long press always does
/// the other one, so both routes stay one gesture away.
enum PayButtonAction {
  /// Open the payment screen: cash pad, change due, ticket division.
  paymentScreen,

  /// Settle the whole unpaid amount as cash immediately and print — no
  /// screen, no change calculation. Fast, but silent.
  quickCash,
}

// App Settings Model
/// Read a per-ticket-type text map back out of stored JSON.
///
/// Tolerant on purpose: this is round-tripped through SharedPreferences and
/// through whatever an older build wrote, so anything that is not a
/// string-to-string map simply reads as "no overrides" rather than throwing on
/// startup and taking the till with it.
Map<String, String> parseTicketTexts(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, String>{};
  raw.forEach((k, v) {
    if (k is String && v is String && v.isNotEmpty) out[k] = v;
  });
  return out;
}

class AppSettings {
  final bool isDarkMode;
  final String language; // 'en', 'ar', 'fr'
  final String loggingLanguage; // Language used for stored activity-log phrases
  final List<String> cashierDefaultPermissions; // Auto-granted to users where type == 'cashier'
  final String defaultOrderType; // 'DINE_IN' or 'TAKE_AWAY'
  final bool showProductImages;
  final String defaultOrderStatus; // 'PENDING', 'ONHOLD', etc.
  /// Kitchen state stamped on each PRODUCT when an order is sent to the kitchen.
  /// The order itself is born [defaultOrderStatus] (COMPLETED / cloud-terminal);
  /// the live kitchen flow (PENDING → PREPARING → COMPLETED) runs on the
  /// products and is what the KDS drives. Default 'PENDING'.
  final String defaultKdsState;
  /// When false, the order-ticket auto-print is skipped on waiter-created
  /// orders even when the source rule allows it. KDS prints still fire.
  /// Default true (current behavior preserved). Common reason to turn
  /// off: the waiter already has a handheld printer / the cashier doesn't
  /// need a paper copy of every waiter order.
  final bool printWaiterOrderTicket;
  /// Master switch for ALL auto-printing triggered by waiter-app actions
  /// (order ticket, KDS, and the payment receipt/store copy on paid/settled
  /// waiter orders). When false, no waiter action produces paper automatically
  /// — regardless of the per-output print rules or [printWaiterOrderTicket].
  /// Explicit reprints via `POST /waiters/orders/<code>/print` still work.
  /// Default true (current behavior preserved).
  final bool printWaiterPaper;

  /// How long the POS waits, after a waiter adds a product to an OPEN order,
  /// for more products before it prints the kitchen ticket. Each further add
  /// restarts the wait, so a run of them lands on one ticket.
  ///
  /// The waiter app has no cart when adding to an existing table: its
  /// add-product screen sends one product and navigates straight back to the
  /// menu, so three items are three separate calls and used to be three
  /// separate tickets. Nothing on the wire says "that was the last one", so
  /// the only way to group them is to wait a moment.
  ///
  /// Trade-off, and the reason it is a setting: the wait delays the kitchen by
  /// exactly this long. 0 disables grouping and prints immediately, which is
  /// the behaviour before this existed.
  ///
  /// It also decides whether a LOOPED round can carry course sections, which is
  /// easy to miss: sections need two or more lines on one ticket, so a run of
  /// single adds sections only while the window swallows the whole run. At 0
  /// every ticket holds one line and a round after the order's first can never
  /// section. Do not set 0 until the waiter tablets batch (`add-products`).
  final int waiterKdsBatchSeconds;

  final String paidOrderDefaultStatus; // Default status for paid orders: 'COMPLETED', 'DELIVERED', etc.
  final CategoryDisplayMode categoryDisplayMode; // How to display categories
  /// How option groups are laid out in the product modification dialog.
  final ComponentGroupDisplayMode componentGroupDisplayMode;
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
  final bool showProceedButton;
  final bool showDailySummaryButton;
  final bool showCashDrawerButton;
  final bool showCancelOrderButton;

  // Button order - list of button keys defining the order
  final List<String> buttonOrder;

  // Horizontal alignment of the action button bar on the main screen
  final ActionButtonAlignment actionButtonAlignment;

  // Sync settings
  final bool autoSyncOnline; // Auto-sync orders when online
  final int bulkSyncSize; // Number of orders to sync at once when offline
  final int autoSyncDurationMinutes; // Auto-sync interval in minutes (default: 5)
  final bool syncUnpaidOrders; // Whether to sync unpaid orders (default: true)
  final bool orderPanelOnRight;

  // Server settings
  final int? serverPort; // HTTP server port (default: 8080)
  final String? serverPassword; // Optional password for server authentication
  final bool autoStartServer; // Auto-start server on app startup

  /// Launch the POS when the machine starts (desktop only).
  ///
  /// On for a till being set up for the first time, off for one that is
  /// merely being updated: an existing till has a routine, and turning its
  /// computer on to find the POS already open is a change nobody asked
  /// for. See `SettingsNotifier` for how the two are told apart.
  final bool openOnStartup;
  /// When false, the `GET /waiters/dashboard` endpoint omits the financial
  /// fields (`expectedCash`, `totalCash`, `cancelledAmount`) from the
  /// response so the waiter app can't display amounts owed/collected.
  /// Defaults to true (current behavior preserved).
  final bool waiterDashboardShowOwed;

  /// Master switch for calling a waiter's phone from the till.
  ///
  /// Off by default: it only does anything once the waiters are running an app
  /// build that listens on `/waiters/events`, and a "call" option that rings
  /// nothing is worse than no option at all. When off, the long-press entries
  /// disappear and [WaiterCallService.call] refuses outright — the switch has
  /// to hold at the service, not only in the widget that happens to be the
  /// entry point today.
  final bool waiterCallEnabled;

  /// Whether a called phone rings until the waiter dismisses it, or chimes
  /// once and goes quiet. Sent to the app in the call payload rather than
  /// configured on each device, so the floor behaves one way and the owner
  /// changes it in one place.
  final bool waiterCallRingUntilDismissed;

  /// Waiter "view order" shows each line's kitchen state (PENDING / PREPARING /
  /// READY / CANCELED). Off = the fields are OMITTED from the payload, not
  /// defaulted, so the app can't mistake "not told" for "not started".
  final bool waiterShowKitchenStatus;

  /// Push `kitchen-ready` to the order's waiter when the KDS bumps lines.
  final bool waiterNotifyReady;

  /// Push `kitchen-canceled` to the order's waiter when the POS pulls a line or
  /// cancels the order. The waiter's own removals are never echoed back.
  final bool waiterNotifyCanceled;

  /// Push `product-availability` to every waiter when the POS toggles a
  /// product EN RUPTURE (or back).
  final bool waiterNotifyRupture;

  /// Master switch for the client-side SSE listener (real-time push from the
  /// remote server: new-order, order-state-changed, POS commands). Admin-only;
  /// defaults to false so the connection stays off unless explicitly enabled.
  final bool sseEnabled;

  // UI settings
  final bool enableSnackBars; // Enable/disable snack bar notifications globally

  // Customer Display settings
  final bool enableCustomerDisplay; // Enable/disable customer-facing second screen

  /// When on (default), the app silently downloads an available (non-mandatory)
  /// update in the background at login, then shows a subtle "ready — restart"
  /// banner instead of a modal prompt. Off = the legacy "update available"
  /// dialog. Mandatory updates always block regardless of this flag.
  final bool autoUpdate;

  // Order validation rules — admin-configurable gates that block save/pay
  // until the required field is filled. Default OFF preserves legacy behavior.
  final bool requireTableForDineIn;
  final bool requireWaiterForDineIn;
  final bool requireCustomerForDelivery;
  final bool requireDeliveryAddress;

  /// When enabled, the table assignment is cleared as soon as every product
  /// on the order is marked PAID. Default OFF.
  final bool autoClearTableAfterPaying;
  /// Print a cancellation ticket when food the kitchen was already told to
  /// make is pulled off an order, or the whole order is voided.
  ///
  /// ON by default, unlike most things added here, because the failure it
  /// prevents is asymmetric: without it the kitchen keeps cooking a dish
  /// nobody will pay for and nobody tells them, and the only way anyone finds
  /// out is when it reaches the pass. A shop that genuinely does not want the
  /// paper can turn it off; a shop that never thinks about it is better served
  /// by being told.
  ///
  /// Only ever fires for quantities that actually reached a kitchen ticket
  /// (`kdsPrintedQuantity`), so pulling a line before it was sent prints
  /// nothing — which is what stops the pass learning to ignore these.
  final bool printKitchenCancellations;

  /// Courses (entrée / plat / dessert) on order lines, and the sections they
  /// produce on the kitchen ticket.
  ///
  /// OFF by default and admin-only to change: most shops do not work in
  /// courses, and for them an extra control on every order line would be
  /// clutter. Switched on, the cashier may tag lines — and the kitchen ticket
  /// only splits when the lines it is printing actually carry more than one
  /// course, so a drinks-only round still prints as it always did.
  final bool coursesEnabled;

  /// Require an admin (or a holder of `pos:sessions:close:variance`) to sign
  /// off a session close that does not balance — a cash variance, unpaid
  /// orders still open, or both.
  ///
  /// OFF by default, which is the behaviour every existing till already has:
  /// the cashier closes, and the shortfall and the open tables are simply
  /// reported on the X. Turning it on makes that moment a supervised one
  /// instead: the same discrepancy still prints, but somebody with authority
  /// has to be standing there.
  ///
  /// Deliberately one switch covering both conditions rather than two. They
  /// are the same question — "is this till short?" — asked of the drawer and
  /// of the floor, and a shop that wants one signed off almost always wants
  /// the other.
  final bool requireAdminToCloseUnbalanced;




  /// Remembered ticks for the report documents offered on session close and
  /// in the Z dialog. Same rule as the older extras beside them: a shop that
  /// always wants a document ticks it once.
  ///
  /// [printProductsByCategoryOnClose] only does anything alongside the
  /// products summary — it chooses its shape, not whether it prints.
  final bool printProductsByCategoryOnClose;
  final bool printUnpaidOnClose;
  final bool printSalesByWaiterOnClose;
  final bool printSalesByCashierOnClose;

  /// Remembered state of the "Print X report" checkbox on the session-close
  /// confirmation dialog. Persisted so the cashier's last choice sticks.
  final bool printXOnSessionClose;
  /// Remembered "Print orders list" checkbox on the session-close dialog.
  final bool printOrdersListOnClose;

  /// Remembered tick for the reductions ticket — every order something came
  /// off, printed beside the Z so a manager can see what was given away.
  final bool printDiscountsOnClose;
  /// Remembered "Print products summary" checkbox on the session-close dialog.
  final bool printProductSummaryOnClose;

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

  /// What tapping "Pay" does; the long press does the other. Defaults to the
  /// payment screen — a tap that silently takes the money and prints gives the
  /// cashier nowhere to enter what the customer handed over.
  final PayButtonAction payButtonAction;

  /// BETA: numeric fields open a small keypad beside them instead of the
  /// full-width on-screen keyboard along the bottom.
  ///
  /// Off by default and deliberately narrow: it only changes fields that ask
  /// for a number, and only when the keypad has somewhere to open. Everything
  /// else — text fields, the keyboard setting itself — behaves exactly as
  /// before, so turning this on can be undone by turning it off.
  final bool numericKeypadBeta;

  /// Whether the incoming external-order queue renders as a card grid rather
  /// than a list. A busy delivery counter wants the grid's scannability; a
  /// small screen wants the list's density, so it is the terminal's choice.
  final bool externalQueueGridView;

  /// Note denominations offered as one-tap shortcuts on the payment pad.
  /// Stored biggest-first for display; the pad also always offers the exact
  /// amount and the next round-ups.
  final List<int> quickCashAmounts;

  /// One-tap order notes the shop wrote itself. Empty falls back to the
  /// built-in translated set, so a till that has never been customised keeps
  /// the notes it always had — and clearing the field is how you get them
  /// back.
  final List<String> notePresets;

  /// One-tap delivery fee amounts. Empty falls back to the built-in set, same
  /// bargain as [quickCashAmounts].
  final List<double> deliveryFeePresets;

  /// Ticket-division panel visibility on the payment screen.
  /// `false` (default) = on demand: a single unsplit ticket hides the grid
  /// and gives the whole dialog to the payment pad; the cashier presses
  /// "Split" to reveal it. `true` = the grid is always shown.
  final bool alwaysShowTicketSplit;

  /// Hard ceiling on how many tickets one order can be divided into.
  /// Guards against a mis-tap turning a 20-item order into 20 tickets.
  final int maxSplitTickets;

  // Agenda settings
  final int agendaTimeStep; // Time grid interval in minutes: 60, 30, or 15

  // On-screen keyboard settings
  final bool showOnscreenKeyboard; // Show/hide the on-screen soft keyboard
  final double onscreenKeyboardWidthFraction; // Width as fraction of screen width (0.25–1.0)

  // Product card size: 1=small, 2=medium, 3=large
  final int productCardSize;

  /// Whether the product grid opens with a tile that goes back to the
  /// categories.
  ///
  /// Only means anything in [CategoryDisplayMode.fullPage], where choosing a
  /// category replaces the category grid with the products and there is
  /// otherwise nowhere obvious to go back to. Off by default: it costs a tile,
  /// and shops that leave the category bar on screen never need it.
  final bool showBackTileInProductGrid;

  /// Whether a product card's name and price sit **on** its image rather than
  /// in a band beneath it.
  ///
  /// Overlaying buys height: the label no longer needs a row of its own, so the
  /// same grid fits more rows on the same screen. It costs a little legibility
  /// on busy photographs, which the blurred panel behind the text is there to
  /// buy back. Off by default — the stacked layout is what shops have now, and
  /// a silent relayout of the whole till on upgrade is not a kindness.
  final bool productLabelOverlay;

  // Ticket printing settings
  final String ticketHeader; // Header text to print at top of ticket
  final String ticketFooter; // Footer text to print at bottom of ticket

  /// Per-ticket-type overrides for the header and footer, keyed by ticket type
  /// ('order', 'customer', 'store').
  ///
  /// One shared header across every document is wrong the moment the texts
  /// have different jobs: the customer copy wants a thank-you and a returns
  /// policy, the store copy wants a signature line, and the order ticket wants
  /// neither. An absent or blank entry falls back to [ticketHeader] /
  /// [ticketFooter], so a till that only ever set the shared text keeps
  /// printing exactly what it printed yesterday.
  final Map<String, String> ticketHeaders;
  final Map<String, String> ticketFooters;

  /// Print the reason beside a reduction ("remise commerciale", "geste").
  ///
  /// On by default: a discount with no stated reason is the line an auditor
  /// asks about, and the reason is already captured when the cashier applies
  /// it. Prints nothing when no reason was given, so it costs an
  /// undiscounted — or unexplained — ticket nothing.
  final bool printDiscountReason;

  /// Show the per-session order number (#1, #2…) in the orders and tickets
  /// screens, and let their search match it. Off by default. Printing it is
  /// a per-ticket field switch in the printer settings, not this flag.
  final bool showOrderNumberInLists;

  /// Send the per-session order number to the KDS screens. Off by default.
  final bool showOrderNumberOnKds;

  /// Send the per-session order number to the waiter app. Off by default.
  final bool showOrderNumberOnWaiter;

  /// When the order number goes back to #1: `session` (every cash session,
  /// the default), `z` (every Z) or `manual` (only when an admin resets it).
  final String orderNumberResetMode;

  /// Whether the orders and tickets screens show totals with the delivery
  /// fee added (what the customer paid) or the products total alone. Display
  /// only — no sales/Z figure reads it. On by default: that is what the
  /// orders list already showed.
  final bool totalsIncludeDeliveryFee;

  // Favorites & sort
  final bool showFavoritesCategory; // Show a ★ Favorites virtual category chip
  final bool sortByLastUsed; // Sort product grid by last-used recency (RAM only)

  // Settings lock
  /// When true, opening Settings asks for [settingsPin] first.
  final bool settingsLockEnabled;

  /// The 4-digit code that opens Settings. An empty string means "never set",
  /// which leaves the lock inert whatever [settingsLockEnabled] says — a lock
  /// with no key would shut the page for everyone, admin included.
  final String settingsPin;

  // Input
  /// Whether the product search takes the caret every time the main screen
  /// comes back into view. Off leaves the on-screen keyboard down until the
  /// cashier actually taps a field.
  final bool autoFocusProductSearch;

  const AppSettings({
    this.isDarkMode = false,
    this.language = 'en',
    this.loggingLanguage = 'en',
    this.cashierDefaultPermissions = const [],
    this.defaultOrderType = 'DINE_IN',
    this.showProductImages = true,
    this.defaultOrderStatus = 'COMPLETED',
    this.defaultKdsState = 'PENDING',
    this.printWaiterOrderTicket = true,
    this.printWaiterPaper = true,
    this.waiterKdsBatchSeconds = 12,
    this.paidOrderDefaultStatus = 'COMPLETED',
    this.categoryDisplayMode = CategoryDisplayMode.topBar,
    this.componentGroupDisplayMode = ComponentGroupDisplayMode.list,
    this.currency = 'DH',
    this.showTableButton = true,
    this.showCustomerButton = false,
    this.showCommercialButton = false,
    this.showWaiterButton = false,
    this.showCouponButton = false,
    this.showDiscountButton = false,
    this.showPrintButton = false,
    this.showPersonsButton = false,
    this.showOrderTypeButton = true,
    this.showConfirmOrderButton = false,
    this.showPayButton = true,
    this.showProceedButton = true,
    this.showDailySummaryButton = false,
    this.showCashDrawerButton = false,
    this.showCancelOrderButton = false,
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
      'cashDrawer',
      'cancelOrder',
      'pay',
      'proceed',
    ],
    this.actionButtonAlignment = ActionButtonAlignment.left,
    this.autoSyncOnline = true,
    this.bulkSyncSize = 50,
    this.autoSyncDurationMinutes = 5,
    this.syncUnpaidOrders = true,
    this.orderPanelOnRight = false,
    this.serverPort = 8080,
    this.serverPassword,
    this.autoStartServer = true,
    this.openOnStartup = true,
    this.waiterDashboardShowOwed = true,
    this.waiterCallEnabled = false,
    this.waiterCallRingUntilDismissed = true,
    this.waiterShowKitchenStatus = false,
    this.waiterNotifyReady = false,
    this.waiterNotifyCanceled = false,
    this.waiterNotifyRupture = false,
    this.sseEnabled = false,
    this.enableSnackBars = false,
    this.enableCustomerDisplay = false,
    this.autoUpdate = true,
    this.requireTableForDineIn = false,
    this.requireWaiterForDineIn = false,
    this.requireCustomerForDelivery = false,
    this.requireDeliveryAddress = false,
    this.autoClearTableAfterPaying = false,
    this.coursesEnabled = false,
    this.printKitchenCancellations = true,
    this.printProductsByCategoryOnClose = true,
    this.printUnpaidOnClose = false,
    this.printSalesByWaiterOnClose = false,
    this.printSalesByCashierOnClose = false,
    this.requireAdminToCloseUnbalanced = false,
    this.printXOnSessionClose = true,
    this.printOrdersListOnClose = false,
    this.printDiscountsOnClose = false,
    this.printProductSummaryOnClose = false,
    this.defaultPaymentMethod = 'CASH',
    this.showTipDialog = false,
    this.showTipButton = false,
    this.payButtonAction = PayButtonAction.paymentScreen,
    this.externalQueueGridView = false,
    this.numericKeypadBeta = false,
    this.quickCashAmounts = const [200, 100, 50, 20],
    this.notePresets = const [],
    this.deliveryFeePresets = const [10, 15, 20, 30],
    this.alwaysShowTicketSplit = false,
    this.maxSplitTickets = 10,
    this.agendaTimeStep = 60,
    this.showOnscreenKeyboard = true,
    this.onscreenKeyboardWidthFraction = 0.5,
    this.productCardSize = 2,
    this.productLabelOverlay = false,
    this.showBackTileInProductGrid = false,
    this.ticketHeader = '',
    this.ticketFooter = '',
    this.ticketHeaders = const {},
    this.ticketFooters = const {},
    this.printDiscountReason = true,
    this.showOrderNumberInLists = false,
    this.showOrderNumberOnKds = false,
    this.showOrderNumberOnWaiter = false,
    this.orderNumberResetMode = 'session',
    this.totalsIncludeDeliveryFee = true,
    this.showFavoritesCategory = false,
    this.sortByLastUsed = false,
    this.settingsLockEnabled = false,
    this.settingsPin = '',
    this.autoFocusProductSearch = true,
  });

  AppSettings copyWith({
    bool? isDarkMode,
    String? language,
    String? loggingLanguage,
    List<String>? cashierDefaultPermissions,
    String? defaultOrderType,
    bool? showProductImages,
    String? defaultOrderStatus,
    String? defaultKdsState,
    bool? printWaiterOrderTicket,
    bool? printWaiterPaper,
    int? waiterKdsBatchSeconds,
    String? paidOrderDefaultStatus,
    CategoryDisplayMode? categoryDisplayMode,
    ComponentGroupDisplayMode? componentGroupDisplayMode,
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
    bool? showProceedButton,
    bool? showDailySummaryButton,
    bool? showCashDrawerButton,
    bool? showCancelOrderButton,
    List<String>? buttonOrder,
    ActionButtonAlignment? actionButtonAlignment,
    bool? autoSyncOnline,
    int? bulkSyncSize,
    int? autoSyncDurationMinutes,
    bool? syncUnpaidOrders,
    bool? orderPanelOnRight,
    int? serverPort,
    String? serverPassword,
    bool? autoStartServer,
    bool? openOnStartup,
    bool? waiterDashboardShowOwed,
    bool? waiterCallEnabled,
    bool? waiterCallRingUntilDismissed,
    bool? waiterShowKitchenStatus,
    bool? waiterNotifyReady,
    bool? waiterNotifyCanceled,
    bool? waiterNotifyRupture,
    bool? sseEnabled,
    bool? enableSnackBars,
    bool? enableCustomerDisplay,
    bool? autoUpdate,
    bool? requireTableForDineIn,
    bool? requireWaiterForDineIn,
    bool? requireCustomerForDelivery,
    bool? requireDeliveryAddress,
    bool? autoClearTableAfterPaying,
    bool? coursesEnabled,
    bool? printKitchenCancellations,
    bool? printProductsByCategoryOnClose,
    bool? printUnpaidOnClose,
    bool? printSalesByWaiterOnClose,
    bool? printSalesByCashierOnClose,
    bool? requireAdminToCloseUnbalanced,
    bool? printXOnSessionClose,
    bool? printOrdersListOnClose,
    bool? printDiscountsOnClose,
    bool? printProductSummaryOnClose,
    String? defaultPaymentMethod,
    bool? showTipDialog,
    bool? showTipButton,
    PayButtonAction? payButtonAction,
    bool? externalQueueGridView,
    bool? numericKeypadBeta,
    List<int>? quickCashAmounts,
    List<String>? notePresets,
    List<double>? deliveryFeePresets,
    bool? alwaysShowTicketSplit,
    int? maxSplitTickets,
    int? agendaTimeStep,
    bool? showOnscreenKeyboard,
    double? onscreenKeyboardWidthFraction,
    int? productCardSize,
    bool? productLabelOverlay,
    bool? showBackTileInProductGrid,
    String? ticketHeader,
    String? ticketFooter,
    Map<String, String>? ticketHeaders,
    Map<String, String>? ticketFooters,
    bool? printDiscountReason,
    bool? showOrderNumberInLists,
    bool? showOrderNumberOnKds,
    bool? showOrderNumberOnWaiter,
    String? orderNumberResetMode,
    bool? totalsIncludeDeliveryFee,
    bool? showFavoritesCategory,
    bool? sortByLastUsed,
    bool? settingsLockEnabled,
    String? settingsPin,
    bool? autoFocusProductSearch,
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
      defaultKdsState: defaultKdsState ?? this.defaultKdsState,
      printWaiterOrderTicket:
          printWaiterOrderTicket ?? this.printWaiterOrderTicket,
      printWaiterPaper: printWaiterPaper ?? this.printWaiterPaper,
      waiterKdsBatchSeconds:
          waiterKdsBatchSeconds ?? this.waiterKdsBatchSeconds,
      paidOrderDefaultStatus: paidOrderDefaultStatus ?? this.paidOrderDefaultStatus,
      categoryDisplayMode: categoryDisplayMode ?? this.categoryDisplayMode,
      componentGroupDisplayMode:
          componentGroupDisplayMode ?? this.componentGroupDisplayMode,
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
      showProceedButton: showProceedButton ?? this.showProceedButton,
      showDailySummaryButton: showDailySummaryButton ?? this.showDailySummaryButton,
      showCashDrawerButton: showCashDrawerButton ?? this.showCashDrawerButton,
      showCancelOrderButton:
          showCancelOrderButton ?? this.showCancelOrderButton,
      buttonOrder: buttonOrder ?? this.buttonOrder,
      actionButtonAlignment:
          actionButtonAlignment ?? this.actionButtonAlignment,
      autoSyncOnline: autoSyncOnline ?? this.autoSyncOnline,
      bulkSyncSize: bulkSyncSize ?? this.bulkSyncSize,
      autoSyncDurationMinutes: autoSyncDurationMinutes ?? this.autoSyncDurationMinutes,
      syncUnpaidOrders: syncUnpaidOrders ?? this.syncUnpaidOrders,
      orderPanelOnRight: orderPanelOnRight ?? this.orderPanelOnRight,
      serverPort: serverPort ?? this.serverPort,
      serverPassword: serverPassword ?? this.serverPassword,
      autoStartServer: autoStartServer ?? this.autoStartServer,
      openOnStartup: openOnStartup ?? this.openOnStartup,
      waiterDashboardShowOwed:
          waiterDashboardShowOwed ?? this.waiterDashboardShowOwed,
      waiterCallEnabled: waiterCallEnabled ?? this.waiterCallEnabled,
      waiterCallRingUntilDismissed:
          waiterCallRingUntilDismissed ?? this.waiterCallRingUntilDismissed,
      waiterShowKitchenStatus: waiterShowKitchenStatus ?? this.waiterShowKitchenStatus,
      waiterNotifyReady: waiterNotifyReady ?? this.waiterNotifyReady,
      waiterNotifyCanceled: waiterNotifyCanceled ?? this.waiterNotifyCanceled,
      waiterNotifyRupture: waiterNotifyRupture ?? this.waiterNotifyRupture,
      sseEnabled: sseEnabled ?? this.sseEnabled,
      enableSnackBars: enableSnackBars ?? this.enableSnackBars,
      enableCustomerDisplay: enableCustomerDisplay ?? this.enableCustomerDisplay,
      autoUpdate: autoUpdate ?? this.autoUpdate,
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
      coursesEnabled: coursesEnabled ?? this.coursesEnabled,
      printKitchenCancellations:
          printKitchenCancellations ?? this.printKitchenCancellations,
      printProductsByCategoryOnClose: printProductsByCategoryOnClose ??
          this.printProductsByCategoryOnClose,
      printUnpaidOnClose: printUnpaidOnClose ?? this.printUnpaidOnClose,
      printSalesByWaiterOnClose:
          printSalesByWaiterOnClose ?? this.printSalesByWaiterOnClose,
      printSalesByCashierOnClose:
          printSalesByCashierOnClose ?? this.printSalesByCashierOnClose,
      requireAdminToCloseUnbalanced:
          requireAdminToCloseUnbalanced ?? this.requireAdminToCloseUnbalanced,
      printXOnSessionClose: printXOnSessionClose ?? this.printXOnSessionClose,
      printOrdersListOnClose:
          printOrdersListOnClose ?? this.printOrdersListOnClose,
      printDiscountsOnClose:
          printDiscountsOnClose ?? this.printDiscountsOnClose,
      printProductSummaryOnClose:
          printProductSummaryOnClose ?? this.printProductSummaryOnClose,
      defaultPaymentMethod: defaultPaymentMethod ?? this.defaultPaymentMethod,
      showTipDialog: showTipDialog ?? this.showTipDialog,
      showTipButton: showTipButton ?? this.showTipButton,
      payButtonAction: payButtonAction ?? this.payButtonAction,
      externalQueueGridView:
          externalQueueGridView ?? this.externalQueueGridView,
      numericKeypadBeta: numericKeypadBeta ?? this.numericKeypadBeta,
      quickCashAmounts: quickCashAmounts ?? this.quickCashAmounts,
      notePresets: notePresets ?? this.notePresets,
      deliveryFeePresets: deliveryFeePresets ?? this.deliveryFeePresets,
      alwaysShowTicketSplit: alwaysShowTicketSplit ?? this.alwaysShowTicketSplit,
      maxSplitTickets: maxSplitTickets ?? this.maxSplitTickets,
      agendaTimeStep: agendaTimeStep ?? this.agendaTimeStep,
      showOnscreenKeyboard: showOnscreenKeyboard ?? this.showOnscreenKeyboard,
      onscreenKeyboardWidthFraction: onscreenKeyboardWidthFraction ?? this.onscreenKeyboardWidthFraction,
      productCardSize: productCardSize ?? this.productCardSize,
      productLabelOverlay: productLabelOverlay ?? this.productLabelOverlay,
      showBackTileInProductGrid:
          showBackTileInProductGrid ?? this.showBackTileInProductGrid,
      ticketHeader: ticketHeader ?? this.ticketHeader,
      ticketFooter: ticketFooter ?? this.ticketFooter,
      ticketHeaders: ticketHeaders ?? this.ticketHeaders,
      ticketFooters: ticketFooters ?? this.ticketFooters,
      printDiscountReason: printDiscountReason ?? this.printDiscountReason,
      showOrderNumberInLists:
          showOrderNumberInLists ?? this.showOrderNumberInLists,
      showOrderNumberOnKds: showOrderNumberOnKds ?? this.showOrderNumberOnKds,
      showOrderNumberOnWaiter:
          showOrderNumberOnWaiter ?? this.showOrderNumberOnWaiter,
      orderNumberResetMode: orderNumberResetMode ?? this.orderNumberResetMode,
      totalsIncludeDeliveryFee:
          totalsIncludeDeliveryFee ?? this.totalsIncludeDeliveryFee,
      showFavoritesCategory: showFavoritesCategory ?? this.showFavoritesCategory,
      sortByLastUsed: sortByLastUsed ?? this.sortByLastUsed,
      settingsLockEnabled: settingsLockEnabled ?? this.settingsLockEnabled,
      settingsPin: settingsPin ?? this.settingsPin,
      autoFocusProductSearch:
          autoFocusProductSearch ?? this.autoFocusProductSearch,
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
      'defaultKdsState': defaultKdsState,
      'printWaiterOrderTicket': printWaiterOrderTicket,
      'printWaiterPaper': printWaiterPaper,
      'waiterKdsBatchSeconds': waiterKdsBatchSeconds,
      'paidOrderDefaultStatus': paidOrderDefaultStatus,
      'categoryDisplayMode': categoryDisplayMode.name,
      'componentGroupDisplayMode': componentGroupDisplayMode.name,
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
      'showProceedButton': showProceedButton,
      'showDailySummaryButton': showDailySummaryButton,
      'showCashDrawerButton': showCashDrawerButton,
      'showCancelOrderButton': showCancelOrderButton,
      'buttonOrder': buttonOrder,
      'actionButtonAlignment': actionButtonAlignment.name,
      'autoSyncOnline': autoSyncOnline,
      'bulkSyncSize': bulkSyncSize,
      'autoSyncDurationMinutes': autoSyncDurationMinutes,
      'syncUnpaidOrders': syncUnpaidOrders,
      'orderPanelOnRight': orderPanelOnRight,
      'serverPort': serverPort,
      'serverPassword': serverPassword,
      'autoStartServer': autoStartServer,
      'openOnStartup': openOnStartup,
      'waiterDashboardShowOwed': waiterDashboardShowOwed,
      'waiterCallEnabled': waiterCallEnabled,
      'waiterCallRingUntilDismissed': waiterCallRingUntilDismissed,
      'waiterShowKitchenStatus': waiterShowKitchenStatus,
      'waiterNotifyReady': waiterNotifyReady,
      'waiterNotifyCanceled': waiterNotifyCanceled,
      'waiterNotifyRupture': waiterNotifyRupture,
      'sseEnabled': sseEnabled,
      'enableSnackBars': enableSnackBars,
      'enableCustomerDisplay': enableCustomerDisplay,
      'autoUpdate': autoUpdate,
      'requireTableForDineIn': requireTableForDineIn,
      'requireWaiterForDineIn': requireWaiterForDineIn,
      'requireCustomerForDelivery': requireCustomerForDelivery,
      'requireDeliveryAddress': requireDeliveryAddress,
      'autoClearTableAfterPaying': autoClearTableAfterPaying,
      'coursesEnabled': coursesEnabled,
      'printKitchenCancellations': printKitchenCancellations,
      'printProductsByCategoryOnClose': printProductsByCategoryOnClose,
      'printUnpaidOnClose': printUnpaidOnClose,
      'printSalesByWaiterOnClose': printSalesByWaiterOnClose,
      'printSalesByCashierOnClose': printSalesByCashierOnClose,
      'requireAdminToCloseUnbalanced': requireAdminToCloseUnbalanced,
      'printXOnSessionClose': printXOnSessionClose,
      'printOrdersListOnClose': printOrdersListOnClose,
      'printDiscountsOnClose': printDiscountsOnClose,
      'printProductSummaryOnClose': printProductSummaryOnClose,
      'defaultPaymentMethod': defaultPaymentMethod,
      'showTipDialog': showTipDialog,
      'showTipButton': showTipButton,
      'payButtonAction': payButtonAction.name,
      'externalQueueGridView': externalQueueGridView,
      'numericKeypadBeta': numericKeypadBeta,
      'quickCashAmounts': quickCashAmounts,
      'notePresets': notePresets,
      'deliveryFeePresets': deliveryFeePresets,
      'alwaysShowTicketSplit': alwaysShowTicketSplit,
      'maxSplitTickets': maxSplitTickets,
      'agendaTimeStep': agendaTimeStep,
      'showOnscreenKeyboard': showOnscreenKeyboard,
      'onscreenKeyboardWidthFraction': onscreenKeyboardWidthFraction,
      'productCardSize': productCardSize,
      'productLabelOverlay': productLabelOverlay,
      'showBackTileInProductGrid': showBackTileInProductGrid,
      'ticketHeader': ticketHeader,
      'ticketFooter': ticketFooter,
      'ticketHeaders': ticketHeaders,
      'ticketFooters': ticketFooters,
      'printDiscountReason': printDiscountReason,
      'showOrderNumberInLists': showOrderNumberInLists,
      'showOrderNumberOnKds': showOrderNumberOnKds,
      'showOrderNumberOnWaiter': showOrderNumberOnWaiter,
      'orderNumberResetMode': orderNumberResetMode,
      'totalsIncludeDeliveryFee': totalsIncludeDeliveryFee,
      'showFavoritesCategory': showFavoritesCategory,
      'sortByLastUsed': sortByLastUsed,
      'settingsLockEnabled': settingsLockEnabled,
      'settingsPin': settingsPin,
      'autoFocusProductSearch': autoFocusProductSearch,
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
      defaultOrderStatus: json['defaultOrderStatus'] as String? ?? 'COMPLETED',
      defaultKdsState: json['defaultKdsState'] as String? ?? 'PENDING',
      printWaiterOrderTicket: json['printWaiterOrderTicket'] as bool? ?? true,
      printWaiterPaper: json['printWaiterPaper'] as bool? ?? true,
      waiterKdsBatchSeconds:
          (json['waiterKdsBatchSeconds'] as num?)?.toInt() ?? 12,
      paidOrderDefaultStatus: json['paidOrderDefaultStatus'] as String? ?? 'COMPLETED',
      categoryDisplayMode: CategoryDisplayMode.values.firstWhere(
        (e) => e.name == json['categoryDisplayMode'],
        orElse: () => CategoryDisplayMode.topBar,
      ),
      componentGroupDisplayMode: ComponentGroupDisplayMode.values.firstWhere(
        (e) => e.name == json['componentGroupDisplayMode'],
        orElse: () => ComponentGroupDisplayMode.list,
      ),
      currency: json['currency'] as String? ?? '\$',
      showTableButton: json['showTableButton'] as bool? ?? true,
      showCustomerButton: json['showCustomerButton'] as bool? ?? false,
      showCommercialButton: json['showCommercialButton'] as bool? ?? false,
      showWaiterButton: json['showWaiterButton'] as bool? ?? false,
      showCouponButton: json['showCouponButton'] as bool? ?? false,
      showDiscountButton: json['showDiscountButton'] as bool? ?? false,
      showPrintButton: json['showPrintButton'] as bool? ?? false,
      showPersonsButton: json['showPersonsButton'] as bool? ?? false,
      showOrderTypeButton: json['showOrderTypeButton'] as bool? ?? true,
      showConfirmOrderButton: json['showConfirmOrderButton'] as bool? ?? false,
      showPayButton: json['showPayButton'] as bool? ?? true,
      showProceedButton: json['showProceedButton'] as bool? ?? true,
      showDailySummaryButton: json['showDailySummaryButton'] as bool? ?? false,
      showCashDrawerButton: json['showCashDrawerButton'] as bool? ?? false,
      showCancelOrderButton: json['showCancelOrderButton'] as bool? ?? false,
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
      'cashDrawer',
      'cancelOrder',
        'pay',
        'proceed',
      ],
      actionButtonAlignment: ActionButtonAlignment.values.firstWhere(
        (e) => e.name == json['actionButtonAlignment'],
        orElse: () => ActionButtonAlignment.left,
      ),
      autoSyncOnline: json['autoSyncOnline'] as bool? ?? true,
      bulkSyncSize: json['bulkSyncSize'] as int? ?? 50,
      autoSyncDurationMinutes: json['autoSyncDurationMinutes'] as int? ?? 5,
      syncUnpaidOrders: json['syncUnpaidOrders'] as bool? ?? true,
      orderPanelOnRight: json['orderPanelOnRight'] as bool? ?? false,
      serverPort: json['serverPort'] as int?,
      serverPassword: json['serverPassword'] as String?,
      autoStartServer: json['autoStartServer'] as bool? ?? true,
      openOnStartup: json['openOnStartup'] as bool? ?? true,
      waiterDashboardShowOwed:
          json['waiterDashboardShowOwed'] as bool? ?? true,
      waiterCallEnabled: json['waiterCallEnabled'] as bool? ?? false,
      waiterCallRingUntilDismissed:
          json['waiterCallRingUntilDismissed'] as bool? ?? true,
      waiterShowKitchenStatus: json['waiterShowKitchenStatus'] as bool? ?? false,
      waiterNotifyReady: json['waiterNotifyReady'] as bool? ?? false,
      waiterNotifyCanceled: json['waiterNotifyCanceled'] as bool? ?? false,
      waiterNotifyRupture: json['waiterNotifyRupture'] as bool? ?? false,
      sseEnabled: json['sseEnabled'] as bool? ?? false,
      enableSnackBars: json['enableSnackBars'] as bool? ?? true,
      enableCustomerDisplay: json['enableCustomerDisplay'] as bool? ?? false,
      autoUpdate: json['autoUpdate'] as bool? ?? true,
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
      coursesEnabled: json['coursesEnabled'] as bool? ?? false,
      printKitchenCancellations:
          json['printKitchenCancellations'] as bool? ?? true,
      printProductsByCategoryOnClose:
          json['printProductsByCategoryOnClose'] as bool? ?? true,
      printUnpaidOnClose: json['printUnpaidOnClose'] as bool? ?? false,
      printSalesByWaiterOnClose:
          json['printSalesByWaiterOnClose'] as bool? ?? false,
      printSalesByCashierOnClose:
          json['printSalesByCashierOnClose'] as bool? ?? false,
      requireAdminToCloseUnbalanced:
          json['requireAdminToCloseUnbalanced'] as bool? ?? false,
      printXOnSessionClose: json['printXOnSessionClose'] as bool? ?? true,
      printOrdersListOnClose:
          json['printOrdersListOnClose'] as bool? ?? false,
      printDiscountsOnClose:
          json['printDiscountsOnClose'] as bool? ?? false,
      printProductSummaryOnClose:
          json['printProductSummaryOnClose'] as bool? ?? false,
      defaultPaymentMethod: json['defaultPaymentMethod'] as String? ?? 'CASH',
      showTipDialog: json['showTipDialog'] as bool? ?? false,
      showTipButton: json['showTipButton'] as bool? ?? false,
      payButtonAction: PayButtonAction.values.firstWhere(
        (e) => e.name == json['payButtonAction'],
        orElse: () => PayButtonAction.paymentScreen,
      ),
      externalQueueGridView:
          json['externalQueueGridView'] as bool? ?? false,
      numericKeypadBeta: json['numericKeypadBeta'] as bool? ?? false,
      notePresets: (json['notePresets'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
      deliveryFeePresets: (json['deliveryFeePresets'] as List?)
              ?.map((e) => (e as num).toDouble())
              .where((e) => e >= 0)
              .toList() ??
          const [10, 15, 20, 30],
      quickCashAmounts: (json['quickCashAmounts'] as List?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [200, 100, 50, 20],
      alwaysShowTicketSplit: json['alwaysShowTicketSplit'] as bool? ?? false,
      maxSplitTickets: (json['maxSplitTickets'] as num?)?.toInt() ?? 10,
      agendaTimeStep: json['agendaTimeStep'] as int? ?? 60,
      showOnscreenKeyboard: json['showOnscreenKeyboard'] as bool? ?? true,
      onscreenKeyboardWidthFraction: (json['onscreenKeyboardWidthFraction'] as num?)?.toDouble() ?? 0.5,
      productCardSize: json['productCardSize'] as int? ?? 2,
      productLabelOverlay: json['productLabelOverlay'] as bool? ?? false,
      showBackTileInProductGrid:
          json['showBackTileInProductGrid'] as bool? ?? false,
      ticketHeader: json['ticketHeader'] as String? ?? '',
      ticketFooter: json['ticketFooter'] as String? ?? '',
      ticketHeaders: parseTicketTexts(json['ticketHeaders']),
      ticketFooters: parseTicketTexts(json['ticketFooters']),
      printDiscountReason: json['printDiscountReason'] as bool? ?? true,
      showOrderNumberInLists:
          json['showOrderNumberInLists'] as bool? ?? false,
      showOrderNumberOnKds: json['showOrderNumberOnKds'] as bool? ?? false,
      showOrderNumberOnWaiter:
          json['showOrderNumberOnWaiter'] as bool? ?? false,
      orderNumberResetMode:
          json['orderNumberResetMode'] as String? ?? 'session',
      totalsIncludeDeliveryFee:
          json['totalsIncludeDeliveryFee'] as bool? ?? true,
      showFavoritesCategory: json['showFavoritesCategory'] as bool? ?? false,
      sortByLastUsed: json['sortByLastUsed'] as bool? ?? false,
      settingsLockEnabled: json['settingsLockEnabled'] as bool? ?? false,
      settingsPin: json['settingsPin'] as String? ?? '',
      autoFocusProductSearch:
          json['autoFocusProductSearch'] as bool? ?? true,
    );
  }

  @override
  String toString() {
    return 'AppSettings(isDarkMode: $isDarkMode, defaultOrderType: $defaultOrderType, showProductImages: $showProductImages, defaultOrderStatus: $defaultOrderStatus, categoryDisplayMode: $categoryDisplayMode, currency: $currency)';
  }
}

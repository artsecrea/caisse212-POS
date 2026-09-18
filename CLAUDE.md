l# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Project Overview

**caisse212** — Flutter POS (Point-of-Sale) desktop/mobile app. Targets Linux, Windows, macOS, Android, iOS. App runs as both a client (syncs to a central server via REST) and an embedded HTTP server (serves KDS/kiosk devices over LAN via Shelf). Supports multi-language (AR/FR/EN), thermal printing, barcode scanning, table management, cash sessions, and offline-first operation with queued sync.

Local sibling packages:
- `../cmdecrea` — custom commands/utilities package
- `../loggecrea` — custom structured logger (`Logger.instance`)

---

# Tech Stack & Core Libraries

| Layer | Library | Version |
|---|---|---|
| Framework | Flutter | SDK ^3.9.2 |
| State | flutter_riverpod | ^2.5.1 |
| State codegen | riverpod_annotation + riverpod_generator | ^2.3.5 / ^2.3.11 |
| Database ORM | drift + sqlite3_flutter_libs | ^2.20.3 / ^0.5.24 |
| DB codegen | drift_dev | ^2.20.3 |
| HTTP client | dio | ^5.4.1 |
| HTTP server | shelf + shelf_router | ^1.4.1 / ^1.1.4 |
| LAN discovery | bonsoir | ^5.0.0 |
| Connectivity | connectivity_plus | ^6.1.4 |
| Localization | flutter_localizations + intl | ^0.20.2 |
| Printing | flutter_thermal_printer + esc_pos_utils_plus | ^2.0.0 / ^2.0.4 |
| Forms | flutter_form_builder + form_builder_validators | ^10.0.1 / ^11.2.0 |
| Auth | bcrypt | ^1.2.0 |
| Desktop update | desktop_updater | ^1.4.0 |
| Window mgmt | window_manager | ^0.4.3 |
| Audio | audioplayers | ^6.5.1 |
| JSON codegen | json_serializable + json_annotation | ^6.7.1 / ^4.8.1 |
| UI extras | data_table_2, getwidget, flutter_svg, cached_network_image | latest |
| Image | image | ^4.7.2 (ESC/POS bitmap printing) |
| On-screen KB | flutter_onscreen_keyboard | ^0.4.1+1 |
| Misc | shared_preferences, uuid, path_provider, path | latest |

---

# Architecture Map

```
lib/
├── core/
│   ├── enums.dart              # App-wide enums (OrderStatus, OrderType, TableState, TransactionType, …)
│   └── theme/app_theme.dart    # Material 3 light/dark themes
│
├── data/
│   └── database/
│       ├── app_database.dart   # @DriftDatabase root — registers all tables
│       ├── app_database.g.dart # Generated — DO NOT edit
│       └── tables/             # One file per Drift table (snake_case filenames)
│                               # Tables: orders, products, categories, users, waiters,
│                               # payments, tickets, transactions, cash_sessions, areas,
│                               # area_tables, kds, kiosks, stations, components,
│                               # component_groups, product_components, product_variants,
│                               # order_products, order_product_components, customers,
│                               # commercials, notes, pending_sync_operations, logs
│
├── domain/
│   └── models/                 # Pure Dart models (NOT Drift-generated)
│       ├── order_models.dart   # CurrentOrder, OrderItem, cart state
│       ├── socket_models.dart  # WebSocket message payloads
│       ├── discovery_models.dart # LAN discovery service info
│       ├── kds-models.dart     # KDS screen data structures
│       ├── order_events.dart   # Order lifecycle events
│       ├── app_settings.dart   # Typed settings model
│       ├── external_order_models.dart # ExternalQueueItem/OrderItem/Component (DealUp/WhatsApp)
│       ├── coupon_model.dart
│       └── scale_config.dart
│
├── presentation/
│   ├── login_screen/           # Local user auth
│   ├── tenant_login_screen/    # Multi-tenant server selection (first boot)
│   ├── main_screen/            # POS main interface (order entry, product grid)
│   ├── paymen_screen/          # Payment flow
│   ├── session_screen/         # Cash session open/close
│   ├── order_confirmation/     # Post-payment confirmation
│   ├── profile/                # User profile
│   ├── settings/settings_screen.dart  # App settings UI (ACTIVE — used by top_bar.dart)
│   │   # settings_screen_backup.dart / settings_screen_new.dart are dead files
│   │   # settings_page/ directory is also unused — do not edit those files
│   └── widgets/                # Management screens and reusable dialogs
│       # OrdersManagement, UsersManagement, DevicesManagement,
│       # SessionsManagement, TicketsManagement, PrintersManagement,
│       # AgendaScreen, DashboardScreen, NotesScreen
│       # ExternalOrdersTab — second tab in OrdersManagementScreen (DealUp/WhatsApp)
│
├── providers/                  # ALL Riverpod providers
│   ├── database_providers.dart # Core: DB, ApiService, DataSync, Session, SyncJob,
│   │                           # PrintingService, BarcodeScanner + BarcodeScanMode enum
│   ├── order_provider.dart     # OrderNotifier + OrderRepository
│   ├── network_provider.dart   # Connectivity, online-status, syncJobServiceWithNetworkProvider
│   ├── settings_provider.dart  # Language, dark mode, server port, onscreen keyboard, etc.
│   │                           # Also exposes: showOnscreenKeyboardProvider, onscreenKeyboardWidthFractionProvider
│   ├── server_provider.dart    # ServerService lifecycle
│   ├── socket_order_providers.dart # Real-time order push via SocketService
│   ├── sync_manager_provider.dart  # Orchestrates sync on connectivity change
│   ├── user_provider.dart      # Logged-in user state
│   ├── device_providers.dart   # KDS/kiosk device state
│   ├── ticket_provider.dart    # Ticket state
│   ├── stat_provider.dart      # Sales stats / dashboard data
│   ├── notes_provider.dart     # Notes state
│   ├── scale_config_provider.dart  # Weighing scale config
│   ├── localization_provider.dart  # Active locale
│   ├── external_order_provider.dart # ExternalOrderState + ExternalOrderNotifier (DealUp/WhatsApp queue)
│   ├── desktop_update_provider.dart
│   └── update_provider.dart
│
├── services/                   # Stateful business-logic
│   ├── api_service.dart        # Dio REST client — baseUrl/token from SharedPrefs
│   ├── server_service.dart     # Shelf HTTP server for KDS/kiosk (CORS + auth middleware)
│   ├── server_startup_service.dart # Coordinates ServerService + DiscoveryService startup
│   ├── discovery_service.dart  # Bonsoir LAN advertisement/discovery
│   ├── socket_service.dart     # WebSocket client for real-time order push from server
│   ├── data_sync_service.dart  # Full sync: remote API → local DB (master data + orders)
│   ├── sync_job_service.dart   # Periodic sync scheduler
│   ├── pending_operations_service.dart # Queue offline mutations; flush on reconnect
│   ├── external_order_queue_service.dart # Poll remote queue for DealUp/WhatsApp orders
│   ├── session_service.dart    # Cash session open/close lifecycle
│   ├── auth_service.dart       # bcrypt login validation
│   ├── permission_service.dart # Role-based permission checks
│   ├── printing_service.dart   # Thermal printer (ESC/POS)
│   ├── order_log_service.dart  # Audit log for order mutations
│   ├── barcode_scanner_service.dart # USB/HID barcode scanner
│   ├── scale_barcode_service.dart   # Weighing scale barcode parsing
│   ├── customer_display_service.dart # Second-screen customer display
│   ├── sound_service.dart      # Audio feedback (audioplayers)
│   ├── daily_summary_service.dart   # End-of-day report generation
│   └── update_service.dart     # desktop_updater integration
│
└── utils/
    ├── app_localizations.dart  # Custom L10n (AR/FR/EN) — hand-written, NOT generated
    ├── currency_formatter.dart
    ├── button_styles.dart
    └── snackbar_helper.dart
```

---

# Key Flows (Cross-File Architecture)

## Boot Sequence
`main()` shows `_BootScreen` immediately, then calls `_initializeApp()` which:
1. Initializes `SharedPreferences` and passes it as a `ProviderScope` override
2. Inits `window_manager` (desktop only)
3. Builds the real `MaterialApp` with all routes and `ProviderScope`

Never let init throw — wrap expensive calls in `.timeout()` with fallback.

## Multi-Tenant Auth Flow
`/tenant` (TenantLoginScreen) → user selects/enters server URL → stored in SharedPrefs → `/login` (LoginScreen) authenticates local user via `AuthService` (bcrypt) → navigates to `/main`.

## Offline-First Mutation Flow
UI → `OrderRepository` → writes to local Drift DB → `PendingOperationsService.queue*()` adds entry to `pending_sync_operations` table → `SyncJobService` polls and calls `DataSyncService` → `ApiService` flushes to remote. Never call sync directly from UI.

## LAN Server Startup
`ServerStartupService.start()` calls `ServerService.start()` (Shelf on LAN IP) then `DiscoveryService.advertise()` (Bonsoir mDNS) so KDS/kiosk devices can discover the POS automatically.

## Real-Time Orders
`SocketService` maintains a WebSocket connection to the remote server. Incoming order events are surfaced via `socket_order_providers.dart` stream providers, consumed by KDS/order screens.

## External Order Queue (DealUp / WhatsApp)
`ExternalOrderQueueService` polls the remote server for pending external orders. `ExternalOrderNotifier` (`external_order_provider.dart`) holds `ExternalOrderState` (items, loading, error, confirming set). `ExternalOrdersTab` renders these as the second tab inside `OrdersManagementScreen`. Confirming an item converts it to a local `Order` via `OrderRepository`.

---

# Named Routes

```dart
'/tenant'       → TenantLoginScreen   // server selection (first boot)
'/tenant_login' → TenantLoginScreen   // alias
'/login'        → LoginScreen
'/main'         → MainScreen          // POS entry point
'/orders'       → OrdersManagementScreen
'/devices'      → DevicesManagementScreen
'/users'        → UsersManagementScreen
'/tickets'      → TicketsManagementScreen
'/sessions'     → SessionsManagementScreen
'/printers'     → PrintersManagementScreen
'/agenda'       → AgendaScreen
'/dashboard'    → DashboardScreen
'/notes'        → NotesScreen
'/api-tester'   → ApiTesterScreen
```

Add new routes as named strings in the `routes` map in `main.dart`.

---

# Strict Development Guidelines

## Naming Conventions
- **Files:** `snake_case.dart`
- **Classes:** `PascalCase` — screens `*Screen`, dialogs `*Dialog`, services `*Service`, repositories `*Repository`, notifiers `*Notifier`
- **Providers:** `camelCase` ending in `Provider`
- **Drift tables (class):** `PascalCase` plural — `Orders`, `Products`
- **Drift data row:** `PascalCase` singular — `Order`, `Product`
- **Drift companion:** `PascalCase` + `Companion` — `OrdersCompanion`

## State Management
- Use `StateNotifier` (not the newer `Notifier`) — project-wide pattern
- Mutable cart/order state lives in `OrderNotifier` (`providers/order_provider.dart`)
- Reactive DB queries: Drift `.watch()` wrapped in `StreamProvider`
- `SharedPreferences` injected via `sharedPreferencesProvider` overridden in `ProviderScope` — never call `SharedPreferences.getInstance()` inside a provider
- Services receive deps via constructor: `ServiceName(this._database)` or `ServiceName(this._ref, ...)`

## Database
- Tables in `lib/data/database/tables/` — one file per table
- Register in `@DriftDatabase(tables: [...])` in `app_database.dart`
- Current `schemaVersion` is **10** — bump and add a migration block in `MigrationStrategy.onUpgrade` for every schema change
- After schema changes: `flutter pub run build_runner build --delete-conflicting-outputs`
- Never edit `app_database.g.dart` manually
- `Value(x)` for optional Companion fields; omit for `DEFAULT`
- `build.yaml` sets `store_date_time_values_as_text: true` and SQLite dialect — never store datetimes as integers
- Full table list: Categories, Products, ProductVariants, **VariantAttributeValues**, Users, Components, ComponentGroups, ProductComponents, Areas, AreaTables, Stations, Kiosks, KDSs, Commercials, Customers, Orders, OrderProducts, OrderProductComponents, Payments, Transactions, CashSessions, Tickets, PendingSyncOperations, OrderLogs, Waiters, **WaiterAreas**, Notes

## Services & Repositories
- `OrderRepository` is sole source of truth for order CRUD — no direct DB calls from UI
- `ApiService` reads `baseUrl`/`accessToken` from SharedPrefs via Dio interceptors — no hardcoded URLs
- `ServerService` (Shelf): CORS and auth handled in middleware pipeline
- Offline mutations: queue via `PendingOperationsService` — do not call sync from UI
- Use `Logger.instance` from `loggecrea` — no bare `print()` in new code
- `PrintingService` manages **two independent printers**: receipt printer (customer copy) and KDS printer (kitchen tickets). Each has its own `PrinterConfig` (address + `ConnectionType`). `KdsPrintMode.modificationsOnly` prints only new/unprinted items to avoid duplicate kitchen tickets.

## Settings
- `AppSettings` (`domain/models/app_settings.dart`) is the typed settings model; persisted to SharedPrefs via `settingsProvider` in `providers/settings_provider.dart`
- Controls action button visibility (`showTableButton`, `showPayButton`, …) and `buttonOrder` list for reorderable POS toolbar
- `CategoryDisplayMode`: `topBar` (default) vs `fullPage` — changes main screen layout significantly

## UI Patterns
- `PermissionGuard` widget (`presentation/widgets/permission_guard.dart`) gates UI sections by role — wrap protected content rather than duplicating permission checks

## UI
- Material 3 (`useMaterial3: true`) — `Theme.of(context).colorScheme` for colors
- Theme in `lib/core/theme/app_theme.dart` — no hardcoded colors in widgets
- L10n: `AppLocalizations.of(context)!.someKey` — add keys in `lib/utils/app_localizations.dart`
- Management screens that are not full routes go in `lib/presentation/widgets/`

## Code Style
- Comments only for non-obvious WHY — not what
- `copyWith` for immutable state updates on domain models
- `WidgetsBinding.instance.addPostFrameCallback` for deferred post-frame init

---

# Common Commands

```bash
# Dependencies
flutter pub get

# Code generation (Drift + Riverpod + JSON) — run after any schema/provider/model change
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode
flutter pub run build_runner watch --delete-conflicting-outputs

# Run (Linux is primary dev target)
flutter run -d linux
flutter run -d android

# Release builds
flutter build linux --release
flutter build windows --release
flutter build apk --release

# Static analysis
flutter analyze

# Tests
flutter test

# Run a single test file
flutter test test/path/to/test_file.dart
```

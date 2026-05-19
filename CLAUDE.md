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
| Network utils | http | ^1.2.0 |
| LAN discovery | bonsoir | ^5.0.0 |
| Connectivity | connectivity_plus | ^6.1.4 |
| Localization | flutter_localizations + intl | ^0.20.2 |
| Printing | flutter_thermal_printer + esc_pos_utils_plus | ^2.0.0 / ^2.0.4 |
| UI extras | flutter_svg, getwidget, data_table_2 | ^2.0.10+1 / ^4.0.0 / ^2.7.1 |
| Forms | flutter_form_builder + form_builder_validators | ^10.0.1 / ^11.2.0 |
| Keyboard | flutter_onscreen_keyboard | ^0.4.1+1 |
| Barcode | flutter_barcode_listener | ^0.1.4 |
| Auth | bcrypt | ^1.2.0 |
| Desktop update | desktop_updater | ^1.4.0 |
| Window mgmt | window_manager | ^0.4.3 |
| Audio | audioplayers | ^6.5.1 |
| JSON codegen | json_serializable + json_annotation | ^6.7.1 / ^4.8.1 |
| Misc | shared_preferences, uuid, path_provider, path | latest |

---

# Architecture Map (Where do things live?)

```
lib/
├── core/
│   ├── enums.dart              # App-wide enums
│   └── theme/app_theme.dart    # Material 3 light/dark themes
│
├── data/
│   └── database/
│       ├── app_database.dart   # @DriftDatabase root — registers all tables
│       ├── app_database.g.dart # Generated — DO NOT edit manually
│       └── tables/             # One file per Drift table (snake_case filenames)
│
├── domain/
│   └── models/                 # Pure Dart domain models (OrderItem, CurrentOrder, etc.)
│                               # These are NOT Drift-generated — they are hand-written cart/state models
│
├── presentation/
│   ├── <screen_name>/          # Full-screen routes (login_screen, main_screen, etc.)
│   └── widgets/                # Reusable and secondary widgets/dialogs/management screens
│
├── providers/                  # ALL Riverpod providers live here
│   ├── database_providers.dart # DB, ApiService, DataSync, Session, SharedPrefs, data stream providers
│   ├── order_provider.dart     # OrderNotifier (StateNotifier) + OrderRepository + orderRepositoryProvider
│   ├── network_provider.dart   # Connectivity + online-status providers
│   ├── settings_provider.dart  # App settings (language, dark mode, server port, etc.)
│   └── *.dart                  # One provider file per domain area
│
├── services/                   # Stateful business-logic services (injected via providers)
│   ├── api_service.dart        # Dio-based REST client — reads baseUrl/token from SharedPrefs
│   ├── server_service.dart     # Shelf HTTP server (POS as LAN server for KDS/kiosk)
│   ├── data_sync_service.dart  # Sync local DB → remote server
│   ├── pending_operations_service.dart  # Queue offline mutations for later sync
│   ├── printing_service.dart   # Thermal printer integration
│   ├── session_service.dart    # Cash session lifecycle
│   └── *.dart
│
├── utils/
│   ├── app_localizations.dart  # Custom L10n (AR/FR/EN) — NOT generated
│   ├── currency_formatter.dart
│   ├── button_styles.dart
│   └── snackbar_helper.dart
│
└── main.dart                   # Entry point: ProviderScope override for SharedPreferences,
                                # window_manager init, GlobalSoundWrapper, named-route MaterialApp
```

**Routing:** `MaterialApp.routes` with named string routes (`/login`, `/main`, `/orders`, etc.). No go_router.

**Provider patterns in use:**
- `Provider<T>` — services and repositories (injected deps)
- `StateNotifierProvider<Notifier, State>` — mutable state (e.g. `orderProvider`)
- `StreamProvider` — reactive Drift DB queries (`.watch()`)
- `FutureProvider` — one-shot async data
- `StateProvider<T>` — simple mutable values (current user, selected category, etc.)
- `.autoDispose` — used on screen-scoped providers
- `.family` — parameterized providers (e.g. `productsByCategoryProvider(categoryId)`)

---

# Strict Development Guidelines

## Naming Conventions
- **Files:** `snake_case.dart`
- **Classes:** `PascalCase` — screens end in `Screen`, dialogs in `Dialog`, services in `Service`, repositories in `Repository`, notifiers in `Notifier`
- **Providers:** `camelCase` ending in `Provider` — e.g. `orderProvider`, `orderRepositoryProvider`
- **Variables/fields/methods:** `camelCase`
- **Drift tables (class):** `PascalCase` plural — `Orders`, `Products`, `OrderProducts`
- **Drift data row (class):** `PascalCase` singular — `Order`, `Product`, `OrderProduct`
- **Drift companion:** `PascalCase` + `Companion` — `OrdersCompanion`

## State Management Rules
- Use `StateNotifier` (not the newer `Notifier`) — existing code uses `StateNotifier<State>` pattern
- Mutable cart/order state lives in `OrderNotifier` in `providers/order_provider.dart`
- Reactive DB queries: always use Drift's `.watch()` wrapped in `StreamProvider`
- `SharedPreferences` must be injected via `sharedPreferencesProvider` (overridden in `ProviderScope` at startup) — never call `SharedPreferences.getInstance()` directly inside a provider
- Services receive deps via constructor: `ServiceName(this._database)` or `ServiceName(this._ref, ...)`

## Database Rules
- All tables defined in `lib/data/database/tables/` — one file per table
- Register new tables in `@DriftDatabase(tables: [...])` in `app_database.dart`
- After any table/schema change, run codegen: `flutter pub run build_runner build --delete-conflicting-outputs`
- Never edit `app_database.g.dart` manually
- Use `Value(x)` wrapper for optional fields in Companions; omit field for `DEFAULT` behavior

## Service & Repository Rules
- `OrderRepository` (in `order_provider.dart`) is the single source of truth for order CRUD — do not bypass it with direct DB calls from UI
- `ApiService` (Dio) reads `baseUrl`/`accessToken` from `SharedPreferences` via interceptors — do not hardcode URLs
- `ServerService` (Shelf) runs on LAN for KDS/kiosk — handle CORS and auth via its middleware pipeline
- Offline mutations: queue via `PendingOperationsService.queueOrderUpdate/Delete()` — do not call sync directly from UI
- Use `Logger.instance` from `loggecrea` for logging — avoid bare `print()` in new code

## UI Rules
- Material 3 (`useMaterial3: true`) — use `Theme.of(context).colorScheme` for colors
- Theme defined in `lib/core/theme/app_theme.dart` — do not hardcode colors in widgets
- SVG assets via `flutter_svg`; PNG assets registered in `pubspec.yaml` under `assets/images/`
- L10n: use `AppLocalizations.of(context)!.someKey` — translations in `lib/utils/app_localizations.dart`
- Dialogs/management screens that are not full routes live in `lib/presentation/widgets/`
- No `go_router` — add new routes as named strings in the `routes` map in `main.dart`

## Code Style
- No comments explaining WHAT code does — only WHY for non-obvious constraints
- `copyWith` pattern for immutable state updates on domain models
- `WidgetsBinding.instance.addPostFrameCallback` for deferred init after first frame
- Wrap expensive init in `.timeout()` with graceful fallback — never let init crash the app

---

# Common Commands

```bash
# Get dependencies
flutter pub get

# Run code generation (Drift schema + Riverpod + JSON serialization)
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode for code generation
flutter pub run build_runner watch --delete-conflicting-outputs

# Run on Linux desktop (primary dev target)
flutter run -d linux

# Run on Windows desktop
flutter run -d windows

# Run on connected Android device
flutter run -d android

# Build Linux release
flutter build linux --release

# Build Windows release
flutter build windows --release

# Build Android APK
flutter build apk --release

# Generate launcher icons
flutter pub run flutter_launcher_icons

# Generate native splash screen
flutter pub run flutter_native_splash:create

# Analyze code
flutter analyze

# Run tests
flutter test
```

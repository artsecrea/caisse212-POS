import 'dart:async';

import 'package:drift/drift.dart' hide Column show OrderingTerm, BooleanExpressionOperators;
import '../domain/models/component_rules.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/app_database.dart';
import '../data/database/app_database.dart' as db;
import '../services/session_service.dart';
import '../services/z_service.dart';
import '../services/notification_outbox.dart';
import '../services/z_rules.dart' show parseZDay;
import 'business_day_provider.dart';
import '../services/refund_service.dart';
import '../services/cash_movement_service.dart';
import '../services/serial_service.dart';
import '../services/quick_product_service.dart';
import '../services/api_service.dart';
import '../services/subscription_store.dart';
import '../services/account_status_store.dart';
import '../services/kick_store.dart';
import '../domain/models/account_status.dart';
import '../services/refund_policy_store.dart';
import '../domain/models/refund_policy.dart';
import '../domain/models/subscription_info.dart';
import '../services/data_sync_service.dart';
import '../services/printing_service.dart';
import '../services/unpaid_orders_service.dart';
import '../services/pending_operations_service.dart';
import '../services/sync_job_service.dart';
import '../services/barcode_scanner_service.dart';
import '../utils/pos_log.dart';

// Database Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

// API Service Provider
final apiServiceProvider = Provider<ApiService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ApiService(prefs);
});

// Fires whenever the server explicitly rejects the refresh token (4xx on
// /pos/refresh). The main screen listens to this and navigates to login.
final forceLogoutStreamProvider = StreamProvider<void>((ref) {
  return ref.watch(apiServiceProvider).forceLogoutStream;
});

// Fires the local DB id of any order whose sync delta was just applied.
// The main screen uses this to live-refresh the order currently open in the panel.
final syncedOrderUpdatedProvider = StreamProvider<int>((ref) {
  return ref.watch(dataSyncServiceProvider).syncedOrderUpdatedStream;
});

// Data Sync Service Provider
final dataSyncServiceProvider = Provider<DataSyncService>((ref) {
  final database = ref.watch(databaseProvider);
  final apiService = ref.watch(apiServiceProvider);
  return DataSyncService(database, apiService);
});

// Pending Operations Service Provider
final pendingOperationsServiceProvider = Provider<PendingOperationsService>((ref) {
  final database = ref.watch(databaseProvider);
  return PendingOperationsService(database);
});

// Sync Job Service Provider - initialized lazily to avoid circular dependency
// Use syncJobServiceWithNetworkProvider from network_provider.dart instead
final syncJobServiceProvider = Provider<SyncJobService>((ref) {
  final syncService = ref.watch(dataSyncServiceProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  // Default offline callback - will be updated by network_provider
  return SyncJobService(syncService, prefs, () => false);
});

// Printing Service Provider
final printingServiceProvider = Provider<PrintingService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final service = PrintingService();
  try {
    service.initialize(prefs, ref);
  } catch (e) {
    debugPrint('⚠️ PrintingService initialization failed: $e');
  }
  return service;
});

// Barcode Scanner Service Provider
final barcodeScannerServiceProvider = Provider<BarcodeScannerService>((ref) {
  return BarcodeScannerService();
});

// Barcode Scanner Mode Provider
enum BarcodeScanMode {
  disabled,  // Scanning disabled
  orders,    // Scan order codes
  products,  // Scan product barcodes
}

class BarcodeScanModeNotifier extends StateNotifier<BarcodeScanMode> {
  static const _key = 'barcode_scan_mode';
  final SharedPreferences _prefs;

  BarcodeScanModeNotifier(this._prefs) : super(_load(_prefs));

  static BarcodeScanMode _load(SharedPreferences prefs) {
    switch (prefs.getString(_key)) {
      case 'orders':   return BarcodeScanMode.orders;
      case 'disabled': return BarcodeScanMode.disabled;
      default:         return BarcodeScanMode.products;
    }
  }

  @override
  set state(BarcodeScanMode value) {
    super.state = value;
    _prefs.setString(_key, value.name);
  }
}

final barcodeScanModeProvider =
    StateNotifierProvider<BarcodeScanModeNotifier, BarcodeScanMode>((ref) {
  return BarcodeScanModeNotifier(ref.watch(sharedPreferencesProvider));
});

// Session Service Provider
final sessionServiceProvider = Provider<SessionService>((ref) {
  final database = ref.watch(databaseProvider);
  return SessionService(database);
});

// Z (shift) Service Provider
final zServiceProvider = Provider<ZService>((ref) {
  final database = ref.watch(databaseProvider);
  return ZService(database);
});

/// Every admin notification goes through the outbox: queued in the DB, sent,
/// deleted once delivered, retried by the sync job when the network is down.
final notificationOutboxProvider = Provider<NotificationOutbox>((ref) {
  return NotificationOutbox(
      ref.watch(databaseProvider), ref.watch(apiServiceProvider));
});

// Refund Service Provider
final refundServiceProvider = Provider<RefundService>((ref) {
  final database = ref.watch(databaseProvider);
  return RefundService(database);
});

// Cash Movement Service Provider (drawer paid-in / paid-out)
final cashMovementServiceProvider = Provider<CashMovementService>((ref) {
  final database = ref.watch(databaseProvider);
  return CashMovementService(database);
});

final quickProductServiceProvider = Provider<QuickProductService>((ref) {
  final db = ref.watch(databaseProvider);
  final api = ref.watch(apiServiceProvider);
  return QuickProductService(api, db, DataSyncService(db, api));
});

// ── Serial-managed products (unit-level stock) ──────────────────────────────

final serialServiceProvider = Provider<SerialService>((ref) {
  final database = ref.watch(databaseProvider);
  return SerialService(database);
});

/// Units of [productId] still sellable. A stream, not a future, so a serial
/// reserved into the basket (or one removed by a catalogue pull after another
/// terminal sold it) leaves an open picker immediately.
final availableSerialsProvider =
    StreamProvider.family<List<db.Serial>, int>((ref, productId) {
  return ref.watch(serialServiceProvider).watchAvailableFor(productId);
});

/// Whether a product needs a serial before it can be sold. Watched by the
/// product tile and the modification dialog, both of which must block the sale
/// rather than let the order fail later with a 400 at sync time.
final isSerialTrackedProvider =
    FutureProvider.family<bool, ({int productId, int? variantId})>(
        (ref, args) async {
  return ref
      .watch(serialServiceProvider)
      .isTracked(productId: args.productId, variantId: args.variantId);
});

// Current Session Provider
final currentSessionProvider = StateProvider<db.CashSession?>((ref) => null);

/// The Z (shift) currently open on this terminal. Set when a Z is opened (auto
/// with the first session, or by an admin/manager), cleared when it's closed.
final currentZProvider = StateProvider<db.Z?>((ref) => null);

/// The open Z straight from the database, for screens that show it before
/// [currentZProvider] is set (the login screen).
final openZStreamProvider = StreamProvider.autoDispose<db.Z?>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.zs)
        ..where((z) => z.status.equals('open'))
        ..orderBy([(z) => OrderingTerm.desc(z.startedAt)])
        ..limit(1))
      .watchSingleOrNull();
});

/// The business day of [z] — the canonical z_day for everything created while
/// that Z is open.
DateTime zDayForZ(db.Z z) => ZService.zDayOf(z);

/// Canonical z_day for a row that belongs to [session] when it has no Z (a
/// legacy row): midnight of the session's opening day.
DateTime zDayForSession(db.CashSession session) => DateTime(
    session.startedAt.year, session.startedAt.month, session.startedAt.day);

/// The "Z day" for all inserts. Derives from the active Z's opening day (so all
/// rows across the Z's multiple sessions share one z_day), falling back to the
/// current session's day, then today. Zero DB hits — reads already-loaded state.
/// What the floor still owes, refreshed whenever anything that could change
/// it changes.
///
/// The trivial `SELECT 1` is a drift idiom, not a mistake: declaring
/// `readsFrom` makes the stream re-emit on any write to those tables, which is
/// what lets one recomputation cover orders, their lines, their tickets and
/// the floor plan together. Watching only `orders` would miss a payment, and
/// the figures on the floor would quietly go stale.
///
/// Tables only — this feeds the table picker. The reports ask the service
/// directly for the wider set.
final unpaidTablesProvider =
    StreamProvider.autoDispose<UnpaidOrdersSummary>((ref) {
  final database = ref.watch(databaseProvider);
  final service = UnpaidOrdersService(database);
  return database
      .customSelect(
        'SELECT 1',
        readsFrom: {
          database.orders,
          database.orderProducts,
          database.orderProductComponents,
          database.tickets,
          database.areaTables,
        },
      )
      .watch()
      .asyncMap((_) => service.summary(tablesOnly: true));
});

final currentZDayProvider = Provider<DateTime>((ref) {
  final z = ref.watch(currentZProvider);
  if (z != null) return zDayForZ(z);
  final session = ref.watch(currentSessionProvider);
  if (session != null) return zDayForSession(session);
  return parseZDay(ref.read(businessDayProvider.notifier).currentZDay())!;
});

class CurrentUser{
  final int id;
  final String username;
  final String password;
  final String firstName;
  final String lastName;
  final String? displayName;
  final String type;
  final String? imageUrl;
  final String? accessToken;
  final String? refreshToken;
  final String permissions;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastLogin;

  late final List<String> _perms;

  CurrentUser(this.id, this.username, this.password, this.firstName,
      this.lastName, this.type, this.imageUrl, this.accessToken,
      this.refreshToken, this.permissions, this.createdAt, this.updatedAt,
      this.lastLogin, {this.displayName}){
    _perms = permissions.split(",");
  }

  String get effectiveDisplayName {
    if (displayName != null && displayName!.isNotEmpty) return displayName!;
    return '$firstName $lastName'.trim();
  }

  /// Legal full name (firstName + lastName). Used by activity log entries so
  /// the audit trail keeps the legal identity even when the cashier sets a
  /// nickname via [displayName].
  String get fullName => '$firstName $lastName'.trim();

  static CurrentUser fromUser(db.User user) {
    return CurrentUser(
        user.id,
        user.username,
        user.password,
        user.firstName,
        user.lastName,
        user.type,
        user.imageUrl,
        user.accessToken,
        user.refreshToken,
        user.permissions ?? "",
        user.createdAt,
        user.updatedAt,
        user.lastLogin,
        displayName: user.displayName,
    );
  }

  /// Whether this user has [perm]. Mirrors PermissionService: admin bypass,
  /// exact match, and prefix wildcards (e.g. "pos:*", "pos:orders:*").
  bool hasPermission(String perm){
    if (type.toLowerCase() == 'admin') return true;
    final perms = _perms.map((p) => p.trim());
    if (perms.contains(perm)) return true;
    for (final p in perms) {
      if (p.endsWith(':*') && perm.startsWith(p.substring(0, p.length - 1))) {
        return true;
      }
    }
    return false;
  }

  CurrentUser copyWith({String? displayName}) {
    return CurrentUser(
      id, username, password, firstName, lastName, type, imageUrl,
      accessToken, refreshToken, permissions, createdAt, updatedAt, lastLogin,
      displayName: displayName ?? this.displayName,
    );
  }
}

/// [user] as the local users table now has it. [currentUserProvider] is a
/// snapshot taken at login, so without this a role or permission change pulled
/// by a sync would only reach the till at the next sign-in. Returns [user]
/// unchanged when its row is missing — a sync must never sign anyone out.
Future<CurrentUser> reloadCurrentUser(
    AppDatabase database, CurrentUser user) async {
  final row = await (database.select(database.users)
        ..where((u) => u.id.equals(user.id)))
      .getSingleOrNull();
  return row == null ? user : CurrentUser.fromUser(row);
}


// Shared Preferences Provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden');
});

// Current User Provider
final currentUserProvider = StateProvider<CurrentUser?>((ref) => null);

// Network State Provider
final networkStateProvider = StateProvider<bool>((ref) => true);

// Per-terminal category scope (`posTerminal.categoryIds`, handed to us on
// login and on every token refresh). null = this terminal shows everything.
//
// The server deliberately keeps sending the FULL catalogue on
// `GET /pos/categories` — narrowing it there would make the sync's delete
// reconciliation drop local category rows that reprints and station routing
// still need. So scoping is a display filter only: hidden categories stay in
// the database, they just never reach the grid.
class CategoryScopeNotifier extends StateNotifier<List<int>?> {
  CategoryScopeNotifier(ApiService api) : super(api.categoryScope) {
    _sub = api.categoryScopeStream.listen((ids) => state = ids);
  }

  late final StreamSubscription<List<int>?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final categoryScopeProvider =
    StateNotifierProvider<CategoryScopeNotifier, List<int>?>((ref) {
  return CategoryScopeNotifier(ref.watch(apiServiceProvider));
});

// The shop's subscription as last heard from the server (login, refresh,
// catalogue sync, daily check, SSE). null = nothing to track.
class SubscriptionNotifier extends StateNotifier<SubscriptionInfo?> {
  SubscriptionNotifier(SharedPreferences prefs)
      : super(SubscriptionStore(prefs).current) {
    _sub = SubscriptionStore.changes.listen((info) => state = info);
  }

  late final StreamSubscription<SubscriptionInfo?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionInfo?>((ref) {
  return SubscriptionNotifier(ref.watch(sharedPreferencesProvider));
});

// Tenant / business / terminal deactivated in the back office, as last heard
// from the server. null = active. Persisted, so the lock survives a restart.
class AccountBlockNotifier extends StateNotifier<AccountBlock?> {
  AccountBlockNotifier(SharedPreferences prefs)
      : super(AccountStatusStore(prefs).current) {
    _sub = AccountStatusStore.changes.listen((b) => state = b);
  }

  late final StreamSubscription<AccountBlock?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final accountBlockProvider =
    StateNotifierProvider<AccountBlockNotifier, AccountBlock?>((ref) {
  return AccountBlockNotifier(ref.watch(sharedPreferencesProvider));
});

// The back office's last `force_kick`, until the terminal signs in again.
class KickNoticeNotifier extends StateNotifier<KickNotice?> {
  KickNoticeNotifier(SharedPreferences prefs) : super(KickStore(prefs).current) {
    _sub = KickStore.changes.listen((k) => state = k);
  }

  late final StreamSubscription<KickNotice?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final kickNoticeProvider =
    StateNotifierProvider<KickNoticeNotifier, KickNotice?>((ref) {
  return KickNoticeNotifier(ref.watch(sharedPreferencesProvider));
});

// The refund policy as last fetched (`GET /pos/refund-policy`), or the
// defaults (today's behaviour) when the server has none.
class RefundPolicyNotifier extends StateNotifier<RefundPolicy> {
  RefundPolicyNotifier(SharedPreferences prefs)
      : super(RefundPolicyStore(prefs).current) {
    _sub = RefundPolicyStore.changes.listen((p) => state = p);
  }

  late final StreamSubscription<RefundPolicy> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final refundPolicyProvider =
    StateNotifierProvider<RefundPolicyNotifier, RefundPolicy>((ref) {
  return RefundPolicyNotifier(ref.watch(sharedPreferencesProvider));
});

// The order-tag catalogue, in the back office's order.
final orderTagsProvider = StreamProvider<List<db.OrderTag>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.orderTags)
        ..orderBy([
          (t) => OrderingTerm(expression: t.sortOrder),
          (t) => OrderingTerm(expression: t.label),
        ]))
      .watch();
});

// Categories Provider
final categoriesProvider = StreamProvider<List<db.Category>>((ref) {
  final database = ref.watch(databaseProvider);
  final scope = ref.watch(categoryScopeProvider);

  final stream = (database.select(database.categories)
    ..where((tbl) => tbl.isActive.equals(true))
    ..orderBy([(tbl) => OrderingTerm(expression: tbl.displayOrder)])
    ..watch()).watch();

  if (scope == null) return stream;
  return stream.map((categories) => scopedCategories(categories, scope));
});

/// Drops the products that belong to a category this terminal may not show.
///
/// A product with no category at all is not IN a hidden category, so it stays.
/// Shared with the LAN server: the waiter tablets are served an already-scoped
/// menu rather than being trusted to filter one, because their search reads
/// every product they hold and never consults the category list.
List<db.Product> scopedProducts(List<db.Product> products, List<int>? scope) {
  if (scope == null) return products;
  final allowed = scope.toSet();
  return products
      .where((p) => p.categoryId == null || allowed.contains(p.categoryId))
      .toList();
}

/// Keeps only the categories this terminal may show, in the order the server
/// listed them — the scope list IS the display order on the till, so it
/// overrides `displayOrder` for the terminals that have one.
List<db.Category> scopedCategories(
    List<db.Category> categories, List<int>? scope) {
  if (scope == null) return categories;
  final rank = {for (var i = 0; i < scope.length; i++) scope[i]: i};
  return categories.where((c) => rank.containsKey(c.id)).toList()
    ..sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
}

// Selected Category Provider
final selectedCategoryProvider = StateProvider<int?>((ref) => null);

// Product Search Query Provider
final productSearchQueryProvider = StateProvider<String>((ref) => '');

// Products by Category Provider
final productsByCategoryProvider = StreamProvider.autoDispose.family<List<db.Product>, int?>((ref, categoryId) {
  final database = ref.watch(databaseProvider);
  final scope = ref.watch(categoryScopeProvider);

  // Products keep syncing for every category; a product whose category is out
  // of this terminal's scope simply never shows in the grid.
  Stream<List<db.Product>> scoped(Stream<List<db.Product>> stream) {
    if (scope == null) return stream;
    return stream.map((products) => scopedProducts(products, scope));
  }

  // categoryId == null: Show category selection (no products)
  // categoryId == -1: Show all products
  // categoryId > 0: Show products for specific category
  if (categoryId == null) {
    return scoped((database.select(database.products)
      ..where((tbl) => tbl.isActive.equals(true))
      ..watch()).watch());
  }

  if (categoryId == -1) {
    // Special value: Show ALL products
    return scoped((database.select(database.products)
      ..where((tbl) => tbl.isActive.equals(true))
      ..watch()).watch());
  }

  if (scope != null && !scope.contains(categoryId)) {
    return Stream.value(const <db.Product>[]);
  }

  return (database.select(database.products)
    ..where((tbl) => tbl.isActive.equals(true) & tbl.categoryId.equals(categoryId))
    ..watch()).watch();
});

// Filtered Products Provider (with search query)
final filteredProductsProvider = Provider.autoDispose<AsyncValue<List<db.Product>>>((ref) {
  final selectedCategory = ref.watch(selectedCategoryProvider);
  final searchQuery = ref.watch(productSearchQueryProvider).trim().toLowerCase();
  final productsAsync = ref.watch(productsByCategoryProvider(selectedCategory));

  return productsAsync.when(
    data: (products) {
      if (searchQuery.isEmpty) {
        return AsyncValue.data(products);
      }

      final filtered = products.where((product) {
        final nameMatch = product.name.toLowerCase().contains(searchQuery);
        final barcodeMatch = product.barcode?.toLowerCase().contains(searchQuery) ?? false;
        final referenceMatch = product.reference?.toLowerCase().contains(searchQuery) ?? false;
        return nameMatch || barcodeMatch || referenceMatch;
      }).toList();

      return AsyncValue.data(filtered);
    },
    loading: () => const AsyncValue.loading(),
    error: (error, stack) => AsyncValue.error(error, stack),
  );
});

// Areas Provider
final areasProvider = StreamProvider<List<db.Area>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.areas)..watch()).watch();
});

// Area Tables Provider
final areaTablesProvider = StreamProvider<List<db.AreaTable>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.areaTables)..watch()).watch();
});

/// Which waiter is on each order, keyed by `orders.id`.
///
/// The floor plan has to say who is serving a table, and `area_tables` only
/// carries an order id — the waiter lives on the order. Keyed by order rather
/// than by table so a stale table pointer shows nobody instead of borrowing
/// some other table's waiter.
final orderWaiterIdsProvider = StreamProvider<Map<int, int>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.orders)
        ..where((o) => o.waiterId.isNotNull()))
      .watch()
      .map((orders) => {
            for (final o in orders)
              if (o.waiterId != null) o.id: o.waiterId!,
          });
});

// Commercials Provider
final commercialsProvider = StreamProvider<List<db.Commercial>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.commercials)..watch()).watch();
});

// Components Provider
final componentsProvider = StreamProvider<List<db.Component>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.components)..watch()).watch();
});

// Component Groups Provider
final componentGroupsProvider = StreamProvider<List<db.ComponentGroup>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.componentGroups)
    ..orderBy([(tbl) => OrderingTerm(expression: tbl.displayOrder)])
    ..watch()).watch();
});

// Product Components by Product ID Provider (components available for a product)
// Returns a list of maps containing both Component and ProductComponent data
final productComponentsProvider = StreamProvider.autoDispose.family<List<Map<String, dynamic>>, int>((ref, productId) async* {
  final database = ref.watch(databaseProvider);

  // Get product-component relationships with constraints
  final productComponents = await (database.select(database.productComponents)
    ..where((tbl) => tbl.productId.equals(productId))).get();
  
  posLog(productComponents.toString());


  if (productComponents.isEmpty) {
    yield [];
    return;
  }

  // Get the actual components with their constraints. 86'd components are
  // left out of ordering entirely — the row stays for history, but nobody can
  // add one to a ticket.
  final componentIds = productComponents.map((pc) => pc.componentId).toList();
  final components = await (database.select(database.components)
    ..where((tbl) => tbl.id.isIn(componentIds))
    ..where((tbl) => tbl.isActive.equals(true))
    ..orderBy([
      (tbl) => OrderingTerm(expression: tbl.displayOrder),
      (tbl) => OrderingTerm(expression: tbl.name),
    ])).get();

  // Combine component data with relationship constraints
  final result = components.map((component) {
    final productComponent = productComponents.firstWhere(
      (pc) => pc.componentId == component.id,
    );

    return {
      'component': component,
      'isRequired': productComponent.isRequired,
      'minQuantity': productComponent.minQuantity,
      'maxQuantity': productComponent.maxQuantity,
      // The resolved price: this link's override, or the component's own.
      // Everything downstream — pricing, the free allowance, removal charges —
      // reads this one number, so the precedence lives in exactly one place.
      'defaultPrice': productComponent.defaultPrice ?? component.price,
      'defaultQuantity': productComponent.defaultQuantity,
      'chargeOnRemoval': productComponent.chargeOnRemoval,
    };
  }).toList();

  yield result;
});

/// The component-group rules in force for one product.
///
/// Keyed by group id, with `null` holding the bucket of components that belong
/// to no group. A product-level override row wins where it has a value; every
/// field it leaves null falls back to the group's own default, and a group
/// with no override row at all is used exactly as the catalogue defines it.
final productComponentGroupRulesProvider = FutureProvider.autoDispose
    .family<Map<int?, ComponentGroupRule>, int>((ref, productId) =>
        loadComponentGroupRules(ref.watch(databaseProvider), productId));

/// The resolution behind [productComponentGroupRulesProvider], callable
/// without a ref so the kitchen ticket reads the rules exactly as the picker
/// does.
Future<Map<int?, ComponentGroupRule>> loadComponentGroupRules(
    AppDatabase database, int productId) async {
  final groups = await (database.select(database.componentGroups)
        ..orderBy([(tbl) => OrderingTerm(expression: tbl.displayOrder)]))
      .get();
  final overrides = await (database.select(database.productComponentGroups)
        ..where((tbl) => tbl.productId.equals(productId)))
      .get();
  final overrideByGroup = {for (final o in overrides) o.groupId: o};

  final rules = <int?, ComponentGroupRule>{
    // Ungrouped components keep the old permissive behaviour: no minimum, no
    // ceiling, steppers. There is no group row to say otherwise.
    null: const ComponentGroupRule(groupId: null, name: '', displayOrder: 9999),
  };

  for (final group in groups) {
    final o = overrideByGroup[group.id];
    rules[group.id] = ComponentGroupRule(
      groupId: group.id,
      name: group.name,
      color: group.color,
      selectionType:
          parseSelectionType(o?.selectionType ?? group.selectionType),
      minSelection: o?.minSelection ?? group.minSelection,
      maxSelection: o?.maxSelection ?? group.maxSelection,
      freeQuantity: o?.freeQuantity ?? group.freeQuantity,
      displayOrder: o?.displayOrder ?? group.displayOrder,
      // Product row only: the group-level default is informational, and the
      // server already dropped triggers this product does not offer. No row
      // means unconditional on this product.
      visibleWhenComponentIds: decodeVisibleWhen(o?.visibleWhenComponentIds),
    );
  }
  return rules;
}

/// How many draft tickets the order is currently divided into — see
/// `TicketDraftSplits`' own doc comment for the full contract. Local-only,
/// exactly like the table it reads: never synced, never seen by the server,
/// purely a cashier's in-progress arrangement made on the payment screen
/// before anything is paid. Drives the "this order is already divided" hint
/// on the main screen's order panel (see `order_panel.dart`).
///
/// A `.watch()` stream rather than a one-shot read: the division changes
/// while the payment screen is open, and a `FutureProvider` here cached the
/// count from the first read and then reported it forever — the panel went on
/// claiming "2 tickets" after the cashier had merged them back into one.
final ticketDraftTicketCountProvider =
    StreamProvider.autoDispose.family<int, int>((ref, orderId) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.ticketDraftSplits)
        ..where((t) => t.orderId.equals(orderId)))
      .watch()
      // Distinct `draft_index` values, not row count: one draft ticket holds
      // as many rows as it has lines, and a line divided across two tickets
      // contributes a row to each.
      .map((rows) => rows.map((r) => r.draftIndex).toSet().length);
});

// Product Variants Provider - fetches all variants for a product with their attribute values
final productVariantsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, int>((ref, productId) async {
  final database = ref.watch(databaseProvider);

  // Get all variants for this product
  final variants = await (database.select(database.productVariants)
    ..where((tbl) => tbl.productId.equals(productId))
    ..where((tbl) => tbl.isActive.equals(true))).get();

  if (variants.isEmpty) {
    return [];
  }

  // Get all attribute values for these variants
  final variantIds = variants.map((v) => v.id).toList();
  final attributeValues = await (database.select(database.variantAttributeValues)
    ..where((tbl) => tbl.variantId.isIn(variantIds))).get();

  // Group attribute values by variant
  final result = variants.map((variant) {
    final variantAttrs = attributeValues
        .where((av) => av.variantId == variant.id)
        .toList();

    return {
      'variant': variant,
      'attributeValues': variantAttrs,
    };
  }).toList();

  return result;
});

// Get unique attributes for a product (for dropdown labels)
final productAttributesProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, int>((ref, productId) async {
  final database = ref.watch(databaseProvider);

  // Get all variants for this product
  final variants = await (database.select(database.productVariants)
    ..where((tbl) => tbl.productId.equals(productId))
    ..where((tbl) => tbl.isActive.equals(true))).get();

  if (variants.isEmpty) {
    return [];
  }

  // Get all attribute values for these variants
  final variantIds = variants.map((v) => v.id).toList();
  final attributeValues = await (database.select(database.variantAttributeValues)
    ..where((tbl) => tbl.variantId.isIn(variantIds))).get();

  // Group by attributeId to get unique attributes with their possible values
  final attributesMap = <int, Map<String, dynamic>>{};

  for (final av in attributeValues) {
    if (!attributesMap.containsKey(av.attributeId)) {
      attributesMap[av.attributeId] = {
        'attributeId': av.attributeId,
        'attributeName': av.attributeName ?? 'Attribute ${av.attributeId}',
        'values': <Map<String, dynamic>>[],
      };
    }

    // Add value if not already present
    final values = attributesMap[av.attributeId]!['values'] as List<Map<String, dynamic>>;
    final exists = values.any((v) => v['valueId'] == av.valueId);
    if (!exists) {
      values.add({
        'valueId': av.valueId,
        'value': av.value ?? 'Value ${av.valueId}',
      });
    }
  }

  return attributesMap.values.toList();
});

// Waiter Providers

/// Get all waiters
final waitersProvider = StreamProvider<List<Waiter>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.waiters)
    ..where((tbl) => tbl.isActive.equals(true))
    ..orderBy([(tbl) => OrderingTerm.asc(tbl.firstName)]))
    .watch();
});

/// Get waiter by ID
final waiterByIdProvider = FutureProvider.autoDispose.family<Waiter?, int>((ref, waiterId) async {
  final database = ref.watch(databaseProvider);
  return await (database.select(database.waiters)
    ..where((tbl) => tbl.id.equals(waiterId)))
    .getSingleOrNull();
});

/// Get area IDs assigned to a waiter
final waiterAreasProvider = FutureProvider.autoDispose.family<List<int>, int>((ref, waiterId) async {
  final database = ref.watch(databaseProvider);
  final waiterAreas = await (database.select(database.waiterAreas)
    ..where((tbl) => tbl.waiterId.equals(waiterId)))
    .get();
  return waiterAreas.map((wa) => wa.areaId).toList();
});

/// Get waiters by area (includes waiters with no area assignments - they serve all areas)
final waitersByAreaProvider = FutureProvider.autoDispose.family<List<Waiter>, int?>((ref, areaId) async {
  final database = ref.watch(databaseProvider);

  // Get all active waiters
  final allWaiters = await (database.select(database.waiters)
    ..where((tbl) => tbl.isActive.equals(true)))
    .get();

  if (areaId == null) {
    // No area selected, return all waiters
    return allWaiters;
  }

  // Get all waiter-area assignments
  final allAssignments = await database.select(database.waiterAreas).get();

  // Group assignments by waiter ID
  final waiterAreaMap = <int, List<int>>{};
  for (final assignment in allAssignments) {
    waiterAreaMap.putIfAbsent(assignment.waiterId, () => []).add(assignment.areaId);
  }

  // Filter waiters: include those assigned to this area OR those with no assignments (serve all)
  final result = <Waiter>[];
  for (final waiter in allWaiters) {
    final assignedAreas = waiterAreaMap[waiter.id] ?? [];
    if (assignedAreas.isEmpty || assignedAreas.contains(areaId)) {
      result.add(waiter);
    }
  }

  return result;
});

/// Get waiter statistics: active orders count and total unpaid amount
final waiterStatsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, waiterId) async {
  final database = ref.watch(databaseProvider);

  // Get all orders assigned to this waiter (not completed/cancelled)
  final ordersQuery = database.select(database.orders)
    ..where((tbl) => tbl.waiterId.equals(waiterId))
    ..where((tbl) => tbl.status.isNotIn(['COMPLETED', 'DELIVERED', 'CANCELLED']));

  final orders = await ordersQuery.get();
  int totalOrders = orders.length;
  double unpaidTotal = 0.0;

  for (final order in orders) {
    // Get all order products for this order
    final products = await (database.select(database.orderProducts)
      ..where((tbl) => tbl.orderId.equals(order.id)))
      .get();

    for (final product in products) {
      // Only count unpaid items (no ticketId)
      if (product.ticketId == null) {
        // Get component prices for this product
        final components = await (database.select(database.orderProductComponents)
          ..where((tbl) => tbl.orderProductId.equals(product.id)))
          .get();
        
        double componentTotal = 0.0;
        for (final comp in components) {
          componentTotal += comp.price * comp.quantity;
        }
        
        final itemTotal = (product.unitaryPrice + componentTotal) * product.quantity;
        unpaidTotal += itemTotal;
      }
    }
  }

  return {
    'totalOrders': totalOrders,
    'unpaidTotal': unpaidTotal,
  };
});

/// Check if a waiter can serve an area
final canWaiterServeAreaProvider = FutureProvider.autoDispose.family<bool, ({int waiterId, int areaId})>((ref, params) async {
  final database = ref.watch(databaseProvider);

  // Get waiter's assigned areas
  final waiterAreas = await (database.select(database.waiterAreas)
    ..where((tbl) => tbl.waiterId.equals(params.waiterId)))
    .get();

  // If no areas assigned, waiter can serve all areas
  if (waiterAreas.isEmpty) {
    return true;
  }

  // Check if the area is in the waiter's assigned areas
  return waiterAreas.any((wa) => wa.areaId == params.areaId);
});

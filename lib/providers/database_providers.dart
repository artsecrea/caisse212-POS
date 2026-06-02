import 'package:drift/drift.dart' hide Column show OrderingTerm, BooleanExpressionOperators;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/app_database.dart';
import '../data/database/app_database.dart' as db;
import '../services/session_service.dart';
import '../services/api_service.dart';
import '../services/data_sync_service.dart';
import '../services/printing_service.dart';
import '../services/pending_operations_service.dart';
import '../services/sync_job_service.dart';
import '../services/barcode_scanner_service.dart';

// Database Provider
final databaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

// API Service Provider
final apiServiceProvider = Provider<ApiService>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ApiService(prefs);
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

final barcodeScanModeProvider = StateProvider<BarcodeScanMode>((ref) {
  return BarcodeScanMode.orders; // Default to scanning orders
});

// Session Service Provider
final sessionServiceProvider = Provider<SessionService>((ref) {
  final database = ref.watch(databaseProvider);
  return SessionService(database);
});

// Current Session Provider
final currentSessionProvider = StateProvider<db.CashSession?>((ref) => null);

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


// Shared Preferences Provider
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden');
});

// Current User Provider
final currentUserProvider = StateProvider<CurrentUser?>((ref) => null);

// Network State Provider
final networkStateProvider = StateProvider<bool>((ref) => true);

// Categories Provider
final categoriesProvider = StreamProvider<List<db.Category>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.categories)
    ..where((tbl) => tbl.isActive.equals(true))
    ..orderBy([(tbl) => OrderingTerm(expression: tbl.displayOrder)])
    ..watch()).watch();
});

// Selected Category Provider
final selectedCategoryProvider = StateProvider<int?>((ref) => null);

// Product Search Query Provider
final productSearchQueryProvider = StateProvider<String>((ref) => '');

// Products by Category Provider
final productsByCategoryProvider = StreamProvider.autoDispose.family<List<db.Product>, int?>((ref, categoryId) {
  final database = ref.watch(databaseProvider);

  // categoryId == null: Show category selection (no products)
  // categoryId == -1: Show all products
  // categoryId > 0: Show products for specific category
  if (categoryId == null) {
    return (database.select(database.products)
      ..where((tbl) => tbl.isActive.equals(true))
      ..watch()).watch();
  }

  if (categoryId == -1) {
    // Special value: Show ALL products
    return (database.select(database.products)
      ..where((tbl) => tbl.isActive.equals(true))
      ..watch()).watch();
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
        return nameMatch || barcodeMatch;
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
  
  print(productComponents.toString());


  if (productComponents.isEmpty) {
    yield [];
    return;
  }

  // Get the actual components with their constraints
  final componentIds = productComponents.map((pc) => pc.componentId).toList();
  final components = await (database.select(database.components)
    ..where((tbl) => tbl.id.isIn(componentIds))).get();

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
      'defaultPrice': productComponent.defaultPrice,
      'defaultQuantity': productComponent.defaultQuantity,
    };
  }).toList();

  yield result;
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

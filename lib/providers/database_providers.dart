import 'package:drift/drift.dart' hide Column show OrderingTerm, BooleanExpressionOperators;
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
  service.initialize(prefs);
  return service;
});

// Barcode Scanner Service Provider
final barcodeScannerServiceProvider = Provider<BarcodeScannerService>((ref) {
  return BarcodeScannerService();
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
      this.lastLogin){
    _perms = permissions.split(",");
  }

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
    );
  }

  bool hasPermission(String perm){
    return _perms.contains(perm);
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

  if (categoryId == null) {
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
    };
  }).toList();

  yield result;
});


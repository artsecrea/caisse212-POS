import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/database/app_database.dart' as db;
import 'database_providers.dart';
import 'settings_provider.dart';

class FavoriteProductsNotifier extends StateNotifier<Set<int>> {
  static const _key = 'favorite_product_ids';
  final SharedPreferences _prefs;

  FavoriteProductsNotifier(this._prefs) : super(const {}) {
    _load();
  }

  void _load() {
    final stored = _prefs.getStringList(_key) ?? [];
    state = stored.map((e) => int.tryParse(e)).whereType<int>().toSet();
  }

  Future<void> toggle(int productId) async {
    final updated = Set<int>.from(state);
    if (updated.contains(productId)) {
      updated.remove(productId);
    } else {
      updated.add(productId);
    }
    state = updated;
    await _prefs.setStringList(_key, updated.map((e) => e.toString()).toList());
  }
}

final favoriteProductsProvider =
    StateNotifierProvider<FavoriteProductsNotifier, Set<int>>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return FavoriteProductsNotifier(prefs);
});

// RAM-only: most recently used first (index 0 = most recent)
final lastUsedProductIdsProvider = StateProvider<List<int>>((ref) => const []);

// Virtual category sentinel for favorites
const int kFavoritesCategoryId = -2;

/// Drops in for [filteredProductsProvider] in ProductGrid.
/// Handles the virtual Favorites category (id = -2) and sort-by-last-used.
final displayedProductsProvider =
    Provider.autoDispose<AsyncValue<List<db.Product>>>((ref) {
  final selectedCategory = ref.watch(selectedCategoryProvider);
  final searchQuery = ref.watch(productSearchQueryProvider).trim().toLowerCase();
  final favorites = ref.watch(favoriteProductsProvider);
  final lastUsed = ref.watch(lastUsedProductIdsProvider);
  final settings = ref.watch(settingsProvider);

  // Favorites virtual category: pull all products, filter to favorites set
  if (selectedCategory == kFavoritesCategoryId) {
    final allAsync = ref.watch(productsByCategoryProvider(-1));
    return allAsync.when(
      data: (products) {
        var result = products.where((p) => favorites.contains(p.id)).toList();
        if (searchQuery.isNotEmpty) {
          result = result.where((p) {
            return p.name.toLowerCase().contains(searchQuery) ||
                (p.barcode?.toLowerCase().contains(searchQuery) ?? false);
          }).toList();
        }
        return AsyncValue.data(result);
      },
      loading: () => const AsyncValue.loading(),
      error: (e, s) => AsyncValue.error(e, s),
    );
  }

  // Regular category path — use existing filtered provider
  final productsAsync = ref.watch(filteredProductsProvider);

  return productsAsync.when(
    data: (products) {
      if (settings.sortByLastUsed && searchQuery.isEmpty && lastUsed.isNotEmpty) {
        // Sort: last-used first, then stable order for everything else
        final result = List<db.Product>.from(products);
        result.sort((a, b) {
          final ai = lastUsed.indexOf(a.id);
          final bi = lastUsed.indexOf(b.id);
          if (ai == -1 && bi == -1) return 0;
          if (ai == -1) return 1;
          if (bi == -1) return -1;
          return ai.compareTo(bi);
        });
        return AsyncValue.data(result);
      }
      return AsyncValue.data(products);
    },
    loading: () => const AsyncValue.loading(),
    error: (e, s) => AsyncValue.error(e, s),
  );
});

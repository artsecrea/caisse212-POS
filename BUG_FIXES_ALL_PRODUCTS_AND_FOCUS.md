# Bug Fixes - All Products & Search Focus

## Issues Fixed

### Issue 1: All Products Showing No Products ❌ → ✅

**Problem:**
When clicking "All Products" in full page category mode, the product grid would show "No products found" instead of displaying all available products.

**Root Cause:**
The `productsByCategoryProvider` didn't handle the special value `-1` (used for "All Products"). When `categoryId == -1`, it would try to filter products where `categoryId = -1`, which matched no products.

**Solution:**
Updated the `productsByCategoryProvider` to explicitly handle three cases:
- `categoryId == null` → Used for category selection mode (returns empty or all)
- `categoryId == -1` → **Special value for "All Products"** → Returns ALL active products
- `categoryId > 0` → Returns products filtered by specific category

**Code Changes:**
```dart
// Before:
if (categoryId == null) {
  return (database.select(database.products)
    ..where((tbl) => tbl.isActive.equals(true))
    ..watch()).watch();
}

return (database.select(database.products)
  ..where((tbl) => tbl.isActive.equals(true) & tbl.categoryId.equals(categoryId))
  ..watch()).watch();

// After:
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
```

**Files Modified:**
- `/lib/providers/database_providers.dart`

---

### Issue 2: Search Focus Lost When Returning to Main Screen ❌ → ✅

**Problem:**
When navigating away from the main screen and then returning (e.g., from Order Management, Payment Screen, etc.), the search bar would lose focus. Users would have to click on the search bar again to type.

**Root Cause:**
The `TopBar` widget's `initState()` was only called once when the widget was first created. When returning to the main screen, the widget was reused (not recreated), so `initState()` didn't run again to request focus.

**Solution:**
Added `didChangeDependencies()` lifecycle method to the `TopBar` widget to re-request focus every time the widget's dependencies change (which happens when navigating back to the screen).

Also extracted the focus request logic into a separate `_requestSearchFocus()` method for reusability and added a `canRequestFocus` check for safety.

**Code Changes:**
```dart
// Added:
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  // Re-request focus when returning to screen
  _requestSearchFocus();
}

void _requestSearchFocus() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _searchFocusNode.canRequestFocus) {
      _searchFocusNode.requestFocus();
    }
  });
}

// Updated initState to use the new method:
@override
void initState() {
  super.initState();
  _checkConnectivity();
  // ... connectivity listener ...
  
  // Sync search controller with provider
  _searchController.text = ref.read(productSearchQueryProvider);

  // Always focus search bar on init
  _requestSearchFocus(); // ✅ Using extracted method
}
```

**Files Modified:**
- `/lib/presentation/widgets/top_bar.dart`

---

## How It Works Now

### All Products Flow:
1. User is in full page category mode
2. Clicks "All Products" button
3. `selectedCategoryProvider` is set to `-1`
4. `productsByCategoryProvider(-1)` returns ALL active products
5. Product grid displays all available products ✅

### Search Focus Flow:
1. User navigates to main screen
2. `TopBar.initState()` calls `_requestSearchFocus()`
3. User navigates away (e.g., to Payment Screen)
4. TopBar widget stays mounted but loses focus
5. User navigates back to main screen
6. `TopBar.didChangeDependencies()` is triggered
7. `_requestSearchFocus()` is called again
8. Search bar regains focus automatically ✅

## Testing Checklist

- [x] "All Products" button shows all active products
- [x] Clicking a specific category shows only that category's products
- [x] Searching filters products correctly in all modes
- [x] Search bar has focus on initial load
- [x] Search bar regains focus when returning from other screens
- [x] Focus works after navigating to/from:
  - [x] Order Management
  - [x] Payment Screen
  - [x] Settings Dialog
  - [x] Session Management
  - [x] Tickets Management
- [x] No compilation errors
- [x] No console warnings during navigation

## User Benefits

1. **Predictable Behavior**: "All Products" actually shows all products now
2. **Better UX**: No need to manually click search bar after navigation
3. **Faster Workflow**: Can immediately start typing after returning to main screen
4. **Consistency**: Focus behavior is the same whether arriving from login or from other screens

## Files Changed

| File | Changes | Description |
|------|---------|-------------|
| `database_providers.dart` | Added `-1` handling | Fix All Products category |
| `top_bar.dart` | Added `didChangeDependencies()` | Auto-focus on return |

**Total**: 2 files, ~20 lines modified

---

**Implementation Date**: February 20, 2026  
**Status**: ✅ Fixed and Tested  
**Both issues**: Resolved


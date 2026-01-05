# Component Constraints Implementation

## Summary
This document describes the implementation of component constraints (min/max quantities, required components) in the product modification dialog.

## Changes Made

### 1. Database Schema Updates

#### File: `lib/data/database/tables/product_component_table.dart`
**Added Fields:**
- `minQuantity`: Minimum quantity required (default: 0)
- `maxQuantity`: Maximum quantity allowed (default: 10)

These fields were added to the `ProductComponents` table to store constraint information for each product-component relationship.

**Migration Required:**
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

---

### 2. Provider Updates

#### File: `lib/providers/database_providers.dart`
**Modified:** `productComponentsProvider`

**Before:** Returned `List<Component>`
**After:** Returns `List<Map<String, dynamic>>` containing:
```dart
{
  'component': Component,          // The component data
  'isRequired': bool,             // Whether component is required
  'minQuantity': int,             // Minimum quantity
  'maxQuantity': int,             // Maximum quantity
  'defaultPrice': double,         // Default price for this product-component
}
```

This change provides all necessary constraint information to the UI.

---

### 3. Product Modification Dialog

#### File: `lib/presentation/widgets/product_modification_dialog.dart`

**Key Changes:**

1. **Display Constraints**
   - Shows "REQUIRED" badge for required components (orange badge)
   - Displays min/max quantities below component name
   - Required components have orange background tint
   - Higher elevation for required component cards

2. **Enforce Constraints**
   - Initializes required components to `minQuantity` automatically
   - Prevents decrementing below `minQuantity`
   - Prevents incrementing above `maxQuantity`
   - Disable buttons when limits are reached (greyed out)

3. **Validation on Save**
   - Validates all required components meet minimum quantity
   - Shows error message if validation fails
   - Prevents saving until requirements are met

4. **Smart Component Saving**
   - **Only includes components where quantity differs from minimum**
   - Required components at minimum quantity are shown but NOT saved
   - Example: If cheese is required (min: 1) and user has 1 cheese, it's not saved
   - If user increases to 2 cheese, then it IS saved
   - Non-required components only saved if quantity > 0

**Visual Indicators:**
- Required components: Orange "REQUIRED" badge
- Orange background tint for required items
- Gray text showing "Min: X, Max: Y"
- Disabled buttons (gray) when limits reached

---

### 4. Product Grid Updates

#### File: `lib/presentation/widgets/product_grid.dart`

**Modified:** `_ProductCard.build()` method

**New Behavior:**
- **Single Click (Tap):**
  - Checks if product has any required components
  - If **YES** → Shows modification dialog (to configure required components)
  - If **NO** → Quick-add to order (as before)

- **Long Press:**
  - Always shows modification dialog (as before)

This ensures users can't skip required component selection.

---

### 5. Sample Data Updates

#### File: `lib/utils/sample_data_generator.dart`

**Updated:** `_generateProductComponents()` method

**Example Constraints Added:**

**Burgers (Products 1-4):**
- **Cheese (Component 1):** REQUIRED, Min: 1, Max: 3
- **Ketchup (Component 6):** REQUIRED, Min: 1, Max: 2
- Other components: Optional, Max: 5

**Pizzas (Products 5-8):**
- **Cheese (Component 1):** REQUIRED, Min: 1, Max: 4
- Other components: Optional, Max: 3

**Salads & Desserts:**
- All components optional
- Max: 3-5 depending on component

---

## User Experience Flow

### Scenario 1: Product with Required Components (e.g., Burger)

1. **User taps on Burger** → Dialog opens automatically
2. **Dialog shows:**
   - Cheese: "REQUIRED" badge, quantity starts at 1 (min)
   - Ketchup: "REQUIRED" badge, quantity starts at 1 (min)
   - Other toppings: Optional, quantity starts at 0
3. **User tries to save with defaults:**
   - ✅ Allowed (required minimums met)
   - Only modified components are saved (not cheese/ketchup at min)
4. **User adds extra cheese (quantity = 2):**
   - ✅ Extra cheese is saved
5. **User tries to remove all ketchup:**
   - ❌ Prevented (minus button disabled)

### Scenario 2: Product without Required Components (e.g., Drink)

1. **User taps on Drink** → Quick-added to order immediately
2. **User long-presses on Drink** → Dialog opens for optional modifications

### Scenario 3: Exceeding Maximum

1. **User has 3 cheese portions (max)**
2. **Plus button becomes disabled (gray)**
3. **Cannot add more**

---

## Technical Notes

### Component Quantity Logic

```dart
// Initial quantity for a component
final quantity = isRequired ? minQuantity : 0;

// Only save if quantity differs from default
if (componentQuantity > minQuantity || 
    (componentQuantity > 0 && minQuantity == 0)) {
  // Save this component
}
```

### Validation Logic

```dart
// Check all required components
for (var componentData in componentsData) {
  if (isRequired) {
    final currentQuantity = _componentQuantities[component.id] ?? 0;
    if (currentQuantity < minQuantity) {
      // Show error, prevent save
    }
  }
}
```

---

## Benefits

1. **Better Data Integrity:**
   - Ensures required components are always selected
   - Prevents excessive quantities

2. **Improved UX:**
   - Clear visual indicators for requirements
   - Auto-initialization of required components
   - Disabled buttons prevent invalid actions

3. **Cleaner Data:**
   - Only stores modifications from defaults
   - Reduces database bloat
   - Easier to track actual customizations

4. **Flexibility:**
   - Per-product component constraints
   - Different min/max for different products
   - Easy to configure via database

---

## Migration Instructions

After pulling these changes:

1. **Rebuild Database Schema:**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

2. **Regenerate Sample Data:**
   - Clear existing data or
   - Run data regeneration function

3. **Test Products:**
   - Try adding burgers (should show dialog)
   - Try adding drinks (should quick-add)
   - Test min/max enforcement

---

## Future Enhancements

Potential improvements:
- Component group constraints (e.g., "Choose 1 sauce")
- Dynamic pricing based on component selections
- Component dependencies (if X selected, require Y)
- Visual indicator of total extra cost
- Bulk component selection (select all, clear all)

---

## Files Modified

1. ✅ `lib/data/database/tables/product_component_table.dart`
2. ✅ `lib/providers/database_providers.dart`
3. ✅ `lib/presentation/widgets/product_modification_dialog.dart`
4. ✅ `lib/presentation/widgets/product_grid.dart`
5. ✅ `lib/utils/sample_data_generator.dart`

**Total:** 5 files modified

---

## Testing Checklist

- [ ] Required components show orange badge
- [ ] Required components initialize to minQuantity
- [ ] Cannot decrement below minQuantity
- [ ] Cannot increment above maxQuantity
- [ ] Validation prevents saving without required components
- [ ] Single tap on required-component product shows dialog
- [ ] Single tap on no-required-component product quick-adds
- [ ] Long press always shows dialog
- [ ] Components at default quantity are not saved
- [ ] Modified components are saved correctly
- [ ] Min/Max quantities display correctly

---

*Implementation completed: January 5, 2026*


# Component Pricing Technical Implementation

## Overview
This document explains the technical implementation of component pricing logic where only quantities beyond the minimum (default) are charged.

---

## Problem Statement

Previously, all components were charged regardless of whether they were at their default (minimum) quantity or not. 

**Example of the problem:**
- Burger costs €10 with default 1 cheese included
- User orders burger with 1 cheese
- System charges €10 + €2 (cheese) = €12 ❌ WRONG

**Required behavior:**
- Default components (at minQuantity) should be included in base price
- Only additional components (above minQuantity) should add cost
- User orders burger with 1 cheese → €10 ✅ CORRECT
- User orders burger with 2 cheese → €12 (base + 1 extra) ✅ CORRECT

---

## Data Model

### ProductComponent Table
```dart
class ProductComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer()();
  IntColumn get componentId => integer()();
  RealColumn get defaultPrice => real().withDefault(const Constant(0.0))();
  BoolColumn get isRequired => boolean().withDefault(const Constant(false))();
  IntColumn get minQuantity => integer().withDefault(const Constant(0))(); // ← KEY FIELD
  IntColumn get maxQuantity => integer().withDefault(const Constant(10))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
```

**Key Field:** `minQuantity`
- Defines the default/included quantity
- If component quantity ≤ minQuantity → No extra charge
- If component quantity > minQuantity → Charge only for (quantity - minQuantity)

### OrderProductComponent Table
```dart
class OrderProductComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get componentId => integer()();
  IntColumn get orderProductId => integer()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  RealColumn get price => real().withDefault(const Constant(0.0))(); // ← Effective price per unit
  BoolColumn get isSpecial => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
```

**Storage Strategy:**
- `quantity`: Store FULL quantity ordered (for accurate records and display)
- `price`: Store EFFECTIVE price per unit (calculated to only charge for extras)

---

## Implementation Details

### 1. Real-time Display Calculation

**Location:** `product_modification_dialog.dart` → `_calculateComponentTotal()`

```dart
double _calculateComponentTotal(List<dynamic> componentsData) {
  double total = 0.0;

  for (final entry in _componentQuantities.entries) {
    final componentId = entry.key;
    final quantity = entry.value;

    if (quantity > 0) {
      final componentData = componentsData.firstWhere(/*...*/);
      final component = componentData['component'];
      final minQuantity = (componentData['minQuantity'] as int?) ?? 0;
      
      if (component != null && component.price != null) {
        // Only charge for quantity beyond the minimum
        final chargeableQuantity = quantity > minQuantity 
            ? (quantity - minQuantity) 
            : 0;
        total += component.price * chargeableQuantity;
      }
    }
  }

  return total;
}
```

**Purpose:** Shows user the real-time component cost as they add/remove components

**Logic:**
1. Get selected quantity for each component
2. Get minQuantity from ProductComponent configuration
3. Calculate chargeableQuantity = max(0, quantity - minQuantity)
4. Total += componentPrice × chargeableQuantity

---

### 2. Saving Components to Order

**Location:** `product_modification_dialog.dart` → `_buildResult()` method

```dart
// When building selected components for the order
final componentPrice = component.price ?? 0.0;
final chargeableQuantity = componentQuantity > minQuantity 
    ? (componentQuantity - minQuantity) 
    : 0;

// Calculate effective price per unit
final effectivePricePerUnit = componentQuantity > 0 
    ? (componentPrice * chargeableQuantity) / componentQuantity 
    : 0.0;

selectedComponents.add(OrderItemComponent(
  componentId: component.id,
  name: component.name ?? 'Unknown',
  quantity: componentQuantity,        // Full quantity ordered
  price: effectivePricePerUnit,       // Adjusted price
  isSpecial: _componentSpecial[component.id] ?? false,
));
```

**Why use effectivePricePerUnit?**

The OrderItem model calculates componentTotal as:
```dart
double get componentTotal {
  return components.fold(0.0, (sum, comp) => sum + (comp.price * comp.quantity));
}
```

So we need: `effectivePricePerUnit × quantity = totalChargeableAmount`

**Example Calculation:**

Component: Cheese, minQty: 1, price: €2.00, ordered: 3

```
chargeableQuantity = 3 - 1 = 2
totalChargeableAmount = €2.00 × 2 = €4.00
effectivePricePerUnit = €4.00 / 3 = €1.333...

When stored:
  quantity: 3
  price: €1.333...

When calculated in componentTotal:
  €1.333... × 3 = €4.00 ✅ CORRECT
```

**Benefits of this approach:**
1. ✅ Full quantity is stored (accurate records for kitchen, receipts)
2. ✅ Price calculation works with existing code (no changes needed elsewhere)
3. ✅ componentTotal automatically calculates correctly
4. ✅ Receipts show correct information

---

### 3. Loading Components from Database

**Location:** Multiple places (order_provider.dart, daily_summary_service.dart, etc.)

```dart
// Get components from database
final orderComponents = await (database.select(database.orderProductComponents)
  ..where((tbl) => tbl.orderProductId.equals(product.id))
).get();

// Calculate component total
double componentTotal = 0.0;
for (final orderComp in orderComponents) {
  componentTotal += orderComp.price * orderComp.quantity;
}
```

**No changes needed!** Since we stored the effective price, the calculation works automatically.

---

## Examples

### Example 1: Component at Minimum (Default)

**Product:** Burger (€10)
**Component:** Cheese (price: €2, minQty: 1)
**User Selection:** Cheese × 1

**Calculation:**
```
chargeableQuantity = 1 - 1 = 0
effectivePricePerUnit = (€2 × 0) / 1 = €0

Stored in DB:
  quantity: 1
  price: €0

Order Total:
  Burger: €10
  Component: €0 × 1 = €0
  Total: €10 ✅
```

### Example 2: Component Above Minimum

**Product:** Burger (€10)
**Component:** Cheese (price: €2, minQty: 1)
**User Selection:** Cheese × 3

**Calculation:**
```
chargeableQuantity = 3 - 1 = 2
effectivePricePerUnit = (€2 × 2) / 3 = €1.333...

Stored in DB:
  quantity: 3
  price: €1.333...

Order Total:
  Burger: €10
  Component: €1.333... × 3 = €4
  Total: €14 ✅
```

### Example 3: Optional Component (minQty = 0)

**Product:** Burger (€10)
**Component:** Bacon (price: €3, minQty: 0)
**User Selection:** Bacon × 2

**Calculation:**
```
chargeableQuantity = 2 - 0 = 2
effectivePricePerUnit = (€3 × 2) / 2 = €3

Stored in DB:
  quantity: 2
  price: €3

Order Total:
  Burger: €10
  Component: €3 × 2 = €6
  Total: €16 ✅
```

### Example 4: Multiple Components

**Product:** Burger (€10)
**Components:**
- Cheese (€2, minQty: 1) → User selects 2
- Bacon (€3, minQty: 0) → User selects 1
- Lettuce (€0.5, minQty: 1) → User selects 1

**Calculations:**

Cheese:
```
chargeableQuantity = 2 - 1 = 1
effectivePricePerUnit = (€2 × 1) / 2 = €1
Component charge = €1 × 2 = €2
```

Bacon:
```
chargeableQuantity = 1 - 0 = 1
effectivePricePerUnit = (€3 × 1) / 1 = €3
Component charge = €3 × 1 = €3
```

Lettuce:
```
chargeableQuantity = 1 - 1 = 0
effectivePricePerUnit = (€0.5 × 0) / 1 = €0
Component charge = €0 × 1 = €0
```

**Order Total:**
```
Burger: €10
Components: €2 + €3 + €0 = €5
Total: €15 ✅
```

---

## Database Sync Protection

### Problem
During database sync, if the operation fails midway:
1. Components are deleted (clearMasterData)
2. Sync fails before re-inserting them
3. Components are lost ❌

### Solution: Transaction Wrapper

**Location:** `data_sync_service.dart` → `syncAllData()`

```dart
Future<void> syncAllData({int? dataRetentionDays}) async {
  try {
    // Wrap entire sync in a transaction - all or nothing
    await _database.transaction(() async {
      // Clear master data
      await clearMasterData();
      
      // Sync all data
      await _syncUsers();
      await _syncCategories();
      // ... etc
      await _syncComponents();
      await _syncProductComponents();
      // ... etc
    });
    
    onProgress?.call('Sync complete!', 1.0);
  } catch (e) {
    _logger.error('Sync failed: $e');
    throw Exception('Sync failed: $e');
  }
}
```

**How it works:**
1. `transaction()` starts a database transaction
2. All operations happen within the transaction
3. If ANY operation fails → entire transaction is rolled back
4. If ALL operations succeed → transaction is committed
5. Result: Either everything syncs or nothing changes ✅

**Additional Protection:** Deletion order optimized
```dart
Future<void> clearMasterData() async {
  // Delete in reverse order of dependencies
  await _database.delete(_database.kDSs).go();
  await _database.delete(_database.kiosks).go();
  await _database.delete(_database.areaTables).go();
  await _database.delete(_database.areas).go();
  await _database.delete(_database.productComponents).go(); // Child
  await _database.delete(_database.variantAttributeValues).go();
  await _database.delete(_database.productVariants).go();
  await _database.delete(_database.products).go(); // Parent
  await _database.delete(_database.components).go(); // Parent
  await _database.delete(_database.componentGroups).go();
  // etc...
}
```

---

## Code Flow Diagram

```
User Opens Modification Dialog
        ↓
Loads Product Components (with minQuantity)
        ↓
User Adjusts Component Quantities
        ↓
[_calculateComponentTotal() called]
   ├─ For each component:
   │  ├─ chargeableQty = qty - minQty
   │  └─ total += price × chargeableQty
   └─ Display total in UI
        ↓
User Confirms
        ↓
[_buildResult() called]
   ├─ For each component:
   │  ├─ chargeableQty = qty - minQty
   │  ├─ effectivePrice = (price × chargeableQty) / qty
   │  └─ Create OrderItemComponent(qty, effectivePrice)
   └─ Return to cart
        ↓
Order Saved to Database
   └─ OrderProductComponent table stores:
      ├─ quantity: full quantity ordered
      └─ price: effective price per unit
        ↓
Order Loaded Later
        ↓
[componentTotal calculated]
   └─ sum(comp.price × comp.quantity)
   └─ Returns correct total ✅
```

---

## Testing Validation

### Unit Test Example (Conceptual)

```dart
test('Component pricing at minimum quantity should be zero', () {
  final component = Component(id: 1, price: 2.0, minQuantity: 1);
  final quantity = 1;
  
  final chargeableQty = quantity > component.minQuantity 
      ? quantity - component.minQuantity 
      : 0;
  final total = component.price * chargeableQty;
  
  expect(total, equals(0.0));
});

test('Component pricing above minimum should charge for extras only', () {
  final component = Component(id: 1, price: 2.0, minQuantity: 1);
  final quantity = 3;
  
  final chargeableQty = quantity > component.minQuantity 
      ? quantity - component.minQuantity 
      : 0;
  final total = component.price * chargeableQty;
  
  expect(total, equals(4.0)); // 2 extras × €2
});
```

---

## Backward Compatibility

**Question:** What about existing orders in the database?

**Answer:** Existing orders are not affected because:
1. They already have stored `price` values in OrderProductComponents
2. These prices were calculated with the OLD logic (charging for all)
3. When loading those orders, we use the STORED prices, not recalculating
4. Only NEW orders created after the fix will use the new pricing logic

**Migration:** No database migration needed! The stored data structure hasn't changed.

---

## Future Enhancements

Potential improvements:

1. **Add Component Pricing Mode Setting**
   - Allow admin to choose: "Charge all" vs "Charge extras only"
   - Store preference in business settings
   - Apply accordingly

2. **Per-Component Pricing Mode**
   - Some components charge all, others charge extras only
   - Add `chargingMode` field to ProductComponents table

3. **Tiered Pricing**
   - First X included, next Y at 50% off, rest at full price
   - More complex but possible with same architecture

---

## Conclusion

The implementation successfully:
- ✅ Only charges for component quantities beyond minimum
- ✅ Maintains accurate records of what was ordered
- ✅ Works with existing code structure (minimal changes)
- ✅ Protects against data loss during sync operations
- ✅ No database migration required
- ✅ Backward compatible with existing orders


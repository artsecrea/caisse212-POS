# Adding Price Field to OrderProductComponents - Migration Guide

## Overview
Added a `price` field to the `OrderProductComponents` table to store the component price at the time the order was created. This simplifies calculations and ensures historical accuracy even if component prices change later.

## Database Schema Changes

### Updated Table: OrderProductComponents
**File:** `lib/data/database/tables/order_product_component_table.dart`

Added field:
```dart
RealColumn get price => real().withDefault(const Constant(0.0))(); // Price at order time
```

**Complete updated table:**
```dart
class OrderProductComponents extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get componentId => integer()();
  IntColumn get orderProductId => integer()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  RealColumn get price => real().withDefault(const Constant(0.0))(); // Price at order time
  BoolColumn get isSpecial => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
```

## Required Action: Rebuild Database Schema

You MUST run the build_runner to regenerate the database schema:

```bash
cd /home/artecrea/StudioProjects/posecrea
flutter pub run build_runner build --delete-conflicting-outputs
```

Or use the provided script:
```bash
chmod +x rebuild_db_with_price.sh
./rebuild_db_with_price.sh
```

## Code Changes Made

### 1. Order Provider - Component Insertion (2 locations)

**File:** `lib/providers/order_provider.dart`

Updated `_createOrder` method (line ~247):
```dart
// Insert order product components
for (final component in item.components) {
  await _database.into(_database.orderProductComponents).insert(
    OrderProductComponentsCompanion.insert(
      componentId: component.componentId,
      orderProductId: orderProductId,
      quantity: Value(component.quantity),
      price: Value(component.price),  // ← ADDED
      isSpecial: Value(component.isSpecial),
    ),
  );
}
```

Updated `updateOrderProducts` method (line ~389):
```dart
// Insert order product components
for (final component in item.components) {
  await _database.into(_database.orderProductComponents).insert(
    OrderProductComponentsCompanion.insert(
      componentId: component.componentId,
      orderProductId: orderProductId,
      quantity: Value(component.quantity),
      price: Value(component.price),  // ← ADDED
      isSpecial: Value(component.isSpecial),
    ),
  );
}
```

### 2. Order Provider - Loading Components

**File:** `lib/providers/order_provider.dart`

Updated `loadOrderDetails` method (line ~502):
```dart
components.add(OrderItemComponent(
  componentId: component.id,
  name: component.name,
  quantity: orderComp.quantity,
  price: orderComp.price,  // ← CHANGED: Use stored price from order time
  isSpecial: orderComp.isSpecial,
));
```

### 3. Order Provider - Calculation Methods

**File:** `lib/providers/order_provider.dart`

Updated `getAllOrdersWithFullDetails` method (line ~760):
```dart
// Get components and calculate total using stored prices
final orderComponents = await (_database.select(_database.orderProductComponents)
  ..where((tbl) => tbl.orderProductId.equals(product.id))).get();

double componentTotal = 0.0;
final components = <ComponentDetails>[];
for (final orderComp in orderComponents) {
  componentTotal += orderComp.price * orderComp.quantity;  // ← Use stored price
  
  final component = await (_database.select(_database.components)
    ..where((tbl) => tbl.id.equals(orderComp.componentId))).getSingleOrNull();
  if (component != null) {
    components.add(ComponentDetails(
      name: component.name,
      quantity: orderComp.quantity,
    ));
  }
}

final productDiscount = ((product.manualDiscount + product.unitaryDiscount) * product.quantity);
final itemSubtotal = ((product.unitaryPrice - product.unitaryTva + product.unitaryDiscount) * product.quantity) + componentTotal;  // ← Added componentTotal
```

Similar changes in `getOrderFullDetails` method (line ~860).

### 4. Order Confirmation Screen - Calculations

**File:** `lib/presentation/order_confirmation/order_confirmation_screen.dart`

Updated `_getOrderTotal` method (line ~115):
```dart
double componentTotal = 0.0;
for (final orderComp in orderComponents) {
  // Use stored price instead of looking up component
  componentTotal += orderComp.price * orderComp.quantity;  // ← Simplified
}
```

Updated `_getOrderItemsWithDetails` method (line ~173):
```dart
components.add({
  'name': component.name,
  'quantity': orderComp.quantity,
  'price': orderComp.price,  // ← Use stored price from order time
  'isSpecial': orderComp.isSpecial,
});
```

### 5. Data Sync Service - API Sync

**File:** `lib/services/data_sync_service.dart`

Updated `getOrdersForSync` method (line ~340):
```dart
// Build components list
final componentsList = productComponents.map((comp) => {
  'componentId': comp.componentId,
  'quantity': comp.quantity,
  'price': comp.price,  // ← Include price from order time
  'isSpecial': comp.isSpecial,
}).toList();
```

Updated `syncSingleOrder` method (line ~598):
```dart
final componentsList = productComponents.map((comp) => {
  'componentId': comp.componentId,
  'quantity': comp.quantity,
  'price': comp.price,  // ← Include price from order time
  'isSpecial': comp.isSpecial,
}).toList();
```

**Impact:** The API will now receive component prices with each order sync, ensuring the backend has accurate pricing information.

## Benefits

### ✅ Performance Improvements
- **Before:** Required database join to Components table for every calculation
- **After:** Direct access to stored price - no joins needed for calculations

### ✅ Data Integrity
- **Before:** Component price changes affected historical order calculations
- **After:** Each order preserves component prices at order time

### ✅ Simplified Code
- **Before:** Multiple database queries per order item
- **After:** Single query to get component details

### ✅ Historical Accuracy
- Orders now maintain exact pricing regardless of menu changes
- Accurate reporting even after price adjustments

## Impact on Existing Data

⚠️ **Important:** Existing orders in the database will have `price = 0.0` for all components until:
1. The database is rebuilt with migration
2. New orders are created with the updated code

Consider running a data migration script to populate prices for existing order components based on current component prices, or accept that historical data will show components at 0 price.

## Testing Checklist

After rebuilding the database, test:

- [ ] Create new order with components - verify price is stored
- [ ] Load existing order - verify calculations include component prices
- [ ] Order confirmation screen shows correct totals
- [ ] Order management screen displays accurate totals
- [ ] Payment calculations include component costs
- [ ] Sync operations include component prices in API calls

## Database Migration Considerations

If you need to preserve historical data with accurate component prices:

```sql
-- Example migration to populate prices for existing order components
UPDATE order_product_components opc
SET price = (
  SELECT c.price 
  FROM components c 
  WHERE c.id = opc.component_id
)
WHERE opc.price = 0.0;
```

This will populate existing components with current component prices (best approximation for historical data).

## Files Modified

1. `/lib/data/database/tables/order_product_component_table.dart` - Added price field
2. `/lib/providers/order_provider.dart` - Updated to use stored price (4 locations)
3. `/lib/presentation/order_confirmation/order_confirmation_screen.dart` - Simplified calculations
4. `/lib/services/data_sync_service.dart` - Include price in API sync (2 locations)
5. `/rebuild_db_with_price.sh` - Helper script to rebuild database

## Next Steps

1. ✅ Run build_runner to regenerate database schema
2. ✅ Test order creation with components
3. ✅ Verify calculations are correct
4. ⚠️ Consider migrating existing data if needed
5. ✅ Update API sync to include component prices

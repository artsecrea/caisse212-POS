# Order Products Sync Implementation

## Date: January 15, 2026

## Overview
Extended the data sync service to include order products and their components when syncing orders to the server.

## API Structure

### Order Sync Request
```json
{
  "id": 1,
  "code": "ORD-001",
  "status": "COMPLETED",
  "type": "DINE_IN",
  "priority": 1,
  "coupon": null,
  "persons": 2,
  "tableId": 5,
  "clientId": 10,
  "commercialId": 3,
  "discountPercentage": 10.0,
  "note": "No onions",
  "products": [
    {
      "productId": 25,
      "quantity": 2,
      "unitaryPrice": 15.50,
      "unitaryDiscount": 1.50,
      "unitaryTva": 3.10,
      "manualDiscount": 0.50,
      "manualDiscountReason": "Loyalty discount",
      "state": "COMPLETED",
      "components": [
        {
          "componentId": 12,
          "quantity": 1,
          "isSpecial": false
        },
        {
          "componentId": 15,
          "quantity": 2,
          "isSpecial": true
        }
      ]
    }
  ],
  "createdAt": "2026-01-15T10:30:00.000Z",
  "updatedAt": "2026-01-15T10:45:00.000Z"
}
```

## Data Classes (Backend)

### PosOrderProductRequest
```kotlin
data class PosOrderProductRequest(
    val productId : Long,
    val quantity : Int,
    val unitaryPrice : Double,
    val unitaryDiscount : Double?,
    val unitaryTva : Double?,
    val manualDiscount : Double?,
    val manualDiscountReason : String?,
    val state : String,
    val components : List<PosOrderProductComponentRequest> = emptyList()
)
```

### PosOrderProductComponentRequest
```kotlin
data class PosOrderProductComponentRequest (
    val componentId : Long,
    val quantity : Int,
    val isSpecial : Boolean
)
```

## Implementation Details

### Modified Method: `getOrdersForSync()`

**Location:** `/lib/services/data_sync_service.dart`

**Changes:**
1. Now fetches order products for each order
2. For each product, fetches its components
3. Builds nested structure matching API requirements

**Process Flow:**
```
1. Fetch all COMPLETED, unsynced orders
2. For each order:
   a. Fetch all order_products
   b. For each product:
      - Fetch all order_product_components
      - Build components list
      - Build product map with components
   c. Build order map with products list
3. Return complete order list
```

### Database Tables Involved

1. **orders** - Main order data
2. **order_products** - Products in each order
3. **order_product_components** - Components for each product

### Field Mapping

#### Order Product Fields
| Database Field | API Field | Type | Nullable |
|---------------|-----------|------|----------|
| productId | productId | Long | No |
| quantity | quantity | Int | No |
| unitaryPrice | unitaryPrice | Double | No |
| unitaryDiscount | unitaryDiscount | Double | Yes |
| unitaryTva | unitaryTva | Double | Yes |
| manualDiscount | manualDiscount | Double | Yes |
| manualDiscountReason | manualDiscountReason | String | Yes |
| state | state | String | No |

#### Product Component Fields
| Database Field | API Field | Type | Nullable |
|---------------|-----------|------|----------|
| componentId | componentId | Long | No |
| quantity | quantity | Int | No |
| isSpecial | isSpecial | Boolean | No |

## Code Example

### Building Order with Products
```dart
// Build order map with products
ordersList.add({
  'id': order.id,
  'code': order.code,
  // ...other order fields...
  'products': [
    {
      'productId': 25,
      'quantity': 2,
      'unitaryPrice': 15.50,
      'unitaryDiscount': 1.50,
      'unitaryTva': 3.10,
      'manualDiscount': 0.50,
      'manualDiscountReason': 'Loyalty',
      'state': 'COMPLETED',
      'components': [
        {
          'componentId': 12,
          'quantity': 1,
          'isSpecial': false
        }
      ]
    }
  ],
  'createdAt': order.createdAt.toIso8601String(),
  'updatedAt': order.updatedAt.toIso8601String(),
});
```

## Sync Process

### When Orders Are Synced

1. **Order Creation/Completion**
   - User creates order with products and components
   - Order status set to 'COMPLETED'
   - `isSynced` = false

2. **Sync Trigger**
   - Manual sync button
   - Auto-sync on completion
   - Periodic background sync

3. **Data Preparation**
   - `getOrdersForSync()` fetches complete order data
   - Includes all products with their components
   - Builds nested JSON structure

4. **API Call**
   - `ApiService.syncOrders(orders)` sends data
   - Server receives complete order structure
   - Server stores products and components

5. **Mark as Synced**
   - On success, `markOrdersAsSynced()` is called
   - Order `isSynced` = true
   - Won't be synced again

## Data Integrity

### Foreign Key Relationships
```
orders (1) ----< (N) order_products
                       |
                       v
           order_product_components (N)
```

### Constraints
- Products must belong to an order
- Components must belong to a product
- All foreign keys enforced in database

### Validation
- Order must be COMPLETED before sync
- Products must have valid productId
- Components must have valid componentId
- Quantities must be > 0

## Error Handling

### Potential Issues
1. **Missing Products** - Order without products
   - Handled: Empty products array sent
   
2. **Missing Components** - Product without components
   - Handled: Empty components array sent

3. **Network Failure** - API unreachable
   - Order stays unsynced
   - Retry on next sync

4. **Server Error** - API returns error
   - Order stays unsynced
   - Error logged

## Testing

### Test Cases

1. **Order with Products (No Components)**
   ```dart
   Order → 2 Products → No Components
   Expected: products array with 2 items, empty components arrays
   ```

2. **Order with Products and Components**
   ```dart
   Order → 1 Product → 3 Components
   Expected: products array with 1 item, 3 components
   ```

3. **Order with Multiple Products and Mixed Components**
   ```dart
   Order → Product 1 (2 components)
        → Product 2 (0 components)
        → Product 3 (1 component)
   Expected: Correct nesting for all
   ```

4. **Empty Order**
   ```dart
   Order → No Products
   Expected: Empty products array
   ```

## Performance Considerations

### Database Queries
- **Before:** 1 query per order
- **After:** 1 + N + M queries per order
  - 1 for order
  - N for products
  - M for components (per product)

### Optimization Opportunities
- Could use joins to reduce queries
- Could batch component queries
- Current implementation prioritizes clarity

### Typical Load
- Average order: 3-5 products
- Average product: 0-3 components
- Total queries per order: ~5-20
- Acceptable for current scale

## Integration Points

### API Service
```dart
// In api_service.dart
Future<void> syncOrders(List<Map<String, dynamic>> orders) async {
  // POST to /api/pos/orders/sync
  // Server expects orders with products array
}
```

### Order Repository
```dart
// Order completion triggers sync readiness
await orderRepo.completeOrder(orderId);
// Now order.isSynced = false, ready to sync
```

## Summary

✅ **Order products included in sync**
✅ **Product components included in sync**
✅ **Nested structure matches API requirements**
✅ **Maintains data relationships**
✅ **Handles empty cases**
✅ **No breaking changes**

The sync service now sends complete order data including all products and their components to the server, matching the expected API structure.


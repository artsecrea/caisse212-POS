# Product Discount System Fix

## Issues Fixed

### 1. **Two Discount Fields**
   - ✅ **Product Discount**: Built-in discount from product table (read-only)
   - ✅ **Manual Discount**: Additional discount applied by user (editable)

### 2. **Product Discount Always Has Value**
   - ✅ Product discount is now properly initialized from product data
   - ✅ Defaults to 0.0 if not set
   - ✅ Always displayed in the dialog when > 0

### 3. **Adding Product Directly**
   - ✅ Quick add (tap) now properly sets product discount
   - ✅ Manual discount defaults to 0.0
   - ✅ Long press opens dialog for modifications

## Changes Made

### 1. Product Modification Dialog (`product_modification_dialog.dart`)

#### New State Variables
```dart
late TextEditingController _manualDiscountController;  // For manual discount input
double _productDiscount = 0.0;  // Stores product's built-in discount
```

#### Initialization Logic
```dart
// Get product discount from product data
if (widget.product is OrderItem) {
  final item = widget.product as OrderItem;
  _productDiscount = item.discount;
  
  // Populate manual discount if editing
  if (item.manualDiscount > 0) {
    _manualDiscountController.text = item.manualDiscount.toStringAsFixed(2);
  }
} else {
  // New product - get discount from product table
  _productDiscount = widget.product.discountAmount ?? 0.0;
}
```

#### UI Changes - Price & Discount Tab

**Product Discount (Read-only)**
```
┌────────────────────────────────────────┐
│ 🏷️ Built-in Discount                   │
│ This discount is included              │
│                          -$2.00        │
└────────────────────────────────────────┘
```

**Manual Discount (Editable)**
```
┌────────────────────────────────────────┐
│ Additional Discount                    │
│ Apply an extra discount to this item   │
│                                         │
│ ┌──────────────┐  ┌────────────┐       │
│ │ 1.50         │  │ [$] [%]    │       │
│ └──────────────┘  └────────────┘       │
└────────────────────────────────────────┘
```

**Preview with Both Discounts**
```
┌────────────────────────────────────────┐
│ Preview                                 │
│ ─────────────────────────────────────  │
│ Original Price:           $10.00        │
│ Product Discount:         -$2.00        │
│ Manual Discount:          -$1.50        │
│ ─────────────────────────────────────  │
│ Final Price:              $6.50         │
└────────────────────────────────────────┘
```

#### Return Data Structure
```dart
{
  'components': List<OrderItemComponent>,
  'discount': double,          // Product discount
  'manualDiscount': double,    // Manual discount
  'note': String?
}
```

### 2. Order Panel (`order_panel.dart`)

Updated to handle both discount fields:
```dart
final updatedItem = item.copyWith(
  components: result['components'] as List<OrderItemComponent>?,
  discount: result['discount'] as double?,
  manualDiscount: result['manualDiscount'] as double?,
  note: result['note'] as String?,
);
```

### 3. Product Grid (`product_grid.dart`)

#### Quick Add (Tap)
```dart
_addToOrder(context, ref, {
  'components': <OrderItemComponent>[],
  'discount': product.discountAmount,     // ← Product discount
  'manualDiscount': 0.0,                   // ← No manual discount
  'note': null,
});
```

#### With Dialog (Long Press)
```dart
final result = await showDialog<Map<String, dynamic>>(...);
if (result != null) {
  _addToOrder(context, ref, result);  // ← Includes both discounts
}
```

## How It Works Now

### Scenario 1: Product with Built-in Discount
1. Product has `discountAmount = 2.00`
2. User taps product (quick add)
3. ✅ Item added with discount = $2.00, manualDiscount = $0.00
4. Total price: $10.00 - $2.00 = **$8.00**

### Scenario 2: Add Manual Discount
1. Product has `discountAmount = 2.00`
2. User long-presses product
3. Dialog opens showing:
   - Product Discount: $2.00 (read-only, green card)
   - Manual Discount: $0.00 (editable)
4. User enters manual discount: $1.50
5. Preview shows: $10.00 - $2.00 - $1.50 = **$6.50**
6. ✅ Item added with both discounts

### Scenario 3: Edit Existing Item
1. User clicks item in order panel
2. Dialog opens with current values:
   - Product Discount: $2.00 (shown in green card)
   - Manual Discount: $1.50 (pre-filled in text field)
3. User changes manual discount to $2.00
4. Preview updates: $10.00 - $2.00 - $2.00 = **$6.00**
5. ✅ Item updated with new manual discount

### Scenario 4: Percentage Discount
1. User opens dialog
2. Switches to percentage mode
3. Enters: 20%
4. Base price: $10.00
5. Manual discount calculated: $10.00 × 20% = $2.00
6. Final: $10.00 - $0.00 (no product discount) - $2.00 = **$8.00**

## Data Flow

### Adding New Product
```
Product Grid → Dialog → OrderItem
   ↓              ↓         ↓
discount:      discount:  discount: 2.00
  2.00          2.00       manualDiscount: 1.50
               manual: 
                1.50
```

### Editing Existing Item
```
OrderItem → Dialog → OrderItem
   ↓           ↓         ↓
discount:   Shown in  discount: 2.00
  2.00      green     manualDiscount: 2.00
manual:     card      (updated)
  1.50      Editable
```

## Price Calculation

### In OrderItem Model
```dart
double get subtotalPerItem {
  return (finalPrice - manualDiscount) + componentTotal;
}

double get totalDiscount {
  return (discount + manualDiscount) * quantity;
}
```

### Final Price Per Item
```
finalPrice - manualDiscount + components
```

### Total Discount Shown
```
(discount + manualDiscount) × quantity
```

## Visual Indicators

### Product Discount Card (Green)
- 🏷️ Icon
- "Built-in Discount" label
- Explanation text
- Amount in green

### Manual Discount Field (Orange/Default)
- 💵 Icon ($ or %)
- "Additional Discount" label
- Editable text field
- Toggle button for $ / %

### Preview Card (Orange)
- Shows all price components
- Product discount in green
- Manual discount in orange
- Final price in bold

## Benefits

### For Users
✅ **Clear Separation**: Product vs Manual discounts clearly distinguished
✅ **Visual Feedback**: Green card shows built-in discount
✅ **Flexible**: Can add extra discount on top of product discount
✅ **Live Preview**: See total savings before confirming

### For Business
✅ **Accurate Pricing**: Two discount types tracked separately
✅ **Promotion Support**: Product discounts for campaigns
✅ **Manager Override**: Manual discounts for special cases
✅ **Audit Trail**: Both discounts saved separately in database

### For Development
✅ **Type Safe**: Both fields properly typed
✅ **Backward Compatible**: Existing orders still work
✅ **Maintainable**: Clear separation of concerns
✅ **Extensible**: Easy to add more discount types

## Testing

### Test 1: Product with Discount
1. Create product with discount = $2.00
2. Tap to add
3. ✅ Verify: discount = $2.00, manualDiscount = $0.00

### Test 2: Add Manual Discount
1. Long press product
2. Enter manual discount: $1.50
3. ✅ Verify both discounts applied

### Test 3: Edit Item
1. Click item in order
2. Change manual discount
3. ✅ Verify update works

### Test 4: Percentage Discount
1. Open dialog
2. Switch to %
3. Enter 20
4. ✅ Verify calculation correct

### Test 5: No Product Discount
1. Product with discount = $0.00
2. Open dialog
3. ✅ Verify green card hidden
4. ✅ Manual discount still works

## Summary

The discount system now properly handles two types of discounts:

1. **Product Discount**: 
   - Always initialized from product data
   - Shown in green read-only card
   - Defaults to 0.0 if not set

2. **Manual Discount**:
   - Editable by user
   - Supports $ and % modes
   - Saved separately

Both discounts are:
- ✅ Properly initialized
- ✅ Correctly displayed
- ✅ Accurately calculated
- ✅ Properly saved

The system now works correctly whether adding products directly or through the modification dialog!


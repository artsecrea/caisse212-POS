# Order Calculation Fixes

## Problem Summary
The calculation logic in `order_models.dart` had several errors in how it computed subtotals, totals, and discounts.

## Understanding the Data Structure

### OrderItem Fields:
- **finalPrice**: Base price per item that INCLUDES TVA and has pre-discount already APPLIED
- **tva**: Tax amount per item
- **discount**: Pre-discount amount per item (already applied to finalPrice)
- **manualDiscount**: Manual discount per item (applied after everything else)
- **components**: Additional components with their own prices (no tax on these)
- **quantity**: Number of items

### Formula Breakdown:
```
finalPrice = (basePrice + tva - prediscount)
```

## Fixes Applied

### 1. OrderItem.subtotalPerItem ✅
**Purpose**: Get base price WITHOUT tax or any discounts (but WITH components)

**Formula**:
```dart
subtotalPerItem = (finalPrice - tva + discount) + componentTotal
```

**Explanation**: 
- `finalPrice - tva` removes the tax
- `+ discount` adds back the pre-discount to get original base price
- `+ componentTotal` adds component prices

### 2. OrderItem.totalPrice ✅
**Purpose**: Get total price for all quantities WITH all discounts applied

**Formula**:
```dart
totalPrice = ((finalPrice + componentTotal) - manualDiscount) * quantity
```

**Explanation**:
- `finalPrice + componentTotal` = price with tva and pre-discount, plus components
- `- manualDiscount` applies the manual discount
- `* quantity` multiplies by quantity

### 3. CurrentOrder.subtotal ✅
**Purpose**: Sum of all base prices (no tax, no discounts)

**Formula**:
```dart
subtotal = Σ(item.subtotalPerItem * item.quantity)
```

### 4. CurrentOrder.tax ✅
**Purpose**: Total tax for all items

**Formula**:
```dart
tax = Σ(item.totalTva)
where totalTva = item.tva * item.quantity
```

### 5. CurrentOrder.totalBeforeDiscount ✅
**Purpose**: Total with all item-level calculations (includes tva, pre-discounts, manual discounts, components)

**Formula**:
```dart
totalBeforeDiscount = Σ(item.totalPrice)
```

**Note**: `item.totalPrice` already includes quantity, so we don't multiply again

### 6. CurrentOrder.total ✅
**Purpose**: Final total with order-level discount

**Formula**:
```dart
total = totalBeforeDiscount - discountAmount
where discountAmount = totalBeforeDiscount * (discountPercentage / 100)
```

## Calculation Flow Example

### Example Order:
- Product A: basePrice = 100, tva = 20, pre-discount = 10, manual discount = 5, quantity = 2
- Component: price = 15, quantity = 1
- Order discount: 10%

### Step-by-step:
1. **finalPrice** = 100 + 20 - 10 = 110 (per item)
2. **componentTotal** = 15 * 1 = 15
3. **subtotalPerItem** = (110 - 20 + 10) + 15 = 115
4. **totalPrice** = ((110 + 15) - 5) * 2 = 120 * 2 = 240
5. **subtotal** = 115 * 2 = 230 (base price for order)
6. **tax** = 20 * 2 = 40
7. **totalBeforeDiscount** = 240
8. **discountAmount** = 240 * 0.1 = 24
9. **total** = 240 - 24 = 216

## Testing Checklist

- [ ] Subtotal shows correct base prices (no tax, no discounts)
- [ ] Tax calculation is accurate
- [ ] Manual discount applies correctly after components
- [ ] Order-level discount percentage applies correctly
- [ ] Payment screen shows correct totals
- [ ] Ticket generation has correct amounts
- [ ] Components are included in all calculations

## Files Modified
- `/lib/domain/models/order_models.dart` - Fixed all calculation getters

## Date
December 16, 2025


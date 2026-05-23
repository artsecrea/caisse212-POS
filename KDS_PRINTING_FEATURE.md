# KDS Smart Printing Feature

## Overview
The KDS (Kitchen Display System) printing feature now intelligently tracks which items have been sent to the kitchen and allows users to print either:
1. **Full Order** - All items in the order
2. **New Items Only** - Only items that haven't been printed to the kitchen yet

This prevents confusion in the kitchen when orders are modified and ensures the kitchen staff only receive tickets for new items.

---

## Database Changes

### New Field: `kdsPrintedAt`
Added to the `OrderProducts` table:
- **Type**: `DateTime?` (nullable)
- **Purpose**: Tracks when an item was sent to the kitchen
- **Default**: `null` (item not yet printed)
- **Updated**: Automatically set to current timestamp when KDS ticket is successfully printed

---

## How It Works

### 1. **Initial Order Creation**
```dart
// All items have kdsPrintedAt = null
Order {
  items: [
    OrderItem(name: "Burger", kdsPrintedAt: null),
    OrderItem(name: "Fries", kdsPrintedAt: null),
  ]
}
```

### 2. **First KDS Print**
When user prints KDS tickets (mode: `modificationsOnly`):
- Items grouped by station
- Separate ticket printed for each station
- After successful print, all items marked with timestamp

```dart
// After printing
Order {
  items: [
    OrderItem(name: "Burger", kdsPrintedAt: 2024-05-23 10:30:00),
    OrderItem(name: "Fries", kdsPrintedAt: 2024-05-23 10:30:00),
  ]
}
```

### 3. **Order Modification**
User reloads order and adds new items:
```dart
Order {
  items: [
    OrderItem(name: "Burger", kdsPrintedAt: 2024-05-23 10:30:00),  // Already printed
    OrderItem(name: "Fries", kdsPrintedAt: 2024-05-23 10:30:00),   // Already printed
    OrderItem(name: "Salad", kdsPrintedAt: null),                  // NEW - not printed
    OrderItem(name: "Drink", kdsPrintedAt: null),                  // NEW - not printed
  ]
}
```

### 4. **Second KDS Print (Modifications Only)**
Only new items are printed:
```
*** KITCHEN STATION ***
=== NEW ITEMS ===
ORDER #12345
...
1x Salad
1x Drink
```

The kitchen receives ONLY the new items, preventing confusion.

---

## Print Modes

### KdsPrintMode Enum
```dart
enum KdsPrintMode {
  full,                // Print all items
  modificationsOnly,   // Print only unprinted items
}
```

### Usage
```dart
await printingService.printKdsTicket(
  order: currentOrder,
  cashierName: "John",
  mode: KdsPrintMode.modificationsOnly, // or KdsPrintMode.full
);
```

---

## User Interface

### Print Options Dialog
The print options dialog now includes:

1. **Customer Receipt** checkbox
2. **Kitchen Ticket (KDS)** checkbox
3. **KDS Print Mode** (only visible when KDS is checked):
   - 📄 **New Items Only** 
     - Shows count: "3 new item(s) will be printed"
     - Default when unprinted items exist
   - 📋 **Full Order**
     - Shows count: "All 5 item(s) will be printed"
     - Default when all items already printed

### Visual Indicators on Tickets

#### Modifications Only Mode
```
*** KITCHEN STATION ***
=== NEW ITEMS ===        <- Inverted colors banner
ORDER #12345
...
```

#### Full Mode
```
*** KITCHEN STATION ***
ORDER #12345
...
```

---

## Practical Scenarios

### Scenario 1: New Order
**User Action**: Create order with 3 items → Print KDS
**Result**: All 3 items printed, each marked with timestamp
**Kitchen Receives**: 3 items

### Scenario 2: Order Modification
**User Action**: 
1. Load existing order (3 items already printed)
2. Add 2 new items
3. Print KDS with "New Items Only"

**Result**: Only 2 new items printed
**Kitchen Receives**: Only the 2 new items, clearly marked as "NEW ITEMS"

### Scenario 3: Reprint Full Order
**User Action**: Select "Full Order" mode and print
**Result**: All 5 items reprinted
**Kitchen Receives**: Complete order for reference

### Scenario 4: Order with No Changes
**User Action**: Try to print KDS with "New Items Only"
**Result**: "No items to print" - success without printing
**Kitchen Receives**: Nothing (avoiding duplicate tickets)

---

## Station Grouping

Items are automatically grouped by station. Example:

**Order Items**:
- Burger (Station: Grill)
- Fries (Station: Fryer)
- Salad (Station: Cold Kitchen)
- Drink (Station: Bar)

**Printed Tickets** (4 separate tickets):
1. **GRILL STATION** → Burger
2. **FRYER STATION** → Fries
3. **COLD KITCHEN STATION** → Salad
4. **BAR STATION** → Drink

Each station only receives their relevant items!

---

## Code Implementation

### 1. Database Migration
```dart
// Added to OrderProducts table
DateTimeColumn get kdsPrintedAt => dateTime().nullable();
```

### 2. OrderItem Model
```dart
class OrderItem {
  final DateTime? kdsPrintedAt;
  // ... other fields
}
```

### 3. Printing Service
```dart
// Filter items by mode
List<OrderItem> _filterItemsByMode(List<OrderItem> items, KdsPrintMode mode) {
  switch (mode) {
    case KdsPrintMode.full:
      return items;
    case KdsPrintMode.modificationsOnly:
      return items.where((item) => item.kdsPrintedAt == null).toList();
  }
}

// Mark items as printed
Future<void> _markItemsAsPrinted(AppDatabase database, List<OrderItem> items) async {
  final now = DateTime.now();
  for (final item in items) {
    if (item.id != null) {
      await database.update(database.orderProducts)
        .write(OrderProductsCompanion(kdsPrintedAt: Value(now)));
    }
  }
}
```

---

## Testing Checklist

- [ ] Create new order and print KDS → All items marked as printed
- [ ] Reload order, add items, print "New Items Only" → Only new items printed
- [ ] Print "Full Order" → All items printed
- [ ] Try "New Items Only" when no new items → No print, success message
- [ ] Verify station grouping works correctly
- [ ] Check visual "NEW ITEMS" banner appears in modifications-only mode
- [ ] Verify timestamps are correctly saved in database
- [ ] Test with items having no station assigned

---

## Benefits

✅ **Reduces Kitchen Confusion** - Kitchen only sees new items when order is modified
✅ **Saves Paper** - Avoids reprinting entire order for small changes
✅ **Improves Workflow** - Clear visual indicators distinguish new vs. full orders
✅ **Flexible** - User can choose full reprint when needed
✅ **Automatic** - Smart default suggestions based on order state

---

## Future Enhancements

Consider adding:
- Manual "Mark as Unprinted" option for reprinting specific items
- KDS reprint history log
- Support for quantity changes (print delta)
- Station-specific print modes
- Automatic reprint on item cancellation

---

## Troubleshooting

**Q: Items showing as "already printed" but kitchen didn't receive**
**A**: Use "Full Order" mode to reprint everything

**Q: No items appear when using "New Items Only"**
**A**: All items already printed. Use "Full Order" mode or add new items.

**Q: Want to reset print status**
**A**: Manually update database or delete and re-add items

**Q: Printer failed but items marked as printed**
**A**: Items only marked on successful print. If print fails, try again.


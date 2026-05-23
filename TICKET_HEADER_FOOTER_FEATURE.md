# Ticket Header/Footer Feature & Order Management Fix

## Summary

Two major enhancements were implemented:

1. **Configurable Ticket Header/Footer**: Users can now configure custom header and footer text that will be printed on all ticket receipts
2. **Order Management Actions Fix**: Fixed a bug where action buttons (edit, status, cancel, delete) were not showing for open/unpaid orders

---

## Changes Made

### 1. AppSettings Model (`lib/domain/models/app_settings.dart`)

**Added Fields:**
- `ticketHeader: String` - Header text to print at top of ticket
- `ticketFooter: String` - Footer text to print at bottom of ticket

**Updated Methods:**
- `copyWith()` - Added ticketHeader and ticketFooter parameters
- `toJson()` - Added serialization for new fields  
- `fromJson()` - Added deserialization for new fields (also fixed missing `language` parameter)

**Defaults:**
- Both ticketHeader and ticketFooter default to empty strings

---

### 2. Settings Provider (`lib/providers/settings_provider.dart`)

**Added Keys:**
```dart
static const String ticketHeader = 'ticket_header';
static const String ticketFooter = 'ticket_footer';
```

**Added Methods:**
```dart
Future<void> setTicketHeader(String header)
Future<void> setTicketFooter(String footer)
```

**Updated _loadSettings():**
- Loads ticketHeader and ticketFooter from SharedPreferences

---

### 3. Printing Service (`lib/services/printing_service.dart`)

**Added Import:**
```dart
import 'package:caisse212/providers/settings_provider.dart';
```

**Updated `printTicketReceipt()`:**

**Header Section (after logo, before store name):**
```dart
// Print custom header text if configured
if (_ref != null) {
  try {
    final settings = _ref!.read(settingsProvider);
    if (settings.ticketHeader.isNotEmpty) {
      bytes += generator.text(
        settings.ticketHeader,
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
      bytes += generator.emptyLines(1);
    }
  } catch (e) {
    debugPrint('Error reading ticket header from settings: $e');
  }
}
```

**Footer Section (after "Thank you!", before final cut):**
```dart
// Print custom footer text if configured  
if (_ref != null) {
  try {
    final settings = _ref!.read(settingsProvider);
    if (settings.ticketFooter.isNotEmpty) {
      bytes += generator.emptyLines(1);
      bytes += generator.text(
        settings.ticketFooter,
        styles: PosStyles(
          align: PosAlign.center,
          height: _resolveTextSize(),
          width: _resolveTextSize(),
        ),
      );
    }
  } catch (e) {
    debugPrint('Error reading ticket footer from settings: $e');
  }
}
```

---

### 4. Settings Screen (`lib/presentation/settings/settings_screen.dart`)

**Added Navigation Item:**
- New "Printing" section in settings navigation (index 7)
- Icon: `Icons.print`

**Added `_buildPrintingContent()` Method:**

Displays two text input fields:
1. **Ticket Header**
   - Multi-line TextField (3 lines)
   - Saves to settings on change
   - Displayed at top of receipts after logo

2. **Ticket Footer**  
   - Multi-line TextField (3 lines)
   - Saves to settings on change
   - Displayed at bottom of receipts before barcode

**Required Localization Keys:**
- `printing` - "Printing"
- `printing_settings` - "Printing Settings"
- `printing_settings_subtitle` - "Configure ticket printing options"
- `ticket_header` - "Ticket Header"
- `ticket_header_subtitle` - "Text to print at the top of receipts"
- `ticket_header_hint` - "e.g., Welcome to our store!"
- `ticket_footer` - "Ticket Footer"
- `ticket_footer_subtitle` - "Text to print at the bottom of receipts"
- `ticket_footer_hint` - "e.g., Thank you for your visit!"

---

### 5. Orders Management Screen (`lib/presentation/widgets/orders_management_screen.dart`)

**Fixed Bug in Action Menu:**

**Before (Lines 857-868):**
```dart
if (isUnpaid)
  PopupMenuItem(value: 'pay', ...)
else if (!isZLocked) ...[  // ❌ This prevented actions from showing for unpaid orders
  if (canUpdate) PopupMenuItem(value: 'edit', ...)
  // ... other actions
]
```

**After (Lines 857-868 and 972-1028):**
```dart
if (isUnpaid)
  PopupMenuItem(value: 'pay', ...)
if (!isZLocked) ...[  // ✅ Now shows actions for both paid and unpaid orders
  if (canUpdate) PopupMenuItem(value: 'edit', ...)  
  if (canUpdate) PopupMenuItem(value: 'status', ...)
  if (canUpdate) PopupMenuItem(value: 'cancel', ...)
  if (canDelete) PopupMenuItem(value: 'delete', ...)
]
```

**Impact:**
- Unpaid orders now show: View, Pay, Edit, Change Status, Cancel, Delete (if permitted)
- Paid orders (not Z-locked) show: View, Edit, Change Status, Cancel, Delete (if permitted)
- Z-locked orders only show: View, Pay (if unpaid)

---

## Usage

### Configure Ticket Header/Footer

1. Open Settings (gear icon in top bar)
2. Navigate to "Printing" section
3. Enter desired header text (e.g., "Welcome to ABC Restaurant")
4. Enter desired footer text (e.g., "Visit us again!")
5. Changes save automatically
6. Next printed receipt will include the configured text

### Example Receipt Layout

```
[LOGO]
Welcome to ABC Restaurant     <-- Header (if configured)

ABC RESTAURANT
PAYMENT RECEIPT
===============
Ticket #123
Order: ORD-2024-001
Date: 2024-05-23 14:30
Cashier: John Doe
Payment: CASH

2x Burger               25.00 DH
  + 2x Cheese
1x Fries                10.00 DH
===============
PAID:                   35.00 DH

Thank you!
Visit us again!          <-- Footer (if configured)

ORD-2024-001
[BARCODE]
```

---

## Testing Checklist

- [x] Settings screen displays Printing section
- [x] Ticket header text field saves to SharedPreferences 
- [x] Ticket footer text field saves to SharedPreferences
- [x] Empty header/footer doesn't print extra blank lines
- [x] Header appears after logo, before store name
- [x] Footer appears after "Thank you!", before barcode
- [x] Multi-line text is supported
- [x] Order management actions show for unpaid orders
- [x] Order management actions show for paid (non-Z-locked) orders
- [x] Z-locked orders only show View/Pay actions

---

## Migration Notes

**No database migration required** - settings are stored in SharedPreferences.

Existing installations will have empty header/footer by default. Users can configure them in Settings > Printing.

---

## Files Modified

1. `lib/domain/models/app_settings.dart` - Added ticketHeader/Footer fields
2. `lib/providers/settings_provider.dart` - Added setters and keys
3. `lib/services/printing_service.dart` - Added header/footer printing logic
4. `lib/presentation/settings/settings_screen.dart` - Added Printing section UI
5. `lib/presentation/widgets/orders_management_screen.dart` - Fixed action menu logic

---

## Future Enhancements

- [ ] Rich text formatting options (bold, underline)
- [ ] Multiple language support for header/footer
- [ ] Preview ticket before printing
- [ ] Template variables (e.g., {{date}}, {{store_name}})
- [ ] Different headers/footers for receipt vs KDS tickets


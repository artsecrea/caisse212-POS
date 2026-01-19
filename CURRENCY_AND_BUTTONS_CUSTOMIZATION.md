# Customizable Currency and Action Buttons Implementation

## Date: January 15, 2026

## Overview
Implemented customizable currency settings and configurable action buttons visibility in the POS system. Users can now select their preferred currency symbol and show/hide specific action buttons to customize their workflow.

## Features Implemented

### 1. Customizable Currency
- **Currency Symbol Setting**: Users can choose from 8 common currencies
- **Available Currencies**:
  - $ (US Dollar) - Default
  - € (Euro)
  - £ (British Pound)
  - DH (Moroccan Dirham)
  - ₹ (Indian Rupee)
  - ¥ (Japanese Yen)
  - CHF (Swiss Franc)
  - R (South African Rand)

### 2. Customizable Action Buttons
Users can show/hide the following action buttons:
- ✅ Table Selection Button
- ✅ Customer Selection Button
- ✅ Commercial Selection Button
- ✅ Coupon Button
- ✅ Manual Discount Button
- ✅ Print Button

### 3. Scrollable Action Buttons
- Action buttons container is now scrollable horizontally
- Prevents UI overflow when many buttons are visible
- Smooth scrolling experience

## Files Modified

### Core Models & Settings

#### 1. `/lib/domain/models/app_settings.dart`
**Added Properties:**
```dart
final String currency;              // Default: '$'
final bool showTableButton;         // Default: true
final bool showCustomerButton;      // Default: true
final bool showCommercialButton;    // Default: true
final bool showCouponButton;        // Default: true
final bool showDiscountButton;      // Default: true
final bool showPrintButton;         // Default: true
```

#### 2. `/lib/providers/settings_provider.dart`
**Added Keys:**
- `currency`
- `showTableButton`
- `showCustomerButton`
- `showCommercialButton`
- `showCouponButton`
- `showDiscountButton`
- `showPrintButton`

**Added Methods:**
```dart
Future<void> setCurrency(String currency)
Future<void> setShowTableButton(bool value)
Future<void> setShowCustomerButton(bool value)
Future<void> setShowCommercialButton(bool value)
Future<void> setShowCouponButton(bool value)
Future<void> setShowDiscountButton(bool value)
Future<void> setShowPrintButton(bool value)
```

### UI Components

#### 3. `/lib/presentation/settings/settings_screen.dart`
**Added Sections:**
- **Currency Section**: Visual currency selector with symbol and name
- **Action Buttons Visibility Section**: Toggle switches for each button

**Features:**
- Currency displayed as chips with symbol and currency name
- Selected currency highlighted with primary color
- Toggle switches for each action button
- All settings persist automatically

#### 4. `/lib/presentation/main_screen/main_screen.dart`
**Changes:**
- Made action buttons container scrollable (`SingleChildScrollView`)
- Added proper spacing between buttons (`SizedBox(width: 8)`)
- Wrapped buttons with conditional visibility based on settings:
  ```dart
  if (settings.showTableButton) _buildActionButton(...)
  if (settings.showCustomerButton && hasPermission) _buildActionButton(...)
  ```
- Combined permission checks with visibility settings

#### 5. `/lib/presentation/widgets/order_panel.dart`
**Changes:**
- Integrated `currencyFormatterProvider`
- Replaced all hardcoded `$` symbols with `currencyFormatter.format()`
- Updated price displays:
  - Item prices
  - Subtotal
  - Discount amounts
  - Tax
  - Total

### Utilities

#### 6. `/lib/utils/currency_formatter.dart` (NEW)
**Created utility class for currency formatting:**
```dart
class CurrencyFormatter {
  final String symbol;
  
  String format(double amount)      // e.g., "$10.50"
  String formatWhole(double amount) // e.g., "$10"
}
```

**Providers:**
- `currencyFormatterProvider` - Full formatter with methods
- `currencySymbolProvider` - Just the symbol string

## How It Works

### Currency System
1. User selects currency in Settings
2. Selection saved to SharedPreferences
3. `CurrencyFormatter` provider watches settings
4. All price displays use `currencyFormatter.format(amount)`
5. Currency updates instantly across the app

### Action Buttons Visibility
1. User toggles button visibility in Settings
2. Settings saved to SharedPreferences
3. Main screen reads settings state
4. Buttons conditionally rendered based on:
   - Settings visibility flag
   - Permission checks (if applicable)
5. Hidden buttons don't take up space

### Scrollable Buttons
1. Action buttons wrapped in `SingleChildScrollView`
2. Horizontal scrolling enabled
3. Proper spacing with `SizedBox` between buttons
4. No UI overflow even with all buttons visible

## Usage Examples

### In Settings (User Perspective)
```
Settings > Currency > Select "€"
Settings > Action Buttons Visibility > Toggle "Print Button" OFF
```

### In Code (Developer Perspective)
```dart
// Use currency formatter
final formatter = ref.watch(currencyFormatterProvider);
Text(formatter.format(99.99)) // Shows: "€99.99"

// Get currency symbol only
final symbol = ref.watch(currencySymbolProvider);
Text('$symbol 100') // Shows: "€ 100"

// Check button visibility
if (settings.showPrintButton && hasPermission(Permissions.printing))
  PrintButton()
```

## Settings Screen Layout

```
┌─────────────────────────────────────────┐
│ Settings                           [X]  │
├─────────────────────────────────────────┤
│ Appearance                              │
│ ☑ Dark Mode                            │
│                                         │
│ Display                                 │
│ ☑ Show Product Images                  │
│ Category Display: [Top Bar] [Full]     │
│                                         │
│ Order Defaults                          │
│ Order Type: [Dine In] [Take Away]      │
│ Order Status: [Pending ▼]              │
│                                         │
│ Currency                                │
│ [$] [€] [£] [DH] [₹] [¥] [CHF] [R]    │
│                                         │
│ Action Buttons Visibility               │
│ ☑ Table Button                         │
│ ☑ Customer Button                      │
│ ☑ Commercial Button                    │
│ ☑ Coupon Button                        │
│ ☑ Discount Button                      │
│ ☑ Print Button                         │
│                                         │
│        [Reset to Defaults]              │
└─────────────────────────────────────────┘
```

## Benefits

### For Users
✅ **Flexibility**: Customize UI to match workflow
✅ **Localization**: Use local currency symbol
✅ **Cleaner UI**: Hide unused buttons
✅ **Better UX**: No button overflow issues
✅ **Instant Updates**: Changes apply immediately

### For Business
✅ **Multi-Region**: Single app for different currencies
✅ **Role-Based UI**: Hide features based on role
✅ **Training**: Simplified UI for new employees
✅ **Efficiency**: Faster operations with relevant buttons only

## Testing

### Test Scenarios

1. **Currency Change**
   - ✅ Change currency in settings
   - ✅ Verify order panel shows new currency
   - ✅ Add items and check prices display correctly
   - ✅ Check totals, discounts, tax all use new currency

2. **Button Visibility**
   - ✅ Hide all buttons and verify clean UI
   - ✅ Show only essential buttons
   - ✅ Verify hidden buttons don't appear
   - ✅ Check spacing is correct

3. **Scrolling**
   - ✅ Enable all buttons
   - ✅ Verify horizontal scroll works
   - ✅ Check buttons don't overflow
   - ✅ Test on different screen sizes

4. **Permissions + Visibility**
   - ✅ User without print permission: button hidden regardless of settings
   - ✅ User with permission but button hidden: button hidden
   - ✅ User with permission and button visible: button shown

### Sample Test Data

**Currency Test:**
```dart
// Change to Euro
settings.currency = '€'

// Expected displays:
Price: €15.50 (not $15.50)
Subtotal: €45.00
Total: €52.00
```

**Button Visibility Test:**
```dart
// Hide discount and print
settings.showDiscountButton = false
settings.showPrintButton = false

// Expected: Only 4 buttons visible:
// [Persons] [Type] [Table] [Customer]
```

## Migration Notes

### Existing Data
- Existing installations will use default currency ($)
- All buttons visible by default
- No data migration required
- Settings automatically created on first access

### Upgrading
1. Settings load with defaults if not set
2. Currency formatter automatically uses setting
3. Action buttons check settings state
4. No manual intervention needed

## Future Enhancements

### Possible Additions
- 🔮 Custom currency symbol input
- 🔮 Currency position (prefix/suffix)
- 🔮 Decimal places configuration
- 🔮 Thousands separator customization
- 🔮 Button reordering (drag & drop)
- 🔮 Custom button labels
- 🔮 Button size configuration

## Technical Details

### State Management
- Settings stored in SharedPreferences
- Riverpod StateNotifier for settings state
- Automatic persistence on change
- Reactive UI updates

### Performance
- Minimal overhead (simple string operations)
- Settings loaded once on app start
- Cached in memory during session
- No database queries needed

### Compatibility
- Works with all existing features
- Compatible with permission system
- No breaking changes
- Backwards compatible

## Summary

✅ **Customizable currency** with 8 common options
✅ **Configurable action buttons** (show/hide 6 buttons)
✅ **Scrollable button container** (no overflow)
✅ **Integrated with permissions** (double protection)
✅ **Persistent settings** (saved to SharedPreferences)
✅ **Instant updates** (reactive state management)
✅ **Clean UI** (visual currency selector)
✅ **Easy to use** (toggle switches)

The system is now more flexible and can adapt to different business needs and regional requirements! 🎉


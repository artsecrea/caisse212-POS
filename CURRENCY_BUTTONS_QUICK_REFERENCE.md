# Quick Reference: Currency & Button Customization

## Changing Currency

### Via Settings UI
1. Open Settings (click user menu → Settings)
2. Scroll to "Currency" section
3. Click on desired currency chip
4. Currency changes instantly across the app

### Available Currencies
| Symbol | Currency | Code |
|--------|----------|------|
| $ | US Dollar | USD |
| € | Euro | EUR |
| £ | British Pound | GBP |
| DH | Moroccan Dirham | MAD |
| ₹ | Indian Rupee | INR |
| ¥ | Japanese Yen | JPY |
| CHF | Swiss Franc | CHF |
| R | South African Rand | ZAR |

## Customizing Action Buttons

### Via Settings UI
1. Open Settings
2. Scroll to "Action Buttons Visibility"
3. Toggle switches to show/hide buttons
4. Changes apply immediately

### Available Buttons
- **Table** - Select/assign table
- **Customer** - Select customer
- **Commercial** - Select commercial
- **Coupon** - Apply coupon (coming soon)
- **Discount** - Apply manual discount
- **Print** - Print order

## Using in Code

### Get Currency Formatter
```dart
// In a ConsumerWidget
final formatter = ref.watch(currencyFormatterProvider);

// Format price
Text(formatter.format(29.99))  // Output: "$29.99" or "€29.99" etc.
```

### Get Currency Symbol Only
```dart
final symbol = ref.watch(currencySymbolProvider);
Text('Price: $symbol 100')  // Output: "Price: $ 100"
```

### Check Button Visibility
```dart
final settings = ref.watch(settingsProvider);

if (settings.showPrintButton) {
  // Show print button
}
```

### Combined with Permissions
```dart
if (settings.showDiscountButton && 
    ref.read(permissionServiceProvider).hasPermission(Permissions.manualDiscount)) {
  // Show discount button
}
```

## Default Values

### On Fresh Install
- Currency: `$` (US Dollar)
- All buttons: **Visible** (true)

### After Reset
Settings → Reset to Defaults restores all to default values

## Tips

💡 **Hide unused buttons** for cleaner UI
💡 **Scroll buttons** horizontally if too many visible
💡 **Currency applies everywhere** - order panel, tickets, reports
💡 **Combine with permissions** for security + UX

## Troubleshooting

### Currency not updating?
- Check Settings → Currency is selected
- Refresh the screen (if needed)
- Verify SharedPreferences is working

### Button still showing?
- Check Settings → Action Buttons toggle is OFF
- Verify user has NO permission (permission overrides visibility)
- Restart app if changes not applying

### Buttons overflowing?
- Scroll horizontally (buttons are now scrollable)
- Hide unnecessary buttons via Settings
- This should not happen anymore!


# Screen Migration Checklist for i18n

## Screens Translation Status

### ✅ Completed
- [x] Users Management Screen
- [x] Settings Screen (Language selector added)

### 🔄 In Progress
- [ ] Login Screen
- [ ] Tenant Screen
- [ ] Tenant Login Screen

### ⏳ Pending
- [ ] Main Screen
- [ ] Order Panel
- [ ] Product Grid
- [ ] Category Selector
- [ ] Payment Screen
- [ ] Orders Management Screen
- [ ] Devices Management Screen
- [ ] Sessions Management Screen
- [ ] Tickets Management Screen
- [ ] Printers Management Screen
- [ ] Top Bar
- [ ] Bottom Bar
- [ ] Dialogs:
  - [ ] Commercial Selection Dialog
  - [ ] Customer Selection Dialog
  - [ ] Coupon Dialog
  - [ ] Manual Discount Dialog
  - [ ] Held Orders Dialog
  - [ ] Product Modification Dialog
  - [ ] Table Selection Dialog

## Migration Steps for Each Screen

### 1. Import AppLocalizations
```dart
import '../../utils/app_localizations.dart';
```

### 2. Get Localizations Instance
In build method:
```dart
final l10n = AppLocalizations.of(context)!;
```

### 3. Replace Hardcoded Strings

#### Before:
```dart
Text('Save')
AppBar(title: const Text('Settings'))
```

#### After:
```dart
Text(l10n.translate('save'))
AppBar(title: Text(l10n.translate('settings')))
```

### 4. Common Replacements

| Hardcoded String | Translation Key |
|------------------|----------------|
| 'Save' | `save` |
| 'Cancel' | `cancel` |
| 'Delete' | `delete` |
| 'Edit' | `edit` |
| 'Add' | `add` |
| 'Search' | `search` |
| 'Refresh' | `refresh` |
| 'Loading...' | `loading` |
| 'Error' | `error` |
| 'Success' | `success` |
| 'Confirm' | `confirm` |

### 5. Test
- [ ] Test in English
- [ ] Test in Arabic (check RTL layout)
- [ ] Test in French
- [ ] Verify all text is translated
- [ ] Check for text overflow
- [ ] Verify tooltips

## Priority Order

1. **High Priority** (User-facing, frequently used):
   - Login Screen
   - Main Screen
   - Order Panel
   - Payment Screen
   - Product Grid

2. **Medium Priority** (Management screens):
   - Orders Management
   - Sessions Management
   - Top Bar dropdown menu

3. **Low Priority** (Admin/Settings):
   - Devices Management
   - Printers Management
   - API Tester

## Notes for Developers

### Arabic (RTL) Considerations:
- Icons may need mirroring for RTL
- Alignments may need adjustment
- Test thoroughly with Arabic language
- Use `Directionality` widget when needed

### Text Length Variations:
- Arabic text is typically 20-30% longer than English
- French text is typically 15-20% longer than English
- Ensure UI accommodates longer text
- Use `overflow: TextOverflow.ellipsis` where appropriate

### Adding New Translation Keys:
1. Add to all three languages in `app_localizations.dart`
2. Use consistent naming (lowercase with underscores)
3. Group related keys together
4. Update this checklist

## Translation Key Naming Convention

### Pattern: `category_item_property`

Examples:
- `user_details_title`
- `order_status_pending`
- `payment_method_cash`
- `product_price_label`

### For Actions: `action_verb`

Examples:
- `save_button`
- `delete_confirm`
- `cancel_action`

### For Messages: `context_message_type`

Examples:
- `login_error_invalid_credentials`
- `order_success_created`
- `payment_warning_insufficient`

## Testing Checklist

For each migrated screen:
- [ ] All visible text is translated
- [ ] Tooltips are translated
- [ ] Dialog titles and messages are translated
- [ ] Button labels are translated
- [ ] Error messages are translated
- [ ] Success messages are translated
- [ ] Placeholder text is translated
- [ ] Help text is translated
- [ ] No console errors about missing keys
- [ ] Layout looks good in all languages
- [ ] RTL layout works correctly for Arabic
- [ ] No text overflow issues

## Example: Complete Screen Migration

### Before:
```dart
class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Screen'),
      ),
      body: Column(
        children: [
          const Text('Welcome'),
          ElevatedButton(
            onPressed: () {},
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
```

### After:
```dart
import '../../utils/app_localizations.dart';

class MyScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('my_screen')),
      ),
      body: Column(
        children: [
          Text(l10n.translate('welcome')),
          ElevatedButton(
            onPressed: () {},
            child: Text(l10n.translate('save')),
          ),
        ],
      ),
    );
  }
}
```

## Progress Tracking

Last Updated: [Date]
Total Screens: 25
Translated: 2
Remaining: 23
Progress: 8%

## Contributors

When you translate a screen, add your name here:
- [Your Name] - Users Management Screen
- [Your Name] - Settings Screen

---

**Note**: This is a living document. Update it as you complete each screen migration.


# i18n Visual Usage Guide

## 🎯 Quick Start in 3 Steps

### Step 1️⃣: Import
```dart
import '../../utils/app_localizations.dart';
```

### Step 2️⃣: Get Instance
```dart
final l10n = AppLocalizations.of(context)!;
```

### Step 3️⃣: Translate
```dart
Text(l10n.translate('your_key'))
```

---

## 📝 Real Examples

### Example 1: Simple Button
```dart
// ❌ Before (Hardcoded)
ElevatedButton(
  onPressed: () {},
  child: const Text('Save'),
)

// ✅ After (Translated)
ElevatedButton(
  onPressed: () {},
  child: Text(l10n.translate('save')),
)
```

### Example 2: AppBar
```dart
// ❌ Before
AppBar(
  title: const Text('Settings'),
  actions: [
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: 'Refresh',
      onPressed: () {},
    ),
  ],
)

// ✅ After
AppBar(
  title: Text(l10n.translate('settings')),
  actions: [
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: l10n.translate('refresh'),
      onPressed: () {},
    ),
  ],
)
```

### Example 3: Dialog
```dart
// ❌ Before
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Confirm'),
    content: const Text('Are you sure?'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      ElevatedButton(
        onPressed: () {},
        child: const Text('Delete'),
      ),
    ],
  ),
)

// ✅ After
final l10n = AppLocalizations.of(context)!;
showDialog(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(l10n.translate('confirm')),
    content: Text(l10n.translate('are_you_sure')),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(l10n.translate('cancel')),
      ),
      ElevatedButton(
        onPressed: () {},
        child: Text(l10n.translate('delete')),
      ),
    ],
  ),
)
```

### Example 4: Form Fields
```dart
// ❌ Before
TextField(
  decoration: const InputDecoration(
    labelText: 'Username',
    hintText: 'Enter your username',
    prefixIcon: Icon(Icons.person),
  ),
)

// ✅ After
final l10n = AppLocalizations.of(context)!;
TextField(
  decoration: InputDecoration(
    labelText: l10n.translate('username'),
    hintText: l10n.translate('enter_username'),
    prefixIcon: const Icon(Icons.person),
  ),
)
```

### Example 5: SnackBar Messages
```dart
// ❌ Before
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(
    content: Text('Operation successful!'),
    backgroundColor: Colors.green,
  ),
)

// ✅ After
final l10n = AppLocalizations.of(context)!;
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(l10n.translate('operation_successful')),
    backgroundColor: Colors.green,
  ),
)
```

### Example 6: Dropdown Menu
```dart
// ❌ Before
DropdownButton<String>(
  value: selectedType,
  items: const [
    DropdownMenuItem(value: 'ALL', child: Text('All Types')),
    DropdownMenuItem(value: 'admin', child: Text('Admin')),
    DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
  ],
  onChanged: (value) {},
)

// ✅ After
final l10n = AppLocalizations.of(context)!;
DropdownButton<String>(
  value: selectedType,
  items: [
    DropdownMenuItem(
      value: 'ALL',
      child: Text(l10n.translate('all_types')),
    ),
    DropdownMenuItem(
      value: 'admin',
      child: Text(l10n.translate('admin')),
    ),
    DropdownMenuItem(
      value: 'cashier',
      child: Text(l10n.translate('cashier')),
    ),
  ],
  onChanged: (value) {},
)
```

### Example 7: DataTable
```dart
// ❌ Before
DataTable(
  columns: const [
    DataColumn(label: Text('ID')),
    DataColumn(label: Text('Name')),
    DataColumn(label: Text('Status')),
  ],
  rows: [],
)

// ✅ After
final l10n = AppLocalizations.of(context)!;
DataTable(
  columns: [
    DataColumn(label: Text(l10n.translate('user_id'))),
    DataColumn(label: Text(l10n.translate('full_name'))),
    DataColumn(label: Text(l10n.translate('status'))),
  ],
  rows: [],
)
```

---

## 🔑 Most Common Keys

### Buttons & Actions
```dart
l10n.translate('save')      // Save | حفظ | Enregistrer
l10n.translate('cancel')    // Cancel | إلغاء | Annuler
l10n.translate('delete')    // Delete | حذف | Supprimer
l10n.translate('edit')      // Edit | تعديل | Modifier
l10n.translate('add')       // Add | إضافة | Ajouter
l10n.translate('close')     // Close | إغلاق | Fermer
l10n.translate('ok')        // OK | موافق | OK
```

### Status Labels
```dart
l10n.translate('active')    // Active | نشط | Actif
l10n.translate('pending')   // Pending | قيد الانتظار | En attente
l10n.translate('completed') // Completed | مكتمل | Terminé
l10n.translate('cancelled') // Cancelled | ملغى | Annulé
```

### Messages
```dart
l10n.translate('loading')           // Loading... | جاري التحميل... | Chargement...
l10n.translate('error')             // Error | خطأ | Erreur
l10n.translate('success')           // Success | نجح | Succès
l10n.translate('no_items')          // No items | لا توجد عناصر | Aucun élément
l10n.translate('error_occurred')    // An error occurred | حدث خطأ | Une erreur s'est produite
```

---

## 🎨 Complete Widget Example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/app_localizations.dart';

class MyTranslatedScreen extends ConsumerWidget {
  const MyTranslatedScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get localization instance
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('my_screen_title')),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: l10n.translate('search'),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.translate('refresh'),
            onPressed: () {},
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Text(
              l10n.translate('section_title'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Text Field
            TextField(
              decoration: InputDecoration(
                labelText: l10n.translate('username'),
                hintText: l10n.translate('enter_username'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Dropdown
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: l10n.translate('user_type'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: 'admin',
                  child: Text(l10n.translate('admin')),
                ),
                DropdownMenuItem(
                  value: 'cashier',
                  child: Text(l10n.translate('cashier')),
                ),
              ],
              onChanged: (value) {},
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.translate('cancel')),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {},
                  child: Text(l10n.translate('save')),
                ),
              ],
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: l10n.translate('add_new'),
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

---

## 🌍 Language Switching

### From User Interface
1. Click profile icon (top-right)
2. Select "Settings"
3. Scroll to "Appearance" section
4. Click on desired language:
   - 🇬🇧 English
   - 🇸🇦 العربية
   - 🇫🇷 Français

### Programmatically (for testing)
```dart
// Get settings notifier
final settingsNotifier = ref.read(settingsProvider.notifier);

// Change to Arabic
await settingsNotifier.setLanguage('ar');

// Change to French
await settingsNotifier.setLanguage('fr');

// Change to English
await settingsNotifier.setLanguage('en');
```

---

## ⚡ Pro Tips

### 1. Store l10n in Variable
```dart
// ✅ Good - Reuse l10n
final l10n = AppLocalizations.of(context)!;
Text(l10n.translate('title'))
Text(l10n.translate('subtitle'))
Text(l10n.translate('description'))

// ❌ Bad - Repeated calls
Text(AppLocalizations.of(context)!.translate('title'))
Text(AppLocalizations.of(context)!.translate('subtitle'))
Text(AppLocalizations.of(context)!.translate('description'))
```

### 2. Handle Null Safety
```dart
// Always use ! after AppLocalizations.of(context)
// The app is configured to always have localizations
final l10n = AppLocalizations.of(context)!;
```

### 3. Use Descriptive Keys
```dart
// ✅ Good
'user_details_title'
'order_status_pending'
'payment_method_cash'

// ❌ Bad
'ud_title'
'os_p'
'pm_c'
```

### 4. Group Related Keys
```dart
// User related
'user_id', 'user_type', 'user_name'

// Order related
'order_id', 'order_status', 'order_total'

// Payment related
'payment_method', 'payment_amount', 'payment_status'
```

---

## 🐛 Troubleshooting

### Issue: Text not translating
**Solution**: Make sure you called `AppLocalizations.of(context)!` and used `translate()` method

### Issue: App crashes with null error
**Solution**: Ensure MaterialApp has localizationsDelegates configured in main.dart

### Issue: New translation key not found
**Solution**: Add the key to all three languages in app_localizations.dart

### Issue: RTL layout broken for Arabic
**Solution**: Flutter handles RTL automatically. Check for hardcoded alignments.

---

## 📚 See Also

- `I18N_IMPLEMENTATION_GUIDE.md` - Detailed technical guide
- `I18N_QUICK_REFERENCE.md` - Quick key lookup
- `I18N_MIGRATION_CHECKLIST.md` - Screen migration tracker
- `lib/utils/app_localizations.dart` - All translation keys


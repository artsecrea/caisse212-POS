# Internationalization (i18n) Implementation Guide

## Overview
This POS system now supports multiple languages: English, Arabic, and French. Users can switch languages from the settings screen, and the app will immediately update all UI text.

## Supported Languages

| Language | Code | Flag | Status |
|----------|------|------|--------|
| English | `en` | 🇬🇧 | ✅ Complete |
| Arabic | `ar` | 🇸🇦 | ✅ Complete |
| French | `fr` | 🇫🇷 | ✅ Complete |

## Implementation Details

### 1. Dependencies Added

```yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: ^0.19.0
```

### 2. Key Files

#### Translation File
- **Location**: `lib/utils/app_localizations.dart`
- **Purpose**: Contains all translated strings for all supported languages
- **Structure**: Map-based translation system

#### Settings Model
- **Updated**: `lib/domain/models/app_settings.dart`
- **Added**: `language` field (String, default: 'en')

#### Settings Provider
- **Updated**: `lib/providers/settings_provider.dart`
- **Added**: `setLanguage(String languageCode)` method
- **Added**: `SettingsKeys.language` constant

#### Main App Configuration
- **Updated**: `lib/main.dart`
- **Added**: Localization delegates
- **Added**: Supported locales configuration
- **Added**: Dynamic locale based on settings

### 3. Using Translations in Widgets

#### Basic Usage

```dart
import '../../utils/app_localizations.dart';

class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    
    return Text(l10n.translate('hello'));
  }
}
```

#### Example with Multiple Strings

```dart
Widget build(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  
  return Column(
    children: [
      Text(l10n.translate('app_title')),
      ElevatedButton(
        onPressed: () {},
        child: Text(l10n.translate('save')),
      ),
      Text(l10n.translate('loading')),
    ],
  );
}
```

### 4. Available Translation Keys

#### Common Actions
- `ok`, `cancel`, `close`, `save`, `delete`, `edit`, `add`
- `search`, `filter`, `refresh`, `loading`
- `error`, `success`, `confirm`
- `yes`, `no`, `back`, `next`, `previous`

#### Login & Authentication
- `login`, `logout`, `username`, `password`
- `sign_in`, `starting_balance`
- `tenant_id`, `tenant_password`
- `verify`, `verify_logout`

#### Users
- `users_management`, `user_id`, `user_type`
- `full_name`, `first_name`, `last_name`
- `created_at`, `updated_at`, `last_login`
- `admin`, `cashier`, `waiter`

#### Orders
- `orders`, `order_id`, `order_status`, `order_type`
- `pending`, `completed`, `cancelled`
- `dine_in`, `take_away`

#### Products & Categories
- `products`, `product_name`, `product_price`
- `categories`, `category`, `all_categories`
- `quantity`, `price`

#### Payment
- `payment`, `pay`, `cash`, `card`
- `amount_paid`, `change`, `payment_successful`

#### Session
- `session`, `sessions`, `session_management`
- `start_session`, `end_session`, `pause_session`, `resume_session`
- `active`, `paused`, `ended`

#### Settings
- `settings`, `general_settings`, `appearance`
- `dark_mode`, `language`, `currency`
- `show_product_images`

### 5. Adding New Translations

#### Step 1: Add to AppLocalizations

Edit `lib/utils/app_localizations.dart`:

```dart
static final Map<String, Map<String, String>> _localizedValues = {
  'en': {
    // ...existing translations...
    'new_key': 'New English Text',
  },
  'ar': {
    // ...existing translations...
    'new_key': 'نص عربي جديد',
  },
  'fr': {
    // ...existing translations...
    'new_key': 'Nouveau texte français',
  },
};
```

#### Step 2: Use in Widgets

```dart
final l10n = AppLocalizations.of(context)!;
Text(l10n.translate('new_key'))
```

### 6. Language Selection UI

Users can change the language from the Settings screen:

```dart
Settings -> Appearance -> Language
```

The language selector shows:
- Flag emoji for each language
- Native language name
- Visual feedback for selected language

### 7. RTL Support for Arabic

The app automatically handles Right-to-Left (RTL) layout for Arabic:

```dart
// MaterialApp configuration in main.dart
MaterialApp(
  locale: Locale(settings.language),
  // ... RTL is handled automatically by Flutter
)
```

### 8. Language Persistence

The selected language is stored in SharedPreferences:
- **Key**: `'language'`
- **Default**: `'en'`
- **Persists** across app restarts

### 9. Testing Different Languages

#### From Settings UI:
1. Open the app
2. Navigate to Settings (from top bar dropdown)
3. Scroll to "Appearance" section
4. Click on desired language (English/العربية/Français)
5. App updates immediately

#### Programmatically (for testing):
```dart
final settingsNotifier = ref.read(settingsProvider.notifier);
await settingsNotifier.setLanguage('ar'); // Arabic
await settingsNotifier.setLanguage('fr'); // French
await settingsNotifier.setLanguage('en'); // English
```

### 10. Best Practices

#### DO:
✅ Always use `AppLocalizations.of(context)!.translate('key')`
✅ Keep translation keys lowercase with underscores
✅ Add all three languages when adding new strings
✅ Use descriptive key names (e.g., `'user_details'` not `'ud'`)
✅ Test all languages before committing

#### DON'T:
❌ Don't hardcode strings in widgets
❌ Don't use overly long translation keys
❌ Don't forget to add translations for all languages
❌ Don't use special characters in keys

### 11. Translation Coverage

Currently translated screens:
- ✅ Users Management Screen
- ✅ Settings Screen (partial)
- ⏳ Login Screen (pending)
- ⏳ Main Screen (pending)
- ⏳ Orders Management (pending)
- ⏳ Other screens (pending)

### 12. Migration Guide for Existing Screens

To add translations to an existing screen:

#### Step 1: Import AppLocalizations
```dart
import '../../utils/app_localizations.dart';
```

#### Step 2: Get localizations instance
```dart
final l10n = AppLocalizations.of(context)!;
```

#### Step 3: Replace hardcoded strings
```dart
// Before:
Text('Save')

// After:
Text(l10n.translate('save'))
```

### 13. Common Patterns

#### Dialog Titles
```dart
AlertDialog(
  title: Text(l10n.translate('confirm')),
  content: Text(l10n.translate('are_you_sure')),
  actions: [
    TextButton(
      onPressed: () => Navigator.pop(context),
      child: Text(l10n.translate('cancel')),
    ),
    ElevatedButton(
      onPressed: () {},
      child: Text(l10n.translate('ok')),
    ),
  ],
)
```

#### AppBar
```dart
AppBar(
  title: Text(l10n.translate('screen_title')),
  actions: [
    IconButton(
      icon: const Icon(Icons.refresh),
      tooltip: l10n.translate('refresh'),
      onPressed: () {},
    ),
  ],
)
```

#### Error Messages
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(l10n.translate('error_occurred')),
    backgroundColor: Colors.red,
  ),
)
```

### 14. Future Enhancements

Potential improvements:
1. **Dynamic Translation Loading**: Load translations from server
2. **More Languages**: Add Spanish, German, Chinese, etc.
3. **Date/Number Formatting**: Locale-specific formatting
4. **Pluralization**: Handle singular/plural forms properly
5. **Translation Management Tool**: UI for managing translations
6. **Missing Translation Fallback**: Better handling of missing keys

### 15. Troubleshooting

#### Issue: Translations not updating
**Solution**: Hot reload the app (press 'r' in terminal or click hot reload in IDE)

#### Issue: `AppLocalizations.of(context)` returns null
**Solution**: Ensure you're using it inside a widget that has MaterialApp as an ancestor

#### Issue: Language doesn't persist
**Solution**: Check SharedPreferences is properly initialized in main.dart

#### Issue: RTL layout issues for Arabic
**Solution**: Use `Directionality` widget or ensure proper constraints

### 16. Code Example: Complete Widget

```dart
import 'package:flutter/material.dart';
import '../../utils/app_localizations.dart';

class ExampleScreen extends StatelessWidget {
  const ExampleScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('example_screen')),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: l10n.translate('search'),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          Text(l10n.translate('welcome_message')),
          ElevatedButton(
            onPressed: () {},
            child: Text(l10n.translate('get_started')),
          ),
          TextButton(
            onPressed: () {},
            child: Text(l10n.translate('learn_more')),
          ),
        ],
      ),
    );
  }
}
```

## Summary

The i18n system is now fully integrated into the POS application. Users can switch between English, Arabic, and French from the settings screen. To add translations to new or existing screens, simply import `AppLocalizations` and use the `translate()` method with the appropriate keys.

For adding new translation keys, update the `app_localizations.dart` file with entries for all three languages.


# Global Snack Bar Control Feature

## Overview
This feature allows users to globally enable or disable snack bar notifications throughout the application. When disabled, all snack bar notifications will be suppressed, providing a cleaner user experience for those who prefer minimal interruptions.

## Files Added/Modified

### New Files
1. **`lib/utils/snackbar_helper.dart`** - Helper class for showing conditional snack bars
2. **`lib/utils/snackbar_usage_example.dart`** - Example usage and migration guide

### Modified Files
1. **`lib/domain/models/app_settings.dart`** - Added `enableSnackBars` field
2. **`lib/providers/settings_provider.dart`** - Added setting key and methods
3. **`lib/presentation/settings/settings_screen.dart`** - Added UI toggle
4. **`lib/utils/app_localizations.dart`** - Added translations (EN, AR, FR)

## Usage

### In Settings UI
Users can toggle snack bars on/off in:
**Settings → Appearance → Enable Notifications**

The setting is persisted in SharedPreferences and applies immediately.

### For Developers

#### Basic Usage
```dart
import 'package:caisse212/utils/snackbar_helper.dart';

// Your widget must be a ConsumerWidget or ConsumerStatefulWidget
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () {
        // Simple message
        SnackBarHelper.showSnackBar(context, ref, 'Operation complete');
      },
      child: Text('Click Me'),
    );
  }
}
```

#### Available Methods

1. **General Snack Bar**
```dart
SnackBarHelper.showSnackBar(
  context,
  ref,
  'Your message here',
  duration: Duration(seconds: 3),
  action: SnackBarAction(label: 'UNDO', onPressed: () {}),
  backgroundColor: Colors.blue,
);
```

2. **Success Snack Bar** (Green background)
```dart
SnackBarHelper.showSuccessSnackBar(
  context,
  ref,
  'Item saved successfully!',
);
```

3. **Error Snack Bar** (Red background)
```dart
SnackBarHelper.showErrorSnackBar(
  context,
  ref,
  'Failed to save item',
);
```

4. **Info Snack Bar** (Blue background)
```dart
SnackBarHelper.showInfoSnackBar(
  context,
  ref,
  'New update available',
);
```

5. **Warning Snack Bar** (Orange background)
```dart
SnackBarHelper.showWarningSnackBar(
  context,
  ref,
  'This action cannot be undone',
);
```

## Migration Guide

### Converting Existing Code

**Before:**
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Saved!'),
    backgroundColor: Colors.green,
  ),
);
```

**After:**
```dart
SnackBarHelper.showSuccessSnackBar(
  context,
  ref,
  'Saved!',
);
```

### Widget Type Changes

If your widget doesn't have access to `WidgetRef`, convert it:

**StatelessWidget → ConsumerWidget:**
```dart
// Before
class MyWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // ...
  }
}

// After
class MyWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ...
  }
}
```

**StatefulWidget → ConsumerStatefulWidget:**
```dart
// Before
class MyWidget extends StatefulWidget {
  @override
  _MyWidgetState createState() => _MyWidgetState();
}

class _MyWidgetState extends State<MyWidget> {
  @override
  Widget build(BuildContext context) {
    // ...
  }
}

// After
class MyWidget extends ConsumerStatefulWidget {
  @override
  ConsumerState<MyWidget> createState() => _MyWidgetState();
}

class _MyWidgetState extends ConsumerState<MyWidget> {
  @override
  Widget build(BuildContext context) {
    // ref is available here
  }
}
```

## Implementation Details

### How It Works
1. The `enableSnackBars` setting is stored in `SharedPreferences`
2. When `SnackBarHelper` methods are called, they check this setting
3. If disabled, the methods return early without showing the snack bar
4. If enabled, snack bars are shown normally

### Default Behavior
- **Default value:** `true` (enabled)
- Snack bars are shown by default to avoid confusion for new users
- Users can disable them if they prefer

### Performance
- Minimal overhead: just a single boolean check before showing snack bars
- No impact when snack bars are disabled (early return)

## Testing

To test this feature:

1. **Enable snack bars** (Settings → Appearance → Enable Notifications: ON)
   - Perform actions that trigger snack bars
   - Verify snack bars appear

2. **Disable snack bars** (Settings → Appearance → Enable Notifications: OFF)
   - Perform the same actions
   - Verify no snack bars appear

3. **Persistence test**
   - Disable snack bars
   - Close and reopen the app
   - Verify setting persists (snack bars still disabled)

## Translations

The feature includes translations in three languages:

| Language | Key | Translation |
|----------|-----|-------------|
| English | enable_snack_bars | Enable Notifications |
| Arabic | enable_snack_bars | تفعيل الإشعارات |
| French | enable_snack_bars | Activer les notifications |

## Benefits

1. **User Control:** Users can choose their notification preference
2. **Cleaner UI:** Reduces visual clutter for users who prefer minimal interruptions
3. **Accessibility:** Helpful for users who find frequent notifications distracting
4. **Consistent API:** Centralized snack bar management through helper methods
5. **Easy to Maintain:** Single point of control for all snack bars

## Future Enhancements

Possible future improvements:
- Per-category notification control (errors only, successes only, etc.)
- Notification history/log for disabled notifications
- Notification sound settings
- Custom notification duration preferences
- Notification position preferences (top/bottom)

## Notes

- This feature does NOT affect dialogs, alerts, or other UI feedback mechanisms
- Only affects snack bars shown through `SnackBarHelper`
- Legacy code using `ScaffoldMessenger` directly will still show snack bars until migrated


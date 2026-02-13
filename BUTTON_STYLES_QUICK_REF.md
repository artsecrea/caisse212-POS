# Quick Reference: Using AppButtonStyles

## Import
```dart
import '../../utils/button_styles.dart';
```

## Examples

### Elevated Button (Standard)
```dart
ElevatedButton(
  onPressed: () {},
  style: AppButtonStyles.elevatedButtonStyle(),
  child: Text('Button'),
)
```

### Elevated Button (Large - Recommended for Touch Screens)
```dart
ElevatedButton(
  onPressed: () {},
  style: AppButtonStyles.elevatedButtonStyle(isLarge: true),
  child: Text('Button'),
)
```

### Elevated Button with Custom Colors
```dart
ElevatedButton(
  onPressed: () {},
  style: AppButtonStyles.elevatedButtonStyle(
    backgroundColor: Colors.blue,
    foregroundColor: Colors.white,
    isLarge: true,
  ),
  child: Text('Save'),
)
```

### Elevated Button with Icon
```dart
ElevatedButton.icon(
  onPressed: () {},
  icon: Icon(Icons.add, size: 24),
  label: Text('Add Item'),
  style: AppButtonStyles.elevatedButtonStyle(isLarge: true),
)
```

### Outlined Button
```dart
OutlinedButton(
  onPressed: () {},
  style: AppButtonStyles.outlinedButtonStyle(isLarge: true),
  child: Text('Cancel'),
)
```

### Outlined Button with Custom Colors
```dart
OutlinedButton(
  onPressed: () {},
  style: AppButtonStyles.outlinedButtonStyle(
    foregroundColor: Colors.red,
    borderColor: Colors.red,
    isLarge: true,
  ),
  child: Text('Delete'),
)
```

### Text Button
```dart
TextButton(
  onPressed: () {},
  style: AppButtonStyles.textButtonStyle(isLarge: true),
  child: Text('Skip'),
)
```

### Icon Button
```dart
ElevatedButton(
  onPressed: () {},
  style: AppButtonStyles.iconButtonStyle(
    backgroundColor: Colors.blue,
    isLarge: true,
  ),
  child: Icon(Icons.settings),
)
```

## Sizes

| Style | Height | Padding | Text Size | Icon Size |
|-------|--------|---------|-----------|-----------|
| **Standard** | 56px | 24x16 | 16px | 20-22px |
| **Large** | 64px | 32x20 | 18px | 24-28px |

## When to Use

✅ **Use `isLarge: true`** for:
- Main action buttons
- Dialog buttons
- Touch screen interfaces
- Mobile/tablet views
- Payment/critical actions

✅ **Use standard size** for:
- Compact layouts
- Secondary actions
- Desktop-only interfaces
- Inline buttons in tables

## Complete Dialog Example

```dart
AlertDialog(
  title: Text('Confirm Action'),
  content: Text('Are you sure you want to proceed?'),
  actions: [
    TextButton(
      onPressed: () => Navigator.pop(context),
      style: AppButtonStyles.textButtonStyle(isLarge: true),
      child: Text('Cancel'),
    ),
    ElevatedButton(
      onPressed: () => Navigator.pop(context, true),
      style: AppButtonStyles.elevatedButtonStyle(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        isLarge: true,
      ),
      child: Text('Confirm'),
    ),
  ],
)
```

## Tips

💡 **Always use `isLarge: true`** for better touch experience on POS systems
💡 **Icon sizes**: 24px for large buttons, 20px for standard
💡 **Disabled buttons**: Style automatically handles disabled state
💡 **Consistency**: Use the same size for all buttons in a dialog/screen

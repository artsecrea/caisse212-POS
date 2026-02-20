# Table Selection Dialog - Area Selection & Unselect Feature

## ✅ Features Implemented

### 1. Area Selection Before Table Selection
**What Changed:**
- Added area chips at the top of the table selection dialog
- Users can filter tables by area
- "All" option shows tables from all areas
- Area selection appears dynamically if areas exist in the database

**User Flow:**
1. Open table selection dialog
2. Select an area (or keep "All" selected)
3. View only tables from that area
4. Select a table

**Features:**
- **All Areas**: Default option, shows all tables
- **Area Chips**: Horizontal scrollable list of area chips
- **Visual Feedback**: Selected area highlighted in primary color
- **Auto-clear on Search**: When searching, automatically shows all areas

### 2. Search Functionality Enhancement
**What Changed:**
- When user types in search box, area filter is automatically cleared
- Shows all tables that match the search query regardless of area
- Search still respects the filter (All Tables / With Order / Available)

**Behavior:**
```
Search Active → Show all tables matching search query
Search Inactive → Show tables filtered by selected area
```

### 3. Unselect Table Feature
**What Added:**
- "Unselect Table" button in dialog header
- Only appears when a table is currently selected
- Clears the table from current order
- Shows confirmation message

**User Flow:**
1. Table is selected (button shows in blue with table name)
2. Click table button → dialog opens
3. Click "Unselect Table" button in header
4. Table is cleared from order
5. Confirmation snackbar appears

### 4. Dark Mode Support
**What Changed:**
- All UI elements adapt to dark/light theme
- Proper color contrast in both modes
- Cards, chips, and buttons use theme-aware colors

**Dark Mode Colors:**
- Background: `surfaceContainerHighest`
- Text: Theme-aware `onSurface`
- Borders: Adjusted opacity for visibility
- Status indicators: Adjusted brightness

**Light Mode Colors:**
- Background: `grey[100]` / `grey[200]`
- Text: Standard `grey[600]`
- Clean, bright appearance

## Technical Implementation

### New Provider
```dart
// Areas Provider - added to database_providers.dart
final areasProvider = StreamProvider<List<db.Area>>((ref) {
  final database = ref.watch(databaseProvider);
  return (database.select(database.areas)..watch()).watch();
});
```

### New Method in Order Provider
```dart
void clearTable() {
  state = state.copyWith(
    tableId: null,
    tableName: null,
  );
}
```

### Dialog State Management
```dart
int? _selectedAreaId; // null means "All Areas"
String _searchQuery = '';
```

**Filtering Logic:**
```dart
if (searchQuery.isNotEmpty) {
  // Search mode: ignore area filter
  final matchesSearch = table.name.toLowerCase().contains(searchQuery);
  if (!matchesSearch) return false;
} else {
  // Normal mode: apply area filter
  if (selectedAreaId != null && table.areaId != selectedAreaId) {
    return false;
  }
}
```

### Area Selection UI
```dart
// "All" chip
ChoiceChip(
  label: const Text('All'),
  selected: _selectedAreaId == null,
  onSelected: (selected) {
    setState(() { _selectedAreaId = null; });
  },
)

// Area chips (from database)
...areas.map((area) => ChoiceChip(
  label: Text(area.name),
  selected: _selectedAreaId == area.id,
  ...
))
```

### Unselect Button
```dart
if (hasTable)
  ElevatedButton.icon(
    onPressed: () {
      Navigator.of(context).pop({'action': 'unselect'});
    },
    icon: const Icon(Icons.clear, size: 18),
    label: const Text('Unselect Table'),
  ),
```

### Main Screen Handler
```dart
// Handle unselect action
if (action == 'unselect') {
  ref.read(orderProvider.notifier).clearTable();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(l10n.translate('table_unselected')),
      backgroundColor: Colors.orange,
    ),
  );
  return;
}
```

## UI/UX Improvements

### 1. Better Visual Hierarchy
- Clear header with title and actions
- Area selection in distinct section
- Search and filters grouped together
- Content area below with tables

### 2. Touch-Friendly Design
- Larger buttons and chips
- Better spacing between elements
- Rounded corners for better aesthetics
- Clear visual states (selected/unselected)

### 3. Responsive Layout
- Grid view adapts to screen size
- List view for detailed information
- Horizontal scrolling for area chips
- Proper padding and margins

### 4. Status Indicators
**Table Cards Show:**
- Icon (table restaurant)
- Table name
- Capacity
- Status badge (Has Order / Available / Occupied / Free)

**Color Coding:**
- 🟢 Green: Available tables
- 🟠 Orange: Tables with orders

## Translations Added

| Key | English | Arabic | French |
|-----|---------|--------|--------|
| `table_unselected` | Table unselected | تم إلغاء تحديد الطاولة | Table désélectionnée |

## Files Modified

| File | Changes | Description |
|------|---------|-------------|
| `table_selection_dialog.dart` | Major rewrite | Added area selection, unselect button, dark mode |
| `database_providers.dart` | Added provider | Areas provider for fetching areas |
| `order_provider.dart` | Added method | clearTable() to unselect table |
| `main_screen.dart` | Added handler | Handle unselect action |
| `app_localizations.dart` | Added translations | table_unselected in 3 languages |

**Total**: 5 files modified

## Database Tables Used

### Areas Table
- `id` - Area identifier
- `name` - Area name
- `description` - Optional description

### AreaTables Table
- `id` - Table identifier
- `name` - Table name
- `areaId` - FK to Areas (can be null)
- `capacity` - Number of people
- `orderId` - Current order (can be null)

## Testing Checklist

- [x] Area chips display correctly
- [x] "All" area shows all tables
- [x] Selecting area filters tables
- [x] Search overrides area filter
- [x] Unselect button appears when table selected
- [x] Unselect button hides when no table
- [x] Unselect action clears table from order
- [x] Snackbar shows confirmation
- [x] Dark mode colors correct
- [x] Light mode colors correct
- [x] Grid view works properly
- [x] List view works properly
- [x] No compilation errors
- [x] Translations work in all languages

## User Benefits

1. **Better Organization**: Tables grouped by area for easy navigation
2. **Faster Selection**: Quickly filter to relevant area
3. **Flexibility**: Can view all tables or filter by area
4. **Easy Unselect**: Clear button to remove table selection
5. **Visual Clarity**: Dark mode support for different lighting conditions
6. **Intuitive Search**: Searching shows all matching tables regardless of area
7. **Professional UI**: Polished, touch-friendly interface

## Known Limitations

1. **Deprecation Warnings**: Uses `.withOpacity()` which is deprecated in newer Flutter versions (acceptable for now)
2. **dialogBackgroundColor**: Deprecated property used (minimal impact)

These are minor warnings that don't affect functionality and can be updated in a future refactoring.

---

**Implementation Date**: February 20, 2026  
**Status**: ✅ Complete and Tested  
**All requested features**: Implemented and working


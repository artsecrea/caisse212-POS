# Permission System Implementation Guide

## Overview
This POS system now includes a comprehensive permission-based access control system. Permissions are managed per-user and stored in the database. Administrators have all permissions by default.

## Permission Format
Permissions follow the format: `pos:resource:action`

Examples:
- `pos:manualDiscount` - Apply manual discounts
- `pos:orders:delete` - Delete orders
- `pos:tickets:print` - Print tickets

## Available Permissions

### Manual Discount
- `pos:manualDiscount` - Apply additional manual discounts to products

### Printing
- `pos:printing` - Print receipts and KDS tickets

### Orders
- `pos:orders:view` - View orders list
- `pos:orders:create` - Create new orders
- `pos:orders:update` - Update/edit existing orders
- `pos:orders:delete` - Delete orders

### Tickets
- `pos:tickets:view` - View tickets list
- `pos:tickets:create` - Create tickets (pay orders)
- `pos:tickets:delete` - Delete tickets
- `pos:tickets:print` - Print individual tickets

### Sessions
- `pos:sessions:start` - Start new cash sessions
- `pos:sessions:end` - End cash sessions
- `pos:sessions:pause` - Pause sessions (auto-pause)
- `pos:sessions:view` - View sessions list
- `pos:sessions:delete` - Delete sessions

### Commercials
- `pos:commercial:set` - Assign commercial to orders
- `pos:commercial:create` - Create new commercials
- `pos:commercial:view` - View commercials list

### Customers
- `pos:customer:set` - Assign customer to orders
- `pos:customer:create` - Create new customers
- `pos:customer:view` - View customers list
- `pos:customer:delete` - Delete customers

### Devices (Printers, etc.)
- `pos:devices:use` - Use devices (printers)
- `pos:devices:view` - View devices list
- `pos:devices:update` - Configure devices
- `pos:devices:delete` - Delete/remove devices

### Tables
- `pos:tables:set` - Assign tables to orders
- `pos:tables:clear` - Clear table assignments

### Products
- `pos:products:view` - View product catalog
- `pos:products:modify` - Modify product details in orders

### Settings
- `pos:settings:view` - View settings
- `pos:settings:update` - Update settings

### Reports
- `pos:reports:view` - View reports and analytics

### Admin
- `pos:admin` - Full administrative access
- `pos:users:view` - View users list
- `pos:users:create` - Create users
- `pos:users:update` - Update users
- `pos:users:delete` - Delete users

### Wildcard
- `pos:*` - All POS permissions (same as admin)

## Usage in Code

### 1. Check Permission in Widgets

#### Using PermissionGuard (Show/Hide UI Elements)
```dart
import '../../services/permission_service.dart';
import '../widgets/permission_guard.dart';

PermissionGuard(
  permission: Permissions.manualDiscount,
  child: YourWidget(),
  fallback: Text('No access'), // Optional
)
```

#### Using PermissionButton
```dart
PermissionButton(
  permission: Permissions.ordersDelete,
  onPressed: () => deleteOrder(),
  child: Text('Delete'),
)
```

#### Using PermissionIconButton
```dart
PermissionIconButton(
  permission: Permissions.printing,
  icon: Icon(Icons.print),
  onPressed: () => printReceipt(),
  tooltip: 'Print Receipt',
)
```

#### Using Conditional Rendering
```dart
final permissionService = ref.read(permissionServiceProvider);

if (permissionService.hasPermission(Permissions.ordersUpdate)) {
  // Show edit button
}
```

### 2. Check Permission in Functions

```dart
void _deleteOrder(Order order) {
  final permissionService = ref.read(permissionServiceProvider);
  
  if (!permissionService.hasPermission(Permissions.ordersDelete)) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('You do not have permission to delete orders'),
        backgroundColor: Colors.red,
      ),
    );
    return;
  }
  
  // Proceed with deletion
  // ...
}
```

### 3. Using PermissionCheckMixin

```dart
class MyWidget extends ConsumerWidget with PermissionCheckMixin {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!checkPermission(ref, Permissions.ticketsDelete)) {
      showPermissionDenied(context);
      return;
    }
    
    // Continue with action
  }
}
```

## Setting User Permissions

### In Database
Permissions are stored in the `users` table in the `permissions` column as a comma-separated string:

```sql
UPDATE users 
SET permissions = 'pos:manualDiscount,pos:printing,pos:orders:view,pos:orders:create'
WHERE id = 1;
```

### Sample Permission Sets

#### Cashier (Basic)
```
pos:products:view,pos:orders:view,pos:orders:create,pos:tickets:create,pos:tickets:view,pos:customer:set,pos:tables:set
```

#### Cashier (Full)
```
pos:products:view,pos:orders:*,pos:tickets:*,pos:customer:set,pos:commercial:set,pos:tables:*,pos:printing
```

#### Supervisor
```
pos:products:view,pos:orders:*,pos:tickets:*,pos:sessions:*,pos:customer:*,pos:commercial:*,pos:tables:*,pos:printing,pos:manualDiscount,pos:reports:view
```

#### Manager
```
pos:*
```

#### Administrator
User type = 'admin' (has all permissions automatically)

## Protected Features in the System

### Already Protected:
1. ✅ Manual Discount (product modification dialog)
2. ✅ Print Button (main screen)
3. ✅ Customer Set (main screen)
4. ✅ Commercial Set (main screen)
5. ✅ Order Delete (orders management)
6. ✅ Order Update (orders management)
7. ✅ Session Delete (sessions management)
8. ✅ Session End (sessions management)
9. ✅ Menu Items in Top Bar (Settings, Sessions, Orders, Tickets, Devices, Users)
10. ✅ Full Logout (admin only)

### To Be Protected (Examples):

#### Tickets Management Screen
```dart
// In tickets management screen
PermissionIconButton(
  permission: Permissions.ticketsDelete,
  icon: Icon(Icons.delete),
  onPressed: () => deleteTicket(ticket),
)

PermissionIconButton(
  permission: Permissions.ticketsPrint,
  icon: Icon(Icons.print),
  onPressed: () => printTicket(ticket),
)
```

#### Payment Screen
```dart
// Protect ticket creation
if (!ref.read(permissionServiceProvider).hasPermission(Permissions.ticketsCreate)) {
  showPermissionDenied(context, message: 'Cannot create tickets');
  return;
}
```

#### Settings Screen
```dart
// Wrap entire settings with permission
PermissionGuard(
  permission: Permissions.settingsUpdate,
  fallback: Center(child: Text('You cannot modify settings')),
  child: SettingsForm(),
)
```

#### Clear Table Action
```dart
// In table long press
PermissionGuard(
  permission: Permissions.tablesClear,
  child: TextButton(
    onPressed: () => clearTable(tableId),
    child: Text('Clear Table'),
  ),
)
```

## Best Practices

1. **Always check permissions before critical operations** (delete, update, create)
2. **Hide UI elements** users cannot access (better UX than showing disabled buttons)
3. **Use appropriate fallbacks** when needed
4. **Provide clear feedback** when permission is denied
5. **Group related permissions** (e.g., `pos:orders:*` for all order operations)
6. **Test with different permission sets** to ensure proper access control

## Migration Guide

To add permissions to existing features:

1. Import permission service:
   ```dart
   import '../../services/permission_service.dart';
   import '../widgets/permission_guard.dart';
   ```

2. Wrap sensitive UI elements:
   ```dart
   if (ref.read(permissionServiceProvider).hasPermission(Permissions.yourPermission))
     YourWidget()
   ```

3. Add runtime checks before actions:
   ```dart
   if (!permissionService.hasPermission(Permissions.yourPermission)) {
     // Show error
     return;
   }
   ```

4. Update user permissions in database to grant access

## Troubleshooting

### Users Cannot See Features
- Check user's `permissions` field in database
- Verify permission constant matches exactly
- Check if user type is 'admin' (admins have all permissions)

### Permission Check Not Working
- Ensure PermissionService is properly initialized with current user
- Check that currentUserProvider is providing the logged-in user
- Verify imports are correct

### UI Not Updating
- Use `ref.watch(permissionServiceProvider)` in widgets that need to react to user changes
- Rebuild widgets when user changes


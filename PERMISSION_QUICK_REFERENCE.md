# Permission System - Quick Reference Card

## Import Required Packages
```dart
import '../../services/permission_service.dart';
import '../widgets/permission_guard.dart';
```

## Common Usage Patterns

### 1. Hide/Show Widget Based on Permission
```dart
if (ref.read(permissionServiceProvider).hasPermission(Permissions.ordersDelete))
  DeleteButton()
```

### 2. Wrap Widget with Guard
```dart
PermissionGuard(
  permission: Permissions.manualDiscount,
  child: ManualDiscountWidget(),
)
```

### 3. Permission Button
```dart
PermissionIconButton(
  permission: Permissions.printing,
  icon: Icon(Icons.print),
  onPressed: () => print(),
  tooltip: 'Print',
)
```

### 4. Runtime Check
```dart
final permService = ref.read(permissionServiceProvider);
if (!permService.hasPermission(Permissions.ordersDelete)) {
  showError('No permission');
  return;
}
// Do action
```

## Most Common Permissions

| Feature | Permission Constant |
|---------|-------------------|
| Manual Discount | `Permissions.manualDiscount` |
| Print | `Permissions.printing` |
| Delete Order | `Permissions.ordersDelete` |
| Edit Order | `Permissions.ordersUpdate` |
| Delete Ticket | `Permissions.ticketsDelete` |
| Delete Session | `Permissions.sessionsDelete` |
| Set Customer | `Permissions.customerSet` |
| Set Commercial | `Permissions.commercialSet` |
| Settings | `Permissions.settingsView` |
| Admin | `'pos:admin'` |

## User Permission Strings

### Cashier (Basic)
```
pos:products:view,pos:orders:view,pos:orders:create,pos:tickets:create,pos:customer:set,pos:tables:set
```

### Cashier (Full)
```
pos:products:view,pos:orders:*,pos:tickets:*,pos:customer:set,pos:commercial:set,pos:tables:*,pos:printing
```

### Supervisor
```
pos:products:view,pos:orders:*,pos:tickets:*,pos:sessions:view,pos:customer:*,pos:commercial:*,pos:tables:*,pos:printing,pos:manualDiscount,pos:reports:view
```

### Admin
```
pos:*
```
(or set user type to 'admin')

## Wildcard Support
- `pos:*` = All permissions
- `pos:orders:*` = All order permissions (view, create, update, delete)
- `pos:tickets:*` = All ticket permissions

## Quick Test
```dart
// Check if current user can delete orders
final canDelete = ref.read(permissionServiceProvider)
    .hasPermission(Permissions.ordersDelete);
print('Can delete: $canDelete');
```


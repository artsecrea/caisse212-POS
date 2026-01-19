# Tenant Password Protection - Quick Reference

## For Users

### Setting Up Your Tenant
1. On first launch, you'll see the Tenant ID screen
2. Enter your **Tenant ID** (e.g., "TENANT001")
3. Create a **Tenant Password** (minimum 4 characters)
4. Click **Continue**
5. You'll be taken to the Login screen

### Exiting to Tenant Screen
If you need to go back to change tenant settings:

1. Look for the **Exit button** (📤 icon) in the top-left corner of the Login screen
2. Click the exit button
3. Enter your **Tenant Password** when prompted
4. Click **Verify**
5. You'll return to the Tenant ID screen

**Note**: If you enter the wrong password, you'll see an error message. Try again.

### Full Logout (Admin Only)
To completely disconnect from the server and clear all data:

1. From the main screen, click your **profile icon** (top-right)
2. Select **Full Logout (Clear All)** from the dropdown menu
   - *Note: This option only appears for users with admin permissions*
3. Enter your **Tenant Password** when prompted
4. Click **Verify & Logout**
5. Confirm the logout action
6. All data will be cleared and you'll return to the Tenant screen

## For Developers

### Quick Implementation Guide

#### 1. Check if Tenant Password Exists
```dart
final prefs = await SharedPreferences.getInstance();
final tenantPasswordHash = prefs.getString('tenant_password_hash');

if (tenantPasswordHash != null) {
  // Password protection is enabled
}
```

#### 2. Verify Tenant Password
```dart
import 'package:bcrypt/bcrypt.dart';

final enteredPassword = "user_entered_password";
final storedHash = prefs.getString('tenant_password_hash');

if (storedHash != null) {
  final isValid = BCrypt.checkpw(enteredPassword, storedHash);
  if (isValid) {
    // Password is correct
  } else {
    // Password is incorrect
  }
}
```

#### 3. Save New Tenant Password
```dart
import 'package:bcrypt/bcrypt.dart';

final newPassword = "new_password";
final passwordHash = BCrypt.hashpw(newPassword, BCrypt.gensalt());
await prefs.setString('tenant_password_hash', passwordHash);
```

#### 4. Clear Tenant Password (during full logout)
```dart
await prefs.remove('tenant_password_hash');
```

## Security Tips

### For Users
1. **Choose a strong password**: While the minimum is 4 characters, use at least 8 for better security
2. **Don't share your tenant password**: This is like a master key for your POS system
3. **Remember your password**: There's no recovery mechanism (yet)
4. **Change default passwords**: If your system came with a default password, change it immediately

### For Administrators
1. **Set password policies**: Require minimum 8-12 character passwords
2. **Regular password changes**: Consider changing tenant passwords periodically
3. **Limit admin access**: Only grant 'pos:admin' permission to trusted users
4. **Monitor logout events**: Check logs for unusual full logout activities
5. **Backup before full logout**: Full logout clears all local data

## Troubleshooting

### I forgot my tenant password
Currently, there's no password recovery mechanism. Options:
1. If you know the tenant ID, you can set a new password by:
   - Clearing app data (loses all local information)
   - Reinstalling the app
   - Re-entering tenant information with a new password

### The exit button doesn't appear
- Make sure you're on the Login screen (not the Tenant screen)
- The button is in the top-left corner with an exit icon (📤)

### "Invalid tenant password" error
- Check for typos in your password
- Ensure Caps Lock is off
- Try again carefully

### Full Logout option is missing
- This option requires admin permissions
- Check with your system administrator to grant you 'pos:admin' permission

### How do I change my tenant password?
1. Perform a Full Logout (requires admin permission)
2. At the Tenant screen, enter the same Tenant ID
3. Enter a new password
4. The new password will replace the old one

## Permissions Required

| Action | Required Permission |
|--------|-------------------|
| Exit to Tenant Screen | None (anyone can do this with password) |
| Full Logout | `pos:admin` |
| View Full Logout Option | `pos:admin` |

## Related Documentation

- Main documentation: `TENANT_PASSWORD_PROTECTION.md`
- Permission system: `PERMISSION_SYSTEM_GUIDE.md`
- Quick references: `PERMISSION_QUICK_REFERENCE.md`

## Support

If you encounter issues:
1. Check this guide first
2. Review the full documentation in `TENANT_PASSWORD_PROTECTION.md`
3. Contact your system administrator
4. For developers: Check implementation details in the source files


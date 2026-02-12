# Quick Reference Card - Enhanced Login Screens

## 🔑 Admin Credentials

### Server Settings Password
```
Password: admin123
Location: tenant_login_screen.dart, line ~30
Constant: _serverSettingsPassword
```

⚠️ **CHANGE IN PRODUCTION!**

## 🎯 Button Sizes

```
Primary Actions:    ┃━━━━━━━━━━━━━━━━━━━━━━━━━┃  60px
Secondary Actions:  ┃━━━━━━━━━━━━━━━━━━━━┃      50px
Corner Icons:       ┃━━━━━━━━━━━━━━━━━┃          52px
```

## 📏 Spacing Reference

```
Between fields:     ████████████████████  20px
Before buttons:     ████████████████████████████████  32px
Card padding:       ████████████████████████████████████████  40px
```

## ✅ Validation Rules

### Tenant Login
- POS Name: ≥2 chars, required
- Username: ≥3 chars, required
- Password: ≥4 chars, required
- Server URL: Must start with http:// or https://

### Login
- Username: ≥3 chars, required
- Password: Required (any length)
- Balance: ≥0, optional

## 🔒 Security Flow

### Access Server Settings
```
1. Click 🔧 icon
2. Enter admin password (admin123)
3. Edit URL
4. Save (validates format)
```

### Create Tenant Password
```
1. Login successful
2. Set tenant password (≥4 chars)
3. Confirm password
4. Hash with BCrypt
5. Save to SharedPreferences
```

### Exit to Tenant Login
```
1. Click 🚪 icon
2. Enter tenant password
3. Verify with BCrypt
4. Clear auth data
5. Navigate to tenant login
```

## 📦 SharedPreferences Keys

```
server_url               → Server base URL
tenant_password_hash     → BCrypt hash of tenant password
```

## 🎨 Color Scheme

```
Primary:         Theme.of(context).primaryColor
Error BG:        red[50]
Error Border:    red[300] (2px)
Error Text:      red[700]
Disabled:        grey[300]
Corner Icons:    black38
```

## 🔤 Typography

```
Headers:         24-28px, Bold, Primary Color
Subheaders:      14px, Normal, grey[600]
Form Labels:     16px, Normal, grey[800]
Primary Buttons: 18px, Bold, White
Error Text:      14px, Medium (w500), red[700]
```

## 📱 Touch Targets

```
Minimum:    60px x 60px
Primary:    Full width x 60px
Secondary:  Full width x 50px
Icons:      52px x 52px
```

## 🛠️ Common Tasks

### Change Admin Password
```dart
// File: tenant_login_screen.dart
static const String _serverSettingsPassword = 'NEW_PASSWORD';
```

### Change Default Server URL
```dart
// File: tenant_login_screen.dart
// In _loadServerUrl() method
final savedUrl = prefs.getString('server_url') ?? 'YOUR_URL_HERE';
```

### Add New Validation
```dart
// In TextFormField validator
validator: (value) {
  if (condition) return 'Error message';
  return null; // Valid
}
```

## 🐛 Debugging

### Check Server URL
```dart
final prefs = await SharedPreferences.getInstance();
print('Server URL: ${prefs.getString('server_url')}');
```

### Check Tenant Password Hash
```dart
final prefs = await SharedPreferences.getInstance();
print('Hash: ${prefs.getString('tenant_password_hash')}');
```

### Verify Password
```dart
final verified = BCrypt.checkpw('password', hash);
print('Verified: $verified');
```

## 📊 Files Modified

```
lib/presentation/
  ├── tenant_login_screen/
  │   └── tenant_login_screen.dart  ✓ Enhanced
  └── login_screen/
      └── login_screen.dart         ✓ Enhanced

lib/utils/
  └── app_localizations.dart        ✓ Updated

Documentation:
  ├── LOGIN_SCREENS_ENHANCEMENT.md
  ├── LOGIN_SCREENS_VISUAL_GUIDE.md
  ├── BEFORE_AFTER_COMPARISON.md
  ├── ENHANCEMENT_COMPLETE.md
  └── QUICK_REFERENCE.md            ← You are here
```

## ⚡ Testing Commands

```bash
# Run the app
flutter run

# Check for errors
flutter analyze

# Hot reload
r

# Hot restart
R

# Clear and rebuild
flutter clean && flutter pub get && flutter run
```

## 🎯 Critical Notes

1. **Admin password is hard-coded** - Change in production!
2. **Server URL persists** - Stored in SharedPreferences
3. **Tenant password required** - Set on every server login
4. **BCrypt hashing** - Secure password storage
5. **Form validation** - All fields validated on submit

## 📞 Common Error Messages

```
"Cannot connect to server"
  → Check: URL, server status, network

"Invalid credentials"
  → Check: Username and password

"POS name must be at least 2 characters"
  → Enter valid POS name

"Invalid admin password"
  → Use: admin123 (default)

"URL must start with http:// or https://"
  → Fix URL format
```

---

**Version**: 1.0.0-BETA  
**Last Updated**: February 12, 2026  
**Status**: ✅ Complete - No Errors


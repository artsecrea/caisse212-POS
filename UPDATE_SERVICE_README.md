# Update Service Setup Guide

## Overview
This update service provides automatic application updates for both Android and Windows platforms with mandatory update support.

## Components Created

### 1. Update Service (`lib/services/update_service.dart`)
- Checks for available updates
- Downloads update packages
- Handles Android APK installation
- Prepares Windows updates and launches updater

### 2. Windows Updater (`windows/updater/WindowsUpdater.ps1`)
- PowerShell script with WinForms UI
- Stops running application
- Creates backup before update
- Downloads and extracts update
- Replaces files (with exclusion support)
- Rollback on failure
- Relaunches application

### 3. Update Provider (`lib/providers/update_provider.dart`)
- State management for update process
- Version comparison
- Progress tracking

### 4. Update Dialog (`lib/presentation/widgets/update_dialog.dart`)
- UI for update notifications
- Shows release notes
- Download progress
- Mandatory update enforcement

## Setup Instructions

### Android Setup

1. **Create FileProvider XML** (required for Android 7.0+):
   ```bash
   mkdir -p android/app/src/main/res/xml
   ```

2. Create file `android/app/src/main/res/xml/file_paths.xml`:
   ```xml
   <?xml version="1.0" encoding="utf-8"?>
   <paths xmlns:android="http://schemas.android.com/apk/res/android">
       <external-path name="external_files" path="."/>
       <external-cache-path name="external_cache" path="."/>
   </paths>
   ```

3. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

### Windows Setup

1. **Bundle Updater Script**:
   - The `WindowsUpdater.ps1` script is already in `windows/updater/`
   - It will be included when you build the Windows app
   - Make sure to copy the `updater` folder to your distribution

2. **Build Configuration**:
   - Ensure the updater folder is included in your Windows build artifacts

## Usage

### 1. Check for Updates on Login

Add this to your login screen after successful authentication:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/update_provider.dart';
import '../presentation/widgets/update_dialog.dart';

// After successful login:
Future<void> _checkForUpdates(BuildContext context, WidgetRef ref) async {
  await ref.read(updateProvider.notifier).checkForUpdates();
  
  final updateState = ref.read(updateProvider);
  
  if (updateState.availableUpdate != null) {
    // Show update dialog
    showUpdateDialog(
      context,
      isMandatory: updateState.updateRequired,
    );
  }
}

// Call in login success:
void _onLoginSuccess(BuildContext context, WidgetRef ref) async {
  // ... your login logic ...
  
  // Check for updates
  await _checkForUpdates(context, ref);
  
  // Navigate to main screen if no mandatory update
  if (!ref.read(updateProvider).updateRequired) {
    Navigator.pushReplacementNamed(context, '/main');
  }
}
```

### 2. Implement Update Check API

Update the `checkForUpdates()` method in `lib/services/update_service.dart`:

```dart
Future<UpdateInfo?> checkForUpdates() async {
  try {
    final response = await http.get(
      Uri.parse('https://your-api.com/api/updates/check'),
      headers: {
        'X-Platform': Platform.isAndroid ? 'android' : 'windows',
        'X-Current-Version': (await PackageInfo.fromPlatform()).version,
      },
    );
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return UpdateInfo.fromJson(data);
    }
    
    return null;
  } catch (e) {
    _logger.error('Failed to check for updates: $e');
    return null;
  }
}
```

### 3. API Response Format

Your update API should return:

```json
{
  "version": "1.2.0",
  "downloadUrl": "https://your-cdn.com/updates/app-v1.2.0.apk",
  "isMandatory": true,
  "releaseNotes": "- Bug fixes\n- New features\n- Performance improvements",
  "checksum": "sha256_hash_of_file"
}
```

For Windows, use `.zip` files instead of `.apk`.

## Windows Updater Parameters

The PowerShell updater accepts these parameters:

```powershell
# Required
-DownloadUrl "https://example.com/update.zip"
-AppDirectory "C:\Program Files\YourApp"
-ExecutableName "YourApp.exe"

# Optional
-ExcludeFolders @("logs", "data", "config")
-ArchivePassword "password123"
-StartDelaySeconds 5
-TempDirectory "C:\Temp\Updater"
-BackupDirectory "C:\Temp\Backup"
-Checksum "sha256_hash"
-Silent  # Run without UI
```

## Testing Updates

### Test Android Update:
1. Build an APK with version 1.0.0
2. Install it on device
3. Build APK with version 1.1.0
4. Host it and configure your API to return update info
5. Login and verify update dialog appears

### Test Windows Update:
1. Build app version 1.0.0
2. Create a ZIP of the updated version
3. Test the updater script:
   ```powershell
   .\WindowsUpdater.ps1 `
     -DownloadUrl "file:///C:/path/to/update.zip" `
     -AppDirectory "C:\path\to\app" `
     -ExecutableName "posecrea.exe" `
     -ExcludeFolders @("logs", "data")
   ```

## Security Considerations

1. **Use HTTPS** for download URLs
2. **Validate checksums** to ensure file integrity
3. **Sign your APKs** on Android
4. **Code sign** Windows executables
5. **Implement rate limiting** on update API

## Troubleshooting

### Android Issues:
- **Permission denied**: Check storage permissions in app settings
- **Installation blocked**: Enable "Install from unknown sources"
- **APK not opening**: Verify FileProvider configuration

### Windows Issues:
- **PowerShell execution policy**: Run as administrator
- **Update fails**: Check logs in temp directory
- **Backup not restoring**: Verify backup directory permissions

## Features

### Implemented:
✅ Version checking
✅ Mandatory update enforcement
✅ Download progress tracking
✅ Android APK installation
✅ Windows automatic update with UI
✅ Backup and rollback (Windows)
✅ Checksum verification
✅ Error handling and logging

### Future Enhancements:
- Delta updates (only changed files)
- Background downloads
- Update scheduling
- Offline update packages
- Multi-language support for updater UI

## File Structure

```
lib/
├── services/
│   └── update_service.dart          # Core update logic
├── providers/
│   └── update_provider.dart         # State management
└── presentation/
    └── widgets/
        └── update_dialog.dart       # Update UI

windows/
└── updater/
    └── WindowsUpdater.ps1          # Windows updater script

android/
└── app/
    └── src/
        └── main/
            ├── AndroidManifest.xml  # Permissions & FileProvider
            └── res/
                └── xml/
                    └── file_paths.xml  # FileProvider paths
```

## License
This update system is part of your application and follows the same license.

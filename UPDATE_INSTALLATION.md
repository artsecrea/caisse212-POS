# Quick Start: Update Service Installation

## 1. Install Dependencies

Run this command to install all required packages:

```bash
flutter pub get
```

**## 2. Android Setup (Manual Step Required)

Create the FileProvider configuration file:**

```bash
# Create directory
mkdir -p android/app/src/main/res/xml

# Create file: android/app/src/main/res/xml/file_paths.xml
```

**File content:**
```xml
<?xml version="1.0" encoding="utf-8"?>
<paths xmlns:android="http://schemas.android.com/apk/res/android">
    <external-path name="external_files" path="."/>
    <external-cache-path name="external_cache" path="."/>
</paths>
```

## 3. Implement Update Check API

Edit `lib/services/update_service.dart` and replace the `checkForUpdates()` method:

```dart
Future<UpdateInfo?> checkForUpdates() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    
    final response = await http.get(
      Uri.parse('YOUR_API_ENDPOINT/check-update'),
      headers: {
        'X-Platform': Platform.isAndroid ? 'android' : 'windows',
        'X-Current-Version': packageInfo.version,
        'X-App-Name': packageInfo.packageName,
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

## 4. Add Update Check to Login Screen

In your login screen (after successful authentication):

```dart
import '../providers/update_provider.dart';
import '../presentation/widgets/update_dialog.dart';

// After login success:
Future<void> _onLoginSuccess() async {
  // Check for updates
  await ref.read(updateProvider.notifier).checkForUpdates();
  
  final updateState = ref.read(updateProvider);
  
  if (updateState.availableUpdate != null && mounted) {
    // Show update dialog
    showUpdateDialog(
      context,
      isMandatory: updateState.updateRequired,
    );
    
    // If mandatory, don't proceed
    if (updateState.updateRequired) {
      return;
    }
  }
  
  // Navigate to main screen
  Navigator.pushReplacementNamed(context, '/main');
}
```

## 5. Backend API Format

Your update check endpoint should return:

**Android:**
```json
{
  "version": "1.2.0",
  "downloadUrl": "https://your-cdn.com/app-v1.2.0.apk",
  "isMandatory": true,
  "releaseNotes": "Bug fixes and improvements",
  "checksum": "sha256_hash_here"
}
```

**Windows:**
```json
{
  "version": "1.2.0",
  "downloadUrl": "https://your-cdn.com/app-v1.2.0.zip",
  "isMandatory": false,
  "releaseNotes": "New features added",
  "checksum": "sha256_hash_here"
}
```

## 6. Testing

### Test on Android:
```bash
# Build and install v1.0.0
flutter build apk --release

# Install on device
adb install build/app/outputs/flutter-apk/app-release.apk

# Update API to return v1.1.0
# Login and verify update dialog appears
```

### Test on Windows:
```bash
# Build v1.0.0
flutter build windows --release

# Create update package (v1.1.0)
cd build/windows/runner/Release
Compress-Archive -Path * -DestinationPath app-v1.1.0.zip

# Test updater manually
cd your-app-installation-directory
.\updater\LaunchUpdater.ps1 -UpdatePackagePath "C:\path\to\app-v1.1.0.zip"
```

## 7. Distribution Checklist

### Android:
- [x] APK signed with release keystore
- [x] Version number incremented in pubspec.yaml
- [x] Update available on your CDN/server
- [x] API returns correct update information
- [x] Checksum calculated and included

### Windows:
- [x] Application built in release mode
- [x] All files zipped (excluding user data folders)
- [x] `updater` folder included in distribution
- [x] Update ZIP hosted on CDN/server
- [x] API configured for Windows platform
- [x] Checksum calculated and included

## 8. Generate Checksums

### For APK:
```bash
sha256sum app-release.apk
```

### For ZIP:
```powershell
Get-FileHash -Path app-v1.2.0.zip -Algorithm SHA256
```

## Complete! 🎉

Your update service is ready to use. See `UPDATE_SERVICE_README.md` for detailed documentation.

## Quick Reference

**Files Created:**
- `lib/services/update_service.dart` - Core update service
- `lib/providers/update_provider.dart` - State management
- `lib/presentation/widgets/update_dialog.dart` - Update UI
- `windows/updater/WindowsUpdater.ps1` - Windows updater
- `windows/updater/LaunchUpdater.ps1` - Updater launcher
- `UPDATE_SERVICE_README.md` - Full documentation

**Modified Files:**
- `pubspec.yaml` - Added dependencies
- `android/app/src/main/AndroidManifest.xml` - Added permissions

**Manual Step:**
- Create `android/app/src/main/res/xml/file_paths.xml`

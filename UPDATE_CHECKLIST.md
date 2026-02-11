# ✅ Update Service Implementation Checklist

Use this checklist to ensure proper implementation of the update service.

## 📦 Initial Setup

- [ ] Run `flutter pub get` to install dependencies
- [ ] Create `android/app/src/main/res/xml/file_paths.xml`
- [ ] Verify AndroidManifest.xml has required permissions
- [ ] Verify pubspec.yaml has all dependencies
- [ ] Review all created files are present

### Quick Setup (Optional)
- [ ] Run `./setup_update_service.sh` (Linux/Mac)
- [ ] Run `setup_update_service.bat` (Windows)

## 🔧 Configuration

### Backend API
- [ ] Create update check API endpoint
- [ ] Implement version comparison logic
- [ ] Return proper JSON format (version, downloadUrl, etc.)
- [ ] Support both Android and Windows platforms
- [ ] Generate and include checksums

### Update Service
- [ ] Edit `lib/services/update_service.dart`
- [ ] Implement `checkForUpdates()` method
- [ ] Add your API endpoint URL
- [ ] Configure authentication headers if needed
- [ ] Test API connection

## 📱 Android Implementation

### Permissions
- [ ] INTERNET permission added
- [ ] WRITE_EXTERNAL_STORAGE permission added
- [ ] READ_EXTERNAL_STORAGE permission added
- [ ] REQUEST_INSTALL_PACKAGES permission added

### FileProvider
- [ ] file_paths.xml created
- [ ] FileProvider declared in AndroidManifest.xml
- [ ] Authority matches app package name

### Build & Sign
- [ ] Configure release signing in build.gradle
- [ ] Generate release keystore
- [ ] Sign APK with release key
- [ ] Test APK installation

## 💻 Windows Implementation

### Updater Script
- [ ] WindowsUpdater.ps1 present in windows/updater/
- [ ] LaunchUpdater.ps1 present in windows/updater/
- [ ] Scripts have correct execution policy settings
- [ ] Test updater manually with sample ZIP

### Build Configuration
- [ ] Include updater folder in release build
- [ ] Verify folder structure after build
- [ ] Test updater launch from app
- [ ] Verify admin elevation works

### Exclusions
- [ ] Configure folders to exclude from update
- [ ] Test that user data is preserved
- [ ] Verify logs, config preserved

## 🎨 UI Integration

### Update Dialog
- [ ] Import update_dialog.dart in login screen
- [ ] Import update_provider.dart
- [ ] Add ConsumerWidget or ConsumerStatefulWidget

### Login Flow
- [ ] Call checkForUpdates() after successful login
- [ ] Show update dialog if update available
- [ ] Block navigation if mandatory update
- [ ] Handle update errors gracefully

### Example Integration
```dart
// After successful login:
await ref.read(updateProvider.notifier).checkForUpdates();
final updateState = ref.read(updateProvider);

if (updateState.availableUpdate != null) {
  showUpdateDialog(context, isMandatory: updateState.updateRequired);
  if (updateState.updateRequired) return; // Block if mandatory
}

Navigator.pushReplacementNamed(context, '/main');
```

- [ ] Code added to login screen
- [ ] Tested with available update
- [ ] Tested with no update
- [ ] Tested with mandatory update

## 🧪 Testing

### Android Testing
- [ ] Build APK version 1.0.0
- [ ] Install on physical device or emulator
- [ ] Configure API to return version 1.1.0
- [ ] Login and verify dialog appears
- [ ] Click "Update Now"
- [ ] Verify download progress shows
- [ ] Verify system installer opens
- [ ] Complete installation
- [ ] Verify app updated successfully

### Windows Testing
- [ ] Build release version 1.0.0
- [ ] Create update ZIP for version 1.1.0
- [ ] Calculate ZIP checksum
- [ ] Host ZIP locally or on test server
- [ ] Configure API to return update info
- [ ] Login and verify dialog appears
- [ ] Click "Update Now"
- [ ] Verify download progress
- [ ] Verify updater launches with admin rights
- [ ] Watch updater UI progress
- [ ] Verify app closes and updates
- [ ] Verify app relaunches
- [ ] Check version updated

### Mandatory Update Testing
- [ ] Set isMandatory: true in API
- [ ] Verify dialog can't be dismissed
- [ ] Verify navigation blocked
- [ ] Verify users can't access app without updating

### Error Testing
- [ ] Test with invalid download URL
- [ ] Test with network disconnected
- [ ] Test with insufficient storage
- [ ] Test with wrong checksum
- [ ] Verify error messages shown
- [ ] Verify app doesn't crash

## 🔐 Security

### Checksums
- [ ] Generate SHA256 for each release
- [ ] Include in API response
- [ ] Verification enabled in code
- [ ] Test with wrong checksum (should fail)

### Download Security
- [ ] Use HTTPS for API
- [ ] Use HTTPS for file downloads
- [ ] Verify SSL certificates
- [ ] No hardcoded credentials

### Code Signing
- [ ] Android APKs signed with release key
- [ ] Windows executables code-signed (optional but recommended)
- [ ] Keep signing keys secure

## 📊 Monitoring & Analytics

### Logging
- [ ] Check logs in update_service.dart
- [ ] Windows updater logs enabled
- [ ] Errors logged properly
- [ ] Success events logged

### Analytics (Optional)
- [ ] Track update check calls
- [ ] Track update dialog shows
- [ ] Track update downloads
- [ ] Track update successes/failures
- [ ] Track version distribution

## 🚀 Deployment

### Pre-Release
- [ ] Test on multiple devices (Android)
- [ ] Test on different Windows versions
- [ ] Verify update works from each version
- [ ] Check file sizes reasonable
- [ ] Verify download speed acceptable

### CDN Setup
- [ ] Choose CDN provider
- [ ] Upload update files
- [ ] Configure CORS if needed
- [ ] Test download speed
- [ ] Setup backup CDN (optional)

### API Deployment
- [ ] Deploy update check API
- [ ] Configure for production
- [ ] Setup database for version tracking
- [ ] Test from production domain
- [ ] Monitor API performance

### Release Process
- [ ] Increment version number in pubspec.yaml
- [ ] Build Android release APK
- [ ] Build Windows release
- [ ] Calculate checksums
- [ ] Upload to CDN
- [ ] Update API with new version info
- [ ] Test update from previous version
- [ ] Monitor rollout

## 📋 Documentation

### User Documentation
- [ ] Write update instructions for users
- [ ] Document known issues
- [ ] Create FAQ for users
- [ ] Add to help/support section

### Developer Documentation
- [ ] Document API endpoints
- [ ] Document build process
- [ ] Document release procedure
- [ ] Update README.md

### Team Training
- [ ] Train team on update process
- [ ] Document rollback procedure
- [ ] Create incident response plan

## ✨ Final Verification

### Code Quality
- [ ] No compiler errors
- [ ] No warnings (or documented)
- [ ] Code follows project style
- [ ] Comments added where needed
- [ ] No TODO comments left

### Performance
- [ ] Update check doesn't slow login
- [ ] Download progress smooth
- [ ] UI remains responsive
- [ ] Memory usage acceptable

### User Experience
- [ ] Dialog text clear and friendly
- [ ] Progress feedback adequate
- [ ] Error messages helpful
- [ ] Update process smooth

### Production Ready
- [ ] All tests passing
- [ ] Security review complete
- [ ] Performance acceptable
- [ ] Documentation complete
- [ ] Team trained
- [ ] Rollback plan ready

## 🎉 Go Live!

- [ ] Merge to main branch
- [ ] Deploy backend API
- [ ] Upload initial release
- [ ] Monitor for issues
- [ ] Prepare hotfix process

---

## 📚 Resources

- 📖 Full Documentation: `UPDATE_SERVICE_README.md`
- 🚀 Installation Guide: `UPDATE_INSTALLATION.md`
- 📋 Implementation Summary: `UPDATE_IMPLEMENTATION_SUMMARY.md`
- ❓ FAQ: `UPDATE_FAQ.md`
- 💻 Code Example: `lib/examples/login_with_update_check_example.dart`

---

**Last Updated:** Ready for implementation
**Status:** Complete - Ready to deploy

---

### Notes:
_Use this checklist for each release that includes update service changes._
_Check off items as completed._
_Add notes for any deviations or issues found._

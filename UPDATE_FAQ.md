# Update Service - Frequently Asked Questions (FAQ)

## General Questions

### Q: How does the update service work?
**A:** The update service checks for new versions when users log in. If an update is available, it shows a dialog. Users can download and install updates directly from the app. On Android, it downloads an APK and opens the system installer. On Windows, it downloads a ZIP and runs a PowerShell updater that safely replaces app files.

### Q: Can I skip updates?
**A:** Only if the update is not marked as mandatory (`isMandatory: false`). Mandatory updates must be installed before the user can continue using the app.

### Q: How often are updates checked?
**A:** By default, updates are checked on every login. You can modify this behavior in your login screen implementation.

### Q: What happens if the update fails?
**A:** On Windows, the updater creates a backup before updating. If anything fails, it automatically restores from backup. On Android, if the download fails, users can retry.

## Implementation Questions

### Q: Do I need a separate backend API for updates?
**A:** Yes, you need an API endpoint that returns update information (version, download URL, mandatory flag, etc.). See `UPDATE_SERVICE_README.md` for the API format.

### Q: How do I set a mandatory update?
**A:** In your API response, set `"isMandatory": true`. The update dialog will block users from dismissing it.

### Q: Can I customize the update dialog?
**A:** Yes! Edit `lib/presentation/widgets/update_dialog.dart`. It's a standard Flutter widget you can fully customize.

### Q: How do I implement the update check API?
**A:** Edit the `checkForUpdates()` method in `lib/services/update_service.dart`. Replace the TODO with your API call. Example provided in documentation.

## Android Questions

### Q: Why do I need to create file_paths.xml manually?
**A:** Android 7.0+ requires FileProvider configuration for sharing files between apps (needed for APK installation). This XML file defines which paths can be shared.

### Q: What permissions are required on Android?
**A:** 
- `INTERNET` - Download updates
- `WRITE_EXTERNAL_STORAGE` - Save APK
- `READ_EXTERNAL_STORAGE` - Read saved APK
- `REQUEST_INSTALL_PACKAGES` - Install APK

These are already added to AndroidManifest.xml.

### Q: Users see "Install blocked" - what to do?
**A:** Users must enable "Install from unknown sources" in their device settings. Guide them:
1. Go to Settings → Security
2. Enable "Unknown Sources" or "Install from Unknown Sources"
3. Try again

### Q: Can I install APK without user interaction?
**A:** No, Android requires user consent for security. The system installer dialog will always appear.

### Q: Do I need to sign my APK?
**A:** Yes! Always sign release APKs with your keystore. Unsigned APKs won't install on most devices.

## Windows Questions

### Q: Why does the updater need admin rights?
**A:** To replace files in Program Files or other protected directories. The updater requests elevation automatically.

### Q: Can I run the updater without the UI?
**A:** Yes! Use the `-Silent` parameter when launching WindowsUpdater.ps1.

### Q: Which files are excluded from updates?
**A:** By default: `logs`, `data`, `config`, `user_data`. Configure this in the `ExcludeFolders` parameter.

### Q: What if users don't grant admin rights?
**A:** The update will fail. Show an error message asking them to run with administrator privileges.

### Q: Can I update while the app is running?
**A:** No, the updater must stop the application first to replace files. This is done automatically.

### Q: Where is the backup stored?
**A:** In `$env:TEMP\AppBackup` by default. Configure with `-BackupDirectory` parameter.

### Q: How long is the backup kept?
**A:** Until the next update. Each update removes the previous backup to save disk space.

## Security Questions

### Q: How do I verify update authenticity?
**A:** Use checksums! Calculate SHA256 hash of your update file and include it in the API response. The updater verifies it before installing.

### Q: Should I use HTTPS for downloads?
**A:** Absolutely! Always use HTTPS to prevent man-in-the-middle attacks.

### Q: Can someone inject malicious updates?
**A:** Not if you:
1. Use HTTPS for API and downloads
2. Verify checksums
3. Sign your APKs (Android)
4. Code sign executables (Windows)
5. Secure your update server

### Q: What if my CDN gets compromised?
**A:** Checksum verification will catch modified files. The update will fail rather than install compromised code.

## Testing Questions

### Q: How do I test updates locally?
**A:** 
- **Android**: Build two APK versions, install v1, configure API to return v2 URL
- **Windows**: Use `file:///` URLs to point to local ZIP files

### Q: Can I test without publishing?
**A:** Yes! Host update files on your local network or test server. Just use the appropriate URL.

### Q: How do I test mandatory updates?
**A:** Set `"isMandatory": true` in your test API response. Verify the dialog can't be dismissed.

### Q: How do I calculate checksums for testing?
**A:**
```bash
# Linux/Mac
sha256sum your-update-file.apk

# Windows PowerShell
Get-FileHash -Path your-update-file.zip -Algorithm SHA256
```

## Troubleshooting

### Q: Update dialog doesn't appear?
**A:** Check:
1. Is `checkForUpdates()` being called?
2. Is your API returning data?
3. Is the version in API response higher than current?
4. Check console logs for errors

### Q: Download fails on Android?
**A:** Check:
1. Storage permissions granted?
2. Sufficient storage space?
3. Network connection stable?
4. Download URL accessible?

### Q: Windows updater shows "script not found"?
**A:** Ensure the `updater` folder is included in your Windows distribution. It should be in the same directory as your executable.

### Q: Backup/restore fails on Windows?
**A:** Check:
1. Sufficient disk space?
2. User has admin rights?
3. Antivirus not blocking?
4. Files not locked by other processes?

### Q: App doesn't relaunch after update?
**A:** Check:
1. Executable name correct?
2. Executable in expected location?
3. Permissions preserved?
4. Check updater logs

## Best Practices

### Q: How often should I release updates?
**A:** Balance between feature delivery and user experience. Frequent updates can annoy users. Consider:
- Critical security fixes: Mandatory, immediate
- Bug fixes: Optional, weekly/monthly
- New features: Optional, monthly/quarterly

### Q: Should I force updates immediately?
**A:** Only for critical security issues. Give users a grace period for optional updates.

### Q: How do I notify users about updates?
**A:** The update dialog shows release notes. Write clear, user-friendly descriptions of changes.

### Q: Should I version Windows and Android separately?
**A:** No, keep versions in sync for simpler management. Your API can return different URLs for each platform.

### Q: How do I handle users on old versions?
**A:** Set minimum supported version in your API. If user's version is too old, force a mandatory update.

## Performance Questions

### Q: Does update checking slow down login?
**A:** Minimal impact. The check is a simple HTTP request. Downloads only happen if user initiates them.

### Q: How big can update files be?
**A:** No hard limit, but consider:
- **Android APK**: 50-200MB typical
- **Windows ZIP**: Larger is fine, but test with slow connections
- Show progress bar for user feedback

### Q: Can I resume interrupted downloads?
**A:** Not in current implementation. Failed downloads must restart. This is a potential enhancement.

## Deployment Questions

### Q: Where should I host update files?
**A:** Options:
- Cloud CDN (AWS S3, Google Cloud Storage, Azure Blob)
- Your own server with good bandwidth
- GitHub Releases (for open source)

### Q: How do I roll back bad updates?
**A:** Change your API to return the previous version number and URL. The "new" version will be the old stable one.

### Q: Can I do staged rollouts?
**A:** Not built-in, but you can implement in your API:
- Return different versions based on user ID
- Gradually increase percentage of users getting new version
- Monitor for issues before full rollout

### Q: How do I track update adoption?
**A:** Add analytics in your app:
- Log version on app start
- Track update dialog interactions
- Monitor update success/failure rates

## Advanced Questions

### Q: Can I update individual files instead of full app?
**A:** The Windows updater supports selective updates via ZIP structure. Android requires full APK.

### Q: Can I schedule updates for off-hours?
**A:** Not built-in. You could add:
- Download in background
- Prompt user to apply at next startup
- Schedule with OS task scheduler

### Q: How do I handle multiple update servers?
**A:** Implement failover in `update_service.dart`:
```dart
final servers = ['primary-cdn.com', 'backup-cdn.com'];
for (final server in servers) {
  try {
    return await downloadFrom(server);
  } catch (e) {
    continue; // Try next server
  }
}
```

### Q: Can I sign updates cryptographically?
**A:** Beyond checksums, you could:
- Sign update metadata with private key
- Verify signature with public key in app
- Requires custom implementation

## Need More Help?

- 📖 Full Documentation: `UPDATE_SERVICE_README.md`
- 🚀 Installation Guide: `UPDATE_INSTALLATION.md`
- 📋 Implementation Summary: `UPDATE_IMPLEMENTATION_SUMMARY.md`
- 💻 Code Example: `lib/examples/login_with_update_check_example.dart`

**Still have questions?** Check the inline code comments or create a GitHub issue!

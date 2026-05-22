# Update System — Backend & Release Guide

## How It Works

```
App boot
  └─ desktop_update_provider → DesktopUpdaterController → fetches app-archive.json
                                                         → shows UpdateDialogListener overlay

After login (Android only)
  └─ UpdateService.checkForUpdates() → fetches app-archive.json
                                     → finds matching platform item
                                     → UpdateNotifier compares versions
                                     → shows UpdateDialog
```

---

## 1. Backend Requirements

### Endpoint

```
GET {baseUrl_without_/api}/pos/app-archive.json
```

Example: if `api_base_url` stored in app is `https://app.caisse212.com/api`,
serve the file at:
```
https://app.caisse212.com/pos/app-archive.json
```

This file must be **publicly readable** (no auth required) — the app fetches it before or during login.

### `app-archive.json` Schema

```json
{
  "appName": "CAISSE212",
  "description": "POS Terminal Updates",
  "items": [
    {
      "version": "1.2.0",
      "shortVersion": 5,
      "date": "2026-05-22",
      "platform": "linux",
      "url": "https://app.caisse212.com/updates/1.2.0/linux/",
      "sha256": "",
      "mandatory": false,
      "changes": [
        { "message": "Fixed order sync issue" },
        { "message": "Improved printer reliability" }
      ]
    },
    {
      "version": "1.2.0",
      "shortVersion": 5,
      "date": "2026-05-22",
      "platform": "windows",
      "url": "https://app.caisse212.com/updates/1.2.0/windows/",
      "sha256": "",
      "mandatory": false,
      "changes": [
        { "message": "Fixed order sync issue" }
      ]
    },
    {
      "version": "1.2.0",
      "shortVersion": 5,
      "date": "2026-05-22",
      "platform": "android",
      "url": "https://app.caisse212.com/updates/1.2.0/app-release.apk",
      "sha256": "abc123deadbeef...",
      "mandatory": false,
      "changes": [
        { "message": "Fixed order sync issue" }
      ]
    }
  ]
}
```

**Required fields per item:**
| Field | Type | Notes |
|-------|------|-------|
| `version` | string | semver, e.g. `"1.2.0"` |
| `shortVersion` | int | increment each release |
| `date` | string | `YYYY-MM-DD` |
| `platform` | string | `linux` / `windows` / `macos` / `android` / `ios` |
| `url` | string | direct download URL (details below) |
| `changes` | array | each item needs `"message"` key |

**Optional:**
| Field | Type | Notes |
|-------|------|-------|
| `sha256` | string | APK checksum (Android); app verifies if non-empty |
| `mandatory` | bool | blocks login if true and update available |

---

## 2. Desktop Update URL Format (`desktop_updater` package)

For Linux/Windows/macOS, `url` must point to a **directory** (trailing slash), not a file.
The `desktop_updater` package expects to find specific files inside that directory.

### Linux

```
url: "https://yourserver.com/updates/1.2.0/linux/"
```

Files the package downloads from that dir:
```
app-linux-x86_64.tar.gz   (the release bundle, tar'd)
```

Create tar from Flutter Linux release:
```bash
# After: flutter build linux --release
tar -czf app-linux-x86_64.tar.gz -C build/linux/x64/release/bundle .
# Upload to: https://yourserver.com/updates/1.2.0/linux/app-linux-x86_64.tar.gz
```

### Windows

```
url: "https://yourserver.com/updates/1.2.0/windows/"
```

```bash
# After: flutter build windows --release
# Zip the release dir
cd build/windows/x64/runner/Release
zip -r app-windows-x86_64.zip .
# Upload to: https://yourserver.com/updates/1.2.0/windows/app-windows-x86_64.zip
```

### Android

```
url: "https://yourserver.com/updates/1.2.0/app-release.apk"
```

Direct APK URL. App downloads it and opens the system installer.

---

## 3. Release Build Steps

### Increment version first

`pubspec.yaml`:
```yaml
version: 1.2.0+5   # semver+shortVersion — both must match app-archive.json
```

### Linux release

```bash
flutter build linux --release

# Package
tar -czf app-linux-x86_64.tar.gz -C build/linux/x64/release/bundle .

# Checksum (optional but good)
sha256sum app-linux-x86_64.tar.gz
```

Upload `app-linux-x86_64.tar.gz` to server at `<url>/app-linux-x86_64.tar.gz`.

### Windows release

```bash
flutter build windows --release

# Package (run on Windows or use zip tool)
cd build/windows/x64/runner/Release
zip -r app-windows-x86_64.zip .
```

Upload to `<url>/app-windows-x86_64.zip`.

### Android release

```bash
# Signed APK
flutter build apk --release

# Output: build/app/outputs/flutter-apk/app-release.apk

# Get sha256
sha256sum build/app/outputs/flutter-apk/app-release.apk
```

Upload APK directly; set `sha256` field in `app-archive.json`.

---

## 4. Deploy Checklist (each release)

```
[ ] Bump version in pubspec.yaml  (e.g. 1.2.0+5)
[ ] flutter build linux --release
[ ] flutter build windows --release  (on Windows machine or CI)
[ ] flutter build apk --release
[ ] Package Linux: tar -czf app-linux-x86_64.tar.gz -C build/linux/x64/release/bundle .
[ ] Package Windows: zip build/windows/x64/runner/Release/
[ ] Upload artifacts to server update directory
[ ] Compute sha256 of APK
[ ] Update app-archive.json:
    - Bump version + shortVersion + date
    - Update all url fields to new release paths
    - Set sha256 for android item
    - Set mandatory: true if critical fix
[ ] Serve updated app-archive.json at /pos/app-archive.json
[ ] Test: set update_archive_url_override in settings to point at test JSON
```

---

## 5. Testing the Update Flow

In app Settings (or via SharedPreferences tool), set:
```
update_archive_url_override = http://localhost:9090/pos/app-archive.json
```
This bypasses the derived URL and hits your local server directly.
Clear it to restore production behavior.

---

## 6. Mandatory Updates

Set `"mandatory": true` in the item. App behavior:
- **Desktop**: `UpdateDialogListener` shows dialog, user cannot dismiss
- **Android**: `UpdateDialog` blocks navigation to `/main` after login

Use for breaking API changes or critical security fixes only.

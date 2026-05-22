# Update Logic Audit

## TL;DR

Two separate update paths exist. Desktop path mostly works. Android path **will fail**. Both have gaps.

---

## Architecture Overview

| Path | File | Trigger | Status |
|------|------|---------|--------|
| Desktop (Linux/Windows/macOS) | `desktop_update_provider.dart` | `UpdateDialogListener` in `main.dart` | ✅ Works if JSON correct |
| Android | `update_service.dart` + `update_provider.dart` | `_checkForUpdates()` in `login_screen.dart` | ❌ Fails |

---

## Issues Found

### Critical — Android path broken

**1. Hardcoded localhost URL (`update_service.dart:88`)**
```dart
// todo
final url = 'http://localhost:9090/api/pos/app-archive.json';
```
`baseUrl` is read from SharedPrefs above (line 82–85) then completely ignored. Every production device hits `localhost:9090` → connection refused.

**Fix:**
```dart
final url = _deriveArchiveUrl(baseUrl); // same logic as desktop_update_provider.dart
```
Or extract `_deriveArchiveUrl` to a shared util and reuse it.

---

**2. Android 13+ storage permission broken (`update_service.dart:147`)**
```dart
final status = await Permission.storage.request();
```
`Permission.storage` is `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` — deprecated on API 33+. On Android 13+ this returns `permanentlyDenied` without showing a prompt.

**Fix — use app-specific dir (no permission needed):**
```dart
final dir = await getApplicationSupportDirectory(); // no permission required
```
Or if you must use external storage on API 33+:
```dart
final status = await Permission.manageExternalStorage.request();
```
But app-specific dir is simpler and works everywhere.

---

**3. JSON schema mismatch**

`UpdateInfo.fromJson` (`update_service.dart:29`) expects a flat object:
```json
{ "version": "1.0.1", "url": "...", "sha256": "...", "mandatory": true }
```

But `desktop_update_provider.dart` (and server) uses:
```json
{
  "appName": "CAISSE212",
  "description": "...",
  "items": [{ "version": "1.0.1", "url": "...", "platform": "android", ... }]
}
```

`UpdateInfo.fromJson` will crash on `response.data` because it's an object containing `items`, not the flat schema it expects.

**Fix — parse items array and find matching platform:**
```dart
factory UpdateInfo.fromArchiveJson(Map<String, dynamic> json, String platform) {
  final items = (json['items'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  final item = items.firstWhere(
    (i) => i['platform'] == platform,
    orElse: () => {},
  );
  if (item.isEmpty) throw Exception('No item for platform $platform');
  return UpdateInfo(
    appName: json['appName'] as String? ?? '',
    platform: platform,
    version: item['version'] as String,
    downloadUrl: item['url'] as String,
    checksum: item['sha256'] as String? ?? '',
    isMandatory: item['mandatory'] as bool? ?? false,
    releaseNotes: (item['changes'] as List?)
        ?.map((c) => c['message'] as String? ?? '')
        .join('\n'),
  );
}
```

---

### Medium — Checksum verification missingcle

`update_service.dart:185–194` — commented out. Downloaded APK is never verified.

**Fix:**
```dart
import 'dart:convert';
import 'package:crypto/crypto.dart';

Future<String> _calculateSha256(File file) async {
  final bytes = await file.readAsBytes();
  return sha256.convert(bytes).toString();
}
```
Add `crypto: ^3.0.3` to `pubspec.yaml`.

---

### Low — Redundant update check on desktop

`login_screen.dart` calls `updateProvider.notifier.checkForUpdates()` which calls `UpdateService.checkForUpdates()` — but on desktop, `UpdateDialogListener` in `main.dart` already handles updates independently via `desktop_updater` package. Two checks run; `UpdateService` check on desktop hits the hardcoded localhost URL and returns `null` silently, so no crash — just wasted network call.

**Fix — skip `UpdateService` check on desktop:**
```dart
Future<void> _checkForUpdates() async {
  if (!Platform.isAndroid) return; // desktop handled by UpdateDialogListener
  // ... rest of android check
}
```

---

## What Works

- **Desktop `desktop_update_provider.dart`** — URL derivation correct, debug validation thorough, `_SafeDesktopUpdaterController` swallows parse errors, `UpdateDialogListener` wired in `main.dart`. Works end-to-end once server serves correct JSON.
- **Version comparison** (`update_provider.dart:165`) — correct semver compare.
- **`UpdateDialog` widget** — correct progress display, mandatory blocking, dismissal logic.
- **`UpdateInfo` model fields** — correct if JSON schema is fixed.

---

## Required `app-archive.json` Format (server-side)

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
      "url": "https://yourserver.com/updates/1.2.0/linux/",
      "sha256": "abc123...",
      "mandatory": false,
      "changes": [
        { "message": "Bug fixes and performance improvements" }
      ]
    },
    {
      "version": "1.2.0",
      "shortVersion": 5,
      "date": "2026-05-22",
      "platform": "android",
      "url": "https://yourserver.com/updates/1.2.0/app-release.apk",
      "sha256": "def456...",
      "mandatory": false,
      "changes": [
        { "message": "Bug fixes and performance improvements" }
      ]
    }
  ]
}
```

Server must serve this at `{baseUrl_without_/api}/pos/app-archive.json`.

---

## Fix Priority Order

1. **`update_service.dart:88`** — replace hardcoded URL with derived URL (10 min)
2. **`update_service.dart:147`** — replace `Permission.storage` with `getApplicationSupportDirectory()` (10 min)
3. **`update_service.dart:115`** — replace `UpdateInfo.fromJson(response.data)` with `UpdateInfo.fromArchiveJson(response.data, _platform)` (20 min)
4. **`login_screen.dart`** — skip update check on desktop (5 min)
5. **Checksum** — add `crypto` dep + implement verification (30 min)

Items 1–4 make Android update functional. Item 5 is security hardening.

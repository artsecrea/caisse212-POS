# Update Logic — caisse212

Two independent update systems run in parallel, targeting different platforms and endpoints.

---

## System A — `UpdateService` + `UpdateNotifier` (Android + optional desktop fallback)

### Flow

```
App startup / manual trigger
        │
        ▼
UpdateNotifier.checkForUpdates()
  1. PackageInfo.fromPlatform() → currentVersion
  2. GET <baseUrl>/api/pos/update_check?platform=<platform>
     Headers: Authorization: Bearer <token>
              X-POS-Name: <posName>
              X-Tenant-ID: <tenantId>
        │
        ├── 404 / null → no update available, state cleared
        │
        └── 200 + UpdateInfo JSON
              ├── _compareVersions(remote, local)
              │     semver: major.minor.patch (3-part only)
              │
              ├── remote > local → state.availableUpdate set, show UpdateDialog
              │     isMandatory → updateRequired = true (dialog not dismissible)
              │
              └── remote ≤ local → up to date, state cleared
```

### UpdateInfo JSON shape (from `api/pos/update_check`)

```json
{
  "version":     "1.2.0",
  "downloadUrl": "https://…/app.apk",
  "sha256":      "abc123…",
  "mandatory":   false,
  "releaseNotes": "Bug fixes",
  "platform":    "android",
  "appName":     "caisse212"
}
```

### Download / Install (Android only)

```
UpdateNotifier.downloadAndInstall()
  └── Platform.isAndroid
        1. Request storage permission
        2. getExternalStorageDirectory() → filePath
        3. Dio.download(downloadUrl, filePath, onProgress)
        4. ⚠ Checksum NOT verified (TODO in update_service.dart:185)
        5. OpenFilex.open(filePath) → system APK installer
```

### Desktop path in System A

For Windows/macOS/Linux, `downloadAndInstall()` returns `true` immediately without downloading anything. The `UpdateDialog` shows "Update started" as a prompt to look for System B's UI. **Actual install is handled by System B.**

---

## System B — `desktop_updater` package (Windows / macOS / Linux only)

### Flow

```
App startup
  └── desktopUpdaterControllerProvider created
        appArchiveUrl = <baseUrl>/pos/app-archive.json
        (baseUrl already contains /api, e.g. https://app.caisse212.com/api)
              │
              ▼
        _SafeDesktopUpdaterController.checkVersion()
          ← errors swallowed silently (malformed JSON, 404, etc.)
              │
              ├── no update → nothing shown
              │
              └── update found → desktop_updater renders its own UI widget
                    "Mise à jour disponible" banner / dialog (French UI)
                    user clicks download → desktop_updater downloads archive
                    user clicks restart → app restarts with new binary
```

### `app-archive.json` shape (served at `<baseUrl>/pos/app-archive.json`)

```json
{
  "appName": "CAISSE212",
  "description": "Latest release",
  "items": [
    {
      "version": "1.2.0",
      "shortVersion": 2,
      "changes": [{ "message": "Bug fixes" }],
      "date": "2026-04-29",
      "mandatory": false,
      "url": "<baseUrl>/updates/1.2.0-linux",
      "platform": "linux"
    }
  ]
}
```

`appName` and `description` are **required non-null** — the app will silently skip the update check if either is missing.

---

## Interaction between System A and System B

| Concern | System A | System B |
|---|---|---|
| Platform | Android (primary), desktop (stub) | Windows, macOS, Linux |
| Endpoint | `/api/pos/update_check` | `/pos/app-archive.json` |
| Auth | Bearer token + tenant headers | None (public URL) |
| UI | Custom `UpdateDialog` widget | `desktop_updater` built-in UI |
| Download | Dio → APK → OpenFilex | `desktop_updater` internal |
| Mandatory enforcement | `isMandatory` flag, dialog not dismissible | `mandatory` field in JSON |

Both systems check independently at startup. On desktop, System A may show its dialog first, but clicking "Update Now" only returns `true` without downloading — the actual download/install is delegated to System B's widget which must be present in the widget tree via `DesktopUpdateWidget` / `UpdateDialogListener`.

---

## Known Issues / Risks

| # | Location | Issue |
|---|---|---|
| 1 | `update_service.dart:185` | **Checksum not verified** — APK downloaded but sha256 not checked before install |
| 2 | `update_service.dart:55` | `SharedPreferences.getInstance()` called directly, not via injected `sharedPreferencesProvider` |
| 3 | `update_service.dart` | No download timeout configured on `Dio` — hangs indefinitely on slow connections |
| 4 | `update_provider.dart:169` | `_compareVersions` only handles 3-part semver; 4-part versions (e.g. `1.2.3.4`) silently truncated |
| 5 | Desktop UX | System A's "Update started" snackbar shown even though no download occurred on desktop |
| 6 | `update_dialog.dart` | `WillPopScope` replaced with `PopScope` (was using deprecated API) ✓ fixed |
| 7 | `update_dialog.dart` | `releaseNotes!` null crash fixed → `(releaseNotes ?? '').isNotEmpty` ✓ fixed |
| 8 | `update_provider.dart` | `dismissUpdate()` lost `currentVersion` ✓ fixed (uses `copyWith(clearUpdate: true)`) |

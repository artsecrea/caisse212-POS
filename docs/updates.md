# caisse212 POS — App Updates (deploy & backend guide)

How to ship a new version of the POS client to deployed terminals. Covers
both update paths the app supports today:

| Platform | Mechanism | Backend surface |
|---|---|---|
| **Android** | Custom `GET /api/pos/update_check` + APK download + system installer | One JSON endpoint + one APK file per release |
| **Windows / macOS / Linux** | `desktop_updater` Flutter plugin reading `app-archive.json` | Static archive JSON + one zip per platform per release |
| **iOS** | App Store only | None — App Store handles it |
| **Web** | n/a | The client skips the check on web |

This doc is the **operations manual** for the dev/ops team. The client side
is already wired (see `lib/services/update_service.dart` and
`lib/providers/desktop_update_provider.dart`).

---

## 1. URLs the client expects

The app reads `api_base_url` from SharedPreferences (set on the tenant-login
screen). Two derived URLs flow from it:

```
api_base_url:          https://example.com/api

Android check URL:     https://example.com/api/pos/update_check?platform=<android|windows|macos|linux>
Desktop archive URL:   https://example.com/pos/app-archive.json
```

Rules:
- The **trailing `/api`** is stripped to compute the desktop archive URL.
- The Android check URL re-appends `/api` and adds `/pos/update_check`.
- `platform` query param is one of `android | windows | macos | linux | ios`.

### Headers the client sends on the Android check
```
Authorization: Bearer <server_access_token>
X-POS-Name:    <pos_name>
X-Tenant-ID:   <tenant_id>
```
All three are optional — return the same response for an unauthenticated
request (the update info isn't sensitive). If you want to gate updates per
tenant / per POS, key off these headers server-side.

### Dev override
If you need to point a specific terminal at a staging update host without
changing `api_base_url`, set this SharedPreferences key on the device:

```dart
prefs.setString('update_archive_url_override',
    'http://localhost:9090/pos/app-archive.json');
```

This bypasses the URL derivation entirely (desktop only).

---

## 2. Android — `GET /api/pos/update_check?platform=android`

Returns the **latest released version for that platform**, or `404` (or empty
body) when there is no newer version.

### Response body (200 OK)
```json
{
  "appName":      "caisse212",
  "platform":     "android",
  "version":      "1.0.3",
  "url":          "https://cdn.example.com/pos/android/caisse212-1.0.3.apk",
  "sha256":       "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  "mandatory":    false,
  "releaseNotes": "• Fixed receipt double-print on slow networks\n• Added cash-count step to session close"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `appName` | string | no | Cosmetic; the dialog ignores it |
| `platform` | string | no | Echoed back; the client doesn't check |
| `version` | string | **yes** | `MAJOR.MINOR.PATCH`. Client compares semver against `PackageInfo.version` |
| `url` | string | **yes** | Direct download URL to the signed APK |
| `sha256` | string | recommended | Lowercase hex SHA-256 of the APK. If non-empty, the client refuses to install on mismatch |
| `mandatory` | bool | no | `true` ⇒ dialog can't be dismissed; if the user cancels, the login flow refuses to proceed |
| `releaseNotes` | string | no | Free-form newline-separated text; rendered in the dialog under "What's new" |

### When NO update is available
Return either:
- HTTP `404`, **or**
- HTTP `200` with an empty body / `null` / `{}`.

The client treats all of these as "no update".

### What the client does with the response
1. Compares `version` to `PackageInfo.fromPlatform().version` (semver-aware).
2. If the response is **strictly greater**, shows `UpdateDialog`.
3. Tapping **Update now** → downloads the APK to the app's private cache,
   verifies the SHA-256, then calls `OpenFilex.open(filePath)`.
4. The OS shows its standard "Install this update?" prompt; the user taps
   Install. If the new APK is signed with the **same keystore** as the
   installed one, the install succeeds without uninstall.

### Signing the APK
- Use **the same upload keystore** for every release. If you change keys,
  every device must uninstall + reinstall, losing all local data.
- For **Play Store** distributions you generally won't use this flow — Play
  Store handles updates. This endpoint is for **direct-distributed** APKs
  (kiosk fleets, sideloaded devices, etc.).

### File hosting layout (suggested)
```
/var/www/cdn/pos/
└── android/
    ├── caisse212-1.0.0.apk
    ├── caisse212-1.0.1.apk
    ├── caisse212-1.0.2.apk
    └── caisse212-1.0.3.apk
```
- Keep old APKs around so devices that missed an update can still catch up.
- Filenames don't have to follow this pattern — the URL in the JSON is what
  matters; the filename is opaque to the client.

### Generating the SHA-256
```bash
sha256sum caisse212-1.0.3.apk
# 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08  caisse212-1.0.3.apk
```

---

## 3. Desktop — `app-archive.json`

The desktop client uses the **`desktop_updater` Flutter plugin**, which
periodically polls a static JSON manifest. When a newer version is found
for the current platform, the plugin's overlay banner appears; the user
clicks → download → restart → swap done.

### URL
```
https://example.com/pos/app-archive.json
```
(Derived by stripping the trailing `/api` from `api_base_url`.)

### File format
```json
{
  "appName": "CAISSE212",
  "description": "POS Terminal Updates",
  "items": [
    {
      "version":      "1.0.3",
      "shortVersion": 4,
      "platform":     "windows",
      "url":          "https://cdn.example.com/pos/desktop/1.0.3/caisse212-windows-x64.zip",
      "date":         "2026-06-02",
      "mandatory":    false,
      "changes": [
        { "message": "Fixed receipt double-print on slow networks" },
        { "message": "Added cash-count step to session close" }
      ]
    },
    {
      "version":      "1.0.3",
      "shortVersion": 4,
      "platform":     "macos",
      "url":          "https://cdn.example.com/pos/desktop/1.0.3/caisse212-macos.zip",
      "date":         "2026-06-02",
      "mandatory":    false,
      "changes": [{ "message": "Fixed receipt double-print on slow networks" }]
    },
    {
      "version":      "1.0.3",
      "shortVersion": 4,
      "platform":     "linux",
      "url":          "https://cdn.example.com/pos/desktop/1.0.3/caisse212-linux-x64.zip",
      "date":         "2026-06-02",
      "mandatory":    false,
      "changes": [{ "message": "Fixed receipt double-print on slow networks" }]
    }
  ]
}
```

### Required fields

**Top-level:**
| Field | Type | Notes |
|---|---|---|
| `appName` | string | Cosmetic; shown in the overlay |
| `description` | string | Cosmetic |
| `items` | array | One entry per platform per release. See below |

**Per item:**
| Field | Type | Notes |
|---|---|---|
| `version` | string | `MAJOR.MINOR.PATCH` — compared to `PackageInfo.version` |
| `shortVersion` | int | Monotonically-increasing build number — compared to `PackageInfo.buildNumber`. Bump on every release |
| `platform` | string | `windows` \| `macos` \| `linux` — must match the running OS exactly |
| `url` | string | Direct download URL to a **zip** (see §3.2) |
| `date` | string | `YYYY-MM-DD` — shown in the overlay |
| `mandatory` | bool | Optional. `true` ⇒ overlay can't be dismissed |
| `changes` | array | Optional. Each entry must have a `message` field |

> ⚠ Each `changes[]` item **must use `message`**, not `title`/`description`.
> The plugin's `_SafeDesktopUpdaterController` will pre-validate and log a
> warning to debug console if you use the wrong field name.

### 3.2 What the zip contains

The plugin downloads the URL, expects a **zip archive**, and replaces the
running app's bundle with the unzipped contents.

Build the zip from a clean release build:

```bash
# Windows
flutter build windows --release
# Output: build/windows/x64/runner/Release/
cd build/windows/x64/runner/Release/
zip -r ../../caisse212-windows-x64.zip .

# Linux
flutter build linux --release
cd build/linux/x64/release/bundle/
zip -r ../../caisse212-linux-x64.zip .

# macOS
flutter build macos --release
cd build/macos/Build/Products/Release/
zip -r ../../caisse212-macos.zip caisse212.app
```

The zip **should not contain a wrapping directory** — `caisse212.exe` (or
`caisse212` / `caisse212.app`) should be at the root of the archive. The
plugin extracts straight into the running app's install folder.

### 3.3 File hosting layout (suggested)
```
/var/www/cdn/pos/desktop/
├── 1.0.0/
│   ├── caisse212-windows-x64.zip
│   ├── caisse212-macos.zip
│   └── caisse212-linux-x64.zip
├── 1.0.1/
│   └── ...
└── 1.0.3/
    ├── caisse212-windows-x64.zip
    ├── caisse212-macos.zip
    └── caisse212-linux-x64.zip
```

The archive JSON only ever points at the **latest** zip per platform.
Older zips can be kept for rollback but aren't referenced.

---

## 4. iOS

The client returns `'ios'` from `UpdateService.currentPlatform`, but
**`downloadAndInstallUpdate` is a no-op on iOS**. App Store sideload-style
APK installs aren't allowed; updates ship through TestFlight or the App
Store.

**Recommendation:** don't return an item with `platform: "ios"` from the
update_check endpoint today. (A future client improvement, deferred from the
last planning session, will detect this and redirect to an App Store URL.)

---

## 5. Mandatory updates

Both Android and desktop respect a `mandatory: true` flag.

- The dialog/overlay **cannot be dismissed** (no "Later" button).
- On Android, if the user cancels the install prompt, the login flow refuses
  to proceed and shows "A mandatory update is required to continue."
- On desktop, the overlay stays on top of the app until the user updates.

Use it sparingly — for security fixes, breaking sync-protocol changes, or
critical bug fixes that affect cash handling. Rolling a routine feature
update as mandatory will frustrate cashiers mid-shift.

---

## 6. Release checklist

For every new client version (e.g. `1.0.3`):

1. **Bump `pubspec.yaml`** version: `version: 1.0.3+4` (semver + build number).
2. **Build the artifacts**:
   ```bash
   flutter build apk --release                    # Android: build/app/outputs/apk/release/app-release.apk
   flutter build windows --release                # Windows: build/windows/x64/runner/Release/
   flutter build macos --release                  # macOS:   build/macos/Build/Products/Release/
   flutter build linux --release                  # Linux:   build/linux/x64/release/bundle/
   ```
3. **Sign the APK** with the production keystore (Gradle release config).
4. **Zip the desktop bundles** (see §3.2) — three zip files.
5. **Compute SHA-256** of the APK and record it.
6. **Upload** the four binaries to your CDN, keeping the suggested layouts.
7. **Update `app-archive.json`** — replace the three desktop items (or
   add three new ones) with the new `version`, `shortVersion`, `url`, and
   today's `date`. Validate it with `jq . app-archive.json`.
8. **Update the Android `update_check` response** server-side so future
   polls return `1.0.3` instead of `1.0.2`.
9. **Smoke-test** on a staging terminal of each platform:
   - Android: install old build → tap login → dialog appears → install →
     verify SHA-256 passes → app reopens at new version.
   - Desktop: launch old build → overlay appears → click → app restarts →
     `About` tab in Settings shows the new version.
10. **Roll out**. Watch backend logs for `/pos/update_check` 404 spikes
    (devices catching up) and CDN bandwidth.

---

## 7. Testing locally

You can serve the update infrastructure from a plain HTTP server — no
HTTPS needed in dev.

```bash
mkdir -p /tmp/pos-cdn/pos/android /tmp/pos-cdn/pos/desktop/1.0.3
# Copy your built APK + zips into those folders, then:
cd /tmp/pos-cdn
python3 -m http.server 9090
```

Then on the device set the override:
```dart
prefs.setString('update_archive_url_override',
    'http://<your-laptop-ip>:9090/pos/app-archive.json');
```

For the Android endpoint there's no override — temporarily point
`api_base_url` at `http://<your-laptop-ip>:9090/api` and serve a fake
`/api/pos/update_check` response with a 1-line Python or Node shim.

---

## 8. Endpoints summary

| Method | URL | Purpose |
|---|---|---|
| `GET` | `/api/pos/update_check?platform=android` | Returns the latest Android update JSON, or `404`/empty if none |
| `GET` | `/pos/app-archive.json` | Static JSON manifest read by the desktop plugin |
| `GET` | `/pos/android/caisse212-<ver>.apk` | The signed APK (URL is what you returned in `update_check`) |
| `GET` | `/pos/desktop/<ver>/caisse212-<platform>.zip` | The per-platform desktop zip (URL is what you put in `app-archive.json`) |

`update_check` is the **only dynamic endpoint** — everything else is
static-file hosting.

---

## 9. Common gotchas

- **APK signing mismatch** → "App not installed" on the device. Fix: use
  the same release keystore every time.
- **`changes` array uses `title`/`description` instead of `message`** →
  desktop overlay silently drops them. Fix: rename to `message`.
- **Zip contains a wrapping folder** → desktop_updater extracts into a
  sub-folder and the new exe never replaces the running one. Fix: zip the
  *contents* of the release dir, not the dir itself.
- **`platform` mismatch** → desktop overlay never appears because the
  plugin filters by exact platform string. Use `windows`/`macos`/`linux`
  in lowercase.
- **`shortVersion` not bumped** → the plugin sees the same build number and
  treats the release as "already installed", even if `version` differs.
  Always bump both.
- **SHA-256 wrong case** → the client lowercases before comparing, but you
  should still emit lowercase hex to avoid surprises.
- **Mandatory dialog leaks across restarts** → today on Android the user can
  relaunch and dismiss again (see deferred enforcement work). If you need
  hard enforcement, return `mandatory: true` AND remove old APK URLs from
  the CDN so even an interactive sideload can't install the old version.

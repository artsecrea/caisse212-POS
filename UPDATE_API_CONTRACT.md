# Update API Contract — `/pos/updates/latest`

Single authenticated endpoint that replaces the old dual-system (static CDN + `desktop_updater`).

---

## Endpoint

```
GET /pos/updates/latest?platform={platform}
```

### Headers (sent automatically by the POS client)

| Header | Value | Source |
|--------|-------|--------|
| `Authorization` | `Bearer {accessToken}` | ApiService interceptor |
| `X-Business-Id` | `{businessId}` | ApiService interceptor |
| `X-Tenant-ID` | `{tenantId}` | ApiService interceptor |
| `X-POS-Name` | `{posName}` | ApiService interceptor |
| `X-Pos-Id` | `{posTerminalId}` | ApiService interceptor |

### Query Parameters

| Param | Values | Required |
|-------|--------|----------|
| `platform` | `windows` \| `linux` \| `macos` \| `android` \| `ios` | yes |

---

## Responses

### 200 — Update available

```json
{
  "version":      "1.2.0",
  "buildNumber":  5,
  "mandatory":    false,
  "releaseNotes": "Fixed sync issue on reconnect. Improved printer reliability.",
  "downloadUrl":  "https://pub-xxx.r2.dev/updates/1.2.0/windows/caisse212-1.2.0-setup.exe",
  "sha256":       "a3f2c1d9e4b7...",
  "sizeBytes":    47185920,
  "platform":     "windows",
  "publishedAt":  "2026-07-03T10:00:00Z"
}
```

### 404 — No update available (or no release exists for this platform)

Return HTTP `404`. Body is ignored by the client.

### No-content variant (alternative to 404)

HTTP `200` with body `null` or `{}` is also safe — the client treats it as "no update".

---

## Field Reference

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `version` | string | yes | Semver `major.minor.patch` |
| `buildNumber` | int | yes | Monotonically increasing |
| `mandatory` | bool | yes | `true` → update dialog is not dismissible |
| `releaseNotes` | string\|null | no | Plain text, shown in update dialog |
| `downloadUrl` | string | yes | Direct URL to the installable binary |
| `sha256` | string | yes | Hex SHA-256 of the binary; client verifies before install |
| `sizeBytes` | int\|null | no | Used to show download progress accurately |
| `platform` | string | no | Echo of the requested platform |
| `publishedAt` | string\|null | no | ISO 8601 |

> **Android/iOS note:** For `android` the client downloads the APK from `downloadUrl` directly.
> For `ios` the endpoint can return 404 — App Store handles iOS updates.

---

## Version comparison logic (client-side)

The client compares `version` (remote) against the running `PackageInfo.version` (local).
Only shows the update dialog when `remote > local` by semver.
`buildNumber` is stored but not used in the comparison — it's informational only.

---

## R2 Release Folder Structure

Files must be publicly accessible at the `downloadUrl` the backend returns.
Recommended layout on Cloudflare R2 (or any CDN):

```
updates/
└── {version}/
    ├── windows/
    │   └── caisse212-{version}-setup.exe        ← NSIS/Inno installer
    ├── linux/
    │   └── caisse212-{version}.AppImage         ← self-contained AppImage
    ├── macos/
    │   └── caisse212-{version}.dmg              ← signed disk image
    └── android/
        └── caisse212-{version}.apk              ← release APK
```

**Examples for version `1.2.0`:**

| Platform | R2 key | Public URL |
|----------|--------|------------|
| Windows | `updates/1.2.0/windows/caisse212-1.2.0-setup.exe` | `https://pub-xxx.r2.dev/updates/1.2.0/windows/caisse212-1.2.0-setup.exe` |
| Linux | `updates/1.2.0/linux/caisse212-1.2.0.AppImage` | `https://pub-xxx.r2.dev/updates/1.2.0/linux/caisse212-1.2.0.AppImage` |
| macOS | `updates/1.2.0/macos/caisse212-1.2.0.dmg` | `https://pub-xxx.r2.dev/updates/1.2.0/macos/caisse212-1.2.0.dmg` |
| Android | `updates/1.2.0/android/caisse212-1.2.0.apk` | `https://pub-xxx.r2.dev/updates/1.2.0/android/caisse212-1.2.0.apk` |

---

## Backend DB Model (minimal)

```sql
CREATE TABLE app_releases (
  id            SERIAL PRIMARY KEY,
  version       VARCHAR(20)   NOT NULL,
  build_number  INT           NOT NULL,
  platform      VARCHAR(20)   NOT NULL,          -- windows|linux|macos|android
  download_url  TEXT          NOT NULL,           -- full R2 public URL
  sha256        VARCHAR(64)   NOT NULL,
  size_bytes    BIGINT,
  mandatory     BOOLEAN       NOT NULL DEFAULT false,
  release_notes TEXT,
  enabled       BOOLEAN       NOT NULL DEFAULT true,
  published_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (version, platform),
  UNIQUE (build_number, platform)
);
```

Query for the endpoint:

```sql
SELECT * FROM app_releases
WHERE platform = $1
  AND enabled = true
ORDER BY build_number DESC
LIMIT 1;
```

---

## Install behavior per platform (client)

| Platform | Client action after download |
|----------|------------------------------|
| Android | `OpenFilex.open(apkPath)` → system APK installer |
| Windows | `Process.start(exePath, [], runInShell: true, mode: detached)` |
| Linux | `chmod +x AppImage` → `Process.start(path, [], mode: detached)` |
| macOS | `Process.start(dmgPath, [], mode: detached)` (opens Finder mount) |
| iOS | Client never downloads — endpoint returns 404 |

---

## Admin Upload Checklist

```bash
# 1. Build
flutter build windows --release
flutter build linux --release
flutter build apk --release

# 2. Compute SHA-256
sha256sum build/windows/runner/Release/caisse212.exe
sha256sum build/linux/x64/release/bundle/caisse212
sha256sum build/app/outputs/flutter-apk/app-release.apk

# 3. Upload binaries to R2
# (use existing upload_release.sh or a direct rclone/wrangler command)

# 4. POST to backend to register the release
curl -X POST https://app.caisse212.com/api/admin/releases \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "version":      "1.2.0",
    "buildNumber":  5,
    "platform":     "windows",
    "downloadUrl":  "https://pub-xxx.r2.dev/updates/1.2.0/windows/caisse212-1.2.0-setup.exe",
    "sha256":       "a3f2c1d9e4b7...",
    "sizeBytes":    47185920,
    "mandatory":    false,
    "releaseNotes": "Fixed sync issue. Improved printer reliability."
  }'
```

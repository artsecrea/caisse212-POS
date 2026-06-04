# Releasing a Windows Update — Runbook

Step-by-step checklist for cutting a new Windows release of caisse212 and
shipping it through the flat static-manifest channel.

This is the **per-release** doc. For background on the update mechanism and
the Android side, see `docs/updates.md` (note: parts of that doc still
describe the old tenant-backend flow — the URL section is superseded by what
you see here).

---

## What the flow looks like

```
┌──────────────────────────────────────────────────────────────────┐
│ 1. Bump version in pubspec.yaml                                  │
│ 2. flutter build windows --release                               │
│ 3. Zip the Release folder contents                               │
│ 4. Upload zip to    https://update.caisse212.com/builds/...      │
│ 5. Edit + upload    https://update.caisse212.com/windows-archive.json │
│ 6. Smoke-test on a staging terminal                              │
└──────────────────────────────────────────────────────────────────┘
```

No backend code runs. No tenant URL is involved. The running POS polls the
manifest on its own schedule via `desktop_updater`, sees the new version,
shows the overlay, downloads the zip on user confirmation, swaps itself out,
and restarts.

---

## Per-release steps

### 1. Bump the version

Edit `pubspec.yaml`:

```yaml
version: 1.0.1+2
#        ^^^^^ ^
#        |     └── build number → becomes `shortVersion` in the manifest
#        └──────── semver       → becomes `version` in the manifest
```

Rules:
- **Always bump both.** The `desktop_updater` plugin uses `shortVersion`
  (the build number) to decide "is this newer than what I'm running". If you
  only bump the semver, devices may not detect the update.
- `shortVersion` must be **strictly greater** than the currently-deployed
  build number. Monotonically increasing integers only.
- Semver is for humans (release notes, dialog text). It's compared too but
  the build number is the authoritative tie-breaker.

### 2. Build

From the repo root:

```powershell
flutter build windows --release
```

Output lands in `build\windows\x64\runner\Release\`. Contents look like:

```
build\windows\x64\runner\Release\
├── caisse212.exe
├── flutter_windows.dll
├── data\
│   ├── flutter_assets\
│   ├── icudtl.dat
│   └── ...
└── (plugin DLLs: bonsoir_windows_plugin.dll, sqlite3.dll, ...)
```

### 3. Zip the Release folder *contents*

> **Critical:** zip the *contents* of the Release folder, not the folder
> itself. The zip's top level must contain `caisse212.exe` directly. If the
> zip has a wrapping folder (`Release/caisse212.exe`), `desktop_updater`
> extracts into a subfolder and the swap silently fails.

```powershell
$version = "1.0.1"
$out = "build\caisse212-windows-x64-$version.zip"
Compress-Archive -Path "build\windows\x64\runner\Release\*" `
                 -DestinationPath $out `
                 -Force
```

Verify with:

```powershell
# Should list caisse212.exe at the top, not Release\caisse212.exe
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $out)).Entries |
    Select-Object -First 5 FullName
```

### 4. Upload the zip

Drop the file into the bucket/CDN at a stable path. Suggested layout:

```
https://update.caisse212.com/
├── windows-archive.json
└── builds/
    ├── caisse212-windows-x64-1.0.0.zip
    ├── caisse212-windows-x64-1.0.1.zip     ← new
    └── ...
```

Keep older zips around for rollback. The manifest is the *only* file that
points at "the current" zip — the zips themselves are immutable artifacts.

### 5. Update `windows-archive.json`

Replace (or add) the Windows item. **Don't append a new item — replace the
existing windows one**, otherwise the plugin sees two candidates and the
behavior depends on order.

Minimum manifest for a Windows-only deployment:

```json
{
  "appName": "CAISSE212",
  "description": "POS Terminal Updates",
  "items": [
    {
      "version": "1.0.1",
      "shortVersion": 2,
      "platform": "windows",
      "url": "https://update.caisse212.com/builds/caisse212-windows-x64-1.0.1.zip",
      "date": "2026-06-03",
      "mandatory": false,
      "changes": [
        { "message": "Fix printer dispatch silent failures" },
        { "message": "Retention purge now leaves customers + sessions alone" }
      ]
    }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `version` | yes | Must match `pubspec.yaml` semver |
| `shortVersion` | yes | Must match `pubspec.yaml` build number (after the `+`) |
| `platform` | yes | Literal `"windows"` (lowercase) |
| `url` | yes | Direct download URL to the zip from step 4 |
| `date` | yes | `YYYY-MM-DD` — shown in the overlay |
| `mandatory` | no | `true` ⇒ user can't dismiss the overlay. Use sparingly. |
| `changes` | no | Each entry **must** be `{"message": "..."}` — *not* `title` or `description`. The plugin drops items with the wrong field name. |

Validate before uploading:

```powershell
# Will throw if the JSON is malformed.
Get-Content windows-archive.json -Raw | ConvertFrom-Json | Out-Null
```

### 6. Upload the manifest

Overwrite `https://update.caisse212.com/windows-archive.json`.

If your CDN has aggressive caching, **purge the cache** for that URL.
Otherwise terminals will keep seeing the old manifest for hours.

### 7. Smoke-test on one staging terminal

1. Open the POS on a staging Windows machine running the *previous* version.
2. Wait for the overlay (or trigger a manual check from Settings → "Check
   for updates").
3. Click through → wait for download → confirm restart.
4. After relaunch, open Settings → About and confirm the new version number
   is shown.

If the overlay doesn't appear within a minute, see Troubleshooting.

### 8. Roll out

Once staging is green, the same manifest is live for every Windows terminal.
There's no per-tenant gating — when the file is updated, every Windows POS
that polls sees the new version. Watch your CDN logs for download-rate
spikes (devices catching up) and 404s (clients trying to download a zip you
forgot to upload).

---

## "No update right now"

To explicitly tell terminals there's no update — useful during incident
response when you've pulled a bad release — overwrite the manifest with an
empty items list:

```json
{
  "appName": "CAISSE212",
  "description": "POS Terminal Updates",
  "items": []
}
```

The plugin parses this fine and shows nothing.

You can also just delete the manifest entirely (HTTP 404). The
`_SafeDesktopUpdaterController` swallows the parse failure cleanly — see
`lib/providers/desktop_update_provider.dart`.

---

## Rolling back a bad release

Two paths:

1. **Republish the previous version as if it were newer.** Bump the
   `shortVersion` to be higher than the bad one, but point `url` at the
   *old* zip. Terminals on the bad version will "update" back to the old
   binary. This is the cleanest path because it uses the existing update
   flow.

2. **Pull the bad zip from the CDN.** Terminals already on the bad version
   are stuck on it until you ship a fix. New terminals trying to download
   will 404 (the plugin handles this gracefully). Combine with path (1) for
   the actual fix.

There is no automatic downgrade — `desktop_updater` only ever installs
versions with a *higher* `shortVersion` than the running build. So a
rollback is structurally an upgrade-to-the-old-binary with a new build
number.

---

## Local testing without touching production

To iterate on the manifest format or a build locally:

```powershell
# 1. Serve a folder containing windows-archive.json + the zip
cd C:\tmp\pos-cdn
python -m http.server 9090
```

```dart
// 2. On the device, set the override pref BEFORE the app starts the updater check.
//    Easiest: temporary code in main.dart, or a hidden setting in Settings.
final prefs = await SharedPreferences.getInstance();
await prefs.setString(
  'update_archive_url_override',
  'http://192.168.1.10:9090/windows-archive.json', // your laptop IP
);
```

The provider in `lib/providers/desktop_update_provider.dart` checks this
override first; if set, the production URL is bypassed entirely. Remove the
override before shipping to a real device.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Overlay never appears | `shortVersion` not bumped, or equal to running build number | Bump `shortVersion` in `pubspec.yaml` *and* the manifest |
| Overlay appears but download fails | Zip URL returns 404, or wrong MIME type from the CDN | Verify the URL in a browser; CDN should serve as `application/zip` |
| Overlay appears, download succeeds, restart leaves you on the old version | Zip has a wrapping `Release\` folder at its root | Re-zip with the contents directly at the root |
| Release notes don't appear | `changes` items use `title`/`description` instead of `message` | Rename the field to `message` |
| Plugin logs "Missing required top-level fields" in debug | Manifest missing `appName`, `description`, or `items` | Add them — see schema above |
| Plugin logs "item[0] missing fields: [date]" | A per-item required field is missing | Compare against the schema table in step 5 |

Live debug output from the controller is logged with the `[DesktopUpdater]`
prefix — search the running POS's debug console.

---

## Where the wiring lives in code

- `lib/providers/desktop_update_provider.dart`
  - `_kDesktopUpdateBaseUrl` — change to point at production CDN
  - `_archiveUrlForCurrentPlatform()` — derives `{base}/windows-archive.json`
  - `_SafeDesktopUpdaterController` — pre-validates the JSON; logs clear errors
- `lib/main.dart` — overlays `UpdateDialogListener` on top of the app on
  desktop platforms

If you change the manifest URL, change it in `_kDesktopUpdateBaseUrl` only;
the per-platform suffix is computed.

---

## Security notes (read once)

- **Anyone with write access to the bucket can push code to every Windows
  POS.** Lock down the bucket's write IAM. HTTPS is necessary but not
  sufficient.
- `desktop_updater` does **not** verify a SHA-256 of the zip — unlike the
  Android path. If you want integrity verification on Windows too, that's a
  client-side change to make. Mention it before pushing the first
  production release.
- The `mandatory: true` flag pins the user inside the overlay until they
  update. Use it only for security fixes, breaking sync changes, or
  cash-handling bugs. Routine feature updates as mandatory will frustrate
  cashiers mid-shift.

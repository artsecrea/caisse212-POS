# CAISSE212 — Release & Update Guide

Follow these steps **every time** you want to publish a new version of the app.

---

## Prerequisites (one-time setup)

Install the `desktop_updater` CLI tool on your dev machine:
```bash
dart pub global activate desktop_updater
```

Make sure your server exposes:
- `GET /api/pos/app-archive.json` — the update manifest
- Static file serving for the update folders (e.g. nginx or Spring Boot static resources)

---

## Step 1 — Bump the version in `pubspec.yaml`

```yaml
# Format:  version: MAJOR.MINOR.PATCH+BUILD_NUMBER
#                                        ^^^^^^^^^^^
#                                        This number is compared by the app.
#                                        Always increment it.

version: 1.0.1+2   # ← was 1.0.0+1
```

> ⚠️ The **build number** (after `+`) is what `desktop_updater` compares against the
> installed version. If it is not higher than the installed build number, no update
> dialog will appear.

---

## Step 2 — Build the release app

Run for **every platform** you want to ship:

```bash
flutter build windows --release
flutter build linux   --release
flutter build macos   --release   # macOS only
flutter build apk     --release   # Android only
```

---

## Step 3 — Generate the update archive (desktop only)

Run from the **root of your project** for each desktop platform:

```bash
# Windows
dart run desktop_updater:release windows
dart run desktop_updater:archive windows

# Linux
dart run desktop_updater:release linux
dart run desktop_updater:archive linux

# macOS
dart run desktop_updater:release macos
dart run desktop_updater:archive macos
```

This creates a `dist/` folder like:
```
dist/
  2/                          ← your build number
    1.0.1+2-windows/          ← upload this entire folder
      hashes.json             ← file manifest (auto-generated, do not edit)
      posecrea.exe
      flutter_windows.dll
      data/
      ...
    1.0.1+2-linux/            ← upload this entire folder
      hashes.json
      posecrea
      lib/
      data/
      ...
```

> ⚠️ **Upload the folder, NOT a zip.**
> The updater downloads `hashes.json` first, then only fetches the files that
> changed since the user's installed version (delta update).

---

## Step 4 — Upload to your server via the upload API

ZIP the contents of the generated platform folder (files must be at ZIP root):

```bash
# Windows example — ZIP the contents, not the folder itself
cd dist/2/1.0.1+2-windows
zip -r ../../../update-windows.zip .

# Linux example
cd dist/2/1.0.1+2-linux
zip -r ../../../update-linux.zip .
```

Then POST to your server:

```bash
# Windows
curl -X POST https://app.caisse212.com/api/pos/upload-update \
  -H "Authorization: Bearer <admin-token>" \
  -F "file=@update-windows.zip" \
  -F "version=1.0.1" \
  -F "shortVersion=2" \
  -F "platform=windows" \
  -F "mandatory=false" \
  -F 'changes=[{"type":"fix","message":"Bug fixes"}]' \
  -F "date=2026-04-22"

# Linux
curl -X POST https://app.caisse212.com/api/pos/upload-update \
  -H "Authorization: Bearer <admin-token>" \
  -F "file=@update-linux.zip" \
  -F "version=1.0.1" \
  -F "shortVersion=2" \
  -F "platform=linux" \
  -F "mandatory=false" \
  -F 'changes=[{"type":"fix","message":"Bug fixes"}]' \
  -F "date=2026-04-22"
```

The server will:
1. Extract the ZIP to `/updates/1.0.1+2-windows/`
2. Update the `app-archive.json` manifest automatically
3. POS apps will see the update on their next startup

> ⚠️ The ZIP must contain files **at the root level** (hashes.json at ZIP root).
> Use `cd` into the folder before zipping, as shown above.

## Step 5 — Verify the manifest was updated

The upload API automatically updates `app-archive.json`. Verify it looks correct:

```bash
curl https://app.caisse212.com/api/pos/app-archive.json \
  -H "Authorization: Bearer <pos-token>" \
  -H "X-POS-Name: test"
```

Expected response:
```json
{
  "appName": "CAISSE212",
  "description": "POS Terminal Updates",
  "items": [
    {
      "version": "1.0.1",
      "shortVersion": 2,
      "changes": [...],
      "date": "2026-04-22",
      "mandatory": false,
      "url": "https://app.caisse212.com/updates/1.0.1+2-windows",
      "platform": "windows"
    }
  ]
}
```

---

## Step 6 — Verify

1. Start the **old** version of the app on a client machine
2. The app calls `/api/pos/app-archive.json` on startup
3. It compares `shortVersion` from the server against the installed build number
4. If server's `shortVersion` is higher → **update dialog appears automatically**
5. User clicks **Download** → only changed files are fetched from the folder
6. User clicks **Restart** → app restarts with the new version ✅

---

## Checklist — every release

```
[ ] 1. Bump version + build number in pubspec.yaml
[ ] 2. flutter build <platform> --release
[ ] 3. dart run desktop_updater:release <platform>
[ ] 4. dart run desktop_updater:archive <platform>
[ ] 5. cd dist/<buildNumber>/<version>+<build>-<platform> && zip -r update-<platform>.zip .
[ ] 6. POST /api/pos/upload-update with the zip + metadata (server handles the rest)
[ ] 7. Test: open old version → update dialog appears → update succeeds
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No update dialog | `shortVersion` not incremented | Bump build number in `pubspec.yaml` |
| App crashes on update check | `appName` or `description` is null in JSON | Add both fields to `app-archive.json` |
| Files not found after update | Wrong `url` in JSON | URL must point to the **folder**, not a zip |
| Update downloads but doesn't apply | Wrong platform string | Use exactly `"windows"` / `"linux"` / `"macos"` |
| Double `/api/api/` in URL | Stored `api_base_url` already contains `/api` | Use `/pos/app-archive.json` suffix only |


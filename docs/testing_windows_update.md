# Testing the Windows Update Flow Locally

Step-by-step recipe for proving the update pipeline works end-to-end **on
your own machine**, without touching the production CDN. Takes ~10 minutes
once you read it through.

The trick: the desktop updater already has a built-in override mechanism
(`update_archive_url_override` in SharedPreferences) that bypasses the
production URL when set. You point it at a local Python HTTP server,
upload your "new version" to that server, and watch the installed "old
version" detect and install the update.

---

## What you need

- Two builds of caisse212:
  - **OLD** — the version currently running on your test Windows machine.
    Could be the version already deployed there, or a fresh build with a
    deliberately-old version number.
  - **NEW** — a higher version number, packaged as the `.zip` the updater
    expects.
- A folder to serve files from (any local folder, doesn't have to be
  inside the repo).
- The LAN IP of the machine running the HTTP server (or `localhost` if
  the same machine runs both the server and the app).

---

## Step-by-step

### 1. Pick versions for the test

Open `pubspec.yaml` and look at the current `version:` line. As of writing
it's:

```yaml
version: 1.0.0+1
```

For this test, treat that as the OLD version (what's installed). The NEW
version needs **both** numbers strictly higher:

```yaml
version: 1.0.1+2
```

(The `+N` part — `shortVersion` in the manifest — is the one
`desktop_updater` actually compares. Without bumping it, the overlay
won't appear.)

### 2. Build OLD first, install it on the test machine

```powershell
# Make sure pubspec.yaml is at the OLD version (e.g. 1.0.0+1)
flutter build windows --release
```

Copy the contents of `build\windows\x64\runner\Release\` onto the test
machine (or use the local dev one if testing same-machine). Run the
`.exe` once so it's the "installed" version.

> If you're not sure what's currently installed, open the app and check
> Settings → About — the version shown there is the OLD version for this
> test.

### 3. Build NEW and package it

Bump `pubspec.yaml` to the NEW version:

```yaml
version: 1.0.1+2
```

Then run the release script — pass `--base-url` so the manifest points at
your local server, not the production CDN:

```powershell
python scripts\release_windows.py --base-url http://192.168.1.X:9090
```

Replace `192.168.1.X` with your machine's LAN IP — find it with
`ipconfig` (look for "IPv4 Address" under your active adapter). If you're
testing on the same machine, `http://127.0.0.1:9090` also works.

The script will prompt for semver, build number, changelog, then:
- Update `pubspec.yaml`
- Run `flutter build windows --release`
- Zip the Release folder contents
- Write `build\release\windows-archive.json` + `caisse212-windows-x64-1.0.1.zip`

The manifest's `url` field now points at
`http://192.168.1.X:9090/builds/caisse212-windows-x64-1.0.1.zip`.

### 4. Serve the artifacts locally

```powershell
mkdir C:\tmp\update-test
mkdir C:\tmp\update-test\builds
copy build\release\windows-archive.json C:\tmp\update-test\
copy build\release\caisse212-windows-x64-1.0.1.zip C:\tmp\update-test\builds\
cd C:\tmp\update-test
python -m http.server 9090
```

Leave that terminal running. Verify in a browser:
- `http://192.168.1.X:9090/windows-archive.json` shows the manifest JSON
- `http://192.168.1.X:9090/builds/caisse212-windows-x64-1.0.1.zip` starts
  a download

If either 404s, fix the file layout before continuing — the app won't be
able to download what the browser can't.

### 5. Tell the installed OLD app to use the local URL

The desktop updater reads `update_archive_url_override` from
SharedPreferences. If set, it uses that exact URL and bypasses
`https://update.caisse212.com` entirely.

The easiest one-shot way to set it: add this block at the top of
`_initializeApp()` in `lib/main.dart`, **temporarily**:

```dart
// TEMP-UPDATE-TEST: remove after the test.
final prefsTmp = await SharedPreferences.getInstance();
await prefsTmp.setString(
  'update_archive_url_override',
  'http://192.168.1.X:9090/windows-archive.json',
);
```

Rebuild + re-deploy the OLD version with this line in place, OR just run
it once via `flutter run` on the test machine to set the pref, then
remove the line. SharedPreferences persists across launches, so once the
pref is set, the OLD version uses the override from then on.

> Alternative if you don't want to touch `main.dart`: add a hidden dev
> setting in the Settings screen that calls
> `ref.read(updateArchiveUrlOverrideProvider.notifier).setOverride(url)`.
> One-time scaffolding cost; reusable afterward.

### 6. Launch the OLD app and watch the update appear

Open the OLD app. Within a minute (the desktop_updater polls on a
schedule), an overlay should appear in the bottom-right reading:

> caisse212 1.0.1 is available
> Tap to download (X MB)

Click → download bar progresses → "Restart to update" → click → app
relaunches.

After relaunch, **Settings → About should show the NEW version**
(`1.0.1+2`). If it does, the pipeline works end-to-end.

### 7. Clean up after the test

Three things to undo:

1. **Remove the `TEMP-UPDATE-TEST` block in `main.dart`** if you added
   it. Without removal, every fresh install would point at your laptop
   IP — a non-starter for production.
2. **Clear the override pref on the test machine** so it goes back to
   the production URL. Either:
   - Add `await prefsTmp.remove('update_archive_url_override');` to
     `main.dart` temporarily, run once, then remove.
   - Or write `clearOverride()` from the dev setting if you added one.
3. **Revert the `pubspec.yaml` bump** if you don't want 1.0.1+2 in your
   git history (the release script committed nothing — it's just a file
   change). Either `git checkout pubspec.yaml` or keep the bump and call
   it the start of release 1.0.1.

---

## Quick smoke checks during the test

| What you observe | What it means |
|---|---|
| No overlay appears within 90s | OLD app isn't hitting your URL. Check the override pref is set; check the OLD app's version is **strictly less** than NEW's `shortVersion`; check the server is reachable in a browser from the OLD machine. |
| Overlay says wrong version | The manifest you uploaded has wrong values. Edit `windows-archive.json` in `C:\tmp\update-test\`, re-save, click the overlay again (no app restart needed). |
| Click overlay → download fails | The zip URL in the manifest 404s, or the path is wrong, or you forgot to copy the zip into `builds\`. |
| Download OK → restart prompt → app doesn't relaunch new version | Zip layout problem. The zip should have `caisse212.exe` at its **root**, not under a `Release\` subfolder. Re-run `release_windows.py` — its `Compress-Archive` step is correct. |
| "Update failed" toast | Open the running app's debug console (if attached) and look for `[DesktopUpdater]` lines. They log every step with clear errors. |

---

## What this proves vs what it doesn't

**Proves:**
- The flat-manifest URL is reachable from the OLD app.
- Manifest format is parsed correctly by `desktop_updater`.
- Version comparison logic detects "newer".
- Zip structure is what the package expects.
- The swap + restart works on Windows.

**Doesn't prove:**
- Production CDN configuration (CORS, caching, MIME type).
- HTTPS certificate handling — local test runs on HTTP.
- Behavior under mandatory-update / rollback scenarios — those are
  separate manifest edits; once the basic flow works, flip the
  `mandatory` field and re-test.

---

## TL;DR command sequence (copy-pasteable)

```powershell
# 1. Build NEW + package, manifest pointed at local server
python scripts\release_windows.py --base-url http://192.168.1.X:9090

# 2. Serve it
mkdir C:\tmp\update-test\builds -Force
copy build\release\windows-archive.json C:\tmp\update-test\
copy build\release\caisse212-windows-x64-*.zip C:\tmp\update-test\builds\
cd C:\tmp\update-test
python -m http.server 9090
# (leave this running)

# 3. On the test machine: set override pref ONCE (via main.dart hack
#    or hidden dev setting), then launch OLD app and wait for overlay.

# 4. After verifying: revert pubspec, clear override, remove hack.
```

You don't need to touch `_kDesktopUpdateBaseUrl` for this test. The
override pref is the supported mechanism — `_kDesktopUpdateBaseUrl`
stays pointed at production the whole time.

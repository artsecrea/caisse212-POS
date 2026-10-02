---
name: pos-build
description: Build and package the CAISSE212 Windows POS - flutter release build, exe renamed to caisse212.exe, update zip for the updates server, and Inno Setup installer. Use when the user asks to build, release, package, bump the version, make the zip/installer/setup, or "pos <command>".
---

# CAISSE212 Windows build

Everything goes through `pos.ps1` at the repo root (engine: `build_windows.ps1`, installer script: `installer/caisse212.iss`). Do not hand-roll `flutter build` + zip + ISCC steps.

## Commands

Run from the repo root with the PowerShell tool:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\pos.ps1 <command> [arg]
```

| Command | Does |
|---|---|
| `build` | build current pubspec version -> zip + installer |
| `release` | patch+1 and build+1 in pubspec -> build -> zip + installer |
| `release 1.3.0` | set version 1.3.0, build+1 -> build -> zip + installer |
| `pack` | skip flutter build, repackage last build -> zip + installer |
| `zip` | build -> zip only |
| `setup` | skip flutter build -> installer only |
| `version` | print pubspec version |

## How to run it

- A real build takes several minutes: use `timeout: 600000`, or `run_in_background: true` and wait for the notification.
- `release` edits `pubspec.yaml`. Only use it when the user asked for a new version; otherwise use `build`. Never commit unless asked.
- Tills only take an update whose build number is higher than theirs - if the user wants to publish, the build number must go up.
- `pack`/`setup` package whatever is already in `build\windows\x64\runner\Release` - say so if the code changed since the last build.

## Report back

The script ends with an `[OK]` block. Relay to the user: version (`<ver>+<build>`), zip path, zip **size** and **sha256** (needed to publish on the updates server), and the installer path. Output folder: `build\release\`.

On `[FAIL]`, show the failing step and its output. Common causes: flutter compile error (show the Dart errors), `ISCC.exe` missing (Inno Setup 6 not installed), `posecrea.exe not found` (flutter build did not produce the exe).

## Facts that matter

- Flutter's exe is `posecrea.exe` (CMake `BINARY_NAME`); the script renames it to `caisse212.exe` in `build\release\bundle`. The bundle must contain exactly one top-level `.exe` - the in-app updater depends on it.
- The installer (AppId `DD01BD8F-...`, never change it) upgrades in place: kills `caisse212.exe` / legacy `posecrea.exe`, replaces files, relaunches (also with `/VERYSILENT`). Per-user install by default so the in-app updater needs no UAC. The DB lives in Documents and is never touched.
- Don't install the setup on the dev PC to "test" it without asking - it closes the running POS.

#!/usr/bin/env python3
"""
release_windows.py - cut a Windows release of caisse212.

What it does, in order:
  1. Reads pubspec.yaml, prompts for the new semver + build number
     (suggests +1 on the patch and +1 on the build).
  2. Prompts for changelog entries and the `mandatory` flag.
  3. Writes the new version line back to pubspec.yaml.
  4. Runs `flutter build windows --release`.
  5. Zips the *contents* of build\\windows\\x64\\runner\\Release\\
     into build\\release\\caisse212-windows-x64-{ver}.zip
     (contents at zip root, no wrapping folder).
  6. Generates build\\release\\windows-archive.json pointing at the zip's
     URL on the configured CDN.
  7. Prints the upload instructions and a `git tag` suggestion.

Run from anywhere; the script resolves the repo root from its own path.

    python scripts\\release_windows.py
    python scripts\\release_windows.py --base-url https://cdn.example.com
    python scripts\\release_windows.py --skip-build   # re-package without rebuilding

Stdlib only; no pip install needed.
"""

from __future__ import annotations

import argparse
import datetime
import json
import re
import subprocess
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = REPO_ROOT / "pubspec.yaml"
RELEASE_DIR = REPO_ROOT / "build" / "windows" / "x64" / "runner" / "Release"
OUT_DIR = REPO_ROOT / "build" / "release"

DEFAULT_BASE_URL = "https://update.caisse212.com"
APP_NAME = "CAISSE212"
DESCRIPTION = "POS Terminal Updates"

# Matches e.g. `version: 1.0.0+1` (allows trailing whitespace).
VERSION_RE = re.compile(r"^(version:\s*)(\d+\.\d+\.\d+)\+(\d+)\s*$", re.MULTILINE)


def die(msg: str) -> "None":
    print(f"[FAIL] {msg}", file=sys.stderr)
    sys.exit(1)


def prompt(question: str, default: str | None = None) -> str:
    suffix = f" [{default}]" if default is not None else ""
    try:
        val = input(f"{question}{suffix}: ").strip()
    except EOFError:
        die("stdin closed")
    return val or (default or "")


def yes(question: str, default_no: bool = True) -> bool:
    default = "n" if default_no else "y"
    val = prompt(f"{question} (y/n)", default=default).lower()
    return val in ("y", "yes")


def bump_patch(semver: str) -> str:
    a, b, c = semver.split(".")
    return f"{a}.{b}.{int(c) + 1}"


def read_pubspec() -> tuple[str, str, int]:
    text = PUBSPEC.read_text(encoding="utf-8")
    m = VERSION_RE.search(text)
    if not m:
        die(f"No `version: X.Y.Z+N` line in {PUBSPEC}")
    return text, m.group(2), int(m.group(3))


def write_pubspec(text: str, new_semver: str, new_build: int) -> None:
    new_text = VERSION_RE.sub(rf"\g<1>{new_semver}+{new_build}", text, count=1)
    if new_text == text:
        die("Failed to rewrite the version line (regex didn't match on replace)")
    PUBSPEC.write_text(new_text, encoding="utf-8")


def collect_changes() -> list[dict]:
    print("Changelog entries (one per line, blank line to finish):")
    out: list[dict] = []
    while True:
        try:
            line = input(f"  [{len(out) + 1}] ").strip()
        except EOFError:
            break
        if not line:
            break
        out.append({"message": line})
    return out


def zip_release_contents(zip_path: Path) -> int:
    if zip_path.exists():
        zip_path.unlink()
    file_count = 0
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for path in RELEASE_DIR.rglob("*"):
            if path.is_file():
                # arcname is relative to the Release folder so caisse212.exe
                # lands at the root of the zip (no wrapping directory) — the
                # desktop_updater plugin requires this layout.
                zf.write(path, path.relative_to(RELEASE_DIR))
                file_count += 1
    return file_count


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Cut a Windows release of caisse212 (build + zip + manifest)."
    )
    parser.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        help=f"CDN base URL (default: {DEFAULT_BASE_URL})",
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Reuse the existing Release/ folder instead of running flutter build",
    )
    args = parser.parse_args()

    if not PUBSPEC.exists():
        die(f"{PUBSPEC} not found — is this the caisse212 repo?")

    text, cur_semver, cur_build = read_pubspec()
    print(f"Current version: {cur_semver}+{cur_build}\n")

    # --- prompts ---------------------------------------------------------
    suggested_semver = bump_patch(cur_semver)
    new_semver = prompt("New semver", default=suggested_semver)
    if not re.fullmatch(r"\d+\.\d+\.\d+", new_semver):
        die("semver must be MAJOR.MINOR.PATCH")

    suggested_build = cur_build + 1
    raw_build = prompt("New build number", default=str(suggested_build))
    try:
        new_build = int(raw_build)
    except ValueError:
        die("build number must be an integer")
    if new_build <= cur_build:
        die(f"build number must be strictly greater than current ({cur_build})")

    mandatory = yes("Mandatory update?")
    changes = collect_changes()

    base_url = args.base_url.rstrip("/")
    zip_name = f"caisse212-windows-x64-{new_semver}.zip"
    zip_url = f"{base_url}/builds/{zip_name}"
    manifest_url = f"{base_url}/windows-archive.json"

    print("\n--- Summary --------------------------------------------------")
    print(f"  Version:       {new_semver}+{new_build}")
    print(f"  Mandatory:     {mandatory}")
    print(f"  Changes:       {len(changes)}")
    print(f"  Zip name:      {zip_name}")
    print(f"  Zip URL:       {zip_url}")
    print(f"  Manifest URL:  {manifest_url}")
    print("--------------------------------------------------------------")
    if not yes("Proceed?", default_no=False):
        print("Aborted before any file was changed.")
        return

    # --- 1. pubspec ------------------------------------------------------
    print(f"\n[1/4] Writing version to {PUBSPEC.name}")
    write_pubspec(text, new_semver, new_build)
    print(f"      -> version: {new_semver}+{new_build}")

    # --- 2. build --------------------------------------------------------
    if args.skip_build:
        print("\n[2/4] Skipping build (--skip-build)")
        if not RELEASE_DIR.exists():
            die(f"Release dir missing: {RELEASE_DIR}\nDrop --skip-build to build.")
    else:
        print("\n[2/4] Running `flutter build windows --release`")
        # `shell=True` is required on Windows so cmd.exe resolves PATHEXT
        # and finds `flutter.bat` — Python's bare `subprocess.run` only
        # auto-resolves `.exe`. On Linux/macOS this still works because the
        # shell just `exec`s the command. We control the args so there's
        # no shell-injection risk.
        try:
            subprocess.run(
                "flutter build windows --release",
                cwd=REPO_ROOT,
                check=True,
                shell=True,
            )
        except FileNotFoundError:
            die("flutter not on PATH (and shell didn't find it either)")
        except subprocess.CalledProcessError as e:
            die(f"flutter build failed (exit {e.returncode})")
        if not RELEASE_DIR.exists():
            die(f"Build completed but Release dir missing: {RELEASE_DIR}")

    # --- 3. zip ----------------------------------------------------------
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = OUT_DIR / zip_name
    print(f"\n[3/4] Zipping {RELEASE_DIR.name}/ contents into {zip_path.name}")
    file_count = zip_release_contents(zip_path)
    kb = zip_path.stat().st_size // 1024
    print(f"      -> {file_count} files, {kb:,} KB")

    # --- 4. manifest -----------------------------------------------------
    manifest_path = OUT_DIR / "windows-archive.json"
    manifest = {
        "appName": APP_NAME,
        "description": DESCRIPTION,
        "items": [
            {
                "version": new_semver,
                "shortVersion": new_build,
                "platform": "windows",
                "url": zip_url,
                "date": datetime.date.today().isoformat(),
                "mandatory": mandatory,
                "changes": changes,
            }
        ],
    }
    print(f"\n[4/4] Writing manifest to {manifest_path.name}")
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )

    # --- next steps ------------------------------------------------------
    print("\n[OK] Artifacts ready in:", OUT_DIR)
    print(f"     {zip_path.name}")
    print(f"     {manifest_path.name}")

    print("\nNext steps:")
    print(f"  1. Upload the zip to:")
    print(f"       {zip_url}")
    print(f"  2. Upload (OVERWRITE) the manifest to:")
    print(f"       {manifest_url}")
    print(f"  3. Purge CDN cache for the manifest URL if your CDN caches.")
    print(f"  4. Smoke-test: open the POS on a staging Windows machine")
    print(f"     running {cur_semver}+{cur_build}, wait for the overlay,")
    print(f"     click through, confirm the new version after restart.")
    print(f"  5. Optionally commit + tag:")
    print(f"       git add pubspec.yaml")
    print(f"       git commit -m \"release: windows {new_semver}+{new_build}\"")
    print(f"       git tag v{new_semver}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nInterrupted.", file=sys.stderr)
        sys.exit(130)

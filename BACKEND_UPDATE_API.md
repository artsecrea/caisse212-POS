# Backend — Update System (R2 Streaming)

## Architecture

```
Dev machine                    Backend API                  Cloudflare R2
──────────                    ───────────                  ─────────────
flutter build linux
dart run desktop_updater:release linux
dart run desktop_updater:archive linux
  → dist/5/caisse212-1.2.0+5-linux/
      hashes.json
      caisse212
      lib/libflutter_linux.so
      ...

For each file:
  POST /api/admin/releases/upload
  ?version=1.2.0&platform=linux
  ?relative_path=lib/libflutter_linux.so  ───stream──►  updates/1.2.0/linux/lib/libflutter_linux.so
  (no disk write on server)

POST /api/admin/releases/finalize ──────────────────────────► DB record saved

POS app startup:
  GET /pos/app-archive.json  ◄── backend queries DB, returns JSON (not a static file)

POS desktop_updater:
  GET https://pub-xxx.r2.dev/updates/1.2.0/linux/hashes.json   ← direct to R2
  GET https://pub-xxx.r2.dev/updates/1.2.0/linux/caisse212      ← direct to R2
```

---

## 1. Environment Variables

```env
R2_ACCOUNT_ID=abc123
R2_ACCESS_KEY_ID=your_r2_access_key_id
R2_SECRET_ACCESS_KEY=your_r2_secret_key
R2_BUCKET_NAME=caisse212-updates
R2_PUBLIC_BASE_URL=https://pub-xxx.r2.dev   # no trailing slash
```

R2 S3 endpoint: `https://{R2_ACCOUNT_ID}.r2.cloudflarestorage.com`

---

## 2. R2 Client

R2 is S3-compatible — use any AWS SDK.

**Python (boto3):**
```python
import boto3, os

r2 = boto3.client(
    "s3",
    endpoint_url=f"https://{os.environ['R2_ACCOUNT_ID']}.r2.cloudflarestorage.com",
    aws_access_key_id=os.environ["R2_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
    region_name="auto",
)
```

**Node.js:**
```js
import { S3Client } from "@aws-sdk/client-s3";

const r2 = new S3Client({
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: {
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
  region: "auto",
});
```

---

## 3. Path Generation (backend owns all keys)

Never accept R2 paths from clients. Backend constructs them.

```python
import re, os

VALID_VERSION = re.compile(r"^\d+\.\d+\.\d+$")
VALID_PLATFORM = {"linux", "windows", "macos", "android", "ios"}

def r2_key(version: str, platform: str, relative_path: str) -> str:
    """
    Constructs the R2 object key for a release file.
    Sanitizes relative_path — no traversal, no leading slash.

    Examples:
      r2_key("1.2.0", "linux", "hashes.json")
        → "updates/1.2.0/linux/hashes.json"
      r2_key("1.2.0", "linux", "lib/libflutter_linux.so")
        → "updates/1.2.0/linux/lib/libflutter_linux.so"
      r2_key("1.2.0", "android", "app-release.apk")
        → "updates/1.2.0/android/app-release.apk"
    """
    if not VALID_VERSION.match(version):
        raise ValueError(f"Invalid version: {version}")
    if platform not in VALID_PLATFORM:
        raise ValueError(f"Invalid platform: {platform}")

    # Sanitize: strip leading slash, collapse .., no null bytes
    clean = relative_path.lstrip("/").replace("..", "").replace("\0", "")
    if not clean:
        raise ValueError("Empty relative_path")

    return f"updates/{version}/{platform}/{clean}"


def r2_public_url(version: str, platform: str) -> str:
    """
    Returns the directory URL stored in app-archive.json items[].url.
    desktop_updater appends /hashes.json and file paths to this.
    Android: full APK URL (single file, not a directory).
    """
    base = os.environ["R2_PUBLIC_BASE_URL"]
    if platform == "android":
        return f"{base}/updates/{version}/android/app-release.apk"
    return f"{base}/updates/{version}/{platform}"
```

---

## 4. Upload Endpoint — Stream File to R2

**No disk I/O on the server.** Incoming file stream piped directly to R2.

```
POST /api/admin/releases/upload
Authorization: Bearer <admin-token>
Content-Type: multipart/form-data

Fields:
  file          — the file binary
  version       — "1.2.0"
  platform      — "linux" | "windows" | "macos" | "android"
  relative_path — "hashes.json" | "lib/libapp.so" | "app-release.apk"
```

### Python / Django
```python
def upload_release_file(request):
    version       = request.POST["version"]
    platform      = request.POST["platform"]
    relative_path = request.POST["relative_path"]
    file_obj      = request.FILES["file"]

    key = r2_key(version, platform, relative_path)

    # upload_fileobj streams in chunks — zero disk write
    r2.upload_fileobj(
        file_obj,
        os.environ["R2_BUCKET_NAME"],
        key,
        ExtraArgs={
            "ContentType": file_obj.content_type or "application/octet-stream",
        },
    )

    return JsonResponse({"key": key})
```

### Node.js / Express
```js
import { PutObjectCommand } from "@aws-sdk/client-s3";
import busboy from "busboy";

app.post("/api/admin/releases/upload", requireAdmin, (req, res) => {
  const { version, platform, relative_path } = req.query;
  const bb = busboy({ headers: req.headers });

  bb.on("file", (_field, stream, info) => {
    const key = r2Key(version, platform, relative_path);

    r2.send(new PutObjectCommand({
      Bucket: process.env.R2_BUCKET_NAME,
      Key: key,
      Body: stream,                        // stream → R2, no buffering
      ContentType: info.mimeType || "application/octet-stream",
    })).then(() => res.json({ key }))
       .catch(err => res.status(500).json({ error: err.message }));
  });

  req.pipe(bb);
});
```

### Response
```json
{ "key": "updates/1.2.0/linux/lib/libflutter_linux.so" }
```

---

## 5. Finalize Release Endpoint

Called once after all files are uploaded for a platform. Saves the DB record.

```
POST /api/admin/releases/finalize
Authorization: Bearer <admin-token>
Content-Type: application/json

{
  "version":       "1.2.0",
  "short_version": 5,
  "platform":      "linux",
  "mandatory":     false,
  "release_date":  "2026-05-22",
  "changes": [
    { "message": "Fixed order sync issue" },
    { "message": "Improved printer reliability" }
  ]
}
```

Backend sets `public_url = r2_public_url(version, platform)` and saves to DB.

---

## 6. Database Model

```sql
CREATE TABLE app_releases (
  id            SERIAL PRIMARY KEY,
  version       VARCHAR(20)  NOT NULL,
  short_version INT          NOT NULL,
  platform      VARCHAR(20)  NOT NULL,
  public_url    TEXT         NOT NULL,    -- r2_public_url() result
  mandatory     BOOLEAN      NOT NULL DEFAULT false,
  enabled       BOOLEAN      NOT NULL DEFAULT true,
  release_date  DATE         NOT NULL,
  changes       JSONB        NOT NULL DEFAULT '[]',
  created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (version, platform),
  UNIQUE (short_version, platform)
);
```

---

## 7. app-archive.json Endpoint

```
GET /pos/app-archive.json
```

**No auth required.** App fetches before login.
Served at `{server_root}/pos/app-archive.json` — NOT under `/api/`.
(Flutter derives this by stripping `/api` from `api_base_url`.)

Backend queries DB dynamically — no static file on disk.

### Python
```python
def app_archive_json(request):
    # Latest enabled release per platform
    from django.db.models import Max

    latest = (
        AppRelease.objects
        .filter(enabled=True)
        .values("platform")
        .annotate(max_sv=Max("short_version"))
    )
    platform_to_sv = {r["platform"]: r["max_sv"] for r in latest}

    releases = AppRelease.objects.filter(
        enabled=True,
        platform__in=platform_to_sv.keys(),
        short_version__in=platform_to_sv.values(),
    )

    items = [
        {
            "version":      r.version,
            "shortVersion": r.short_version,
            "date":         r.release_date.isoformat(),
            "platform":     r.platform,
            "url":          r.public_url,
            "mandatory":    r.mandatory,
            "changes":      r.changes,   # [{message: ...}] from DB
        }
        for r in releases
    ]

    return JsonResponse({
        "appName":     "CAISSE212",
        "description": "POS Terminal Updates",
        "items":       items,
    })
```

### Node.js
```js
app.get("/pos/app-archive.json", async (req, res) => {
  // subquery: latest short_version per platform
  const rows = await db.query(`
    SELECT * FROM app_releases
    WHERE enabled = true
      AND (platform, short_version) IN (
        SELECT platform, MAX(short_version)
        FROM app_releases WHERE enabled = true
        GROUP BY platform
      )
    ORDER BY platform
  `);

  res.json({
    appName:     "CAISSE212",
    description: "POS Terminal Updates",
    items: rows.map(r => ({
      version:      r.version,
      shortVersion: r.short_version,
      date:         r.release_date,
      platform:     r.platform,
      url:          r.public_url,
      mandatory:    r.mandatory,
      changes:      r.changes,
    })),
  });
});
```

---

## 8. Directory Separation

| Layer | Location |
|-------|----------|
| App code | `/srv/caisse212/app/` |
| DB / ORM | your database server |
| Media (receipts, images) | separate bucket or `/srv/caisse212/media/` |
| **Update files** | **Cloudflare R2 only — zero local disk** |

Backend never writes update files to disk. No `MEDIA_ROOT` or static dir for releases.
R2 is the only storage layer for update binaries.

---

## 9. Admin Upload Script (Dev Side)

Run after each build on dev machine. Uploads entire dist folder to backend.

```bash
#!/bin/bash
# scripts/upload_release.sh
# Usage: ./upload_release.sh linux 1.2.0 5

set -e

PLATFORM=$1
VERSION=$2
SHORT_VERSION=$3
API_URL=${API_URL:-https://app.caisse212.com}
ADMIN_TOKEN=${ADMIN_TOKEN:?ADMIN_TOKEN required}

# Find the dist folder
DIST_DIR="dist/${SHORT_VERSION}"
APP_DIR=$(ls -d "${DIST_DIR}"/*-"${PLATFORM}" 2>/dev/null | head -1)

if [ -z "$APP_DIR" ]; then
  echo "ERROR: dist folder not found for ${PLATFORM}. Run dart run desktop_updater:release ${PLATFORM} first."
  exit 1
fi

echo "Uploading from: $APP_DIR"

# Upload every file in the dist dir
find "$APP_DIR" -type f | while read -r FILE; do
  RELATIVE_PATH="${FILE#${APP_DIR}/}"
  echo "  → $RELATIVE_PATH"

  curl -sf \
    -X POST "${API_URL}/api/admin/releases/upload" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    -F "file=@${FILE}" \
    -F "version=${VERSION}" \
    -F "platform=${PLATFORM}" \
    -F "relative_path=${RELATIVE_PATH}" \
    > /dev/null
done

# Finalize
curl -sf \
  -X POST "${API_URL}/api/admin/releases/finalize" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"version\": \"${VERSION}\",
    \"short_version\": ${SHORT_VERSION},
    \"platform\": \"${PLATFORM}\",
    \"mandatory\": false,
    \"release_date\": \"$(date +%Y-%m-%d)\",
    \"changes\": [{\"message\": \"Release ${VERSION}\"}]
  }"

echo "Done: ${VERSION}+${SHORT_VERSION} for ${PLATFORM}"
```

---

## 10. Full Release Checklist

```bash
# 1. Bump version in pubspec.yaml → e.g. 1.2.0+5

# 2. Build + package
flutter build linux --release
dart run desktop_updater:release linux
dart run desktop_updater:archive linux

flutter build windows --release          # on Windows / CI
dart run desktop_updater:release windows
dart run desktop_updater:archive windows

flutter build apk --release
# Copy APK to dist/5/ manually:
cp build/app/outputs/flutter-apk/app-release.apk dist/5/app-release.apk

# 3. Upload (streams directly to R2 via backend)
ADMIN_TOKEN=xxx ./scripts/upload_release.sh linux   1.2.0 5
ADMIN_TOKEN=xxx ./scripts/upload_release.sh windows 1.2.0 5

# Android separate (single APK file, no hashes.json needed)
curl -X POST .../api/admin/releases/upload \
  -F "file=@dist/5/app-release.apk" \
  -F "version=1.2.0" -F "platform=android" -F "relative_path=app-release.apk"
curl -X POST .../api/admin/releases/finalize \
  -d '{"version":"1.2.0","short_version":5,"platform":"android",...}'

# 4. Verify
curl https://app.caisse212.com/pos/app-archive.json | jq .
```

---

## 11. Security

- `/api/admin/releases/*` — admin JWT only
- `/pos/app-archive.json` — public, no auth (app reads before login)
- R2 bucket — public READ, no public WRITE
- Never expose `R2_SECRET_ACCESS_KEY` outside backend
- Validate `version` regex `^\d+\.\d+\.\d+$` and `platform` enum before building any key
- `short_version` must be strictly greater than existing for same platform (reject duplicate)

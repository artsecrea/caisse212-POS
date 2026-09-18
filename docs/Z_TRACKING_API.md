# Z (Shift) Tracking — Backend API Contract

Status: **client implemented, backend NOT yet implemented.** This document is the
spec the POS backend must implement so the Flutter POS can sync the new `Z`
entity. The client already builds/sends everything below.

## Concept

A **Z** is a shift that owns one or more cash sessions. Exactly **one Z may be
`open` per POS terminal** at a time. It is the grouping key for a shift's
reporting (a Z can span multiple cashier sessions). The POS is the source of
truth (push-only, upsert-by-`code`); the backend stores + enforces uniqueness.

- A Z is opened automatically with the first session of a shift, or manually by
  an admin/manager from the POS login screen.
- A Z is closed by anyone with `pos:z:close` (in-app) or by an admin/manager.
  Closing a Z auto-closes its still-open sessions.
- **z_day**: every order/ticket/session created while a Z is open is stamped
  with the Z's opening day.

## Auth / scoping

All endpoints are authenticated with the existing POS bearer token. The terminal
is identified by the **auto-injected `X-Pos-Id` header** (POS terminal id) plus
`X-Tenant-ID` / `X-POS-Name`. The server MUST scope Z rows to the tenant and use
`X-Pos-Id` (or the body `posId`) to enforce per-terminal uniqueness — do **not**
trust the body alone.

## Entity: `z`

| field       | type      | notes |
|-------------|-----------|-------|
| `code`      | string    | **unique** identifier, client-generated (`Z-YYYYMMDD-HHMMSS-XXX`). Upsert key. |
| `posId`     | int, null | owning POS terminal (also in `X-Pos-Id`). |
| `createdBy` | int       | user id who opened the Z. |
| `startedAt` | ISO-8601  | open time. |
| `endedAt`   | ISO-8601, null | close time. |
| `endedBy`   | int, null | user id who closed it. |
| `status`    | string    | `'open'` \| `'closed'`. |
| `totalPaid` | number, null | aggregate takings across the Z's sessions (set at close). |
| `details`   | object, null | JSON snapshot at close: `{sessionCount, sessionCodes[], totalPaid, moneyAtStart}`. |

### `cash_sessions` change
Each session payload now includes **`zCode`** (string, nullable) — the `code` of
the Z it belongs to. The server should resolve it to the Z FK. Because Z is
synced **before** sessions, the referenced Z always exists when the session
arrives. Existing session fields are unchanged.

## Uniqueness rule (server MUST enforce)

**At most one `status='open'` Z per (tenant, posId).** On create/upsert of an
`open` Z:
- If no open Z exists for the terminal → create it.
- If an open Z with the **same `code`** exists → update it (idempotent).
- If a **different** open Z already exists for the terminal → reject with
  **409 Conflict** and return the existing open Z in the body so the client can
  reconcile. (The client also calls `GET /pos/z/open` before opening to adopt an
  existing server Z, but the server is the final guard.)

## Endpoints

### POST `/pos/z/bulk`
Bulk upsert. Body: `{ "zs": [ <z>, ... ] }`. Upsert each by `code`. Return 2xx on
success. Enforce the uniqueness rule per item.

```json
{ "zs": [ {
  "id": 12, "code": "Z-20260712-091500-042", "posId": 7, "createdBy": 3,
  "startedAt": "2026-07-12T09:15:00.000", "endedAt": null, "endedBy": null,
  "status": "open", "totalPaid": null, "details": null
} ] }
```

### PUT `/pos/z/{code}`
Upsert a single Z (create-or-update by `code`). Body = one `<z>` object (no `id`
required). Same uniqueness enforcement. Used by the per-item fallback and for the
close upsert.

### GET `/pos/z/open`
Return the **open** Z for the requesting terminal (`X-Pos-Id`), or **404** if
none. Response body = one `<z>` object. Used by the POS to adopt an existing open
Z instead of creating a duplicate.

### DELETE `/pos/z/{code}`
Delete a Z by code (optional; used only if Z deletion is exposed on the POS).

## Sync ordering guarantee

The POS sync job pushes in this order: **pending-ops → Z → sessions → orders →
tickets → customers → pull deltas.** So a Z is always upserted before any session
that references it via `zCode`.

## Permissions (add server-side)

Mirror the client tokens (comma-separated on the user, `:*` wildcards supported):

- `pos:z:open` — open a Z (login-screen manager gate uses this).
- `pos:z:close` — close a Z (granted broadly / in cashier defaults so "anyone can
  close" holds).
- `pos:z:view` — view current Z.
- `pos:z:print` — print X / Z reports.

Admin-type users bypass all checks (existing behavior).

## Reports (client-side, informational)

- **X report** = a daily-summary over the open Z's sessions, printed without
  closing (no cash-variance block).
- **Z report** = the same summary printed at close.
Both are generated on the POS from local data; the backend only needs the sync
endpoints above.

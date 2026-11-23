# Subscription & Token Refresh — Backend Contract

POS side is implemented (2026-10-06). This is what the backend needs to add.

What the till does with it:

- Shows a warning on the **login screen** starting **14 days** before the subscription end date, and a red "expired" message after it.
- **Warns only, never blocks** (again the rule since 2026-11-16, see section 7). Locking is reserved for account deactivation (section 8).
- Inside the 14-day window, the till re-checks **once per calendar day**. As soon as a renewal shows up (a new `endsAt` more than 14 days out), the warning disappears on its own.
- Outside the window, the subscription is refreshed through channels the till already uses: login, token refresh (including the top-bar **Update** button) and every catalogue sync. No extra calls are made.

---

## 1. The `subscription` object

The same shape is used everywhere below.

```json
{
  "status": "ACTIVE",
  "endsAt": "2026-10-20T23:59:59Z",
  "planName": "Pro",
  "contact": "+212 6 00 00 00 00"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `endsAt` | string, ISO-8601 | yes* | End of the paid period. An instant with an offset is preferred. A bare date (`"2026-10-20"`) is read as the end of that day, local time. Aliases accepted: `endDate`, `expiresAt`. |
| `status` | string | no | `ACTIVE`, `TRIAL`, `PAST_DUE`, `EXPIRED`, `CANCELED`… Case-insensitive. **`EXPIRED` always shows the expired message**, whatever `endsAt` says. |
| `planName` | string | no | Stored but not shown yet. |
| `contact` | string | no | Phone or email for renewals. Shown under the warning when present. |

\* If `endsAt` is missing or null, the till never warns. Use that for unlimited or unmanaged tenants.

**Null semantics (please respect them):**
- **Key absent** → "this server knows nothing about subscriptions". The till keeps its stored copy.
- **`"subscription": null`** → "nothing to track". The till clears its stored copy and the warning.

---

## 2. Changes to existing endpoints

### 2a. `POST /api/pos/login` and `POST /api/pos/refresh`

Add `subscription` inside the existing `posTerminal` object, next to `categoryIds`:

```json
{
  "accessToken": "...",
  "refreshToken": "...",
  "expiresIn": 900000,
  "posTerminal": {
    "id": "2",
    "businessId": "1",
    "categoryIds": [41, 5],
    "subscription": { "status": "ACTIVE", "endsAt": "2026-10-20T23:59:59Z" }
  }
}
```

(A top-level `subscription` is also accepted, but `posTerminal.subscription` takes priority.)

When `posTerminal` is `null` (refresh without `X-POS-Name`), the till keeps its stored copy. That is fine.

---

## 3. New endpoint

### `GET /api/pos/subscription`

The external path is `/api/api/pos/subscription`. The double `/api` comes from the context-path plus the controller mapping, same as every other `/pos/*` route.

Same auth and headers as the other POS calls: `Authorization: Bearer`, `X-POS-Name`, `X-Tenant-ID`, `X-Business-Id`.

| Response | Meaning to the till |
|---|---|
| `200` + subscription object (bare, or wrapped as `{"subscription": {...}}`) | Store it. |
| `200` + `{"subscription": null}`, or `204` | Nothing to track. The warning is cleared. |
| `404` / `5xx` / timeout | Ignored. The stored copy is kept and the till retries later. |

Must be cheap: no catalogue, no joins beyond the business → subscription lookup.

When it is called:
- On every full sync and menu sync (Update button, `sync_all`, `sync_menu`…).
- Once a day while within 14 days of `endsAt` (or past it): when the login screen opens, every 30 minutes while it stays open, and on the background sync tick.

---

## 4. New SSE `pos-command` types

Both are sent as `event: pos-command` on `/api/pos/queue/subscribe`, like the existing commands (see `sse_pos_commands.md`).

### `refresh_token`

Aliases: `refresh_tokens`, `rotate_token`, `renew_token`.

```json
{ "type": "refresh_token" }
```

The till calls `POST /pos/refresh` right away, single-flight with any refresh already running. It stores the new access and refresh tokens, so the refresh token's expiry slides forward. It also re-reads the category scope and the subscription from that response.

Use it to:
- extend a till that is idle for a long time before its refresh token dies;
- push a scope or subscription change immediately.

Notes:
- A failed refresh does **not** log the till out (only an explicit 401 on a normal request does). The activity log row says `refresh_token — ok` or `— failed`.
- **Do not put tokens in the SSE payload.** The till always fetches them itself over the authenticated refresh call.
- SSE only runs while a cashier is signed in, so a till sitting on the login screen cannot receive this command.

### `subscription_updated`

Aliases: `refresh_subscription`, `sync_subscription`.

Send it right after a payment or renewal so the warning clears without waiting for the daily check:

```json
{ "type": "subscription_updated",
  "subscription": { "status": "ACTIVE", "endsAt": "2027-10-20T23:59:59Z" } }
```

- With `subscription` present → stored as-is (`null` clears it).
- Without the key → the till calls `GET /pos/subscription`.

Send it to **every terminal of the business**. SSE does not replay messages, so tills that are offline will catch up through the daily check.

---

## 5. Backend checklist

1. Add `subscription` to `posTerminal` in the login and refresh responses.
2. `GET /api/pos/subscription` (cheap; `200`/`204`).
3. SSE `pos-command` `refresh_token`.
4. SSE `pos-command` `subscription_updated`, fired on renewal, plan change or cancellation.
5. Optional: a BMS button "Refresh tokens on all tills" that sends `refresh_token` to every terminal.

---

## 6. As built by BMS (2026-10-06, repo `bms`: not committed, not deployed)

- `posTerminal.subscription` is **always present** on login and refresh: an object, or `null` when the tenant has no subscription row. There is no top-level copy.
- `GET /api/pos/subscription` always returns **200** with `{"subscription": {...}}` or `{"subscription": null}`, never 204. It is one indexed query.
- Subscriptions are **per tenant**: every terminal of every business in the tenant gets the same object.
- `status` is one of `ACTIVE`, `TRIAL`, `EXPIRED`, `CANCELED`. An ACTIVE row past its end date is sent as EXPIRED. `PAST_DUE` is never sent.
- For `CANCELED`, `endsAt` is the **moment of cancellation**, so the till shows the red message right away.
- `endsAt` is an ISO instant in UTC (`...Z`). `contact` comes from the setting `app.pos.subscription.contact` (env var `POS_SUBSCRIPTION_CONTACT`) and is null until someone sets it.
- `refresh_token` needs no new code: `POST /api/pos-terminal/commands` with body `{"command":{"type":"refresh_token"}}` and no targets reaches every connected till of the business. It needs the `pos:commands` permission or ADMIN.
- `subscription_updated` (always carrying `subscription`, possibly null) is pushed automatically after the database change is saved. It fires on assign, upgrade, plan change, cancel, the nightly expiry job, payment verification (renewal) and extend-on-credit.
- Not built yet: the BMS button "Refresh tokens on all tills", and any lockout of expired tenants. Login and refresh still succeed for an expired tenant.

The POS handles every one of these shapes as-is (`test/subscription_test.dart`, "BMS shape" case).

---

## 7. Expired subscription: warning only (user ruling 2026-11-16)

This **replaces the 2026-10-08 lock**. An expired subscription (end date passed, or `status: EXPIRED`) shows the red card on the login screen with **Check again**, but **sign-in is never locked** and the till keeps working. The 14-day warning is unchanged. The CANCELED rulings still hold: `endsAt` is the paid-until date, and a payment reactivates the subscription. They now only affect what the warning says.

The backend confirmed (2026-11-16) that no POS route is gated on the subscription.

---

## 8. Account deactivation: locks the till (user ruling 2026-11-16)

Tenant, business and terminal can each be switched off manually in the back office. When any of them is off, the POS signs the cashier out to the login screen and **locks sign-in** until all three are active again.

### Backend (built 2026-11-16 by the bms session; uncommitted, not deployed)

- **Toggles:** `PATCH /api/super-admin/tenants/{id}/active` (SUPER_ADMIN), `PATCH /api/businesses/{id}/active`, `PATCH /api/pos-terminal/{id}/active` (ADMIN/SUPER_ADMIN). Body: `{"active": bool, "reason": "..."?}`. The `reason` becomes the `message` shown on the till. The existing terminal PUT `isActive` also kicks. New columns `tenants.is_active` and `businesses.is_active` (V214, default true).
- **Per-request filter** on `/api/pos/**` and `/api/pos-terminal/**` when `X-POS-Name` is present. State is cached for 60s and evicted on every toggle. The filter runs before auth, so a till with a dead token still gets 423, not 401. Exempt paths: login, refresh, logout, account-status, update_check. Login and refresh check the account themselves.
- **Refusal:**
  `HTTP 423` `{"code":"ACCOUNT_DISABLED","scope":"TENANT|BUSINESS|TERMINAL","message":"..."}`
  header `X-Account-Status: DISABLED_<SCOPE>`.
  Precedence is TENANT > BUSINESS > TERMINAL, and `message` is never null. The sync endpoints' old `403 "POS terminal is not active"` is now this 423. The POS still recognises the old 403 for servers deployed before the change.
- **`GET /api/pos/account-status`** is public and needs no token. The till is identified by `X-Tenant-Id` + `X-POS-Name`. It returns `200 {"active": bool, "scope"?, "message"?, "subscription": {...}|null}` and never 404. An unknown or deleted terminal returns `active:false` with scope TERMINAL. It is rate-limited.
- **`posTerminal.accountStatus: {"active": true}`** is included on login and refresh. `GET /pos/subscription` also returns `accountStatus`.
- **SSE** `pos-command` `{"type":"account_disabled","scope","message"}` is sent after commit to every affected till, and then the stream is closed. Reactivation sends `account_enabled`.
- Still open with the BMS user: whether a disabled tenant or business should also block web and mobile login. Today the block applies to the POS only.

### POS (built 2026-11-16, uncommitted)

- `AccountStatusStore` (prefs key `pos_account_block_json`) holds the block, so it survives restarts and network loss. It is set by: any 423 / `ACCOUNT_DISABLED` / `X-Account-Status: DISABLED_*` answer (Dio interceptor, and the SSE connect), the SSE `account_disabled` push, or `accountStatus.active:false`. It is cleared only by the server: `accountStatus.active:true`, a successful login, or a tenant switch (`clearAuthData`). A refresh that succeeds without `accountStatus` proves nothing, because old servers never checked on refresh.
- **Kick:** `AccountBlockWatcher` (mounted at the app root) clears the user, session, admin elevation and cart state, then navigates to `/login`. Saved orders, tickets and the open cash session stay in the local database, and the shift resumes after reactivation. `/pos/logout` is not called: it signs the terminal itself out.
- **Login screen:** `AccountBlockNotice` is a red lock card with the scope title, the server's message, the "since" time and **Check again**. It calls `GET /pos/account-status` when the screen opens and every 60s while the lock is up. The Sign-in button is disabled and `_handleLogin` is guarded. The post-update auto-resume is skipped while blocked. Being offline keeps the lock.
- **While blocked**, the Dio gate refuses every cloud call locally except the exempt paths. The sync job skips, and pending operations are not attempted, so nothing burns its retry budget. Queued work waits and flushes after reactivation. SSE does not connect.
- **LAN server:** `waiters/*` and `POST /orders` answer 423 `ACCOUNT_DISABLED`, so the waiter app cannot keep selling. The KDS keeps working so the kitchen can finish what was already ordered.
- An older server without `/pos/account-status` (404) falls back to a token refresh: a 423 keeps the lock, anything else changes nothing.
- Tests: `test/account_status_test.dart`.

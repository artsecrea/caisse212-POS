# Waiter App — PIN Login Spec

## Purpose

The waiter app authenticates against the local POS HTTP server using a
**PIN** — a unique numeric (or alphanumeric) identifier assigned to each
waiter by the backend. The PIN replaces the older username/password flow.

This document describes:
1. How the waiter app discovers the POS on the LAN.
2. The login endpoint, request body, and response shape.
3. Error cases and recommended UX behavior.
4. How the PIN gets to the waiter (lifecycle).
5. Subsequent endpoints the waiter app calls after login.

---

## 1. Discovery (mDNS / Bonsoir)

The POS broadcasts itself on the local network using Bonsoir under the
service type:

```
_caisse212._tcp
```

The TXT record carries three keys you need to construct the base URL:

| Key | Example | Notes |
|---|---|---|
| `name` | `"Caisse 1"` | Cashier-friendly device label. Show in a picker if multiple POSes are on the LAN. |
| `ip` | `"192.168.1.42"` | IPv4 address the POS bound to. Use as the host. |
| `port` | `"8080"` | HTTP port the POS Shelf server is listening on. Default is `8080`; the cashier can change it in settings. |

Construct the base URL as:

```
http://{ip}:{port}
```

**On Android / iOS:** use [`bonsoir`](https://pub.dev/packages/bonsoir) with
`type: '_caisse212._tcp'` and a 5-second discovery window. Most LANs return
results within 1–2 seconds.

**Manual fallback:** if discovery fails (some hotel/captive networks block
mDNS), let the waiter type the IP + port manually. Cache the last working
base URL so re-login on the same shift is one tap.

---

## 2. Login endpoint

```
POST {baseUrl}/waiters/login
Content-Type: application/json

{ "pin": "1234" }
```

The PIN is trimmed server-side; leading/trailing whitespace is ignored.
Case matters (if the backend ever issues alphanumeric pins).

### Headers

No `Authorization` header is required on this endpoint — the PIN itself is
the credential. CORS is open (the POS Shelf server adds `Access-Control-
Allow-Origin: *` so a web-based waiter client works too).

### 2xx response

```json
{
  "waiter": {
    "id": 42,
    "firstName": "Yassine",
    "lastName": "B.",
    "imageUrl": "https://cdn.example.com/waiters/42.jpg",
    "areaIds": [3, 5, 7]
  }
}
```

**`id`** is the waiter's stable backend ID — store it client-side and pass
it as the `waiterId` query parameter or body field to every subsequent
endpoint (`/waiters/dashboard?waiterId=42`, etc.).

**`areaIds`** is the list of dining-area IDs the waiter is assigned to.
Use it to filter the tables shown in the table picker so a waiter only
sees the rooms they're responsible for.

`lastName`, `imageUrl` may be `null` — render safely.

### Error responses

| Status | Body | Meaning | Waiter app should… |
|---|---|---|---|
| 400 | `{"error":"pin_required"}` | Body missing `pin` or pin empty after trim | Surface inline ("Enter your PIN"); don't lock out |
| 403 | `{"error":"invalid_pin"}` | PIN not found OR matches an inactive waiter | Show "Wrong PIN — try again". **Deliberately ambiguous** — see §3 |
| 500 | `{"error":"login_failed","details":"..."}` | Server-side exception | Show "Server error — please try again" and log `details` for support |

**Network failure** (timeout, `ECONNREFUSED`, DNS error): show
"Can't reach POS — check Wi-Fi" and offer the manual-IP fallback. Don't
auto-retry hard — let the waiter retap.

---

## 3. Why the error is ambiguous

`403 invalid_pin` is returned for **both** "PIN doesn't exist" and "PIN
matches but the waiter is `is_active = false`". This is intentional: a
distinguishable response would let someone with LAN access probe valid
PINs by watching the error change when they get close. The waiter app
should not try to disambiguate; the cashier on the POS handles
de-activation as an admin task.

---

## 4. PIN lifecycle

```
Backend admin assigns PIN to waiter record
        │
        ▼
Backend exposes pin in GET /pos/waiters response
        │
        ▼
POS syncs (DataSyncService → _persistWaiters → waiters.pin column)
        │
        ▼
Waiter receives the PIN from their manager / cashier
        │
        ▼
Waiter types PIN into the waiter app → POST /waiters/login
```

**PIN format.** The POS does not enforce a format. Standard practice is
4–6 digits (numeric) since a numeric keypad is faster on the waiter
device. Alphanumeric pins are supported if the backend chooses to issue
them. **Uniqueness is enforced** by a partial unique index on the POS DB
(`idx_waiters_pin WHERE pin IS NOT NULL`) — two waiters can't share a
non-null PIN. The backend should enforce the same invariant before
issuing.

**Rotating a PIN.** The backend changes the value on the waiter record.
On next POS sync the new PIN propagates; the old PIN stops working.
There is no PIN-change endpoint on the POS itself — by design.

**Inactive waiters.** Setting `is_active = false` on the backend makes
the next sync deactivate the waiter; the next login attempt returns
`403 invalid_pin`. PINs are NOT cleared on deactivation, so they can be
reactivated without re-issue.

---

## 5. Subsequent endpoints

After login the waiter app passes `waiterId={id}` to every protected
endpoint. None of these require additional auth headers; they all run on
the same Shelf server scoped to the cashier's tenant.

| Method | Endpoint | Use |
|---|---|---|
| `GET` | `/waiters/dashboard?waiterId={id}` | Daily totals: orders, expected cash, active orders |
| `GET` | `/waiters/products` | Menu catalog |
| `GET` | `/waiters/categories` | Category tree |
| `GET` | `/waiters/components` | Modifier list |
| `GET` | `/waiters/component-groups` | Modifier groupings |
| `GET` | `/waiters/product-components` | Product → modifier mappings |
| `GET` | `/waiters/product-variants` | Size / option variants |
| `GET` | `/waiters/tables?waiterId={id}` | Tables — filter by `areaIds` from login response |
| `GET` | `/waiters/orders?waiterId={id}` | Open orders the waiter created |
| `POST` | `/waiters/orders` | Create a new order |
| `PUT` | `/waiters/orders/{code}/add-product` | Append a product to an existing order |

The waiter app should **cache the menu locally** (`/products`,
`/categories`, etc.) and refresh on session start + when the waiter pulls
to refresh — the POS pushes no realtime updates for catalog data.

---

## 6. Suggested client behavior

1. **On app launch**, discover POSes via mDNS. If exactly one is found,
   skip the picker. If multiple, list them by `name` from the TXT record.
2. **Persist the chosen base URL** + the last-used waiter ID.
3. **PIN entry screen** — large numeric keypad, autocomplete-style PIN
   reveal/hide toggle, no "remember PIN" option (the PIN IS the
   credential; remembering it bypasses auth).
4. **On `403 invalid_pin`**, clear the entry and shake the input. Don't
   exponentially back off — 4-digit PINs only have 10K possibilities and
   the POS is on LAN; rate-limiting client-side adds friction without
   meaningful security benefit. The cashier-facing concern (someone
   shoulder-surfs and tries a coworker's PIN) is not addressed by client
   backoff.
5. **On 5xx or network failure**, surface "Can't reach POS — check
   Wi-Fi" with a single "Retry" button. Don't drop the entered PIN.
6. **After successful login**, do an immediate `GET /waiters/tables` to
   warm the table cache. The first thing a waiter does is pick a table.

---

## 7. Test plan

1. **Happy path** — fresh app, single POS on LAN, valid PIN → discovery
   resolves, login returns 200, waiter ID stored, dashboard endpoint
   reachable.
2. **Wrong PIN** — 200 → 403 `invalid_pin` → input clears, shake
   animation, no waiter ID set.
3. **Inactive waiter** — backend deactivates a waiter; their PIN now
   returns 403 `invalid_pin` (same as wrong PIN — confirm no leakage).
4. **PIN rotation** — backend changes a waiter's PIN; POS syncs; old PIN
   returns 403, new PIN returns 200.
5. **No POS on LAN** — discovery times out; manual-IP fallback shown.
6. **POS unreachable mid-session** — Wi-Fi drops while the waiter app is
   open; subsequent endpoints fail. Recommend client buffer + retry on
   reconnect (out of scope here).
7. **Two POSes on LAN** — both broadcast; the waiter picks one; choice
   persists across app restarts.
8. **CORS** (browser-based waiter client only) — preflight `OPTIONS`
   request succeeds; subsequent `POST` carries no auth header and
   succeeds.

---

## Out of scope

- Multi-factor / biometric authentication on the waiter app — pin-only
  is the V1 model.
- Per-session JWT or refresh tokens — the waiter app re-uses the waiter
  ID returned from login; there's no separate token to refresh.
- Pin-change UI inside the waiter app — pin changes happen exclusively
  on the backend.
- Encrypted-at-rest PIN storage — the POS LAN model treats the local DB
  as trusted (it's on the cashier's own machine). If you want at-rest
  hashing later, add it backend-side and ship `pinHash` instead of `pin`;
  the POS would then hash at compare time. Not needed for V1.

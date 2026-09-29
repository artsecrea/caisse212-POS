# Waiter API — Complete Reference

The authoritative reference for **every** endpoint the waiter app can call on
the POS's embedded LAN HTTP server. Companion docs:

- `waiter_app_state_and_errors.md` — **read me first**: current state, recent
  changes, and error-handling summary
- `waiter_api_errors.md` — **every error response** + client handling
- `waiter_app_pin_login.md` — login/discovery deep dive
- `waiter_app_printing.md` — printing behavior & order attribution
- `waiter_app_payment_integration.md` — **deprecated** (waiter-side payment
  was removed; all payment happens on the POS)

Everything below is served by `ServerService` (`lib/services/server_service.dart`),
a Shelf HTTP server that runs **inside the POS app** on the LAN. The waiter
app is a pure client of this server. There is no cloud hop for waiter traffic —
it's device-to-device over Wi-Fi.

---

## 0. Architecture at a glance

```
 Waiter tablet ──HTTP (LAN)──▶  POS app (Shelf server)  ──▶ local Drift DB
        ▲                              │
        └── mDNS discovery ────────────┘  (Bonsoir: _caisse212._tcp)
```

- The POS is both the server and the source of truth. Waiter actions write
  straight into the POS's local database.
- Orders created/paid by the waiter then ride the POS's normal sync pipeline
  up to the central backend — the waiter app never talks to the backend.
- Data is **polled** (`GET`) for tables/orders. Push over SSE
  (`GET /waiters/events`) carries waiter calls and kitchen events (ready /
  canceled / rupture) — see `waiter_app_sse_notifications.md`.

---

## 1. Connecting

### 1.1 Discovery (mDNS / Bonsoir)

The POS advertises via Bonsoir under service type **`_caisse212._tcp`**.
Read the **TXT attributes** (not the SRV record) to build the URL:

| TXT key | Example | Meaning |
|---|---|---|
| `name` | `"Caisse 1"` | Human label; show in a picker if several POSes. |
| `ip` | `"192.168.1.42"` | POS IPv4 host. |
| `port` | `"8080"` | **HTTP port of the Shelf server.** |

> ⚠️ The Bonsoir SRV `port` is a placeholder (`12345`). **Always use the
> `port` TXT attribute**, never the SRV port.

Base URL: `http://{ip}:{port}`

Manual fallback: let the waiter type `ip:port` if mDNS is blocked; cache the
last working base URL.

### 1.2 Port

The server binds the POS's configured server port (Settings → Server;
effective default **8080**). It listens on `0.0.0.0` (all interfaces).

---

## 2. Authentication & authorization

There are **two** independent layers:

### 2.1 Server password (transport gate, optional)

If the cashier set a server password (Settings → Server), **every** request
except `GET /health` must send:

```
X-Server-Password: <the password>
```

Missing/wrong → `403 {"error":"Invalid or missing server password"}`.
If no password is configured, the header is not required.

### 2.2 Waiter identity (`waiterId`)

- `POST /waiters/login` validates a **PIN** and returns the waiter's numeric
  `id`.
- Every subsequent endpoint takes that `id` as **`waiterId`** (query param on
  GETs, body field on writes). There is **no session token** — the endpoints
  simply trust the `waiterId` you pass.
- **Ownership** is enforced on a per-order basis: mutating or viewing a
  specific order requires `order.waiter_id == waiterId`, else `403`.

> 🔒 **Security note.** Because `waiterId` is a small integer and there's no
> per-session secret, the server password is the only real barrier on the
> LAN. See §8 (Observations) — this is the top item to decide on.

### 2.3 CORS

Open: `Access-Control-Allow-Origin: *`, methods `GET, POST, PUT, DELETE,
OPTIONS`, allowed headers include `X-Server-Password`. Pre-flight `OPTIONS`
returns `200`. A browser-based waiter client works.

---

## 3. Conventions

- **Content-Type:** send `application/json` on POST/PUT bodies; all responses
  are `application/json`.
- **Numbers:** money/quantity are JSON numbers (quantities can be
  fractional — e.g. weighed items).
- **Dates:** ISO-8601 strings (`createdAt`, `updatedAt`).
- **Error envelope:** `{"error": "<machine_or_human_string>", "details": "..."}`
  (`details` only on 500s).
- **Status codes used:** `200` OK, `201` Created, `400` bad input,
  `403` forbidden (bad password / not owner / inactive), `404` not found,
  `500` server error, `503` printer unavailable.

### 3.1 Endpoint index

**Connection & auth**

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness probe (no auth) |
| GET | `/waiters/profiles` | Login roster (id/name/photo) for the profile picker |
| POST | `/waiters/login` | PIN login (optionally scoped to a picked profile) |

**Catalog & dashboard**

| Method | Path | Purpose |
|---|---|---|
| GET | `/waiters/dashboard` | Daily totals for a waiter |
| GET | `/waiters/products` | Menu products |
| GET | `/waiters/categories` | Categories |
| GET | `/waiters/components` | Modifiers/components |
| GET | `/waiters/component-groups` | Modifier groups + selection rules |
| GET | `/waiters/product-components` | Product→modifier links |
| GET | `/waiters/product-component-groups` | Per-product overrides of a group's selection rules |
| GET | `/waiters/product-variants` | Variants for a product |

**Tables**

| Method | Path | Purpose |
|---|---|---|
| GET | `/waiters/tables` | Tables + occupancy/balance |
| POST | `/waiters/tables/{tableId}/clear` | Free a table (unlink its order) |

**Orders**

| Method | Path | Purpose |
|---|---|---|
| GET | `/waiters/orders` | Waiter's orders (itemised) |
| GET | `/waiters/orders/{code}` | One order, full detail |
| POST | `/waiters/orders` | Create an order (always open/unpaid) |
| PUT | `/waiters/orders/{code}/add-product` | Append a line |
| PUT | `/waiters/orders/{code}/add-products` | Append a whole round (preferred) |
| DELETE | `/waiters/orders/{code}/products/{opId}` | Remove a line |
| POST | `/waiters/orders/{code}/cancel` | Cancel the order |
| POST | `/waiters/orders/{code}/transfer-table` | Move to another table |
| POST | `/waiters/orders/{code}/print` | Reprint ticket/KDS |

> **Payment is POS-only.** The waiter app never takes payment. A waiter order
> is always created open; the **cashier** settles it on the POS (waiter
> settlement / profile dialog). The order/detail responses still expose `paid`
> / `balanceAmount` so the waiter can *see* what the cashier has settled.

> **Session scoping.** `dashboard` and `orders` reflect only the **open shift**
> (not a calendar day) and return empty when no session is open. **`tables` is
> NOT session-scoped** — occupancy mirrors the POS regardless of session.
> Creating an order requires an **open, non-paused** session, else
> `POST /waiters/orders` returns `409 no_open_session` or `session_paused`.
> Full error catalog: `waiter_api_errors.md`.

---

## 4. Endpoints

### 1) `GET /health`

Liveness check. **No auth** (skips the password gate).

**200**
```json
{ "status": "ok", "timestamp": "2026-07-23T10:00:00.000", "port": 8080,
  "coursesEnabled": false, "waiterCallsEnabled": false, "catalogVersion": "…",
  "waiterShowKitchenStatus": false, "waiterNotifyReady": false,
  "waiterNotifyCanceled": false, "waiterNotifyRupture": false }
```

Switch fields are always present. When `waiterShowKitchenStatus` is `true`,
each order line in `GET /waiters/orders` and `GET /waiters/orders/{code}` also
carries `kitchenState` (`PENDING` | `PREPARING` | `READY` | `CANCELED`) and
`readyAt` (ISO-8601 or `null`). When it is `false` those two keys are
**absent** — never read a missing key as `PENDING`.

**Money on orders** (`GET /waiters/orders`, `GET /waiters/orders/{code}`), since 2026-09-24:

| Order field | Meaning |
|---|---|
| `subtotalAmount` | Before any discount |
| `discountAmount` | Line discounts (promo + manual) + order-level discount |
| `totalAmount` | After every discount (the order-level % is now applied — it was ignored before) |
| `paidAmount` | `totalAmount − balanceAmount` (payment is per line: a line is paid once a ticket carries it) |
| `balanceAmount` | Unpaid lines, with the order-level % off |
| `discountLabel` | `"-10%"` when an order-level discount exists, else `null` |
| `discountReason` | The cashier's reason for it, or `null` |

Per line: `grossTotal` (before discount), `discountAmount` (positive), and the existing `lineTotal` (after the line's own discounts; the order-level % is not spread over lines).

---

### 2a) `GET /waiters/profiles`

Roster for the login **profile picker** — the active waiters the app shows so
the user taps their name/photo, then enters their PIN (instead of a blind PIN
entry). Carries **no PIN**; names/photos aren't secret, the PIN is still the
credential. No `waiterId` needed. (Server password still applies if set.)

**200**
```json
{ "waiters": [ { "id": 42, "firstName": "Yassine", "lastName": "B.", "imageUrl": "…" } ] }
```
Only `is_active` waiters, ordered by first name. `lastName`/`imageUrl` may be `null`.

**Errors:** `500`.

---

### 2b) `POST /waiters/login`

PIN authentication. The PIN is unique per waiter (enforced by a partial
unique index on the POS DB).

**Body**
```json
{ "pin": "1234", "waiterId": 42 }
```
- `pin` (required) — trimmed server-side, case-sensitive.
- `waiterId` (optional) — the profile the user picked in the picker. When
  present, the PIN is validated **against that specific waiter** (picking
  profile A but typing B's PIN → `403`). When omitted, falls back to the
  original pin-only lookup (any waiter whose PIN matches).

**200**
```json
{
  "waiter": {
    "id": 42,
    "firstName": "Yassine",
    "lastName": "B.",
    "imageUrl": "https://…/42.jpg",
    "areaIds": [3, 5, 7]
  }
}
```
- `id` → use as `waiterId` everywhere after.
- `areaIds` → the dining areas the waiter is assigned to. **Empty array =
  "global" waiter** who may serve every table.
- `lastName`, `imageUrl` may be `null`.

**Errors**

| Status | Body | Meaning |
|---|---|---|
| 400 | `{"error":"pin_required"}` | Missing/empty pin |
| 403 | `{"error":"invalid_pin"}` | Unknown PIN **or** inactive waiter (deliberately indistinguishable) |
| 500 | `{"error":"login_failed","details":"…"}` | Server error |

**Side effect:** writes an activity-log entry (audit trail) on success.

---

### 3) `GET /waiters/dashboard?waiterId={id}`

KPI tile for the waiter, **scoped to the current cash session** (the open
shift) — not a calendar day. If **no session is open**, all fields return `0`.

**Query:** `waiterId` (required).

**200**
```json
{
  "totalOrders": 12,
  "activeOrders": 3,
  "cancelledOrders": 1,
  "expectedCash": 840.0,
  "totalCash": 610.0,
  "cancelledAmount": 45.0
}
```

| Field | Definition |
|---|---|
| `totalOrders` | Non-cancelled orders the waiter created **this session**. |
| `activeOrders` | Of those, the ones not yet `COMPLETED`. |
| `cancelledOrders` | Count of this session's cancelled orders. |
| `expectedCash` | Sum of all non-cancelled order line totals (`(unit+components)×qty − discounts`). |
| `totalCash` | Sum of **paid** lines (linked to a non-cancelled ticket). |
| `cancelledAmount` | Sum of cancelled order line totals. |

> If the cashier disabled **Settings → Server → "Show owed amounts in
> waiter app"** (`waiterDashboardShowOwed=false`), the three money fields are
> forced to `0.0` (keys stay present for a stable shape).

**Errors:** `400` missing/invalid `waiterId`; `500`.

---

### 4) `GET /waiters/products`

All **active** products (the menu). No params.

**200**
```json
{
  "products": [
    {
      "id": 10, "name": "Tacos", "barcode": "…", "imageUrl": "…",
      "description": "…", "price": 40.0, "finalPrice": 40.0,
      "categoryId": 2, "stationId": 1, "isVariant": false,
      "color": "#FF8800", "isPlannable": false, "planDurationMinutes": null
    }
  ]
}
```
- `finalPrice` = price after any product-level discount — use this for totals.
- `isVariant: true` → fetch options via endpoint 9 before ordering.

**Errors:** `500`.

---

### 5) `GET /waiters/categories`

Active categories, ordered by `displayOrder`. No params.

**200**
```json
{ "categories": [
  { "id": 2, "name": "Plats", "imageUrl": "…", "description": "…",
    "displayOrder": 1, "color": "#3366FF" }
] }
```

---

### 6) `GET /waiters/components`

All modifier components. No params. 86'd components (`isActive = false`) are
excluded server-side — same rule the POS itself applies to new lines. The
`isActive` field is still sent (always `true` on a surviving row) so a client
that skips its own filtering has something to defend itself with.

**200**
```json
{ "components": [
  { "id": 5, "name": "Extra cheese", "price": 5.0, "componentGroupId": 1,
    "displayOrder": 2, "isActive": true }
] }
```

---

### 7) `GET /waiters/component-groups`

Modifier groups, ordered by `displayOrder`. No params. `selectionType` is
`"SINGLE"` (radio, at most one), `"MULTIPLE"` (checkboxes, one each) or
`"QUANTITY"` (steppers, the default). `minSelection > 0` is what makes a group
required — there is no separate required flag. `maxSelection: null` means
unlimited; treat `0` the same way (some rows arrive that way from upstream).
These are the group's OWN defaults — see §7a for the per-product overrides
that win over them field by field.

**200**
```json
{ "componentGroups": [
  { "id": 1, "name": "Toppings", "description": "…", "displayOrder": 1,
    "selectionType": "MULTIPLE", "minSelection": 0, "maxSelection": 2,
    "freeQuantity": 1, "color": "#ff8800" }
] }
```

---

### 7a) `GET /waiters/product-component-groups`

Per-product overrides of a group's selection rules. No params. A row exists
ONLY for a genuinely overridden `(productId, componentGroupId)` pair — a
product that follows its group's defaults has no row here.

Within a row, each rule field (`selectionType`/`minSelection`/`maxSelection`/
`freeQuantity`) is **omitted from the JSON entirely when that field carries no
override** — never sent as an explicit `null`, never coerced to `0`. Test with
your JSON library's "has this key" rather than "is this value null": on this
endpoint `minSelection: 0` would silently un-require a group and
`maxSelection: 0` would read as unlimited, so a coerced zero would be
indistinguishable from a genuine override in both directions. `displayOrder`
is the one field always present (the column is non-nullable).

**200**
```json
{ "productComponentGroups": [
  { "productId": 12, "componentGroupId": 3,
    "selectionType": "SINGLE", "minSelection": 1, "displayOrder": 2 }
] }
```
This row overrides only `selectionType`/`minSelection` for product 12's group
3 — `maxSelection` and `freeQuantity` are absent, so fall back to whatever
`GET /waiters/component-groups` says for group 3.

Merge order: `override.field ?? group.field`, applied per field, never per row.

---

### 8) `GET /waiters/product-components`

Which components attach to which product, with defaults/limits. No params.
`chargeOnRemoval`: when true, taking this default off the product still bills
it — see §7 for why intake does not yet accept the removal.

**200**
```json
{ "productComponents": [
  { "productId": 10, "componentId": 5, "defaultPrice": 5.0, "defaultQuantity": 0,
    "isRequired": false, "minQuantity": 0, "maxQuantity": 3, "chargeOnRemoval": false }
] }
```
Use `minQuantity`/`maxQuantity`/`isRequired` to drive the modifier UI.

---

### 9) `GET /waiters/product-variants?productId={id}`

Variant matrix for one product (sizes/options), with attribute groups for a
picker. **Query:** `productId` (required).

**200 (has variants)**
```json
{
  "hasVariants": true,
  "baseProduct": { "id": 10, "name": "Pizza", "price": 60.0, "imageUrl": "…" },
  "variants": [
    {
      "id": 101, "productId": 10, "name": "Large",
      "barcode": "…", "sku": "…", "description": "…", "imageUrl": "…",
      "color": "…", "price": 80.0, "additionalPrice": 20.0, "finalPrice": 80.0,
      "tvaAmount": 0.0, "isActive": true,
      "attributes": [ { "attributeId": 1, "attributeName": "Size", "valueId": 3, "value": "L" } ]
    }
  ],
  "attributeGroups": [
    { "id": 1, "name": "Size", "values": [ { "id": 3, "value": "L", "attributeId": 1 } ] }
  ]
}
```
- Pass the chosen `variant.id` as `variantId` when adding the line; the POS
  re-reads the authoritative variant price server-side.

**200 (no variants):** `{ "hasVariants": false, "variants": [], "attributeGroups": [] }`

**Errors:** `400` missing/invalid `productId`; `404` product doesn't exist; `500`.

---

### 10) `GET /waiters/tables?waiterId={id}`

Tables the waiter can serve, with live occupancy + outstanding balance.
**Query:** `waiterId` (required).

- **Area-restricted** waiter (`areaIds` non-empty at login) → only tables in
  those areas.
- **Global** waiter (`areaIds` empty) → all tables.
- Occupancy is scoped to the **current session**: a table linked only to a
  prior (closed) session's order reads as free. With no session open, every
  table is free.

**200**
```json
{ "tables": [
  { "id": 12, "name": "T12", "capacity": 4, "areaId": 3, "areaName": "Terrace",
    "orderId": 88, "orderCode": "RGH7IE3H3LR", "totalAmount": 120.0,
    "orderWaiterId": 3, "orderWaiterName": "Salma" }
] }
```

| Field | Meaning |
|---|---|
| `orderId`/`orderCode` | The open order occupying the table, or `null` = **free**. |
| `totalAmount` | **Outstanding balance = unpaid lines only.** A fully-paid-but-not-cleared table shows the order with `totalAmount: 0`. |
| `orderWaiterId` | Who is serving the table. `null` = **nobody's**. |
| `orderWaiterName` | Their display name, or `null`. Presentation only — match on the id. |

> **`orderWaiterId` is not `waiterId`.** The query param on this endpoint is
> already `waiterId` and means the *caller*; this is the waiter on the table's
> ORDER, which is why it is named for the order like `orderId`/`orderCode`.
>
> **Null means "nobody's", never "everybody's".** It is null for a free table,
> for an order the cashier rang up at the till (`Orders.waiterId` is nullable),
> and it is absent entirely on builds before this field existed. Treat absent
> and null identically, and never as a wildcard — a null must not make a table
> match every waiter.
>
> This is for a **view** ("which of these am I holding"), not for scoping.
> Which tables a waiter RECEIVES is already decided server-side by their area
> assignments; this field only lets the app sort the ones it was given.

> **Occupancy mirrors the POS**: a table is occupied whenever it has an order
> linked, including a paid `COMPLETED` order that hasn't been cleared. Only
> `CANCELED` orders are excluded. Treat this endpoint as the single source of
> truth for occupancy and re-fetch after paying.

**Errors:** `400` missing/invalid `waiterId`; `500`.

---

### 11) `GET /waiters/orders?waiterId={id}&status={csv}&page={n}&limit={n}`

The waiter's orders for the **current session**, **fully itemised**. Ordered
newest-first. With no session open, returns an empty list.

**Query**

| Param | Required | Default | Notes |
|---|---|---|---|
| `waiterId` | yes | — | |
| `status` | no | (all) | CSV, e.g. `PENDING,PREPARING`; matched upper-case. |
| `page` | no | `0` | Zero-based. |
| `limit` | no | `20` | Page size. |

**200**
```json
{
  "orders": [
    {
      "id": 88, "code": "RGH7IE3H3LR", "status": "PENDING", "type": "DINE_IN",
      "persons": 2, "tableId": 12, "tableName": "T12",
      "totalAmount": 220.0, "balanceAmount": 120.0, "allPaid": false,
      "productCount": 3,
      "products": [
        {
          "id": 501, "productId": 10, "name": "Tacos", "quantity": 2.0,
          "unitaryPrice": 40.0, "note": "no onion", "paid": true, "lineTotal": 80.0,
          "components": [ { "id": 9, "componentId": 5, "name": "Extra cheese", "quantity": 1, "price": 5.0 } ]
        }
      ],
      "createdAt": "2026-07-23T09:12:00.000", "updatedAt": "2026-07-23T09:20:00.000"
    }
  ],
  "page": 0, "limit": 20, "count": 1
}
```

| Field | Meaning |
|---|---|
| `totalAmount` | **Full** order total (all lines). |
| `balanceAmount` | Outstanding (unpaid lines only). |
| `allPaid` | `true` when every line is on a ticket. |
| `products[].id` | The **`order_products.id`** — use it to remove a line. |
| `products[].paid` | Whether that line has been settled on the POS. |

**Errors:** `400` missing/invalid `waiterId`; `500`.

---

### 12) `GET /waiters/orders/{code}?waiterId={id}`

Full detail for **one** order — identical per-order shape as endpoint 11, but
a single object. Use it to render an itemised order screen.

**Path:** `{code}` = order code. **Query:** `waiterId` (required, ownership-checked).

**200**
```json
{
  "id": 88, "code": "RGH7IE3H3LR", "status": "PENDING", "type": "DINE_IN",
  "persons": 2, "tableId": 12, "tableName": "T12",
  "totalAmount": 220.0, "balanceAmount": 120.0, "allPaid": false, "productCount": 3,
  "products": [ { "id": 501, "productId": 10, "name": "Tacos", "quantity": 2.0,
    "unitaryPrice": 40.0, "note": null, "paid": false, "lineTotal": 80.0, "components": [] } ],
  "createdAt": "…", "updatedAt": "…"
}
```

**Errors:** `400` missing `waiterId`; `403` not owner; `404` no such order; `500`.

---

### 13) `POST /waiters/orders`

Create a new order.

**Body**
```json
{
  "waiterId": 42,
  "tableId": 12,
  "type": "DINE_IN",
  "persons": 2,
  "products": [
    {
      "productId": 10,
      "variantId": null,
      "quantity": 2,
      "note": "no onion",
      "components": [ { "componentId": 5, "quantity": 1, "price": 5.0 } ]
    }
  ]
}
```

| Field | Required | Default | Notes |
|---|---|---|---|
| `waiterId` | yes | — | Must exist & be active. |
| `type` | no | `DINE_IN` | `DINE_IN` \| `TAKE_AWAY` \| `DELIVERY`. |
| `tableId` | for `DINE_IN` | — | Required when `DINE_IN`. |
| `persons` | no | `1` | Covers. Set **only at creation** — neither `add-product` nor `add-products` accepts it, and there is no waiter endpoint to amend it afterwards. The cashier can still change it on the POS, so it is a starting number, not a lock. Reopening an order returns whatever it currently holds. |
| `products[]` | no | `[]` | Unknown `productId`s are skipped. |
| `products[].variantId` | no | — | Server re-reads variant price/TVA. |
| `products[].quantity` | no | `1` | Fractional allowed. |
| `products[].note` | no | — | Per-line note. |
| `products[].components[]` | no | `[]` | `componentId` (req), `quantity` (1), `price` (0.0). |

**Requires an OPEN, non-paused cash session.** Checked against the session's
live status at request time. Rejected with **`409`**:
- `{"error":"no_open_session","message":"…"}` — no session open (or it ended).
- `{"error":"session_paused","message":"…"}` — the cashier paused the session.

Orders can only be raised during an active shift (the POS itself needs an open
session to ring up). See `waiter_api_errors.md` for the full error catalog.

**Validation / `400`s:** `waiterId` missing; `DINE_IN` without `tableId`;
invalid/inactive waiter; table not found. **`403`:** an area-restricted
waiter targeting a table outside their areas (global waiters may use any
table). **`409 table_taken_by_other_waiter`:** the target table already has an
**active** order owned by someone else — a completed/canceled leftover doesn't
block. To add to your own open order, use `add-product` instead.

**201**
```json
{ "id": 88, "code": "RGH7IE3H3LR", "message": "Order created successfully" }
```

**Server-side behavior (matches a cashier POS order):**
- `source = 'WAITER'`; `created_by`/`taken_by` = the POS user currently logged
  in; `waiter_id` = you; `session_id`/`z_day` = active cash session.
- Initial `status` = **`defaultOrderStatus`** (same setting as cashier
  orders). Line `state` = `ONHOLD` if that status is `ONHOLD`, else `PENDING`.
- Links the table (`areaTables.order_id`).
- The order is always created **open/unpaid**. Payment is a cashier action on
  the POS — there is no pay-on-create.
- Fires auto-prints (order ticket + KDS) under the `printWaiterPaper` master
  switch + per-output rules.
- Auto-syncs to the backend when online.

**Note:** order-level `note` is **not** currently accepted (only per-line notes).

**Errors:** `400`, `403`, `409` (`no_open_session` / `session_paused` /
`table_taken_by_other_waiter`), `500` as above. Full catalog:
`waiter_api_errors.md`.

---

### 14) `PUT /waiters/orders/{code}/add-product`

Append one product line to an existing order.

**Body**
```json
{ "waiterId": 42, "productId": 10, "variantId": null, "quantity": 1,
  "note": "extra spicy", "components": [ { "componentId": 5, "quantity": 1, "price": 5.0 } ] }
```

| Field | Required | Notes |
|---|---|---|
| `waiterId` | yes | Must own the order. |
| `productId` | yes | Must exist. |
| `variantId`/`quantity`/`note`/`components` | no | As in create. |

**200** `{ "message": "Product added to order successfully" }`

**Behavior:** inserts the line (`state = PENDING`) + components, touches
`updated_at`, logs, and fires a **KDS ticket for the new line only**
(`modificationsOnly`), gated by `printWaiterPaper` + `kdsEnabled` + rules.

**Errors:** `400` missing `waiterId`/`productId`, or product not found;
`403` not owner; `404` order not found; `500`.

---

### 14b) `PUT /waiters/orders/{code}/add-products`  ← prefer this

Append **several** product lines in one call. Same job as `add-product`, but
for a whole round of ordering at once.

**Use this instead of looping `add-product`.** It is not a micro-optimisation:
it is the difference between one kitchen ticket and N of them. Sent as N single
calls there is nothing on the wire telling the POS where the round ended, so it
has to group them with a timer (`waiterKdsBatchSeconds`, default 12s) and the
kitchen ticket is delayed by that much. One call *is* the round, so the ticket
is exact and immediate.

`add-product` (singular) is **not deprecated** and is not going away — older
tablets keep using it, and the two can be mixed freely on the same order.

**Body**
```json
{
  "waiterId": 42,
  "products": [
    { "productId": 10, "quantity": 2, "note": "extra spicy" },
    { "productId": 11, "variantId": 3, "quantity": 1, "courseNo": 2,
      "components": [ { "componentId": 5, "quantity": 1, "price": 5.0 } ] }
  ]
}
```

| Field | Required | Notes |
|---|---|---|
| `waiterId` | yes | Must own the order. |
| `products` | yes | Non-empty array. Each entry is **exactly** the shape used in the `products` array of `POST /waiters/orders` — same keys, same optionality. |

**200**
```json
{ "message": "Products added to order successfully", "added": 2, "skipped": [] }
```

| Field | Meaning |
|---|---|
| `added` | How many lines were actually written. |
| `skipped` | Lines the catalogue did not recognise, as `{ "index": 1, "productId": 9999 }`. `index` is the position in the `products` array you sent. The rest still went in — show the user what was dropped rather than claiming the round failed. |

`skipped` carries the **index**, not just the id, because the id alone cannot
identify a line: a cart legitimately holds two entries of the same product that
differ by variant, options or `courseNo`, and they ring up differently. Told
only the id, you cannot tell which of your two lines to keep for retry.

**Batching makes course sections deterministic. A loop makes them a coin
flip.** The POS decides sections from *the lines being printed* —
`shouldSplitByCourse` needs at least two lines carrying more than one distinct
`courseNo`.

* **One `add-products` call** → one ticket holding the whole round, printed
  **immediately** → sections always correct, regardless of timing. The grouping
  wait (`waiterKdsBatchSeconds`) is skipped entirely: this call is itself the
  statement that the round is finished, so there is nothing to wait for.
* **N `add-product` calls** → it depends on `waiterKdsBatchSeconds`:
  * window **> 0** and every tap lands inside the rolling window → the calls
    collapse into one print job whose delta is all the new lines → it **does**
    section;
  * window **= 0**, or a waiter pauses long enough for the window to expire
    mid-round → one ticket per line → one line can never split → **no
    sections**.

So a looping build gives a waiter who orders briskly a sectioned ticket and a
waiter who stops to talk to the table an unsectioned one, with nothing on
either end explaining the difference. That non-determinism is the real argument
for batching — more than the ticket count, and more than "a loop cannot
section", which is not true.

> **Do not set `waiterKdsBatchSeconds: 0` while any tablet still loops
> `add-product`.** You do not need to change it for batching tablets either —
> `add-products` already bypasses the wait. The setting only governs the looped
> route. Set it early and a shop that uses courses loses sections on
> every round after the order's first, because the create ticket (`full` mode)
> is the only one that ever sees more than one line.

**Behavior:** every line (`state = PENDING`) and its components commit in **one
transaction** — a half-added round is never visible. Then `updated_at` is
touched, `is_synced` cleared, one log entry written, and **one** KDS ticket
fired for the whole round (`modificationsOnly`), gated by `printWaiterPaper` +
`kdsEnabled` + rules.

Prices, TVA and pre-discounts are always read from the POS catalogue. Anything
price-shaped in the request body is ignored — a tablet cannot name its own
price.

**Errors:** `400` missing `waiterId`, empty `products`, or *every* product
unknown (`error: "no_known_products"`, nothing written); `403` not owner;
`404` order not found; `500`.

---

### 15) `POST /waiters/orders/{code}/print`

Explicit (re)print. **Operator action → bypasses** the auto-print rules and
the `printWaiterPaper` master switch (but still needs `printingEnabled`).

**Body**
```json
{ "waiterId": 42, "kds": false }
```
`kds: true` also reprints the kitchen ticket in **full** mode.

**200 / 503**
```json
{ "printed": true, "outputs": { "orderTicket": true, "kds": false } }
```
`200` if at least one output printed; `503` if the printer is offline /
printing disabled.

**Errors:** `400` missing `waiterId`; `403` not owner; `404`; `503`
(`{"error":"printing_disabled","printed":false}`); `500`.

---

### 16) `DELETE /waiters/orders/{code}/products/{opId}?waiterId={id}`

Remove one line from an order the waiter owns. A **paid** line (already on a
ticket) cannot be removed — refund is a cashier action.

**Path:** `{code}` order code, `{opId}` = `order_products.id` (from endpoint
11/12). **Query:** `waiterId` (required, ownership-checked).

**200** `{ "removed": true, "removedId": 501 }`

**Errors:** `400` missing `waiterId`/`opId` or `{"error":"cannot_remove_paid_line"}`;
`403` not owner; `404` order or line not found; `500`.

**Side effects:** deletes the line + its components, touches `updated_at`,
logs, auto-syncs.

---

### 17) `POST /waiters/orders/{code}/cancel`

Cancel an order the waiter owns. **Blocked** if any line is already paid
(`order_has_payments`) — a paid order must be voided/refunded by the cashier.

**Body**
```json
{ "waiterId": 42, "reason": "customer left" }
```
`reason` optional.

**200** `{ "canceled": true, "status": "CANCELED" }`

**Behavior:** sets the order **and its lines** to `CANCELED`, records the
reason, **frees the table**, logs, auto-syncs.

**Errors:** `400` missing `waiterId` / `{"error":"order_has_payments"}`;
`403` not owner; `404`; `500`.

---

### 18) `POST /waiters/orders/{code}/transfer-table`

Move an order the waiter owns to a different **free** table.

**Body**
```json
{ "waiterId": 42, "tableId": 15 }
```

**200** `{ "transferred": true, "tableId": 15 }`

**Behavior:** frees the old table, links the new one, updates `order.tableId`,
logs, auto-syncs. The waiter must be allowed to serve the target table (area
rule): global waiters (no areas) can use any table; area-restricted waiters
only tables in their areas.

**Errors:** `400` missing fields / `{"error":"target_table_occupied"}`;
`403` not owner **or** not allowed on the target table; `404` order or target
table not found; `500`.

---

### 19) `POST /waiters/tables/{tableId}/clear`

Free a table (unlink its order) **without** touching the order — the explicit
counterpart to `autoClearTableAfterPaying`. The order still exists and remains
findable in `GET /waiters/orders`.

**Path:** `{tableId}`. **Body**
```json
{ "waiterId": 42 }
```

**200** `{ "cleared": true }`

**Behavior:** sets `areaTables.order_id = null`; logs against the (former)
occupying order if any. Waiter must be allowed to serve the table (area rule).

**Errors:** `400` missing `waiterId`/`tableId`; `403` not allowed on this
table; `404` table not found; `500`.

---

## 5. End-to-end flows

### 5.1 Shift → order (payment is on the POS)
```
GET  /waiters/profiles                  → show profile picker (name/photo)
POST /waiters/login {pin, waiterId}     → validate PIN for the picked profile
GET  /waiters/tables?waiterId=…         → pick a free table
GET  /waiters/products|categories|…     → build the menu (cache it)
POST /waiters/orders                    → create order on the table (code)
PUT  /waiters/orders/{code}/add-products → add a round (one call, one ticket)
PUT  /waiters/orders/{code}/add-product  → single line; still supported
DELETE /waiters/orders/{code}/products/{opId}?waiterId=…  → remove a wrong line
GET  /waiters/orders/{code}?waiterId=…  → review the itemised bill
                                          → cashier settles it on the POS
GET  /waiters/tables?waiterId=…         → table frees once the POS clears it
```

### 5.1b Manage an open order
```
POST /waiters/orders/{code}/transfer-table {tableId}  → move the party
POST /waiters/orders/{code}/cancel {reason}           → cancel (if unpaid)
POST /waiters/tables/{tableId}/clear                  → free a table manually
```

### 5.3 Reprint
```
POST /waiters/orders/{code}/print { kds:true }   → prints regardless of auto-print settings
```

---

## 6. POS settings that change waiter behavior

These live on the POS (Settings) and are invisible to the waiter app, but they
change what the endpoints do:

| Setting | Effect on waiter APIs |
|---|---|
| `defaultOrderStatus` | Initial status of created orders (shared with cashier). |
| `autoClearTableAfterPaying` | Frees the table when the **cashier** settles the order on the POS. |
| `printWaiterPaper` | **Master** switch for all waiter auto-printing (order ticket + KDS). |
| `printWaiterOrderTicket` | Sub-toggle: order-ticket auto-print on create. |
| `PrintRule.sources` (per output) | Include/exclude `WAITER` per order-ticket/KDS. |
| `waiterDashboardShowOwed` | Zeroes the money fields in the dashboard. |
| Server password | Requires `X-Server-Password` on all endpoints. |

Printing gate order for a waiter action:
`printWaiterPaper → printingEnabled → rule.enabled → orderTypes → sources('WAITER') → requireTable (→ kdsEnabled for KDS)`.
Reprints (endpoint 15) skip everything except `printingEnabled`.

---

## 7. Data notes

- **`totalAmount` vs `balanceAmount`:** orders/detail return both — total is
  all lines, balance is unpaid lines. Tables return only the **balance** as
  `totalAmount`. (Naming differs — see §8.)
- **Line total math** (everywhere): `(unitaryPrice + Σ component.price ×
  component.quantity) × quantity − unitaryDiscount×qty − manualDiscount×qty`.
- **Prices are authoritative server-side:** on create/add, the POS re-reads
  product/variant price from its DB; client-sent prices for products are not
  trusted (component `price` is taken as sent). This is what makes the
  free-allowance split work over the wire: send one array entry per row you
  want stored (e.g. 2 units of a component at `price: 0.0` and 1 more at
  catalogue price, same `componentId`) and every entry lands as its own row —
  create/add insert one row per array entry, there is no merge-by-componentId
  and no unique constraint that would collapse them.
- **`chargeOnRemoval` is read-only for now.** `POST /waiters/orders` and
  `PUT .../add-product` do not yet accept a `removalCharge` flag on a
  component entry, so a removal that should bill cannot be expressed from the
  waiter app today — treat `chargeOnRemoval: true` as "don't offer removing
  this one" rather than "bill for removing this one".
- **Component name on an order line** (§11/§12's `components[].name`) prefers
  the name captured when the line was sold; it falls back to a live lookup
  only for older order rows written before that column existed. A component
  since 86'd still resolves through either path — a genuinely **deleted**
  component is the one case that can come back as `null`. Guard for it rather
  than rendering an empty string.

---

## 8. Observations & status

### Done in this round
- ✅ **Profile-picker login** — `GET /waiters/profiles` + optional `waiterId`
  on login (PIN validated against the picked profile).
- ✅ **Remove line** (`DELETE …/products/{opId}`) and **cancel order**
  (`POST …/cancel`).
- ✅ **Transfer table** (`POST …/transfer-table`) and **clear table**
  (`POST /waiters/tables/{id}/clear`).
- ✅ **Payment removed from the waiter side** — no pay endpoint, no
  pay-on-create, no pre-pay setting. All payment is POS-only.
- ✅ **Cleanup** — removed the dead `waiterOrderDefaultStatus` /
  `waiterOrderDefaultPaid` settings + stray debug prints.

### Still open (decide when you want)
1. **No session token — `waiterId` is trusted as-is.** The profile picker is a
   UX improvement, not a security boundary: anyone on the LAN (past the
   optional server password) can still act as any waiter by sending a guessed
   id. The server password remains the only real gate. Options: require the
   password in production, or issue a short-lived token at login.

2. **Edit-quantity not supported.** The waiter can add or remove whole lines,
   but not change a line's quantity in place (remove + re-add works). Add a
   `PUT …/products/{opId}` if inline qty edits are wanted.

3. **Order-level `note` not accepted on create.** Only per-line notes. Easy to
   add an order-wide `note`.

4. **Naming inconsistency:** `tables[].totalAmount` is the *unpaid balance*,
   while `orders[].totalAmount` is the *full* total (balance is a separate
   `balanceAmount`). Consider renaming the tables field to `balanceAmount`
   (⚠️ client-breaking — coordinate).

5. **Port default drift:** the settings *model* defaults `serverPort` to
   `2004`, but the loader/server fall back to `8080` (and docs say `8080`).
   Harmless today; pick one intended default.

If you want any of the open items, tell me which.

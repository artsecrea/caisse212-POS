# Waiter App — Current State, Changes & Error Handling

A short briefing for the **waiter app developer**. What the app can do today,
what changed recently (and needs client work), and how to handle every error.

Full detail lives in:
- `waiter_api_reference.md` — every endpoint, request/response.
- `waiter_api_errors.md` — the complete error catalog (tables per endpoint).

This doc is the **"read me first"** summary.

---

## 1. TL;DR — what you must know now

1. **Payment is POS-only.** The waiter app never takes payment — there is no
   pay endpoint anymore. Remove any pay UI. You can still *show* paid state.
2. **Orders need an open, non-paused session.** `POST /waiters/orders` can now
   fail with `409 no_open_session` / `409 session_paused`. Handle both.
3. **Don't recompute money.** Display the server's `totalAmount` / `lineTotal`
   / `balanceAmount`. The server formula was fixed; local math will disagree.
4. **New abilities:** remove line, cancel order, transfer table, clear table,
   and a login **profile picker**.
5. **Errors now carry a `message`** on the important ones — safe to show to the
   user directly.
6. **Everything (except tables) is scoped to the current session.**

---

## 2. Current capabilities

**The waiter app CAN:**
- Log in via **profile picker + PIN** (`GET /waiters/profiles`, then
  `POST /waiters/login` with `{ pin, waiterId }`).
- Browse menu (products/categories/components/variants), tables, and its own
  orders — all itemised.
- **Create** an order (open/unpaid), **add** a line, **remove** a line,
  **cancel** an order, **transfer** it to another table, **clear** a table.
- **Reprint** the order/kitchen ticket (`POST …/print`).
- See what the cashier has settled (`paid`, `balanceAmount`, `allPaid`).

**The waiter app CANNOT (by design):**
- Take payment / settle / split a bill — that's the cashier on the POS.
- Apply discounts or tips.
- Act on another waiter's order (ownership enforced).
- Edit a line's quantity in place (remove + re-add instead).

---

## 3. What changed (and what you need to do)

Grouped by area. ⚠️ = client work needed.

### Payment — removed from the waiter side ⚠️
- ❌ `POST /waiters/orders/{code}/pay` — **gone**.
- ❌ `pay` / `method` on `POST /waiters/orders` — **gone** (create is always
  open/unpaid).
- ❌ "Waiter orders pre-paid" setting — gone.
- ✅ Still exposed for display: each order/line has `paid`, and orders carry
  `balanceAmount` (unpaid) + `allPaid`.
- **Do:** delete pay/split UI. Keep a read-only "paid / balance" indicator
  driven by the server fields.

### Sessions — creation is gated, reads are scoped ⚠️
- `POST /waiters/orders` now requires an **open, non-paused** cash session:
  - `409 { "error":"no_open_session", "message":"…" }`
  - `409 { "error":"session_paused", "message":"…" }`
- `GET /waiters/dashboard` and `GET /waiters/orders` return only the **current
  session's** data (empty when no session is open) — not a calendar day.
- `GET /waiters/tables` is **NOT** session-scoped (occupancy mirrors the POS).
- **Do:** when create returns `409`, don't hard-fail — disable the "send order"
  action, show the `message` ("waiting for cashier to open/resume session"),
  keep the cart, and let the waiter retry.

### Table safety ⚠️
- Creating an order on a table that already has **another** waiter's (or a
  cashier's) active order → `409 table_taken_by_other_waiter` (with `message`
  naming the owner). This is now race-safe (transactional) — two waiters can't
  double-book the same table.
- **Do:** if it's the waiter's *own* order on that table, route to it and use
  `add-product`; otherwise show the `message`.

### Login — profile picker (new) ⚠️
- `GET /waiters/profiles` → `{ waiters: [ { id, firstName, lastName, imageUrl } ] }`
  (active waiters, no PINs).
- `POST /waiters/login` now accepts optional `waiterId`; when sent, the PIN is
  validated **against that profile** (pick A + type B's PIN → `403 invalid_pin`).
  Pin-only login still works.
- **Do:** show face/name cards, then a PIN pad for the chosen profile; send
  `{ pin, waiterId }`.

### New order-management endpoints (new) ⚠️
| Action | Endpoint |
|---|---|
| Remove a line | `DELETE /waiters/orders/{code}/products/{opId}?waiterId=` |
| Cancel an order | `POST /waiters/orders/{code}/cancel` `{ waiterId, reason? }` |
| Transfer to another table | `POST /waiters/orders/{code}/transfer-table` `{ waiterId, tableId }` |
| Free a table | `POST /waiters/tables/{tableId}/clear` `{ waiterId }` |
- **Do:** wire the UI; each enforces ownership + returns typed errors (below).

### Orders are now itemised ✅ (usually no work)
- `GET /waiters/orders` and `GET /waiters/orders/{code}` return `products[]`
  with `id` (the `order_products.id`), `name`, `quantity`, `unitaryPrice`,
  `note`, `paid`, `lineTotal`, and `components[]`, plus `totalAmount`,
  `balanceAmount`, `allPaid`, `productCount`.
- **Do:** use `products[].id` for remove-line; render `lineTotal`/`totalAmount`
  directly.

### Money calculation — fixed on the server ⚠️
- Line total is now **exactly** what the POS shows:
  `(unitaryPrice + Σ(component.price × component.quantity) − manualDiscount) × quantity`.
- The old code under-counted components on qty>1 lines and double-subtracted the
  pre-discount.
- **Do:** **stop computing totals in the app.** Render the server's
  `lineTotal` / `totalAmount` / `balanceAmount`. Any client-side math will
  drift from the POS receipt.

### Order status default (info only)
- Waiter orders now start at the shared `defaultOrderStatus` (same as cashier
  orders), configured on the POS. No client change; just know the initial
  status is cashier-controlled, not fixed to `PENDING`.

---

## 4. Error handling

### 4.1 The shape

```json
{ "error": "<code_or_sentence>", "message": "optional human text", "details": "500 only" }
```

- **`error`** — either a **machine code** (`snake_case`, stable — prefer these)
  or a **human sentence** (older endpoints).
- **`message`** — present on the important business errors; **safe to show the
  user as-is**.
- **`details`** — only on `500`; for your logs, not the user.

> **Match on HTTP status + `error` together.** Use the machine codes where
> present; treat sentence-style `error` values as labels that may be reworded —
> key off the status for those.

### 4.2 Error classes and how to handle them

| Class | Examples | Handle by |
|---|---|---|
| **Session gate** `409` | `no_open_session`, `session_paused` | Soft-block create; show `message`; keep cart; retry when session is ready. |
| **Table conflict** `409/400` | `table_taken_by_other_waiter`, `target_table_occupied` | Show `message`. If it's the waiter's own order → route to it + `add-product`. |
| **Business rule** `400` | `cannot_remove_paid_line`, `order_has_payments` | Show `message`; the action is legitimately blocked (a cashier must handle it). |
| **Ownership** `403` | `Not authorized to …` | Hide edit/print controls for orders the waiter doesn't own; refresh the list. |
| **Not found** `404` | `Order not found`, `Table not found` | Local cache is stale — re-fetch `orders`/`tables`. |
| **Auth** `403/400` | `invalid_pin`, `pin_required`, `Invalid or missing server password` | Re-prompt PIN (ambiguous by design); or re-send the server password. |
| **Validation** `400` | `waiterId is required`, `Invalid waiterId` | A client bug — fix the request; shouldn't reach users. |
| **Printing** `503` | `printing_disabled` | Tell the waiter the ticket didn't print; the order action still succeeded. |
| **Server** `500` | `Failed to …` (+`details`) | Generic retry; log `details`. |
| **Network** — | timeout / connection refused | "Can't reach POS — check Wi-Fi"; offer manual-IP + retry. Don't drop input. |

### 4.3 Machine codes that carry a `message` (the ones you'll show users)

| `error` | HTTP | Endpoint |
|---|---|---|
| `no_open_session` | 409 | create |
| `session_paused` | 409 | create |
| `table_taken_by_other_waiter` | 409 | create |
| `target_table_occupied` | 400 | transfer-table |
| `cannot_remove_paid_line` | 400 | remove line |
| `order_has_payments` | 400 | cancel |

Other stable machine codes (no `message`): `pin_required`, `invalid_pin`,
`printing_disabled`.

---

## 5. Golden rules (pin these on the wall)

1. **Never take payment** — no pay endpoint exists; the cashier settles on the POS.
2. **Never compute totals** — render `totalAmount` / `lineTotal` /
   `balanceAmount` from the server.
3. **Create needs a live session** — handle `409 no_open_session` /
   `session_paused` gracefully (keep the cart).
4. **Ownership is enforced** — only show actions for the waiter's own orders.
5. **`GET /waiters/tables` is the source of truth for occupancy** — re-fetch
   after any create/cancel/transfer/clear.
6. **Prefer machine codes; show `message` when present.**
7. **A `200` on `…/print` isn't a guarantee** — check `printed` / `outputs`.

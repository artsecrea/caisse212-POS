# Waiter App ↔ POS — Printing & Order Attribution

This doc describes how printing and order ownership work between the
waiter app and the POS for the three endpoints the waiter app calls:

- `POST /waiters/orders` — create an order
- `PUT /waiters/orders/{code}/add-product` — add a product to an existing order
- `POST /waiters/orders/{code}/print` — **NEW**: on-demand reprint

Plus a guide for the waiter app team to wire the new reprint endpoint
and a paper-size diagnostic for the "title not centered, lines don't
span" symptom.

---

## 1. Mental model — there is no "special" waiter ticket

A waiter-created order is, on paper, **identical to a cashier-created
order**. The POS uses the same template (`printOrderReceipt`), the same
KDS template (`printKdsTicket`), and the same store-identity header.
The only visible differences are:

| Field on the printed ticket | What it shows |
|---|---|
| **Cashier** | The POS user logged in when the waiter order arrived. (Order is stored with `created_by` = this user, so it matches the standard cashier line on the receipt and the Orders Management attribution.) |
| **Waiter** | The waiter who raised the order (separate column on the order row). Carried on the receipt when the table area / order context surfaces it; visible everywhere in the cashier-side UI. |

If you see a "different looking" ticket from a waiter order, see §6 —
it's almost always a paper-size config mismatch, not a template
divergence.

---

## 2. `POST /waiters/orders` — create

When the waiter app posts a new order:

1. The POS persists the order with:
   - `source = 'WAITER'` (rule-engine + reporting tag)
   - `waiter_id = <the waiter you authenticated as>`
   - `created_by` / `taken_by` = the **POS user currently logged in**
     (so the order looks like a normal cashier order in all the
     cashier-side screens — Orders Management, Daily Summary, etc.)
   - `session_id` = the POS's active cash session (or `null` if none open)
   - `status` = cashier-configured default (Settings → Order Defaults →
     "Waiter Order Status"; default `PENDING`)
2. The waiter app gets back `{ id, code, message }` immediately.
3. **In the background**, the POS fires the standard auto-prints:
   - **Order ticket** (customer copy) — `printOrderReceipt` template,
     same as a cashier order.
   - **KDS ticket** — same as a cashier order, honoring
     `splitKdsByStation` and per-station printer assignments.
   - **Customer receipt + store copy + cash drawer kick** — only if
     `waiterOrderDefaultPaid = true` in Settings → Order Defaults
     (Section §3 below).

Each output is gated by the cashier's per-rule `Sources` filter — the
cashier can uncheck "Waiter" on the Customer Receipt rule and waiter
orders will print everything except customer receipts. Default: all
outputs on for source `WAITER`.

### 2.1 No body change needed in the waiter app

The waiter app already posts the body it has always posted. No new
fields. The behavior changes are all server-side, driven by Settings.

---

## 3. `waiterOrderDefaultPaid` mode (optional)

When the cashier enables **Settings → Order Defaults → "Waiter orders
are pre-paid"**, every order created via `POST /waiters/orders` is
auto-marked paid on the POS side:

- A **CASH ticket** is inserted for the full order amount.
- Every line is marked `state=PAID` and linked to that ticket.
- The order's status is bumped to `paidOrderDefaultStatus` (default
  `COMPLETED`).
- The receipt printer prints the **customer receipt + store copy** in
  addition to the order ticket + KDS.

The waiter app sees no API change — same POST body, same response.

Useful for shops where the waiter collects cash at the table.

---

## 4. `PUT /waiters/orders/{code}/add-product` — add an item

When the waiter app adds a product to an existing open order:

1. The POS validates the waiter owns this order (`order.waiterId ==
   body.waiterId`) and persists the new line.
2. In the background, the POS fires **KDS** in `modificationsOnly`
   mode — only the newly added line prints, exactly like the
   cashier-side "add to open order" flow. No order ticket reprint,
   no customer receipt.
3. Activity log records "Waiter X added Y to order Z".

If you want a full reprint after adding, use §5 below.

---

## 5. `POST /waiters/orders/{code}/print` — **NEW** reprint endpoint

On-demand (re)print of a waiter's own order ticket from the waiter
app. Useful for:

- "I lost the slip" — reprint the order ticket on the receipt printer
- "Kitchen says they never got it" — also reprint the kitchen ticket
- General "print this order again" gesture in the waiter app UI

### 5.1 Request

```
POST {baseUrl}/waiters/orders/{code}/print
Content-Type: application/json

{
  "waiterId": 5,
  "kds": false        // optional, default false
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| `waiterId` | int | yes | Must match `orders.waiter_id` for `{code}` |
| `kds` | bool | no | When `true`, also reprints the kitchen ticket (in FULL mode — every line, not just modifications) |

### 5.2 Responses

| Status | Body | Meaning |
|---|---|---|
| 200 | `{"printed": true, "outputs": {"orderTicket": true, "kds": false}}` | At least one output reached the printer |
| 503 | `{"printed": false, "outputs": {...}}` | Printer offline / `printingEnabled` is false |
| 400 | `{"error": "waiterId is required"}` | Body missing `waiterId` |
| 403 | `{"error": "Not authorized to print this order"}` | Waiter doesn't own this order |
| 404 | `{"error": "Order not found"}` | No order with that code |
| 500 | `{"error": "Failed to print", "details": "..."}` | Unhandled exception |

### 5.3 Important behavioral notes

- **Bypasses `shouldPrint` rules.** Reprint is operator-initiated, so
  the cashier's per-rule source / order-type filters do NOT gate this.
  Mirrors the cashier-side reprint button.
- **`orderTicket` always fires** if `printingEnabled` is on.
- **`kds: true` only fires** if `kdsEnabled` is on. If the cashier has
  disabled KDS printing globally, `kds` will report `false` even when
  requested.
- The cashier line on the reprinted ticket is the **original
  cashier** (whoever was logged in when the order was first created),
  not the cashier currently logged in. Matches the original ticket.
- A reprint counts toward `tickets.print_count` only when the order
  has an associated ticket (i.e. the order has been paid). Order
  tickets don't have a `print_count` yet — track via your own UI
  ("printed at 14:33") if needed.

### 5.4 Suggested UX in the waiter app

```
Order details screen
  ┌────────────────────────────────────┐
  │ #W42_169…                          │
  │ Table 5  ·  DINE_IN                │
  │ Total: 220.00                      │
  │                                     │
  │ [ Print receipt ]   [ Print KDS ]   │
  └────────────────────────────────────┘
```

- "Print receipt" → `POST .../print` with `kds: false`
- "Print KDS" → `POST .../print` with `kds: true`

Or a single "Reprint" action that fires `kds: true` — covers both
audiences in one tap.

---

## 6. "The ticket looks different / off-paper" — diagnostic

If the waiter ticket has:

- **Title not centered**
- **`---` lines that don't reach the edge**
- **Text looks small**

…it is **NOT a different template**. The waiter receipt and the
cashier receipt share the same `printOrderReceipt` code. What you're
seeing is one of two things:

### 6a. Paper-size mismatch (most common)

The receipt printer is physically **80mm** but the POS's
`printer_paper_size` setting is **58mm** — or vice versa.

- ESC/POS's `generator.hr()` and `PosAlign.center` measure against the
  configured paper size, NOT the printer's actual roll. If the
  configured size is smaller than the roll, `hr` only fills ~32 chars
  of the 48-char-wide paper, and the centered title centers within
  those 32 chars — so it looks left-aligned on a wide roll.
- **Fix in the POS:** Settings → Printers Management → Paper Size →
  pick the size that matches the physical roll. Hot-restart the POS.

### 6b. Text size 1 + 58mm roll

If `printer_text_size = 1` (default "normal") combined with a 58mm
roll, the body text really is small — that's the design. The cashier
ticket would look identical. Bump to `printer_text_size = 2` in
Settings → Printers Management → Text Size.

### 6c. Custom header pushes content off-page

If the cashier has typed a long `ticketHeader` in Settings, that text
wraps and pushes the centered store name off the visible part of the
roll. Trim the header or remove it.

**None of these are fixed by changing the waiter-app integration.**
They're POS-side print config issues.

---

## 7. Suggested integration order

For the waiter app team:

1. **Wire the new `POST /waiters/orders/{code}/print` endpoint.** Add
   "Reprint" / "Print KDS" buttons in the order details screen. Use
   the existing waiter PIN-auth session — no new auth.
2. **Verify the print quality** of a new waiter order by side-by-side
   comparing to a cashier-created order. If they look different, walk
   through §6 with the cashier — do NOT report it as a waiter-app
   bug, it's a print config mismatch.
3. (Optional) **Surface `waiterOrderDefaultPaid` mode behavior** in
   the waiter app's "settings" or onboarding — when the cashier turns
   this on, the waiter sees the same response shape but doesn't need
   to settle anything later. The cashier-side accounting handles it.
4. (Optional) **Respect the dashboard "show owed" toggle.** When the
   cashier disables Settings → Server Settings → "Show owed amounts
   in waiter app", `GET /waiters/dashboard` omits the
   `expectedCash` / `totalCash` / `cancelledAmount` fields. Read with
   null-safe accessors so the UI hides the corresponding rows when
   the keys are missing.

---

## 8. Quick reference

```http
# Create order — auto-prints order ticket + KDS (+ customer receipt + store
# copy when waiterOrderDefaultPaid=true). No special template; same as
# cashier-created.
POST /waiters/orders
{ "waiterId": 5, "tableId": 12, "type": "DINE_IN", "products": [...] }

# Add product — auto-prints KDS for the new line only (modificationsOnly).
PUT /waiters/orders/W5_169.../add-product
{ "waiterId": 5, "productId": 42, "quantity": 1, "components": [...] }

# Reprint on demand — operator-initiated, no rule gate.
POST /waiters/orders/W5_169.../print
{ "waiterId": 5, "kds": true }
```

All three honor the same cashier-side print config (printer slots,
paper size, language, business header). All three attribute the order
to the **POS user logged in at the moment of the action**, not to the
waiter — the waiter is recorded separately on the order row and
printed in the waiter line.

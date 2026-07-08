# POS Notification Params Contract

This document defines the `params` payload for every notification type the POS sends to
`POST /api/pos/notify`. The mobile app renders push content and in-app feed entries
**strictly from these keys** — treat them as a versioned contract.

---

## General rules

- All `params` values are **strings**.  Numbers and datetimes are serialised as strings.
- Every payload carries a `"v"` key (schema version, currently `"1"`).  Bump `v` when
  adding or renaming keys so the mobile can handle both old and new payloads gracefully.
- The mobile must **fail-soft** on unknown types or missing keys — render a generic fallback,
  never crash.
- `refId` in the envelope is the DB id of the related entity (session id as a string).
- `clientRequestId` is a UUID generated per logical event (idempotency, not yet enforced
  server-side but reserved).

---

## Type index

| `type` | Sent by | Trigger |
|---|---|---|
| `POS_SESSION_OPENED` | **POS** | Cashier opens a new cash session |
| `POS_SESSION_CLOSED` | **POS** | Cashier closes a session (Z-report) |
| `GENERAL` | **POS** | Free-form admin message from the terminal |
| `POS_ONLINE` | backend (SSE) | Terminal heartbeat came online *(POS does not send)* |
| `POS_OFFLINE` | backend (SSE) | Terminal went offline *(POS does not send)* |
| `SUBSCRIPTION_EXPIRING` | backend (task) | Subscription nearing end *(POS does not send)* |

---

## `POS_SESSION_OPENED`

Fired immediately after `startSession` succeeds, before navigating to the main screen.

### Envelope

```json
{
  "type": "POS_SESSION_OPENED",
  "params": { ... },
  "refId": "<sessionId>"
}
```

### `params` keys

| key | required | example | notes |
|---|---|---|---|
| `v` | yes | `"1"` | Schema version |
| `terminalName` | yes | `"Caisse 1"` | `x-pos-name` header value |
| `cashierName` | yes | `"Sara Amrani"` | `firstName + " " + lastName` |
| `cashierId` | yes | `"42"` | User DB id |
| `openedAt` | yes | `"2026-06-29T08:14:00"` | Local ISO 8601 (no Z suffix) |
| `startingBalance` | yes | `"500.00"` | Opening float — 2 decimal places |
| `currency` | yes | `"MAD"` | From tenant/POS settings |

### Mobile display guidance

> **Session opened**
> Sara Amrani opened a session on Caisse 1 at 08:14
> Opening float: 500.00 MAD

---

## `POS_SESSION_CLOSED`

Fired after `endSession` + sync + email report all complete.
Contains the full Z-report summary so the mobile can render a rich feed card
without a second API call.

### Envelope

```json
{
  "type": "POS_SESSION_CLOSED",
  "params": { ... },
  "refId": "<sessionId>",
  "clientRequestId": "<uuid>"
}
```

### `params` keys

#### Identity & timing

| key | required | example | notes |
|---|---|---|---|
| `v` | yes | `"1"` | Schema version |
| `terminalName` | yes | `"Caisse 1"` | |
| `cashierName` | yes | `"Sara Amrani"` | |
| `cashierId` | yes | `"42"` | |
| `sessionCode` | yes | `"CS-20260629-081400-123"` | Matches `refId` session |
| `openedAt` | yes | `"2026-06-29T08:14:00"` | Local ISO 8601 |
| `closedAt` | yes | `"2026-06-29T16:45:00"` | Local ISO 8601 |
| `durationMinutes` | yes | `"511"` | `closedAt − openedAt` in whole minutes |
| `currency` | yes | `"MAD"` | |

#### Revenue totals

| key | required | example | notes |
|---|---|---|---|
| `totalAmount` | yes | `"4200.00"` | Sum of all paid: cash + card + phone + other |
| `totalCash` | yes | `"2800.00"` | |
| `totalCard` | yes | `"1200.00"` | |
| `totalPhone` | yes | `"0.00"` | Mobile payment subtotal |
| `totalOther` | yes | `"200.00"` | Cheque / voucher / other |

#### Counts

| key | required | example | notes |
|---|---|---|---|
| `ordersCount` | yes | `"47"` | Total non-cancelled orders in session |
| `ticketsCount` | yes | `"52"` | Paid tickets only |
| `unpaidAmount` | yes | `"150.00"` | Still-open orders at close time |
| `cancelledAmount` | yes | `"75.00"` | Sum of voided/cancelled tickets |

#### Cash drawer reconciliation

| key | required | example | notes |
|---|---|---|---|
| `moneyAtStart` | yes | `"500.00"` | Opening float |
| `moneyAtEnd` | yes | `"3300.00"` | `moneyAtStart + totalCash` (expected) |
| `countedCash` | **no** | `"3295.00"` | Physical drawer count — omitted if cashier skipped |
| `variance` | **no** | `"-5.00"` | `countedCash − moneyAtEnd`; negative = shortage |
| `countNotes` | **no** | `"Slight shortage"` | Cashier note — omitted when blank |

### Mobile display guidance

```
┌─────────────────────────────────────────────────┐
│ 🧾  Session closed — Caisse 1                   │
│  Sara Amrani  ·  08:14 → 16:45  (8h 31m)        │
├─────────────────────────────────────────────────┤
│  Revenue                                        │
│  Cash          2 800,00 MAD                     │
│  Card          1 200,00 MAD                     │
│  Phone             0,00 MAD                     │
│  Other           200,00 MAD                     │
│  ──────────────────────────────                 │
│  Total         4 200,00 MAD                     │
├─────────────────────────────────────────────────┤
│  Orders: 47    Tickets: 52                      │
│  Unpaid: 150,00 MAD   Cancelled: 75,00 MAD      │
├─────────────────────────────────────────────────┤
│  Drawer                                         │
│  Opening float    500,00 MAD                    │
│  Expected         3 300,00 MAD                  │
│  Counted          3 295,00 MAD                  │
│  Variance           − 5,00 MAD  ⚠️              │
│  Note: "Slight shortage"                        │
└─────────────────────────────────────────────────┘
```

Render rules:
- Show the **Drawer** section only when `countedCash` is present.
- Colour `variance`: green when `0`, red when negative, amber when positive.
- Format `durationMinutes` as `Xh Ym` (e.g. `"511"` → `"8h 31m"`).
- `openedAt` / `closedAt` are local times — display without timezone conversion.

---

## `GENERAL`

Free-form terminal message. The `body` field is optional plain text.

### Envelope

```json
{
  "type": "GENERAL",
  "params": { ... }
}
```

### `params` keys

| key | required | example | notes |
|---|---|---|---|
| `v` | yes | `"1"` | Schema version |
| `terminalName` | yes | `"Caisse 1"` | |
| `title` | yes | `"Register closed early"` | ≤ 80 chars — used as push title |
| `body` | **no** | `"Power outage at 16:30."` | Plain text, ≤ 255 chars |

### Mobile display guidance

Push title = `title`.  Push body = `body` (or omit if absent).
Feed card: show `terminalName` as subtitle.

---

## Versioning

When params evolve:

1. Bump `"v"` to `"2"` in the new payload.
2. The mobile checks `v` and uses the appropriate renderer.
3. Old payloads stored in the feed keep `"v": "1"` — the mobile falls back to the v1 renderer.
4. Never remove a key within the same `v` — add new keys instead and bump `v` only when
   a key is renamed or removed.

# caisse212 POS — Delivery Orders (backend contract)

Adds **delivery** as a first-class order type, with a per-order delivery **address**.
This doc lists the order types/statuses the client currently uses, flags what the
backend must support for delivery, and specifies the address field.

---

## 1. Order types

`Orders.type` (string). The client now lets the operator pick all three:

| Value | Meaning |
|---|---|
| `DINE_IN` | Eat-in (implies a table) |
| `TAKE_AWAY` | Takeaway |
| `DELIVERY` | **NEW** — delivery to an address |

A `DELIVERY` order has no table; selecting it prompts the operator for the address.

---

## 2. Order statuses currently used by the client

`Orders.status` (string). These are the values the POS reads/writes today:

| Status | Used for | Notes |
|---|---|---|
| `ONHOLD` | Parked / not yet confirmed | Not synced |
| `PENDING` | Confirmed, awaiting prep | |
| `PREPARING` | Being prepared | |
| `READY` | Ready (pickup/serve) | |
| `DELIVERED` | Handed to the customer | |
| `COMPLETED` | Fully paid / finalized | |
| `CANCELED` | Cancelled | carries `cancellationReason` |

> ⚠️ **Inconsistency to fix on the backend side too:** the client's `OrderStatus`
> enum only declares `ONHOLD, PENDING, PREPARING, READY, DELIVERED`, but the code
> actually uses `COMPLETED` and `CANCELED` as plain strings (status-change dialog,
> payment completion, cancel flow). Treat the **7 values above** as the real set.

---

## 3. Delivery-specific statuses — NOT yet configured

The current statuses don't cleanly model a delivery lifecycle (there's no
"out for delivery" stage). The client does **not** emit any delivery-only status yet
— it's waiting on the backend. **Please configure the backend to support a delivery
flow**, e.g. add:

| Suggested status | Meaning |
|---|---|
| `OUT_FOR_DELIVERY` | Left the store with a driver |
| (optional) `DELIVERY_FAILED` | Attempted, not delivered |

Suggested delivery state flow:

```
PENDING → PREPARING → READY → OUT_FOR_DELIVERY → DELIVERED → COMPLETED
                                   └── (DELIVERY_FAILED) ──┘
```

Once the backend declares the delivery statuses it supports, tell me the exact
status strings and I'll wire them into the client's status options + the status
dialog (and the `OrderStatus` enum). Until then the client only uses the 7 statuses
in §2 for delivery orders.

---

## 4. Delivery address field

Per-order address (a customer may deliver to different addresses), stored on the order.

- **Client local column:** `orders.address` (TEXT, nullable) — added in this change.
- **API — outgoing** (`syncOrdersBulk` and the queued order-update payload): the order
  JSON now includes:

  ```json
  { "code": "AB12CD34", "type": "DELIVERY", "address": "12 Rue X, Apt 3, City", "...": "..." }
  ```

  `address` is `null` for non-delivery orders.
- **API — incoming** (`GET` of orders, if the server returns orders): include `address`
  on the order so the client can display/reprint it. Field name expected: `address`.
- **Printing:** when `type == DELIVERY` and `address` is set, the client prints the
  address (bold) on both the **order ticket** and the **payment receipt**.

### Backend storage
```
ALTER TABLE orders ADD COLUMN address TEXT NULL;   -- delivery address
```
(Or reuse an existing order address column if you already have one — just return it
as `address` in the order JSON.)

---

## 5. Summary of backend work

1. Accept + persist `address` on orders (incoming order create/update) and return it.
2. Treat `DELIVERY` as a valid `type`.
3. Configure delivery statuses (e.g. `OUT_FOR_DELIVERY`) and share the exact strings.
4. Align `status` handling to the 7 values in §2 (incl. `COMPLETED`, `CANCELED`).

# Order refresh contract (server → POS)

Status: **POS side implemented 2026-10-02 (uncommitted). Backend not built yet.**
Replaces the cursor pull (`GET /pos/sync/orders`, `GET /pos/sync/payments`).

## Why

The admin (back office now, mobile app next) must be able to change an order
the till already has — cancel it, cancel a line, give a discount, edit a note —
and the till must show it. The cursor pull could skip or replay changes
(lost/reset cursor, months-old backfills into today's Z) and never ran on its
own. The new model is simpler: **the till asks for the full current state of
the orders in its open session(s)**, and the server **pings** the till when it
changes one.

## 1. `GET /api/pos/sessions/{sessionCode}/orders`

Every order whose `sessionCode` is `{sessionCode}`, for the calling terminal
(X-POS-Name + JWT tenant, as all `/pos/*`). No cursor, no paging — a session
holds tens to a few hundred orders.

- `200` → `{ "orders": [ <order snapshot>, … ] }` (a bare array is also accepted)
- `404` → session unknown to the server (not pushed yet) — the POS treats it as empty.

## 2. `GET /api/pos/orders/{orderCode}` (exists)

Must return **the same order snapshot** as one element of §1.

## 3. Order snapshot

Field names are the ones the POS already reads (camelCase; snake_case accepted).

Header: `code` (required), `status`, `type`, `priority`, `coupon`, `persons`,
`date`/`createdAt`, `updatedAt`, `tableId`, `source`, `sourceId`,
`externalOrderCode`, `discountPercentage`, `tip`, `deliveryFee`, `amountPaid`,
`balanceDue`, `paymentStatus`, `createdBy`, `takenBy`, `waiterId`, `clientId`,
`commercialId`, `note`, `address`, `cancellationReason`, `zDay`.

`products`: **every** line, including removed ones:
`id` (server line id — required), `productId`, `variantId`, `price`/`unitaryPrice`,
`unitaryDiscount`, `manualDiscount`, `unitaryTva`/`totalTva`, `quantity`, `note`,
`state`, `saleUomId`, `planStartAt`/`planEndAt`/`planWaiterId`/`planResourceId`,
`deletedAt` (set on a removed line), `components`: [`componentId`, `quantity`,
`price`, `isSpecial`, `name`, `removalCharge`].

`payments`: the order's tickets: `num` (required), `paymentMethod`, `amount`,
`isPaid`, `isCancelled`, `date`, `zDay`, `deletedAt`.

`sessionId` is ignored — the till keeps its own session link.

## 4. Rules

**Server**
1. A cancelled **order** is `status: "CANCELED"` + `cancellationReason`. Never
   send an order with `deletedAt` — the POS ignores order tombstones and never
   deletes an order (orders are kept forever).
2. A cancelled **line** is `state: "CANCELED"` (it stays on the order, still
   counted as annulled) — or `deletedAt` if it is truly removed. Never just
   leave a line out: a line missing from `products` is **not** removed on the
   till (a pull never subtracts).
3. Discount (remise): order level `discountPercentage`; line level
   `manualDiscount` / `unitaryDiscount`. Send `0` to remove one — a missing
   field keeps the till's value.
4. Text fields (`note`, `address`, `cancellationReason`, line `note`) are taken
   as sent: `null` clears them.
5. Line `state` other than `CANCELED` / `PAID` is ignored (kitchen states are
   LAN-local, see KDS cloud sync model).

**POS**
1. Before every refresh the till pushes its own pending orders/operations, so
   the snapshot already holds them.
2. An order with an edit still unpushed (not synced, or a queued operation) is
   **skipped** — overwriting it would lose that edit. The next refresh takes it.
3. If the changed order is open in the order panel it is reloaded — unless the
   cashier has unsaved lines on it.

## 5. Push to the till: SSE `order-updated`

On the existing stream (`/api/pos/queue/subscribe`), to the terminal that owns
the order, whenever the server changes an order **other than by that till's
own push** (admin cancel, discount, note, approval decision):

```
event: order-updated
data: {"orderCode": "ORD-…", "sessionCode": "S-…", "reason": "CANCELLED|DISCOUNT|EDIT"}
```

The till then calls §2 for that order. (`reason` is informational.)
The `pos-command` `sync_orders` now runs the §1 refresh for every open session.

Note: SSE is off by default per till (`sse_enabled`); the admin-approval flow
needs it on.

## 6. Coming next — to agree with the backend (not built)

Approval requests: a cashier without `pos:orders:cancel` / discount permission
**requests** a cancel or a discount; the request goes to the admin mobile app
as a notification; the admin accepts or refuses; on accept the server applies
the change (§4) and sends `order-updated`, on refuse it notifies the till.
Open points: request entity + endpoints, who may decide, what the till shows
while a request is pending, timeout.

## 7. Retire

Once §1 is live: `GET /pos/sync/orders`, `GET /pos/sync/payments` and the
cursor keys (`sync_orders_cursor`, `sync_payments_cursor`, …) are removed from
the POS. Until then the Sync Inspector's "force full pull" still uses them.

# Cancelled order lines — POS ↔ backend (v2 order push)

Status 2026-10-20: POS implemented (schema v66, uncommitted). Backend built by
the bms session (uncommitted, not deployed). The earlier separate
`POST /pos/v2/order-cancellations/bulk` design is dropped and the route no
longer exists.

## Rule

A line taken off an order is a **cancellation**, not a deletion. It keeps
travelling with its order on every push, so the server stores it as cancelled
instead of seeing a line that vanished.

## Wire

Routes: `PUT /pos/v2/orders/{code}` and `POST /pos/v2/orders/bulk`. Same bodies
as v1, plus on every line:

| field | |
|---|---|
| `lineUid` | required on every line; POS-minted, 7 characters, never changes. An order the server already knows may echo the server's own 8-character ids. |
| `canceledQuantity` | running total of units cancelled on the line |
| `canceledAt` | local `yyyy-MM-ddTHH:mm:ss.SSS` |
| `canceledBy` | POS user id (omitted for a waiter's removal: waiter ids are not user ids) |
| `cancelReason` | optional, not sent yet (no reason picker on the POS) |

* Cancelled whole: `state: "CANCELED"`, `quantity` = units the line had when
  cancelled, `canceledQuantity` = running total including earlier cuts (a 3 cut
  to 1 and then cancelled is `quantity: 1, canceledQuantity: 3`).
* Quantity cut (3 → 1): a live line, `quantity: 1`, `canceledQuantity: 2`.
* A line missing from a v2 push is removed by omission on the server, so the
  POS always sends its cancelled lines.

v1 routes (`/pos/orders/{code}`, `/pos/orders/bulk`) are unchanged and the POS
sends them exactly the payload it always did (no `lineUid`, no cancel fields).

## Which route an order uses

v2 only when **every** line of the order, live or cancelled, has a `lineUid`.
Lines written before v66 have none; the server knows them by ids of its own,
and a v2 push under fresh ids would read as "every line removed". Such an
order stays on v1 until it is refreshed from the server ("Mettre à jour" or an
`order-updated` event): the pull adopts the server's `lineUid` for each line,
after which the order moves to v2. New orders are v2 from their first push.

The bulk sweep splits each batch: v2-ready orders to v2 bulk, the rest to v1
bulk. Note v2 bulk also merges lines of orders the server already has (v1 bulk
only moved their state).

## POS storage

* `order_products.line_uid` — minted on every insert (cashier, waiter routes,
  payment split, external queue, pull keeps the server's).
* `order_products.canceled_quantity / canceled_at / canceled_by` — cuts on a
  live line. `quantity` stays what is sold, so totals, tickets, kitchen,
  payment and the Z read it unchanged.
* `cancelled_order_lines` — lines cancelled whole, snapshotted (price, tax,
  discounts, options, uid) before the row is deleted. Only the push reads it.
* `removed_order_items` — unchanged: the local tombstones the X/Z and the
  order panel's "Annulés" row and dialog read.

## Not covered

* Deleting an already PAID line from the panel (long press) still removes it
  and adjusts its ticket; it is a payment correction, not sent as a cancel.
* A whole order cancelled (waiter cancel, order status CANCELED) goes as
  today: order status CANCELED, lines with state CANCELED and no
  `canceledQuantity`.

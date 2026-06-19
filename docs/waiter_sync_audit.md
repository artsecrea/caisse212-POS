# Waiter Sync Audit

**Scope:** Sync logic touching the recent waiter-orders work — `source='WAITER'`
column, `sessionId` on waiter orders, the NULLed-out `createdBy`/`takenBy`, and
the auto-created CASH ticket from `waiterOrderDefaultPaid`.

**Outcome:** 4 findings (2 high, 2 medium). Fixes applied inline; verification at
the end of each finding.

---

## Finding 1 — HIGH — `source` column is not sent in order sync payload

**Where:** `lib/services/data_sync_service.dart`
- `getOrdersForSync` (bulk push, line 932)
- `syncSingleOrder` (single push, line 1231)

**Problem:** When the cashier-side POS pushes an order to the backend, the
payload omits the `source` column. So a waiter-created order — locally tagged
`'WAITER'` so the print-rule engine can filter on it — looks identical to a
cashier order on the server. Any backend reporting / analytics / receipt
re-print that wants to distinguish origins is blind.

**Fix:** Add `'source': order.source` to both payload maps.

---

## Finding 2 — HIGH — `sessionId` is not sent in order sync payload

**Where:** same file, same two methods.

**Problem:** We just fixed `_waiterCreateOrder` to stamp `sessionId` on the
order row (so the `WaiterProfileDialog`'s session-scoped query finds it).
But the sync payload never carried `sessionId` to begin with — cashier-side
orders also lose their session attribution at the wire. The backend can't
reconcile orders to sessions for Z-report purposes; it has to fall back to
matching tickets (which DO carry `sessionCode`).

The ticket sync at line 990 already includes both `sessionId` (local id)
and `sessionCode` (backend's stable key) — orders should mirror that
exact shape so the backend has a consistent contract.

**Fix:** Resolve the `sessionCode` from the session table in both
`getOrdersForSync` and `syncSingleOrder`, then add `'sessionId': order.sessionId`
+ `'sessionCode': sessionCode` to the payload.

---

## Finding 3 — MEDIUM — `takenBy` is not sent in order sync payload

**Where:** same file, same two methods.

**Problem:** The payload sends `createdBy` and `servedBy` (which we map from
`waiterId`), but `takenBy` — the user who took the order at the POS — is
dropped on the wire. For cashier orders, `takenBy` is usually the same as
`createdBy`, but for orders the cashier confirmed on behalf of someone
else (e.g. an admin assisting), `takenBy` carries the actual cashier id and
`createdBy` is whoever started the cart.

**Fix:** Add `'takenBy': order.takenBy`. If the backend doesn't have a
column for it today, it's at worst a no-op; at best it makes future audit
queries possible without a schema change in two places.

---

## Finding 4 — MEDIUM — No immediate auto-sync after waiter order creation

**Where:** `lib/services/server_service.dart` → `_waiterCreateOrder`.

**Problem:** The cashier-side order-save path in `main_screen.dart` fires
`syncManager.autoSyncOrder(orderId)` immediately after the order is saved
(when online). Waiter-side just inserts the row with `isSynced=false` and
returns — the order sits unsynced until the next periodic `SyncJobService`
cycle (5+ minutes by default) or until someone manually syncs.

This used to be fine when waiter orders were "just open tabs" but now the
default-paid flow can mark them COMPLETED + create a ticket at creation
time. A completed waiter order that's been sitting unsynced for 4 minutes
because the periodic timer hadn't fired yet is a real reporting gap.

**Fix:** Mirror the cashier-side pattern. Inside `_waiterCreateOrder`,
after the inserts (and after the print-fire), check
`lastKnownOnlineStatusProvider`; if online, fire-and-forget
`syncManagerProvider.autoSyncOrder(orderId)`. Failure is logged and
swallowed — the order is already persisted with `isSynced=false`, so the
periodic sync picks it up next cycle.

---

## Out of scope (worth noting, not fixed here)

- **Backend contract change.** Adding `source`, `sessionId`, `sessionCode`,
  `takenBy` to the order payload requires the backend to either ignore or
  consume these new keys. Both pass-through and accept-and-store are
  compatible with the existing serializer — but if backend validation is
  strict (whitelist) the fields will silently drop. Worth coordinating
  with the backend team.
- **The cashier-side order-save path** has the same `source`/`sessionId`/
  `takenBy` gap upstream, but `source` is null for cashier orders today
  (we only set it for waiter orders) so the impact is theoretical. Still
  worth fixing for consistency — the fixes below cover all orders, not
  just waiter ones, because they touch the shared payload builder.
- **`PendingOperationsService` queue.** Each waiter order's `_isSynced=false`
  flag is enough for the periodic sync to pick it up. No pending-op row
  needed for the initial create — the queue is for `UPDATE` / `DELETE`
  after the order has already been pushed once. No bug.
- **Waiter sync UP.** Waiters are server-authoritative — the POS only
  consumes via `_persistWaiters`, never pushes. The new `pin` column
  reads correctly via `Value(waiter['pin'])`. No bug.

---

## Verification

After applying the fixes:

1. **Online cashier creates an order** → row inserted with `isSynced=false`,
   `autoSyncOrder` fires inline, payload includes `source: null`,
   `sessionId: 42`, `sessionCode: 'S-2026-…'`, `takenBy: <cashier_id>`.
   Row flips to `isSynced=true` after server 200.
2. **Online waiter app posts** `/waiters/orders` → row inserted with
   `isSynced=false`, `source='WAITER'`, `sessionId=42`. Background
   `_firePrintsForWaiterOrder` runs, then the new background auto-sync
   call fires. Payload includes all four new fields. Row flips to
   `isSynced=true` within ~1s.
3. **Offline waiter app posts** → row inserted unsynced. Auto-sync attempt
   logs a warning and returns. The periodic sync picks it up when the
   tablet comes back online.
4. **`flutter analyze`** on the two touched files → 0 errors / 0 warnings
   introduced.

---

## Files touched by the fixes

| File | Change |
|---|---|
| `lib/services/data_sync_service.dart` | Pre-load `sessionCode` for the orders' `sessionId` set (mirror the existing customer-phone preload). Add `source`, `sessionId`, `sessionCode`, `takenBy` to both `getOrdersForSync` and `syncSingleOrder` payloads. |
| `lib/services/server_service.dart` | `_waiterCreateOrder` fires `syncManager.autoSyncOrder(orderId)` in the background after the print kick, gated by `lastKnownOnlineStatusProvider`. Imports the network + sync providers. |

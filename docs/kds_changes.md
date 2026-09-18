# KDS Endpoint Changes

LAN-only KDS behaviour served by the embedded Shelf server (`lib/services/server_service.dart`). This documents what changed so the KDS client (and anyone reasoning about sync) can apply/consume it correctly.

**Core principle:** the KDS micro-state machine lives **entirely on the POS over the LAN**. The cloud backend only ever sees the **major/terminal** order state. Kitchen stats are **local**, computed on the POS from stage timestamps — nothing new is pushed to the cloud.

---

## 1. `GET /orders` — scoped to the current session (day-overridable)

**Before:** always returned orders from **start-of-today**.

**Now:** defaults to the **current cash session** (the open shift). Any explicit date param overrides back to a date window.

| Case | Scope |
|---|---|
| No date params | Orders where `sessionId == currentSession.id` |
| No open session (and no date params) | **Empty response** (nothing to cook) |
| `since` / `from_date` given | Orders with `createdAt >= <date>` (day/history override) |
| `to_date` given | Adds upper bound `createdAt <= <date>` |

### Query params (unchanged wire format)

| Param | Meaning |
|---|---|
| `after_id` | Only orders with `id > after_id` (new-order cursor) |
| `status` | Comma-separated states filter; `ONHOLD` is always excluded |
| `station` | Restrict to a station's products (primary `stationId` **or** `product_stations` join) |
| `since` / `from_date` | Lower `createdAt` bound → **switches to date mode** |
| `to_date` | Upper `createdAt` bound → **switches to date mode** |
| `updated_after_log_id` | Incremental log cursor (secondary; always constrained by scope) |

### Response shape (unchanged)

```json
{
  "orders":         [ /* new orders */ ],
  "orders_updated": [ /* changed orders */ ],
  "orders_deleted": [ /* ids */ ],
  "last_log_id":    123,
  "count":          0,
  "updated_count":  0,
  "deleted_count":  0
}
```

**KDS client impact:** none to the request/response contract. The *set of orders* is now the open shift by default. To fetch history (e.g. reprint yesterday), pass `from_date`/`to_date`. Poll the same way; when a shift closes with no new one open, `/orders` returns empty — treat that as "clear the board", not an error.

---

## 2. State updates — micro-states stay local, only terminal states sync

Two endpoints drive KDS state:

- `PUT /orders/products/<id>?status=<STATE>` — one line item's state
- `PUT /orders/<id>` — whole order (fast-status path)

### Terminal states

```
COMPLETED · CANCELED · DELIVERED
```

- **Intermediate states** (`PENDING`, `PREPARING`, `READY`) update the local DB only. They **never** touch `isSynced`, so they never round-trip to the cloud.
- **Terminal states** set `isSynced = false` and trigger an auto-sync push to the backend. This is the *only* KDS-driven cloud write.

When every line item of an order reaches the same state, the parent order's `status` is set to that state (and synced only if terminal).

**KDS client impact:** drive the board through `PENDING → PREPARING → READY → DELIVERED` (or `CANCELED`) freely over the LAN — it's cheap and offline-safe. The backend will only reflect the final outcome.

---

## 3. Stage timestamps on `order_products` (schema v27)
r
Three nullable `DateTime` columns, stamped the **first** time a line item enters each stage (a remake bouncing back to `PREPARING` does **not** overwrite the original):

| Column | Stamped when state first becomes | Used for |
|---|---|---|
| `preparing_at` | `PREPARING` | prep-time start |
| `ready_at` | `READY` | prep-time end / pickup-wait start |
| `served_at` | terminal (`COMPLETED`/`DELIVERED`/`CANCELED`) | pickup-wait end |
p
Stored as **TEXT** (`store_date_time_values_as_text: true`). Migration adds the columns idempotently in `onUpgrade` (`from < 27`).

Derived durations:
- **Prep time** = `ready_at − preparing_at`
- **Pickup wait** = `served_at − ready_at` (served, non-cancelled items only)

---

## 4. Local KDS stats (POS only — no cloud)

Computed on the POS from the stage timestamps, scoped to the current session (matches the `/orders` scoping decision).

- `services/kds_stats_service.dart` → `KdsStatsService.forSession(sessionId)`
- `providers/kds_stats_provider.dart` → `kdsSessionStatsProvider`
- `presentation/widgets/kds_stats_dialog.dart` → `showKdsStatsDialog(context)`
- **Entry point:** Dashboard app-bar insights icon ("Kitchen stats — current shift")

Metrics: avg/median prep time, avg pickup wait, items served, live backlog (fired but not ready), kitchen cancels, throughput per station. Null session → empty stats.

---

## Files touched

| File | Change |
|---|---|
| `lib/data/database/tables/order_product_table.dart` | + `preparingAt` / `readyAt` / `servedAt` |
| `lib/data/database/app_database.dart` | `schemaVersion = 27` + `from < 27` migration |
| `lib/services/server_service.dart` | `_getOrders` session scope; `_updateOrderProduct` / `_updateOrder` terminal-only sync + timestamp stamping; `_isTerminalState` helper |
| `lib/services/kds_stats_service.dart` | new — local stats |
| `lib/providers/kds_stats_provider.dart` | new — stats provider |
| `lib/presentation/widgets/kds_stats_dialog.dart` | new — stats view |
| `lib/presentation/widgets/dashboard_screen.dart` | stats entry point |

**Reminder:** run `flutter pub run build_runner build --delete-conflicting-outputs` after the schema change (already done for v27).

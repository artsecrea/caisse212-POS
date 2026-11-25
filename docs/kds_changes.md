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

---

## 5. Push instead of 2 s polling, and who is connected (2026-11-25)

The KDS no longer has to poll every 2 s. The till nudges it; the KDS then fetches with its own cursors. Everything is additive: an old KDS polls exactly as before, a new KDS against an old till falls back to polling.

### Events

| Endpoint | Purpose |
|---|---|
| `POST /orders/events/ticket` | Behind the password header. → `{ "ticket": "…", "expiresInSeconds": 60 }`. One-time ticket, because a browser's EventSource cannot send headers and the password must not go in a URL (request log). |
| `GET /orders/events?ticket=…&name=…&stations=a,b&version=…` | `text/event-stream`. Authenticated by the password header **or** a ticket (403 otherwise). Events: `connected` (`{name, heartbeatSeconds}`), `orders-changed` (`{seq}`), plus `: hb` comments every 20 s. An old till answers 404 → keep polling. |

`orders-changed` is a **nudge, never data**: each screen has its own stations / filters and fetches its share with its cursors. It is sent when any table the board is built from is written (orders, lines, components, order logs, cancelled lines, sessions, catalogue/stations), throttled to one per 250 ms, and only when a screen is listening. A lost nudge costs nothing: the KDS keeps a 20 s safety poll while live, and goes back to its normal poll interval (2 s) the moment the stream drops.

### "Nothing new" short answer

Every `GET /orders` answer now carries `version` (opaque string). A KDS echoes it as `known_version` on its next **incremental** poll (both `after_id` and `updated_after_log_id` present, same scope). If nothing the board is built from was written since, the till answers the empty response without running the scope queries. The version also rolls over every 30 s, so a write that bypasses drift's change feed (raw SQL) is never hidden longer than that. First fetches and the 30 s reconcile never send it.

### Identity and presence

A KDS sends `X-KDS-Name`, `X-KDS-Stations`, `X-KDS-Version` on every request (same-origin only on web, to avoid CORS preflights against an older till). The till keeps an in-memory registry (`KdsPresenceRegistry`): **Live** (holding the event stream), **Polling** (asked within 45 s), **Offline**. Shown in Devices management (live status per registered KDS by name, plus a "Kitchen screens on this till" panel that also lists unregistered screens).

### Settings lock: till PIN

`POST /kds-api/settings-code { "code": "…" }` → `{ "accepted": bool, "tillPinSet": bool }`. Lets a KDS set to "use the till's PIN" accept the till's own settings PIN or the daily master code without the PIN leaving the till. 5 wrong codes per address per minute → 429.

### Payload additions (KDS feed)

| Where | Key | Meaning |
|---|---|---|
| line | `prepMinutes` | product preparation time (back-office), minutes; absent = not configured |
| line | `doneAt` | when the line was finished (ready, else served); absent while open |
| line | `removedComponents` | paid defaults the customer took off ("NO onion"). **No longer in `components`**, where an old KDS showed them as options to make |
| line | `components` | zero-quantity signal rows are no longer sent |
| order | `courseLines` | every course-tagged line of the order across all stations `{id, courseNo, state, kitchenAt, doneAt}` (courses on only) |
| order | `source`, `waiterName`, `externalOrderCode` | who rang it up |

Linked option lines (`linked=1`) now carry the parent's `kitchenAt` / `preparingAt` / `doneAt`, and a removed linked option no longer creates a line on the other station.

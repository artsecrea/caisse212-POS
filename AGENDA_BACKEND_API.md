# Agenda — Backend API Requirements

This document describes every field, endpoint, and sync behaviour the **Agenda** screen
consumes and produces. Share it with the backend team so they can expose the right
contracts.

---

## 1. Local DB fields used by the Agenda

### `order_products` table

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | int | no | PK |
| `order_id` | int | no | FK → `orders.id` |
| `product_id` | int | no | FK → `products.id` |
| `plan_start_at` | DateTime | **yes** | ISO-8601 scheduled start |
| `plan_end_at` | DateTime | **yes** | ISO-8601 scheduled end |
| `plan_waiter_id` | int | **yes** | FK → `waiters.id` — staff assigned to this booking |
| `state` | String | no | `PENDING` / `PREPARING` / `COMPLETED` / `CANCELED` |
| `note` | String | **yes** | Free-text booking notes |
| `updated_at` | DateTime | no | Last write timestamp (set on every schedule update) |

> The Agenda only shows items where **both** `plan_start_at` and `plan_end_at` are non-null.  
> Items without a schedule are invisible to the Agenda.

### `orders` table (fields referenced)

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | int | no | PK |
| `code` | String | no | Human-readable label shown in cards (e.g. `ORD-001`) |
| `client_id` | int | **yes** | FK → `customers.id` |

### `customers` table (fields referenced)

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | int | no | PK |
| `first_name` | String | no | |
| `last_name` | String | no | |
| `phone` | String | **yes** | Shown in the booking detail dialog |

### `waiters` table (fields referenced)

| Column | Type | Nullable | Description |
|---|---|---|---|
| `id` | int | no | PK |
| `first_name` | String | no | |
| `last_name` | String | **yes** | |

---

## 2. API endpoints required

### 2.1 — List scheduled items for a date range

```
GET /api/order-products/agenda
    ?startDate=YYYY-MM-DD
    &endDate=YYYY-MM-DD
```

Returns `order_products` rows that have `plan_start_at` within **[startDate 00:00, endDate 24:00)**.

**Response shape:**

```json
{
  "data": [
    {
      "id": 12,
      "orderId": 4,
      "productId": 7,
      "planStartAt": "2026-04-28T09:00:00",
      "planEndAt":   "2026-04-28T10:00:00",
      "planWaiterId": 3,
      "state": "PENDING",
      "note": "Prefers quiet room",
      "updatedAt": "2026-04-27T18:33:00",
      "order": {
        "id": 4,
        "code": "ORD-004",
        "clientId": 9
      },
      "product": {
        "id": 7,
        "name": "Massage 60min"
      },
      "customer": {
        "id": 9,
        "firstName": "Aoutmane",
        "lastName": "Azzi",
        "phone": "+213 555 0000"
      },
      "waiter": {
        "id": 3,
        "firstName": "Sarah",
        "lastName": "Connor"
      }
    }
  ]
}
```

> The app fetches one day at a time (`startDate == endDate`).  
> The nested `customer` and `waiter` objects can be `null` when the FK is null.

---

### 2.2 — Reschedule an order-product (drag & drop / edit dialog)

```
PATCH /api/order-products/{id}/schedule
```

**Request body:**

```json
{
  "planStartAt":  "2026-04-28T11:30:00",
  "planEndAt":    "2026-04-28T12:30:00",
  "planWaiterId": 5
}
```

All three fields are optional — send only the ones that changed.  
`planWaiterId: null` explicitly unassigns the waiter.

**Response:** the updated `order_product` object (same shape as one item in §2.1).

**HTTP codes:**

| Code | Meaning |
|---|---|
| `200` | Success |
| `400` | Invalid time range (`planEndAt <= planStartAt`) |
| `404` | Order-product not found |
| `409` | Time conflict with another booking for the same waiter |

---

### 2.3 — List all waiters (column headers)

```
GET /api/waiters
```

Already exists for other POS features — just confirm it returns at minimum:

```json
[
  { "id": 1, "firstName": "Sarah", "lastName": "Connor" }
]
```

---

## 3. State values

| Value | Display colour | Meaning |
|---|---|---|
| `PENDING` | Blue | Scheduled, not yet started |
| `PREPARING` | Orange | Currently in progress |
| `COMPLETED` | Green | Service delivered |
| `CANCELED` | Red | Booking canceled |

The app uses these exact strings — casing matters.

---

## 4. Sync behaviour

The Agenda does **not** call the server directly.  
It reads from the local SQLite database (via Drift) and writes changes there immediately  
(so the UI updates instantly). Backend sync happens through the existing `DataSyncService` /
`PendingOperationsService` pipeline.

### What should be added to the sync pipeline

When a drag-and-drop or edit-dialog save occurs, the app writes:

```dart
OrderProductsCompanion(
  planStartAt: Value(newStart),
  planEndAt:   Value(newEnd),
  planWaiterId: Value(newWaiterId),  // nullable
  updatedAt:   Value(DateTime.now()),
)
```

A pending sync operation should be enqueued with type `UPDATE_ORDER_PRODUCT_SCHEDULE`
and payload:

```json
{
  "id": 12,
  "planStartAt":  "2026-04-28T11:30:00",
  "planEndAt":    "2026-04-28T12:30:00",
  "planWaiterId": 5
}
```

On connectivity restore, `DataSyncService` calls `PATCH /api/order-products/{id}/schedule`
with this payload.

### Pull sync

During the regular `syncAllData()` cycle, the app should pull from `GET /api/order-products/agenda`
for **today ± N days** (configurable, suggested default: today + 7 days) and upsert the results
into the local `order_products` table — updating scheduling columns only when
`api.updatedAt > local.updatedAt` to avoid clobbering local edits not yet pushed.

---

## 5. Conflict resolution

| Scenario | Resolution |
|---|---|
| Local edit not yet synced, server has newer version | **Server wins** on pull — local pending operation is still retried on next push |
| Two devices edit the same booking simultaneously | Last-write-wins based on `updatedAt`; the backend should reject the older write with `409` |
| Waiter conflict (two bookings overlap for same waiter) | Backend validates and returns `409`; app shows a snackbar and reverts the local change |

---

## 6. Quick reference — field name mapping

The Flutter app uses **camelCase** (Dart convention); the DB stores **snake_case**.
The API should accept and return **camelCase** JSON.

| Dart field | DB column | JSON key |
|---|---|---|
| `planStartAt` | `plan_start_at` | `planStartAt` |
| `planEndAt` | `plan_end_at` | `planEndAt` |
| `planWaiterId` | `plan_waiter_id` | `planWaiterId` |
| `orderCode` | `orders.code` | `order.code` |
| `customerPhone` | `customers.phone` | `customer.phone` |
| `note` | `order_products.note` | `note` |


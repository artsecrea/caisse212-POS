# caisse212 POS — Backend Integration Guide

Single entry point for the backend AI agent. It summarises **everything the server
must provide** for the current POS client, and points to the detailed docs:

- [`permissions.md`](./permissions.md) — full permission catalog + DB model
- [`multi_station.md`](./multi_station.md) — multi-station products contract

Everything here is **additive** — old fields keep working; new fields are optional but
unlock the corresponding client features.

---

## 1. `GET /pos/users`

Returns the list of POS users. The client syncs these into its local DB and uses them
for login, permissions, and the Users screen.

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | int | yes | Primary key |
| `username` | string | yes | Unique |
| `password` | string | yes | **bcrypt hash** (client verifies local login with bcrypt) |
| `firstName` | string | yes | |
| `lastName` | string | yes | |
| `type` | string | yes | `admin` \| `cashier` \| `waiter`. `admin` ⇒ all permissions |
| `imageUrl` | string? | no | Avatar |
| `permissions` | string[] **or** CSV string | no | Permission tokens — see §3 |
| `displayName` | string? | no | Optional custom display name (`displayName` or `display_name`) |
| `createdAt` | ISO-8601 string \| epoch ms | no | |
| `updatedAt` | ISO-8601 string \| epoch ms | no | |
| `lastLogin` | ISO-8601 string \| epoch ms \| null | no | Last login (`lastLogin` or `last_login`) — shown in the Users screen |

Example:
```json
{
  "id": 7,
  "username": "ali",
  "password": "$2a$10$....bcryptHash....",
  "firstName": "Ali",
  "lastName": "B.",
  "type": "cashier",
  "imageUrl": null,
  "permissions": ["pos:orders:create","pos:orders:view","pos:orders:item:add","pos:tickets:create","pos:tickets:print","pos:printing"],
  "displayName": "Ali (Caisse 1)",
  "createdAt": "2026-01-04T09:00:00Z",
  "updatedAt": "2026-05-20T12:00:00Z",
  "lastLogin": "2026-05-27T08:15:00Z"
}
```

> The client accepts both camelCase and snake_case for `displayName/createdAt/updatedAt/lastLogin`.
> If `lastLogin` is omitted, the client keeps the locally-recorded login time.

---

## 2. `GET /pos/products`

Existing product fields are unchanged. **One new field** enables multi-station:

| Field | Type | Notes |
|---|---|---|
| `stationId` | int? | **Primary** station (unchanged, keep populating) |
| `stationIds` | int[] | **NEW** — full/extra station set. Omit or `[]` ⇒ single-station (legacy) |

The client treats a product's stations as `{stationId} ∪ stationIds`. See
[`multi_station.md`](./multi_station.md) for the join-table model and KDS/printing behavior.

Other product fields the client reads (all existing): `id, name, barcode, imageUrl,
description, price, uom, categoryId, tvaAmount, discountAmount, finalPrice, color,
isActive, isVariant, isPlannable, planDurationMinutes, mbwCode, pricePerKg`.

---

## 3. Permissions

The client gates every action on string tokens like `pos:orders:item:remove`. Return the
user's tokens in the `permissions` field (§1). Highlights:

- Wildcards: `pos:*` (everything), `pos:<resource>:*` (all actions of a resource).
- `type: "admin"` bypasses all checks.
- **Order item-level anti-fraud split**: `pos:orders:item:add` (cashier) is separate from
  `pos:orders:item:remove` and `pos:orders:item:modify` (manager-only) so a cashier can't
  remove items / reduce quantities on a saved order to skim cash. **Cancel** has its own
  `pos:orders:cancel` (manager) since cancelling can also hide a sale. Status/transfer
  remain under `pos:orders:update`.

**Full token list, DB schema (`permissions` + `user_permissions`), SQL seed, and example
roles are in [`permissions.md`](./permissions.md)** — that file is the source of truth for
permissions; seed it as-is.

> **Enforce permissions server-side too.** The client gate is UI-level; the order-update,
> ticket, and session endpoints must independently check the caller's permissions
> (especially `pos:orders:item:remove` / `item:modify`).

---

## 4. Suggested new backend tables

```
-- multi-station products (extra stations beyond products.station_id)
product_stations(
  product_id  FK -> products.id,
  station_id  FK -> stations.id,
  PRIMARY KEY (product_id, station_id)
)

-- permissions catalog + per-user grants (see permissions.md for full seed)
permissions(id PK, token UNIQUE, resource, action, label)
user_permissions(user_id FK, permission_id FK, PRIMARY KEY(user_id, permission_id))
-- optional: roles + role_permissions for bundled grants
```

---

## 5. Client-only features (no backend work needed)

These were added on the client and **do not require any backend support** — listed so the
backend agent knows not to build for them:

- **Activity / audit log** — user actions (orders, payments, login/logout, sessions) are
  recorded to the local DB in a chosen "logging language", shown in a Logs screen, and
  rolled to a Desktop text file after 30 days. Purely local.
- **Master password** — a support master key equal to the current date `YYYYMMDD` that
  also passes the local tenant-password prompt. Purely local.
- **Tenant password** — set/stored locally (bcrypt) on the device.

---

## 6. Endpoints touched (summary)

| Endpoint | Change |
|---|---|
| `GET /pos/users` | Add `permissions`, `lastLogin`, `displayName` (and `createdAt`/`updatedAt`) |
| `GET /pos/products` | Add `stationIds` array |
| (all mutating endpoints) | Enforce the permission tokens server-side |

No other endpoints change. `GET /pos/stations` is already consumed as-is.

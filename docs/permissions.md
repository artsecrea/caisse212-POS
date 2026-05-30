# caisse212 POS — Permissions Reference (for backend implementation)

This document lists every permission the POS client checks, how the permission
model works, and a suggested backend data model. Give this to the backend so the
server can store per-user permissions and return them on `/pos/users`.

---

## 1. Permission model

- A permission is a **string token** in the form `pos:<resource>:<action>` (a few are
  two-segment, e.g. `pos:printing`).
- A user has a **set** of permission tokens. The client currently receives them on the
  user object from `GET /pos/users` (field `permissions`).
- **Accepted formats** for the `permissions` field (the client normalizes all of them):
  - a JSON array: `["pos:orders:view","pos:tickets:create"]`
  - a comma-separated string: `"pos:orders:view,pos:tickets:create"`
- **Wildcards** (the client expands these):
  - `pos:*` → grants **every** permission.
  - `pos:<resource>:*` → grants all actions under that resource (e.g. `pos:orders:*`
    grants create/view/update/delete on orders).
- **Admin bypass**: a user whose `type` is `admin` is granted everything regardless of
  the `permissions` field. (User `type` values seen in the client: `admin`, `cashier`,
  `waiter`.)
- **Deny by default**: if a user lacks a token (and isn't admin / wildcard), the action
  is hidden/disabled in the UI and blocked.

> The client enforcement is UI-level. The backend should **also** enforce these on its
> own endpoints — never trust the client alone.

---

## 2. Full permission list

Grouped by resource. "Gates" = what the action unlocks in the POS.

### Orders
| Token | Gates |
|---|---|
| `pos:orders:view` | Open the Orders management screen |
| `pos:orders:create` | Save a new order (the "Proceed" action) |
| `pos:orders:item:add` | **Add** an item to an already-**saved** order (normal cashier work) |
| `pos:orders:item:remove` | **Remove** an item from a saved order ⚠️ *anti-fraud: gate to managers* |
| `pos:orders:item:modify` | Change an item's **quantity** / components / discount / note on a saved order ⚠️ *anti-fraud: quantity-down is a skim vector* |
| `pos:orders:update` | General/lifecycle edits on a saved order: change **status**, **confirm**, **transfer to another table**, and persisting edits |
| `pos:orders:cancel` | **Cancel** an order (status → CANCELED) ⚠️ *anti-fraud: cancelling can hide a sale — gate to managers* |
| `pos:orders:delete` | Delete an order |

> **Why item-level split:** with a single `pos:orders:update`, a cashier who can add
> items could also *remove* an item (or reduce its quantity) from a saved, unpaid order
> after collecting cash — skimming the difference. Splitting `item:add` (cashier) from
> `item:remove` / `item:modify` (manager) closes that.
>
> **Editing rules (client):** item edits are unrestricted on a brand-new unsaved cart;
> the permissions above are enforced only once an order is **saved** (has an id). A
> typical cashier gets `pos:orders:item:add` but **not** `item:remove` / `item:modify`.
> Status/cancel/transfer remain under `pos:orders:update`.

### Tickets (payments / receipts)
| Token | Gates |
|---|---|
| `pos:tickets:view` | Open the Tickets management screen |
| `pos:tickets:create` | Take payment (creating a ticket) |
| `pos:tickets:update` | Edit a ticket |
| `pos:tickets:print` | Print / reprint / batch-reprint tickets |
| `pos:tickets:delete` | Delete a ticket (or a paid line item) |

### Sessions (cash register sessions)
| Token | Gates |
|---|---|
| `pos:sessions:view` | Open the Sessions management screen |
| `pos:sessions:start` | Open a cash session |
| `pos:sessions:pause` | Pause a session |
| `pos:sessions:end` | Close a session |
| `pos:sessions:delete` | Delete a session |

### Customers
| Token | Gates |
|---|---|
| `pos:customer:view` | View customers |
| `pos:customer:set` | Attach a customer to an order |
| `pos:customer:create` | Create a customer |
| `pos:customer:delete` | Delete a customer |

### Commercials (sales reps)
| Token | Gates |
|---|---|
| `pos:commercial:view` | View commercials |
| `pos:commercial:set` | Attach a commercial to an order |
| `pos:commercial:create` | Create a commercial |

### Waiters
| Token | Gates |
|---|---|
| `pos:waiter:view` | View waiters |
| `pos:waiter:set` | Assign a waiter to an order/table |
| `pos:waiter:create` | Create a waiter |
| `pos:waiter:delete` | Delete a waiter |

### Tables
| Token | Gates |
|---|---|
| `pos:tables:set` | Select / assign / transfer a table |
| `pos:tables:clear` | Clear a table |

### Products
| Token | Gates |
|---|---|
| `pos:products:view` | View products |
| `pos:products:modify` | Modify products (incl. station assignment, prices) |

### Devices (KDS / kiosks / printers)
| Token | Gates |
|---|---|
| `pos:devices:view` | Open the Devices management screen |
| `pos:devices:use` | Use a device |
| `pos:devices:update` | Add/edit a device or station |
| `pos:devices:delete` | Delete a device |

### Users
| Token | Gates |
|---|---|
| `pos:users:view` | Open the Users management screen |
| `pos:users:create` | Create a user |
| `pos:users:update` | Edit a user / their permissions |
| `pos:users:delete` | Delete a user |

### Notes
| Token | Gates |
|---|---|
| `pos:notes:view` | Open the Notes screen |
| `pos:notes:create` | Create a note |
| `pos:notes:update` | Edit a note |
| `pos:notes:delete` | Delete a note / clear all |

### Agenda / Planning
| Token | Gates |
|---|---|
| `pos:agenda:view` | Open the Agenda/planning screen |
| `pos:agenda:manage` | Manage planning entries |

### Activity logs
| Token | Gates |
|---|---|
| `pos:logs:view` | Open the Activity Logs screen + export |

### Reports / Dashboard
| Token | Gates |
|---|---|
| `pos:reports:view` | Open the Dashboard + daily-summary report |

### Settings
| Token | Gates |
|---|---|
| `pos:settings:view` | Open Settings |
| `pos:settings:update` | Change settings |

### Sync operations
| Token | Gates |
|---|---|
| `pos:sync:orders` | Sync orders |
| `pos:sync:tickets` | Sync tickets |
| `pos:sync:sessions` | Sync sessions |
| `pos:sync:customers` | Sync customers |
| `pos:sync:all` | Sync everything |
| `pos:sync:viewPending` | View the pending-operations queue |
| `pos:sync:managePending` | Manage (retry/discard) pending operations |

### Other
| Token | Gates |
|---|---|
| `pos:manualDiscount` | Apply a manual discount on an order |
| `pos:printing` | Use the print button on the POS |

### Wildcard
| Token | Gates |
|---|---|
| `pos:*` | All permissions (typically only for admins/owners) |

---

## 3. Suggested backend data model

A normalized model the backend can use:

```
permissions(
  id            PK,
  token         TEXT UNIQUE,   -- e.g. 'pos:orders:create'
  resource      TEXT,          -- e.g. 'orders'
  action        TEXT,          -- e.g. 'create'
  label         TEXT           -- human description (the "Gates" text above)
)

user_permissions(
  user_id       FK -> users.id,
  permission_id FK -> permissions.id,
  PRIMARY KEY (user_id, permission_id)
)
```

Optionally add a `roles` layer (`roles`, `role_permissions`, `users.role_id`) so an
admin can assign a role (e.g. *Cashier*, *Manager*) that bundles tokens, plus
per-user overrides.

**On `GET /pos/users`**, return each user's effective tokens, e.g.:

```json
{
  "id": 7,
  "username": "ali",
  "type": "cashier",
  "permissions": ["pos:orders:view", "pos:orders:create", "pos:tickets:create", "pos:tickets:print"]
}
```

(Array or comma-separated string both work. Use `["pos:*"]` for full access, or set
`type: "admin"`.)

---

## 4. Seed suggestion (example roles)

- **Admin / Owner** → `["pos:*"]` (or `type: admin`).
- **Manager** → all of orders/tickets/sessions/customers/reports/logs + `pos:manualDiscount`,
  `pos:printing`, `pos:tables:*`, `pos:waiter:*`, `pos:commercial:*`. Includes the
  manager-only, anti-fraud order actions: `pos:orders:item:remove`, `pos:orders:item:modify`,
  `pos:orders:cancel`, `pos:orders:delete`.
- **Cashier** → `pos:orders:create`, `pos:orders:view`, `pos:orders:item:add`,
  `pos:tickets:create`, `pos:tickets:print`, `pos:tickets:view`, `pos:tables:set`,
  `pos:customer:set`, `pos:printing`, `pos:sessions:start`, `pos:sessions:end`.
  **Deliberately NOT** `pos:orders:item:remove` / `pos:orders:item:modify` / `pos:orders:update`
  — so a cashier can add items but cannot remove items or reduce quantities on a saved order.
- **Waiter** → `pos:orders:create`, `pos:orders:view`, `pos:orders:item:add`,
  `pos:tables:set`, `pos:waiter:set`, `pos:customer:set`.

These are starting points — adjust to the business.

---

## 5. Complete flat token list (for DB seeding)

All 54 permission tokens the client recognises (excluding the `pos:*` wildcard, which
is a grant shortcut rather than a stored permission):

```
pos:manualDiscount
pos:printing
pos:orders:view
pos:orders:create
pos:orders:update
pos:orders:delete
pos:orders:cancel
pos:orders:item:add
pos:orders:item:remove
pos:orders:item:modify
pos:tickets:view
pos:tickets:create
pos:tickets:update
pos:tickets:print
pos:tickets:delete
pos:sessions:view
pos:sessions:start
pos:sessions:pause
pos:sessions:end
pos:sessions:delete
pos:customer:view
pos:customer:set
pos:customer:create
pos:customer:delete
pos:commercial:view
pos:commercial:set
pos:commercial:create
pos:waiter:view
pos:waiter:set
pos:waiter:create
pos:waiter:delete
pos:tables:set
pos:tables:clear
pos:products:view
pos:products:modify
pos:devices:view
pos:devices:use
pos:devices:update
pos:devices:delete
pos:users:view
pos:users:create
pos:users:update
pos:users:delete
pos:notes:view
pos:notes:create
pos:notes:update
pos:notes:delete
pos:agenda:view
pos:agenda:manage
pos:logs:view
pos:reports:view
pos:settings:view
pos:settings:update
pos:sync:orders
pos:sync:tickets
pos:sync:sessions
pos:sync:customers
pos:sync:all
pos:sync:viewPending
pos:sync:managePending
```

> `pos:*` and `pos:<resource>:*` are **wildcard grants** the client expands at
> check-time. You generally don't store them as catalog rows — either assign the
> literal `pos:*` string to an owner/admin, or rely on `type: "admin"`.

### Example SQL seed

```sql
INSERT INTO permissions (token, resource, action) VALUES
  ('pos:manualDiscount', 'misc',       'manualDiscount'),
  ('pos:printing',       'misc',       'printing'),
  ('pos:orders:view',    'orders',     'view'),
  ('pos:orders:create',  'orders',     'create'),
  ('pos:orders:update',  'orders',     'update'),
  ('pos:orders:delete',  'orders',     'delete'),
  ('pos:orders:cancel',      'orders', 'cancel'),
  ('pos:orders:item:add',    'orders', 'item:add'),
  ('pos:orders:item:remove', 'orders', 'item:remove'),
  ('pos:orders:item:modify', 'orders', 'item:modify'),
  ('pos:tickets:view',   'tickets',    'view'),
  ('pos:tickets:create', 'tickets',    'create'),
  ('pos:tickets:update', 'tickets',    'update'),
  ('pos:tickets:print',  'tickets',    'print'),
  ('pos:tickets:delete', 'tickets',    'delete'),
  ('pos:sessions:view',  'sessions',   'view'),
  ('pos:sessions:start', 'sessions',   'start'),
  ('pos:sessions:pause', 'sessions',   'pause'),
  ('pos:sessions:end',   'sessions',   'end'),
  ('pos:sessions:delete','sessions',   'delete'),
  ('pos:customer:view',  'customer',   'view'),
  ('pos:customer:set',   'customer',   'set'),
  ('pos:customer:create','customer',   'create'),
  ('pos:customer:delete','customer',   'delete'),
  ('pos:commercial:view',  'commercial','view'),
  ('pos:commercial:set',   'commercial','set'),
  ('pos:commercial:create','commercial','create'),
  ('pos:waiter:view',    'waiter',     'view'),
  ('pos:waiter:set',     'waiter',     'set'),
  ('pos:waiter:create',  'waiter',     'create'),
  ('pos:waiter:delete',  'waiter',     'delete'),
  ('pos:tables:set',     'tables',     'set'),
  ('pos:tables:clear',   'tables',     'clear'),
  ('pos:products:view',  'products',   'view'),
  ('pos:products:modify','products',   'modify'),
  ('pos:devices:view',   'devices',    'view'),
  ('pos:devices:use',    'devices',    'use'),
  ('pos:devices:update', 'devices',    'update'),
  ('pos:devices:delete', 'devices',    'delete'),
  ('pos:users:view',     'users',      'view'),
  ('pos:users:create',   'users',      'create'),
  ('pos:users:update',   'users',      'update'),
  ('pos:users:delete',   'users',      'delete'),
  ('pos:notes:view',     'notes',      'view'),
  ('pos:notes:create',   'notes',      'create'),
  ('pos:notes:update',   'notes',      'update'),
  ('pos:notes:delete',   'notes',      'delete'),
  ('pos:agenda:view',    'agenda',     'view'),
  ('pos:agenda:manage',  'agenda',     'manage'),
  ('pos:logs:view',      'logs',       'view'),
  ('pos:reports:view',   'reports',    'view'),
  ('pos:settings:view',  'settings',   'view'),
  ('pos:settings:update','settings',   'update'),
  ('pos:sync:orders',    'sync',       'orders'),
  ('pos:sync:tickets',   'sync',       'tickets'),
  ('pos:sync:sessions',  'sync',       'sessions'),
  ('pos:sync:customers', 'sync',       'customers'),
  ('pos:sync:all',       'sync',       'all'),
  ('pos:sync:viewPending','sync',      'viewPending'),
  ('pos:sync:managePending','sync',    'managePending');
```

# caisse212 POS — Customer Sync (backend contract)

> **Status: required to consume client v1.0.x+ after schema v16**
>
> The POS client moved its customer identity model from "autoincrement id +
> nullable phone" to "phone-keyed, names optional". This doc lists every
> backend change needed to stay compatible.

---

## 1. What changed on the client

| Field | Before | After |
|---|---|---|
| `firstName` | required (`text NOT NULL`) | **optional** (`text NOT NULL DEFAULT ''`) — empty string allowed |
| `lastName` | required | **optional** — empty string allowed |
| `phone` | optional / nullable | **required for new rows**; UI validates non-empty + ≥ 8 digits |
| `phone_normalized` | did not exist | **NEW** — canonical form, used as dedup key |
| Primary identifier | numeric `id` | numeric `id` *for FKs* + **`phone_normalized` for dedup** |
| Local index | none | `UNIQUE` partial index on `phone_normalized` where not null |

Schema migration **v15 → v16** runs on every device:

```sql
ALTER TABLE customers ADD COLUMN phone_normalized TEXT;

-- Best-effort backfill: strip non-digits, peel leading 0, prefix "212".
UPDATE customers SET phone_normalized = …;

CREATE UNIQUE INDEX IF NOT EXISTS idx_customers_phone_normalized
  ON customers(phone_normalized)
  WHERE phone_normalized IS NOT NULL;
```

The client now writes `phone_normalized` on every create/update; old rows
with `NULL` phone keep `NULL` and stay anonymous until they're edited.

### Normalization rule (must match server-side)

```
strip everything that isn't a digit
if string starts with "00<cc>"  → drop "00<cc>"
else if starts with "<cc>"      → drop "<cc>"
if starts with "0"              → drop "0"
prefix "<cc>"
```

Default `<cc>` = `"212"` (Morocco). The same algorithm must run server-side
so client- and server-computed `phone_normalized` agree byte-for-byte.

Examples:

| Raw input | `phone_normalized` |
|---|---|
| `+212 600 000 000` | `212600000000` |
| `0600000000` | `212600000000` |
| `00212600000000` | `212600000000` |
| `06 00 00 00 00` | `212600000000` |
| empty / null | `null` (no dedup possible) |

---

## 2. `POST /pos/customers/bulk` — new payload field

The client now sends `phoneNormalized` alongside `phone` for every customer
in the bulk POST. Existing fields are unchanged.

```json
POST /pos/customers/bulk
{
  "customers": [
    {
      "id":              7,
      "firstName":       "Ali",
      "lastName":        "",
      "phone":           "0600000000",
      "phoneNormalized": "212600000000",
      "email":           null,
      "createdAt":       "2026-06-02T10:30:00Z"
    },
    {
      "id":              8,
      "firstName":       "",
      "lastName":        "",
      "phone":           "0600000001",
      "phoneNormalized": "212600000001",
      "email":           null,
      "createdAt":       "2026-06-02T10:31:00Z"
    }
  ]
}
```

Notes:

- `firstName` / `lastName` may be **empty strings** — treat them as "no name
  given"; do not reject.
- `phoneNormalized` is **almost always** present. It will be `null` only for
  legacy rows that pre-dated the change and were never touched. New rows
  created in the UI always have a phone + `phoneNormalized`.

### Required server-side behaviour

For each incoming customer:

1. If `phoneNormalized` is non-empty:
   - `INSERT … ON CONFLICT (tenant_id, phone_normalized) DO UPDATE`
     setting `first_name`, `last_name`, `phone`, `email`, `updated_at`.
   - The server **keeps its own canonical `id`** for that row.
2. If `phoneNormalized` is null/empty:
   - Insert as a new anonymous customer with a server-generated id.

### Required response

Return an array of mappings so the client can reconcile its local id with
the server's canonical id:

```json
HTTP 200 OK
{
  "mappings": [
    { "localId": 7, "serverId": 7,  "phoneNormalized": "212600000000" },
    { "localId": 8, "serverId": 42, "phoneNormalized": "212600000001" }
  ]
}
```

- `localId` echoes the `id` the client sent.
- `serverId` is the row's canonical id post-upsert.
- If `serverId != localId`, the **client will renumber** its local row and
  cascade-update every `orders.client_id` that referenced the old id, in a
  single transaction.

> Today's client doesn't yet perform the reconciliation — it assumes
> `localId == serverId`. **Implement and return the mappings now** so the
> client can adopt the reconciliation step in the next release without you
> breaking the contract.

---

## 3. `GET /pos/customers` — extended response

Add `phoneNormalized` (also accepted as snake_case `phone_normalized`) so a
freshly-installed terminal can sync customers without re-deriving the
normalisation locally.

```json
[
  {
    "id":              42,
    "firstName":       "Ali",
    "lastName":        "",
    "phone":           "0600000001",
    "phoneNormalized": "212600000001",
    "email":           null,
    "createdAt":       "2026-04-12T08:00:00Z",
    "updatedAt":       "2026-06-02T10:31:00Z"
  }
]
```

The client tolerates either spelling and falls back to a local
normalisation if neither is sent.

---

## 4. Backend storage (recommended)

```sql
ALTER TABLE customers
  ALTER COLUMN first_name  DROP NOT NULL,    -- or set DEFAULT ''
  ALTER COLUMN last_name   DROP NOT NULL,
  ADD COLUMN phone_normalized VARCHAR(32);

UPDATE customers
   SET phone_normalized = <run the normalisation algorithm>
 WHERE phone IS NOT NULL;

CREATE UNIQUE INDEX uniq_customers_tenant_phone
  ON customers(tenant_id, phone_normalized)
  WHERE phone_normalized IS NOT NULL;

CREATE INDEX idx_customers_tenant_phone
  ON customers(tenant_id, phone_normalized);
```

Notes:

- The unique constraint is **partial** so anonymous customers (no phone)
  never collide.
- Always scope the dedup by **tenant_id** — two unrelated tenants may legit
  share the same number.
- Anonymous customers will accumulate over time (one row per "walk-in"
  order). Consider a quarterly cleanup job that prunes anonymous customers
  not referenced by any order.

---

## 5. Validation summary

| Field | Required? | Validation |
|---|---|---|
| `firstName` | no | None — accept empty string |
| `lastName` | no | None — accept empty string |
| `phone` | **yes for new rows** | non-empty when `phoneNormalized` is non-null; raw form is what the cashier typed |
| `phoneNormalized` | yes (when phone is present) | matches the normalisation algorithm; the dedup key |
| `email` | no | RFC-light regex, optional |

When migrating existing data, customers without a phone can stay as-is
(both `phone` and `phoneNormalized` null) but **cannot be deduped** —
they're anonymous one-offs.

---

## 6. Orders unchanged

`orders.client_id` still references `customers.id`. No payload change on the
orders side — the foreign-key resolution is exactly what it was. The only
adjustment, eventually, is that the client will renumber its local
`client_id` if your bulk-POST response says the canonical server id is
different.

---

## 7. Endpoint summary

| Method | URL | Change |
|---|---|---|
| `POST` | `/pos/customers/bulk` | Accept `phoneNormalized`; upsert by `(tenant_id, phone_normalized)`; return `mappings` array |
| `GET` | `/pos/customers` | Return `phoneNormalized` (or `phone_normalized`) per customer |
| `POST/PUT` | `/pos/orders/*` | No change |

---

## 8. Migration order (server)

1. Add the column `phone_normalized` (nullable).
2. Backfill from existing `phone` values using the normalisation algorithm.
3. Add the partial unique index.
4. Deploy the new `POST /pos/customers/bulk` handler that upserts by
   `(tenant_id, phone_normalized)` and returns `mappings`.
5. Deploy the new `GET /pos/customers` that includes `phoneNormalized`.
6. Roll out the matching client release. Old clients that don't yet send
   `phoneNormalized` still work — the server is free to compute it from
   the `phone` field server-side as a fallback.

---

## 9. TL;DR for the backend team

> Customers are now keyed by **`(tenant_id, phone_normalized)`**, not by the
> client's local autoincrement `id`. Add the column, add the partial unique
> index, add the upsert in `/pos/customers/bulk`, return `{mappings: [...]}`
> so the POS can renumber its rows. Names are now optional — let empty
> strings through.

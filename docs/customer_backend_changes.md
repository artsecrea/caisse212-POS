# caisse212 — Customer Sync: Backend Changes

**Audience:** backend dev.
**Goal:** dedup customers by phone across all POS terminals while keeping name fields optional.
**Client version that requires this:** `1.0.x` after schema v16 (already in production).
**Backward compatibility:** the new client tolerates old backends. The old client tolerates new backends. **Nothing breaks during the rollout.** You can deploy these changes anytime.

---

## 1. Schema migration

```sql
-- 1a. Relax name columns (or default them to '')
ALTER TABLE customers ALTER COLUMN first_name DROP NOT NULL;
ALTER TABLE customers ALTER COLUMN last_name  DROP NOT NULL;
-- (or, on MySQL/older Postgres: ALTER COLUMN first_name SET DEFAULT '')

-- 1b. Add the dedup-key column
ALTER TABLE customers ADD COLUMN phone_normalized VARCHAR(32);

-- 1c. Backfill it from existing phone values (run the algorithm in §2 below)
UPDATE customers
   SET phone_normalized = <normalize(phone)>
 WHERE phone IS NOT NULL AND phone <> '';

-- 1d. Partial unique index, scoped per tenant
CREATE UNIQUE INDEX uniq_customers_tenant_phone
    ON customers(tenant_id, phone_normalized)
    WHERE phone_normalized IS NOT NULL;

-- 1e. Plain index too, for fast lookups when the unique check isn't hit
CREATE INDEX idx_customers_tenant_phone
    ON customers(tenant_id, phone_normalized);
```

> The index is **partial** — anonymous customers (no phone) never collide on the unique constraint. The unique scope is **`(tenant_id, phone_normalized)`** because two tenants may legitimately share the same phone.

---

## 2. Phone-normalization algorithm

**Server- and client-side normalisation must produce identical output**, byte-for-byte, or dedup will miss matches.

```
fn normalize(raw: string, country_code: string = "212") -> string|null:
    if raw is empty:
        return null
    digits = strip every character that isn't 0-9 from raw
    if digits is empty:
        return null

    if digits starts with "00" + country_code:
        digits = digits.substring(2 + len(country_code))
    else if digits starts with country_code:
        digits = digits.substring(len(country_code))

    if digits starts with "0":
        digits = digits.substring(1)

    return country_code + digits
```

### Reference test cases (cc = "212")

| Input | Output |
|---|---|
| `"+212 600 000 000"` | `"212600000000"` |
| `"0600000000"` | `"212600000000"` |
| `"00212600000000"` | `"212600000000"` |
| `"06-00-00-00-00"` | `"212600000000"` |
| `"(0600) 00.00.00"` | `"212600000000"` |
| `""` / `null` / `"   "` / `"abc"` | `null` |

Mirror these as test cases on your side.

---

## 3. `POST /pos/customers/bulk` — handler changes

### Incoming payload

The new client sends `phoneNormalized` per row. **Old clients may omit it** — compute it server-side as a fallback.

```json
POST /pos/customers/bulk
{
  "customers": [
    {
      "id": 7,
      "firstName": "Ali",
      "lastName": "",
      "phone": "0600000000",
      "phoneNormalized": "212600000000",
      "email": null,
      "createdAt": "2026-06-02T10:30:00Z"
    }
  ]
}
```

### Server-side rule per row

```
for each incoming customer c:
    norm = c.phoneNormalized
    if norm is null or empty:
        norm = normalize(c.phone)          # fallback for old clients

    if norm is not null:
        upsert by (tenant_id, norm):
            update first_name, last_name, phone, email, updated_at
        canonical_id = the row's id
    else:
        insert anonymous customer with a fresh server-generated id
        canonical_id = the new server id

    push { localId: c.id, serverId: canonical_id, phoneNormalized: norm }
        to the mappings array
```

Empty `firstName` / `lastName` strings are **valid**. Don't reject them.

### Response

Return the mapping array. Even when `localId == serverId`, include the entry — keeps the format consistent.

```json
HTTP 200 OK
{
  "mappings": [
    { "localId": 7, "serverId": 7,  "phoneNormalized": "212600000000" },
    { "localId": 8, "serverId": 42, "phoneNormalized": "212600000001" }
  ]
}
```

The new client already parses this and renumbers the local row + cascades to every `orders.client_id` in a transaction. Old clients ignore the body — no compatibility risk.

---

## 4. `GET /pos/customers` — response addition

Add `phoneNormalized` (snake_case `phone_normalized` also accepted) to each customer in the response. Empty/legacy rows may have `null`.

```json
HTTP 200 OK
[
  {
    "id": 42,
    "firstName": "Ali",
    "lastName": "",
    "phone": "0600000001",
    "phoneNormalized": "212600000001",
    "email": null,
    "createdAt": "2026-04-12T08:00:00Z",
    "updatedAt": "2026-06-02T10:31:00Z"
  }
]
```

Old client ignores the new field. New client uses it as-is (skips its local renormalisation).

---

## 5. Other endpoints

| Endpoint | Change |
|---|---|
| `POST /pos/customers/bulk` | New `phoneNormalized` field accepted; upsert by `(tenant_id, phone_normalized)`; return `{mappings:[...]}` |
| `GET  /pos/customers` | Add `phoneNormalized` (or `phone_normalized`) to each row |
| `POST/PUT /pos/orders/*` | **No change** — `clientId` still references `customers.id` |
| Everything else | **No change** |

---

## 6. Validation summary

| Field | Required? | Validation |
|---|---|---|
| `firstName` | no | accept empty string |
| `lastName` | no | accept empty string |
| `phone` | yes for new rows (client enforces non-empty + ≥ 8 digits) | accept as-is server-side; trust client validation |
| `phoneNormalized` | yes when `phone` is present | compute it yourself if the client didn't send it |
| `email` | no | RFC-light regex; optional |

---

## 7. Operational notes

- **Anonymous customers will accumulate.** A walk-in pays cash with no phone → one row per order over time. Consider a quarterly job that prunes anonymous customers with no order references.
- **Tenant isolation is critical.** Two unrelated tenants may share the same phone. Always include `tenant_id` in the dedup key, the index, and every query.
- **Existing duplicates may block the unique index creation.** Run a dedup pass first: find rows with matching `(tenant_id, phone_normalized)`, merge their orders' `client_id` to the oldest row, then create the index.

---

## 8. Deploy order (no client coordination required)

1. Add `phone_normalized` column (nullable).
2. Backfill from existing `phone` values using the algorithm in §2.
3. (If duplicates surface) dedup before creating the unique index.
4. Add the partial unique index.
5. Deploy the new `/pos/customers/bulk` handler (accept the new field, upsert by phone, return `mappings`).
6. Deploy the new `/pos/customers` response shape (include `phoneNormalized`).

Once 1–6 are live, dedup activates automatically on every client running the new build — no coordinated client release needed. The client has been future-proofed to parse the `mappings` response on its own.

---

## 9. Test matrix the backend should pass

| # | Scenario | Expected |
|---|---|---|
| 1 | New client posts `{id:7, phone:"0600000000", phoneNormalized:"212600000000"}`; server has no matching row | Insert; return `{mappings:[{localId:7, serverId:7, phoneNormalized:"212600000000"}]}` |
| 2 | New client posts the same `phoneNormalized`; server already has it under id 42 | Update first/last/email/phone/updated_at; return `{mappings:[{localId:7, serverId:42, ...}]}` |
| 3 | Old client posts `{id:7, phone:"+212 600 000 000"}` (no `phoneNormalized`) | Server normalises and upserts the same as #2 |
| 4 | New client posts `{phoneNormalized: null}` (anonymous walk-in) | Insert fresh row; return `{mappings:[{localId:8, serverId:<new>, phoneNormalized:null}]}` |
| 5 | Two tenants A and B both send `phoneNormalized:"212600000000"` | Two distinct rows, one per tenant (no collision) |
| 6 | New client posts `{firstName:"", lastName:""}` with a valid phone | Accept; the row is keyed off the phone |
| 7 | Old client (no mapping awareness) posts → ignores response body | Server still returns `mappings` (idempotent for the server) |

---

## 10. TL;DR

> **Add `phone_normalized` to `customers`. Upsert by `(tenant_id, phone_normalized)` in `POST /pos/customers/bulk`. Return `{mappings:[{localId, serverId, phoneNormalized}]}`. Include `phoneNormalized` in `GET /pos/customers`. Names are now optional — accept empty strings.**

That's the entire change set. Rolls out independently of the client. No coordinated release needed.
